#!/bin/bash

# halt on any error for safety and proper pipe handling
set -euo pipefail ; # <- this semicolon and comment make options apply
# even when script is corrupt by CRLF line terminators
# empty line must follow this comment for immediate fail with CRLF newlines

arch="$(uname -m)"

ensure_deps() {
  for dep in "$@"; do
    if ! command -v "$dep" >/dev/null 2>&1 ; then
      >&2 echo "Unable to locate dependency: \"$dep\". Please install it."
      exit 1
    fi
  done
}
ensure_deps curl tar gzip

mkdir -p /usr/local/bin

# Install dumbproxy
#
declare -A dp_arch_map=(
  ["x86_64"]="amd64"
  ["i386"]="386"
  ["i486"]="386"
  ["i586"]="386"
  ["i686"]="386"
  ["aarch64"]="arm64"
  ["armv5l"]="arm"
  ["armv6l"]="arm"
  ["armv7l"]="arm"
  ["armhf"]="arm"
)
dp_download_url="https://github.com/SenseUnit/dumbproxy/releases/latest/download/dumbproxy.linux-${dp_arch_map[$arch]}"

curl --no-progress-meter -Lo /usr/local/bin/dumbproxy "$dp_download_url"
chmod +x /usr/local/bin/dumbproxy


# Install myip
# 
myip_download_url="https://github.com/Snawoot/myip/releases/latest/download/myip.linux-${dp_arch_map[$arch]}"
curl --no-progress-meter -Lo /usr/local/bin/myip "$myip_download_url"
chmod +x /usr/local/bin/myip

ext_ip="$(/usr/local/bin/myip)"
