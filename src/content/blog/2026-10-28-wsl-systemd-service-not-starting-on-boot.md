---
title: "WSL 里的 systemd 服务写了 Restart=always，为什么 Windows 重启后还是不跑"
description: "WSL 发行版不会随 Windows 开机自动启动；用 wsl -e 拉起也会在命令结束后被回收。要让里面的服务常驻，需要一个不退出的会话。"
pubDate: 2026-10-28
---

舰队里有一台 Windows 主机，WSL2 里跑着 Telegram 机器人网关，已经做成了 systemd 服务，`Restart=always`。

结果每次 Windows 重启（停电、自动更新），机器人就失联，一失联就是一两天，直到我手动打开终端。

## 现象

- Windows 侧一切正常，同一台机器上 Windows 的代理服务一直在工作。
- 机器人不回消息，WSL 里的服务日志在重启那一刻之后就再没有新内容。

## 根因：实例根本没启动

```powershell
wsl -l -v
```

```
  NAME            STATE           VERSION
* Ubuntu-24.04    Stopped         2
```

**WSL 发行版不会随 Windows 开机自动启动。** 实例没起来，里面的 systemd 和所有服务自然都不存在，`Restart=always` 根本没有机会生效。

## 第一次修：失败

很自然的想法是开机时执行一条 `wsl` 命令把实例拉起来：

```powershell
wsl -d Ubuntu-24.04 -e /bin/true
```

确实能拉起，服务也启动了。但命令一结束，**没有任何会话挂在实例上，WSL 过一会儿就把整个实例回收了**，服务被优雅停掉。

我是怎么发现的：每调用一次 `wsl -e ...`，机器人就往群里发一条 "Gateway shutting down"。

结论：WSL 内 systemd 有服务在跑，**不能**阻止实例被回收。必须有一个常驻会话。

## 第二次修：挂一个永不退出的会话

在启动文件夹里放一个 VBS，隐藏窗口运行 `sleep infinity`：

```
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\wsl-autostart.vbs
```

```vb
Set sh = CreateObject("WScript.Shell")
sh.Run "wsl.exe -d Ubuntu-24.04 -e sleep infinity", 0, False
```

- 第二个参数 `0`：不显示窗口。
- 第三个参数 `False`：不等待，脚本立刻结束，`sleep` 留在后台。

登录后 `wsl -l -v` 显示 `Running`，服务一直在。

## 还差一步：Windows 自动登录

启动文件夹只在**用户登录之后**才执行。机器无人值守重启时会停在登录界面，等于没启动。

需要开自动登录：`Win+R` 运行 `netplwiz`，取消勾选"要使用本计算机，用户必须输入用户名和密码"。

如果找不到这个勾选框：它被 Windows Hello 的设置藏起来了。先到 设置 → 账户 → 登录选项，关掉"为了提高安全性，仅允许对此设备上的 Microsoft 帐户使用 Windows Hello 登录"，再打开 `netplwiz` 就有了。

> 自动登录意味着拿到机器的人能直接进系统。家里的固定主机可以接受，笔记本不建议。

## 前提检查

WSL 里要先开 systemd（`/etc/wsl.conf`）：

```ini
[boot]
systemd=true
```

## 小结

WSL 实例的生命周期由 Windows 侧管，不由里面的 systemd 管。想让服务常驻，三件事缺一不可：

1. `wsl.conf` 开 systemd；
2. 开机后有东西拉起实例，**并且挂着一个不退出的会话**；
3. Windows 能无人值守地走到"用户已登录"这一步。
