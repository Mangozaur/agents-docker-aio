#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME="$SCRIPT_DIR/home"

DEV_IMAGE="${DEV_IMAGE:-agents}"
DEV_VOLUME="agents-dev-home"
CONTAINER_HOME="/home/dev"

# 📁 Project directory (argument or current)
if [ $# -gt 0 ]; then
    HOST_DIR="$1"
    shift
else
    HOST_DIR="$(pwd)"
fi

CMD=("$@")
[ ${#CMD[@]} -eq 0 ] && CMD=("/bin/bash")

if [ ! -d "$HOST_DIR" ]; then
    echo "❌ Directory not found: $HOST_DIR" >&2
    exit 1
fi
HOST_DIR="$(cd "$HOST_DIR" && pwd)"


# 📦 Create volume if missing
docker volume create "$DEV_VOLUME" >/dev/null 2>&1 || true

# 🔧 Fix volume permissions for the user (only runs when UID/GID changes)
docker run --rm --user 0:0 -v "$DEV_VOLUME:$CONTAINER_HOME" "$DEV_IMAGE" \
  chown -R "$(id -u):$(id -g)" "$CONTAINER_HOME" 2>/dev/null || true

# 🌐 Environment settings from .env (proxy, etc.)
ENV_ARGS=()
if [ -f "$SCRIPT_DIR/.env" ]; then
    ENV_ARGS+=(--env-file "$SCRIPT_DIR/.env")
fi

# 🔌 Port forwarding settings: from project .agents.env or .env
PORT_ARGS=()

_get_env_from() {
  local val
  val=$(grep -E "^${1}=" "$2" 2>/dev/null | head -n1 | cut -d'=' -f2-)
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  if [[ "$val" == \"*\" ]]; then
    val="${val#\"}" ; val="${val%\"}"
  elif [[ "$val" == \'*\' ]]; then
    val="${val#\'}" ; val="${val%\'}"
  fi
  echo "$val"
}

_find_free_port() {
  local preferred="${1:-0}"
  if [[ "$preferred" =~ ^[0-9]+$ ]] && [ "$preferred" -gt 0 ]; then
    if ! ss -tlnp 2>/dev/null | grep -qE ":${preferred}[[:space:]]"; then
      echo "$preferred"
      return
    fi
    echo "⚠️  Port ${preferred} is busy, looking for a free one..." >&2
  fi
  local port
  while true; do
    port=$(shuf -i 49152-65535 -n 1)
    if ! ss -tlnp 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
      echo "$port"
      return
    fi
  done
}

_sanitize_name() {
  local s="$1"
  s="${s//щ/shch}"; s="${s//Щ/Shch}"
  s="${s//ё/yo}";   s="${s//Ё/Yo}"
  s="${s//ж/zh}";   s="${s//Ж/Zh}"
  s="${s//ц/ts}";   s="${s//Ц/Ts}"
  s="${s//ч/ch}";   s="${s//Ч/Ch}"
  s="${s//ш/sh}";   s="${s//Ш/Sh}"
  s="${s//ъ/}";     s="${s//Ъ/}"
  s="${s//ы/y}";    s="${s//Ы/Y}"
  s="${s//ь/}";     s="${s//Ь/}"
  s="${s//э/e}";    s="${s//Э/E}"
  s="${s//ю/yu}";   s="${s//Ю/Yu}"
  s="${s//я/ya}";   s="${s//Я/Ya}"
  s="${s//є/ye}";   s="${s//Є/Ye}"
  s="${s//ї/yi}";   s="${s//Ї/Yi}"
  s="${s//і/i}";    s="${s//І/I}"
  s="${s//ґ/g}";    s="${s//Ґ/G}"
  s="${s//а/a}"; s="${s//А/A}"
  s="${s//б/b}"; s="${s//Б/B}"
  s="${s//в/v}"; s="${s//В/V}"
  s="${s//г/g}"; s="${s//Г/G}"
  s="${s//д/d}"; s="${s//Д/D}"
  s="${s//е/e}"; s="${s//Е/E}"
  s="${s//з/z}"; s="${s//З/Z}"
  s="${s//и/i}"; s="${s//И/I}"
  s="${s//й/y}"; s="${s//Й/Y}"
  s="${s//к/k}"; s="${s//К/K}"
  s="${s//л/l}"; s="${s//Л/L}"
  s="${s//м/m}"; s="${s//М/M}"
  s="${s//н/n}"; s="${s//Н/N}"
  s="${s//о/o}"; s="${s//О/O}"
  s="${s//п/p}"; s="${s//П/P}"
  s="${s//р/r}"; s="${s//Р/R}"
  s="${s//с/s}"; s="${s//С/S}"
  s="${s//т/t}"; s="${s//Т/T}"
  s="${s//у/u}"; s="${s//У/U}"
  s="${s//ф/f}"; s="${s//Ф/F}"
  s="${s//х/kh}"; s="${s//Х/Kh}"
  s=$(printf '%s' "$s" | tr 'A-Z' 'a-z')
  s="${s// /-}"
  s=$(printf '%s' "$s" | tr -c 'a-z0-9.-' '-')
  while [[ "$s" == *--* ]]; do s="${s//--/-}"; done
  s="${s#-}"; s="${s%-}"
  [ -z "$s" ] && s=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s' "$s"
}

if [ -f "$HOST_DIR/.agents.env" ]; then
    PORT_ENV_FILE="$HOST_DIR/.agents.env"
elif [ -f "$SCRIPT_DIR/.env" ]; then
    PORT_ENV_FILE="$SCRIPT_DIR/.env"
else
    PORT_ENV_FILE=""
fi

if [ -n "$PORT_ENV_FILE" ]; then
    FWD_HOST_PORT=$(_get_env_from "FWD_HOST_PORT" "$PORT_ENV_FILE")
    FWD_CONTAINER_PORT=$(_get_env_from "FWD_CONTAINER_PORT" "$PORT_ENV_FILE")

    if [ -n "$FWD_CONTAINER_PORT" ] && [[ "$FWD_CONTAINER_PORT" =~ ^[0-9]+$ ]]; then
        RESOLVED_HOST_PORT=$(_find_free_port "$FWD_HOST_PORT")
        PORT_ARGS+=("-p" "${RESOLVED_HOST_PORT}:${FWD_CONTAINER_PORT}")
        echo "🌐 Port forwarding: ${RESOLVED_HOST_PORT} → ${FWD_CONTAINER_PORT}" >&2
    fi
fi

# 📛 Mount name: from .agents.env or current directory name
MOUNT_NAME=$(_get_env_from "MOUNT_NAME" "$PORT_ENV_FILE")
_DIR_NAME="${MOUNT_NAME:-$(basename "$HOST_DIR")}"
CONTAINER_WORKDIR="/var/www/$_DIR_NAME"
CONTAINER_NAME="agents-$(_sanitize_name "$_DIR_NAME")-$(head -c 4 /dev/urandom | xxd -p)"

EXTRA_PATH=$(_get_env_from "EXTRA_PATH" "$PORT_ENV_FILE")
[ -z "$EXTRA_PATH" ] && [ -f "$SCRIPT_DIR/.env" ] && EXTRA_PATH=$(_get_env_from "EXTRA_PATH" "$SCRIPT_DIR/.env")

DOCKER_NETWORK=$(_get_env_from "DOCKER_NETWORK" "$PORT_ENV_FILE")

EXEC_BEFORE=$(_get_env_from "EXEC_BEFORE" "$PORT_ENV_FILE")
EXEC_AFTER=$(_get_env_from "EXEC_AFTER" "$PORT_ENV_FILE")

if [ -n "$EXEC_AFTER" ]; then
    _exec_or_run() { "$@"; }
    trap 'eval "$EXEC_AFTER"' EXIT
else
    _exec_or_run() { exec "$@"; }
fi

if [ -n "$DOCKER_NETWORK" ]; then
    NETWORK_ARGS=("--network" "$DOCKER_NETWORK")
    echo "🔗 Docker network: $DOCKER_NETWORK" >&2
else
    NETWORK_ARGS=()
fi

if [ -n "$EXEC_BEFORE" ]; then
    eval "$EXEC_BEFORE"
fi

# 🎧 WSL: forward WSLg PulseAudio socket (no-op on Linux/macOS)
WSL_ARGS=()
_is_wsl() {
    [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi "microsoft" /proc/version 2>/dev/null
}
if _is_wsl && [ -S "/mnt/wslg/PulseServer" ]; then
    WSL_ARGS+=(
        "-e" "PULSE_SERVER=unix:/mnt/wslg/PulseServer"
        "-v" "/mnt/wslg/:/mnt/wslg/"
    )
fi

# 🐳 Docker-outside-of-Docker: forward Docker socket
DOCKER_ARGS=()
ENABLE_DOCKER=$(_get_env_from "ENABLE_DOCKER" "$PORT_ENV_FILE")
if [ -z "$ENABLE_DOCKER" ] && [ -f "$SCRIPT_DIR/.env" ]; then
    ENABLE_DOCKER=$(_get_env_from "ENABLE_DOCKER" "$SCRIPT_DIR/.env")
fi
if [[ "${ENABLE_DOCKER:-true}" != "false" ]] && [ -S /var/run/docker.sock ]; then
    DOCKER_ARGS+=("-v" "/var/run/docker.sock:/var/run/docker.sock")
    echo "🐳 Docker socket forwarded" >&2
fi

# 🔗 Selective mounts
EXTRA_VOLUMES=()
mount_if_exists() {
    local src="$1" target="$2" opts="${3:-ro}"
    if [ -e "$src" ]; then
        EXTRA_VOLUMES+=("-v" "$src:$target:$opts")
    fi
}

mount_if_exists "$HOME/.ai"                  "$CONTAINER_HOME/.ai"                  "rw"
mount_if_exists "$SCRIPT_DIR/defaults/opencode/opencode.json" "/opt/defaults/opencode/opencode.json" "ro"
mount_if_exists "$HOME/.bashrc"              "$CONTAINER_HOME/.bashrc"              "ro"

mount_if_exists "$HOME/.config/opencode"     "$CONTAINER_HOME/.config/opencode"     "rw"
mount_if_exists "$HOME/.claude"              "$CONTAINER_HOME/.claude"              "rw"
mount_if_exists "$HOME/.qwen"                "$CONTAINER_HOME/.qwen"                "rw"
mount_if_exists "$HOME/.codex"               "$CONTAINER_HOME/.codex"               "rw"

mount_if_exists "$HOME/.gitconfig"           "$CONTAINER_HOME/.gitconfig"           "ro"
mount_if_exists "$HOME/.npmrc"               "$CONTAINER_HOME/.npmrc"               "ro"
mount_if_exists "$HOME/.ssh"                 "$CONTAINER_HOME/.ssh"                 "ro"
mount_if_exists "$HOME/.config/git"          "$CONTAINER_HOME/.config/git"          "ro"
mount_if_exists "$HOME/.docker/config.json"  "$CONTAINER_HOME/.docker/config.json"  "ro"

# 🚀 One-shot run — container is removed on exit
_exec_or_run docker run -it --rm \
  --pull=missing \
  --init \
  --name "$CONTAINER_NAME" \
  -v "$DEV_VOLUME:$CONTAINER_HOME" \
  "${EXTRA_VOLUMES[@]}" \
  -v "$HOST_DIR:$CONTAINER_WORKDIR" \
  -w "$CONTAINER_WORKDIR" \
  -e HOME="$CONTAINER_HOME" \
  -e USER="$(whoami)" \
  -e PS1='$USER@\h:\w\$ ' \
  -e TERM="${TERM:-xterm}" \
  -e LANG=C.UTF-8 \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -e EXTRA_PATH="${EXTRA_PATH:-}" \
  "${ENV_ARGS[@]}" \
  "${PORT_ARGS[@]}" \
  "${WSL_ARGS[@]}" \
  "${DOCKER_ARGS[@]}" \
  "${NETWORK_ARGS[@]}" \
  --hostname dev \
  --add-host=host.docker.internal:host-gateway \
  "$DEV_IMAGE" "${CMD[@]}"
