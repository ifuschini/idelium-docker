FROM composer:2.10.2@sha256:5946476338742b200bb9ff88f8be56275ddae4b3949c72305cb0dbf10cfcb760 AS composer-bin

FROM php:8.5.11-apache-bookworm@sha256:8d79fdbba3e40de52608bedd1602864a1a4c47725203aba992fe5347a7d986e9

ARG API_SOURCE_REVISION=unknown
ARG STACK_SOURCE_REVISION=unknown
LABEL org.opencontainers.image.source="https://github.com/idelium/idelium-api" \
      org.opencontainers.image.revision="${API_SOURCE_REVISION}" \
      io.idelium.stack.revision="${STACK_SOURCE_REVISION}"

RUN apt-get update \
    && apt-get install --yes --no-install-recommends curl libzip-dev supervisor unzip \
    && docker-php-ext-install pdo pdo_mysql mysqli zip \
    && a2enmod rewrite \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer-bin /usr/bin/composer /usr/local/bin/composer
WORKDIR /var/idelium-api
COPY --from=api_source composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --no-progress --prefer-dist --optimize-autoloader --no-scripts
COPY --from=api_source . ./
RUN composer dump-autoload --no-dev --no-interaction --optimize --classmap-authoritative \
    && mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views storage/logs bootstrap/cache /etc/supervisor/logs \
    && chown -R www-data:www-data storage bootstrap/cache

COPY ideliumapi/conf/idelium-httpd.conf /etc/apache2/sites-enabled/000-default.conf
COPY ideliumapi/conf/supervisord.conf /etc/supervisor/supervisord.conf
COPY ideliumapi/script/entrypoint.sh /usr/local/bin/idelium-api-entrypoint
COPY ideliumapi/script/initialize.sh /usr/local/bin/initialize-idelium
RUN chmod 0755 /usr/local/bin/idelium-api-entrypoint /usr/local/bin/initialize-idelium

ENTRYPOINT ["/usr/local/bin/idelium-api-entrypoint"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
