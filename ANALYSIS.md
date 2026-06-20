# vevc/one-node —— Google IDX 浏览器保活机制深度分析

> 分析对象：https://github.com/vevc/one-node `google-idx/keepalive/`
> 关注重点：**浏览器保活原理** + **能否跳过 CF 盾**（代理节点搭建部分不在范围内）
> 分析日期：2026-06-20

---

## 0. 一句话结论

这套方案的"浏览器保活"= **jlesage/firefox（真实 GUI 浏览器）+ profile 持久化卷 + 真人首次 VNC 登录**，
而 `app.js` 里的 `axios` 只是一个**裸 HTTP 健康探测器**，不是浏览器、不执行 JS。

- **能"浏览器登录"的根因**：登录态（cookies/session）被持久化在挂载卷 `/config` 里，`docker rm -f` 重建容器也不丢。
- **能否跳过 CF 盾**：
  - `axios` 探测：**不能**，遇到 CF JS challenge 只会拿到挑战页（403/503），必然误判。
  - jlesage/firefox：**不是"绕过"，是真浏览器+真人正常通过**，没有任何 stealth / 指纹伪造 / challenge solver。
  - 它在这里能工作，纯粹是因为目标域 `*.cloudworkstations.dev` **走的是 Google 自家鉴权（返回 400），根本没套 CF 盾**。

---

## 1. 整体拓扑：双节点互守

这是一个**对称的双工作空间互相守护**结构（文章里说的"台湾 tw / 美国 us"）：

```
┌─────────────── IDX 节点 A (tw, projectDir=/home/user/tw) ───────────────┐
│  app.js (Node keepalive)                                                 │
│    ├─ axios 每 20s GET  →  对端 B 的 8080 预览域 (cloudworkstations.dev)  │ 健康探测
│    └─ Docker Firefox 容器                                                 │
│         └─ FF_OPEN_URL = idx.google.com/us-...  （打开对端 B 的 IDX 页）   │ 真浏览器保活
└──────────────────────────────────────────────────────────────────────────┘
                         ↕  互为对方的"守护者"
┌─────────────── IDX 节点 B (us) ── 配置对称，守护 A ──────────────────────┐
└──────────────────────────────────────────────────────────────────────────┘
```

两个角色分工：

| 组件 | 协议 | 作用 | 针对对象 |
|------|------|------|----------|
| `axios.get(targetUrl)` | 裸 HTTP | **判活**：对端还在不在 | 对端的 `8080-...cloudworkstations.dev` |
| Docker Firefox (`FF_OPEN_URL`) | 真实浏览器会话 | **保活**：用真人登录态的浏览器持续访问对端 IDX 页，让 Google 认为"有人在用" → 不休眠 | 对端的 `idx.google.com/us-...` |

> 关键认知：**Firefox 才是真正干"保活"活的**（产生真实浏览器流量/会话让对端不休眠）；
> **axios 只是探针**（决定要不要把 Firefox 容器重启一遍）。

---

## 2. 为什么它"可以浏览器登录"（凭证持久化原理）

这是用户最关心的问题之一。答案全在这一行 `docker run` 参数里（app.js:23 / 53）：

```bash
docker run -d --name=idx \
  -e VNC_PASSWORD='vevc.firefox.VNC.pwd' \      # ① noVNC/VNC 访问密码
  -e FF_OPEN_URL=https://idx.google.com/us-...\  # ② 容器启动即自动打开的 URL
  -p 5800:5800 \                                  # ③ noVNC Web 端口（浏览器里操作这个 Firefox）
  -v /home/user/tw/app/firefox/idx:/config \      # ④ 【核心】profile 持久化卷
  jlesage/firefox
```

### 逐项拆解

- **④ `-v .../app/firefox/idx:/config` —— 登录态不丢的根因**
  `jlesage/firefox` 镜像把整个 Firefox **profile 目录放在 `/config`** 下（含 cookies、localStorage、保存的会话）。
  这个目录被挂载到宿主机 `app/firefox/idx`。因此：
  - 首次在 VNC 里手动登录 Google → 登录 cookie 写进宿主机的 `app/firefox/idx`。
  - 之后 `docker rm -f idx && docker run ...` 反复销毁/重建容器，**profile 还在宿主磁盘上** → 新容器挂载同一目录 → **自动保持登录**。
  - 这就是"无需每次重新登录、能自动拉起后继续保活"的全部秘密。

- **③ `-p 5800:5800` + ① `VNC_PASSWORD` —— 首次人工登录入口**
  jlesage/firefox 暴露 `5800` 是 **noVNC（浏览器里的远程桌面）**。
  部署者第一次通过 `http://<ip>:5800` 输入 VNC 密码进去，在里面**像真人一样手动登录 Google 账号 / 过验证码**。
  > 注意：**首次登录是人工的**，脚本不做任何自动化登录。它只负责"登录态保存后的持续保活"。

- **② `FF_OPEN_URL=idx.google.com/us-...` —— 自动保活动作**
  容器一启动，Firefox 自动打开对端的 IDX workspace 页面。
  因为 profile 已带登录态 → 页面自动登录并保持活跃 → 对端 IDX 检测到"有活跃浏览器会话" → 不进入休眠。

### 小结
"可以浏览器登录"= **真浏览器(jlesage/firefox) + 真人首登(VNC) + profile 卷持久化(/config)**。
没有任何账号密码硬编码、没有自动填表、没有 token 注入。

---

## 3. `app.js` 逐行分析（57 行，核心保活逻辑）

```js
const exec = require('child_process').exec   // 用来调用宿主机 docker 命令
const axios = require('axios')               // 唯一第三方依赖：HTTP 客户端（注意——不是浏览器！）
```

### 3.1 配置区（6–11 行）

```js
const targetUrl = 'https://8080-firebase-us-...cloudworkstations.dev'  // ★对端B的预览域:8080，axios探测目标
const ffOpenUrl = 'https://idx.google.com/us-51072006'                 // ★对端B的IDX页，给Firefox打开
const projectDir = '/home/user/tw'           // 本节点(A=tw)工作目录，profile卷挂在它下面
const vncPassword = 'vevc.firefox.VNC.pwd'    // noVNC访问密码（明文，需自行修改）
```

> 注意 `targetUrl`（探活对端的运行端口 8080）和 `ffOpenUrl`（用浏览器打开对端 IDX 控制台）**都指向对端 B**——这就是"互守"。

### 3.2 状态变量（13–15 行）

```js
let lock = false        // 重启互斥锁：正在重建容器时，阻止第二个定时器并发重建
let errorCount = 0      // 连续探测失败计数
const containerName = 'idx'
```

### 3.3 保活/重启函数（17–27 行）

```js
const keepalive = () => {
    if (errorCount >= 3) {              // 连续失败≥3次（≈60秒）才动手，避免抖动误杀
        lock = true                    // 上锁
        errorCount = 0                 // 清零
        exec(`docker rm -f idx && docker run -d --name=idx \
              -e VNC_PASSWORD='...' -e FF_OPEN_URL=... \
              -p 5800:5800 -v .../app/firefox/idx:/config jlesage/firefox`,
             () => { lock = false })   // 重建完成→解锁
    }
}
```

- 逻辑：探测对端连续失败 3 次 → 判定"对端可能掉了 / 自己的 Firefox 会话死了" → **把本地 Firefox 容器整个重建**，让它重新打开对端 IDX 页，试图把对端唤醒/保活。
- 重建用 `docker rm -f` + `docker run`，**挂载同一个 `/config` 卷 → 登录态保留**（呼应第 2 节）。

### 3.4 健康探测定时器（29–45 行，每 20 秒）

```js
setInterval(() => {
    axios.get(targetUrl).catch(error => {       // 注意：只在 catch 里判断！
        if (error.response) {
            const status = error.response.status
            if (status === 400) {               // ★★★ 关键：400 == "存活"
                errorCount = 0                   // 视为成功，清零
            } else {                            // 其它状态码(403/404/5xx...) == 异常
                errorCount++
                keepalive()
            }
        } else {                                // 无响应（超时/拒连/DNS失败）== 异常
            errorCount++
            keepalive()
        }
    })
}, 20000)
```

**这里有两个非常反直觉、但很关键的设计：**

1. **`axios.get` 永远走 `.catch`，没有 `.then`。**
   因为目标 `cloudworkstations.dev:8080` 在**未携带 Google 鉴权**时，必然返回 **HTTP 400**（被 Google 网关拒绝）。
   axios 默认把 4xx/5xx 当作 reject → 进 `.catch`。所以代码把 **拿到 400 当作"对端网关活着"的成功信号**。

2. **判活语义 = "能不能稳定拿到 Google 的 400 拒绝"。**
   - 拿到 400 → 对端 workstation 在线（只是没登录态而已）→ 健康。
   - 拿不到 400（超时 / 连接拒绝 / 其它码）→ 对端可能休眠/挂了 → errorCount++。

> 这正是判断"能否跳过 CF 盾"的命门，详见第 5 节。

### 3.5 容器存在性守护定时器（48–57 行，每 3 秒）

```js
setInterval(() => {
    if (!lock) {                                          // 未在重建中
        exec("docker ps --format '{{.Names}}'", (_, stdout) => {
            if (!stdout.includes('idx')) {               // 容器不在了（崩溃/被杀）
                exec(`docker rm -f idx && docker run -d ... jlesage/firefox`)  // 立刻补一个
            }
        })
    }
}, 3000)
```

- 第二层兜底：**每 3 秒检查 Firefox 容器是否还在**，不在就立即重建。
- `lock` 防止与 3.3 的重建并发冲突。
- 这层保证"浏览器永远在线"，与 3.4 的"对端健康度"是两件事。

### 3.6 app.js 设计评价
- **优点**：极简（57 行，仅 axios 依赖）、双层守护（对端健康 + 本地容器存活）、有抖动保护（≥3 次）和并发锁。
- **缺陷/坑**：
  - `targetUrl`/`ffOpenUrl`/`vncPassword` **全部硬编码**，每个节点要手改源码。
  - 把 **400 当成功**是脆弱契约——一旦 Google 改网关行为（比如改成 401/302/CF 盾），整套判活逻辑全错。
  - 无指数退避：异常时每 20s 触发一次 keepalive，3 次后无脑重建。
  - VNC 密码明文写在源码并暴露 `5800` 端口，安全性差。

---

## 4. `dev.nix` 逐行分析（IDX 自启配置，57 行）

IDX 用 Nix 描述工作空间环境，`.idx/dev.nix` 是它的"开机配置"。本文件真正起作用的只有几行：

```nix
{ pkgs, ... }: {
  channel = "stable-24.05";          # nixpkgs 频道
  packages = [ ];                    # 没装额外包（go/python/node 全是注释掉的示例）
  env = {};

  services.docker.enable = true;     # ★ 启用 Docker —— 整个方案的前提（要 docker run firefox）

  idx = {
    extensions = [
      "google.gemini-cli-vscode-ide-companion"   # 仅装了个 Gemini 插件，无关保活
    ];
    previews = { enable = true; previews = { }; };  # 预览功能开着但没配具体预览

    workspace = {
      onCreate = {                   # 工作空间"首次创建"时
        default.openFiles = [ ".idx/dev.nix" "README.md" ];  # 仅自动打开两个文件，无实质动作
      };
      onStart = {                    # ★★★ 工作空间"每次(重)启动"时执行 —— 自启核心
        xray = "/home/user/tw/app/xray/startup.sh";          # 拉起 xray（代理，本次不分析）
        idx  = "/home/user/tw/app/idx-keepalive/startup.sh"; # ★ 拉起保活程序 app.js
      };
    };
  };
}
```

### 自启链路串起来

```
IDX workspace 启动
  └─(dev.nix: onStart.idx)→ app/idx-keepalive/startup.sh
                              └─ nohup npm run start &   (startup.sh)
                                  └─ node app.js         (package.json: start)
                                      ├─ 每20s axios 探对端
                                      ├─ 每3s 守 Firefox 容器存活
                                      └─ 失败则 docker 重建 Firefox（带 /config 卷）
```

- **关键点**：`services.docker.enable = true` 是整个保活方案能跑的地基（IDX 默认不一定开 Docker）。
- `onStart`（每次重启都跑）而不是 `onCreate`（只首次）—— 保证**工作空间休眠被唤醒后能自动重新拉起保活**，这是"自动保活"自闭环的关键。
- `startup.sh` 用 `nohup ... &` 把 app.js 丢到后台，日志写 `idx-keepalive.log`。

---

## 5. 核心问题：能否"跳过 CF 盾"？

把问题拆成两条独立的访问路径分别回答。

### 路径 A：`axios` 健康探测 —— **不能跳过 CF 盾**

`axios.get` 是**纯 HTTP 请求**：
- 不执行 JavaScript、不渲染页面、不带浏览器指纹（TLS 指纹/UA/JS challenge 全无）。
- 如果 `targetUrl` 前面有 **Cloudflare JS Challenge / 5 秒盾 / Turnstile**，axios 拿到的会是 **CF 的挑战页面（典型 403 / 503 + `cf-mitigated` 头）**，而**不是**真实后端响应。
- 在本代码里，这会被判成 `status !== 400` → `errorCount++` → 触发无意义的容器重建 → **保活逻辑彻底失效（反复误判掉线）**。

> 也就是说：**如果把这套探测原样套到一个 CF 盾保护的站点上，它会直接坏掉。**

### 它在 IDX 上为什么"看起来能用"？—— 因为目标根本没 CF 盾

`*.cloudworkstations.dev`（IDX 的预览域）走的是 **Google 自家的鉴权网关（Cloud Workstations / IAP）**，不是 Cloudflare：
- 未授权访问 → 稳定返回 **HTTP 400**（不是 CF 的 403/503 challenge）。
- 代码正是**利用这个稳定的 400 来判活**。
- 所以这里**根本不存在"跳过 CF 盾"这回事**——它面对的是 Google 鉴权，且只需要"能收到拒绝响应"即可证明存活，**不需要真正通过鉴权**。

### 路径 B：jlesage/firefox 真浏览器 —— **不是"绕过"，是"真人真浏览器正常通过"**

- jlesage/firefox 是**完整的真实 Firefox**，能执行 JS、有完整浏览器环境，由**真人通过 VNC 首次操作**。
- 面对 CF Turnstile / Google reCAPTCHA 这类人机验证：**靠的是真人首登时手动点过**，之后靠 profile 里的 cookie 维持。
- 它**没有**任何自动化过盾能力：
  - 无 `puppeteer-extra-stealth` / 指纹伪造；
  - 无 CF challenge solver / 打码平台对接；
  - 无 cookie 自动刷新逻辑。
- 一旦 cookie 过期、CF/Google 要求重新验证 → **必须人再进 VNC 手动登录一次**，脚本无法自动恢复。

### CF 盾问题总结表

| 路径 | 是否真浏览器 | 执行JS/带指纹 | 能否过 CF JS 盾 | 在本项目中的实际情况 |
|------|:---:|:---:|:---:|------|
| `axios` 探测 | ✗ | ✗ | **不能**（拿到挑战页就误判） | 目标是 Google 400 鉴权，**没 CF 盾**，所以能用 |
| jlesage/firefox | ✓(真Firefox) | ✓ | 真人首登可过，**非自动绕过** | 过的是 Google 登录风控，靠人工 VNC |

**最终判断**：
> 这套方案**本身不具备"跳过/绕过 Cloudflare 盾"的能力**。
> - 它的自动探测（axios）遇真正 CF 盾必然失败；
> - 它能"过验证/保持登录"完全依赖**真浏览器 + 真人首次 VNC 手动登录 + profile 持久化**；
> - 它在 IDX 上跑得通，是因为目标域是 Google 自鉴权（返回 400）而**非 CF 盾保护**，两者不要混为一谈。
>
> 如果你的真实目标是"用它去自动绕过某个 CF Turnstile/5 秒盾的站点"——**做不到**，需要的是浏览器自动化(Playwright)+stealth+打码方案，而这个项目里完全没有。

---

## 6. 安全与可靠性提醒

1. **VNC 密码明文** + 暴露 `5800` 端口 = 任何人扫到都能进你的浏览器，里面是**已登录的 Google 账号**。务必改密码、加防火墙/不公网暴露 5800。
2. **登录态全在 `app/firefox/idx` 目录**：等于把 Google 账号会话明文存盘，泄露=账号被接管。
3. **判活靠"400 魔法值"**，Google 一改网关策略就全线失效，维护性差。
4. **滥用免费额度**：用 IDX 跑 Docker Firefox + 代理保活违反平台 ToS，账号被封是常态；这也是仓库 fork 高（用坏一个换一个）的原因。

---

## 附：本目录文件清单
- `ANALYSIS.md`  本分析文档
- `app.js`       保活主程序（已逐行分析，见 §3）
- `dev.nix`      IDX 自启配置（已逐行分析，见 §4）
- `startup.sh`   `nohup npm run start &` 后台拉起 app.js
- `install.sh`   拉镜像 + 下载脚本 + npm install + 生成 startup.sh
- `README.md`    项目总介绍
- `source-google-idx/`  vevc/one-node 原始文件副本
- `platforms/`   多平台部署方案
  - `google-idx/`   Google IDX 原版方案（source-google-idx 副本）
  - `cto-ai/`       CTO.ai Docker 容器 Firefox + noVNC 方案
    - `cf-bypass.md`  CF Turnstile 绕过分析（Chrome vs Firefox）
