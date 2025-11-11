# Mastodon Integration Tests

This directory contains integration tests for the Mastodon AWS Marketplace pattern. These tests validate infrastructure deployment, application health, and user workflows.

## Test Levels

### Level 1: Infrastructure & Health Tests (`test_health.py`)
- HTTPS accessibility
- SSL certificate validation
- Health check endpoint
- API availability
- Response time
- Security headers
- CloudFormation stack status
- EC2 instance health

### Level 2: API Tests (`test_health.py`)
- Instance API validation
- Version verification
- Infrastructure components

### Level 3: UI Workflow Tests (`test_workflows.py`)
- Homepage loading
- Navigation flows
- User signup/login pages
- Public timeline
- About page

## Setup

### Install Dependencies

```bash
cd test/integration
pip install -r requirements.txt

# Install Playwright browsers
playwright install chromium
```

### Configuration

Edit `config.yaml` to match your deployment:

```yaml
urls:
  base_url: "https://your-mastodon-instance.example.com"

aws:
  region: "us-east-1"
  stack_name: "your-stack-name"

application:
  expected_version: "4.4.8"
```

Alternatively, use environment variables:

```bash
export TEST_BASE_URL="https://your-mastodon-instance.example.com"
export TEST_STACK_NAME="your-stack-name"
export AWS_REGION="us-east-1"
```

## Running Tests

### Using Make (Recommended)

The easiest way to run tests is using the Makefile targets, which run tests inside the devenv container:

```bash
# Run all health and infrastructure tests
make test-integration

# Run only health tests
make test-integration-health

# Run only infrastructure tests
make test-integration-infrastructure

# Run UI/workflow tests
make test-integration-ui

# Run all tests (health, infrastructure, and UI)
make test-integration-all
```

### Using pytest Directly

You can also run tests directly with pytest:

```bash
# Run all tests
pytest -v

# Run only health tests
pytest test_health.py -v

# Run with custom URL
pytest --base-url="https://your-instance.com" -v

# Run specific test
pytest test_health.py::TestMastodonHealth::test_health_endpoint -v
```

## Test Markers

Tests are organized with pytest markers:

- `@pytest.mark.ui` - UI/browser tests using Playwright
- `@pytest.mark.slow` - Slower end-to-end tests

Run only UI tests:
```bash
pytest -m ui -v
```

Skip slow tests:
```bash
pytest -m "not slow" -v
```

## AWS Authentication

Tests use boto3 and respect standard AWS credential chain:

1. Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
2. AWS credentials file (`~/.aws/credentials`)
3. IAM instance profile (when running on EC2)
4. AWS profile:
   ```bash
   export AWS_PROFILE=your-profile
   pytest -v
   ```

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Run Integration Tests
  env:
    TEST_BASE_URL: ${{ secrets.TEST_BASE_URL }}
    TEST_STACK_NAME: ${{ secrets.STACK_NAME }}
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  run: |
    cd test/integration
    pip install -r requirements.txt
    playwright install --with-deps chromium
    pytest --skip-ui -v  # Skip UI tests in CI for speed
```

## User Workflow Testing

Full user workflow tests (signup, posting, etc.) require a test user. Create one using `tootctl`:

```bash
# SSH into the instance
ssh ec2-user@your-instance

# Create test user
sudo su - mastodon -c 'cd ~/live && \
  RAILS_ENV=production bin/tootctl accounts create testuser \
  --email test@example.com --confirmed --role User'

# The command will output a password - save this for testing
```

Then update `test_workflows.py` to use these credentials.

## Adapting for Other Projects

This test framework is designed to be reusable across all OE Patterns projects:

1. Copy the `test/integration` directory to your project
2. Update `config.yaml` with project-specific endpoints
3. Modify `get_health_endpoint()`, `get_version_endpoint()` in tests
4. Add project-specific workflow tests to `test_workflows.py`

Example for WordPress:

```yaml
application:
  name: "WordPress"
  health_endpoint: "/wp-json/wp/v2/posts"
  version_endpoint: "/wp-json/"
  version_field: "version"
  expected_version: "6.4"
```

## Troubleshooting

### SSL Certificate Errors

If you're testing against a self-signed certificate:

```bash
export PYTHONHTTPSVERIFY=0  # Not recommended for production
```

### Timeout Errors

Increase timeout in `config.yaml`:

```yaml
test:
  timeout: 60
```

### Playwright Browser Issues

```bash
# Reinstall browsers
playwright install --force chromium

# Run with visible browser for debugging
# Edit test to set headless=False
```

### AWS Permission Errors

Ensure your AWS credentials have permissions:
- `cloudformation:DescribeStacks`
- `ec2:DescribeInstances`
- `ssm:SendCommand` (for workflow tests)

## Writing New Tests

Follow the pattern in `base_integration_test.py`:

```python
import pytest
import requests

def test_my_feature(base_url, config):
    """Test my custom feature."""
    response = requests.get(f"{base_url}/my-endpoint")
    assert response.status_code == 200
    # Add more assertions
```

## Support

For issues specific to this testing framework, open an issue on the project repository.

For Mastodon-specific questions, see: https://docs.joinmastodon.org/
