---
name: workbuddy-checkin
description: "macOS 桌面自动化：每日打开 WorkBuddy 左侧「Buddy加油站」抽屉并点击「立即领取/今日已领」按钮领取通用积分。当用户需要自动签到、重复领取积分、排查签到脚本坐标问题、校准头像/按钮点击位置、或把签到接入定时任务时使用。触发词：签到、领积分、每日签到、自动签到、Buddy加油站、立即领取、WorkBuddy签到、check-in、claim points、daily checkin。"
description_zh: "WorkBuddy 每日签到领积分（macOS 桌面自动化，自包含可复用）"
description_en: "WorkBuddy daily check-in / claim points (self-contained macOS desktop automation)"
version: "1.1.0"
allowed-tools: Bash, Read, Write, Edit
display_name: "WorkBuddy 签到"
visibility: "public"
agent_created: true
---

# WorkBuddy 每日签到助手（可复用分发包）

自动打开 WorkBuddy 左侧「Buddy加油站」抽屉，点击「立即领取」领取每日通用积分，
支持「今日已领」状态识别与跳过。坐标用「相对窗口偏移」存储，窗口移动/换屏都稳定可用。

本目录即一个**自包含、可移植**的分发包：整体拷到任意位置即可运行（脚本全部使用相对路径，
不依赖任何绝对路径）。新机器只需 `bash build.sh` 重编译 `wbclick` 并重新校准一次坐标。

---

## ⚠️ 先看：最容易踩的两个坑

1. **坐标必须校准，且是「相对窗口偏移」而非硬编码绝对坐标。**
   绝对坐标（如 `522,498`）在某个窗口位置下可能对，窗口一移动/换屏就全错，
   这是最初"假成功"的根因。本 skill 一律存 `ENTRY_REL_X/Y`、`BTN_REL_X/Y`（相对窗口原点）。
2. **Electron 应用按名点不到按钮。** WorkBuddy 对话区是 WebView，不向 macOS 辅助功能树
   暴露"立即领取"按钮。只能用"坐标点击 + 图像差分/饱和度/OCR 判定"方案，不能走 UI 树。

> 本机已校准的偏移（基于 1200×800 窗口，已写入 `scripts/.wbcheckin.offsets`）：
> `ENTRY_REL=(32,766)` 头像、`BTN_REL=(95,368)` 按钮。
> 若换机器 / WorkBuddy 改版 / 界面位移，跑一遍校准即可（见下文）。

---

## 工作原理（架构）

```
AppleScript 激活 + 读取窗口矩形
   └─ 窗口矩形在 CoreGraphics「事件坐标」空间(原点主屏左上, y 向下, 跨多屏, 负=副屏)
   ├─ screencapture -R 按窗口矩形整窗截图
   ├─ wbclick(CoreGraphics) 在 CG = 窗口原点 + 相对偏移 处点击
   └─ 判定弹框状态:
        ① 左下区域图像差分(>阈值 ⇒ 弹框已打开, 主信号)
        ② OCR 全图强信号("今日已领/已领取/领取成功") ⇒ claimed
        ③ OCR "立即领取" ⇒ unclaimed; 否则按钮饱和度兜底(亮色=未领, 灰=已领)
```

**关键约束**：对话本身也会提到"加油站/领取"，所以**单凭 OCR 关键词不能判定弹框是否打开**
——必须以「左下区域图像差分」作为弹框打开的主信号，OCR 只做"已领取"强确认。

---

## 环境依赖

- macOS（CoreGraphics / AppleScript）
- 编译 `wbclick`：`bash build.sh`（内部即 `clang -O2 -framework CoreGraphics -framework CoreFoundation -o wbclick wbclick.c`）；需要 Xcode 命令行工具 `xcode-select --install`
- `tesseract` + 中文包（`brew install tesseract tesseract-lang`，识别中文关键词用）
- `ImageMagick`（`convert`，做图像差分/饱和度分析）
- **权限**：运行脚本的进程需 macOS「辅助功能」权限（点击用）；`screencapture` 需「屏幕录制」权限。
  手动在终端跑若点击无效，多半是终端缺辅助功能权限 —— **改用 WorkBuddy 定时任务运行可继承完整权限**。
- ⚠️ 不要用 `open -a WorkBuddy` 激活，会让窗口矩形查询返回空；只用 `osascript ... activate`（脚本已内置）。

---

## 文件清单（本分发包自带）

```
SKILL.md                    # 本文档
README.md                   # 分发部署指南(前置依赖/编译/校准/定时接入)
build.sh                    # 编译 wbclick(新机器必跑)
scripts/
  workbuddy-checkin.sh      # 主控脚本(严格模式, 防止假成功)
  wbclick.c                 # 零依赖 CoreGraphics 坐标点击工具源码
  wbclick                   # 已编译二进制(本机可直接用, 新机请重编译)
  .wbcheckin.offsets        # 校准偏移样例(运行后会覆盖更新; 已含本机已验证值)
references/
  troubleshooting.md        # 详细排错与坐标校准笔记
```

部署：把整个 `skill/` 目录拷到任意固定位置即可（推荐直接放在你的工作区下，可复用本仓库）。
首次使用先编译 `wbclick`：

```bash
cd <skill目录>/scripts
bash ../build.sh
```

---

## 快速开始

```bash
cd <skill目录>/scripts

# 执行一次签到(严格模式: 未确认领取即判失败, 绝不谎报成功)
bash workbuddy-checkin.sh

# 仅诊断, 不点击: 打印窗口矩形 / 坐标 / 弹框状态
bash workbuddy-checkin.sh debug
```

成功日志（`checkin.log`）示例：
```
窗口矩形: 100|100|1200|800  SCALE=2
头像点击 CG=(132,866) [相对 32,766]
按钮点击 CG=(195,468) [相对 95,368]
弹框状态(点击头像后): claimed
=== 签到完成(今日已领) ===
```

---

## 校准流程（换机器 / 界面位移 / 改版后必做）

坐标失效或首次部署时，两步人工校准（其余交给脚本）：

```bash
cd <skill目录>/scripts

# 第 1 步：在 WorkBuddy 里把鼠标悬停在「打开 Buddy加油站 的头像/控件」上，运行：
bash workbuddy-checkin.sh where-entry

# 第 2 步：手动点开签到抽屉，鼠标悬停在「立即领取」按钮上，运行：
bash workbuddy-checkin.sh where
```

坐标会写入 `scripts/.wbcheckin.offsets`。`wbclick -w` 读光标坐标已验证可用。
嫌麻烦也可直接发我一张抽屉打开、能看到按钮的截图，由我算偏移写进文件。

自动探测（可选）：`bash workbuddy-checkin.sh probe` 会扫描左下角网格定位头像热区，
命中即写 offsets（依赖点击权限，手动 bash 跑可能因缺权限失败）。

---

## 状态判定与防止"假成功"

- `popup_state()` 返回 `claimed | unclaimed | none`。
- `main()` **严格模式**：只有确认 `claimed` 或"弹框确实打开过又关闭"才返回成功（退出码 0）；
  若从头到尾弹框都没打开（点击疑似 no-op），则 `WARN` 并以退出码 1 收尾，让调用方感知失败。
- 历史教训：旧版把 `none`（弹框根本没开）也当成功 → 连续"假成功"。现已杜绝。

---

## 接入定时任务（每日自动签到）

用 WorkBuddy 自动化创建每日任务（继承完整辅助功能/屏幕录制权限，点击最稳）：

- 命令（用 `caffeinate -i` 防止期间 Mac 休眠）：
  `caffeinate -i bash <skill目录>/scripts/workbuddy-checkin.sh`
- 频率：`FREQ=DAILY;BYHOUR=9;BYMINUTE=5`（每天 09:05，GMT+8）
- 报告规则（对齐脚本真实输出）：
  - 日志含「签到完成(今日已领)」→ 报告"今日已签到，已跳过"
  - 日志含「签到完成(已领取)」→ 报告"今日签到成功"
  - 日志含「签到失败」或「WARN」→ 报告"签到失败"，附 `snapshot/` 最近截图与日志 WARN/ERROR 行

---

## 排错清单

| 现象 | 原因 | 处理 |
|---|---|---|
| 弹框未打开，状态恒 `none` | 头像偏移错 / 点击权限不足 | `where-entry` 重新校准；或改用定时任务运行 |
| `wbclick` 打印帮助而非点击 | 负坐标被误当选项（旧 bug，已修） | 用本包 `wbclick.c` 重编译 |
| 窗口矩形为空 | 用了 `open -a` 激活 | 改用 `osascript … activate`（脚本已内置） |
| 点击位置错落在对话区 | 偏移是绝对坐标残留 | 确认 `.wbcheckin.offsets` 是相对偏移，重校准 |
| 今天已领却仍点 | 逻辑正常，会识别 `claimed` 跳过 | 无需处理 |
| OCR 把对话里的"领取"误判 | 仅 OCR 不可靠 | 以图像差分为主信号（脚本已如此） |

更多细节见 [references/troubleshooting.md](references/troubleshooting.md) 与 [README.md](README.md)。
