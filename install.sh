#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/xVeDi/monito-host-setup/main/files"

log() {
    echo "[`date '+%Y-%m-%d %H:%M:%S'`] $1"
}

check_command() {
    if ! command -v "$1" >/dev/null; then
        log "[ERROR] Команда $1 не найдена. Установите её и повторите попытку."
        exit 1
    fi
}

# Проверка необходимых команд
check_command wget
check_command curl
check_command hostnamectl
check_command timedatectl
check_command chpasswd
check_command apt-get

# Функция загрузки файлов с проверкой существования
safe_download() {
    local file="$1"
    local dest="$2"

    if [[ -f "$dest" ]]; then
        log "[INFO] Файл $dest уже существует, пропускаем загрузку."
        return
    fi

    if command -v wget >/dev/null; then
        wget -qO "$dest" "$REPO_RAW/$file"
    elif command -v curl >/dev/null; then
        curl -fsSL -o "$dest" "$REPO_RAW/$file"
    else
        log "[ERROR] Нужен wget или curl для загрузки файлов."
        exit 1
    fi
}

# Проверка прав
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log "[ERROR] Этот скрипт нужно запускать от root."
    exit 1
fi

log "[*] Настройка хоста для работы Monito..."

# Устанавливаем MOTD и issue*
log "[*] Копируем файлы motd и issue..."
install -d /usr/lib/qubian/update-motd.d

safe_download "01-header"       "/usr/lib/qubian/update-motd.d/01-header"
safe_download "15-system-state" "/usr/lib/qubian/update-motd.d/15-system-state"

safe_download "issue"     "/etc/issue"
safe_download "issue.net" "/etc/issue.net"

chmod 755 /usr/lib/qubian/update-motd.d/01-header
chmod 755 /usr/lib/qubian/update-motd.d/15-system-state
chmod 644 /etc/issue /etc/issue.net

# Имя хоста
log "[*] Меняем hostname на monito-box..."
hostnamectl set-hostname monito-box

if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sed -i 's/^127\.0\.1\.1.*/127.0.1.1\tmonito-box/' /etc/hosts
else
    echo -e "127.0.1.1\tmonito-box" >> /etc/hosts
fi

# Временная зона
log "[*] Устанавливаем временную зону Europe/Moscow..."
timedatectl set-timezone Europe/Moscow

# Пароль root
log "[*] Меняем пароль root на 'monito'..."
echo 'root:monito' | chpasswd

# HOLD ядра
log "[*] Ставим hold на пакеты ядра..."
kernel_pkgs=$(dpkg -l 'linux-image*' 'linux-headers*' 2>/dev/null \
  | awk '/^ii/ {print $2}' \
  | grep -E '^(linux-image|linux-headers)-' || true)

if [[ -n "${kernel_pkgs}" ]]; then
    log "[*] Найдены пакеты ядра для hold:"
    echo "${kernel_pkgs}"
    for pkg in ${kernel_pkgs}; do
        if apt-mark hold "${pkg}" >/dev/null 2>&1; then
            log "    - ${pkg} поставлен на hold"
        else
            log "    - [WARN] не удалось поставить на hold ${pkg}"
        fi
    done
else
    log "[*] Установленных пакетов linux-image-*/linux-headers-* не найдено."
fi

# Полный запрет установки новых ядер через APT (pinning)
log "[*] Включаем APT pinning: запрещаем установку любых новых ядер и headers..."
cat >/etc/apt/preferences.d/no-kernel <<'EOF'
Package: linux-image*
Pin: version *
Pin-Priority: -1

Package: linux-headers*
Pin: version *
Pin-Priority: -1
EOF

log "[*] APT pinning установлен: linux-image* и linux-headers* больше не будут устанавливаться."

# Установка ПО
log "[*] Устанавливаем ПО..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y mc wireguard-tools ssh curl sudo jq fping snmp

# Фикс /boot/boot.config
log "[*] Правим /boot/boot.config..."

BOOTCFG="/boot/boot.config"

if [[ -f "${BOOTCFG}" ]]; then
    sed -i 's/^majorbranch=.*/majorbranch=6.x.y/' "${BOOTCFG}" || true
    sed -i 's/^branch=.*/branch=6.12.y/' "${BOOTCFG}" || true
    sed -i 's/^release=.*/release=6.12.17-meson64/' "${BOOTCFG}" || true
    sed -i 's/^variant=.*/variant=mainline/' "${BOOTCFG}" || true
else
    cat >"${BOOTCFG}" <<'EOF'
# Kernel version config
majorbranch=6.x.y
branch=6.12.y
release=6.12.17-meson64
variant=mainline
EOF
fi

chmod 644 "${BOOTCFG}"
chown root:root "${BOOTCFG}"

if command -v chattr >/dev/null 2>&1; then
    chattr +i "${BOOTCFG}" || log "[WARN] Не удалось выставить immutable на ${BOOTCFG}"
    log "[*] ${BOOTCFG} помечен как immutable"
else
    log "[WARN] chattr не найден, immutable не установлен."
fi

# Скрипт установки monito
log "[*] Создаем /root/monito-install.sh..."
cat >/root/monito-install.sh <<'EOF'
#!/usr/bin/env bash
curl -s https://get.monito.run | bash
EOF

chmod +x /root/monito-install.sh

# Финальное сообщение
log "[✓] Установка завершена!"
log "[✓] Ядро зафиксировано и boot.config защищён."
log "[✓] Для установки Monito запускайте: /root/monito-install.sh"

read -r -p "Хотите выполнить перезагрузку сейчас? [y/N]: " ans
case "${ans,,}" in
    y|yes)
        log "Перезагрузка..."
        sleep 1
        reboot
        ;;
    *)
        log "Ок, перезагрузка отменена. Не забудьте выполнить reboot позже."
        ;;
esac
