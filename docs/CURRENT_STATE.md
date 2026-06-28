# 当前机器状态快照

记录时间：2026-06-29 02:20 左右。

## JDCloud VPS

```text
IP: 117.72.114.86
OS: Ubuntu 24.04.2 LTS
derper: v1.98.5
systemd: derper.service enabled
```

服务参数：

```ini
ExecStart=/usr/local/bin/derper -a :443 -hostname 117.72.114.86 -certmode manual -certdir /var/lib/derper/certs -http-port 80 -stun-port 3478
```

监听：

```text
TCP 443
TCP 80
UDP 3478
```

证书：

```text
subject=CN = 117.72.114.86
SAN=IP Address:117.72.114.86
notBefore=Jun 28 17:36:21 2026 GMT
notAfter=Jul 30 17:36:21 2027 GMT
SHA256=D3:83:A8:82:49:B6:FE:74:13:AC:D0:B7:7A:44:45:86:EB:29:68:C9:8B:67:15:B2:F9:28:5C:98:E0:26:91:4A
```

## Tailscale ACL

当前可用强制方案：

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

## Mac

Mac 当前用户登录钥匙串已信任 DERP 自签证书。

Clash/TUN 关键要求：

```text
117.72.114.86 必须直连，不要进 198.18.0.1 / utun fake-ip 路径。
```

## 实验室服务器

```text
Tailscale IP: 100.88.219.12
HostName: dell-PowerEdge-R7625
OS: Ubuntu 22.04.5 LTS
```

已安装 DERP 自签证书：

```text
/usr/local/share/ca-certificates/jdc-derper-117.72.114.86.crt
```

## 最终验证

成功输出：

```text
Self Relay: jdc
Peer dell-PowerEdge-R7625 Relay jdc
pong via DERP(jdc) in 58-60ms
ssh 100.88.219.12 成功
```
