#!/usr/bin/env bash
# 用途:
#   当自建 DERP 出问题时，提示如何临时恢复官方 DERP。
#
# 用例:
#   bash scripts/recover_official_derp.sh
#
# 说明:
#   Tailscale ACL 目前通常需要在网页保存。这个脚本不直接调用 Tailscale API，
#   只打印最小恢复策略，避免误删你的 ACL。

set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_config

cat <<'EOF'
恢复官方 DERP 的最小操作：

1. 打开 Tailscale Admin Console:
   https://login.tailscale.com/admin/acls/file

2. 二选一：

   A. 删除 derpMap 里的这一行，让官方 DERP 恢复为 fallback:
      "OmitDefaultRegions": true,

   B. 临时让自建 DERP 不参与 home 选择，在 region 900 中加入:
      "NoMeasureNoHome": true,

3. 保存 ACL。

4. 在 Mac 上重启 Tailscale:
   /Applications/Tailscale.app/Contents/MacOS/Tailscale down
   /Applications/Tailscale.app/Contents/MacOS/Tailscale up

5. 验证:
   /Applications/Tailscale.app/Contents/MacOS/Tailscale ping --until-direct=false --c 5 100.88.219.12
EOF
