#<editor-fold desc="api_platform_php:  Base container for PHP and API platform.">
FROM php:7.4.15-fpm-alpine AS api_platform_php

# Dockerfile: https://github.com/docker-library/php/blob/622b2415c64a96ea00e24ef0cb00f0117ee184f7/7.4/alpine3.11/fpm/Dockerfile
# tini: persistent / runtime deps Adds https://github.com/krallin/tini to help solve
# https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/.  Modern docker-compose
# has the --init flag, which applies tini by default to the entrypoint, but we want to make sure
# we never end up with zombie processes even if the flag is not passed, so we add it directly.
RUN apk add --no-cache \
		acl \
		bash \
		fcgi \
		file \
		gettext \
		git \
		libpng \
		mysql-client \
		openjdk8-jre \
		supervisor \
		tini \
		tree \
		tzdata \
		wkhtmltopdf \
	;
# Install deps.
RUN set -eux; \
	# Temporary requirements.
	apk add --no-cache --virtual .build-deps \
		$PHPIZE_DEPS \
		icu-dev \
		libzip-dev \
		rabbitmq-c-dev \
		mysql-dev \
		zlib-dev \
		# GD temporary requirements:
		freetype-dev \
		libjpeg-turbo-dev \
		libpng-dev \
		# For adding timezone data after build deps cleanup.
		tzdata \
	;
# Configure
RUN docker-php-ext-configure zip; \
	docker-php-ext-configure gd \
		  --with-freetype \
		  --with-jpeg \
		  --target=x86_64 \
		  ;
# Install php and pecl libraries.
# apcu: Most recent version as of: 2020-02-19
RUN docker-php-ext-install -j$(nproc) \
		intl \
		pdo_mysql \
		zip \
		gd \
		sockets \
	; \
	pecl install \
		apcu-5.1.19 \
		amqp \
	; \
	pecl clear-cache; \
	docker-php-ext-enable \
		apcu \
		amqp \
		opcache \
		gd \
	;
# Add runtime dependencies.
RUN runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --no-cache --virtual .api-phpexts-rundeps $runDeps;

# Clean dependencies.
RUN apk del .build-deps

# Add pdftk-java from other docker image.
# See https://github.com/clevyr/docker-pdftk-java for more info.
COPY --from=clevyr/pdftk-java /app/ /usr/local/bin/

# Add composer to the container, but do not install vendor dependencies.  That is
# done outside of the base container.
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
#</editor-fold>

#<editor-fold desc="api_platform_php_xdebug:  Adds xdebug to container build.">
# Example Usage:
# COPY --from=api-platform-php:xdebug-latest
#############
FROM api_platform_php as api_platform_php_xdebug
ARG XDEBUG_VERSION=2.9.6
ENV current_os=linux
# Add build deps for building xdebug.
RUN set -eux  \
	&& apk add --no-cache --virtual .build-deps $PHPIZE_DEPS

# Install and enable xdebug, and copy over the configuration.
RUN pecl install xdebug-$XDEBUG_VERSION \
	&& docker-php-ext-enable xdebug \
	&& php_extension_dir=$(php -r "echo ini_get('extension_dir');") \
	&& [[ -f "${php_extension_dir}/xdebug.so" ]] || { \
		echo "XDebug extension was not installed!"; \
		return 255; \
	};
# Note: xdebug configuration must be added by the project.
#</editor-fold>

#<editor-fold desc="api_platform_php_blackfire:  Adds blackfire to container build.">
# Usage:
# COPY --from=api-platform-php:blackfire-latest
#############
FROM api_platform_php as api_platform_php_blackfire
# Add build deps for building blackfire.
RUN set -eux  \
	&& apk add --no-cache --virtual .build-deps $PHPIZE_DEPS
# Install and enable blackfire, and copy over the configuration.
# Adapted from https://blackfire.io/docs/php/integrations/php-docker
RUN php_extension_dir=$(php -r "echo ini_get('extension_dir');") \
    && version=$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;") \
	&& architecture=$(case $(uname -m) in i386 | i686 | x86) echo "i386" ;; x86_64 | amd64) echo "amd64" ;; aarch64 | arm64 | armv8) echo "arm64" ;; *) echo "amd64" ;; esac) \
	&& curl -A "Docker" -o /tmp/blackfire-probe.tar.gz -D - -L -s https://blackfire.io/api/v1/releases/probe/php/alpine/$architecture/$version \
	&& mkdir -p /tmp/blackfire \
	&& tar zxpf /tmp/blackfire-probe.tar.gz -C /tmp/blackfire \
	&& mv /tmp/blackfire/blackfire-*.so "${php_extension_dir}/blackfire.so" \
	&& rm -rf /tmp/blackfire /tmp/blackfire-probe.tar.gz \
    && [[ -f "${php_extension_dir}/blackfire.so" ]] || { \
		echo "Blackfire extension was not installed!"; \
		exit 255; \
	};
# Note: blackfire configuration must be added by the project.
#</editor-fold>

#<editor-fold desc="api_platform_php_pcov:  Adds PCOV to container build.">
# Usage:
# COPY --from=api-platform-php:pcov-latest
#############
FROM api_platform_php as api_platform_php_pcov
# Add build deps for building PCOV.
RUN set -eux  \
	&& apk add --no-cache --virtual .build-deps $PHPIZE_DEPS
# Install PCOV for a faster alternative for code-coverage tests.
RUN pecl install pcov;
#</editor-fold>
