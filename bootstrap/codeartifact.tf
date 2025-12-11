# =============================================================================
# AWS CodeArtifact Configuration
# =============================================================================
# This file creates AWS CodeArtifact resources for hosting internal Python
# packages within project-specific repositories.
#
# Architecture:
#   - Single domain shared across all projects (e.g., 'agsys')
#   - Project-specific repositories: {domain}-{project_name}
#     * Examples: agsys-common, agsys-frontend, agsys-api
#   - Environment separation via semantic versioning:
#     * Dev: Pre-release versions (1.2.0a1, 1.2.0b1, 1.2.0rc1)
#     * Prod: Stable versions (1.2.0, 1.3.0)
#
# Resources created:
#   - CodeArtifact Domain (with AWS managed encryption, shared across all projects)
#   - CodeArtifact Repository (PyPI format with upstream to public PyPI)
#   - IAM policies for publishing and reading packages
#   - Policy attachments to Lambda, AppRunner, and GitHub Actions roles
# =============================================================================

# =============================================================================
# CodeArtifact Domain
# =============================================================================
# Using AWS managed encryption (default) instead of customer managed KMS key

resource "aws_codeartifact_domain" "main" {
  count = var.enable_codeartifact ? 1 : 0

  domain = var.codeartifact_domain

  tags = {
    Name        = "${var.project_name}-codeartifact-domain"
    Environment = "shared"
    Service     = "codeartifact"
  }
}

# =============================================================================
# CodeArtifact Repository (Python/PyPI)
# =============================================================================
# Project-specific repository: {domain}-{project_name}
# Example: agsys-common, agsys-frontend, agsys-api
# This allows each project to have its own repository within the shared domain

resource "aws_codeartifact_repository" "python" {
  count = var.enable_codeartifact ? 1 : 0

  repository = "${var.codeartifact_domain}-${var.project_name}"
  domain     = aws_codeartifact_domain.main[0].domain

  # Upstream PyPI for public packages
  external_connections {
    external_connection_name = "public:pypi"
  }

  tags = {
    Name        = "${var.codeartifact_domain}-${var.project_name}-repo"
    Environment = "shared"
    Service     = "codeartifact"
    Format      = "pypi"
  }
}

# =============================================================================
# IAM Policy for Publishing Packages
# =============================================================================

resource "aws_iam_policy" "codeartifact_publish" {
  count = var.enable_codeartifact ? 1 : 0

  name        = "${var.project_name}-codeartifact-publish"
  description = "Allow publishing packages to CodeArtifact repository"
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PublishPackageVersion"
        Effect = "Allow"
        Action = [
          "codeartifact:PublishPackageVersion",
          "codeartifact:PutPackageMetadata",
        ]
        Resource = [
          aws_codeartifact_repository.python[0].arn,
          "${aws_codeartifact_repository.python[0].arn}/*"
        ]
      },
      {
        Sid    = "GetAuthorizationToken"
        Effect = "Allow"
        Action = [
          "codeartifact:GetAuthorizationToken",
          "codeartifact:GetRepositoryEndpoint",
          "codeartifact:DescribeRepository",
        ]
        Resource = [
          aws_codeartifact_repository.python[0].arn,
          aws_codeartifact_domain.main[0].arn,
        ]
      },
      {
        Sid      = "GetServiceBearerToken"
        Effect   = "Allow"
        Action   = "sts:GetServiceBearerToken"
        Resource = "*"
        Condition = {
          StringEquals = {
            "sts:AWSServiceName" = "codeartifact.amazonaws.com"
          }
        }
      },
    ]
  })

  tags = {
    Name    = "${var.project_name}-codeartifact-publish"
    Service = "codeartifact"
  }
}

# =============================================================================
# IAM Policy for Reading Packages
# =============================================================================

resource "aws_iam_policy" "codeartifact_read" {
  count = var.enable_codeartifact ? 1 : 0

  name        = "${var.project_name}-codeartifact-read"
  description = "Allow reading packages from CodeArtifact repository"
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadPackages"
        Effect = "Allow"
        Action = [
          "codeartifact:GetPackageVersionReadme",
          "codeartifact:GetPackageVersionAsset",
          "codeartifact:ReadFromRepository",
          "codeartifact:ListPackages",
          "codeartifact:ListPackageVersions",
          "codeartifact:DescribePackageVersion",
          "codeartifact:GetRepositoryEndpoint",
        ]
        Resource = [
          aws_codeartifact_repository.python[0].arn,
          "${aws_codeartifact_repository.python[0].arn}/*"
        ]
      },
      {
        Sid    = "GetAuthorizationToken"
        Effect = "Allow"
        Action = [
          "codeartifact:GetAuthorizationToken",
          "codeartifact:DescribeRepository",
          "codeartifact:DescribeDomain",
        ]
        Resource = [
          aws_codeartifact_repository.python[0].arn,
          aws_codeartifact_domain.main[0].arn,
        ]
      },
      {
        Sid      = "GetServiceBearerToken"
        Effect   = "Allow"
        Action   = "sts:GetServiceBearerToken"
        Resource = "*"
        Condition = {
          StringEquals = {
            "sts:AWSServiceName" = "codeartifact.amazonaws.com"
          }
        }
      },
    ]
  })

  tags = {
    Name    = "${var.project_name}-codeartifact-read"
    Service = "codeartifact"
  }
}

# =============================================================================
# Attach Read Policy to Lambda Execution Role
# =============================================================================
# Note: Lambda services use container images, so CodeArtifact access is only
# needed at Docker build time (via GitHub Actions), not at runtime.
# This attachment is optional and for future use cases.

resource "aws_iam_role_policy_attachment" "lambda_codeartifact" {
  count = var.enable_lambda && var.enable_codeartifact ? 1 : 0

  role       = aws_iam_role.lambda_execution[0].name
  policy_arn = aws_iam_policy.codeartifact_read[0].arn
}

# =============================================================================
# Attach Read Policy to AppRunner Instance Role
# =============================================================================
# Note: AppRunner services also use container images from ECR, so CodeArtifact
# access is only needed at Docker build time (via GitHub Actions), not at runtime.
# This attachment is optional and for future use cases.

resource "aws_iam_role_policy_attachment" "apprunner_codeartifact" {
  count = var.enable_apprunner && var.enable_codeartifact ? 1 : 0

  role       = aws_iam_role.apprunner_instance[0].name
  policy_arn = aws_iam_policy.codeartifact_read[0].arn
}

# =============================================================================
# Attach Publish Policy to GitHub Actions Roles
# =============================================================================
# Allow GitHub Actions workflows to publish packages to CodeArtifact

resource "aws_iam_role_policy_attachment" "github_dev_codeartifact_publish" {
  count = var.enable_codeartifact ? 1 : 0

  role       = aws_iam_role.github_actions_dev.name
  policy_arn = aws_iam_policy.codeartifact_publish[0].arn
}

resource "aws_iam_role_policy_attachment" "github_dev_codeartifact_read" {
  count = var.enable_codeartifact ? 1 : 0

  role       = aws_iam_role.github_actions_dev.name
  policy_arn = aws_iam_policy.codeartifact_read[0].arn
}

resource "aws_iam_role_policy_attachment" "github_test_codeartifact_publish" {
  count = var.enable_test_environment && var.enable_codeartifact ? 1 : 0

  role       = aws_iam_role.github_actions_test[0].name
  policy_arn = aws_iam_policy.codeartifact_publish[0].arn
}

resource "aws_iam_role_policy_attachment" "github_test_codeartifact_read" {
  count = var.enable_test_environment && var.enable_codeartifact ? 1 : 0

  role       = aws_iam_role.github_actions_test[0].name
  policy_arn = aws_iam_policy.codeartifact_read[0].arn
}

resource "aws_iam_role_policy_attachment" "github_prod_codeartifact_publish" {
  count = var.enable_codeartifact ? 1 : 0

  role       = aws_iam_role.github_actions_prod.name
  policy_arn = aws_iam_policy.codeartifact_publish[0].arn
}

resource "aws_iam_role_policy_attachment" "github_prod_codeartifact_read" {
  count = var.enable_codeartifact ? 1 : 0

  role       = aws_iam_role.github_actions_prod.name
  policy_arn = aws_iam_policy.codeartifact_read[0].arn
}
