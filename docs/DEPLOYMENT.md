# Tailscale 自建 JDCloud DERP 完整部署流程

本文档记录当前已验证成功的方案。目标是保留 Tailscale 直连能力，同时在无法直连时强制使用京东云 DERP 中转，避开 iPhone 热点或运营商网络导致的官方 DERP 慢路径。

## 0. 当前已验证结果

```text
DERP VPS: 117.72.114.86
RegionID: 900
RegionCode: jdc
RegionName: JDCloud
实验室服务器: 100.88.219.12

最终验证:
Self Relay: jdc
Peer dell-PowerEdge-R7625 Relay jdc
tailscale ping 100.88.219.12 via DERP(jdc) in 58-60ms
ssh 100.88.219.12 可登录
```

## 1. 部署架构

实际选路逻辑：

```text
能直连时：
Mac ---- Tailscale direct ---- 实验室服务器

不能直连时：
Mac ---- JDCloud DERP ---- 实验室服务器
```

`OmitDefaultRegions: true` 只影响 DERP 中继候选列表，不会禁止 Tailscale 的 direct 直连。它的含义是：如果 Tailscale 需要使用 DERP，则只能使用我们自建的 `jdc`，不再使用官方 `hkg/tok/sfo/...`。

中继路径：

```text
Mac
  |
  | Tailscale DERP TCP 443
  v
JDCloud VPS 117.72.114.86
  |
  | Tailscale DERP TCP 443
  v
实验室服务器 100.88.219.12
```

同时使用 `UDP 3478` 做 STUN 探测。STUN 不转发 SSH 数据，但会影响 Tailscale 是否认为该 DERP 节点健康和可选。

## 2. 云服务器准备

云服务器要求：

- Ubuntu 22.04/24.04 均可。
- 有公网 IPv4。
- SSH 可登录。
- 安全组/防火墙放行：
  - `TCP 443`
  - `TCP 80`
  - `UDP 3478`

本次京东云控制台最终规则：

```text
自定义UDP UDP 3478 0.0.0.0/0
自定义TCP TCP 443  0.0.0.0/0
http（TCP） TCP 80  0.0.0.0/0
ssh        TCP 22  0.0.0.0/0
```

注意：`TCP 3478` 没用，必须是 `UDP 3478`。

## 3. 配置项目参数

```bash
cd /Users/zhangzhiyu/Desktop/tailscale-jdcloud-derp-kit
cp config.env.example config.env
```

当前可用配置：

```bash
DERP_HOST=117.72.114.86
DERP_REGION_ID=900
DERP_REGION_CODE=jdc
DERP_REGION_NAME=JDCloud
VPS_SSH=root@117.72.114.86
LAB_TAILSCALE_IP=100.88.219.12
LAB_SSH=100.88.219.12
DERPER_VERSION=v1.98.5
```

## 4. 安装 derper 到云服务器

```bash
bash scripts/vps_install_derper.sh
```

脚本会做这些事：

- 安装或更新 `/usr/local/bin/derper`
- 备份旧 derper
- 生成 IP SAN 自签证书
- 写入 systemd 服务
- 启用并重启 derper
- 拉取公开证书到本地 `certs/`

当前 systemd 服务核心参数：

```ini
ExecStart=/usr/local/bin/derper -a :443 -hostname 117.72.114.86 -certmode manual -certdir /var/lib/derper/certs -http-port 80 -stun-port 3478
```

关键点：

- `-hostname` 使用 IP：`117.72.114.86`
- `-certmode manual`
- `-http-port 80` 必须打开，用于 Tailscale captive portal check
- `-stun-port 3478`

## 5. 安装证书到 Mac

```bash
bash scripts/mac_install_derp_cert.sh
```

脚本会把 DERP 自签证书安装到当前用户登录钥匙串。

本次排障确认：Mac 不信任证书时，会出现：

```text
x509: certificate signed by unknown authority
```

## 6. 安装证书到实验室服务器

```bash
bash scripts/linux_install_derp_cert.sh
```

脚本会上传证书到实验室服务器，然后执行：

```bash
sudo install -m 0644 /tmp/jdc-derper-117.72.114.86.crt /usr/local/share/ca-certificates/jdc-derper-117.72.114.86.crt
sudo update-ca-certificates
sudo systemctl restart tailscaled
```

本次排障确认：只给 Mac 安装证书是不够的。实验室服务器也必须信任同一张证书，否则它可能显示 `Relay: jdc`，但实际 `tailscale ping` 和 `ssh` 会黑洞超时。

## 7. Tailscale ACL DERPMap

生成已验证的强制方案：

```bash
bash scripts/generate_derpmap.sh --force-only
```

把输出复制到 Tailscale Admin Console 的 ACL 文件中：

```text
https://login.tailscale.com/admin/acls/file
```

当前已验证可用片段：

```json
"derpMap": {
  "OmitDefaultRegions": true,
  "Regions": {
    "900": {
      "RegionID": 900,
      "RegionCode": "jdc",
      "RegionName": "JDCloud",
      "Latitude": 39.9042,
      "Longitude": 116.4074,
      "Nodes": [
        {
          "Name": "900a",
          "RegionID": 900,
          "HostName": "117.72.114.86",
          "IPv4": "117.72.114.86",
          "CertName": "117.72.114.86",
          "CanPort80": true
        }
      ]
    }
  }
}
```

关键点：

- 当前已验证方案使用 `CertName: "117.72.114.86"`
- 不使用 `sha256-raw`
- 不写 `"IPv6": "none"`
- 强制只用自建 DERP 时使用 `OmitDefaultRegions: true`

## 8. 验证

```bash
bash scripts/verify_derp.sh
```

关键成功信号：

```text
Tailscale debug derp 900:
Successfully established a DERP connection
Node returned IPv4 STUN response

Tailscale netcheck:
Nearest DERP: JDCloud
jdc: 30ms 左右

tailscale ping:
via DERP(jdc)

ssh:
ssh 100.88.219.12 可登录
```

## 9. 恢复官方 DERP

如果 JDCloud DERP 出问题：

```bash
bash scripts/recover_official_derp.sh
```

最小恢复方法是在 ACL 里删除：

```json
"OmitDefaultRegions": true,
```

然后重启 Mac Tailscale：

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale down
/Applications/Tailscale.app/Contents/MacOS/Tailscale up
```

如果只想临时禁用自建 DERP 作为 home，给 region 900 加：

```json
"NoMeasureNoHome": true
```

这样可以保留节点但不让 Tailscale 主动选它。
