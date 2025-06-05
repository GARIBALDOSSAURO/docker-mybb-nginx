FROM php:8.3-fpm-alpine

ARG BUILD_AUTHORS
ARG BUILD_DATE
ARG BUILD_SHA512SUM
ARG BUILD_VERSION

LABEL org.opencontainers.image.authors=$BUILD_AUTHORS \
      org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.version=$BUILD_VERSION

RUN set -ex; \
	\
	apk add --no-cache --virtual .build-deps \
		$PHPIZE_DEPS \
		libzip-dev \
		libmemcached-dev \
		freetype-dev \
		libjpeg-turbo-dev \
		libpng-dev \
		libwebp-dev \
		postgresql-dev \
		libxml2-dev \
		oniguruma-dev \
        procps \
	; \
	\
    mkdir -p /var/log/nginx && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log && \
	docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
	docker-php-ext-install -j "$(nproc)" \
		gd \
		mysqli \
		opcache \
		pdo_mysql \
 		pdo_pgsql \
		pgsql \
		zip \
		xml \
		mbstring \
	; \
	pecl channel-update pecl.php.net; \
	pecl install igbinary-3.2.14 memcached-3.2.0 redis-6.0.2; \
	docker-php-ext-enable igbinary memcached redis; \
	\
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --virtual .mybb-phpexts-rundeps $runDeps; \
	apk del .build-deps

RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=12'; \
		echo 'opcache.max_accelerated_files=10000'; \
		echo 'opcache.revalidate_freq=2'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

RUN { \
		echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
		echo 'display_errors = Off'; \
		echo 'display_startup_errors = Off'; \
		echo 'log_errors = On'; \
		echo 'error_log = /dev/stderr'; \
		echo 'log_errors_max_len = 1024'; \
		echo 'ignore_repeated_errors = On'; \
		echo 'ignore_repeated_source = Off'; \
		echo 'html_errors = Off'; \
	} > /usr/local/etc/php/conf.d/error-logging.ini

# RUN { \
#         echo 'session.save_handler = redis'; \
#         echo 'session.save_path = "tcp://redis:6379"'; \
#         echo 'redis.session.locking_enabled = 1'; \
#         echo 'redis.session.lock_expire = 30'; \
#         echo 'redis.session.lock_retries = 10'; \
#         echo 'redis.session.lock_wait_time = 2000'; \
#     } > /usr/local/etc/php/conf.d/redis-session.ini

RUN { \
        echo 'file_uploads=On'; \
        echo 'upload_max_filesize=50M'; \
        echo 'post_max_size=50M'; \
        echo 'max_execution_time=40'; \
        echo 'memory_limit=256M'; \
    } > /usr/local/etc/php/conf.d/mybb-recommended.ini

ENV MYBB_VERSION=$BUILD_VERSION
ENV MYBB_SHA512=$BUILD_SHA512SUM

RUN set -ex; \
	curl -o mybb.tar.gz -fSL "https://github.com/mybb/mybb/archive/refs/tags/mybb_${MYBB_VERSION}.tar.gz"; \
	echo "$MYBB_SHA512 *mybb.tar.gz" | sha512sum -c -; \
	tar -xzf mybb.tar.gz -C /usr/src/; \
	rm mybb.tar.gz; \
	chown -R www-data:www-data /usr/src/mybb-mybb_${MYBB_VERSION}

RUN set -ex; \
	apk add --no-cache nginx busybox-extras curl

RUN rm -f /etc/nginx/http.d/default.conf
RUN mkdir -p /run/nginx

COPY mybb-nginx.conf /etc/nginx/http.d/mybb-nginx.conf
COPY docker-entrypoint.sh /usr/local/bin/
COPY mybb.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/mybb.sh && \
    chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/usr/local/bin/mybb.sh"]