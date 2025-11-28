#!/usr/bin/env bash
set -euo pipefail

### 0. Проверка прав
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Этот скрипт нужно запускать от root (sudo)."
  exit 1
fi

echo "[*] Настройка хоста для monito-box..."

### 1. Устанавливаем MOTD и /etc/issue*

echo "[*] Копируем файлы motd и issue..."

# Убедимся, что каталог существует
install -d /usr/lib/qubian/update-motd.d

# Копируем 01-header и 15-system-state
install -m 0755 "files/01-header"       "/usr/lib/qubian/update-motd.d/01-header"
install -m 0755 "files/15-system-state" "/usr/lib/qubian/update-motd.d/15-system-state"

# /etc/issue и /etc/issue.net
install -m 0644 "files/issue"     "/etc/issue"
install -m 0644 "files/issue.net" "/etc/issue.net"

### 2. Имя хоста

echo "[*] Меняем hostname на monito-box..."

hostnamectl set-hostname monito-box

# Обновим /etc/hosts, чтобы 127.0.1.1 указывал на monito-box
if grep -q '^127\.0\.1\.1' /etc/hosts; then
  sed -i 's/^127\.0\.1\.1.*/127.0.1.1\tmonito-box/' /etc/hosts
else
  echo -e "127.0.1.1\tmonito-box" >> /etc/hosts
fi

### 3. Пароль root

echo "[*] Меняем пароль root на 'monito'..."

# ВНИМАНИЕ: пароль будет лежать в открытом виде в репозитории GitHub.
echo 'root:monito' | chpasswd

### 4. Блокируем обновление ядра

echo "[*] Ставим hold на установленные пакеты ядра (linux-image*, linux-headers*)..."

# Собираем список уже установленных пакетов ядра
kernel_pkgs=$(dpkg-query -W -f='${Package}\n' 'linux-image*' 'linux-headers*' 2>/dev/null || true)

if [[ -n "${kernel_pkgs}" ]]; then
  echo "${kernel_pkgs}" | xargs -r apt-mark hold
  echo "[*] Заблокированы пакеты:"
  echo "${kernel_pkgs}"
else
  echo "[*] Установленных пакетов linux-image*/linux-headers* не найдено (это странно для Debian, но ладно)."
fi

### 5. Установка пакетов (без обновления ядра)

echo "[*] Устанавливаем пакеты: mc wireguard ssh curl sudo jq fping snmp..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  mc \
  wireguard \
  ssh \
  curl \
  sudo \
  jq \
  fping \
  snmp

### 6. Скрипт /root/monito-install.sh

echo "[*] Создаем /root/monito-install.sh..."

cat >/root/monito-install.sh <<'EOF'
#!/usr/bin/env bash
curl -s https://get.monito.run | bash
EOF

chmod +x /root/monito-install.sh

echo "[+] Готово. Хост настроен как monito-box."
echo "[+] Для установки monito можно запустить /root/monito-install.sh"
echo "[+] Обновление ядра через APT заблокировано (apt-mark hold для linux-image*/linux-headers*)."
