#!/usr/bin/env bash
# 用途:
#   把 DERP 自签证书安装到实验室 Linux 服务器的系统 CA 中，并重启 tailscaled。
#
# 用例:
#   bash scripts/linux_install_derp_cert.sh
#
# 输出:
#   - 远程 /usr/local/share/ca-certificates/jdc-derper-*.crt
#   - update-ca-certificates 输出
#   - 远程 openssl verify 验证结果
#
# 说明:
#   如果实验室服务器没有信任 DERP 自签证书，Tailscale 可能显示 Relay=jdc，
#   但实际 tailscale ping / ssh 会黑洞超时。

set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_config

ROOT="$(repo_root)"
CERT="$ROOT/$LOCAL_CERT_PATH"
[[ -f "$CERT" ]] || die "找不到证书: $CERT。先运行 scripts/vps_install_derper.sh 或 scripts/mac_install_derp_cert.sh"

REMOTE_CERT="/tmp/jdc-derper-${DERP_HOST}.crt"
REMOTE_CA="/usr/local/share/ca-certificates/jdc-derper-${DERP_HOST}.crt"

log "上传证书到实验室服务器: ${LAB_SSH}"
scp "$CERT" "${LAB_SSH}:${REMOTE_CERT}"

log "安装证书到远程系统 CA，并重启 tailscaled。这里可能需要输入远程 sudo 密码。"
ssh -tt "$LAB_SSH" "sudo install -m 0644 '${REMOTE_CERT}' '${REMOTE_CA}' && sudo update-ca-certificates && sudo systemctl restart tailscaled && openssl verify -CApath /etc/ssl/certs '${REMOTE_CERT}'"

log "完成。下一步: bash scripts/generate_derpmap.sh --force-only"
