# Docker Compose Manager (Docker Compose管理脚本)

![License](https://img.shields.io/github/license/SHINYUZ/Docker-Compose-Manager?color=blue)
![Language](https://img.shields.io/badge/language-Bash-green)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)
![Version](https://img.shields.io/badge/version-v1.7.4-orange)

🚀 **一款轻量级、功能强大的 Docker Compose 项目管理 Shell 脚本。**

专为 VPS 运维设计，集成了项目管理、容器监控、一键更新、以及**自动备份**功能。无需安装复杂的面板，一个脚本即可高效管理你的 Docker 容器。

---

## ✨ 功能特性

* **🛠 开箱即用**：自动检测环境，自动安装 Docker & Docker Compose 插件，自动修复缺失的依赖（Nano, Wget 等）。
* **🧠 智能导入**：首次运行会自动扫描当前系统运行中的 Docker Compose 项目并导入管理列表。
* **⚡ 快捷指令**：内置 `dk` 快捷别名，在任何目录下输入 `dk` 即可唤醒管理面板。
* **🛡 数据备份**：
    * 支持手动一键备份项目文件（打包 tar.gz）。
    * **定时自动备份**：支持自定义每日备份时间，通过 Crontab 自动运行，并在后台静默完成打包。
* **🕹 全能管理**：支持启动、停止、重启、更新镜像（`pull` + `up -d`）、查看日志、编辑配置等常用操作。

---

## 🚀 安装 (Installation)

复制和执行以下命令：

```bash
wget -N --no-check-certificate "https://raw.githubusercontent.com/SHINYUZ/Docker-Compose-Manager/main/docker.sh" && chmod +x docker.sh && ./docker.sh
```
如果下载失败，请检查 VPS 的网络连接或 DNS 设置

使用镜像加速源下载：

```bash
wget -N --no-check-certificate https://ghproxy.net/https://raw.githubusercontent.com/SHINYUZ/Docker-Compose-Manager/main/docker.sh && chmod +x docker.sh && sed -i 's|https://github.com|https://ghproxy.net/https://github.com|g' docker.sh && sed -i 's|https://api.github.com|https://ghproxy.net/https://api.github.com|g' docker.sh && ./docker.sh
```
如果下载失败，请使用其他加速源下载

---

## ⌨️ 快捷指令

安装完成后，以后只需在终端输入以下命令即可打开菜单：

```bash
dk
```

---

## 📖 菜单功能说明

1.  **添加项目**：手动通过路径添加现有的 `docker-compose.yml` 项目。
2.  **管理项目**：
    * 查看项目运行状态 (Running/Stopped)。
    * **更新容器**：自动执行 `docker compose pull` 和 `docker compose up -d`，实现无缝更新。
    * **编辑配置**：直接调用 nano 编辑器修改 yaml 文件。
    * **查看日志**：实时查看容器最后 100 行日志。
3.  **备份项目**：
    * 设置每日定时自动备份（自定义小时/分钟）。
    * 手动触发备份，文件默认保存在 `/opt/docker-manager/backup`。
4.  **管理 Docker 服务**：一键启动/停止/重启 Docker 守护进程，或完全卸载 Docker。

---

## 📂 目录结构

* **配置文件**：`/etc/dcm_projects.txt` (存储项目列表)
* **备份目录**：`/opt/docker-manager/backup` (默认，自动创建)
* **自动备份脚本**：`/usr/local/backup/docker-auto-backup.sh`
* **Crontab 任务**：`/etc/cron.d/docker-auto-backup`

---

## ⚠️ 注意事项

* **Root 权限**：本脚本必须以 root 用户运行。
* **删除项目**：在管理菜单中选择“删除容器”时，脚本会同时**删除硬盘上的项目文件夹**，请务必提前备份重要数据！

---

## ⚠️ 免责声明

1. 本脚本仅供学习交流使用，请勿用于非法用途。
2. 使用本脚本造成的任何损失（包括但不限于数据丢失、服务器被封锁等），作者不承担任何责任。
3. 请遵守当地法律法规。

---

## 📄 开源协议

本项目遵循 [GPL-3.0 License](LICENSE) 协议开源。

Copyright (c) 2026 Shinyuz

---

**如果这个脚本对你有帮助，请给一个 ⭐ Star！**
