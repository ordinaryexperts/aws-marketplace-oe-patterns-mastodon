#!/usr/bin/env python3
import os

from aws_cdk import core as cdk

# For consistency with TypeScript code, `cdk` is the preferred import name for
# the CDK's core module.  The following line also imports it as `core` for use
# with examples from the CDK Developer's Guide, which are in the process of
# being updated to use `cdk`.  You may delete this import if you don't need it.
from aws_cdk import core

from mastodon.mastodon_stack import MastodonStack


# OE AWS Marketplace Patterns Dev
# arn:aws:organizations::440643590597:account/o-kqeqlsvu0w/992593896645
# ~/.aws/config
# [profile oe-patterns-dev]
# region=us-east-1
# role_arn=arn:aws:iam::992593896645:role/OrganizationAccountAccessRole
# source_profile=oe-prod
env_oe_patterns_dev_us_east_1 = core.Environment(account="992593896645", region="us-east-1")

app = core.App()
MastodonStack(app, "oe-patterns-mastodon-{}".format(os.environ['USER']), env=env_oe_patterns_dev_us_east_1)

app.synth()
