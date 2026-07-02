#!/usr/bin/env bash
# 用途:
#   在京东云或其他 Ubuntu 云服务器上一键安装/更新 Tailscale derper。
#
# 用例:
#   1. 先复制配置:
#      cp config.env.example config.env
#   2. 修改 config.env 中的 VPS_SSH / DERP_HOST / DERPER_VERSION。
#   3. 运行:
#      bash scripts/vps_install_derper.sh
#
# 输出:
#   - 安装或更新 /usr/local/bin/derper
#   - 复用已有 IP SAN 自签证书；缺失时才生成标准 397 天证书
#   - 写入 /etc/systemd/system/derper.service
#   - 重启 derper，并打印证书指纹与 DERPMap 提示
#
# 重要:
#   云厂商安全组仍需放行 TCP 443、TCP 80、UDP 3478。
#   如确实需要换证书，运行:
#     FORCE_RENEW_DERP_CERT=1 bash scripts/vps_install_derper.sh

set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_config

ROOT="$(repo_root)"

log "目标 VPS: ${VPS_SSH}"
log "DERP Host: ${DERP_HOST}"
log "derper version: ${DERPER_VERSION}"

ssh "$VPS_SSH" "DERP_HOST='$DERP_HOST' DERPER_VERSION='$DERPER_VERSION' FORCE_RENEW_DERP_CERT='${FORCE_RENEW_DERP_CERT:-0}' bash -s" <<'REMOTE'
set -euo pipefail

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

log "检查系统依赖"
if ! command -v go >/dev/null 2>&1; then
  log "安装 Go"
  apt-get update
  apt-get install -y golang-go
fi

if ! command -v openssl >/dev/null 2>&1; then
  apt-get update
  apt-get install -y openssl ca-certificates
fi

log "停用会抢占 80/443 的代理服务"
systemctl stop xray nginx subscription-server >/dev/null 2>&1 || true
systemctl disable xray nginx subscription-server >/dev/null 2>&1 || true
rm -f /etc/systemd/system/multi-user.target.wants/xray.service \
  /etc/systemd/system/multi-user.target.wants/nginx.service \
  /etc/systemd/system/multi-user.target.wants/subscription-server.service
chattr -i /etc/systemd/system/xray.service /etc/systemd/system/nginx.service >/dev/null 2>&1 || true
if [[ -f /root/install_xray_reality.sh ]]; then
  mv -f /root/install_xray_reality.sh "/root/install_xray_reality.sh.disabled.$(date +%Y%m%d-%H%M%S)"
fi
chmod 000 /root/install_xray_reality.sh.disabled.* >/dev/null 2>&1 || true

cat >/etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Disabled: conflicts with Tailscale DERP on TCP/UDP 443
RefuseManualStart=yes

[Service]
Type=oneshot
ExecStart=/bin/false
EOF

cat >/etc/systemd/system/nginx.service <<'EOF'
[Unit]
Description=Disabled: conflicts with Tailscale DERP on TCP 80
RefuseManualStart=yes

[Service]
Type=oneshot
ExecStart=/bin/false
EOF

chattr +i /etc/systemd/system/xray.service /etc/systemd/system/nginx.service >/dev/null 2>&1 || true

log "备份旧 derper"
if [[ -x /usr/local/bin/derper ]]; then
  cp -a /usr/local/bin/derper "/usr/local/bin/derper.bak.$(date +%Y%m%d-%H%M%S)"
fi

log "安装 derper ${DERPER_VERSION}"
GOBIN=/usr/local/bin go install "tailscale.com/cmd/derper@${DERPER_VERSION}"
/usr/local/bin/derper -version || true

install -d -m 700 /var/lib/derper/certs

if [[ "${FORCE_RENEW_DERP_CERT}" == "1" || ! -f "/var/lib/derper/certs/${DERP_HOST}.crt" || ! -f "/var/lib/derper/certs/${DERP_HOST}.key" ]]; then
  log "生成标准 IP SAN 自签证书，有效期 397 天"
  if [[ -f "/var/lib/derper/certs/${DERP_HOST}.crt" ]]; then
    cp -a "/var/lib/derper/certs/${DERP_HOST}.crt" "/var/lib/derper/certs/${DERP_HOST}.crt.bak.$(date +%Y%m%d-%H%M%S)"
  fi
  if [[ -f "/var/lib/derper/certs/${DERP_HOST}.key" ]]; then
    cp -a "/var/lib/derper/certs/${DERP_HOST}.key" "/var/lib/derper/certs/${DERP_HOST}.key.bak.$(date +%Y%m%d-%H%M%S)"
  fi

  openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 397 \
    -keyout "/var/lib/derper/certs/${DERP_HOST}.key" \
    -out "/var/lib/derper/certs/${DERP_HOST}.crt" \
    -subj "/CN=${DERP_HOST}" \
    -addext "subjectAltName=IP:${DERP_HOST}" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
    -addext "extendedKeyUsage=serverAuth" >/dev/null 2>&1
else
  log "复用已有 DERP 证书，避免客户端和实验室服务器信任失效"
fi
chmod 600 "/var/lib/derper/certs/${DERP_HOST}.key"

log "写入 systemd 服务"
chattr -i /etc/systemd/system/derper.service >/dev/null 2>&1 || true
systemctl unmask derper >/dev/null 2>&1 || true
if [[ -L /etc/systemd/system/derper.service && "$(readlink /etc/systemd/system/derper.service)" == "/dev/null" ]]; then
  rm -f /etc/systemd/system/derper.service
fi
cat >/etc/systemd/system/derper.service <<EOF
[Unit]
Description=Tailscale DERP relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/derper -a :443 -hostname ${DERP_HOST} -certmode manual -certdir /var/lib/derper/certs -http-port 80 -stun-port 3478
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
chattr +i /etc/systemd/system/derper.service >/dev/null 2>&1 || true

log "重启 derper"
systemctl daemon-reload
systemctl enable derper
systemctl restart derper
sleep 1
systemctl status derper --no-pager -l | sed -n '1,80p'

log "监听端口"
ss -ltnup | grep -E ':(80|443|3478)' || true

fingerprint="$(openssl x509 -in "/var/lib/derper/certs/${DERP_HOST}.crt" -outform DER | sha256sum | awk '{print $1}')"
log "证书 SHA256 指纹: ${fingerprint}"
log "注意: 当前已验证方案在 DERPMap 中使用 CertName=${DERP_HOST}，不是 sha256-raw。"
REMOTE

log "拉取公开证书到 ${ROOT}/${LOCAL_CERT_PATH}"
mkdir -p "$ROOT/$(dirname "$LOCAL_CERT_PATH")"
ssh "$VPS_SSH" "cat /var/lib/derper/certs/${DERP_HOST}.crt" > "$ROOT/$LOCAL_CERT_PATH"
openssl x509 -in "$ROOT/$LOCAL_CERT_PATH" -noout -subject -dates -fingerprint -sha256

log "完成。下一步: bash scripts/mac_install_derp_cert.sh"
