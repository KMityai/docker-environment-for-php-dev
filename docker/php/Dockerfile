FROM php:7.4-cli

RUN apt-get update && apt-get -y upgrade && apt-get install -y git \
                                                               libpq-dev \
                                                               zlib1g-dev \
                                                               libxml2-dev \
                                                               libzip-dev \
                                                               unzip

RUN curl -L https://getcomposer.org/download/2.1.6/composer.phar -o /usr/bin/composer \
    && chmod a+x /usr/bin/composer

# sample to install php extension
# RUN docker-php-ext-install -j$(nproc) intl pcntl pdo pgsql pdo_pgsql zip

RUN apt-get clean
