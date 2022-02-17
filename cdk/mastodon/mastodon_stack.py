from aws_cdk import (
    core as cdk
)

from oe_patterns_cdk_common import (
    Util,
    Vpc
)

class MastodonStack(cdk.Stack):

    def __init__(self, scope: cdk.Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # vpc
        vpc = Vpc(
            self,
            "Vpc"
        )
