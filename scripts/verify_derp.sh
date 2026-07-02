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
status=0

log "检查到 DERP_HOST 的系统路由"
route -n get "$DERP_HOST" || true

log "检查 HTTPS"
if ! curl -4vk --noproxy '*' --connect-timeout 10 "https://${DERP_HOST}/" -o /dev/null; then
  status=1
fi

log "检查 HTTP generate_204"
if ! curl -4v --noproxy '*' --connect-timeout 10 "http://${DERP_HOST}/generate_204" -o /dev/null; then
  status=1
fi

log "检查 Tailscale DERP region ${DERP_REGION_ID}"
if ! "$TS" debug derp "$DERP_REGION_ID"; then
  status=1
fi

log "检查 netcheck"
if ! "$TS" netcheck; then
  status=1
fi

log "检查 tailscale ping ${LAB_TAILSCALE_IP}"
if ! "$TS" ping --until-direct=false --c 5 "$LAB_TAILSCALE_IP"; then
  status=1
fi

log "检查 SSH ${LAB_SSH}"
if ! ssh -o BatchMode=yes -o ConnectTimeout=12 "$LAB_SSH" 'hostname; whoami; tailscale status --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(\"remote relay\", d.get(\"Self\",{}).get(\"Relay\"))"'; then
  status=1
fi

exit "$status"
