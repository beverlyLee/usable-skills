# Trae Work CN 签到 Skill · `trae-work-cn-checkin`

> 一条命令，自动打开 macOS 桌面端 **Trae Work CN**（`cn.trae.solo.app`，窗口标题 `TRAE Work CN`）
> 左下角的用户菜单并点击「签到」。内置**防假成功**机制：拿不到「今日已签 / 签到成功」的确凿证据，
> 就绝不谎报成功。

**平台**：macOS（依赖 CoreGraphics / AppleScript，仅桌面端可用） · **语言**：Bash + C

---

## ✨ 它解决什么问题

Trae Work CN 的「签到」入口（左下角用户头像 → 弹出用户菜单 →「签到」胶囊按钮）是 Electron 内嵌
界面，**按钮不向系统辅助功能树暴露**，没法用「按名点击」，只能靠坐标 + 图像判定。最容易踩的坑是
**「假成功」**：脚本报告签到完成，其实菜单根本没打开 / 按钮没点中。

本 Skill 在反复踩坑后沉淀了三道关键设计：

1. **归一化比例坐标（NX/NY）**（非绝对、也非固定相对偏移）—— 坐标以「窗口宽/高比例」存储，
   运行时换算成像素相对偏移 `REL = NX*WIN_W / NY*WIN_H`，**自适应窗口缩放与 Retina/DPI**，
   窗口移动、换屏、改尺寸都不跑偏。
2. **按 Window Server 窗口 ID 截图** `screencapture -l <windowID>` —— 直接从窗口本体抓图，
   **不依赖 Trae 是否置于最前**，因此不会拍到后面的桌面壁纸。
   （踩过的坑：旧方案 `screencapture -R 区域` 抓的是「屏幕上该坐标实际显示的内容」，Trae 没置前时就
   拍到桌面，导致状态判定全部失效、误判「菜单未打开」。）
3. **严格成功判定** —— 仅在菜单确实打开且按钮被点击、或识别出「今日已签」时才判定成功；否则返回非 0。

---

## 📦 目录结构

```
trae-work-cn-checkin/
├── SKILL.md                  # Skill 主入口（能力说明 / 触发词 / 原理 / 校准 / 定时接入）
├── README.md                 # 本文件：部署与使用指南
├── .gitignore                # 忽略运行时产物（snapshot/、checkin.log）
├── scripts/
│   ├── trae-work-cn-checkin.sh  # 主控脚本（窗口发现/激活/截图/点击/OCR 状态判定/校准）
│   ├── wbclick.c             # 零依赖 CoreGraphics 点击/读光标工具源码
│   ├── wbclick               # 已编译二进制（新机请重编译）
│   ├── winfo.c               # 零依赖 CoreGraphics 窗口枚举工具源码
│   ├── winfo                 # 已编译二进制（新机请重编译）
│   ├── build.sh              # 编译 wbclick + winfo（新机器必跑一次）
│   └── .traecheckin.offsets  # 校准坐标（NX/NY 归一化比例，含本机已验证值，新机请重新校准）
```

> 所有脚本均使用相对路径（`SCRIPT_DIR` 推导），整个目录可**整体拷贝到任意位置**运行，
> 不依赖任何写死的绝对路径。

---

## 🚀 快速开始（新机器 5 步）

### 1. 安装前置依赖（一次性）

```bash
# 编译工具（提供 clang）
xcode-select --install

# 状态判定用的 OCR + 图像处理（推荐）
brew install tesseract tesseract-lang imagemagick
```

> OCR 非强制：缺省也能靠图像差分兜底，但装了中文包（`chi_sim`）判定更准。

### 2. 系统权限（缺一不可）

| 设置路径 | 需勾选的对象 |
|---|---|
| 系统设置 → 隐私与安全性 → **辅助功能** | 运行脚本的终端 / WorkBuddy |
| 系统设置 → 隐私与安全性 → **屏幕录制** | 运行脚本的终端 / WorkBuddy |

> 经验：在 iTerm/Terminal 手动跑若点击无效，多半是终端缺「辅助功能」权限。
> **最稳的办法是用 WorkBuddy 自身定时任务运行**（继承完整权限）。

### 3. 编译原生工具

```bash
cd trae-work-cn-checkin
bash build.sh          # 内部即 clang 编译 scripts/wbclick.c 与 scripts/winfo.c
```

### 4. 校准坐标（关键，换机器必做）

脚本存的是**「窗口宽/高的归一化比例 NX/NY」**（运行时再换算成相对偏移），不是绝对坐标。
本机已验证值写在 `.traecheckin.offsets`（基于参考窗 1440×871 换算）：

```
AVATAR_NX=0.0313  AVATAR_NY=0.9839   # 左下角用户名/头像入口
BTN_NX=0.1458     BTN_NY=0.5534      # 用户菜单内「签到」按钮
```

UI 改版 / 换机器 / 窗口位移后**必须重新校准**：

```bash
cd trae-work-cn-checkin/scripts

# 诊断当前窗口 / 坐标 / 状态（先跑它确认截图是 Trae 窗口而非桌面）
bash trae-work-cn-checkin.sh debug

# 校准①：把鼠标悬停在左下角用户名/头像上，再运行（免回车）
bash trae-work-cn-checkin.sh where-entry

# 校准②：手动点开用户菜单，把鼠标悬停在「签到」按钮上，再运行（免回车）
bash trae-work-cn-checkin.sh where
```

> 校准值写入 `scripts/.traecheckin.offsets`，按当前窗口尺寸归一化，跨窗口尺寸自适应。
> 嫌麻烦也可以发一张「菜单打开、能看到签到按钮」的截图，由我算偏移写进文件。

### 5. 执行

```bash
cd trae-work-cn-checkin/scripts

# 执行一次签到（严格模式）
bash trae-work-cn-checkin.sh once

# 只诊断不点击
bash trae-work-cn-checkin.sh debug
```

运行日志落在 `scripts/checkin.log`，过程截图落在 `scripts/snapshot/`。

---

## 🎛 命令一览

| mode | 作用 |
|------|------|
| `once`（默认，可省略） | 完整签到流程：激活→发现窗口→点头像→识别菜单→点签到→校验。**用于每日定时任务。** |
| `debug` | 诊断：打印窗口矩形/windowID/坐标/菜单状态并截图，**不点击**。应先跑它确认窗口能被正确抓取。 |
| `windows` | 列出候选 Trae 窗口（CoreGraphics + System Events 两份视角）。 |
| `where-entry` | 校准用户名入口：鼠标悬停左下角用户名上后运行，记录归一化坐标。 |
| `where` | 校准签到按钮：点开用户菜单，鼠标悬停「签到」胶囊上后运行。 |
| `reset` | 清除已保存的校准偏移，恢复默认比例。 |

---

## ⚙️ 接入每日定时任务

推荐用 **WorkBuddy 自动化**建每日任务，因为它继承完整的辅助功能 / 屏幕录制权限，点击最稳：

- **命令**：`bash <skill目录>/scripts/trae-work-cn-checkin.sh once`
- **频率**：每天 `09:30`（GMT+8，可按需调整）
- **报告规则**（对齐脚本真实输出）：
  - 日志含「签到成功」或「今日已签」→ 报告「今日已签到」
  - 日志含「签到失败」或退出码非 0 → 报告「签到失败」，附 `snapshot/` 最近截图与日志 WARN/ERROR 行

---

## ❓ 常见问题速查

| 现象 | 原因 | 处理 |
|---|---|---|
| 截图是桌面 / 壁纸 | 旧版区域截图依赖窗口置前 | 已改用 `screencapture -l <windowID>`；若仍出现，检查 `debug` 里 `windowID` 是否为空（winfo 未找到 Trae） |
| 「窗口矩形自动发现失败」 | Trae 未运行 / 窗口不可见 / 缺权限 | 确认 Trae Work CN 已打开；检查辅助功能/屏幕录制权限；或临时设 `TRAECHECKIN_WIN_RECT=x|y|w|h` |
| 误开 Trae CN 而非 Trae Work CN | 窗口筛选关键字太宽 | 本 skill 已锁定 `work cn` 关键字；若仍误选，用 `windows` 看 owner/title |
| 点了但菜单没打开 / 签到失败 | 在 WorkBuddy 沙箱里 Trae 无法真正置前 | 到 iTerm 本地终端运行；`debug` 截图不受此限制 |
| OCR 识别不到中文 | 缺 `chi_sim` 语言包 | `brew install tesseract-lang`，确认 `tesseract --list-langs` 含 `chi_sim` |
| 坐标落点偏 / 点不中按钮 | 换了机器或 UI 改版 | 跑 `where-entry` / `where` 重新校准 |
| 今天已签却仍点 | 正常，会识别并跳过 | 无需处理 |

更多细节见 [SKILL.md](SKILL.md)。

---

## 📄 说明

- 仅适用于 **macOS 桌面端 Trae Work CN**（`cn.trae.solo.app`）；坐标用**归一化比例**存储，已自适应
  窗口缩放与 DPI，但基准比例仍基于本机特定 UI 版本，跨机型请走上面的「校准」流程。
- `.traecheckin.offsets` 里是本机已验证值（NX/NY 比例），**只是样例**，不代表你的机器可直接用。
- 仓库既有的 `workbuddy-click-skill` 是 WorkBuddy 桌面端签到的同类方案；本 skill 针对 Trae Work CN，
  并额外用 Window Server 窗口 ID 截图规避了「拍到桌面」这一坑。
