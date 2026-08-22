---
name: trae-work-cn-checkin
description: "Automate the daily check-in (每日签到) inside the macOS 'Trae Work CN' app — click the bottom-left user avatar to open the menu, then click the 签到 button. Uses relative (normalized) coordinates so it survives window move/resize, and captures the window by Window-Server ID to avoid screenshotting the desktop. Use when the user mentions Trae Work CN 签到, macOS 桌面自动签到, or daily GUI check-in automation."
description_zh: "macOS『Trae Work CN』App 每日签到自动化：点击左下角用户名打开菜单，再点签到按钮。采用归一化相对坐标（抗窗口移动/缩放），并按 Window Server 窗口 ID 截图（避免拍到桌面）。"
description_en: "Automate daily check-in in macOS 'Trae Work CN' via relative coordinates and window-ID capture."
version: 1.0.0
display_name: "Trae Work CN 每日签到"
display_name_en: "Trae Work CN Daily Check-in"
visibility: "private"
metadata:
  tags:
    - "trae"
    - "签到"
    - "macos automation"
    - "desktop check-in"
    - "gui automation"
  clawdbot:
    emoji: "\U0001F3A5"
    requires:
      bins:
        - bash
        - clang
        - osascript
        - screencapture
---

# Trae Work CN 每日签到（macOS 桌面自动化）

在 macOS 上自动完成 **Trae Work CN**（`cn.trae.solo.app`，窗口标题 `TRAE Work CN`）的每日签到：
点击左下角用户名/头像 → 弹出用户菜单 → 点击菜单内的「签到」胶囊按钮（或识别「今日已签」）。

配套脚本：`{baseDir}/scripts/trae-work-cn-checkin.sh`（全部逻辑：窗口发现、激活、截图、点击、OCR/图像差分状态判定、校准）。

## 核心设计（务必理解，便于排错）

1. **归一化相对坐标（NX/NY）**：点击位置存成相对窗口宽高的比例（0–1），运行时换算为像素
   `像素 = NX*WIN_W`，绝对 CG 坐标 = `窗口原点 + 像素偏移`。窗口移动/缩放/换屏都自动适配，
   **不会因窗口位置变化而点错**。
2. **按 Window Server 窗口 ID 截图**：`screencapture -l <windowID>`，
   直接从 Window Server 抓窗口本体，**不依赖 Trae 是否置于最前**，因此不会拍到后面的桌面壁纸。
   （旧方案 `screencapture -R 区域` 抓的是「屏幕上该坐标实际显示的内容」，Trae 没置前时就拍到桌面。）
3. **严格成功判定**：仅在菜单确实打开且按钮被点击、或识别出「今日已签」时才判定成功；
   否则返回非 0，**绝不谎报成功**。
4. **目标锁定 Trae Work CN**：窗口筛选优先标题/owner 含 `work cn` / `trae work`，
   即使存在更大的「Trae CN」窗口也不会误选。

## 前置条件

- macOS；安装命令行开发者工具（`clang`）：`xcode-select --install`（若未装）。
- **必须在「系统设置 → 隐私与安全性」中授予 WorkBuddy / 终端 两项权限**：
  - **辅助功能（Accessibility）** —— 用于 `wbclick` 发送鼠标事件、AppleScript 激活窗口。
  - **屏幕录制（Screen Recording）** —— 用于 `screencapture` 抓取窗口。
- **OCR 依赖（推荐）**：状态判定用 `tesseract`(chi_sim+eng) + ImageMagick `convert`。
  缺省也能靠图像差分兜底，但建议安装：`brew install tesseract imagemagick`，
  并确保 `tesseract --list-langs` 含 `chi_sim`（中文语言包：`brew install tesseract-lang`）。
- Trae Work CN 已安装、已登录，且左侧栏可见（签到入口在左下角用户区）。

## 安装 / 构建

```bash
bash {baseDir}/scripts/build.sh
```

会编译出 `wbclick` 与 `winfo` 两个可执行文件（与脚本同目录）。

## 用法

```bash
bash {baseDir}/scripts/trae-work-cn-checkin.sh <mode>
```

| mode | 作用 |
|------|------|
| `once`（默认，可省略） | 完整签到流程：激活→发现窗口→点头像→识别菜单→点签到→校验。**用于每日定时任务。** |
| `debug` | 诊断：打印窗口矩形/windowID/坐标/菜单状态并截图，**不点击**。应先跑它确认窗口能被正确抓取。 |
| `windows` | 列出候选 Trae 窗口（CoreGraphics + System Events 两份）。 |
| `where-entry` | 校准用户名入口：把鼠标悬停在左下角用户名上后运行，记录归一化坐标。 |
| `where` | 校准签到按钮：先点开用户菜单，把鼠标悬停在「签到」按钮上后运行。 |
| `reset` | 清除已保存的校准偏移，恢复默认比例。 |

日志：`{baseDir}/scripts/checkin.log`；调试截图：`{baseDir}/scripts/snapshot/`。

## 首次部署步骤

1. `bash {baseDir}/scripts/build.sh`
2. `bash {baseDir}/scripts/trae-work-cn-checkin.sh debug` —— 确认截图是 Trae 窗口（非桌面）、坐标合理。
3. 若 debug 显示未校准或坐标偏差，手动校准：
   - 把鼠标移到左下角用户名上 → `bash {baseDir}/scripts/trae-work-cn-checkin.sh where-entry`
   - 点开用户菜单，把鼠标移到「签到」按钮上 → `bash {baseDir}/scripts/trae-work-cn-checkin.sh where`
   （校准值写入 `{baseDir}/scripts/.traecheckin.offsets`，按当前窗口尺寸归一化，跨窗口尺寸自适应。）
4. `bash {baseDir}/scripts/trae-work-cn-checkin.sh once` —— 验证能成功签到（或识别「今日已签」）。

## 接入每日定时任务

验证 `once` 可用后，用 `automation_update`（mode=create）创建每日任务，例如每天 09:30 (GMT+8)：

- name：`Trae Work CN 每日签到`
- prompt：`运行 bash {baseDir}/scripts/trae-work-cn-checkin.sh once 完成 Trae Work CN 每日签到；仅当输出含"签到成功"或"今日已签"时视为完成，否则报告失败日志。`
- scheduleType：`recurring`，rrule：`FREQ=DAILY;BYHOUR=9;BYMINUTE=30`（按用户时区，默认 GMT+8）
- 注意：定时任务在 WorkBuddy 进程树下运行，已继承辅助功能/屏幕录制权限，无需额外授权终端。

## 排错速查

- **截图是桌面/壁纸**：已通过 `screencapture -l <windowID>` 修复；若仍出现，检查 `debug` 里的 `windowID` 是否为空（winfo 未找到 Trae）。
- **「窗口矩形自动发现失败」**：确认 Trae Work CN 正在运行且窗口可见；检查辅助功能/屏幕录制权限；或临时设环境变量 `TRAECHECKIN_WIN_RECT=x|y|w|h` 指定窗口。
- **误开 Trae CN 而非 Trae Work CN**：本 skill 已锁定 `work cn` 关键字；若仍误选，检查 `windows` 输出里的 owner/title。
- **点了但菜单没打开 / 签到失败**：在 iTerm 本地终端运行（而非 WorkBuddy 沙箱），沙箱可能无法把 Trae 真正置前；`debug` 截图不受此限制。
- **OCR 识别不到中文**：确认 `tesseract` 已装 `chi_sim` 语言包。

## 文件清单

- `scripts/trae-work-cn-checkin.sh` —— 主脚本（全部逻辑）
- `scripts/wbclick.c` —— CoreGraphics 点击/读光标工具源码
- `scripts/winfo.c` —— CoreGraphics 窗口枚举工具源码
- `scripts/build.sh` —— 编译上述两个工具
- `scripts/.traecheckin.offsets` —— 校准偏移（NX/NY 归一化比例）
