# CTO.ai 平台 — 容器内浏览器

在 CTO.ai Docker 容器中运行 Firefox + Xvfb + noVNC，通过 Cloudflare Tunnel 公开访问。

## 架构

```
┌───────── CTO.ai 容器 ──────────────────────┐
│  Firefox → Xvfb :99 (虚拟显示)              │
│             x11vnc :5900                    │
│             websockify (noVNC) :3000        │
│                  │                          │
│                  └── cloudflared tunnel      │
└──────────────────────────────────────────────┘
                          │
                          ▼
            https://vnc.your-domain.com/vnc.html
```

## 快速安装

```bash
# 一行命令，替换你的目标网址
TARGET_URL="https://your-site.com" bash -c "$(curl -sSL https://raw.githubusercontent.com/zv201413/docker_browser/main/platforms/cto-ai/install.sh)"
```

### 前置条件

- CTO.ai 容器（Ubuntu 22.04）或任意 Docker 环境
- 通过 ttyd 的 root 访问权限（你已有）
- Cloudflare Tunnel 以 `--token` 模式运行（用于公网访问）

### 安装内容

| 包 | 来源 | 大小 |
|---------|--------|------|
| Firefox | Mozilla tar.gz（非 snap） | ~280 MB |
| Xvfb | apt | |
| x11vnc | apt | |
| noVNC | apt 或 GitHub | |
| Supervisor 配置 | 3 个程序 | |

## 环境变量

| 变量 | 默认值 | 说明 |
|----------|---------|-------------|
| `TARGET_URL` | `https://github.com/zv201413/docker_browser` | Firefox 打开的目标网址 |
| `VNC_PORT` | `3000` | noVNC 监听端口 |
| `DISPLAY_NUM` | `99` | Xvfb 显示编号 |

## Supervisor 程序（自动重启）

```bash
# 查看状态
supervisorctl status browser-xvfb browser-firefox browser-novnc

# 只重启 Firefox（VNC 画面不中断）
supervisorctl restart browser-firefox

# 全部重启
supervisorctl restart browser-xvfb browser-firefox browser-novnc
```

## Cloudflare Tunnel 设置

你的 cloudflared 使用 `--token` 模式（无本地 config.yml）：

1. 打开 https://one.dash.cloudflare.com/
2. 找到你的 Tunnel → **Public Hostnames** → **Add**
3. 子域名：`vnc`
4. 服务：`HTTP://localhost:3000`
5. 访问地址：`https://vnc.your-domain.com/vnc.html`

## 首次使用

1. 打开 `https://vnc.your-domain.com/vnc.html`
2. 点击 **Connect**
3. Firefox 会自动打开目标网址
4. **手动解决 Cloudflare 验证**（Firefox 能正常通过，见 cf-bypass.md）
5. 登录目标网站
6. 配置文件保存在 `~/.mozilla/firefox/` 中，重启容器不会丢失

## 故障排查

| 现象 | 原因 | 解决方法 |
|---------|-------|-----|
| VNC 显示黑屏 | Xvfb 锁文件残留 | `rm -f /tmp/.X99-lock` + `supervisorctl restart browser-xvfb` |
| Tunnel 返回 502 | noVNC 未运行 | `supervisorctl restart browser-novnc` |
| Firefox 未加载 | 显示尚未就绪 | `supervisorctl restart browser-firefox`（启动脚本有重试机制）|
| CF 验证失败 | Chrome --no-sandbox | 你正在使用 Firefox，不会遇到此问题（见 cf-bypass.md） |
| Firefox 启动失败 | 缺少依赖库 | `apt install -y libdbus-glib-1-2 libxt6 libxmu6` |

## 文件说明

| 文件 | 用途 |
|------|---------|
| `install.sh` | 一键安装脚本 |
| `start-browser.sh` | 浏览器启动器（环境变量驱动） |
| `supervisor/browser-xvfb.conf` | Xvfb supervisor 配置 |
| `supervisor/browser-firefox.conf` | Firefox supervisor 配置 |
| `supervisor/browser-novnc.conf` | noVNC supervisor 配置 |
| `cf-bypass.md` | Firefox 为何能在 Docker 中绕过 CF Turnstile 的技术分析 |
