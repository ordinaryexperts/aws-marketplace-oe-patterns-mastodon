# Mastodon on AWS

## Overview

The Ordinary Experts Mastodon AWS Marketplace product is a CloudFormation template with a custom AMI which provisions a production-ready [Mastodon](https://joinmastodon.org/) system. It uses the following AWS services:

* VPC (operator can pass in VPC info or product can create a VPC)
* EC2 - it provisions an Auto Scaling Group for the web application tier
* Aurora Postgres - for persistent database
* ElastiCache Redis - for cache
* OpenSearch Service - for site search
* S3 - to store user-generated binary files (images, etc)
* SES - for sending email
* Route53 - for setting up friendly domain names
* ACM - for SSL
* and others...(IAM, Secrets Manager, SSM)

## Architecture Diagram

![AWS Mastodon Architecture Diagram](docs/mastodon-aws-diagram.png)

## How to deploy

### Pre-work

Before deploying the pattern, you will need the following provisioned in the AWS account you are going to use:

* A hosted zone set up in Route53
* A SSL certificate set up in Amazon Certificate Manager

Also, this pattern optionally sets up a SES Domain Identity with EasyDKIM support based on the DNS Hosted Zone that is provided. If this SES Domain Identity already exists, you can set the `SesCreateDomainIdentity` parameter to `false`.

If you are just starting using SES with this product, then be aware your account will start in "sandbox" mode, and will only send emails to verified email identities. You will need to move to SES "production" mode before having general users in your Mastodon site.

See [this AWS information about the SES sandbox](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html) for more info.

### Deploying

To deploy, subscribe to the product and then launch the provided CloudFormation template.

### Post-deploy setup

After an initial deployment, you can create an initial user using the web interface. You should receive one email to confirm your email address, and then another email after you have confirmed. After that, you can log into the AWS console, navigate to EC2, and connect to the Mastodon instance via the Sessions Manager. Once there, you can make your user an admin user following these instructions:

https://docs.joinmastodon.org/admin/setup/#admin

Here is an example, starting from when SSM Sessions Manager connects to the instance:

    $ sudo su - mastodon
    mastodon@ip-10-0-224-182:~$ cd live
    mastodon@ip-10-0-224-182:~/live$ RAILS_ENV=production bin/tootctl accounts modify dylan --role Owner
    OK
    mastodon@ip-10-0-224-182:~/live$

You should also fill in the server information as described here:

https://docs.joinmastodon.org/admin/setup/#info

You can connect to the EC2 instance via the Sessions Manager in the AWS console.
