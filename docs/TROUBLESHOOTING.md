# 排障手册

## 快速总检

```bash
bash scripts/verify_derp.sh
```

## 检查 DERPMap 是否生效

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale debug derp-map
```

看 region 900 是否存在：

```json
"900": {
  "RegionID": 900,
  "RegionCode": "jdc"
}
```

如果使用强制方案，应只剩 region 900。

## 检查 Mac 到 DERP VPS 是否直连

```bash
route -n get 117.72.114.86
```

期望：

```text
gateway: 192.168.0.1
interface: en0
```

不希望看到：

```text
gateway: 198.18.0.1
interface: utun...
```

## 检查 DERP TCP/TLS

```bash
curl -4vk --noproxy '*' https://117.72.114.86/
```

期望：

```text
HTTP/1.1 200 OK
```

## 检查 DERP HTTP 80

```bash
curl -4v --noproxy '*' http://117.72.114.86/generate_204
```

期望：

```text
HTTP/1.1 204 No Content
```

如果失败，检查 derper 是否带了：

```text
-http-port 80
```

以及云安全组是否放行 `TCP 80`。

## 检查 STUN

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale debug derp 900
```

期望：

```text
Successfully established a DERP connection
Node returned IPv4 STUN response
```

如果没有 STUN response，检查云安全组 `UDP 3478`。

## 检查云服务器 derper

```bash
ssh root@117.72.114.86 'systemctl status derper --no-pager -l; ss -ltnup | grep -E ":(80|443|3478)"'
```

期望：

```text
tcp *:443
tcp *:80
udp *:3478
```

## 检查实验室服务器是否信任证书

```bash
ssh 100.88.219.12 'openssl verify -CApath /etc/ssl/certs /tmp/jdc-derper-117.72.114.86.crt'
```

期望：

```text
/tmp/jdc-derper-117.72.114.86.crt: OK
```

如果不是 OK：

```bash
bash scripts/linux_install_derp_cert.sh
```

## 检查最终链路

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale ping --until-direct=false --c 5 100.88.219.12
ssh 100.88.219.12 'hostname; whoami'
```

成功示例：

```text
pong from dell-poweredge-r7625-1 via DERP(jdc) in 58ms
dell-PowerEdge-R7625
zhangzhiyu
```

## 黑洞恢复流程

如果出现：

```text
Self Relay: jdc
Peer Relay: jdc
tailscale ping timed out
ssh timed out
```

先恢复官方 DERP：

1. Tailscale ACL 中删除 `"OmitDefaultRegions": true`
2. 或给 region 900 加 `"NoMeasureNoHome": true`
3. 保存 ACL
4. Mac 执行：

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale down
/Applications/Tailscale.app/Contents/MacOS/Tailscale up
```

恢复后再查 Linux 证书、derper 版本和 UDP 3478。
