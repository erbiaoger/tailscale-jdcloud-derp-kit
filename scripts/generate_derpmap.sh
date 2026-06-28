#!/usr/bin/env bash
# 用途:
#   生成可复制到 Tailscale Admin Console ACL 文件中的 derpMap JSON/HuJSON 片段。
#
# 用例:
#   bash scripts/generate_derpmap.sh --force-only
#   bash scripts/generate_derpmap.sh --with-fallback
#
# 输出:
#   - 打印 derpMap 片段到终端
#
# 参数:
#   --force-only     只使用自建 DERP。已验证最稳定，但没有官方 DERP fallback。
#   --with-fallback  保留官方 DERP。可测速，但 Tailscale 不一定主动选 jdc。

set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_config

MODE="${1:---force-only}"
if [[ "$MODE" != "--force-only" && "$MODE" != "--with-fallback" ]]; then
  die "参数必须是 --force-only 或 --with-fallback"
fi

omit=""
if [[ "$MODE" == "--force-only" ]]; then
  omit=$'  "OmitDefaultRegions": true,\n'
fi

cat <<EOF
"derpMap": {
${omit}  "Regions": {
    "${DERP_REGION_ID}": {
      "RegionID": ${DERP_REGION_ID},
      "RegionCode": "${DERP_REGION_CODE}",
      "RegionName": "${DERP_REGION_NAME}",
      "Latitude": ${DERP_LATITUDE},
      "Longitude": ${DERP_LONGITUDE},
      "Nodes": [
        {
          "Name": "${DERP_REGION_ID}a",
          "RegionID": ${DERP_REGION_ID},
          "HostName": "${DERP_HOST}",
          "IPv4": "${DERP_HOST}",
          "CertName": "${DERP_HOST}",
          "CanPort80": true
        }
      ]
    }
  }
}
EOF
