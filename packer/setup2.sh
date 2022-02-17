#!/bin/bash -eux

useradd -m -s /bin/bash mastodon
su - mastodon -c "git clone https://github.com/rbenv/rbenv.git ~/.rbenv"
su - mastodon -c "cd ~/.rbenv && src/configure && make -C src"
su - mastodon -c "echo 'export PATH=\"/home/mastodon/.rbenv/bin:$PATH\"' >> ~/.bashrc"
su - mastodon -c "echo 'eval \"\$(rbenv init - bash)\"' >> ~/.bashrc"
su - mastodon -c "git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build"
su - mastodon -c "HOME=/home/mastodon RUBY_CONFIGURE_OPTS=--with-jemalloc /home/mastodon/.rbenv/bin/rbenv install 2.7.2"
su - mastodon -c "/home/mastodon/.rbenv/bin/rbenv global 2.7.2 && /home/mastodon/.rbenv/shims/gem install bundler --no-document"
su - mastodon -c "git clone https://github.com/mastodon/mastodon.git /home/mastodon/live"
