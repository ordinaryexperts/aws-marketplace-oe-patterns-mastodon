import os
import subprocess

from aws_cdk import (
    Aws,
    aws_iam,
    CfnMapping,
    CfnOutput,
    CfnParameter,
    Stack
)
from constructs import Construct

from oe_patterns_cdk_common.alb import Alb
from oe_patterns_cdk_common.asg import Asg
from oe_patterns_cdk_common.assets_bucket import AssetsBucket
from oe_patterns_cdk_common.aurora_cluster import AuroraPostgresql
from oe_patterns_cdk_common.db_secret import DbSecret
from oe_patterns_cdk_common.dns import Dns
from oe_patterns_cdk_common.elasticache_cluster import ElasticacheRedis
from oe_patterns_cdk_common.open_search_service import OpenSearchService
from oe_patterns_cdk_common.ses import Ses
from oe_patterns_cdk_common.util import Util
from oe_patterns_cdk_common.vpc import Vpc

if 'TEMPLATE_VERSION' in os.environ:
    template_version = os.environ['TEMPLATE_VERSION']
else:
    try:
        template_version = subprocess.check_output(["git", "describe"]).strip().decode('ascii')
    except:
        template_version = "CICD"


AMI_ID="ami-0f3b34f0e5c608f0d" # ordinary-experts-patterns-mastodon-2.1.0-8-gd40f35c-20250718-0121

class MastodonStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # vpc
        vpc = Vpc(
            self,
            "Vpc"
        )

        self.name_param = CfnParameter(
            self,
            "Name",
            default="Mastodon",
            description="The name of this Mastodon site."
        )

        # dns
        dns = Dns(self, "Dns")

        bucket = AssetsBucket(
            self,
            "AssetsBucket",
            object_ownership_value = "ObjectWriter",
            remove_public_access_block = True
        )

        ses = Ses(
            self,
            "Ses",
            hosted_zone_name=dns.route_53_hosted_zone_name_param.value_as_string,
            additional_iam_user_policies=[bucket.user_policy]
        )

        # db_secret
        db_secret = DbSecret(
            self,
            "DbSecret"
        )

        # redis
        redis = ElasticacheRedis(
            self,
            "Redis",
            custom_parameters={
                "maxmemory-policy": "noeviction"
            },
            vpc=vpc
        )

        # Open Search Service
        oss = OpenSearchService(
            self,
            "OpenSearchService",
            vpc=vpc
        )

        asg_update_secret_policy = aws_iam.CfnRole.PolicyProperty(
            policy_document=aws_iam.PolicyDocument(
                statements=[
                    aws_iam.PolicyStatement(
                        effect=aws_iam.Effect.ALLOW,
                        actions=[
                            "secretsmanager:UpdateSecret"
                        ],
                        resources=[
                            f"arn:{Aws.PARTITION}:secretsmanager:{Aws.REGION}:{Aws.ACCOUNT_ID}:secret:{Aws.STACK_NAME}/instance/credentials-*"
                        ]
                    )
                ]
            ),
            policy_name="AllowUpdateInstanceSecret"
        )

        # asg
        with open("mastodon/user_data.sh") as f:
            user_data = f.read()
        asg = Asg(
            self,
            "Asg",
            additional_iam_role_policies=[asg_update_secret_policy],
            ami_id=AMI_ID,
            default_instance_type="t3.small",
            secret_arns=[db_secret.secret_arn(), ses.secret_arn()],
            use_graviton = False,
            user_data_contents=user_data,
            user_data_variables={
                "AssetsBucketName": bucket.bucket_name(),
                "DbSecretArn": db_secret.secret_arn(),

                "Hostname": dns.hostname(),
                "HostedZoneName": dns.route_53_hosted_zone_name_param.value_as_string,
                "InstanceSecretName": Aws.STACK_NAME + "/instance/credentials"
            },
            vpc=vpc
        )

        alb = Alb(
            self,
            "Alb",
            asg=asg,
            health_check_path = "/health",
            vpc=vpc
        )

        asg.asg.target_group_arns = [ alb.target_group.ref ]

        db = AuroraPostgresql(
            self,
            "Db",
            db_secret=db_secret,
            vpc=vpc
        )
        asg.asg.node.add_dependency(db.db_primary_instance)
        asg.asg.node.add_dependency(ses.generate_smtp_password_custom_resource)

        Util.add_sg_ingress(oss, asg.sg)
        Util.add_sg_ingress(redis, asg.sg)
        Util.add_sg_ingress(db, asg.sg)
        
        dns.add_alb(alb)

        CfnOutput(
            self,
            "FirstUseInstructions",
            description="Instructions for getting started",
            value="""
Create an admin user by connecting to the EC2 instance with SSM Sessions Manager and running this command:

sudo su - mastodon -c 'read -p \"Enter username: \" username && read -p \"Enter email: \" email && cd ~/live && PATH=~/.rbenv/shims:$PATH RAILS_ENV=production bin/tootctl accounts create \"$username\" --email \"$email\" --confirmed --approve --role Owner'
"""
        )

        parameter_groups = [
            {
                "Label": {
                    "default": "Application Config"
                },
                "Parameters": [
                    self.name_param.logical_id
                ]
            }
        ]
        parameter_groups += alb.metadata_parameter_group()
        parameter_groups += bucket.metadata_parameter_group()
        parameter_groups += db_secret.metadata_parameter_group()
        parameter_groups += db.metadata_parameter_group()
        parameter_groups += dns.metadata_parameter_group()
        parameter_groups += redis.metadata_parameter_group()
        parameter_groups += oss.metadata_parameter_group()
        parameter_groups += asg.metadata_parameter_group()
        parameter_groups += ses.metadata_parameter_group()
        parameter_groups += vpc.metadata_parameter_group()

        # AWS::CloudFormation::Interface
        self.template_options.metadata = {
            "OE::Patterns::TemplateVersion": template_version,
            "AWS::CloudFormation::Interface": {
                "ParameterGroups": parameter_groups,
                "ParameterLabels": {
                    self.name_param.logical_id: {
                        "default": "Mastodon Site Name"
                    },
                    **alb.metadata_parameter_labels(),
                    **bucket.metadata_parameter_labels(),
                    **db_secret.metadata_parameter_labels(),
                    **db.metadata_parameter_labels(),
                    **dns.metadata_parameter_labels(),
                    **redis.metadata_parameter_labels(),
                    **oss.metadata_parameter_labels(),
                    **asg.metadata_parameter_labels(),
                    **ses.metadata_parameter_labels(),
                    **vpc.metadata_parameter_labels()
                }
            }
        }
