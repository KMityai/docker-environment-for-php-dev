---
name: docker-php
description: >-
  Работа с Docker-окружением этого проекта (сервис php, образ PHP 8.4 CLI):
  запуск PHP-скриптов, Composer и линтеров внутри контейнера, сборка образа,
  правила поддержания чистоты образов (multi-stage, очистка apt/composer-кэша,
  запуск от непривилегированного пользователя). Используй при правке
  Dockerfile, docker-compose.yaml / docker.compose.yaml, docker/php/*,
  а также при запуске CLI-скриптов и отладке окружения.
---

# Docker-окружение проекта

Окружение — один сервис **`php`** (образ PHP 8.4 CLI) для запуска любых
PHP-программ из каталога проекта.

Фактические настройки (сверяйся с файлами, они — источник истины):

| Что | Где | Значение |
| --- | --- | --- |
| compose-файл | `docker-compose.yaml` (в корне, kebab-case) | сервис `php`, `target: dev`, `user: 1000:1000`, `init: true` |
| Dockerfile | `docker/php/Dockerfile` | stages: `base` → `dev` / `prod` |
| php.ini | `docker/php/php.ini` | dev-профиль, монтируется в `/usr/local/etc/php/php.ini` |
| точка входа | `docker/php/entrypoint` | `php -v` (установлен в `/usr/local/bin/entrypoint`) |
| рабочая директория | `/app` | bind-mount `./` → `/app` |
| Composer | `/usr/bin/composer` | `COMPOSER_HOME=/app/composer-home` (git-ignored) |
| пользователь | `app` (uid/gid 1000) | `USER app`, compose запускает от `1000:1000` |
| healthcheck | `docker-compose.yaml` | `php -r "exit(extension_loaded('intl') ? 0 : 1);"` |

Образ **не задаёт `ENTRYPOINT`**: контейнер принимает любую команду
(`php`, `composer`, `sh`, линтеры), а команда по умолчанию (`php -v`) задана в compose.

## 1. Базовые команды

Всегда указывай compose-файл явно и не полагайся на `latest`:

```bash
# Сборка образа и запуск
docker compose -f docker-compose.yaml up -d --build

# Пересоздать контейнер с нуля (после правки Dockerfile/php.ini)
docker compose -f docker-compose.yaml up -d --build --force-recreate

# Остановить и удалить контейнеры
docker compose -f docker-compose.yaml down
```

## 2. Запуск PHP-скриптов

```bash
# Одноразовый запуск скрипта (рекомендуется: контейнер создаётся и удаляется)
docker compose -f docker-compose.yaml run --rm php php path/to/script.php

# С аргументами скрипта
docker compose -f docker-compose.yaml run --rm php php bin/tool.php --dry-run

# Проверка синтаксиса
docker compose -f docker-compose.yaml run --rm php php -l path/to/script.php

# Интерактивная оболочка внутри поднятого контейнера
docker compose -f docker-compose.yaml exec php sh

# Разовый скрипт из stdin (без создания файла)
docker compose -f docker-compose.yaml run --rm -T php php -r 'echo PHP_VERSION, PHP_EOL;'
```

- `run --rm` создаёт **новый** контейнер из образа сервиса; используется для
  скриптов, линтеров и разовых задач.
- `exec` работает только в **уже запущенном** контейнере (`up -d`).
- Флаг `-T` отключает TTY — обязателен в скриптах, CI и при перенаправлении вывода.
- Файлы проекта доступны в контейнере по путям от `/app`
  (`./src/A.php` → `/app/src/A.php`), поэтому монтировать ничего не нужно.

## 3. Composer

```bash
# Установка зависимостей
docker compose -f docker-compose.yaml run --rm php composer install --no-interaction

# Новая зависимость
docker compose -f docker-compose.yaml run --rm php composer require --dev phpunit/phpunit

# Диагностика
docker compose -f docker-compose.yaml run --rm php composer --version
docker compose -f docker-compose.yaml run --rm php composer validate --no-check-publish
```

- `COMPOSER_HOME=/app/composer-home` — кэш и глобальный конфиг лежат вне образа,
  в каталоге проекта (он в `.gitignore`, коммитить нельзя).
- При запуске от пользователя `app` (uid 1000) каталог `composer-home` и
  `vendor` должны быть доступны на запись; при ошибках прав используй
  `docker compose run --rm --user root php ...` **только** для исправления
  владельца (`chown -R app:app /app/vendor /app/composer-home`).
- `composer.lock` в репозиторий не коммитится (окружение универсальное).

## 4. Линтеры и анализаторы

Инструменты не входят в образ по умолчанию — ставятся через Composer
(разработческие зависимости) и запускаются в том же контейнере:

```bash
# PHP-CS-Fixer (PER Coding Style)
docker compose -f docker-compose.yaml run --rm php \
  php vendor/bin/php-cs-fixer fix --dry-run --diff

# PHPStan
docker compose -f docker-compose.yaml run --rm php \
  php vendor/bin/phpstan analyse src -l max

# Валидация compose-файла — обязательна после любой его правки
docker compose -f docker-compose.yaml config --quiet
```

Полный цикл проверок описан в `.agents/rules/workflow.md`.

## 5. Чистота образов

- **Multi-stage**: `docker/php/Dockerfile` содержит
  `base` (Composer, `php.ini`, политика запуска) и `dev` (сборочные пакеты
  `*-dev`, расширения через `docker-php-ext-install`, `git`, `unzip`,
  пользователь `app`). Compose собирает `target: dev`.
- **Файл `Dockerfile` в корне — копия `docker/php/Dockerfile`** (контекст сборки —
  корень репозитория, поэтому пути `COPY docker/php/...` верны и там). При правке
  одного нужно синхронизировать второй:

  ```bash
  { printf '%s\n' '# syntax=docker/dockerfile:1' '# Образ использует контекст репозитория, поэтому Dockerfile лежит в корне.' '# Dockerfile, на который ссылается docker-compose.yaml, — docker/php/Dockerfile.' ''; cat docker/php/Dockerfile; } > Dockerfile
  ```
- **Очистка пакетного менеджера** — в одном `RUN` со установкой:
  `apt-get update && apt-get install -y --no-install-recommends ... &&
  rm -rf /var/lib/apt/lists/*`; `apt-get upgrade` в образе не выполняется.
- **Временные сборочные зависимости** удаляются в том же слое, где ставились
  (`apt-get purge -y <пакеты из списка установки>`), чтобы не раздувать слои.
  **Не используй `apt-get purge --auto-remove`** для `*-dev` пакетов: по
  зависимостям он удаляет runtime-библиотеки (`libicu76`, `libpq5`, `libzip5`),
  и PHP не сможет загрузить `intl`, `pgsql`, `pdo_pgsql`, `zip`
  (`Unable to load dynamic library`). Проверять надо `php -m`, а не только `php -v`.
- **`.dockerignore`** обязателен: исключай `.git`, `.agents`, `vendor`,
  `composer-home`, `.env*`, `*.log`, `node_modules` — иначе они попадут
  в контекст сборки.
- **Непривилегированный пользователь**: в `dev`/`prod` создан `app` (uid 1000),
  `WORKDIR /app` принадлежит ему; контейнер запускается от `app`, а не от `root`.
  `root` — только для отладки через `--user root`.
- **Фиксированные версии**: тег базового образа (`php:8.4-cli-trixie`),
  Composer ставится из официального образа `composer:2` (`COPY --from`),
  без `curl | sh` и самодельных phar на `latest`.
- **Проверка после сборки**:

  ```bash
  docker compose -f docker-compose.yaml run --rm php php -v   # ожидается 8.4.x
  docker compose -f docker-compose.yaml run --rm php php -m   # список расширений
  docker image inspect <image> --format '{{.Config.User}}'
  ```

  `php -m` не должен содержать строк `PHP Warning: Unable to load dynamic library`
  и `PHP Deprecated: session.sid_*`.

- Секреты не передаются через `ARG`/`ENV` в образ; переменные окружения —
  из `.env` (git-ignored) или `environment:` в compose.
