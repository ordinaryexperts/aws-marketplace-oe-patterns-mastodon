-include common.mk

update-common:
	wget -O common.mk https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/1.5.1/common.mk

deploy: build
	docker compose run -w /code/cdk --rm devenv cdk deploy \
	--require-approval never \
	--parameters AlbCertificateArn=arn:aws:acm:us-east-1:992593896645:certificate/943928d7-bfce-469c-b1bf-11561024580e \
	--parameters AlbIngressCidr=0.0.0.0/0 \
	--parameters AsgAmiId=ami-0f3b34f0e5c608f0d \
	--parameters AsgReprovisionString=20221008.1 \
	--parameters DnsHostname=mastodon-${USER}.dev.patterns.ordinaryexperts.com \
	--parameters DnsRoute53HostedZoneName=dev.patterns.ordinaryexperts.com \
	--parameters OpenSearchServiceCreateServiceLinkedRole="false" \
	--parameters Name="OE Mastodon"
