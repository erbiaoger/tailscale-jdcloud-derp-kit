#!/usr/bin/env bash
# 用途:
#   在 Mac 上安装 DERP 自签证书到当前用户登录钥匙串，并验证 TLS。
#
# 用例:
#   bash scripts/mac_install_derp_cert.sh
#
# 输出:
#   - certs/jdc-derper-*.crt
#   - macOS security verify-cert 验证结果
#
# 说明:
#   当前方案使用 IP 自签证书 + DERPMap CertName=IP。
#   Mac 必须信任这张证书，否则 Tailscale 会报 unknown authority。

set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_config

ROOT="$(repo_root)"
CERT="$ROOT/$LOCAL_CERT_PATH"

if [[ ! -f "$CERT" ]]; then
  log "本地没有证书，尝试从 VPS 拉取"
  mkdir -p "$(dirname "$CERT")"
  ssh "$VPS_SSH" "cat /var/lib/derper/certs/${DERP_HOST}.crt" > "$CERT"
fi

log "证书信息"
openssl x509 -in "$CERT" -noout -subject -issuer -dates -fingerprint -sha256

log "安装到当前用户登录钥匙串"
security add-trusted-cert -d -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$CERT"

log "验证 Mac 信任"
security verify-cert -c "$CERT" -p ssl -s "$DERP_HOST" || true

log "验证 HTTPS"
curl -4vk --noproxy '*' --connect-timeout 10 "https://${DERP_HOST}/" -o /dev/null

log "完成。下一步: bash scripts/linux_install_derp_cert.sh"
