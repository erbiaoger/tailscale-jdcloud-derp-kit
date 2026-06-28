#!/usr/bin/env bash
# 用途:
#   验证自建 DERP、STUN、Tailscale 选路和 SSH 是否正常。
#
# 用例:
#   bash scripts/verify_derp.sh
#
# 输出:
#   - Mac 到 DERP 的路由
#   - DERP HTTPS / STUN / Tailscale debug derp 结果
#   - netcheck 最近 DERP
#   - tailscale ping 与 ssh 测试

set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_config

TS="$(tailscale_bin)"

log "检查到 DERP_HOST 的系统路由"
route -n get "$DERP_HOST" || true

log "检查 HTTPS"
curl -4vk --noproxy '*' --connect-timeout 10 "https://${DERP_HOST}/" -o /dev/null || true

log "检查 HTTP generate_204"
curl -4v --noproxy '*' --connect-timeout 10 "http://${DERP_HOST}/generate_204" -o /dev/null || true

log "检查 Tailscale DERP region ${DERP_REGION_ID}"
"$TS" debug derp "$DERP_REGION_ID" || true

log "检查 netcheck"
"$TS" netcheck || true

log "检查 tailscale ping ${LAB_TAILSCALE_IP}"
"$TS" ping --until-direct=false --c 5 "$LAB_TAILSCALE_IP" || true

log "检查 SSH ${LAB_SSH}"
ssh -o BatchMode=yes -o ConnectTimeout=12 "$LAB_SSH" 'hostname; whoami; tailscale status --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(\"remote relay\", d.get(\"Self\",{}).get(\"Relay\"))"' || true
