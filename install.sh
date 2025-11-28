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

echo "[*] Настройка хоста для monito-box..."

### 1. Качаем и устанавливаем MOTD и ISSUE

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

sed -i 's/^127\.0\.1\.1.*/127.0.1.1\tmonito-box/' /etc/hosts || \
echo -e "127.0.1.1\tmonito-box" >> /etc/hosts

### 3. Пароль root

echo "[*] Меняем пароль root на 'monito'..."
echo 'root:monito' | chpasswd

### 4. HOLD ядра

echo "[*] Ставим hold на пакеты ядра..."
kernel_pkgs=$(dpkg-query -W -f='${Package}\n' 'linux-image*' 'linux-headers*' 2>/dev/null || true)
echo "$kernel_pkgs" | xargs -r apt-mark hold

### 5. ПО

echo "[*] Устанавливаем ПО..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y mc wireguard ssh curl sudo jq fping snmp

### 6. Скрипт monito-install.sh

echo "[*] Создаем /root/monito-install.sh..."
cat >/root/monito-install.sh <<'EOF'
#!/usr/bin/env bash
curl -s https://get.monito.run | bash
EOF

chmod +x /root/monito-install.sh

echo "[+] Готово!"
echo "[+] monito-install.sh создан."
echo "[+] Ядро заморожено (apt-mark hold)."
echo "[+] ПО установлено (mc, wireguard, ssh, curl, sudo, jq, fping, snmp)."
echo "[+] Hostname установлен (monito-box)."
echo "[+] Пароль root установлен (monito)."
echo "[+] Скрипт monito-install.sh создан."
echo "[+] Для установки monito выполните /root/monito-install.sh."
