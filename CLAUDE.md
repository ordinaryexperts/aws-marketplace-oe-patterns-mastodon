# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AWS Marketplace pattern that deploys a production-ready Mastodon instance using CloudFormation/CDK. The project consists of:

1. **Custom AMI** built with Packer (Ubuntu 24.04 with Mastodon pre-installed)
2. **CDK Infrastructure** (Python) that synthesizes to CloudFormation templates
3. **Product Listing Framework (PLF)** configuration for AWS Marketplace publishing

The infrastructure includes: VPC, Auto Scaling Groups (EC2), Aurora PostgreSQL, ElastiCache Redis, OpenSearch Service, S3, SES, Route53, ACM, and supporting services (IAM, Secrets Manager, SSM).

## Development Environment

All development is done inside Docker containers via docker-compose to ensure consistency:

- `devenv` service: Main development environment with CDK, AWS CLI, Python, and all required tools
- `ami` service: Packer environment for building custom AMIs

**Never run CDK, Packer, or other build commands directly on the host.** Always use `make` targets which wrap docker-compose.

### Using AWS Profiles

The `~/.aws` directory is mounted into the container, so you can use AWS profiles directly:

```bash
AWS_PROFILE=oe-patterns-dev make ami-ec2-build
AWS_PROFILE=oe-patterns-dev make deploy
```

Alternatively, you can export the profile:
```bash
export AWS_PROFILE=oe-patterns-dev
make ami-ec2-build
```

## Common Commands

### Build and Setup
- `make build` - Build the devenv Docker image
- `make rebuild` - Rebuild devenv without cache
- `make bash` - Start an interactive bash session in devenv container

### CDK Operations
- `make synth` - Synthesize CloudFormation template
- `make synth-to-file` - Synthesize template and save to `dist/template.yaml`
- `make diff` - Show differences between deployed stack and current code
- `make deploy` - Deploy the stack to AWS (dev environment)
- `make destroy` - Destroy the deployed stack
- `make cdk-bootstrap` - Bootstrap CDK in the AWS account

### Testing
- `make lint` - Run linting checks
- `make test-main` - Run main integration test with taskcat (deploys actual stack)
- `make test-all` - Run all integration tests

### AMI Building
- `make ami-ec2-build AMI_ID=<id> TEMPLATE_VERSION=<version>` - Build AMI with Packer
- `make ami-ec2-copy AMI_ID=<id>` - Copy AMI to other regions
- `make ami-docker-bash` - Interactive bash session in AMI container

### Product Listing Framework (PLF)
- `make gen-plf AMI_ID=<id> TEMPLATE_VERSION=<version>` - Generate PLF configuration
- `make plf AMI_ID=<id> TEMPLATE_VERSION=<version>` - Update product listing
- `make plf-skip-pricing` - Update PLF without updating pricing
- `make plf-skip-region` - Update PLF without updating region availability

### Publishing
- `make publish TEMPLATE_VERSION=<version>` - Publish CloudFormation template to S3
- `make publish-diagram TEMPLATE_VERSION=<version>` - Publish architecture diagram

### Cleanup
- `make clean` - Clean up test resources
- `make clean-snapshots-tcat` - Clean up taskcat snapshots
- `make clean-logs-tcat` - Clean up taskcat logs
- `make clean-buckets-tcat` - Clean up taskcat S3 buckets

## Architecture

### CDK Stack Structure

The main CDK stack (`cdk/mastodon/mastodon_stack.py`) is composed using reusable constructs from the `oe-patterns-cdk-common` library. Key components:

1. **Vpc** - Creates VPC or uses existing one via parameters
2. **Dns** - Route53 hosted zone integration (parameter-driven)
3. **AssetsBucket** - S3 bucket for user-generated content (images, videos)
4. **Ses** - SES domain identity with Easy DKIM for email
5. **DbSecret** - Secrets Manager for database credentials
6. **ElasticacheRedis** - Redis cluster for caching (with `maxmemory-policy: noeviction`)
7. **OpenSearchService** - OpenSearch domain for full-text search
8. **AuroraPostgresql** - Aurora PostgreSQL cluster (multi-AZ)
9. **Alb** - Application Load Balancer with ACM certificate
10. **Asg** - Auto Scaling Group with custom AMI

### AMI Configuration

The AMI is built via Packer (`packer/ami.json`) using `packer/ubuntu_2404_appinstall.sh`. It pre-installs:
- Mastodon application files
- Ruby, Node.js, and dependencies
- nginx as reverse proxy
- CloudWatch agent
- AWS Systems Manager agent

The AMI ID is hardcoded in `cdk/mastodon/mastodon_stack.py` and must be updated when building new AMIs.

### User Data

EC2 instances run `cdk/mastodon/user_data.sh` on boot, which:
- Retrieves secrets from Secrets Manager
- Configures Mastodon environment variables
- Starts Mastodon services
- Configures CloudWatch Logs

### Parameter-Driven Design

The stack uses CloudFormation parameters extensively (see `CfnParameter` calls in `mastodon_stack.py`). Key parameters:
- `Name` - Site name
- `DnsHostname` / `DnsRoute53HostedZoneName` - DNS configuration
- `AlbCertificateArn` - ACM certificate for HTTPS
- `AlbIngressCidr` - IP ranges allowed to access the site
- `AsgReprovisionString` - Forces ASG instance replacement when changed
- `OpenSearchServiceCreateServiceLinkedRole` - Whether to create OSS role
- `SesCreateDomainIdentity` - Whether to create SES domain identity

## Important Patterns

### Version Management
Template version is determined by:
1. `TEMPLATE_VERSION` environment variable (if set)
2. `git describe` output (in git repos)
3. Falls back to "CICD" in CI environments

### Secrets Management
Database passwords and other secrets are:
1. Generated via `DbSecret` construct in Secrets Manager
2. Retrieved by EC2 instances via IAM role permissions
3. SES SMTP password generated by Lambda function (`lambda_generate_smtp_password.py`)

### Resource Tagging
All resources are tagged via CDK's built-in tagging, including the stack name and custom tags for AWS Marketplace patterns.

## Testing

Integration tests use [taskcat](https://github.com/aws-ia/taskcat), which:
1. Synthesizes the CloudFormation template
2. Deploys it to AWS with test parameters
3. Validates deployment succeeds
4. Cleans up resources

Test configuration is in `test/main-test/.taskcat.yml`. Tests run on:
- Every push to `develop` branch
- Pull requests to `develop`
- Weekly schedule (Mondays at 12:12pm Pacific)

## Git Workflow

- Main branch: `develop` (not `main` or `master`)
- Use git-flow style releases: feature branches → develop → release/X.Y.Z → tags

## Dependencies

### Python CDK Dependencies
Defined in `cdk/setup.py`:
- `aws-cdk-lib==2.120.0`
- `constructs>=10.0.0,<11.0.0`
- `oe-patterns-cdk-common@4.2.6` (from GitHub, contains reusable constructs)

### Docker Base Image
`ordinaryexperts/aws-marketplace-patterns-devenv:2.5.5` - contains CDK, Python, AWS CLI, taskcat, and other tools.

## Files to Update When Releasing

1. `cdk/mastodon/mastodon_stack.py` - Update `AMI_ID` constant
2. `plf_config.yaml` - Product listing metadata (auto-updated by PLF scripts)
3. `CHANGELOG.md` - Document changes
4. Git tag with version number
