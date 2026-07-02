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

## 这次真实故障：xray/nginx 抢占端口

这次京东云上的实际问题不是 Tailscale 客户端，而是 VPS 上另一个服务抢占了 DERP 需要的端口：

- `xray` 占住了 `443`
- `nginx` 占住了 `80`
- `derper` 变成了 `inactive (dead)`

典型现象：

```text
curl https://117.72.114.86/  超时或返回 Cloudflare 证书
curl http://117.72.114.86/generate_204  返回 nginx 404
Tailscale debug derp 900 连接失败
```

排查命令：

```bash
ssh root@117.72.114.86 'systemctl status derper xray nginx --no-pager -l; ss -ltnup | grep -E ":(80|443|3478)"'
```

如果看到类似结果，就说明端口冲突：

```text
udp *:443  users:(("xray",...))
tcp *:80   users:(("nginx",...))
tcp *:443  users:(("xray",...))
```

恢复步骤：

```bash
ssh root@117.72.114.86 'systemctl disable --now xray nginx; systemctl enable --now derper'
```

如果修复后 `xray/nginx` 又抢回 `80/443`，说明这台 VPS 同时装过个人代理服务，或者本机仍有 VS Code Remote SSH / 自动化会话连接到同一台 VPS 并重新部署代理栈。先在本机关闭或杀掉连到 `tail` 的 VS Code Remote 会话：

```bash
ps auxww | grep -E 'config-vscode-remote.* tail bash|ssh -T -D .* tail bash'
pkill -f 'config-vscode-remote.* tail bash' || true
pkill -f 'ssh -T -D .* tail bash' || true
```

然后重新部署 DERP。`scripts/vps_install_derper.sh` 会执行这些保护动作：

- 停止并禁用 `xray`、`nginx`、`subscription-server`。
- 删除它们的 `multi-user.target.wants` 自启链接。
- 隔离 `/root/install_xray_reality.sh`。
- 把 `xray.service`、`nginx.service` 替换成 `RefuseManualStart=yes` 的 blocker unit。
- 对 `derper.service`、`xray.service`、`nginx.service` 设置 immutable，避免被误改或重建。

如需手工确认 blocker 状态：

```bash
ssh root@117.72.114.86 'systemctl is-enabled derper xray nginx subscription-server; lsattr /etc/systemd/system/derper.service /etc/systemd/system/xray.service /etc/systemd/system/nginx.service'
```

然后重新部署或启动 DERP：

```bash
bash scripts/vps_install_derper.sh
```

注意：不要随意换 DERP 自签证书。Mac 和实验室 Linux 都信任当前证书；如证书被换掉，实验室服务器需要重新安装证书。`scripts/vps_install_derper.sh` 默认复用已有证书，只有设置 `FORCE_RENEW_DERP_CERT=1` 才会强制换证书。

恢复后再确认：

```bash
ssh root@117.72.114.86 'systemctl status derper --no-pager -l; ss -ltnup | grep -E ":(80|443|3478)"'
curl -4vk --noproxy '*' https://117.72.114.86/
curl -4v --noproxy '*' http://117.72.114.86/generate_204
```

期望结果：

```text
derper: active (running)
tcp *:443  users:(("derper",...))
tcp *:80   users:(("derper",...))
udp *:3478 users:(("derper",...))
HTTP/1.1 200 OK
HTTP/1.1 204 No Content
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
