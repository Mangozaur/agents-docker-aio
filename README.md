[English](#english) | [Русский](#русский) | [中文](#中文)

---

<a id="english"></a>

# Coding Agents Docker All-In-One

> "One ~~Ring~~ Container to rule them all"

An all-in-one Docker image for running AI coding agents (Claude Code, OpenAI Codex, Open Code, Qwen) in an isolated environment with a pre-installed PHP/Laravel development stack.

Both ephemeral and persistent containers are supported.

Proxy wrappers provide transparent API access through SOCKS5/HTTP proxies.
User data (history, caches, agent settings) is persisted in a separate Docker volume between sessions.

The image includes PHP 8.4, Node.js, Python, Rust, Go, Composer, Bun, as well as LSP servers for PHP and Laravel.

- Option to access Docker from within the container.
- Configurable port forwarding

Management is done through two scripts: `agent.sh` for ephemeral and `agentx.sh` for persistent containers.

## Setup

Create a `.env` file next to `agent.sh`; parameter descriptions are available in `.env.example`.

Port forwarding settings (`FWD_HOST_PORT`, `FWD_CONTAINER_PORT`) can be placed in `.agents.env` in the root of a specific project — they will be picked up from there. Template: `.agents.env.example`. If no `.agents.env` exists in the project, the fallback from `.env` is used.

You can also set `MOUNT_NAME` in `.agents.env` — the project name inside the container. It determines the mount path (`/var/www/<MOUNT_NAME>`) and the container name (`agents-<MOUNT_NAME>`). By default, the current host directory name is used, but for projects with generic names (e.g., `app`, `src`, `backend`) it's convenient to set a meaningful name: `MOUNT_NAME=my-project`.

Container names are automatically transliterated and sanitized (Cyrillic → Latin, special characters → hyphens). The mount path inside the container preserves the original directory name.

### Key `.env` variables

| Variable | Purpose |
|-|-|
| `CLAUDE_PROXY` | HTTP proxy for Claude |
| `CODEX_PROXY` | Proxy for Codex |
| `NO_PROXY` | Hosts to bypass proxy |
| `FWD_CONTAINER_PORT` | Port inside the container to forward outward |
| `FWD_HOST_PORT` | Preferred host port; if occupied — a random one is used |
| `ENABLE_DOCKER` | Forward Docker socket into the container (DooD). `true` by default |

### `.agents.env` variables (in project root)

| Variable | Purpose |
|-|-|
| `MOUNT_NAME` | Project name inside the container (path `/var/www/<MOUNT_NAME>`, container name `agents-<MOUNT_NAME>`). Defaults to the host directory name |
| `FWD_CONTAINER_PORT` | Port inside the container to forward outward (overrides `.env`) |
| `FWD_HOST_PORT` | Preferred host port (overrides `.env`) |
| `ENABLE_DOCKER` | Forward Docker socket (overrides `.env`). `true` by default |
| `DOCKER_NETWORK` | Docker network to connect the container to. Default bridge network is used if not set |
| `EXEC_BEFORE` | Command executed on the host before starting the container |
| `EXEC_AFTER` | Command executed on the host after stopping the container |
| `EXTRA_PATH` | Additional paths separated by `:`, appended to `$PATH` inside the container. Allows adding binaries from a persistent volume without rebuilding the image |

## Usage

```
agent.sh <workdir> <exec>
```

`workdir` — working directory. Defaults to the current directory from which the script was called \
`exec` — command to be executed inside the container. Defaults to `bash`

Usage example:

From your project directory, run `agent.sh`. The script will automatically create a container and mount the current directory to `/var/www/<directory-name>`. The name can be overridden via `MOUNT_NAME` in `.agents.env`.

### Ephemeral containers

Run `agent.sh`. A container will start, the current directory will be mounted to `/var/www/<directory-name>` (or `/var/www/$MOUNT_NAME` if set), and a console will open.
Then simply launch the desired agent.\
After exiting, the container will be destroyed.

For convenience, to avoid specifying the full path to `agent.sh`, you can add a function to `.bash_aliases`:

```shell
agent() {
    <path-to-script>/agent.sh "$PWD" "$@"
}
```

Then you can open an agent in the current directory directly. For example, `agent claude`

### Persistent containers

There is also a script `agentx.sh` — it works the same way but creates **persistent** containers.

### Docker-outside-of-Docker (DooD)

Inside the container, `docker` and `docker compose` commands are available — they work with the host's Docker daemon via the forwarded Unix socket `/var/run/docker.sock`.

Works on macOS (Docker Desktop), Linux, and WSL without additional configuration — if the socket exists on the host, it's forwarded automatically. To disable, set `ENABLE_DOCKER=false` in `.env` or `.agents.env`.

### User data

All user data from `~/` is persisted between sessions in a separate volume.

## Installed agents

### Claude
https://github.com/anthropics/claude-code \
Command: `claude`

Requires a proxy or VPN to work from Russia. Proxy is configured through `.env`.

Claude doesn't natively use installed LSPs. This is done through skills.
But it can install LSPs via the `/plugin` command.

### Codex
https://developers.openai.com/codex/cli \
Command: `codex`

Requires a proxy or VPN to work from Russia. Proxy is configured through `.env`.

### Open Code
https://opencode.ai/ \
Command: `opencode`

### Qwen
https://github.com/QwenLM/qwen-code \
Command: `qwen`

## Installed tools

### context7
https://github.com/upstash/context7 \
Command: `npx -y @upstash/context7-mcp`

A documentation library for all frameworks and libraries. The installed version accesses the API at https://context7.com

If the default limits aren't enough, you can get a free key at https://context7.com/dashboard

#### Installation in Claude
`claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp --api-key YOUR_API_KEY`

`--api-key` is optional

#### Installation in Codex
`codex mcp add context7 -- npx -y @upstash/context7-mcp --api-key YOUR_API_KEY`

`--api-key` is optional

### php-lsp
https://crates.io/crates/php-lsp \
Command: `php-lsp`

LSP server for PHP. Claims the most complete understanding of PHP structure up to 8.5.

Not suitable for use as a CLI utility, since it only works through stdin/stdout.

### phpantom_lsp
https://crates.io/crates/phpantom_lsp \
Command: `phpantom_lsp`

LSP server for PHP. Understands Laravel Eloquent.

### laravel-ls
https://github.com/laravel-ls/laravel-ls \
Command: `laravel-ls`

A dedicated LSP for Laravel.

## Helpers

### chrome-mcp

A wrapper for `chrome-devtools-mcp`. Use it as an MCP server if the standard one can't connect to a Chrome instance on the host machine.
This issue appears, for example, in Windows WSL. Inside the container, you need to find the correct IP to send the request to.
The situation is further complicated by the fact that Chrome in remote-debugging mode expects connections by IP, without using hostnames. So the standard `host.docker.internal` won't work.
It is recommended to launch Chrome with the flags `--remote-debugging-address=0.0.0.0 --remote-debugging-port=9222 --remote-allow-origins=* --no-first-run --no-default-browser-check --user-data-dir="<temp-directory-for-profile>"`

## Build

Build the image locally: `docker build -t agents .`

Full rebuild: `docker build --no-cache -t agents .`

Debug build: `docker build --progress=plain -t agents .`

Remove the home directory volume: `docker volume rm agents-dev-home`

---

<a id="русский"></a>

# Coding Agents Docker All-In-One

> "One ~~Ring~~ Container to rule them all"

Docker-образ «всё-в-одном» для запуска ИИ-кодинг-агентов (Claude Code, OpenAI Codex, Open Code, Qwen) в изолированном окружении с предустановленным стеком для PHP/Laravel-разработки. 

Поддерживаются эфемерные и персистентные контейнеры.

Прокси-обёртки обеспечивают прозрачный доступ к API через SOCKS5/HTTP-прокси. 
Данные пользователя (история, кэши, настройки агентов) сохраняются в отдельном Docker volume между сессиями.

Образ содержит PHP 8.4, Node.js, Python, Rust, Go, Composer, Bun, а также LSP-серверы для PHP и Laravel.

- Опция для доступа к докеру из контейнера.
- Настраиваемый проброс порта

Управление — через два скрипта: `agent.sh` для эфемерных и `agentx.sh` для персистентных контейнеров.

## Настройка
Создать файл `.env` рядом с `agent.sh`, описание параметров есть в `.env.example`

Настройки проброса портов (`FWD_HOST_PORT`, `FWD_CONTAINER_PORT`) можно вынести в `.agents.env` в корне конкретного проекта — тогда они будут браться оттуда. Шаблон: `.agents.env.example`. Если `.agents.env` в проекте нет, используется фолбэк из `.env`.

Там же, в `.agents.env`, можно задать `MOUNT_NAME` — имя проекта внутри контейнера. Определяет путь маунта (`/var/www/<MOUNT_NAME>`) и имя контейнера (`agents-<MOUNT_NAME>`). По умолчанию используется имя текущей директории хоста, но для проектов с типовой структурой (например, `app`, `src`, `backend`) удобно задать осмысленное имя: `MOUNT_NAME=my-project`.

Имя контейнера автоматически транслитерируется и санитизируется (кириллица → латиница, спецсимволы → дефисы). Путь монтирования внутри контейнера сохраняет оригинальное имя директории.

### Ключевые переменные `.env`

|Переменная|Назначение|
|-|-|
|`CLAUDE_PROXY`|HTTP-прокси для Claude|
|`CODEX_PROXY`|прокси для Codex|
|`NO_PROXY`|Хосты в обход прокси|
|`FWD_CONTAINER_PORT`|Порт внутри контейнера для проброса наружу|
|`FWD_HOST_PORT`|Предпочтительный порт на хосте; если занят — берётся случайный|
|`ENABLE_DOCKER`|Проброс Docker-сокета внутрь контейнера (DooD). `true` по умолчанию|

### Переменные `.agents.env` (в корне проекта)

|Переменная|Назначение|
|-|-|
|`MOUNT_NAME`|Имя проекта внутри контейнера (путь `/var/www/<MOUNT_NAME>`, имя контейнера `agents-<MOUNT_NAME>`). По умолчанию — имя директории хоста|
|`FWD_CONTAINER_PORT`|Порт внутри контейнера для проброса наружу (переопределяет `.env`)|
|`FWD_HOST_PORT`|Предпочитаемый порт на хосте (переопределяет `.env`)|
|`ENABLE_DOCKER`|Проброс Docker-сокета (переопределяет `.env`). `true` по умолчанию|
|`DOCKER_NETWORK`|Сеть Docker, к которой подключить контейнер. Если не указана — используется сеть по умолчанию (bridge)|
|`EXEC_BEFORE`|Команда, выполняемая на хосте перед запуском контейнера|
|`EXEC_AFTER`|Команда, выполняемая на хосте после остановки контейнера|
|`EXTRA_PATH`|Дополнительные пути через `:`, добавляемые в `$PATH` внутри контейнера. Позволяет добавлять бинарники из персистентного тома без пересборки образа|

## Использование

```
agent.sh <workdir> <exec>
```

`workdir` - рабочая директория. По-умолчанию текущая, из которой был вызван скрипт \
`exec` - команда, которая будет вызвана в контейнере. По-умолчанию `bash`

Пример использования:

Из директории вашего проекта вызываете `agent.sh`. Скрипт автоматически создаст контейнер и смотирует текущую директорию в `/var/www/<имя директории>`. Имя можно переопределить через `MOUNT_NAME` в `.agents.env`.

### "Эфемерные" контейнеры
Вызвать `agent.sh`. Запустится контейнер, текущая директория будет смонтирована в `/var/www/<имя директории>` (или `/var/www/$MOUNT_NAME`, если задано), откроется консоль.
Дальше просто запускаем нужного агента.\
После выхода контейнер будет уничтожен. 

Для удобства, чтобы не указывать полный путь до `agent.sh` можно добавить в `.bash_aliases` функцию:

```shell
agent() {
    <путь до скрипта>/agent.sh "$PWD" "$@"
}
```

Тогда можно сразу открывать агента в текущей директории. Например, `agent claude`

### Персистентные контейнеры
 Так же есть скрипт `agentx.sh` - он работает точно также, но создает **персистентные** контейнеры.

### Docker-outside-of-Docker (DooD)
Внутри контейнера доступны команды `docker` и `docker compose` — они работают с Docker daemon хоста через проброс Unix-сокета `/var/run/docker.sock`.

Работает на macOS (Docker Desktop), Linux и WSL без дополнительной настройки — если сокет существует на хосте, он пробрасывается автоматически. Для отключения установите `ENABLE_DOCKER=false` в `.env` или `.agents.env`.

### Пользовательские данные
Все пользовательские данные из `/~` сохраняются между сессиями в отдельном томе.

## Установленные агенты

### Claude
https://github.com/anthropics/claude-code \
Команда `claude`

Для работы в РФ требуется прокси или VPN. Прокси прокидывается через `.env`

Claude нативно не использует установленные lsp. Это делается через скиллы.
Но у него есть возможность ставить lsp через команду `/plugin`

### Codex
https://developers.openai.com/codex/cli \
Команда `codex`

Для работы в РФ требуется прокси или VPN. Прокси прокидывается через `.env`

### Open Code
https://opencode.ai/ \
Команда `opencode`

### Qwen
https://github.com/QwenLM/qwen-code \
Команда `qwen`

## Установленные тулзы

### context7
https://github.com/upstash/context7 \
Команда: `npx -y @upstash/context7-mcp`

Библиотека документации по всем фреймворкам и библиотекам. Установленная версия ходит в API https://context7.com

Если дефолтных лимитов не хватает, то можно получить бесплатный ключ у них https://context7.com/dashboard

#### Установка в Claude
`claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp --api-key YOUR_API_KEY`

`--api-key` опциональный

#### Установка в Codex
`codex mcp add context7 -- npx -y @upstash/context7-mcp --api-key YOUR_API_KEY`

`--api-key` опциональный

### php-lsp
https://crates.io/crates/php-lsp \
Команда: `php-lsp`

LSP сервер для PHP. Декларирует наиболее полное понимание структуры PHP вплоть до 8.5

Не подходит для использования в качестве CLI-утилиты, т.к. работает только через stdin/stdout.

### phpantom_lsp
https://crates.io/crates/phpantom_lsp \
Команда: `phpantom_lsp`

LSP сервер для PHP. Знает про Laravel Eloquent

### laravel-ls
https://github.com/laravel-ls/laravel-ls \
Команда: `laravel-ls`

Отдельный LSP для Ларавел

## Хелперы

### chrome-mcp

Обертка для `chrome-devtools-mcp`. Прописывайте ее как mcp-сервер, если стандартный не может подсоединиться к инстансу Chrome на хост-машине.
Проблема проявляется, например, в Windows WSL. Внутри контейнера нужно найти правильной IP, на который отправить запрос.
Ситуация еще усугубляется тем, что сам Chrome в режиме remote-debugging ожидает подключения по IP, без использования хостнеймов. Поэтому стандартный host.docker.internal использовать не получится.
Рекомендуется запускать Chrome с флагами `--remote-debugging-address=0.0.0.0 --remote-debugging-port=9222 --remote-allow-origins=*  --no-first-run --no-default-browser-check  --user-data-dir="<временная-директория-для-профиля>"` 

## Сборка

Локально собрать образ `docker build -t agents .`

Полная пересборка `docker build --no-cache -t agents .`

Отладка `docker build --progress=plain -t agents .`

Удаление тома с домашней директорией `docker volume rm agents-dev-home`

---

<a id="中文"></a>

# Coding Agents Docker 一体化镜像

> "One ~~Ring~~ Container to rule them all"

一体化 Docker 镜像，用于在隔离环境中运行 AI 编程代理（Claude Code、OpenAI Codex、Open Code、Qwen），预装 PHP/Laravel 开发技术栈。

支持临时容器和持久化容器。

代理包装器通过 SOCKS5/HTTP 代理提供透明的 API 访问。
用户数据（历史记录、缓存、代理设置）在会话之间持久保存在独立的 Docker 卷中。

镜像包含 PHP 8.4、Node.js、Python、Rust、Go、Composer、Bun，以及 PHP 和 Laravel 的 LSP 服务器。

- 支持从容器内访问 Docker 的选项。
- 可配置的端口转发

通过两个脚本管理：`agent.sh` 用于临时容器，`agentx.sh` 用于持久化容器。

## 配置

在 `agent.sh` 旁边创建 `.env` 文件，参数说明参见 `.env.example`。

端口转发设置（`FWD_HOST_PORT`、`FWD_CONTAINER_PORT`）可以放在特定项目根目录的 `.agents.env` 中——它们将从那里读取。模板：`.agents.env.example`。如果项目中没有 `.agents.env`，则使用 `.env` 中的配置作为后备。

在同一 `.agents.env` 中，还可以设置 `MOUNT_NAME`——容器内的项目名称。它决定了挂载路径（`/var/www/<MOUNT_NAME>`）和容器名称（`agents-<MOUNT_NAME>`）。默认使用当前宿主机目录名称，但对于具有通用名称的项目（例如 `app`、`src`、`backend`），建议设置一个有意义的名称：`MOUNT_NAME=my-project`。

容器名称会自动进行音译和清理（西里尔字母 → 拉丁字母，特殊字符 → 连字符）。容器内的挂载路径保留原始目录名称。

### 主要 `.env` 变量

| 变量 | 用途 |
|-|-|
| `CLAUDE_PROXY` | Claude 的 HTTP 代理 |
| `CODEX_PROXY` | Codex 的代理 |
| `NO_PROXY` | 绕过代理的主机 |
| `FWD_CONTAINER_PORT` | 容器内要向外转发的端口 |
| `FWD_HOST_PORT` | 首选宿主机端口；如被占用则使用随机端口 |
| `ENABLE_DOCKER` | 将 Docker 套接字转发到容器内（DooD）。默认为 `true` |

### `.agents.env` 变量（项目根目录）

| 变量 | 用途 |
|-|-|
| `MOUNT_NAME` | 容器内的项目名称（路径 `/var/www/<MOUNT_NAME>`，容器名称 `agents-<MOUNT_NAME>`）。默认为宿主机目录名称 |
| `FWD_CONTAINER_PORT` | 容器内要向外转发的端口（覆盖 `.env`） |
| `FWD_HOST_PORT` | 首选宿主机端口（覆盖 `.env`） |
| `ENABLE_DOCKER` | 转发 Docker 套接字（覆盖 `.env`）。默认为 `true` |
| `DOCKER_NETWORK` | 要将容器连接到的 Docker 网络。如果未设置，则使用默认的 bridge 网络 |
| `EXEC_BEFORE` | 启动容器前在宿主机上执行的命令 |
| `EXEC_AFTER` | 停止容器后在宿主机上执行的命令 |
| `EXTRA_PATH` | 以 `:` 分隔的附加路径，添加到容器内的 `$PATH` 中。允许从持久卷添加二进制文件而无需重新构建镜像 |

## 使用方法

```
agent.sh <workdir> <exec>
```

`workdir` — 工作目录。默认为调用脚本的当前目录 \
`exec` — 在容器内执行的命令。默认为 `bash`

使用示例：

在项目目录下运行 `agent.sh`。脚本将自动创建容器并将当前目录挂载到 `/var/www/<目录名>`。可以通过 `.agents.env` 中的 `MOUNT_NAME` 覆盖名称。

### 临时容器

运行 `agent.sh`。容器将启动，当前目录将挂载到 `/var/www/<目录名>`（如果设置了 `MOUNT_NAME` 则为 `/var/www/$MOUNT_NAME`），并打开控制台。
然后直接启动所需的代理。\
退出后容器将被销毁。

为方便起见，可以在 `.bash_aliases` 中添加函数，避免每次都指定 `agent.sh` 的完整路径：

```shell
agent() {
    <脚本路径>/agent.sh "$PWD" "$@"
}
```

然后可以直接在当前目录打开代理。例如，`agent claude`

### 持久化容器

还有 `agentx.sh` 脚本——功能相同，但创建的是**持久化**容器。

### Docker-outside-of-Docker (DooD)

容器内可以使用 `docker` 和 `docker compose` 命令——它们通过转发的 Unix 套接字 `/var/run/docker.sock` 与宿主机的 Docker 守护进程通信。

在 macOS（Docker Desktop）、Linux 和 WSL 上无需额外配置即可使用——如果宿主机上存在套接字，将自动转发。要禁用，请在 `.env` 或 `.agents.env` 中设置 `ENABLE_DOCKER=false`。

### 用户数据

`~/` 中的所有用户数据在会话之间持久保存在独立卷中。

## 已安装的代理

### Claude
https://github.com/anthropics/claude-code \
命令：`claude`

在中国大陆使用需要代理或 VPN。代理通过 `.env` 配置。

Claude 原生不使用已安装的 LSP。这通过 skills 实现。
但它可以通过 `/plugin` 命令安装 LSP。

### Codex
https://developers.openai.com/codex/cli \
命令：`codex`

在中国大陆使用需要代理或 VPN。代理通过 `.env` 配置。

### Open Code
https://opencode.ai/ \
命令：`opencode`

### Qwen
https://github.com/QwenLM/qwen-code \
命令：`qwen`

## 已安装的工具

### context7
https://github.com/upstash/context7 \
命令：`npx -y @upstash/context7-mcp`

涵盖所有框架和库的文档库。已安装版本访问 API https://context7.com

如果默认配额不够用，可以在 https://context7.com/dashboard 获取免费密钥

#### 在 Claude 中安装
`claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp --api-key YOUR_API_KEY`

`--api-key` 为可选参数

#### 在 Codex 中安装
`codex mcp add context7 -- npx -y @upstash/context7-mcp --api-key YOUR_API_KEY`

`--api-key` 为可选参数

### php-lsp
https://crates.io/crates/php-lsp \
命令：`php-lsp`

PHP 的 LSP 服务器。声称对 PHP 结构有最完整的理解，支持到 8.5 版本。

不适合作为 CLI 工具使用，因为它只通过 stdin/stdout 工作。

### phpantom_lsp
https://crates.io/crates/phpantom_lsp \
命令：`phpantom_lsp`

PHP 的 LSP 服务器。了解 Laravel Eloquent。

### laravel-ls
https://github.com/laravel-ls/laravel-ls \
命令：`laravel-ls`

Laravel 专用 LSP。

## 辅助工具

### chrome-mcp

`chrome-devtools-mcp` 的包装器。如果标准 MCP 无法连接到宿主机上的 Chrome 实例，请将其作为 MCP 服务器使用。
例如在 Windows WSL 中会出现此问题。在容器内需要找到正确的 IP 来发送请求。
情况更加复杂的是，Chrome 在 remote-debugging 模式下期望按 IP 连接，不支持主机名。因此无法使用标准的 `host.docker.internal`。
建议使用以下标志启动 Chrome：`--remote-debugging-address=0.0.0.0 --remote-debugging-port=9222 --remote-allow-origins=* --no-first-run --no-default-browser-check --user-data-dir="<临时配置文件目录>"`

## 构建

本地构建镜像：`docker build -t agents .`

完全重新构建：`docker build --no-cache -t agents .`

调试构建：`docker build --progress=plain -t agents .`

删除主目录卷：`docker volume rm agents-dev-home`
