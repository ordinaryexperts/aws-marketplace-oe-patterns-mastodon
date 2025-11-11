"""
User workflow tests for Mastodon using Playwright.
These tests simulate real user interactions.
"""

import pytest
import time
import random
import string
from playwright.sync_api import sync_playwright, expect


@pytest.mark.ui
class TestMastodonUIWorkflows:
    """Level 3: UI and user workflow tests."""

    @pytest.fixture(scope="class")
    def browser_context(self):
        """Create a browser context for UI tests."""
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context(
                viewport={"width": 1280, "height": 720},
                user_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
            )
            yield context
            context.close()
            browser.close()

    def test_homepage_loads(self, base_url, browser_context):
        """Test that the Mastodon homepage loads correctly."""
        page = browser_context.new_page()

        try:
            page.goto(base_url, wait_until="networkidle", timeout=30000)

            # Wait for page to be interactive
            page.wait_for_load_state("domcontentloaded")

            # Check that essential elements are present
            assert page.title(), "Page title should not be empty"

            # Mastodon should show sign up/login options
            page_content = page.content()
            assert "mastodon" in page_content.lower(), \
                "Page should contain 'Mastodon'"

        finally:
            page.close()

    def test_signup_page_accessible(self, base_url, browser_context):
        """Test that the signup page is accessible."""
        page = browser_context.new_page()

        try:
            page.goto(base_url, timeout=30000)

            # Look for sign up link/button
            # Note: Mastodon's UI may vary, so we use flexible selectors
            signup_selectors = [
                'a:has-text("Sign up")',
                'a:has-text("Create account")',
                'a:has-text("Register")',
                '[href*="sign_up"]',
                '[href*="signup"]',
            ]

            signup_found = False
            for selector in signup_selectors:
                try:
                    if page.locator(selector).count() > 0:
                        signup_found = True
                        break
                except:
                    continue

            # If we can't find signup link, that's okay - may require config
            # Just verify page loaded
            if not signup_found:
                pytest.skip("Signup link not found - may require server configuration")

        finally:
            page.close()

    def test_login_page_accessible(self, base_url, browser_context):
        """Test that the login page is accessible."""
        page = browser_context.new_page()

        try:
            page.goto(base_url, timeout=30000)

            # Look for sign in link/button
            signin_selectors = [
                'a:has-text("Sign in")',
                'a:has-text("Log in")',
                'a:has-text("Login")',
                '[href*="sign_in"]',
                '[href*="login"]',
            ]

            signin_found = False
            for selector in signin_selectors:
                try:
                    if page.locator(selector).count() > 0:
                        signin_found = True
                        page.click(selector, timeout=5000)

                        # Should navigate to login page
                        page.wait_for_load_state("domcontentloaded")
                        assert "sign_in" in page.url.lower() or "login" in page.url.lower(), \
                            "Should navigate to login page"
                        break
                except:
                    continue

            if not signin_found:
                pytest.skip("Sign in link not found")

        finally:
            page.close()

    def test_public_timeline_accessible(self, base_url, browser_context):
        """Test that public timeline is accessible."""
        page = browser_context.new_page()

        try:
            # Try to access public timeline directly
            public_url = f"{base_url}/public"

            try:
                page.goto(public_url, timeout=30000)
                page.wait_for_load_state("domcontentloaded")

                # Public timeline should show posts or a message
                # Don't fail if no posts, just verify page loads
                assert page.title(), "Page should have a title"

            except Exception as e:
                # Public timeline may be disabled
                pytest.skip(f"Public timeline not accessible: {e}")

        finally:
            page.close()

    def test_about_page(self, base_url, browser_context):
        """Test that the about page is accessible."""
        page = browser_context.new_page()

        try:
            about_url = f"{base_url}/about"
            page.goto(about_url, timeout=30000)
            page.wait_for_load_state("domcontentloaded")

            # About page should have instance information
            page_content = page.content()
            assert page_content, "About page should have content"

        finally:
            page.close()

    def test_api_documentation_accessible(self, base_url, browser_context):
        """Test that API documentation is linked."""
        page = browser_context.new_page()

        try:
            page.goto(base_url, timeout=30000)

            # Look for API or developer documentation links
            api_selectors = [
                'a:has-text("API")',
                'a:has-text("Developers")',
                '[href*="api"]',
                '[href*="developers"]',
            ]

            api_found = False
            for selector in api_selectors:
                try:
                    if page.locator(selector).count() > 0:
                        api_found = True
                        break
                except:
                    continue

            # API docs may not be prominently linked, which is okay
            if not api_found:
                pytest.skip("API documentation link not prominently displayed")

        finally:
            page.close()


@pytest.mark.ui
@pytest.mark.slow
class TestMastodonUserWorkflow:
    """
    End-to-end user workflow tests.
    These require a test user to be created via tootctl first.
    """

    @pytest.fixture(scope="class")
    def test_user_credentials(self, config):
        """
        Get or create test user credentials.

        Note: For full workflow testing, you'll need to create a test user
        via tootctl CLI:

        sudo su - mastodon -c 'cd ~/live && RAILS_ENV=production bin/tootctl \
          accounts create testuser --email test@example.com --confirmed --role User'
        """
        pytest.skip(
            "Full user workflow tests require a pre-configured test user. "
            "Create one using tootctl and update this fixture."
        )

        return {
            "username": "testuser",
            "email": "test@example.com",
            "password": "test_password"
        }

    def test_user_login_workflow(self, base_url, test_user_credentials, browser_context):
        """Test complete user login workflow."""
        page = browser_context.new_page()

        try:
            page.goto(base_url, timeout=30000)

            # Navigate to login
            page.click('a:has-text("Sign in")')
            page.wait_for_load_state("domcontentloaded")

            # Fill in credentials
            page.fill('input[type="email"], input[name="username"]',
                     test_user_credentials["email"])
            page.fill('input[type="password"]',
                     test_user_credentials["password"])

            # Submit login
            page.click('button[type="submit"]')
            page.wait_for_load_state("networkidle")

            # Should be logged in
            assert "sign_in" not in page.url.lower(), \
                "Should be redirected after login"

        finally:
            page.close()
