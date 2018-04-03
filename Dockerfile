FROM php:7.1-apache

# Required Components
# @see https://secure.phabricator.com/book/phabricator/article/installation_guide/#installing-required-comp
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    git \
  && rm -rf /var/lib/apt/lists/*

# install the PHP extensions we need
RUN set -ex; \
	\
	if command -v a2enmod; then \
		a2enmod rewrite; \
	fi; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libcurl4-gnutls-dev \
	; \
	\
	docker-php-ext-install -j "$(nproc)" \
    opcache \
		mbstring \
		iconv \
		mysqli \
		curl \
		pcntl \
	; \
	\
  # reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
		| awk '/=>/ { print $3 }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

RUN pecl channel-update pecl.php.net \
  && pecl install apcu \
  && docker-php-ext-enable apcu

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
  		echo 'opcache.memory_consumption=128'; \
  		echo 'opcache.interned_strings_buffer=8'; \
  		echo 'opcache.max_accelerated_files=4000'; \
  		echo 'opcache.revalidate_freq=60'; \
  		echo 'opcache.fast_shutdown=1'; \
  		echo 'opcache.enable_cli=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini

ENV APACHE_DOCUMENT_ROOT /var/www/phabricator/webroot

RUN { \
  		echo '<VirtualHost *:80>'; \
  		echo 'DocumentRoot ${APACHE_DOCUMENT_ROOT}'; \
  		echo 'RewriteEngine on'; \
  		echo 'RewriteRule ^(.*)$ /index.php?__path__=$1 [B,L,QSA]'; \
  		echo '</VirtualHost>'; \
    } > /etc/apache2/sites-available/000-default.conf

COPY ./ /var/www

WORKDIR /var/www

RUN git submodule update --init --recursive

ENV PATH "$PATH:/var/www/phabricator/bin"