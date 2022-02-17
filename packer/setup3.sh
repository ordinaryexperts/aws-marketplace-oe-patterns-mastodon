#!/bin/bash -eux

# git tag -l | grep -v 'rc[0-9]*$' | sort -V | tail -n 1
su - mastodon -c "cd /home/mastodon/live && git checkout v3.4.1"
su - mastodon -c "cd /home/mastodon/live && /home/mastodon/.rbenv/shims/bundle config deployment 'true'"
su - mastodon -c "cd /home/mastodon/live && /home/mastodon/.rbenv/shims/bundle config without 'development test'"
su - mastodon -c "cd /home/mastodon/live && /home/mastodon/.rbenv/shims/bundle install -j$(getconf _NPROCESSORS_ONLN)"
su - mastodon -c "cd /home/mastodon/live && yarn install --pure-lockfile"
