# inkanboard

Канбан-доска команды inslopnia: проекты, колонки, swimlane-ы, задачи с подзадачами, комментариями, тегами, вложениями и учётом времени, плюс JSON-RPC API для скриптов и агентов.

Интерфейс сделан в фирменном стиле: глаз-солнце в шапке, тёплая янтарная палитра и три темы.

- **Dawn** — светлая.
- **Night** — тёмная.
- **Auto** — следует настройке ОС.

Тема выбирается в профиле пользователя.

## Быстрый старт

Нужен только Docker.

```bash
git clone https://github.com/Duhamster456/inkanboard.git
cd inkanboard
docker compose -f docker-compose.sqlite.yml up -d --build
```

Откройте <http://localhost:8001/>. Логин `admin`, пароль `admin`, смените его сразу после первого входа.

Образ собирается из этого репозитория, база — SQLite в Docker-томе. Контейнер называется `inkanboard` и перезапускается сам, пока его не остановят вручную.

```bash
docker logs -f inkanboard                               # логи
docker compose -f docker-compose.sqlite.yml down        # остановить (данные остаются в томе)
docker compose -f docker-compose.sqlite.yml up -d --build   # пересобрать после изменений
```

### Другая база данных

| Файл | База | Примечание |
|---|---|---|
| `docker-compose.sqlite.yml` | SQLite | по умолчанию, ничего настраивать не нужно |
| `docker-compose.mysql.yml` | MariaDB 11.4 | 12.x не подходит: она иначе называет внешние ключи, и старые миграции схемы падают |
| `docker-compose.postgres.yml` | PostgreSQL 17 | образы 18+ ожидают том по другому пути |

Запускаются так же: `docker compose -f docker-compose.postgres.yml up -d --build`. Перед тем как открывать сервис наружу, поменяйте пароли базы в файле.

Все варианты слушают один порт и используют одно имя контейнера, поэтому одновременно работает только один из них. Тома у них свои: `inkanboard_*`, `inkanboard-mysql_*`, `inkanboard-postgres_*`.

### Переменные compose

| Переменная | По умолчанию | Что делает |
|---|---|---|
| `INKANBOARD_PORT` | `8001` | порт на хосте |
| `INKANBOARD_IMAGE` | `inkanboard:local` | имя собираемого образа |
| `INKANBOARD_VERSION` | `inslopnia` | версия, которая показывается в «About» и в API |

```bash
INKANBOARD_PORT=9000 docker compose -f docker-compose.sqlite.yml up -d --build
```

В PowerShell: `$env:INKANBOARD_PORT = "9000"; docker compose -f docker-compose.sqlite.yml up -d --build`.

### Бэкап SQLite

```bash
docker cp inkanboard:/var/www/app/data/db.sqlite ./backup.sqlite
```

Вложения лежат рядом, в `/var/www/app/data/files`.

## Настройка

Все параметры приложения описаны в `config.default.php`. Переопределить их можно двумя способами:

- **переменными окружения** — их читает приложение (`DEBUG`, `DATA_DIR`, `LOG_DRIVER`, `MAIL_*`, `LDAP_*`, …);
- **файлом `config.php`** в корне — скопируйте `config.default.php` и поменяйте нужные `define`.

Подключение к базе в Docker задаётся одной строкой `DATABASE_URL`, примеры есть в compose-файлах:

```
mysql://user:password@host/dbname
postgres://user:password@host/dbname
```

В контейнере nginx слушает 80 (наружу проброшен он) и 443 с самоподписанным сертификатом, который генерируется при старте. Для продакшена ставьте перед сервисом обычный reverse proxy с TLS.

## API

JSON-RPC 2.0 по адресу `http://localhost:8001/jsonrpc.php`. Есть два способа авторизации:

- **логин и пароль пользователя** (HTTP Basic) — действия выполняются с правами этого пользователя;
- **токен приложения** — пользователь `jsonrpc`, пароль — токен из «Settings → API». Полный доступ.

```bash
curl -s -u admin:admin http://localhost:8001/jsonrpc.php \
  -d '{"jsonrpc":"2.0","method":"getAllProjects","id":1}'

curl -s -u admin:admin http://localhost:8001/jsonrpc.php \
  -d '{"jsonrpc":"2.0","method":"createTask","id":2,"params":{"project_id":1,"title":"Поднять VDS","color_id":"blue","tags":["infra"]}}'
```

Процедуры сгруппированы по сущностям в `app/Api/Procedure/`: проекты, колонки, swimlane-ы, задачи, подзадачи, комментарии, теги, файлы, пользователи, группы и т.д. Имя метода совпадает с именем публичной функции процедуры.

## Дизайн

Всё оформление — обычный CSS без сборщиков.

| Где | Что |
|---|---|
| `assets/css/src/themes/light.css`, `dark.css`, `auto.css` | палитра тем: `--page`, `--surface`, `--ink`, `--accent`… `auto.css` = light + dark внутри `prefers-color-scheme`, держите три файла согласованными |
| `assets/css/src/base.css` | общие токены (шрифты, радиусы) и производные переменные компонентов (`--button-primary-*`, `--table-*`, …) |
| `assets/css/src/*.css` | компоненты: шапка, доска, карточки, формы, меню… |
| `app/Template/header/logo.php` | логотип (inline SVG, обводка глаза следует цвету темы) |
| `assets/img/` | `logo.svg`, адаптивная SVG-фавиконка и PNG-иконки |

Цвет задачи, выбранный пользователем, рисуется поверх карточки полупрозрачной вуалью `--card-veil`. Поэтому в тёмной теме карточки остаются тёмными с оттенком своего цвета и цветной полосой слева.

После правок в `assets/css/src` пересоберите минифицированные файлы:

```bash
php cli css        # assets/css/{light,dark,auto,print}.min.css
```

В образ попадают только `*.min.css`, поэтому `php cli css` нужен до `docker compose … --build`. Без локального PHP можно взять PHP из уже собранного образа (в нём есть все нужные расширения):

```bash
docker run --rm --entrypoint php -v "$PWD:/app" -w /app inkanboard:local cli css
```

## Разработка без Docker

Нужен PHP 8.1+ с расширениями `pdo_sqlite`, `mbstring`, `gd`, `openssl`, `zip`, `xml`, `dom`, `ctype`, `session`. Зависимости уже лежат в `vendor/`, `composer install` не обязателен.

Встроенному серверу PHP нужен роутер, иначе он отправляет в `index.php` и статику, и `jsonrpc.php`:

```php
<?php // router.php — держите вне репозитория или добавьте в .gitignore
$p = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$f = $_SERVER['DOCUMENT_ROOT'] . $p;
if ($p !== '/' && is_file($f)) {
    if (substr($p, -4) === '.php') { require $f; return true; }
    return false;
}
require $_SERVER['DOCUMENT_ROOT'] . '/index.php';
```

```bash
DATA_DIR=/tmp/inkanboard-data php -S 127.0.0.1:8001 -t . router.php
```

`DATA_DIR` выносит базу и кэш из `data/` репозитория. При первом запуске создаются база и пользователь `admin`/`admin`.

Тестам нужны dev-зависимости:

```bash
composer install
make test-sqlite        # также test-mysql, test-postgres
```

## Make

| Цель | Что делает |
|---|---|
| `make docker-image` | собрать `inkanboard:local` |
| `make docker-run` | запустить его на порту 8001 (без тома, данные пропадут) |
| `make docker-sh` | shell в работающем контейнере `inkanboard` |
| `make archive` | zip-архив текущего коммита |

## Лицензия

MIT, см. [LICENSE](LICENSE). Основано на [Kanboard](https://github.com/kanboard/kanboard).
