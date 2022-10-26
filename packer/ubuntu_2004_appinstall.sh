#
# Mastodon configuration
#  * https://docs.joinmastodon.org/admin/install/
#

apt-get update && apt-get upgrade -y

# prereqs
apt-get install -y curl wget gnupg apt-transport-https lsb-release ca-certificates

# Node.js
curl -sL https://deb.nodesource.com/setup_16.x | bash -

# System packages
apt-get install -y \
  imagemagick ffmpeg libpq-dev libxml2-dev libxslt1-dev file git-core \
  g++ libprotobuf-dev protobuf-compiler pkg-config nodejs gcc autoconf \
  bison build-essential libssl-dev libyaml-dev libreadline6-dev \
  zlib1g-dev libncurses5-dev libffi-dev libgdbm-dev \
  nginx redis-tools postgresql-client \
  libidn11-dev libicu-dev libjemalloc-dev

# yarn
corepack enable
yarn set version stable

useradd -m -s /bin/bash mastodon
su - mastodon -c "git clone https://github.com/rbenv/rbenv.git ~/.rbenv"
su - mastodon -c "cd ~/.rbenv && src/configure && make -C src"
su - mastodon -c "echo 'export PATH=\"/home/mastodon/.rbenv/bin:$PATH\"' >> ~/.bashrc"
su - mastodon -c "echo 'eval \"\$(rbenv init - bash)\"' >> ~/.bashrc"
su - mastodon -c "git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build"
su - mastodon -c "HOME=/home/mastodon RUBY_CONFIGURE_OPTS=--with-jemalloc /home/mastodon/.rbenv/bin/rbenv install 3.0.3"
su - mastodon -c "/home/mastodon/.rbenv/bin/rbenv global 3.0.3 && /home/mastodon/.rbenv/shims/gem install bundler --no-document"
su - mastodon -c "git clone https://github.com/mastodon/mastodon.git /home/mastodon/live"

# git tag -l | grep -v 'rc[0-9]*$' | sort -V | tail -n 1
su - mastodon -c "cd /home/mastodon/live && git checkout v3.5.3"
su - mastodon -c "cd /home/mastodon/live && /home/mastodon/.rbenv/shims/bundle config deployment 'true'"
su - mastodon -c "cd /home/mastodon/live && /home/mastodon/.rbenv/shims/bundle config without 'development test'"
su - mastodon -c "cd /home/mastodon/live && /home/mastodon/.rbenv/shims/bundle install -j$(getconf _NPROCESSORS_ONLN)"
su - mastodon -c "cd /home/mastodon/live && yarn install --pure-lockfile"

# precompile assets
su - mastodon -c "cd /home/mastodon/live && OTP_SECRET=precompile_placeholder SECRET_KEY_BASE=precompile_placeholder RAILS_ENV=production /home/mastodon/.rbenv/shims/bundle exec rake assets:precompile && yarn cache clean"

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

# log rotation
cat <<EOF > /etc/logrotate.d/mastodon
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

# set up crons
cat <<EOF > /etc/cron.d/mastodon
0 0 * * 0 mastodon RAILS_ENV=production /home/mastodon/live/bin/tootctl media remove
0 0 * * 0 mastodon RAILS_ENV=production /home/mastodon/live/bin/tootctl preview_cards remove
EOF

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

    puts env.to_json
  end
end
EOF
chown mastodon:mastodon /home/mastodon/live/lib/tasks/oe.rake
chmod 664 /home/mastodon/live/lib/tasks/oe.rake

# remove default site
rm -f /etc/nginx/sites-enabled/default
