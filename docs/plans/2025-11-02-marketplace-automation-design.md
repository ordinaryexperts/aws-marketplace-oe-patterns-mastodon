# AWS Marketplace Submission Automation Design

**Date:** 2025-11-02
**Status:** Design Complete
**Author:** Dylan (with Claude)

## Overview

Automate the submission of new Mastodon AMI versions to AWS Marketplace using the AWS Marketplace Catalog API. This replaces the deprecated Product Load Form (PLF) spreadsheet approach with a modern API-based workflow.

## Goals

- Reduce manual effort when submitting new versions to AWS Marketplace
- Eliminate error-prone manual form filling and spreadsheet uploads
- Provide immediate feedback on submission validation
- Maintain consistency with existing make-based workflow
- Enable safe retries when AWS requests changes

## Non-Goals (Future Work)

- Automated triggers (git tags, CI/CD) - keeping manual control for now
- Updating product metadata (descriptions, pricing) - version updates only
- Restricting old versions - manual process for now
- Multi-region AMI copying automation

## Background

Currently, we use `make gen-plf` and `make plf` to generate a PLF spreadsheet, which is then manually uploaded through the AWS Marketplace Management Portal. AWS has deprecated this approach in favor of:
1. Online web forms (still manual)
2. AWS Marketplace Catalog API (what we're implementing)

Our product is a CloudFormation template + Custom AMI listing. Each new version requires:
- New AMI ID
- CloudFormation template uploaded to S3
- Architecture diagram uploaded to S3
- Version number and release notes
- Product metadata (descriptions, instance types, etc.)

## Design Decisions

### Trigger Mechanism: Manual via Make

**Decision:** Manual `make submit-marketplace` command

**Rationale:** We need flexibility to iterate based on AWS Marketplace feedback before finalizing releases. We don't complete the release branch until AWS approves the submission, and sometimes changes are needed.

**Rejected Alternatives:**
- Git tag automation - too rigid, releases aren't final until AWS approves
- GitHub Actions - adds unnecessary complexity for a manual process
- After-test automation - same rigidity issue as git tags

### Input Parameters

**Decision:** `make submit-marketplace AMI_ID=ami-xxx TEMPLATE_VERSION=2.3.0`

**Rationale:** Matches existing pattern used by `make plf`. AMI ID must be explicit (it's the main artifact). Version drives everything else (release notes, S3 paths).

**Rejected Alternatives:**
- Auto-discover AMI from mastodon_stack.py - error-prone, AMI might not match what was actually tested
- Interactive prompts - breaks scriptability and automation potential
- Config file for all inputs - too much indirection

### Workflow Automation

**Decision:** Fully automated sequence in one command

**Workflow:**
1. Validate inputs (AMI format, version format)
2. Extract release notes from CHANGELOG.md
3. Load metadata from plf_config.yaml
4. Run `make publish TEMPLATE_VERSION=X` (upload template to S3)
5. Run `make publish-diagram TEMPLATE_VERSION=X` (upload diagram to S3)
6. Build JSON payload for Marketplace API
7. Call `start-change-set` with AddDeliveryOptions
8. Poll `describe-change-set` every 30s for up to 15 minutes
9. Display result: SUCCEEDED, FAILED (with errors), or PENDING

**Rationale:** Ensures template and diagram are always published before API submission. Eliminates possibility of forgetting steps. Provides immediate feedback on validation errors.

**Rejected Alternatives:**
- Require manual pre-publish - easy to forget, causes submission failures
- Smart detection of existing S3 files - adds complexity, idempotent overwrites are safe
- Prompt before publishing - breaks flow, adds friction

### Error Handling Strategy

**Decision:** Idempotent design - safe to retry the same command

**Behavior:**
- `make publish` overwrites template in S3 (version is in path, safe)
- `make publish-diagram` overwrites diagram in S3 (safe)
- AWS Marketplace API rejects duplicate version titles (safe guard)
- All failures exit with clear error messages and non-zero status

**Rationale:** When AWS requests changes, you fix the issue and re-run the exact same command. No cleanup needed, no intermediate state to manage.

**Rejected Alternatives:**
- Rollback on failure - adds complexity, S3 overwrites are harmless
- Stop on first error without cleanup - what we're doing, simpler
- Continue with warnings - too risky, fail fast is better

### Release Notes Extraction

**Decision:** Parse CHANGELOG.md and match exact version number (e.g., `# 2.3.0`)

**Behavior:**
- Find section header matching `# {TEMPLATE_VERSION}`
- Extract all bullet points until next version header or end of file
- Fail with clear error if version not found
- Format as multi-line string for API submission

**Rationale:** Precise and unambiguous. Works whether submitting current version or re-submitting older version. Forces proper CHANGELOG hygiene.

**Rejected Alternatives:**
- Always use "Unreleased" section - doesn't work for resubmissions
- Use "Unreleased" with fallback to version - ambiguous, error-prone
- Manual parameter - defeats purpose of automation
- Generic fallback text - encourages lazy documentation

### Implementation Approach

**Decision:** New Python script `scripts/submit-marketplace.py`

**Rationale:** Clean separation from legacy PLF code. Python is already in devenv container, has good AWS SDK (boto3), and handles JSON naturally.

**Rejected Alternatives:**
- Extend existing plf.py - mixes old and new approaches
- Shell script with AWS CLI and jq - harder to maintain, error-prone JSON construction
- Standalone Go/Rust binary - overkill, adds build complexity

## Technical Architecture

### Component Structure

**scripts/submit-marketplace.py:**

```
ChangelogParser
  - parse_changelog(version) -> release_notes
  - Regex-based markdown parsing
  - Fail if version not found

ConfigLoader
  - load_config() -> dict
  - Parse plf_config.yaml
  - Extract Product ID, Role ARN, OS details, etc.

MarketplaceSubmitter
  - build_payload(ami_id, version, release_notes, config) -> dict
  - submit_changeset(payload) -> changeset_id
  - Uses boto3 marketplace-catalog client

ChangesetPoller
  - poll_until_complete(changeset_id, timeout=900) -> status
  - Poll every 30 seconds
  - Handle states: PREPARING, APPLYING, SUCCEEDED, FAILED

main()
  - Validate inputs
  - Run publish steps (subprocess)
  - Orchestrate components
  - Display results
```

### Configuration Changes

**plf_config.yaml additions:**

```yaml
# AWS Marketplace API Configuration (add at top)
"Marketplace Access Role ARN": "arn:aws:iam::123456789012:role/AwsMarketplaceAmiIngestion"
"CloudFormation Parameter Name": "AsgAmiIdv230"
"Template Base URL": "https://ordinary-experts-aws-marketplace-pattern-artifacts.s3.amazonaws.com/mastodon"
"Diagram Base URL": "https://ordinaryexperts.com/img/products/mastodon-pattern"
```

**Makefile addition:**

```makefile
submit-marketplace: build
	docker compose run -w /code --rm devenv \
		bash -c "make publish TEMPLATE_VERSION=$(TEMPLATE_VERSION) && \
		         make publish-diagram TEMPLATE_VERSION=$(TEMPLATE_VERSION) && \
		         python3 scripts/submit-marketplace.py $(AMI_ID) $(TEMPLATE_VERSION)"
```

### AWS Marketplace API Payload

**API Call:** `marketplace-catalog:StartChangeSet`

**Payload Structure:**

```json
{
  "Catalog": "AWSMarketplace",
  "ChangeSet": [
    {
      "ChangeType": "AddDeliveryOptions",
      "Entity": {
        "Type": "AmiProduct@1.0",
        "Identifier": "d0a98067-9a26-440a-858e-00193a953934"
      },
      "DetailsDocument": {
        "Version": {
          "VersionTitle": "2.3.0",
          "ReleaseNotes": "* Upgrade Mastodon to 4.4.8\n* Upgrade Ruby to 3.4.4\n..."
        },
        "DeliveryOptions": [
          {
            "DeliveryOptionTitle": "Ordinary Experts Mastodon Pattern",
            "Details": {
              "DeploymentTemplateDeliveryOptionDetails": {
                "ShortDescription": "<from plf_config.yaml>",
                "LongDescription": "<from plf_config.yaml>",
                "UsageInstructions": "<from plf_config.yaml>",
                "RecommendedInstanceType": "m5.xlarge",
                "ArchitectureDiagram": "https://.../mastodon-aws-diagram.png",
                "Template": "https://.../2.3.0/template.yaml",
                "TemplateSources": [
                  {
                    "ParameterName": "AsgAmiIdv230",
                    "AmiSource": {
                      "AmiId": "ami-0e95cf48ef6e3b89f",
                      "AccessRoleArn": "arn:aws:iam::...:role/AwsMarketplaceAmiIngestion",
                      "UserName": "ubuntu",
                      "OperatingSystemName": "UBUNTU",
                      "OperatingSystemVersion": "24.04"
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
```

**Key Points:**
- Only one delivery option: CloudFormation template + Custom AMI
- Template and diagram URLs use version in path (e.g., `/2.3.0/template.yaml`)
- AMI source details must match actual AMI (validated by AWS)
- Intent "APPLY" for real submission, "VALIDATE" for dry-run

### Input Validation

**AMI ID:**
- Pattern: `ami-[a-f0-9]{17}`
- Must exist and be accessible to AWS Marketplace role

**Version:**
- Pattern: Semantic version `X.Y.Z` (e.g., `2.3.0`)
- Must exist as header in CHANGELOG.md
- Must not be duplicate (AWS will reject)

**Config:**
- All required fields present in plf_config.yaml
- Role ARN valid format
- URLs accessible

### Error Handling

**Validation Failures:**
```
❌ Error: Invalid AMI ID format: ami-123
Expected format: ami-[a-f0-9]{17}
```

```
❌ Error: Version 2.3.0 not found in CHANGELOG.md
Expected section header: # 2.3.0
```

**Publish Failures:**
```
❌ Error: Failed to publish template to S3
make publish TEMPLATE_VERSION=2.3.0 failed with exit code 1

<stderr output>
```

**API Failures:**
```
❌ Error: Changeset submission failed
AWS Error: InvalidParameterException
Message: Version 2.3.0 already exists for this product
```

**Success Output:**
```
✓ Validated inputs
✓ Extracted release notes from CHANGELOG.md
✓ Loaded configuration from plf_config.yaml
✓ Published template to S3
✓ Published diagram to S3
✓ Submitted changeset: cs-abc123def456

⏳ Polling changeset status...
  [30s] Status: PREPARING
  [60s] Status: PREPARING
  [90s] Status: SUCCEEDED

✅ Version 2.3.0 submitted successfully!

Changeset ID: cs-abc123def456
Status: SUCCEEDED

Next Steps:
- AWS will review your submission
- Track progress: https://aws.amazon.com/marketplace/management/products/
- Check status: aws marketplace-catalog describe-change-set --catalog AWSMarketplace --change-set-id cs-abc123def456
```

**Timeout Output:**
```
⏳ Changeset still PREPARING after 15 minutes

Changeset ID: cs-abc123def456
Status: PREPARING

Check status with:
aws marketplace-catalog describe-change-set \
  --catalog AWSMarketplace \
  --change-set-id cs-abc123def456

Or view in console:
https://aws.amazon.com/marketplace/management/products/
```

### Polling Behavior

**Poll Interval:** 30 seconds
**Timeout:** 15 minutes (30 polls)
**Changeset States:**

- **PREPARING** - AWS validating the changeset (typical: 2-5 minutes)
- **APPLYING** - AWS processing the change (rarely seen, usually instant)
- **SUCCEEDED** - Validation passed, submitted for review (goal state)
- **FAILED** - Validation failed, show error details
- **CANCELLED** - Someone cancelled it manually

**Rationale:** 30 seconds is frequent enough for quick feedback on validation errors, but not so aggressive as to hammer AWS APIs. 15 minute timeout catches slow validations while not hanging forever.

## Dependencies

**Python Packages (already in devenv):**
- boto3 - AWS SDK for Python
- PyYAML - YAML parsing
- Standard library: subprocess, argparse, re, time, sys, json

**External Tools:**
- AWS CLI credentials via AWS_PROFILE
- make (for publish steps)
- S3 bucket for template/diagram hosting

**AWS Permissions Required:**
- `marketplace-catalog:StartChangeSet`
- `marketplace-catalog:DescribeChangeSet`
- S3 write permissions for artifacts bucket
- IAM role for AWS Marketplace AMI ingestion

## Testing Strategy

**Unit Tests:**
- ChangelogParser with various CHANGELOG formats
- ConfigLoader with missing/invalid YAML
- Payload builder with different configurations
- Input validation edge cases

**Integration Tests:**
- Dry-run mode: Use `Intent: "VALIDATE"` to test without real submission
- Submit test version to verify end-to-end flow
- Test duplicate version rejection
- Test missing CHANGELOG entry

**Manual Testing:**
- Run against actual product during next release
- Verify AWS Marketplace shows correct version details
- Confirm template downloads from S3 work
- Test retry after AWS requests changes

## Rollout Plan

**Phase 1: Implementation (This Week)**
1. Create `scripts/submit-marketplace.py`
2. Update `plf_config.yaml` with new fields
3. Add `submit-marketplace` target to Makefile
4. Test with dry-run mode (Intent: "VALIDATE")

**Phase 2: Validation (Next Release)**
1. Use for actual submission of next version
2. Verify AWS Marketplace displays correctly
3. Document any issues or edge cases
4. Refine based on feedback

**Phase 3: Deprecation (Future)**
1. Mark `gen-plf` and `plf` targets as deprecated
2. Remove PLF-related scripts after 2-3 successful releases
3. Update documentation to reference new workflow

## Future Enhancements

**Not in initial scope, but possible later:**

1. **Metadata Updates** - Use `UpdateInformation` change type to update product descriptions, highlights, pricing
2. **Version Restriction** - Use `RestrictDeliveryOptions` to deprecate old versions
3. **CI/CD Integration** - GitHub Actions workflow for automated submission after tests pass
4. **Multi-Region AMI** - Automate AMI copying and update region availability
5. **Dry-Run Flag** - `make submit-marketplace-dryrun` for validation without submission
6. **Status Checking** - `make marketplace-status CHANGESET_ID=cs-xxx` to check existing changesets

## References

- [AWS Marketplace Catalog API - AMI Products](https://docs.aws.amazon.com/marketplace-catalog/latest/api-reference/ami-products.html)
- [AWS Blog: Automating AMI Listings](https://aws.amazon.com/blogs/awsmarketplace/automating-updates-to-your-single-ami-listings-in-aws-marketplace-with-catalog-api/)
- [aws-marketplace-api-samples GitHub](https://github.com/aws-samples/aws-marketplace-api-samples)
- [Current PLF-based workflow](../CLAUDE.md#product-listing-framework-plf)

## Success Metrics

- Time to submit new version: < 5 minutes (vs. 20-30 minutes manual)
- Immediate validation feedback (vs. hours/days waiting for AWS)
- Zero submission errors due to missing fields or incorrect formats
- Successful adoption for 3+ consecutive releases
