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
ensure_deps curl openssl tr mktemp install

mkdir -p /usr/local/bin

# Install or update dumbproxy
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
tmp="$(mktemp)"
curl --no-progress-meter -Lo "$tmp" "$dp_download_url"
install "$tmp" /usr/local/bin/dumbproxy
rm "$tmp" || true

mkdir -p /etc/dumbproxy

passwd="$(tr -cd '[:alnum:]' < /dev/urandom | dd bs=1 count=10 2>/dev/null || true)"
/usr/local/bin/dumbproxy -passwd /etc/dumbproxy/passwd "auto" "${passwd}"

cat > /etc/dumbproxy/dumbproxy.cfg <<EOF
auth basicfile://?path=/etc/dumbproxy/passwd
bind-address :443
cert /etc/dumbproxy/fullchain.pem
key /etc/dumbproxy/key.pem
EOF

cat > /etc/systemd/system/dumbproxy.service <<'EOF'
[Unit]
Description=Dumb Proxy
Documentation=https://github.com/SenseUnit/dumbproxy/
After=network.target network-online.target
Requires=network-online.target

[Service]
User=root
Group=root
ExecStart=/usr/local/bin/dumbproxy -config /etc/dumbproxy/dumbproxy.cfg
TimeoutStopSec=5s
PrivateTmp=true
ProtectSystem=full
LimitNOFILE=20000

[Install]
WantedBy=default.target
EOF
systemctl daemon-reload
systemctl enable dumbproxy

# Install or update myip
# 
myip_download_url="https://github.com/Snawoot/myip/releases/latest/download/myip.linux-${dp_arch_map[$arch]}"
tmp="$(mktemp)"
curl --no-progress-meter -Lo "$tmp" "$myip_download_url"
install "$tmp" /usr/local/bin/myip
rm "$tmp" || true

# External IP address discovery
#
ext_ip="$(/usr/local/bin/myip)"

# Install acme.sh
#
curl --no-progress-meter -Lo /usr/local/bin/acme.sh 'https://raw.githubusercontent.com/acmesh-official/acme.sh/refs/heads/master/acme.sh'
chmod +x /usr/local/bin/acme.sh
/usr/local/bin/acme.sh --install-cronjob || true

# Issue certificate
#
acme.sh --issue \
  -d "$ext_ip" \
  --alpn \
  --force \
  --pre-hook "systemctl stop dumbproxy || true" \
  --post-hook "[ -e /etc/dumbproxy/cert.pem -a -e /etc/dumbproxy/fullchain.pem ] && systemctl stop dumbproxy || true" \
  --server letsencrypt \
  --certificate-profile shortlived \
  --days 3

acme.sh --install-cert \
  -d "$ext_ip" \
  --cert-file /etc/dumbproxy/cert.pem \
  --key-file /etc/dumbproxy/key.pem \
  --fullchain-file /etc/dumbproxy/fullchain.pem \
  --reloadcmd "systemctl restart dumbproxy"

cat <<EOF

=========================
Installation is finished!
=========================

Proxy URL: https://auto:${passwd}@${ext_ip}:443

which is

Proxy protocol: https
Proxy port:     443
Proxy host:     ${ext_ip}
Proxy user:     auto
Proxy password: ${passwd}

EOF
