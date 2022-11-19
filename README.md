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
* Route53 - for setting up friend domain names
* ACM - for SSL
* and others...(IAM, Secrets Manager, SSM)

## Architecture Diagram

![AWS Mastodon Architecture Diagram](docs/mastodon-aws-diagram.png)
