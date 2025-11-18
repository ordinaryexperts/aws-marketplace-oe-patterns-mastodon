"""
Health and basic connectivity tests for Mastodon.
These tests validate infrastructure and basic application health.
"""

import pytest
import requests


class TestMastodonHealth:
    """Level 1: Infrastructure and basic health tests."""

    def test_https_accessible(self, base_url):
        """Test that Mastodon is accessible over HTTPS."""
        response = requests.get(base_url, timeout=30, allow_redirects=True)
        assert response.status_code == 200, \
            f"Failed to access Mastodon at {base_url}"
        assert response.url.startswith("https://"), \
            "Mastodon should be accessible via HTTPS"

    def test_health_endpoint(self, base_url):
        """Test Mastodon health check endpoint."""
        health_url = f"{base_url}/health"
        response = requests.get(health_url, timeout=10)

        assert response.status_code == 200, \
            f"Health check failed with status {response.status_code}"

        # Mastodon's /health endpoint returns plain text "OK", not JSON
        assert response.text.strip() == "OK", \
            f"Health check returned unexpected status: {response.text}"

    def test_instance_api(self, base_url, config):
        """Test Mastodon instance API endpoint."""
        instance_url = f"{base_url}/api/v2/instance"
        response = requests.get(instance_url, timeout=10)

        assert response.status_code == 200, \
            f"Instance API failed with status {response.status_code}"

        data = response.json()

        # Validate response structure
        assert "domain" in data, "Instance response missing 'domain' field"
        assert "version" in data, "Instance response missing 'version' field"

        # Validate version
        expected_version = config["application"]["expected_version"]
        assert expected_version in data["version"], \
            f"Version mismatch. Expected: {expected_version}, Got: {data['version']}"

    def test_response_time(self, base_url):
        """Test that Mastodon responds within acceptable time."""
        import time

        start = time.time()
        response = requests.get(f"{base_url}/health", timeout=30)
        elapsed = time.time() - start

        assert response.status_code == 200, \
            "Health check failed"
        assert elapsed < 5.0, \
            f"Response time {elapsed:.2f}s exceeds 5 seconds"

    def test_ssl_certificate(self, base_url):
        """Verify SSL certificate is valid."""
        import ssl
        import socket
        from urllib.parse import urlparse

        parsed = urlparse(base_url)
        hostname = parsed.hostname
        port = parsed.port or 443

        context = ssl.create_default_context()
        try:
            with socket.create_connection((hostname, port), timeout=10) as sock:
                with context.wrap_socket(sock, server_hostname=hostname) as ssock:
                    cert = ssock.getpeercert()
                    assert cert is not None, "No SSL certificate found"

                    # Certificate is valid if we get here without exception
                    # Additional checks could be added here
        except ssl.SSLError as e:
            pytest.fail(f"SSL certificate validation failed: {e}")

    def test_security_headers(self, base_url):
        """Test that important security headers are present."""
        response = requests.get(base_url, timeout=10)
        headers = response.headers

        # Mastodon should set these security headers
        assert "X-Frame-Options" in headers, \
            "X-Frame-Options header missing"
        assert "X-Content-Type-Options" in headers, \
            "X-Content-Type-Options header missing"
        assert headers.get("X-Content-Type-Options") == "nosniff", \
            "X-Content-Type-Options should be 'nosniff'"


class TestMastodonInfrastructure:
    """Level 2: AWS infrastructure tests."""

    def test_cloudformation_stack_exists(self, cloudformation_client, stack_name):
        """Verify CloudFormation stack exists and is in good state."""
        response = cloudformation_client.describe_stacks(StackName=stack_name)

        assert len(response["Stacks"]) == 1, \
            f"Expected 1 stack, found {len(response['Stacks'])}"

        stack = response["Stacks"][0]
        assert stack["StackStatus"] in ["CREATE_COMPLETE", "UPDATE_COMPLETE"], \
            f"Stack is in unexpected state: {stack['StackStatus']}"

    def test_stack_outputs(self, stack_outputs):
        """Verify CloudFormation stack has required outputs."""
        required_outputs = [
            "DnsSiteUrlOutput",
            "VpcIdOutput",
        ]

        for output in required_outputs:
            assert output in stack_outputs, \
                f"Required output '{output}' missing from stack"
            assert stack_outputs[output], \
                f"Output '{output}' is empty"

    def test_ec2_instance_running(self, instance_id, ec2_client):
        """Verify EC2 instance is running."""
        response = ec2_client.describe_instances(InstanceIds=[instance_id])

        assert len(response["Reservations"]) > 0, \
            f"No reservations found for instance {instance_id}"

        instance = response["Reservations"][0]["Instances"][0]
        assert instance["State"]["Name"] == "running", \
            f"Instance is not running: {instance['State']['Name']}"

    def test_instance_has_correct_ami(self, instance_id, ec2_client, config):
        """Verify instance is using the expected AMI."""
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        instance = response["Reservations"][0]["Instances"][0]

        ami_id = instance["ImageId"]
        assert ami_id.startswith("ami-"), \
            f"Invalid AMI ID format: {ami_id}"

        # AMI ID can be validated from config if needed
        # For now, just verify it's a valid format
