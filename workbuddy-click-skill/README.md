# WorkBuddy 签到 Skill · `workbuddy-click-skill`

> 一条命令，自动打开 WorkBuddy macOS 桌面端的「Buddy 加油站」抽屉并点击「立即领取」。
> 已内置**防假成功**机制：拿不到「已领取」的确凿证据就绝不谎报成功。

**平台**：macOS（依赖 CoreGraphics / AppleScript，仅桌面端可用） · **语言**：Bash + C

---

## ✨ 它解决什么问题

WorkBuddy 的签到入口（Buddy 加油站 → 立即领取）是 Electron 内嵌 WebView，
按钮**不向系统辅助功能树暴露**，所以没法用 `click "立即领取"` 这种按名点击，
只能靠坐标 + 图像判定。最容易踩的坑是**「假成功」**：脚本报告签到完成，
其实抽屉根本没打开 / 按钮没点中。

本 Skill 用三道判定 + 严格退出码把这件事做扎实：

1. **相对窗口偏移坐标**（非绝对坐标）—— 窗口移动、多屏都不怕点错位置。
2. **图像差分 + 饱和度 + OCR 三板斧**判定抽屉是否真打开、按钮是否真已领取。
3. **严格退出码**：只有确认 `claimed`（今日已领）或「弹框开过又关」才退 0，否则退 1。

---

## 📦 目录结构

```
workbuddy-click-skill/
├── SKILL.md                  # Skill 主入口（能力说明 / 触发词 / 原理 / 校准 / 定时接入）
├── README.md                 # 本文件：部署与使用指南
├── build.sh                  # 编译 wbclick（新机器必跑一次）
├── scripts/
│   ├── workbuddy-checkin.sh  # 主控脚本（严格防假成功模式）
│   ├── wbclick.c             # 零依赖 CoreGraphics 坐标点击工具源码
│   ├── wbclick               # 已编译二进制（本机可直接用，新机请重编译）
│   └── .wbcheckin.offsets    # 校准偏移（含本机已验证值，新机请重新校准）
└── references/
    └── troubleshooting.md    # 坐标系 / 相对偏移 / 判定三板斧 / 故障复盘 详细笔记
```

> 所有脚本均使用相对路径（`SCRIPT_DIR` 推导），整个目录可**整体拷贝到任意位置**运行，
> 不依赖任何写死的绝对路径。

---

## 🚀 快速开始（新机器 5 步）

### 1. 安装前置依赖（一次性）

```bash
# 编译工具（提供 clang）
xcode-select --install

# 图像差分 / 饱和度判定 + OCR
brew install imagemagick tesseract tesseract-lang
```

### 2. 系统权限（缺一不可）

| 设置路径 | 需勾选的对象 |
|---|---|
| 系统设置 → 隐私与安全性 → **辅助功能** | 运行脚本的终端 / WorkBuddy |
| 系统设置 → 隐私与安全性 → **屏幕录制** | 运行脚本的终端 / WorkBuddy |

> 经验：在 iTerm/Terminal 手动跑若点击无效，多半是终端缺「辅助功能」权限。
> **最稳的办法是用 WorkBuddy 自身定时任务运行**（继承完整权限）。

### 3. 编译点击工具

```bash
cd workbuddy-click-skill
bash build.sh          # 内部即 clang 编译 scripts/wbclick.c
```

### 4. 校准坐标（关键，换机器必做）

脚本存的是**「相对窗口原点的偏移」**，不是绝对坐标。本机已验证偏移写在
`.wbcheckin.offsets`（`ENTRY_REL=(32,766)` / `BTN_REL=(95,368)`，基于 1200×800 窗口）。
UI 改版 / 换机器 / 窗口位移后**必须重新校准**：

```bash
cd workbuddy-click-skill/scripts

# 诊断当前窗口 / 坐标 / 状态
bash workbuddy-checkin.sh debug

# 校准①：鼠标悬停在 WorkBuddy 左下角「用户头像」上，再运行（免回车）
bash workbuddy-checkin.sh where-entry

# 校准②：手动点开签到抽屉，鼠标悬停在「立即领取」按钮上，再运行（免回车）
bash workbuddy-checkin.sh where
```

> 嫌麻烦也可以发一张「抽屉打开、能看到按钮」的截图，由我算偏移写进文件。

### 5. 执行

```bash
cd workbuddy-click-skill/scripts

# 执行一次签到（严格模式）
bash workbuddy-checkin.sh once

# 只诊断不点击
bash workbuddy-checkin.sh debug
```

运行日志落在 `scripts/checkin.log`，过程截图落在 `scripts/snapshot/`。

---

## ⚙️ 接入每日定时任务

推荐用 **WorkBuddy 自动化**建每日任务，因为它继承完整的辅助功能 / 屏幕录制权限，
点击最稳：

- **命令**（用 `caffeinate -i` 防止期间 Mac 休眠）：
  ```bash
  caffeinate -i bash <skill目录>/scripts/workbuddy-checkin.sh
  ```
- **频率**：每天 `09:05`（GMT+8）
- **报告规则**：
  - 日志含「签到完成(今日已领)」→ 报告「今日已签到，已跳过」
  - 日志含「签到完成(已领取)」→ 报告「今日签到成功」
  - 日志含「签到失败」或「WARN」→ 报告「签到失败」，附 `snapshot/` 最近截图与日志 WARN/ERROR 行

---

## ❓ 常见问题速查

| 现象 | 原因 | 处理 |
|---|---|---|
| 弹框未打开，状态恒 `none` | 头像偏移错 / 缺点击权限 | `where-entry` 重校准；或改用定时任务运行 |
| `wbclick` 打印帮助而非点击 | 负坐标被误当选项（旧 bug，已修） | 用本包 `wbclick.c` 重编译 |
| 窗口矩形为空 | 用了 `open -a` 激活 | 用 `osascript … activate`（脚本已内置） |
| 点击落点错在对话区 | 用了绝对坐标残留 | 确认 `.wbcheckin.offsets` 是相对偏移，重校准 |
| 今天已领却仍点 | 正常，会识别 `claimed` 跳过 | 无需处理 |

更多细节见 [references/troubleshooting.md](references/troubleshooting.md) 与 [SKILL.md](SKILL.md)。

---

## 📄 说明

- 仅适用于 **macOS 桌面端 WorkBuddy**；坐标 / 判定参数基于特定窗口尺寸与 UI 版本，
  跨机型请走上面的「校准」流程。
- `.wbcheckin.offsets` 里是本机已验证值，**只是样例**，不代表你的机器可直接用。
