#!/bin/bash

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/ssl/private/nginx-selfsigned.key \
  -out /etc/ssl/certs/nginx-selfsigned.crt \
  -subj '/CN=localhost'

mkdir -p /opt/oe/patterns/mastodon

# hostname
aws ssm get-parameter \
    --name "${HostnameParameterName}" \
    --with-decryption \
    --query Parameter.Value \
| jq -r . > /opt/oe/patterns/mastodon/hostname.txt

HOSTNAME=$(cat /opt/oe/patterns/mastodon/hostname.txt)
cat <<EOF > /etc/nginx/sites-available/mastodon
map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

upstream backend {
    server 127.0.0.1:3000 fail_timeout=0;
}

upstream streaming {
    server 127.0.0.1:4000 fail_timeout=0;
}

proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=CACHE:10m inactive=7d max_size=1g;

server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name $HOSTNAME;

  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers HIGH:!MEDIUM:!LOW:!aNULL:!NULL:!SHA;
  ssl_prefer_server_ciphers on;
  ssl_session_cache shared:SSL:10m;
  ssl_session_tickets off;

  ssl_certificate     /etc/ssl/certs/nginx-selfsigned.crt;
  ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;

  keepalive_timeout    70;
  sendfile             on;
  client_max_body_size 80m;

  root /home/mastodon/live/public;

  gzip on;
  gzip_disable "msie6";
  gzip_vary on;
  gzip_proxied any;
  gzip_comp_level 6;
  gzip_buffers 16 8k;
  gzip_http_version 1.1;
  gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml image/x-icon;

  add_header Strict-Transport-Security "max-age=31536000" always;

  location / {
    try_files \$uri @proxy;
  }

  location ~ ^/(emoji|packs|system/accounts/avatars|system/media_attachments/files) {
    add_header Cache-Control "public, max-age=31536000, immutable";
    add_header Strict-Transport-Security "max-age=31536000" always;
    try_files \$uri @proxy;
  }

  location /sw.js {
    add_header Cache-Control "public, max-age=0";
    add_header Strict-Transport-Security "max-age=31536000" always;
    try_files \$uri @proxy;
  }

  location @proxy {
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Proxy "";
    proxy_pass_header Server;

    proxy_pass http://backend;
    proxy_buffering on;
    proxy_redirect off;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;

    proxy_cache CACHE;
    proxy_cache_valid 200 7d;
    proxy_cache_valid 410 24h;
    proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
    add_header X-Cached \$upstream_cache_status;
    add_header Strict-Transport-Security "max-age=31536000" always;

    tcp_nodelay on;
  }

  location /api/v1/streaming {
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Proxy "";

    proxy_pass http://streaming;
    proxy_buffering off;
    proxy_redirect off;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;

    tcp_nodelay on;
  }

  error_page 500 501 502 503 504 /500.html;
}
EOF

cat <<EOF > /home/mastodon/live/.env.production
LOCAL_DOMAIN=$HOSTNAME
SINGLE_USER_MODE=false
SECRET_KEY_BASE=TODO
OTP_SECRET=TODO
VAPID_PRIVATE_KEY=TODO
VAPID_PUBLIC_KEY=TODO
DB_HOST=/var/run/postgresql
DB_PORT=5432
DB_NAME=mastodon_production
DB_USER=mastodon
DB_PASS=
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
SMTP_SERVER=localhost
SMTP_PORT=25
SMTP_AUTH_METHOD=none
SMTP_OPENSSL_VERIFY_MODE=none
SMTP_FROM_ADDRESS='Mastodon <notifications@mastodon-dylan.dev.patterns.ordinaryexperts.com>'
EOF

ln -s /etc/nginx/sites-available/mastodon /etc/nginx/sites-enabled/mastodon
service nginx restart

# this is safe to re-reun as it will check if the db has already been setup...
su - mastodon -c "cd /home/mastodon/live && RAILS_ENV=production /home/mastodon/.rbenv/shims/bundle exec rake db:setup"

success=$?
cfn-signal --exit-code $success --stack ${AWS::StackName} --resource Asg --region ${AWS::Region}
