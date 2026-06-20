# Cloudflare Turnstile 绕过分析：为什么 Firefox 可以而 Chrome 不行

> 实测环境：CTO.ai Docker 容器（Ubuntu 22.04），Firefox 152.0.1，2026 年 6 月。

## 问题

在 Docker 中运行浏览器访问 Cloudflare 保护的网站时：

```
Chrome + Xvfb + noVNC
  → CF Turnstile 验证界面正常加载
  → 用户手动点击"我不是机器人"
  → CF 拒绝验证 → 页面卡死
```

Chrome 在 Docker **必须**带 `--no-sandbox` 运行（无用户命名空间）。Cloudflare Turnstile 能检测到这个参数，即使真人点击验证也会被静默拒绝。

## 根本原因

| 因素 | Chrome | Firefox |
|--------|--------|---------|
| Docker 中的沙箱 | 必须 `--no-sandbox` | 自动降级 |
| 可检测标记 | ✅ 有 — `--no-sandbox` 可见 | ❌ 无 |
| Turnstile 行为 | 验证界面正常显示，点击被拒绝 | 验证正常通过 |
| GPU/WebGL | Xvfb 中缺失 | 相同（均使用软件渲染） |

沙箱状态是**唯一有意义的差异**。两个浏览器都缺 GPU、都跑在 Xvfb 里、都有 dbus 警告。但 Chrome 的 `--no-sandbox` 是一个硬信号，Turnstile 会据此封杀。

## 测试结果（CTO.ai 容器，Ubuntu 22.04）

| 浏览器 | 配置 | 验证界面 | 手动点击 | 结果 |
|---------|--------|-----------|-------------|--------|
| Chrome 149 | `--no-sandbox --disable-gpu` | ✅ 正常加载 | ❌ 被拒 | ❌ |
| Firefox 152 | 无特殊参数 | ✅ 正常加载 | ✅ 通过 | ✅ |

## 为什么 Firefox 不需要 `--no-sandbox`

Firefox 在 Docker 中会打印 `CanCreateUserNamespace() clone() failure: EPERM`，但会以降级模式继续运行：

- 内容进程沙箱（无需 CLONE_NEWUSER）
- 基于 `LD_PRELOAD` 的沙箱回退
- 没有 JavaScript 可检测的用户态 `--no-sandbox` 标记

Turnstile 通过 `navigator.webdriver`、进程参数检查和沙箱 API 探测来识别 `--no-sandbox`。Firefox 的回退路径不会触发这些检测器。

## 首次配置

1. 在你的本地浏览器打开 `https://vnc.your-domain.com/vnc.html`
2. 点击 **Connect** → 看到 Firefox 桌面
3. 导航到 CF 保护的网站
4. **手动解决 Turnstile/CAPTCHA 验证**（只需一次）
5. 登录 — cookies 保存在 `~/.mozilla/firefox/` 中

## 局限性

- **不是自动化绕过**：首次登录和 cookie 过期后需要人工介入
- **IP 信誉**：如果 CF 硬拦截你的 IP（不只是验证），任何浏览器都没用。用 `curl -sI https://目标网站 | grep cf-mitigated` 检查：
  - `cf-mitigated: challenge` → Firefox 可用
  - `cf-mitigated: blocked` 或无此头 → IP 级封锁
- **Cookie 过期**：会话 cookie 最终会过期，需要重新打开 VNC 重新登录

## 验证

```bash
# 检查浏览器是否带 --no-sandbox（Firefox 应为 0）
ps aux | grep -c no-sandbox

# 检查 CF 响应类型
curl -sI https://your-target-site.com | grep cf-mitigated

# 确认 Firefox 在正确的显示器上运行
ps aux | grep firefox | head -3
```
