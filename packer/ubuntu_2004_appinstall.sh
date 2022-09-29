#
# Mastodon configuration
#  * https://docs.joinmastodon.org/admin/install/
#

# System packages

# Yarn
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list

apt-get update && apt install -y \
  curl imagemagick ffmpeg libpq-dev libxml2-dev libxslt1-dev file git-core \
  g++ libprotobuf-dev protobuf-compiler pkg-config gcc autoconf \
  bison build-essential libssl-dev libyaml-dev libreadline6-dev \
  zlib1g-dev libncurses5-dev libffi-dev libgdbm-dev \
  nginx redis-server redis-tools postgresql postgresql-contrib \
  certbot python-certbot-nginx yarn libidn11-dev libicu-dev libjemalloc-dev

# Node.js
curl -sL https://deb.nodesource.com/setup_12.x | bash -
apt-get install -y nodejs=12*

useradd -m -s /bin/bash mastodon
su - mastodon -c "git clone https://github.com/rbenv/rbenv.git ~/.rbenv"
su - mastodon -c "cd ~/.rbenv && src/configure && make -C src"
su - mastodon -c "echo 'export PATH=\"/home/mastodon/.rbenv/bin:$PATH\"' >> ~/.bashrc"
su - mastodon -c "echo 'eval \"\$(rbenv init - bash)\"' >> ~/.bashrc"
su - mastodon -c "git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build"
su - mastodon -c "HOME=/home/mastodon RUBY_CONFIGURE_OPTS=--with-jemalloc /home/mastodon/.rbenv/bin/rbenv install 2.7.2"
su - mastodon -c "/home/mastodon/.rbenv/bin/rbenv global 2.7.2 && /home/mastodon/.rbenv/shims/gem install bundler --no-document"
su - mastodon -c "git clone https://github.com/mastodon/mastodon.git /home/mastodon/live"

# git tag -l | grep -v 'rc[0-9]*$' | sort -V | tail -n 1
su - mastodon -c "cd /home/mastodon/live && git checkout v3.4.1"
su - mastodon -c "cd /home/mastodon/live && /home/mastodon/.rbenv/shims/bundle config deployment 'true'"
su - mastodon -c "cd /home/mastodon/live && /home/mastodon/.rbenv/shims/bundle config without 'development test'"
su - mastodon -c "cd /home/mastodon/live && /home/mastodon/.rbenv/shims/bundle install -j$(getconf _NPROCESSORS_ONLN)"
su - mastodon -c "cd /home/mastodon/live && yarn install --pure-lockfile"
