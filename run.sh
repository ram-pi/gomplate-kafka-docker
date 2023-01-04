#!/usr/bin/env bash
GOMPLATE_LOG_FORMAT=json

set -x
gomplate -f confluent.docker-compose.tpl -o docker-compose.yml -d config.yml
gomplate -f ./volumes/prometheus.yml.tpl -o ./volumes/prometheus.yml -d config.yml
