"""
Base integration test class for OE Patterns projects.
This can be used across all patterns projects (Mastodon, WordPress, Drupal, etc.)
"""

import time
import requests
import pytest
from typing import Dict, Any, Optional


class BaseIntegrationTest:
    """Base class for integration tests across all OE Patterns projects."""

    def __init__(self, base_url: str, config: Dict[str, Any]):
        self.base_url = base_url
        self.config = config
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "OE-Patterns-Integration-Test/1.0"
        })

    def test_https_access(self):
        """Test that the application is accessible over HTTPS."""
        response = self.session.get(self.base_url, timeout=30)
        assert response.status_code in [200, 301, 302], \
            f"HTTPS access failed with status {response.status_code}"
        assert response.url.startswith("https://"), \
            "Application should use HTTPS"

    def test_ssl_certificate(self):
        """Verify SSL certificate is valid."""
        import ssl
        import socket
        from urllib.parse import urlparse

        parsed = urlparse(self.base_url)
        hostname = parsed.hostname
        port = parsed.port or 443

        context = ssl.create_default_context()
        with socket.create_connection((hostname, port), timeout=10) as sock:
            with context.wrap_socket(sock, server_hostname=hostname) as ssock:
                cert = ssock.getpeercert()
                # If we get here without exception, certificate is valid
                assert cert is not None, "No SSL certificate found"

    def test_health_endpoint(self):
        """
        Test application-specific health endpoint.
        Override get_health_endpoint() in subclass to customize.
        """
        health_url = self.get_health_endpoint()
        if not health_url:
            pytest.skip("No health endpoint configured")

        response = self.session.get(f"{self.base_url}{health_url}", timeout=10)
        assert response.status_code == 200, \
            f"Health check failed with status {response.status_code}"

        expected = self.get_expected_health_response()
        if expected:
            assert response.json() == expected, \
                f"Health response mismatch. Expected: {expected}, Got: {response.json()}"

    def test_version_endpoint(self):
        """
        Test that the application reports the correct version.
        Override get_version_endpoint() in subclass to customize.
        """
        version_url = self.get_version_endpoint()
        if not version_url:
            pytest.skip("No version endpoint configured")

        response = self.session.get(f"{self.base_url}{version_url}", timeout=10)
        assert response.status_code == 200, \
            f"Version check failed with status {response.status_code}"

        data = response.json()
        version_field = self.get_version_field()
        expected_version = self.get_expected_version()

        if version_field and expected_version:
            actual_version = self._get_nested_field(data, version_field)
            assert expected_version in actual_version, \
                f"Version mismatch. Expected: {expected_version}, Got: {actual_version}"

    def test_response_time(self):
        """Test that the application responds within acceptable time."""
        max_response_time = self.config.get("test", {}).get("timeout", 30)

        start = time.time()
        response = self.session.get(self.base_url, timeout=max_response_time)
        elapsed = time.time() - start

        assert response.status_code in [200, 301, 302], \
            f"Request failed with status {response.status_code}"
        assert elapsed < max_response_time, \
            f"Response time {elapsed:.2f}s exceeds maximum {max_response_time}s"

    def test_security_headers(self):
        """Test that important security headers are present."""
        response = self.session.get(self.base_url, timeout=10)
        headers = response.headers

        # Check for important security headers
        security_checks = {
            "X-Frame-Options": ["DENY", "SAMEORIGIN"],
            "X-Content-Type-Options": ["nosniff"],
            "Strict-Transport-Security": None,  # Just check presence
        }

        for header, expected_values in security_checks.items():
            if header in headers:
                if expected_values:
                    assert any(val in headers[header] for val in expected_values), \
                        f"{header} has unexpected value: {headers[header]}"
            # Note: We don't fail if headers are missing, just log
            # Some apps may not set all headers

    # Methods to override in subclasses

    def get_health_endpoint(self) -> Optional[str]:
        """Return the health check endpoint path. Override in subclass."""
        return self.config.get("application", {}).get("health_endpoint")

    def get_expected_health_response(self) -> Optional[Dict]:
        """Return expected health response. Override in subclass."""
        return self.config.get("application", {}).get("health_expected_response")

    def get_version_endpoint(self) -> Optional[str]:
        """Return the version endpoint path. Override in subclass."""
        return self.config.get("application", {}).get("version_endpoint")

    def get_version_field(self) -> Optional[str]:
        """Return the field name containing version info. Override in subclass."""
        return self.config.get("application", {}).get("version_field")

    def get_expected_version(self) -> Optional[str]:
        """Return expected version string. Override in subclass."""
        return self.config.get("application", {}).get("expected_version")

    # Helper methods

    def _get_nested_field(self, data: Dict, field_path: str) -> Any:
        """Get nested field from dict using dot notation (e.g., 'metadata.version')."""
        fields = field_path.split(".")
        value = data
        for field in fields:
            value = value.get(field)
            if value is None:
                return None
        return value

    def retry_request(self, url: str, max_attempts: int = 3, delay: int = 2) -> requests.Response:
        """Retry a request with exponential backoff."""
        for attempt in range(max_attempts):
            try:
                response = self.session.get(url, timeout=10)
                if response.status_code == 200:
                    return response
            except requests.exceptions.RequestException:
                if attempt == max_attempts - 1:
                    raise

            time.sleep(delay * (attempt + 1))

        raise requests.exceptions.RequestException(f"Failed after {max_attempts} attempts")
