---
title: "云服务器 138 天没重启，一次重启炸出三个隐患：tinyproxy、fstab、公网端口"
description: "长期不重启的机器，配置错误会一直潜伏。一次例行升级重启，暴露了服务启动顺序、fstab 重复条目和被遗忘的公网端口。"
pubDate: 2026-10-28
---

舰队里有一台对外的小云主机，跑着 Caddy（网站）、Uptime Kuma（监控）和 tinyproxy（给家里节点当国内出口）。很久没管它，一查：**138 天没重启，58 个包待升级，9 个新内核排队没生效**。

升级、重启，网站很快恢复了，但 `systemctl --failed` 里多了两个红字。以下是这次炸出来的全部问题。

## 1. tinyproxy 起不来：服务比 Tailscale 先启动

日志：

```
tinyproxy: Could not create listening sockets.
tinyproxy.service: Main process exited, code=exited, status=71/OSERR
```

原因是我让 tinyproxy 只监听 Tailscale 地址（`Listen <tailscale-ip>`），避免代理暴露在公网。但它的 systemd 单元只写了 `After=network.target`，开机时 `tailscale0` 还没拿到地址，绑不上就退出了。

手动 `systemctl restart tinyproxy` 立刻正常，说明就是顺序问题。修法是加一个 drop-in：

```bash
mkdir -p /etc/systemd/system/tinyproxy.service.d
cat > /etc/systemd/system/tinyproxy.service.d/wait-tailscale.conf <<'EOF'
[Unit]
After=tailscaled.service
Wants=tailscaled.service
[Service]
Restart=on-failure
RestartSec=5
EOF
systemctl daemon-reload
```

注意光写 `After=tailscaled.service` 不够：tailscaled 进程起来时，地址不一定已经分配好。真正兜底的是 `Restart=on-failure`，失败就 5 秒后再试，直到地址就绪。

> 凡是 `Listen`/`bind` 到某个具体 IP 的服务（尤其是 VPN 地址），都要考虑这个问题。

## 2. /data 挂不上：fstab 里同一块盘写了两行

```
/dev/vdb /data ext4 defaults 0 2
/dev/vdb /data xfs  defaults 0 0
```

盘实际是 xfs。第一行写错了类型，开机按 ext4 挂就失败了。看起来是当初写错一行、后来补了正确的一行却没删旧的。手动 `mount` 过一次之后一直没重启，所以 138 天都没暴露。

修法：删错误行，改用 UUID，加 `nofail`（这块盘出问题也不会卡住开机）：

```
UUID=<盘的UUID> /data xfs defaults,nofail 0 0
```

改完之后跑一下这个，fstab 写错的地方它都会指出来：

```bash
findmnt --verify
```

另外挂载前先 `ls -A /data` 看一眼：如果没挂载期间有程序往这个目录写过东西，挂上去之后那些文件会被盖住，需要先挪走。

## 3. apt autoremove 顺手卸掉了 netplan

升级时我加了 `autoremove`，输出里赫然出现：

```
Removing python3-netplan ...
Removing netplan-generator ...
Removing libnetplan1 ...
```

netplan-generator 负责开机时把 `/etc/netplan/*.yaml` 翻译成网络配置。如果你的机器靠它管网卡，这一下重启之后就失联了，只能去云厂商控制台救。

我这台运气好：没有 `/etc/netplan` 目录，`networkctl list` 里网卡全是 `unmanaged`，网络不归它管。但这是运气，不是判断。

**教训：autoremove 之前先模拟一遍，看清单再决定。**

```bash
apt-get -s autoremove | grep ^Remv
```

## 4. 顺便查出来的：两个被遗忘的公网端口

- **3001**：Uptime Kuma 后台，从公网直接能打开登录页。
- **8080**：Caddy 上一个早期语音服务的反代入口，后端服务早就下线了，入口还开着。

处理方式：Tailscale 网卡整体放行，公网只留 22/80/443。

```bash
ufw allow in on tailscale0
ufw delete allow 3001/tcp
ufw delete allow 8080/tcp
```

Caddy 改配置前先备份、再 `caddy validate`，校验通过才 reload。

## 体检命令

以后定期跑一下这个，能看出上面大部分问题：

```bash
ssh <host> 'uptime; df -h /; systemctl --failed --no-legend; apt list --upgradable 2>/dev/null | tail -n +2 | wc -l; ls /var/run/reboot-required 2>/dev/null; findmnt --verify 2>&1 | tail -1; ufw status | grep ALLOW'
```

## 小结

这台机器一直"没出问题"，只是因为它一直没重启。长期不重启不等于稳定，配置错误只是在潜伏。**定期重启本身就是一种测试。**
