# docker_browser — 容器内浏览器

在任何 Docker 容器中运行真正的 Firefox 浏览器，通过 VNC 远程访问，并且能绕过 Cloudflare Turnstile 人机验证。

## 为什么用 Firefox？

Chrome 在 Docker 中必须加 `--no-sandbox` 参数，Cloudflare Turnstile **能检测到这个标记**，即使真人点击验证也会被拒绝。

Firefox 的沙箱在容器中会自动降级，不会产生任何可被检测的信号——CF Turnstile 正常工作。详见 [cf-bypass.md](platforms/cto-ai/cf-bypass.md)。

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

## 功能

- 安装 Firefox 152+（原生 tar.gz，绕过 Ubuntu 22.04 snap 虚包）
- 配置 Xvfb 虚拟显示 + x11vnc + noVNC
- 注册 supervisor 自动重启（3 个独立程序）
- 通过 VNC 一次性手动通过 CF Turnstile 验证
- Firefox 配置文件持久化，重启不丢失

## 托管服务管理

```bash
supervisorctl status browser-xvfb browser-firefox browser-novnc
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
│       ├── start-browser.sh  # 浏览器启动器（环境变量驱动）
│       ├── supervisor/       # Supervisor 配置（3 个程序）
│       ├── cf-bypass.md      # CF Turnstile 绕过分析
│       └── README.md         # 详细部署文档
└── ANALYSIS.md               # vevc/one-node 保活机制分析
```

## 鸣谢

本项目基于 [vevc/one-node](https://github.com/vevc/one-node) 的保活机制及分析启发，该项目的思路推动了容器内浏览器行为与 Cloudflare Turnstile 绕过方案的探索。

## License

MIT
