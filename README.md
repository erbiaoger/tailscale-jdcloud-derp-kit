# Tailscale JDCloud DERP Kit

这个项目记录并自动化部署一套自建 Tailscale DERP 中转：

```text
Mac ---- JDCloud DERP ---- 实验室服务器
```

当前已验证环境：

- DERP VPS: `117.72.114.86`
- DERP region: `900 / jdc / JDCloud`
- 实验室服务器: `100.88.219.12`
- 可用验证结果: `tailscale ping 100.88.219.12` 走 `DERP(jdc)`，RTT 约 `58-60ms`

## 目录说明

- `scripts/`: 一键部署、证书安装、DERPMap 生成和验证脚本。
- `docs/`: 完整部署流程、踩坑记录和排障手册。
- `templates/`: 可复制到 Tailscale Admin Console 的 DERPMap 模板。
- `certs/`: 本地保存从 DERP 服务器拉下来的自签证书，不提交私钥。

## 快速使用

```bash
cd /Users/zhangzhiyu/Desktop/tailscale-jdcloud-derp-kit
cp config.env.example config.env
```

按需修改 `config.env` 后执行：

```bash
# 1. 在云服务器安装/更新 derper
bash scripts/vps_install_derper.sh

# 2. 拉取 DERP 证书并安装到 Mac 当前用户钥匙串
bash scripts/mac_install_derp_cert.sh

# 3. 把证书安装到实验室 Linux 服务器
bash scripts/linux_install_derp_cert.sh

# 4. 生成可粘贴到 Tailscale ACL 的 DERPMap
bash scripts/generate_derpmap.sh --force-only

# 5. 验证
bash scripts/verify_derp.sh
```

详细步骤见 [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)。

重要坑位见 [docs/PITFALLS.md](docs/PITFALLS.md)。

## 当前推荐策略

已验证最稳定的是 `OmitDefaultRegions: true`，即只使用自建 JDCloud DERP。这样可以强制 Mac 和实验室服务器都走 `jdc`。

代价是：如果 JDCloud DERP 挂了，就没有官方 DERP fallback。需要恢复时，在 Tailscale ACL 删除 `OmitDefaultRegions` 或临时删除整个 `derpMap`。

## 安全说明

- 不提交 DERP 私钥。
- 自签证书公钥可以保存和分发。
- `config.env` 不提交，避免以后加入敏感信息时误提交。
