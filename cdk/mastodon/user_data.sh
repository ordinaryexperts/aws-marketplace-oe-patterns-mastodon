#!/bin/bash

# aws cloudwatch
cat <<EOF > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root",
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "metrics": {
    "metrics_collected": {
      "collectd": {
        "metrics_aggregation_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      }
    },
    "append_dimensions": {
      "ImageId": "\${!aws:ImageId}",
      "InstanceId": "\${!aws:InstanceId}",
      "InstanceType": "\${!aws:InstanceType}",
      "AutoScalingGroupName": "\${!aws:AutoScalingGroupName}"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/dpkg.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/dpkg.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/apt/history.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/apt/history.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/cloud-init.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/cloud-init-output.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/auth.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/syslog",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/amazon/ssm/amazon-ssm-agent.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/amazon/ssm/amazon-ssm-agent.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/amazon/ssm/errors.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/amazon/ssm/errors.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "${AsgAppLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/nginx/access.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "${AsgAppLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/nginx/error.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/mastodon-web.log",
            "log_group_name": "${AsgAppLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/mastodon-web.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/mastodon-sidekiq.log",
            "log_group_name": "${AsgAppLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/mastodon-sidekiq.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/mastodon-streaming.log",
            "log_group_name": "${AsgAppLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/mastodon-streaming.log",
            "timezone": "UTC"
          }
        ]
      }
    },
    "log_stream_name": "{instance_id}"
  }
}
EOF
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/ssl/private/nginx-selfsigned.key \
  -out /etc/ssl/certs/nginx-selfsigned.crt \
  -subj '/CN=localhost'

mkdir -p /opt/oe/patterns

# secretsmanager
SECRET_ARN="${DbSecretArn}"
echo $SECRET_ARN > /opt/oe/patterns/secret-arn.txt
SECRET_NAME=$(aws secretsmanager list-secrets --query "SecretList[?ARN=='$SECRET_ARN'].Name" --output text)
echo $SECRET_NAME > /opt/oe/patterns/secret-name.txt

aws ssm get-parameter \
    --name "/aws/reference/secretsmanager/$SECRET_NAME" \
    --with-decryption \
    --query Parameter.Value \
| jq -r . > /opt/oe/patterns/secret.json

DB_PASSWORD=$(cat /opt/oe/patterns/secret.json | jq -r .password)
DB_USERNAME=$(cat /opt/oe/patterns/secret.json | jq -r .username)

/root/check-secrets.py ${AWS::Region} ${InstanceSecretName}

aws ssm get-parameter \
    --name "/aws/reference/secretsmanager/${InstanceSecretName}" \
    --with-decryption \
    --query Parameter.Value \
| jq -r . > /opt/oe/patterns/instance.json

ACCESS_KEY_ID=$(cat /opt/oe/patterns/instance.json | jq -r .access_key_id)
OTP_SECRET=$(cat /opt/oe/patterns/instance.json | jq -r .otp_secret)
SECRET_ACCESS_KEY=$(cat /opt/oe/patterns/instance.json | jq -r .secret_access_key)
SECRET_KEY_BASE=$(cat /opt/oe/patterns/instance.json | jq -r .secret_key_base)
SMTP_PASSWORD=$(cat /opt/oe/patterns/instance.json | jq -r .smtp_password)
VAPID_PRIVATE_KEY=$(cat /opt/oe/patterns/instance.json | jq -r .vapid_private_key)
VAPID_PUBLIC_KEY=$(cat /opt/oe/patterns/instance.json | jq -r .vapid_public_key)
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(cat /opt/oe/patterns/instance.json | jq -r .active_record_encryption_deterministic_key)
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(cat /opt/oe/patterns/instance.json | jq -r .active_record_encryption_key_derivation_salt)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(cat /opt/oe/patterns/instance.json | jq -r .active_record_encryption_primary_key)

cat <<EOF > /home/mastodon/live/.env.production
LOCAL_DOMAIN=${Hostname}
SINGLE_USER_MODE=false
SECRET_KEY_BASE="$SECRET_KEY_BASE"
OTP_SECRET="$OTP_SECRET"
VAPID_PRIVATE_KEY="$VAPID_PRIVATE_KEY"
VAPID_PUBLIC_KEY="$VAPID_PUBLIC_KEY"
DB_HOST=${DbCluster.Endpoint.Address}
DB_PORT=${DbCluster.Endpoint.Port}
DB_NAME=mastodon_production
DB_USER=$DB_USERNAME
DB_PASS="$DB_PASSWORD"
ES_ENABLED=true
ES_HOST=${OpenSearchServiceDomain.DomainEndpoint}
ES_PORT=80
REDIS_HOST=${RedisCluster.RedisEndpoint.Address}
REDIS_PORT=${RedisCluster.RedisEndpoint.Port}
REDIS_PASSWORD=
S3_ENABLED=true
S3_BUCKET=${AssetsBucketName}
S3_PROTOCOL=https
AWS_ACCESS_KEY_ID=$ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$SECRET_ACCESS_KEY
S3_REGION=${AWS::Region}
S3_HOSTNAME=s3.${AWS::Region}.amazonaws.com
SMTP_SERVER=email-smtp.${AWS::Region}.amazonaws.com
SMTP_PORT=587
SMTP_LOGIN=$ACCESS_KEY_ID
SMTP_PASSWORD="$SMTP_PASSWORD"
SMTP_AUTH_METHOD=login
SMTP_OPENSSL_VERIFY_MODE=none
SMTP_FROM_ADDRESS='${Name} <no-reply@${HostedZoneName}>'
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
EOF

sed -i 's|# ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;|ssl_certificate     /etc/ssl/certs/nginx-selfsigned.crt;|' /etc/nginx/sites-available/mastodon
sed -i 's|# ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;|ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;|' /etc/nginx/sites-available/mastodon
sed -i 's/example.com/${Hostname}/g' /etc/nginx/sites-available/mastodon
ln -s /etc/nginx/sites-available/mastodon /etc/nginx/sites-enabled/mastodon
service nginx restart

crontab -l -u mastodon > /tmp/cron
echo "@weekly RAILS_ENV=production /home/mastodon/live/bin/tootctl media remove" >> /tmp/cron
echo "@weekly RAILS_ENV=production /home/mastodon/live/bin/tootctl preview_cards remove" >> /tmp/cron
crontab -u mastodon /tmp/cron
rm /tmp/cron

# this is safe to re-run as it will check if the db has already been setup...
su - mastodon -c "cd /home/mastodon/live && RAILS_ENV=production /home/mastodon/.rbenv/shims/bundle exec rake db:setup"

systemctl restart mastodon-web mastodon-sidekiq mastodon-streaming
success=$?
cfn-signal --exit-code $success --stack ${AWS::StackName} --resource Asg --region ${AWS::Region}
