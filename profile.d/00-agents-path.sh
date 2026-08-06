# /etc/profile в Debian безусловно перезаписывает PATH жёстким списком,
# из-за чего login-шеллы теряют /opt/wrapper (обёртки агентов с прокси),
# /usr/local/cargo/bin (rtk, LSP), /opt/go/bin и ~/.npm-global/bin.
# entrypoint.sh кладёт итоговый PATH в AGENTS_PATH — здесь возвращаем его,
# так как /etc/profile.d подключается уже после сброса.
if [ -n "${AGENTS_PATH:-}" ]; then
    PATH="$AGENTS_PATH"
    export PATH
fi
