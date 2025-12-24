#!/bin/bash
# (c) 2020 devmfc
# modified: full IP + clock blink via brightness + chip temperature (works on W2)

# Path to the display device
dev_path=$(dirname /sys/bus/platform/drivers/tm16xx*/*/digits)

# Function to write characters to the display
write_digits() {
  echo -e "$1" > "$dev_path/digits"
}

# Function to scroll text on the display
scroll4() {
  local text="$1"
  local delay="${2:-0.22}"
  local pad="${3:-4}"

  local padding
  padding=$(printf '%*s' "$pad" "")
  local s="${padding}${text}${padding}"
  local len=${#s}

  for ((i=0; i<=len-4; i++)); do
    write_digits "${s:i:4}"
    sleep "$delay"
  done
}

# Get a list of IP addresses (excluding loopback)
get_ips_pretty() {
  ip -brief -4 addr show up 2>/dev/null \
    | awk '$1!="lo" {print $3}' \
    | cut -d'/' -f1 \
    | paste -sd' ' - \
    | sed 's/[[:space:]]\+/ /g; s/[[:space:]]$//'
}

# Start the service
start() {
  touch /run/tm16xx.run
  echo 'none' > /sys/class/leds/tm16xx\:\:power/trigger
  echo 1 > /sys/class/leds/tm16xx\:\:power/brightness
  echo 6 > "$dev_path/brightness"

  # Welcome message
  scroll4 "HELLO" 0.28 4
  sleep 0.3

  while [[ -f "$dev_path/digits" && -f /run/tm16xx.run ]]; do

    # USB indication, if available
    if [[ -e /sys/class/leds/tm16xx::usb ]]; then
      ls /sys/class/block -al | grep usb &>/dev/null \
        && echo 1 > /sys/class/leds/tm16xx::usb/brightness \
        || echo 0 > /sys/class/leds/tm16xx::usb/brightness
    fi

    # Display IP addresses
    ips=$(get_ips_pretty)
    [[ -z "$ips" ]] && ips="NET OFF"
    scroll4 "IP $ips" 0.20 2
    sleep 0.4

    # Display current time with blinking separator
    count=10
    while [ "$count" -gt 0 ]; do
      echo 7 > "$dev_path/brightness"
      write_digits "$(date +"%H%M")"
      sleep 0.5
      echo 6 > "$dev_path/brightness"
      write_digits "$(date +"%H%M")"
      sleep 0.5
      count=$((count - 1))
    done
    echo 6 > "$dev_path/brightness"

    # Display chip temperature
    temp=$(cat /sys/devices/virtual/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
    write_digits "${temp:0:2}*C"
    sleep 4
  done

  write_digits ""
  echo "stop"
}

# Stop the service
stop() {
  echo stopping...
  rm -f /run/tm16xx.run
  sleep 0.2
  echo 0 > "$dev_path/brightness"
}

# Command-line argument handling
case "$1" in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  status) ;;
  *) echo "Usage: $0 {start|stop|status|restart}" ;;
esac

exit 0
