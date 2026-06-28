# 部署踩坑记录

这里记录本次真实踩过的坑，后续不要重复试错。

## 1. 只放行 TCP 3478 没用，必须放行 UDP 3478

错误现象：

```text
debug derp 900:
Successfully established a DERP connection
Node did not return a IPv4 STUN response

netcheck:
jdc:         (JDCloud)
```

根因：

京东云安全组里只加了 `TCP 3478`，而 STUN 使用的是 `UDP 3478`。

正确做法：

```text
自定义UDP UDP 3478 0.0.0.0/0
```

## 2. 域名 `erbiaoger.site` 在京东云路径上会被拦截

错误现象：

```bash
curl -4vk https://erbiaoger.site/
Recv failure: Connection reset by peer

curl -4v http://erbiaoger.site/generate_204
Server: JDTP
HTTP/1.1 403 Forbidden
```

根因：

域名流量经过京东云边缘/防护层，被 `JDTP` 拦截，没有正常进入 derper。

正确做法：

当前方案不用域名，直接使用 IP：

```json
"HostName": "117.72.114.86",
"IPv4": "117.72.114.86",
"CertName": "117.72.114.86"
```

## 3. `sha256-raw` 在当前 macOS Tailscale 上不可用

错误现象：

```text
x509: certificate is not valid for any names, but wanted to match sha256-raw:...
```

根因：

当前 macOS Tailscale 构建没有按预期把 `sha256-raw:` 当作证书哈希 pin 使用，而是当成证书名校验。

正确做法：

不用 `sha256-raw`，改成：

```json
"CertName": "117.72.114.86"
```

并把自签证书安装到 Mac 和 Linux 的系统信任中。

## 4. derper 自动生成的 10 年证书会被认为不标准

错误现象：

```text
x509: “117.72.114.86” certificate is not standards compliant
```

根因：

derper 自动生成的 IP 自签证书有效期过长，macOS/Tailscale 的证书校验不接受。

正确做法：

手动生成 397 天证书，并包含 IP SAN：

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 397 \
  -keyout /var/lib/derper/certs/117.72.114.86.key \
  -out /var/lib/derper/certs/117.72.114.86.crt \
  -subj "/CN=117.72.114.86" \
  -addext "subjectAltName=IP:117.72.114.86" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth"
```

## 5. 只给 Mac 安装证书不够，实验室服务器也必须信任

错误现象：

```text
Self Relay: jdc
Peer Relay: jdc
tailscale ping 100.88.219.12 timed out
ssh 100.88.219.12 timed out
```

根因：

Mac 能连 JDCloud DERP，但实验室 Linux 服务器不信任 DERP 自签证书。控制面显示在线，不代表数据面真的能转发。

正确做法：

在实验室服务器安装证书：

```bash
sudo install -m 0644 /tmp/jdc-derper-117.72.114.86.crt /usr/local/share/ca-certificates/jdc-derper-117.72.114.86.crt
sudo update-ca-certificates
sudo systemctl restart tailscaled
```

## 6. `NoMeasureNoHome` 可以救急恢复访问

如果启用 jdc 后 SSH 黑洞，在 ACL 的 region 900 内加入：

```json
"NoMeasureNoHome": true
```

保存后重启 Mac Tailscale：

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale down
/Applications/Tailscale.app/Contents/MacOS/Tailscale up
```

这样 Tailscale 不会把 jdc 当 home DERP，连接会回到官方 DERP。

## 7. 保留官方 DERP 时，Tailscale 不一定主动选 jdc

现象：

```text
netcheck:
Nearest DERP: JDCloud
jdc: 31ms
hkg: 115ms

status:
Self Relay: hkg
Peer Relay: hkg
```

解释：

`netcheck` 测到 jdc 最近，不代表当前 home DERP 会立刻迁移。Tailscale 可能继续沿用已有 hkg 连接。

已验证强制方案：

```json
"OmitDefaultRegions": true
```

这样 DERPMap 只剩 jdc，Tailscale 必须使用自建 DERP。

## 8. derper 开发版可能造成调试复杂化

本次 VPS 起初运行：

```text
1.101.0-dev20260627
```

两端客户端是 `1.98.x`。为降低协议/实现差异，最终降到：

```text
derper v1.98.5
```

建议 derper 版本尽量贴近客户端版本。

## 9. Clash Verge TUN 会影响域名/IP 路由

早期错误现象：

```text
route -n get 117.72.114.86
gateway: 198.18.0.1
interface: utun1024
```

这说明 DERP 流量进了 Clash TUN/fake-ip 路径。

正确处理：

Clash 规则前置：

```yaml
- IP-CIDR,117.72.114.86/32,DIRECT,no-resolve
```

TUN 排除：

```yaml
tun:
  route-exclude-address:
    - 117.72.114.86/32
```

最终确认：

```text
route -n get 117.72.114.86
gateway: 192.168.0.1
interface: en0
```

## 10. 不要写 `"IPv6": "none"`

错误现象：

```text
lookup none: no such host
```

正确做法：

在 DERPMap 节点里直接省略 `IPv6` 字段。

## 11. `debug derp` 成功不等于 SSH 一定成功

`debug derp 900` 只能证明当前机器能连接 DERP 节点。最终必须验证：

```bash
tailscale ping --until-direct=false --c 5 100.88.219.12
ssh 100.88.219.12 'hostname; whoami'
```

两者都成功，才算数据面真正可用。
