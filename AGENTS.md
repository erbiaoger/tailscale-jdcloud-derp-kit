# AGENTS.md

本仓库用于部署和维护自建 Tailscale DERP。

## 维护要求

- 重要改动必须提交 git commit，提交信息写清楚改了什么和为什么。
- 脚本必须可以重复执行，避免因为已存在文件或服务而失败。
- Shell 脚本必须有：
  - 文件开头用途说明
  - 用例说明
  - 参数说明
  - 终端日志输出
- 不提交私钥、密码、API token。
- `config.env` 不提交。
- DERP 私钥和证书私钥只能留在服务器，不放进仓库。

## 验收标准

改动后至少运行：

```bash
make check
```

如果改动涉及实际部署，还要运行：

```bash
make verify
```

## 已验证核心事实

- 当前稳定方案使用 `OmitDefaultRegions: true`，强制只使用 JDCloud DERP。
- 当前 DERPMap 使用 `CertName: "117.72.114.86"`，不要使用 `sha256-raw`。
- Mac 和实验室 Linux 服务器都必须信任 DERP 自签证书。
- 京东云必须放行 `UDP 3478`，不是 `TCP 3478`。
