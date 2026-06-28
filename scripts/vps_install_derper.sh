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
#   - 生成标准 397 天 IP SAN 自签证书
#   - 写入 /etc/systemd/system/derper.service
#   - 重启 derper，并打印证书指纹与 DERPMap 提示
#
# 重要:
#   云厂商安全组仍需放行 TCP 443、TCP 80、UDP 3478。

set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_config

ROOT="$(repo_root)"

log "目标 VPS: ${VPS_SSH}"
log "DERP Host: ${DERP_HOST}"
log "derper version: ${DERPER_VERSION}"

ssh "$VPS_SSH" "DERP_HOST='$DERP_HOST' DERPER_VERSION='$DERPER_VERSION' bash -s" <<'REMOTE'
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

log "备份旧 derper"
if [[ -x /usr/local/bin/derper ]]; then
  cp -a /usr/local/bin/derper "/usr/local/bin/derper.bak.$(date +%Y%m%d-%H%M%S)"
fi

log "安装 derper ${DERPER_VERSION}"
GOBIN=/usr/local/bin go install "tailscale.com/cmd/derper@${DERPER_VERSION}"
/usr/local/bin/derper -version || true

log "生成标准 IP SAN 自签证书，有效期 397 天"
install -d -m 700 /var/lib/derper/certs
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
chmod 600 "/var/lib/derper/certs/${DERP_HOST}.key"

log "写入 systemd 服务"
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
