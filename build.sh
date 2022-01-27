#!/bin/sh
##
# Builds all images for push to Docker hub.
##
set -e
docker build --target=api_platform_php \
  --tag hottomali/api-platform-php:latest \
  .
docker build --target=api_platform_php_xdebug \
  --tag hottomali/api-platform-php:xdebug-latest \
  .
docker build --target=api_platform_php_blackfire \
  --tag hottomali/api-platform-php:blackfire-latest \
  .
docker build --target=api_platform_php_pcov \
  --tag hottomali/api-platform-php:pcov-latest \
  .
