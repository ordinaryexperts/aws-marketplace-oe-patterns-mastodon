# Unreleased

* Upgrade Mastodon to 4.5.0
* Upgrade Node.js to 24 LTS (required by Mastodon 4.5.0)
* Upgrade Ruby to 3.4.7 (required by Mastodon 4.5.0)
* Upgrade OE Common Constructs to 4.3.0
  * Upgrade Aurora PostgreSQL to 15.13 (was 15.4)
  * Upgrade ElastiCache Redis to 7.0 (was 6.2)

# 2.2.0

* Upgrade Mastodon to 4.4.1
* Adding TaskCat tests
* Increasing root volume size to 40GB
* Upgrade OE Common Constructs to 4.2.6

# 2.1.0

* Upgrade Mastodon to 4.3.1
* Upgrade Ruby to 3.3.5
* Upgrade Ubuntu to 24.04
* Upgrade OE Common Constructs to 4.1.0
* Update REDIS maxmemory-policy to 'noeviction'
* Add hourly cronjob for tootctl search deploy

# 2.0.0

* Upgrade Mastodon to 4.2.8
* Upgrade Node.js to 20
* Upgrade OE Common Constructs to 3.20.0
  * Upgrade Postgresql Aurora Clusters to 15.4 *causes downtime during upgrade*
* Upgrade OE devenv to 2.5.1
  * Upgrade CDK to 2.120.0
  * Update pricing

# 1.3.0

* Updated AWS Calculator link to use smaller default instance types
* Upgrade to Mastodon 4.2.5
* Upgrade to Ruby 3.2.3
* Add weekly cron jobs as described here: https://docs.joinmastodon.org/admin/setup/#cleanup
* python linting cleanup

# 1.2.0

* Upgrade to Mastodon 4.1.2
* Move to shared packer templates
* Add FirstUseInstructions Output
* Upgrade to Ubuntu 22.04
* Assets bucket permission updates

# 1.1.0

* [Fixing apex DNS issue](https://github.com/ordinaryexperts/aws-marketplace-oe-patterns-cdk-common/issues/5)
* Upgrade to Mastodon 4.1.0
* Smaller defaults
* Move from launch configs to launch templates

# 1.0.0

* Initial development
* Upgrade to Mastodon 4.0.2
