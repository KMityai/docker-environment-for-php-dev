---
name: php-84
description: >-
  Стандарты разработки на чистом PHP 8.4 (без фреймворков): PSR-1, PSR-4,
  PER Coding Style, declare(strict_types=1), запрет неявных nullable,
  идиомы PHP 8.4 (asymmetric visibility, property hooks, array_find/array_any,
  new Class()->method(), readonly-классы, типизированные константы, enum).
  Используй этот скилл при создании и правке любых файлов *.php, composer.json,
  autoload-путей и PSR-интерфейсов в этом репозитории.
---

# PHP 8.4 (чистый PHP)

Проект — это окружение для запуска произвольных программ на **чистом PHP 8.4**.
Никаких фреймворков (Laravel/Symfony) и их хелперов: только язык, SPL и
интерфейсы `Psr\*`. PHP-код запускается CLI внутри контейнера — см.
`.agents/skills/docker-php/SKILL.md`.

## 1. Стандарты оформления

- **PSR-1**: файлы — только `<?php` (без закрывающего `?>`), одна ответственность,
  StudlyCaps для классов, константы — UPPER_CASE, методы — camelCase,
  побочных эффектов в файлах с классами нет.
- **PSR-4**: один класс на файл, namespace повторяет путь от корня автозагрузки
  (`App\Domain\User` → `src/Domain/User.php`), имя файла совпадает с именем класса.
- **PER Coding Style** (пришёл на смену PSR-12): отступ — **4 пробела** (не табы),
  переводы строк **Unix LF**, файл заканчивается одним пустым переводом строки,
  без `?>` в конце файла, строка до 120 символов, одна инструкция на строку,
  `use`-импорты по алфавиту, модификаторы в порядке `final readonly class`.
- **Явная видимость** у всех свойств, методов и констант:
  `public const int`, `private string $name`, `protected function boot(): void`.
  `var` и неявные `public` не используются.
- Типы обязательны для параметров, возвращаемых значений и свойств
  (`void`/`never`/`mixed` — явно), а не «где получится».

## 2. `declare(strict_types=1);`

- Первая инструкция **каждого** `.php` файла, сразу после `<?php`
  (до `namespace` и `use`):

  ```php
  <?php

  declare(strict_types=1);

  namespace App\Domain;
  ```

- Неявные приведения типов (`"42"` → `42`, `null` в `int`) запрещены;
  привод выполняй валидацией на границе, а не кастом внутри домена.

## 3. Nullable-параметры (запрет устаревшего синтаксиса PHP 8.4)

В PHP 8.4 неявные nullable-объявления **устарели** (`E_DEPRECATED`) и будут
ошибкой в PHP 9. Тип по умолчанию `null` обязан быть явно nullable:

```php
// Плохо (deprecated в PHP 8.4)
function find(string $key = null): ?string {}

// Хорошо
function find(?string $key = null): ?string {}
function find(string|null $key = null): ?string {}   // альтернативная запись
```

Правило распространяется на параметры, свойства (`?array $tags = null`),
промоушен в конструкторе и union-типы.

## 4. Идиомы PHP 8.4

- **Asymmetric visibility** — чтение публичное, запись закрыта:
  `public private(set) string $status = 'new';`
- **Property hooks** вместо getter/setter:

  ```php
  public string $email {
      get => mb_strtolower($this->email);
      set {
          if (!filter_var($value, FILTER_VALIDATE_EMAIL)) {
              throw new \InvalidArgumentException('Некорректный e-mail');
          }

          $this->email = $value;
      }
  }
  ```

- **Нативные функции поиска**: `array_find()`, `array_find_key()`, `array_any()`,
  `array_all()` вместо ручных `foreach`/`array_filter` + `reset`.
- **Вызов метода при инстанцировании без скобок**:
  `new ConfigValidator()->validate($config);`
- **`readonly`-классы** для DTO/VO: `final readonly class Money { ... }`;
  модификатор на классе запрещает изменение любого свойства.
- **Типизированные константы**: `public const int LIMIT = 100;`,
  `public const string DEFAULT_TZ = 'UTC';`
- **`enum`** для закрытых наборов значений; backing type — `string`/`int`,
  методы вместо внешних `match`-таблиц.
- Также уместны: `match(true)`, named arguments, first-class callable syntax
  (`$fn = strlen(...)`), `new` в инициализаторах параметров, `#[\Override]`
  у переопределяемых методов.

## 5. Архитектура чистого PHP

- **Без фреймворков**: не подключай Laravel/Symfony-компоненты, хелперы `app()`,
  фасады, глобальные функции фреймворка.
- Опора на **SPL**: `ArrayObject`, `SplObjectStorage`, `SplPriorityQueue`,
  `SplFixedArray`, `countable`/`iterator`-контракты, исключения SPL
  (`InvalidArgumentException`, `LogicException`, `RuntimeException`).
- Публичные контракты — **`Psr\*`**: `Psr\Log\LoggerInterface`,
  `Psr\Container\ContainerInterface`, `Psr\Http\Message\*`.
- **Внедрение зависимостей через конструктор** (`final readonly class` +
  `private Foo $foo`), сервис-локатор и статические синглтоны запрещены.
- **Строгая валидация на границах**: входные данные (CLI-аргументы, файлы,
  env) проверяются один раз на входе и превращаются в типизированные VO;
  внутри домена данные уже валидны.
- Домен не знает про `$_SERVER`, `getenv()`, `STDIN` напрямую — только через
  абстракции; ошибки — исключениями, не `false`/`null`-кодами.

## 6. Частые ошибки: правильно / неправильно

**6.1. Заголовок файла и строгая типизация**

```php
// Неправильно
<?php
namespace App;
function add($a, $b) { return $a + $b; }   // неявные типы, приведение строк
?>

// Правильно
<?php

declare(strict_types=1);

namespace App;

function add(int $a, int $b): int
{
    return $a + $b;
}
```

**6.2. Поиск в массиве**

```php
// Неправильно
$found = null;
foreach ($users as $user) {
    if ($user->isActive()) { $found = $user; break; }
}
$hasAdmin = false;
foreach ($roles as $role) {
    if ($role === 'admin') { $hasAdmin = true; }
}

// Правильно (PHP 8.4)
$found = array_find($users, static fn (User $user): bool => $user->isActive());
$hasAdmin = array_any($roles, static fn (string $role): bool => $role === 'admin');
$key = array_find_key($users, static fn (User $user): bool => $user->isActive());
```

**6.3. Иммутабельный DTO**

```php
// Неправильно
class Money {
    public $amount;                 // нет типа и видимости
    public $currency;
    public function setAmount($a) { $this->amount = $a; }  // мутабельный
}

// Правильно
final readonly class Money
{
    public function __construct(
        public int $amount,
        public Currency $currency,
    ) {
    }
}
```

**6.4. Состояние и запись**

```php
// Неправильно: публичный сеттер и nullable без «?»
class Order {
    public string $status = null;
    public function setStatus(string $status = null): void { $this->status = $status; }
}

// Правильно: асимметричная видимость + property hook + типизированные константы
final class Order
{
    public const string NEW = 'new';
    public private(set) string $status = self::NEW;

    public function approve(): void
    {
        $this->status = 'approved';          // запись разрешена только из класса
    }

    public function label(?string $prefix = null): string
    {
        return ($prefix ?? 'Order') . ': ' . $this->status;
    }
}

new Order()->approve();   // метод при инстанцировании — без лишних скобок
```

## 7. Перед коммитом

1. `php -l` для каждого изменённого файла — синтаксис.
2. `php-cs-fixer fix --dry-run --diff` (PER Coding Style) и `phpstan analyse` —
   если инструменты установлены.
3. Прогон скрипта внутри контейнера (`docker compose run --rm php php ...`).

Цикл проверок описан в `.agents/rules/workflow.md`, команды окружения —
в `.agents/skills/docker-php/SKILL.md`.
