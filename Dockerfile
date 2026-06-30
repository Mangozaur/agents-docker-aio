FROM php:8.4-fpm

# Настраиваем пути
ENV PATH=/opt/wrapper:/home/dev/.npm-global/bin:/opt/go/bin:/usr/local/cargo/bin:$PATH \
    CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    RUST_VERSION=stable \
    GOPATH=/opt/go \
    NPM_CONFIG_PREFIX=/home/dev/.npm-global \
    OPENCODE_CONFIG=/opt/defaults/opencode/opencode.json

RUN apt-get update && apt-get install -y --no-install-recommends \
    jq \
    ripgrep \
    bash \
    git \
    curl \
    gcc \
    build-essential \
    libssl-dev \
    libpng-dev \
    libjpeg-dev \
    libonig-dev \
    libxml2-dev \
    libpq-dev \
    libzip-dev \
    libicu-dev \
    libfreetype6-dev \
    pkg-config \
    zip \
    unzip \
    npm \
    mc \
    make \
    wget \
    tree \
    imagemagick \
    ca-certificates \
    gnupg \
    procps \
    golang-go \
    sudo \
    gosu \
    && rm -rf /var/lib/apt/lists/* \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
        && docker-php-ext-install -j$(nproc) \
            pdo_pgsql \
            pgsql \
            gd \
            zip \
            bcmath \
            exif \
            pcntl \
            intl \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
       | sh -s -- -y --no-modify-path --default-toolchain ${RUST_VERSION:-stable} \
    && rustup component add rustfmt clippy 2>/dev/null || true

# Python 3.13 + pip (multi-stage из официального образа)
COPY --from=python:3.13-slim-bookworm /usr/local/bin/python3.13 /usr/local/bin/
COPY --from=python:3.13-slim-bookworm /usr/local/lib/libpython3.13.so* /usr/local/lib/
COPY --from=python:3.13-slim-bookworm /usr/local/lib/python3.13/ /usr/local/lib/python3.13/
COPY --from=python:3.13-slim-bookworm /usr/local/include/python3.13/ /usr/local/include/python3.13/
RUN ldconfig \
    && ln -sf python3.13 /usr/local/bin/python3 \
    && ln -sf python3.13 /usr/local/bin/python \
    && python3 -m ensurepip --upgrade

# Docker CLI для Docker-outside-of-Docker (DooD)
COPY --from=docker:cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker/compose-bin:latest /docker-compose /usr/local/lib/docker/cli-plugins/docker-compose

# uv / uvx
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
COPY --from=ghcr.io/astral-sh/uv:latest /uvx /usr/local/bin/uvx

RUN chsh -s /bin/bash root

# Создаём пользователя dev (UID 1000 по умолчанию; entrypoint перемапит под хост-UID)
RUN groupadd --gid 999 docker \
    && groupadd --gid 1000 dev \
    && useradd --uid 1000 --gid 1000 --groups docker --home-dir /home/dev --create-home --shell /bin/bash dev \
    && echo 'dev ALL=(ALL) NOPASSWD: ALL' \
       > /etc/sudoers.d/dev-nopasswd \
    && chmod 0440 /etc/sudoers.d/dev-nopasswd

# Установка Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Install Bun by copying from the official image
# This installs bun globally to /usr/local/bin so it is available to everyone
COPY --from=oven/bun:1 /usr/local/bin/bun /usr/local/bin/bun
# Create the bunx symlink (standard practice)
RUN ln -s /usr/local/bin/bun /usr/local/bin/bunx

### Агенты

RUN env -u NPM_CONFIG_PREFIX npm i -g opencode-ai \
    && env -u NPM_CONFIG_PREFIX npm i -g @anthropic-ai/claude-code \
    && env -u NPM_CONFIG_PREFIX npm i -g @openai/codex \
    && env -u NPM_CONFIG_PREFIX npm i -g @qwen-code/qwen-code@latest

# Обходы для слишком подозрительных
RUN mkdir -p /opt/wrapper
COPY wrappers/ /opt/wrapper
RUN chmod -R 0777 /opt/wrapper/

### Тулзы

RUN env -u NPM_CONFIG_PREFIX npm i -g @upstash/context7-mcp@latest \
    && cargo install php-lsp --locked \
    && cargo install phpantom_lsp --locked \
    && go install github.com/laravel-ls/laravel-ls/cmd/laravel-ls@latest

RUN echo "prefix=/home/dev/.npm-global" > /root/.npmrc

SHELL ["/bin/bash", "-c"]

WORKDIR /var/www/html

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]