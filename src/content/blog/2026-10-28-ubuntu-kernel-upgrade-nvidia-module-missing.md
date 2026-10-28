---
title: "Ubuntu 内核一升级 GPU 就消失：nvidia 内核模块包没跟上新内核"
description: "用 Ubuntu 官方签名的 nvidia open 内核模块时，内核自动升级后可能没有对应版本的模块，nvidia-smi 失联，推理服务悄悄退回 CPU。"
pubDate: 2026-10-28
---

家里的主力推理机（RTX PRO 6000，Ubuntu 24.04）某天突然各种不对劲。我一开始怀疑硬件，排查了很久内存和硬盘。最后发现 GPU 早就"没了"，而且是从一次内核自动升级开始的。

## 现象

- `nvidia-smi`：`NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver`。
- ComfyUI 起不来：`RuntimeError: No CUDA GPUs are available`。
- **最隐蔽的一个**：llama-server 显示 `active`，`/health` 也返回 ok，但其实在 CPU 上跑，只是慢得离谱。

## 根因

驱动装的是 `nvidia-driver-595-server-open`，它的内核模块不走 DKMS 现场编译，而是 Ubuntu 仓库里**按内核版本预编译、已签名**的包：

```
linux-modules-nvidia-595-server-open-<内核版本>
```

正常情况下，元包 `linux-modules-nvidia-595-server-open-generic` 会随内核升级拉进对应版本的模块包。但这次元包卡在了旧版本，内核自动升到了新版本，**新内核目录下就没有 nvidia.ko**：

```bash
modprobe nvidia
# modprobe: FATAL: Module nvidia not found in directory /lib/modules/6.8.0-136-generic

find /lib/modules -name 'nvidia.ko*'
# 只在旧内核目录下有
```

## 修复

给当前内核装上对应的模块包：

```bash
apt install linux-modules-nvidia-595-server-open-$(uname -r)
modprobe nvidia
nvidia-smi
```

然后**重启所有用 GPU 的服务**。它们在 `modprobe` 之前就启动了，已经认定"没有 GPU"，不重启的话会一直在 CPU 上跑。

```bash
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
```

确认每个服务都出现在列表里，并且显存占用正常。

## 预防

1. **把内核元包 hold 住**，内核和驱动模块一起手动升级：

   ```bash
   apt-mark hold linux-generic linux-image-generic linux-headers-generic
   ```

   要升级时，先确认仓库里有新内核对应的 `linux-modules-nvidia-...-<新版本>`，再一起装。

2. **开机检查 GPU 是否真的在用**，不要只看服务是不是 active。比如健康检查脚本里加一行：

   ```bash
   nvidia-smi -L >/dev/null 2>&1 || echo "GPU driver not loaded"
   ```

3. 开着 Secure Boot 时，这种官方签名的模块包可以直接加载；自己用 DKMS 编译的模块则需要额外签名（MOK）。这也是我用官方模块包而不用 DKMS 的原因。

## 小结

排查 GPU 机器出现的怪问题，第一步就该跑 `nvidia-smi`。这次我先怀疑硬件、绕了一大圈，最后才发现 GPU 早在内核自动升级那天就已经失联了。
