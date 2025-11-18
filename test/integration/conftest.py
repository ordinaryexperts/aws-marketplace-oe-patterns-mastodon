"""
Pytest configuration and shared fixtures for integration tests.
This file is automatically loaded by pytest.
"""

import os
import yaml
import pytest
import boto3
from pathlib import Path


def pytest_addoption(parser):
    """Add custom command line options."""
    parser.addoption(
        "--base-url",
        action="store",
        default=None,
        help="Base URL for the application under test"
    )
    parser.addoption(
        "--stack-name",
        action="store",
        default=None,
        help="CloudFormation stack name"
    )
    parser.addoption(
        "--skip-ui",
        action="store_true",
        default=False,
        help="Skip UI/browser tests"
    )


@pytest.fixture(scope="session")
def config():
    """Load test configuration from config.yaml."""
    config_path = Path(__file__).parent / "config.yaml"
    with open(config_path, 'r') as f:
        return yaml.safe_load(f)


@pytest.fixture(scope="session")
def base_url(request, config):
    """Get base URL from CLI option, environment variable, or config file."""
    # Priority: CLI option > Environment variable > config file
    url = (
        request.config.getoption("--base-url") or
        os.environ.get("TEST_BASE_URL") or
        config["urls"]["base_url"]
    )
    # Ensure URL doesn't end with slash
    return url.rstrip("/")


@pytest.fixture(scope="session")
def stack_name(request, config):
    """Get CloudFormation stack name."""
    return (
        request.config.getoption("--stack-name") or
        os.environ.get("TEST_STACK_NAME") or
        config["aws"]["stack_name"]
    )


@pytest.fixture(scope="session")
def aws_region(config):
    """Get AWS region."""
    return os.environ.get("AWS_REGION") or config["aws"]["region"]


@pytest.fixture(scope="session")
def cloudformation_client(aws_region):
    """Create CloudFormation client."""
    return boto3.client("cloudformation", region_name=aws_region)


@pytest.fixture(scope="session")
def ec2_client(aws_region):
    """Create EC2 client."""
    return boto3.client("ec2", region_name=aws_region)


@pytest.fixture(scope="session")
def ssm_client(aws_region):
    """Create SSM client."""
    return boto3.client("ssm", region_name=aws_region)


@pytest.fixture(scope="session")
def stack_outputs(cloudformation_client, stack_name):
    """Get CloudFormation stack outputs."""
    try:
        response = cloudformation_client.describe_stacks(StackName=stack_name)
        stack = response["Stacks"][0]

        outputs = {}
        for output in stack.get("Outputs", []):
            outputs[output["OutputKey"]] = output["OutputValue"]

        return outputs
    except Exception as e:
        pytest.fail(f"Failed to get stack outputs: {e}")


@pytest.fixture(scope="session")
def instance_id(ec2_client, stack_name):
    """Get EC2 instance ID from stack."""
    try:
        response = ec2_client.describe_instances(
            Filters=[
                {"Name": "tag:aws:cloudformation:stack-name", "Values": [stack_name]},
                {"Name": "instance-state-name", "Values": ["running"]}
            ]
        )

        if response["Reservations"]:
            return response["Reservations"][0]["Instances"][0]["InstanceId"]

        pytest.fail(f"No running instances found for stack {stack_name}")
    except Exception as e:
        pytest.fail(f"Failed to get instance ID: {e}")


@pytest.fixture(scope="session")
def skip_ui_tests(request):
    """Check if UI tests should be skipped."""
    return request.config.getoption("--skip-ui")


def pytest_collection_modifyitems(config, items):
    """Modify test collection to handle skip markers."""
    skip_ui = config.getoption("--skip-ui")

    if skip_ui:
        skip_ui_marker = pytest.mark.skip(reason="--skip-ui option provided")
        for item in items:
            if "ui" in item.keywords:
                item.add_marker(skip_ui_marker)
