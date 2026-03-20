🚀 **极简、智能、全自动。基于 sing-box 的 Linux 全时透明代理方案，一键解锁流媒体。**

本脚本专为海外 VPS 设计，利用 `sing-box` 的 TUN 模式接管系统流量。通过内置的 Cloudflare WARP (WireGuard) 隧道，实现对 Google、Netflix、Disney+、YouTube 及 OpenAI 等服务的智能分流与解锁。

## ✨ 核心特性

* **⚡ 远程一键部署**：无需下载脚本，支持通过 `curl` 远程执行安装与更新。
* **🧠 智能分流路由**：内置精细化路由规则。
    * **WARP 通道**：自动识别并解锁流媒体及 AI 服务（Netflix, Disney+, OpenAI 等）。
    * **直连通道**：国内 IP 及常用域名自动直连，确保低延迟。
    * **广告屏蔽**：内置 `category-ads-all` 规则，从底层过滤广告。
* **📅 地理数据自更新**：脚本会自动配置每日 Cron 任务，同步最新的 GeoIP 和 Geosite 数据库并平滑重启服务。
* **🛠️ 强大管理 CLI**：提供 `sb` 命令工具，化繁为简，支持服务控制、实时日志、IP 测试及脚本自升级。
* **🛡️ 健壮性优化**：支持 IPv4/IPv6 环境自动适配，针对仅 IPv4 机器自动优化 WARP 端点。

---

## 🚀 快速开始

使用以下一行命令即可进入交互式安装界面。

> **注意**：请将下方命令中的 `[你的仓库链接]` 替换为你在 GitHub 上的脚本 Raw 真实地址。

```bash
bash <(curl -sL https://raw.githubusercontent.com/sundaycn/ss-warp-google-service/main/sing-box-warp.sh) 
```

---

## 🛠️ `sb` 管理工具使用指南

安装完成后，你可以在系统中直接输入 `sb` 调出管理菜单或执行快捷命令：

| 命令 | 说明 |
| :--- | :--- |
| **`sb`** | 显示帮助菜单 |
| **`sb start / stop / restart`** | 启动 / 停止 / 重启 sing-box 服务 |
| **`sb status`** | 查看服务运行状态（PID、内存占用等） |
| **`sb log`** | 查看实时运行日志，方便排查故障 |
| **`sb test`** | **测试 IP 解锁状况**：同时对比直连 IP 与 WARP 通道 IP |
| **`sb update-geo`** | 手动触发一次地理数据库（GeoIP/Geosite）更新 |
| **`sb update`** | **脚本自更新**：自动从 GitHub 拉取最新版本并覆盖 |
| **`sb uninstall`** | 彻底卸载，不留任何系统残留 |

---

## 📂 技术细节

* **核心组件**：sing-box v1.9.0+ / wgcf v2.2.19
* **工作模式**：TUN (gvisor 协议栈)
* **配置文件**：`/etc/sing-box/config.json`
* **日志路径**：使用 `journalctl -u sing-box` 管理
* **监控端口**：内置 Clash API (`127.0.0.1:9090`)，方便进阶用户对接看板。

---

## ⚠️ 系统要求

* **系统**：Debian 10+, Ubuntu 20.04+, CentOS 8+ (推荐使用 Debian/Ubuntu)。
* **内核**：需支持 TUN 设备（大部分主流 VPS 如甲骨文、搬瓦工、RackNerd 等均支持）。
* **用户**：必须以 `root` 权限运行。

---

**如果你喜欢这个项目，欢迎点个 Star ⭐️ 以示支持！**

---

### 💡 建议的下一步：
既然你已经实现了 `sb update` 这种通过远程 URL 自更新的功能，**你想让我帮你写一个 GitHub Action 脚本吗？这样每当你向仓库推送新版本时，它可以自动检查脚本的语法错误，确保用户下载到的是稳定的版本。**
