-include common.mk

update-common:
	wget -O common.mk https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/1.6.2/common.mk

deploy: build
	docker compose run -w /code/cdk --rm devenv cdk deploy \
	--require-approval never \
	--parameters AlbCertificateArn=arn:aws:acm:us-east-1:992593896645:certificate/943928d7-bfce-469c-b1bf-11561024580e \
	--parameters AlbIngressCidr=0.0.0.0/0 \
	--parameters AsgAmiIdv230=ami-0aff5be145fae37fe \
	--parameters AsgReprovisionString=20251113.1 \
	--parameters DnsHostname=mastodon-${USER}.dev.patterns.ordinaryexperts.com \
	--parameters DnsRoute53HostedZoneName=dev.patterns.ordinaryexperts.com \
	--parameters OpenSearchServiceCreateServiceLinkedRole="false" \
	--parameters Name="OE Mastodon"

# Integration testing targets
test-integration: build
	docker compose run -w /code/test/integration --rm devenv pytest test_health.py -v

test-integration-health: build
	docker compose run -w /code/test/integration --rm devenv pytest test_health.py::TestMastodonHealth -v

test-integration-infrastructure: build
	docker compose run -w /code/test/integration --rm devenv pytest test_health.py::TestMastodonInfrastructure -v

test-integration-ui: build
	docker compose run -w /code/test/integration --rm devenv pytest test_workflows.py -m ui -v

test-integration-all: build
	docker compose run -w /code/test/integration --rm devenv pytest -v

# AWS Marketplace submission automation
submit-marketplace: build
	docker compose run -w /code --rm devenv python3 /code/scripts/submit-marketplace.py $(AMI_ID) $(TEMPLATE_VERSION)

submit-marketplace-dryrun: build
	docker compose run -w /code --rm devenv python3 /code/scripts/submit-marketplace.py $(AMI_ID) $(TEMPLATE_VERSION) --dry-run
