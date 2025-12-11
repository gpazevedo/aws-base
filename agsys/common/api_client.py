"""API client for inter-service communication with automatic API key injection."""

import os
from typing import Any, Optional

import boto3
import httpx
from botocore.exceptions import ClientError


class ServiceAPIClient:
    """
    HTTP client for inter-service communication with automatic API key management.

    Features:
    - Automatic API key retrieval from AWS Secrets Manager
    - Caching of API keys to minimize Secrets Manager calls
    - Automatic injection of x-api-key header
    - Built on httpx for async/sync support

    Usage:
        # Initialize with service name
        client = ServiceAPIClient(service_name="api")

        # Make authenticated requests to other services
        response = await client.get("https://api-gateway/runner/health")
        response = await client.post("https://api-gateway/s3vector/embeddings/generate",
                                     json={"text": "hello"})
    """

    def __init__(
        self,
        service_name: str,
        project_name: str | None = None,
        environment: str | None = None,
        base_url: str | None = None,
        timeout: float = 30.0,
        cache_api_key: bool = True,
    ):
        """
        Initialize the service API client.

        Args:
            service_name: Name of this service (e.g., "api", "runner", "s3vector")
            project_name: Project name (defaults to PROJECT_NAME env var)
            environment: Environment (defaults to ENVIRONMENT env var)
            base_url: Base URL for API Gateway (defaults to API_GATEWAY_URL env var)
            timeout: Request timeout in seconds
            cache_api_key: Whether to cache the API key (recommended for Lambda warm starts)

        Raises:
            ValueError: If project_name or environment are not provided and env vars not set
        """
        self.service_name = service_name
        self.project_name = project_name or os.getenv("PROJECT_NAME")
        self.environment = environment or os.getenv("ENVIRONMENT")
        self.base_url = base_url or os.getenv("API_GATEWAY_URL", "")
        self.timeout = timeout
        self.cache_api_key = cache_api_key

        # Validate required configuration
        if not self.project_name:
            raise ValueError(
                "project_name must be provided or set via PROJECT_NAME environment variable"
            )
        if not self.environment:
            raise ValueError(
                "environment must be provided or set via ENVIRONMENT environment variable"
            )

        # Cached API key (set to None to force refresh)
        self._cached_api_key: Optional[str] = None

        # HTTP client (async)
        self._async_client: Optional[httpx.AsyncClient] = None

        # Secrets Manager client (lazy loaded)
        self._secrets_client: Optional[Any] = None

    @property
    def secrets_client(self) -> Any:
        """Lazy load Secrets Manager client."""
        if self._secrets_client is None:
            self._secrets_client = boto3.client("secretsmanager")
        return self._secrets_client

    def get_api_key(self) -> str:
        """
        Retrieve API key from AWS Secrets Manager.

        The API key is stored at: {project_name}/{environment}/{service_name}/api-key

        Returns:
            API key value

        Raises:
            RuntimeError: If API key cannot be retrieved
        """
        # Return cached key if available
        if self.cache_api_key and self._cached_api_key:
            return self._cached_api_key

        secret_name = f"{self.project_name}/{self.environment}/{self.service_name}/api-key"

        try:
            response = self.secrets_client.get_secret_value(SecretId=secret_name)
            if response is None or "SecretString" not in response:
                raise RuntimeError(f"Invalid response from Secrets Manager for {secret_name}")

            api_key = response["SecretString"]

            # Cache the key if caching is enabled
            if self.cache_api_key:
                self._cached_api_key = api_key

            return api_key

        except ClientError as e:
            error_code = e.response["Error"]["Code"]
            if error_code == "ResourceNotFoundException":
                raise RuntimeError(
                    f"API key not found in Secrets Manager: {secret_name}. "
                    f"Make sure enable_service_api_keys is true in Terraform."
                ) from e
            else:
                raise RuntimeError(
                    f"Failed to retrieve API key from Secrets Manager: {error_code}"
                ) from e

    def invalidate_api_key_cache(self) -> None:
        """Clear cached API key (useful after key rotation)."""
        self._cached_api_key = None

    def _get_headers(self, headers: Optional[dict[str, str]] = None) -> dict[str, str]:
        """Get headers with API key injected."""
        api_key = self.get_api_key()

        result_headers = headers.copy() if headers else {}
        result_headers["x-api-key"] = api_key

        return result_headers

    # =============================================================================
    # Async HTTP Methods
    # =============================================================================

    async def _get_async_client(self) -> httpx.AsyncClient:
        """Get or create async HTTP client."""
        if self._async_client is None:
            self._async_client = httpx.AsyncClient(
                timeout=httpx.Timeout(self.timeout),
                limits=httpx.Limits(max_keepalive_connections=5, max_connections=10),
            )
        return self._async_client

    async def get(
        self,
        url: str,
        params: Optional[dict[str, Any]] = None,
        headers: Optional[dict[str, str]] = None,
        **kwargs,
    ) -> httpx.Response:
        """Make authenticated GET request."""
        client = await self._get_async_client()
        return await client.get(
            url,
            params=params,
            headers=self._get_headers(headers),
            **kwargs,
        )

    async def post(
        self,
        url: str,
        json: Optional[dict[str, Any]] = None,
        data: Optional[Any] = None,
        headers: Optional[dict[str, str]] = None,
        **kwargs,
    ) -> httpx.Response:
        """Make authenticated POST request."""
        client = await self._get_async_client()
        return await client.post(
            url,
            json=json,
            data=data,
            headers=self._get_headers(headers),
            **kwargs,
        )

    async def put(
        self,
        url: str,
        json: Optional[dict[str, Any]] = None,
        data: Optional[Any] = None,
        headers: Optional[dict[str, str]] = None,
        **kwargs,
    ) -> httpx.Response:
        """Make authenticated PUT request."""
        client = await self._get_async_client()
        return await client.put(
            url,
            json=json,
            data=data,
            headers=self._get_headers(headers),
            **kwargs,
        )

    async def delete(
        self,
        url: str,
        headers: Optional[dict[str, str]] = None,
        **kwargs,
    ) -> httpx.Response:
        """Make authenticated DELETE request."""
        client = await self._get_async_client()
        return await client.delete(
            url,
            headers=self._get_headers(headers),
            **kwargs,
        )

    async def aclose(self) -> None:
        """Close async HTTP client."""
        if self._async_client:
            await self._async_client.aclose()
            self._async_client = None

    # Context manager support for async
    async def __aenter__(self):
        """Async context manager entry."""
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.aclose()


def get_service_url(service_name: str, base_url: str | None = None) -> str:
    """
    Get the full URL for a service endpoint.

    Args:
        service_name: Name of the target service ("api", "runner", "s3vector", etc.)
        base_url: Base API Gateway URL (defaults to API_GATEWAY_URL env var)

    Returns:
        Full URL with service path prefix

    Example:
        >>> get_service_url("runner")
        "https://abc123.execute-api.us-east-1.amazonaws.com/dev/runner"
    """
    if base_url is None:
        base_url = os.getenv("API_GATEWAY_URL", "")

    if not base_url:
        raise ValueError("base_url not provided and API_GATEWAY_URL environment variable not set")

    # Remove trailing slash from base_url
    base_url = base_url.rstrip("/")

    # Add service path prefix
    return f"{base_url}/{service_name}"
