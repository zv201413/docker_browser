# docker_browser — 容器内浏览器

在任何 Docker 容器中运行真正的 Firefox 浏览器，通过 VNC 远程访问，并且能绕过 Cloudflare Turnstile 人机验证。


## 一键安装 (CTO.ai / Docker)

```bash
TARGET_URL="https://github.com/zv201413/docker_browser" bash -c "$(curl -sSL https://raw.githubusercontent.com/zv201413/docker_browser/main/platforms/cto-ai/install.sh)"
```

或手动安装：

```bash
git clone https://github.com/zv201413/docker_browser.git
cd docker_browser/platforms/cto-ai
TARGET_URL="https://your-site.com" bash install.sh
```

## 一键卸载

```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/zv201413/docker_browser/main/platforms/cto-ai/uninstall.sh)"
```

## 功能

- 安装 Firefox 152+（原生 tar.gz，绕过 Ubuntu 22.04 snap 虚包）
- 配置 Xvfb 虚拟显示 + x11vnc + noVNC
- 支持 `VNC_PASSWORD` 环境变量设置密码
- 注册 supervisor 自动重启（统一为 browser-launcher 总控）
- 内置健康检查脚本（进程/VNC 端口/Cookie/页面可达性）
- 可选 webhook 告警（支持 Telegram 等）
- 通过 VNC 一次性手动通过 CF Turnstile 验证
- Firefox 配置文件持久化，重启不丢失

## 托管服务管理

```bash
supervisorctl status browser-launcher browser-health
```

## Cloudflare Tunnel 配置

如果使用 cloudflared `--token` 模式：

1. 打开 https://one.dash.cloudflare.com/
2. 找到你的 Tunnel → **Public Hostnames** → **Add**
3. 子域名：`vnc` → 服务：`HTTP://localhost:3000`

## 项目结构

```
docker_browser/
├── platforms/
│   └── cto-ai/              # CTO.ai/Docker 部署
│       ├── install.sh        # 一键安装脚本
│       ├── uninstall.sh      # 一键卸载脚本
│       ├── start-browser.sh  # 浏览器启动器（环境变量驱动）
│       ├── health-check.sh   # 健康检查（4 项探活 + webhook 告警）
│       ├── supervisor/       # Supervisor 配置 (原遗留，现由 install.sh 动态生成)
│       ├── cf-bypass.md      # CF Turnstile 绕过分析
│       └── README.md         # 详细部署文档
└── ANALYSIS.md               # vevc/one-node 保活机制分析
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `TARGET_URL` | `https://github.com/zv201413/docker_browser` | 浏览器打开的网址 |
| `VNC_PASSWORD` | （自动生成） | noVNC 连接密码 |
| `VNC_PORT` | `3000` | noVNC Web 端口 |
| `ALERT_WEBHOOK` | （无） | 健康检查告警 webhook |
| `DISPLAY_NUM` | `99` | Xvfb 虚拟显示编号 |

## 为什么用 Firefox？

Chrome 在 Docker 中必须加 `--no-sandbox` 参数，Cloudflare Turnstile **能检测到这个标记**，即使真人点击验证也会被拒绝。

Firefox 的沙箱在容器中会自动降级，不会产生任何可被检测的信号——CF Turnstile 正常工作。详见 [cf-bypass.md](platforms/cto-ai/cf-bypass.md)。

## 鸣谢

本项目基于 [vevc/one-node](https://github.com/vevc/one-node) 的保活机制及分析启发，该项目的思路推动了容器内浏览器行为与 Cloudflare Turnstile 绕过方案的探索。

## License

MIT
