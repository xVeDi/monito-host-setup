#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/xVeDi/monito-host-setup/main/files"

download() {
    local file="$1"
    local dest="$2"

    if command -v wget >/dev/null; then
        wget -qO "$dest" "$REPO_RAW/$file"
    elif command -v curl >/dev/null; then
        curl -fsSL -o "$dest" "$REPO_RAW/$file"
    else
        echo "Нужен wget или curl для загрузки файлов."
        exit 1
    fi
}

### 0. Проверка прав
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Этот скрипт нужно запускать от root."
  exit 1
fi

echo "[*] Настройка хоста для работы Monito..."

### 1. Устанавливаем MOTD и issue*

echo "[*] Копируем файлы motd и issue..."

install -d /usr/lib/qubian/update-motd.d

download "01-header"       "/usr/lib/qubian/update-motd.d/01-header"
download "15-system-state" "/usr/lib/qubian/update-motd.d/15-system-state"

download "issue"     "/etc/issue"
download "issue.net" "/etc/issue.net"

chmod 755 /usr/lib/qubian/update-motd.d/01-header
chmod 755 /usr/lib/qubian/update-motd.d/15-system-state
chmod 644 /etc/issue /etc/issue.net

### 2. Имя хоста

echo "[*] Меняем hostname на monito-box..."
hostnamectl set-hostname monito-box

if grep -q '^127\.0\.1\.1' /etc/hosts; then
  sed -i 's/^127\.0\.1\.1.*/127.0.1.1\tmonito-box/' /etc/hosts
else
  echo -e "127.0.1.1\tmonito-box" >> /etc/hosts
fi

### 3. Пароль root

echo "[*] Меняем пароль root на 'monito'..."
echo 'root:monito' | chpasswd

### 4. HOLD ядра

echo "[*] Ставим hold на пакеты ядра..."

kernel_pkgs=$(dpkg -l 'linux-image*' 'linux-headers*' 2>/dev/null \
  | awk '/^ii/ {print $2}' \
  | grep -E '^(linux-image|linux-headers)-' || true)

if [[ -n "${kernel_pkgs}" ]]; then
  echo "[*] Найдены пакеты ядра для hold:"
  echo "${kernel_pkgs}"
  for pkg in ${kernel_pkgs}; do
    if apt-mark hold "${pkg}" >/dev/null 2>&1; then
      echo "    - ${pkg} поставлен на hold"
    else
      echo "    - [WARN] не удалось поставить на hold ${pkg}"
    fi
  done
else
  echo "[*] Установленных пакетов linux-image-*/linux-headers-* не найдено."
fi

### 5. Полный запрет установки новых ядер через APT (pinning)

echo "[*] Включаем APT pinning: запрещаем установку любых новых ядер и headers..."

cat >/etc/apt/preferences.d/no-kernel <<'EOF'
Package: linux-image*
Pin: version *
Pin-Priority: -1

Package: linux-headers*
Pin: version *
Pin-Priority: -1
EOF

echo "[*] APT pinning установлен: linux-image* и linux-headers* больше не будут устанавливаться."


### 6. Установка ПО

echo "[*] Устанавливаем ПО..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y mc wireguard-tools ssh curl sudo jq fping snmp

### 7. Фикс /boot/boot.config

echo "[*] Правим /boot/boot.config..."

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

# Попытка сделать immutable
if command -v chattr >/dev/null 2>&1; then
  chattr +i "${BOOTCFG}" || echo "[WARN] Не удалось выставить immutable на ${BOOTCFG}"
  echo "[*] ${BOOTCFG} помечен как immutable"
else
  echo "[WARN] chattr не найден, immutable не установлен."
fi

### 8. Скрипт установки monito

echo "[*] Создаем /root/monito-install.sh..."
cat >/root/monito-install.sh <<'EOF'
#!/usr/bin/env bash
curl -s https://get.monito.run | bash
EOF

chmod +x /root/monito-install.sh

### 9. Финальное сообщение

echo
echo "[✓] Установка завершена!"
echo "[✓] Ядро зафиксировано и boot.config защищён."
echo "[✓] Для установки Monito запускайте: /root/monito-install.sh"
echo

read -r -p "Хотите выполнить перезагрузку сейчас? [y/N]: " ans
case "${ans,,}" in
    y|yes)
        echo "Перезагрузка..."
        sleep 1
        reboot
        ;;
    *)
        echo "Ок, перезагрузка отменена. Не забудьте выполнить reboot позже."
        ;;
esac
