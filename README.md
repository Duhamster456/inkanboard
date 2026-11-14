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

### Переменные compose

| Переменная | По умолчанию | Что делает |
|---|---|---|
| `INKANBOARD_BIND` | `127.0.0.1` | адрес на хосте; `0.0.0.0` — слушать на всех интерфейсах |
| `INKANBOARD_PORT` | `8001` | порт на хосте |
| `INKANBOARD_IMAGE` | `inkanboard:local` | имя собираемого образа |
| `INKANBOARD_CONTAINER` | `inkanboard` | имя контейнера (для второго экземпляра рядом — вместе с `-p <проект>` и другим портом) |
| `INKANBOARD_VERSION` | `inslopnia` | версия, которая показывается в «About» и в API |
| `INKANBOARD_MEMORY` | `1g` | лимит памяти контейнера (tmpfs-каталоги считаются в него же) |
| `INKANBOARD_CPUS` | `1.0` | лимит CPU |

```bash
INKANBOARD_PORT=9000 docker compose -f docker-compose.sqlite.yml up -d --build
```

В PowerShell: `$env:INKANBOARD_PORT = "9000"; docker compose -f docker-compose.sqlite.yml up -d --build`.

### Доступ снаружи

По умолчанию сервис доступен только с самой машины (`127.0.0.1:8001`). Это важно на сервере: на Linux Docker прописывает проброшенные порты прямо в iptables, в обход `ufw`/`firewalld`, так что порт на `0.0.0.0` оказывается открыт в интернет, даже если файрвол его «закрывает».

Как зайти снаружи:

- **reverse proxy** (nginx, Caddy) на той же машине с TLS, проксирует на `http://127.0.0.1:8001`;
- **SSH-туннель**: `ssh -L 8001:127.0.0.1:8001 user@server`, затем <http://localhost:8001/> у себя;
- **открыть порт осознанно**: `INKANBOARD_BIND=0.0.0.0 docker compose -f docker-compose.sqlite.yml up -d`.

### Бэкап SQLite

```bash
docker cp inkanboard:/var/www/app/data/db.sqlite ./backup.sqlite
```

Вложения лежат рядом, в `/var/www/app/data/files`.

## Настройка

Все параметры приложения описаны в `config.default.php`. Переопределить их можно двумя способами:

- **переменными окружения** — их читает приложение (`DEBUG`, `LOG_DRIVER`, `MAIL_*`, `LDAP_*`, …); в Docker добавьте их в секцию `environment:` сервиса `app`;
- **файлом `data/config.php`** — скопируйте `config.default.php`, оставьте нужные `define` и положите файл в том с данными:

```bash
docker cp my-config.php inkanboard:/var/www/app/data/config.php
docker restart inkanboard
```

Файл принадлежит root, а приложение не может его изменить (см. «Изоляция»). Править его — только так, снаружи.

В контейнере nginx слушает 80 (наружу проброшен он) и 443 с самоподписанным сертификатом, который генерируется при старте. Для продакшена ставьте перед сервисом обычный reverse proxy с TLS.

## Изоляция

Безопасная конфигурация включена в `docker-compose.sqlite.yml` по умолчанию, отдельного «hardened»-варианта нет. Расчёт — что даже при RCE в приложении атакующий остаётся пользователем `nginx` в контейнере без прав, без доступа к коду и без возможности закрепиться.

| Мера | Что даёт |
|---|---|
| PHP-FPM и nginx-воркеры работают от `nginx` | RCE в приложении — не root |
| `cap_drop: [ALL]` + 5 нужных capabilities | у PHP-воркеров capabilities нет вообще; root-процессы (s6, cron, мастер-процессы nginx/php-fpm) могут только сменить пользователя, поправить владельца томов, занять порт 80 и сигналить своим воркерам. Нет `DAC_OVERRIDE`, `SYS_ADMIN`, `NET_RAW` и т.п. |
| `no-new-privileges`, в образе нет SUID-бинарников | стать root из `nginx` можно только через уязвимость ядра |
| `read_only: true` | код приложения, конфиги nginx/PHP/cron и системные файлы нельзя изменить даже root внутри контейнера |
| tmpfs с `noexec` (`/tmp`, временные файлы nginx) | там, куда PHP может писать, нельзя запустить свой бинарник |
| `plugins/` и `data/config.php` принадлежат root | приложение не может подложить исполняемый PHP-код, который переживёт пересоздание контейнера; `data/` — sticky-каталог, `config.php` нельзя ни изменить, ни удалить, ни подменить |
| entrypoint меняет владельцев через `find`, не следуя симлинкам | ссылка, подложенная в том, не заставит root сменить владельца файла вне тома |
| лимиты памяти, CPU и процессов, ротация логов | контейнер не положит машину и не забьёт диск логами |
| порт только на `127.0.0.1` | см. «Доступ снаружи» |

Плагины ставит администратор снаружи, приложению запись в `plugins/` не нужна:

```bash
docker cp MyPlugin inkanboard:/var/www/app/plugins/
docker restart inkanboard
```

Установка плагинов из веб-интерфейса выключена по умолчанию. Если её включить (`PLUGIN_INSTALLER: "true"` в `environment:`), entrypoint отдаст `plugins/` приложению — это осознанно ослабляет пункт про закрепление.

Чего Docker-средствами не закрыть:

- **ядро общее с хостом** — уязвимость ядра или runtime даёт выход из контейнера; для враждебного кода нужны gVisor (`runtime: runsc`), Kata или отдельная VM, плюс `userns-remap` в настройках демона;
- **исходящий трафик открыт** — он нужен для почты, вебхуков и превью ссылок. Встроенная защита Kanboard от SSRF (`WEBHOOK_ALLOW_PRIVATE_NETWORKS`, `EXTERNAL_LINK_ALLOW_PRIVATE_NETWORKS`, по умолчанию выключены) не даёт приложению ходить во внутренние сети, но RCE-код может;
- **данные приложения** — база, вложения и сессии доступны процессу PHP по определению;
- **размер тома** — лимит диска для named volume без отдельной ФС не задать.

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
make test-sqlite
```

## Make

| Цель | Что делает |
|---|---|
| `make docker-image` | собрать `inkanboard:local` |
| `make docker-run` | запустить его на `127.0.0.1:8001` с теми же ограничениями, что в compose (без тома, данные пропадут) |
| `make docker-sh` | shell в работающем контейнере `inkanboard` |
| `make archive` | zip-архив текущего коммита |

## Лицензия

MIT, см. [LICENSE](LICENSE). Основано на [Kanboard](https://github.com/kanboard/kanboard).
