#
# AMI hardening
#

# TODO failtoban

# Update the AMI tools before using them
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/building-shared-amis.html#public-amis-update-ami-tools
# More details
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/set-up-ami-tools.html
# http://www.dowdandassociates.com/blog/content/howto-install-aws-cli-amazon-elastic-compute-cloud-ec2-ami-tools/
mkdir -p /tmp/aws
mkdir -p /opt/aws
curl https://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip -o /tmp/aws/ec2-ami-tools.zip
unzip -d /tmp/aws /tmp/aws/ec2-ami-tools.zip
mv /tmp/aws/ec2-ami-tools-* /opt/aws/ec2-ami-tools
rm -f /tmp/aws/ec2-ami-tools.zip
cat <<'EOF' > /etc/profile.d/ec2-ami-tools.sh
export EC2_AMITOOL_HOME=/opt/aws/ec2-ami-tools
export PATH=$PATH:$EC2_AMITOOL_HOME/bin
EOF
cat <<'EOF' >> /etc/bash.bashrc

# https://askubuntu.com/a/1139138
if [ -d /etc/profile.d ]; then
  for i in /etc/profile.d/*.sh; do
    if [ -r $i ]; then
      . $i
    fi
  done
  unset i
fi
EOF

# Disable password-based remote logins for root
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/building-shared-amis.html#public-amis-disable-password-logins-for-root
# install ssh...
apt-get -y install ssh
# Default in Ubuntu already is PermitRootLogin prohibit-password...

# Disable local root access
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/building-shared-amis.html#restrict-root-access
passwd -l root

# Remove SSH host key pairs
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/building-shared-amis.html#remove-ssh-host-key-pairs
shred -u /etc/ssh/*_key /etc/ssh/*_key.pub

# Install public key credentials
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/building-shared-amis.html#public-amis-install-credentials
# Default in Ubuntu already does this...

# Disabling sshd DNS checks (optional)
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/building-shared-amis.html#public-amis-disable-ssh-dns-lookups
# Default in Ubuntu already is UseDNS no

# AWS Marketplace Security Checklist
# https://docs.aws.amazon.com/marketplace/latest/userguide/product-and-ami-policies.html#security
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# apt cleanup
apt-get -y autoremove
apt-get -y update

# https://aws.amazon.com/articles/how-to-share-and-use-public-amis-in-a-secure-manner/
find / -name "authorized_keys" -exec rm -f {} \;
