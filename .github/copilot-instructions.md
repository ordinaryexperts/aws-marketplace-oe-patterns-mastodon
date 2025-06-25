# GitHub Copilot Custom Instructions for AWS Marketplace Mastodon

## Repository Overview

This repository contains the **Ordinary Experts Mastodon AWS Marketplace product**, which provides a production-ready [Mastodon](https://joinmastodon.org/) deployment on AWS using infrastructure as code.

## Architecture & Technologies

### Core Infrastructure
- **AWS CloudFormation/CDK**: Infrastructure deployment using AWS CDK (Python)
- **AWS Services**: VPC, EC2 Auto Scaling Groups, Aurora Postgres, ElastiCache Redis, OpenSearch, S3, SES, Route53, ACM, IAM, Secrets Manager, SSM
- **AMI Management**: Custom AMI built with Packer for the Mastodon application tier

### Development Environment
- **Primary Languages**: Shell scripting and Python
- **Build System**: Makefile with shared `common.mk` from [aws-marketplace-utilities](https://github.com/ordinaryexperts/aws-marketplace-utilities)
- **Containerization**: Docker Compose for development tasks and isolated build environments
- **Testing**: Taskcat for CloudFormation template testing

## Key Commands & Workflow

### Build & Development Commands
The repository uses a Makefile system that proxies to `common.mk`. Key targets include:

```bash
# Download/update shared build utilities
make update-common

# Build the development Docker environment
make build

# Run full test pipeline (CDK synth + Taskcat)
make test-all

# Run main test only
make test-main

# Deploy infrastructure (requires AWS credentials)
make deploy

# Start interactive development shell
make bash

# Generate CloudFormation template
make synth
```

### Docker Compose Services
- **devenv**: Main development environment with CDK, Python, and AWS tools
- **ami**: Packer-based AMI building environment

### Project Structure
- `cdk/`: AWS CDK Python application (CDK version 2.120.0, Python >=3.6)
- `packer/`: AMI building scripts for Mastodon application
- `test/`: Taskcat test configurations
- `common.mk`: Shared Makefile targets from aws-marketplace-utilities

## Development Guidelines

1. **Use Docker Compose**: All development tasks should use the containerized environment via `make` commands
2. **Follow CDK Patterns**: Use the established CDK patterns from `oe-patterns-cdk-common` library
3. **Test Infrastructure**: Always run `make test-main` for validation before submitting changes
4. **Shell Scripting**: Follow existing patterns in packer and user_data scripts
5. **Python Code**: Follow CDK Python conventions, use type hints where appropriate
6. **File Format**: All files must end with a newline character

## Code Context Tips

- Look for infrastructure patterns in `cdk/mastodon/` directory
- Shell scripts primarily in `packer/` for AMI configuration and `cdk/mastodon/user_data.sh` for instance initialization
- Configuration files use YAML format (`.taskcat.yml`, `docker-compose.yml`, workflow files)
- The repository deploys a complete social media platform, so consider scalability, security, and operational concerns

## Testing & CI/CD

The repository includes GitHub Actions workflows for:
- Main testing pipeline (`.github/workflows/main.yml`)
- Automated testing on push/PR to develop branch
- Scheduled testing (weekly)

When suggesting code changes, consider:
- Impact on CloudFormation template generation
- AWS resource dependencies and constraints
- Security implications (IAM, networking, secrets)
- Cost optimization opportunities
- Operational monitoring and logging requirements

---

For more information about GitHub Copilot custom instructions, see: [Adding repository custom instructions for GitHub Copilot](https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot)
