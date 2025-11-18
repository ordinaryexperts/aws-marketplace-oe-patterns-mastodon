#!/usr/bin/env python3
"""
AWS Marketplace submission automation script.

Submits a new AMI version to AWS Marketplace using the Catalog API.
Replaces the deprecated Product Load Form (PLF) spreadsheet workflow.
"""

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, Optional, Tuple

import boto3
import yaml


class ChangelogParser:
    """Parse CHANGELOG.md to extract release notes for a specific version."""

    def __init__(self, changelog_path: Path):
        self.changelog_path = changelog_path

    def parse_changelog(self, version: str) -> str:
        """
        Extract release notes for the specified version from CHANGELOG.md.

        Args:
            version: Semantic version string (e.g., "2.3.0")

        Returns:
            Release notes as a multi-line string

        Raises:
            ValueError: If version not found in CHANGELOG
        """
        if not self.changelog_path.exists():
            raise FileNotFoundError(f"CHANGELOG.md not found at {self.changelog_path}")

        with open(self.changelog_path, 'r') as f:
            content = f.read()

        # Look for version header like "# 2.3.0" or "## 2.3.0"
        version_pattern = rf'^#+ {re.escape(version)}$'
        lines = content.split('\n')

        notes = []
        found_version = False
        for i, line in enumerate(lines):
            if re.match(version_pattern, line, re.MULTILINE):
                found_version = True
                # Start collecting lines after the version header
                continue

            if found_version:
                # Stop at next version header
                if line.startswith('#') and not line.startswith('####'):
                    break
                # Collect non-empty lines
                if line.strip():
                    notes.append(line)

        if not found_version:
            raise ValueError(
                f"Version {version} not found in CHANGELOG.md\n"
                f"Expected section header: # {version}"
            )

        if not notes:
            raise ValueError(f"No release notes found for version {version}")

        return '\n'.join(notes).strip()


class ConfigLoader:
    """Load configuration from plf_config.yaml."""

    def __init__(self, config_path: Path):
        self.config_path = config_path

    def load_config(self) -> Dict:
        """
        Load and validate configuration from plf_config.yaml.

        Returns:
            Dictionary with configuration values

        Raises:
            FileNotFoundError: If config file doesn't exist
            ValueError: If required fields are missing
        """
        if not self.config_path.exists():
            raise FileNotFoundError(f"Config file not found at {self.config_path}")

        with open(self.config_path, 'r') as f:
            config = yaml.safe_load(f)

        # Validate required fields
        required_fields = [
            "Product ID",
            "Marketplace Access Role ARN",
            "CloudFormation Parameter Name",
            "Template Base URL",
            "Diagram Base URL",
            "Operating System",
            "Operating System Version",
            "Operating System Username",
            "Recommended Instance Type",
            "Short Description",
            "Full Description",
            "Product Access Instructions",
        ]

        missing = [f for f in required_fields if f not in config or not config[f]]
        if missing:
            raise ValueError(f"Missing required fields in plf_config.yaml: {', '.join(missing)}")

        return config


class MarketplaceSubmitter:
    """Handle AWS Marketplace API interactions."""

    def __init__(self, config: Dict):
        self.config = config
        self.client = boto3.client('marketplace-catalog', region_name='us-east-1')

    def build_payload(self, ami_id: str, version: str, release_notes: str) -> Dict:
        """
        Build the JSON payload for the StartChangeSet API call.

        Args:
            ami_id: AMI ID (e.g., "ami-0e95cf48ef6e3b89f")
            version: Version string (e.g., "2.3.0")
            release_notes: Multi-line release notes string

        Returns:
            Dictionary representing the API payload
        """
        template_url = f"{self.config['Template Base URL']}/{version}/template.yaml"
        diagram_url = f"{self.config['Diagram Base URL']}/mastodon-aws-diagram.png"

        payload = {
            "Catalog": "AWSMarketplace",
            "ChangeSet": [
                {
                    "ChangeType": "AddDeliveryOptions",
                    "Entity": {
                        "Type": "AmiProduct@1.0",
                        "Identifier": self.config["Product ID"]
                    },
                    "DetailsDocument": {
                        "Version": {
                            "VersionTitle": version,
                            "ReleaseNotes": release_notes
                        },
                        "DeliveryOptions": [
                            {
                                "DeliveryOptionTitle": self.config.get("Title", "Ordinary Experts Mastodon Pattern"),
                                "Details": {
                                    "DeploymentTemplateDeliveryOptionDetails": {
                                        "ShortDescription": self.config["Short Description"],
                                        "LongDescription": self.config["Full Description"],
                                        "UsageInstructions": self.config["Product Access Instructions"],
                                        "RecommendedInstanceType": self.config["Recommended Instance Type"],
                                        "ArchitectureDiagram": diagram_url,
                                        "Template": template_url,
                                        "TemplateSources": [
                                            {
                                                "ParameterName": self.config["CloudFormation Parameter Name"],
                                                "AmiSource": {
                                                    "AmiId": ami_id,
                                                    "AccessRoleArn": self.config["Marketplace Access Role ARN"],
                                                    "UserName": self.config["Operating System Username"],
                                                    "OperatingSystemName": self.config["Operating System"],
                                                    "OperatingSystemVersion": self.config["Operating System Version"]
                                                }
                                            }
                                        ]
                                    }
                                }
                            }
                        ]
                    }
                }
            ],
            "Intent": "APPLY"
        }

        return payload

    def submit_changeset(self, payload: Dict) -> str:
        """
        Submit the changeset to AWS Marketplace.

        Args:
            payload: The complete API payload

        Returns:
            Changeset ID

        Raises:
            Exception: If API call fails
        """
        try:
            response = self.client.start_change_set(**payload)
            return response['ChangeSetId']
        except Exception as e:
            raise Exception(f"Failed to submit changeset: {str(e)}")


class ChangesetPoller:
    """Poll changeset status until complete or timeout."""

    def __init__(self, client):
        self.client = client

    def poll_until_complete(
        self,
        changeset_id: str,
        timeout: int = 900,
        interval: int = 30
    ) -> Tuple[str, Optional[str]]:
        """
        Poll changeset status until completion or timeout.

        Args:
            changeset_id: The changeset ID to monitor
            timeout: Maximum time to poll in seconds (default: 15 minutes)
            interval: Polling interval in seconds (default: 30 seconds)

        Returns:
            Tuple of (status, error_message)
            status: SUCCEEDED, FAILED, PREPARING, APPLYING, or CANCELLED
            error_message: Error details if status is FAILED, None otherwise
        """
        elapsed = 0
        while elapsed < timeout:
            try:
                response = self.client.describe_change_set(
                    Catalog='AWSMarketplace',
                    ChangeSetId=changeset_id
                )

                status = response['Status']
                print(f"  [{elapsed}s] Status: {status}")

                if status in ['SUCCEEDED', 'FAILED', 'CANCELLED']:
                    error_msg = None
                    if status == 'FAILED':
                        # Extract error details
                        errors = response.get('FailureDescription', 'Unknown error')
                        error_msg = errors

                    return status, error_msg

                time.sleep(interval)
                elapsed += interval

            except Exception as e:
                print(f"  Error polling status: {e}")
                time.sleep(interval)
                elapsed += interval

        # Timeout reached
        return 'PREPARING', None


def validate_ami_id(ami_id: str) -> bool:
    """Validate AMI ID format."""
    pattern = r'^ami-[a-f0-9]{17}$'
    return bool(re.match(pattern, ami_id))


def validate_version(version: str) -> bool:
    """Validate semantic version format (X.Y.Z)."""
    pattern = r'^\d+\.\d+\.\d+$'
    return bool(re.match(pattern, version))


def run_publish_steps(version: str) -> None:
    """
    Run make publish and make publish-diagram.

    Args:
        version: Template version

    Raises:
        subprocess.CalledProcessError: If make command fails
    """
    print("✓ Validated inputs")
    print("✓ Extracted release notes from CHANGELOG.md")
    print("✓ Loaded configuration from plf_config.yaml")

    # Run make publish
    print("📤 Publishing template to S3...")
    subprocess.run(
        ['make', 'publish', f'TEMPLATE_VERSION={version}'],
        check=True,
        capture_output=False
    )
    print("✓ Published template to S3")

    # Run make publish-diagram
    print("📤 Publishing diagram to S3...")
    subprocess.run(
        ['make', 'publish-diagram', f'TEMPLATE_VERSION={version}'],
        check=True,
        capture_output=False
    )
    print("✓ Published diagram to S3")


def main():
    parser = argparse.ArgumentParser(
        description='Submit new AMI version to AWS Marketplace'
    )
    parser.add_argument('ami_id', help='AMI ID (e.g., ami-0e95cf48ef6e3b89f)')
    parser.add_argument('version', help='Version string (e.g., 2.3.0)')
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Use Intent=VALIDATE instead of APPLY (test mode)'
    )

    args = parser.parse_args()

    # Validate inputs
    if not validate_ami_id(args.ami_id):
        print(f"❌ Error: Invalid AMI ID format: {args.ami_id}")
        print("Expected format: ami-[a-f0-9]{17}")
        sys.exit(1)

    if not validate_version(args.version):
        print(f"❌ Error: Invalid version format: {args.version}")
        print("Expected format: X.Y.Z (e.g., 2.3.0)")
        sys.exit(1)

    try:
        # Setup paths
        repo_root = Path(__file__).parent.parent
        changelog_path = repo_root / "CHANGELOG.md"
        config_path = repo_root / "plf_config.yaml"

        # Parse changelog
        parser_obj = ChangelogParser(changelog_path)
        release_notes = parser_obj.parse_changelog(args.version)

        # Load config
        loader = ConfigLoader(config_path)
        config = loader.load_config()

        # Run publish steps
        run_publish_steps(args.version)

        # Build payload
        submitter = MarketplaceSubmitter(config)
        payload = submitter.build_payload(args.ami_id, args.version, release_notes)

        # Override intent for dry-run
        if args.dry_run:
            payload['Intent'] = 'VALIDATE'
            print("\n🧪 DRY RUN MODE - Using Intent=VALIDATE")

        # Submit changeset
        print(f"\n📤 Submitting changeset...")
        changeset_id = submitter.submit_changeset(payload)
        print(f"✓ Submitted changeset: {changeset_id}")

        # Poll for status
        print(f"\n⏳ Polling changeset status...")
        poller = ChangesetPoller(submitter.client)
        status, error_msg = poller.poll_until_complete(changeset_id)

        # Display results
        print()
        if status == 'SUCCEEDED':
            print(f"✅ Version {args.version} submitted successfully!")
            print(f"\nChangeset ID: {changeset_id}")
            print(f"Status: {status}")
            print(f"\nNext Steps:")
            print(f"- AWS will review your submission")
            print(f"- Track progress: https://aws.amazon.com/marketplace/management/products/")
            print(f"- Check status: aws marketplace-catalog describe-change-set --catalog AWSMarketplace --change-set-id {changeset_id}")
            sys.exit(0)

        elif status == 'FAILED':
            print(f"❌ Changeset FAILED")
            print(f"\nChangeset ID: {changeset_id}")
            print(f"Error: {error_msg}")
            sys.exit(1)

        elif status == 'CANCELLED':
            print(f"⚠️  Changeset was CANCELLED")
            print(f"\nChangeset ID: {changeset_id}")
            sys.exit(1)

        else:
            # Timeout
            print(f"⏳ Changeset still {status} after 15 minutes")
            print(f"\nChangeset ID: {changeset_id}")
            print(f"Status: {status}")
            print(f"\nCheck status with:")
            print(f"aws marketplace-catalog describe-change-set \\")
            print(f"  --catalog AWSMarketplace \\")
            print(f"  --change-set-id {changeset_id}")
            print(f"\nOr view in console:")
            print(f"https://aws.amazon.com/marketplace/management/products/")
            sys.exit(0)

    except FileNotFoundError as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

    except ValueError as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

    except subprocess.CalledProcessError as e:
        print(f"❌ Error: Failed to publish to S3")
        print(f"Command failed with exit code {e.returncode}")
        sys.exit(1)

    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
