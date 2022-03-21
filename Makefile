-include common.mk

bootstrap:
	wget -O common.mk https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/develop/common.mk

deploy: build
	docker-compose run -w /code/cdk --rm devenv cdk deploy \
	--require-approval never \
	--parameters VpcId=vpc-00425deda4c835455 \
	--parameters VpcPrivateSubnet1Id=subnet-030c94b9795c6cb96 \
	--parameters VpcPrivateSubnet2Id=subnet-079290412ce63c4d5 \
	--parameters VpcPublicSubnet1Id=subnet-0c2f5d4daa1792c8d \
	--parameters VpcPublicSubnet2Id=subnet-060c39a6ded9e89d7
