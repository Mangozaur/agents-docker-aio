#!/bin/bash
set -e

TARGET_UID="${HOST_UID:-1000}"
TARGET_GID="${HOST_GID:-1000}"

# Adjust GID
if [ "$(getent group dev | cut -d: -f3)" != "$TARGET_GID" ]; then
    CONFLICT=$(getent group "$TARGET_GID" | cut -d: -f1 || true)
    [ -n "$CONFLICT" ] && [ "$CONFLICT" != "dev" ] && groupmod --gid "$((TARGET_GID + 50000))" "$CONFLICT"
    groupmod --gid "$TARGET_GID" dev
fi

# Adjust UID
if [ "$(id -u dev)" != "$TARGET_UID" ]; then
    CONFLICT=$(getent passwd "$TARGET_UID" | cut -d: -f1 || true)
    [ -n "$CONFLICT" ] && [ "$CONFLICT" != "dev" ] && usermod --uid "$((TARGET_UID + 50000))" "$CONFLICT"
    usermod --uid "$TARGET_UID" dev
fi

# Update sudoers with the current username
USERNAME=$(getent passwd "$TARGET_UID" | cut -d: -f1)
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/dev-nopasswd
chmod 0440 /etc/sudoers.d/dev-nopasswd

# Fix home directory permissions
chown "$TARGET_UID:$TARGET_GID" /home/dev 2>/dev/null || true

# Docker создаёт недостающие родительские каталоги бинд-маунтов от root.
# Выправляем владельца нерекурсивно — рекурсия залезла бы внутрь самих
# бинд-маунтов и переписала права хостовых файлов.
for d in /home/dev/.config; do
    [ -d "$d" ] && chown "$TARGET_UID:$TARGET_GID" "$d" 2>/dev/null || true
done

# Create npm prefix dir if volume is empty
mkdir -p /home/dev/.npm-global/bin /home/dev/.npm-global/lib/node_modules
chown -R "$TARGET_UID:$TARGET_GID" /home/dev/.npm-global

# Remove abandoned npm temp directories (matching .pkg-XXXXXXXX)
# These are left behind after interrupted npm install/update on a Docker volume and block subsequent attempts
find /home/dev/.npm-global/lib/node_modules -maxdepth 2 -type d -name '.*-????????' -exec rm -rf {} + 2>/dev/null || true

# 🐳 Docker-outside-of-Docker: align group GID with host socket
if [ -S /var/run/docker.sock ]; then
    DOCKER_SOCK_GID=$(stat -c '%g' /var/run/docker.sock 2>/dev/null || true)
    if [ -n "$DOCKER_SOCK_GID" ]; then
        EXISTING_GRP=$(getent group "$DOCKER_SOCK_GID" | cut -d: -f1 || true)
        if [ -z "$EXISTING_GRP" ]; then
            groupmod --gid "$DOCKER_SOCK_GID" docker 2>/dev/null || groupadd --gid "$DOCKER_SOCK_GID" docker-host 2>/dev/null || true
            EXISTING_GRP=$(getent group "$DOCKER_SOCK_GID" | cut -d: -f1)
        fi
        usermod -aG "$EXISTING_GRP" dev 2>/dev/null || true
    fi
fi

[ -n "${EXTRA_PATH:-}" ] && export PATH="$EXTRA_PATH:$PATH"

exec gosu "$TARGET_UID" "$@"
