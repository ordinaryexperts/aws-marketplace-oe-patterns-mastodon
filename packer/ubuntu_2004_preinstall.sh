#!/bin/bash -eux

# wait for cloud-init to be done
if [ ! "$IN_DOCKER" = true ]; then
    cloud-init status --wait
fi

# apt upgrade
export DEBIAN_FRONTEND=noninteractive
apt-get -y update && apt-get -y upgrade

# install helpful utilities
apt-get -y install curl git jq ntp software-properties-common unzip vim wget zip xfsprogs

# install latest CFN utilities
apt-get -y install python3-pip
ln -s /usr/bin/pip3 /usr/bin/pip
pip install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz

# install aws cli
cd /tmp
curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip
unzip awscliv2.zip
./aws/install
cd -

# install CloudWatch agent
cd /tmp
curl https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -o amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb
cd -
# collectd for metrics
apt-get -y install collectd

# install CodeDeploy agent - requires ruby
apt-get -y install ruby
cd /tmp
curl https://aws-codedeploy-us-west-1.s3.us-west-1.amazonaws.com/latest/install -o install
chmod +x ./install
./install auto
cd -

# install efs mount helper - requires git
apt-get -y install binutils git
git clone https://github.com/aws/efs-utils /tmp/efs-utils
cd /tmp/efs-utils
./build-deb.sh
apt-get install -y ./build/amazon-efs-utils*deb
cd -

# install RDS SSL CA for Aurora
mkdir -p /opt/aws/rds
cd /opt/aws/rds
wget https://www.amazontrust.com/repository/AmazonRootCA1.pem
cd -
