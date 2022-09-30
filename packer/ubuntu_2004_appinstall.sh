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
  nginx redis-server redis-tools postgresql-client \
  certbot python3-certbot-nginx libidn11-dev libicu-dev libjemalloc-dev

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
systemctl daemon-reload
systemctl enable mastodon-web mastodon-sidekiq mastodon-streaming

# remove default site
rm -f /etc/nginx/sites-enabled/default
