SCRIPT_VERSION=1.6.0
SCRIPT_PREINSTALL=ubuntu_2204_2404_preinstall.sh
SCRIPT_POSTINSTALL=ubuntu_2204_2404_postinstall.sh

# preinstall steps
curl -O "https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/$SCRIPT_VERSION/packer_provisioning_scripts/$SCRIPT_PREINSTALL"
chmod +x $SCRIPT_PREINSTALL
./$SCRIPT_PREINSTALL
rm $SCRIPT_PREINSTALL

#
# Mastodon configuration
#  * https://docs.joinmastodon.org/admin/install/
#

RUBY_VERSION=3.4.4
MASTODON_VERSION=4.4.1

apt-get update && apt-get upgrade -y

# prereqs
apt-get install -y curl wget gnupg apt-transport-https lsb-release ca-certificates

# Node.js
curl -sL https://deb.nodesource.com/setup_20.x | bash -

# System packages
apt install -y \
  imagemagick ffmpeg libvips-tools libpq-dev libxml2-dev libxslt1-dev file git-core \
  g++ libprotobuf-dev protobuf-compiler pkg-config gcc autoconf \
  bison build-essential libssl-dev libyaml-dev libreadline6-dev \
  zlib1g-dev libncurses5-dev libffi-dev libgdbm-dev \
  nginx nodejs redis-tools postgresql-client \
  libidn11-dev libicu-dev libjemalloc-dev

# yarn
corepack enable

adduser --disabled-password mastodon
su - mastodon -c "git clone https://github.com/rbenv/rbenv.git ~/.rbenv"
su - mastodon -c "cd ~/.rbenv && src/configure && make -C src"
su - mastodon -c "echo 'export PATH=\"/home/mastodon/.rbenv/bin:$PATH\"' >> ~/.bashrc"
su - mastodon -c "echo 'eval \"\$(rbenv init - bash)\"' >> ~/.bashrc"
su - mastodon -c "git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build"
su - mastodon -c "HOME=/home/mastodon RUBY_CONFIGURE_OPTS=--with-jemalloc /home/mastodon/.rbenv/bin/rbenv install $RUBY_VERSION"
su - mastodon -c "/home/mastodon/.rbenv/bin/rbenv global $RUBY_VERSION && /home/mastodon/.rbenv/shims/gem install bundler --no-document"
su - mastodon -c "git clone https://github.com/mastodon/mastodon.git /home/mastodon/live"

# git tag -l | grep -v 'rc[0-9]*$' | sort -V | tail -n 1
su - mastodon -c "cd /home/mastodon/live && git checkout v$MASTODON_VERSION"
su - mastodon -c "cd /home/mastodon/live && /home/mastodon/.rbenv/shims/bundle config deployment 'true'"
su - mastodon -c "cd /home/mastodon/live && /home/mastodon/.rbenv/shims/bundle config without 'development test'"
su - mastodon -c "cd /home/mastodon/live && /home/mastodon/.rbenv/shims/bundle install -j$(getconf _NPROCESSORS_ONLN)"
su - mastodon -c "cd /home/mastodon/live && yarn install"

# precompile assets
su - mastodon -c "cd /home/mastodon/live && SECRET_KEY_BASE_DUMMY=1 RAILS_ENV=production /home/mastodon/.rbenv/shims/bundle exec rake assets:precompile && yarn cache clean"

# set up services
cp /home/mastodon/live/dist/mastodon-*.service /etc/systemd/system/
# enable log files
# https://stackoverflow.com/a/43830129
sed -i '/^\[Service\].*/a SyslogIdentifier=mastodon-web' /etc/systemd/system/mastodon-web.service
sed -i '/^\[Service\].*/a SyslogIdentifier=mastodon-sidekiq' /etc/systemd/system/mastodon-sidekiq.service
sed -i '/^\[Service\].*/a SyslogIdentifier=mastodon-streaming' /etc/systemd/system/mastodon-streaming.service
cat <<EOF > /etc/rsyslog.d/60-mastodon.conf
:programname, isequal, "mastodon-web" /var/log/mastodon-web.log
:programname, isequal, "mastodon-sidekiq" /var/log/mastodon-sidekiq.log
:programname, isequal, "mastodon-streaming" /var/log/mastodon-streaming.log
EOF

# set up crons
crontab -l -u mastodon > /tmp/cron
echo "@weekly RAILS_ENV=production PATH=/home/mastodon/.rbenv/shims:$PATH /home/mastodon/live/bin/tootctl media remove >> /home/mastodon/live/log/crons.log 2>&1" >> /tmp/cron
echo "@weekly RAILS_ENV=production PATH=/home/mastodon/.rbenv/shims:$PATH /home/mastodon/live/bin/tootctl preview_cards remove >> /home/mastodon/live/log/crons.log 2>&1" >> /tmp/cron
echo "@hourly RAILS_ENV=production PATH=/home/mastodon/.rbenv/shims:$PATH /home/mastodon/live/bin/tootctl search deploy --only=instances accounts tags statuses public_statuses >> /home/mastodon/live/log/crons.log 2>&1" >> /tmp/cron
crontab -u mastodon /tmp/cron
rm /tmp/cron

# log rotation
cat <<EOF > /etc/logrotate.d/mastodon
/home/mastodon/live/log/crons.log {
  size 10M
  copytruncate
  su mastodon mastodon
  rotate 4
}
/var/log/mastodon-web.log {
  size 10M
  copytruncate
  su root root
  rotate 4
}
/var/log/mastodon-sidekiq.log {
  size 10M
  copytruncate
  su root root
  rotate 4
}
/var/log/mastodon-streaming.log {
  size 10M
  copytruncate
  su root root
  rotate 4
}
EOF

systemctl daemon-reload
systemctl enable mastodon-web mastodon-sidekiq mastodon-streaming

# install custom rake task for generating secrets at initial provisioning
cat <<EOF > /home/mastodon/live/lib/tasks/oe.rake
require 'json'

namespace :oe do
  desc 'Generate Secrets'
  task :generate_secrets do
    env = {}

    %w(SECRET_KEY_BASE OTP_SECRET).each do |key|
      env[key] = SecureRandom.hex(64)
    end

    vapid_key = Webpush.generate_key
    env['VAPID_PRIVATE_KEY'] = vapid_key.private_key
    env['VAPID_PUBLIC_KEY']  = vapid_key.public_key

    %w(
      ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
      ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
      ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
    ).each do |key|
      env[key] = SecureRandom.alphanumeric(32)
    end

    puts env.to_json
  end
end
EOF
chown mastodon:mastodon /home/mastodon/live/lib/tasks/oe.rake
chmod 664 /home/mastodon/live/lib/tasks/oe.rake

pip install boto3 --break-system-packages
cat <<EOF > /root/check-secrets.py
#!/usr/bin/env python3

import boto3
import json
import subprocess
import sys

region_name = sys.argv[1]
secret_name = sys.argv[2]

client = boto3.client("secretsmanager", region_name=region_name)
response = client.list_secrets(
  Filters=[{"Key": "name", "Values": [secret_name]}]
)
arn = response["SecretList"][0]["ARN"]
response = client.get_secret_value(
  SecretId=arn
)
current_secret = json.loads(response["SecretString"])
secrets_already_generated = True
if not 'secret_key_base' in current_secret:
  secrets_already_generated = False
  cmd = 'su - mastodon -c "cd /home/mastodon/live && RAILS_ENV=production PATH=/home/mastodon/.rbenv/shims:$PATH bundle exec rake oe:generate_secrets"'
  output = subprocess.run(cmd, stdout=subprocess.PIPE, shell=True).stdout.decode('utf-8')
  secrets = json.loads(output)
  current_secret['secret_key_base']   = secrets['SECRET_KEY_BASE']
  current_secret['otp_secret']        = secrets['OTP_SECRET']
  current_secret['vapid_public_key']  = secrets['VAPID_PUBLIC_KEY']
  current_secret['vapid_private_key'] = secrets['VAPID_PRIVATE_KEY']
  client.update_secret(
    SecretId=arn,
    SecretString=json.dumps(current_secret)
  )
# added in Mastodon 4.3.0
if not 'active_record_encryption_deterministic_key' in current_secret:
  secrets_already_generated = False
  cmd = 'su - mastodon -c "cd /home/mastodon/live && RAILS_ENV=production PATH=/home/mastodon/.rbenv/shims:$PATH bundle exec rake oe:generate_secrets"'
  output = subprocess.run(cmd, stdout=subprocess.PIPE, shell=True).stdout.decode('utf-8')
  secrets = json.loads(output)
  current_secret['active_record_encryption_deterministic_key']   = secrets['ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY']
  current_secret['active_record_encryption_key_derivation_salt'] = secrets['ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT']
  current_secret['active_record_encryption_primary_key']         = secrets['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY']
  client.update_secret(
    SecretId=arn,
    SecretString=json.dumps(current_secret)
  )
if secrets_already_generated:
  print('Secrets already generated - no action needed.')
EOF
chown root:root /root/check-secrets.py
chmod 744 /root/check-secrets.py

# remove default site
rm -f /etc/nginx/sites-enabled/default

# setup nginx config
cp /home/mastodon/live/dist/nginx.conf /etc/nginx/sites-available/mastodon
usermod -a -G mastodon www-data

# post install steps
curl -O "https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/$SCRIPT_VERSION/packer_provisioning_scripts/$SCRIPT_POSTINSTALL"
chmod +x "$SCRIPT_POSTINSTALL"
./"$SCRIPT_POSTINSTALL"
rm $SCRIPT_POSTINSTALL
