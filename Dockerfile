# syntax=docker/dockerfile:1
# Образ использует контекст репозитория, поэтому Dockerfile лежит в корне.
# Dockerfile, на который ссылается docker-compose.yaml, — docker/php/Dockerfile.

# syntax=docker/dockerfile:1
FROM php:8.4-cli-trixie AS base

LABEL org.opencontainers.image.title="docker-environment-for-php-dev" \
      org.opencontainers.image.description="CLI-окружение для запуска программ на чистом PHP 8.4"

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY docker/php/php.ini /usr/local/etc/php/php.ini

WORKDIR /app

# Линтеры и анализаторы ставятся в проект через Composer:
#   composer require --dev friendsofphp/php-cs-fixer phpstan/phpstan
# ENTRYPOINT намеренно пустой: контейнер должен принимать любую команду
# (php, composer, sh, линтеры). Запуск по умолчанию задаёт compose.
CMD ["php", "-v"]

FROM base AS dev

# Сборочные пакеты и заголовочные файлы (*-dev) нужны только на этапе сборки
# расширений; удаляются в том же слое, чтобы не раздувать образ.
# ВНИМАНИЕ: --auto-remove тянет по зависимостям runtime-библиотеки (libicu, libpq,
# libzip) — их удаление ломает загрузку расширений. Поэтому в purge перечислены
# строго пакеты из списка установки, без --auto-remove; runtime-зависимости
# (libicu76, libpq5, libzip5, zlib1g) остаются в образе.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        git \
        unzip \
        libicu-dev \
        libpq-dev \
        zlib1g-dev \
        libxml2-dev \
        libzip-dev \
    && docker-php-ext-install -j"$(nproc)" \
        intl \
        pcntl \
        pdo \
        pgsql \
        pdo_pgsql \
        zip \
    && apt-get purge -y \
        libicu-dev \
        libpq-dev \
        zlib1g-dev \
        libxml2-dev \
        libzip-dev \
    && rm -rf /var/lib/apt/lists/* /tmp/pear

RUN groupadd --gid 1000 app \
    && useradd --uid 1000 --gid app --create-home --shell /bin/bash app \
    && mkdir -p /app/composer-home \
    && chown -R app:app /app

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY docker/php/php.ini /usr/local/etc/php/php.ini

COPY docker/php/entrypoint /usr/local/bin/entrypoint

RUN chmod 0755 /usr/local/bin/entrypoint

USER app
