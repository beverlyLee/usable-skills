#!/usr/bin/env bash
# =============================================================================
# WorkBuddy 每日签到领取助手  (重构版 v2)
# -----------------------------------------------------------------------------
# 思路: macOS 桌面自动化 = AppleScript(激活+定位窗口) + screencapture(区域截图)
#       + wbclick(CoreGraphics 绝对坐标点击) + 图像差分/左侧卡片 OCR 判定.
#
# 流程(v5.3.5 新版):
#   1. 点击左下角用户头像, 打开用户菜单.
#   2. 点击菜单内"Buddy 加油站", 打开签到卡片.
#   3. 若卡片显示"立即领取"则点击; 若显示"今日已领/已领取/已领X天"则跳过.
#   4. 点击后通过卡片关闭或状态变化确认领取成功.
#
# 为什么不用"按名点击 UI 树":
#   WorkBuddy 是 Electron 应用, 其对话区是 WebView, 不向 macOS 辅助功能树
#   暴露"立即领取"按钮, 按名点击必然失败. 改用"坐标点击 + 图像差分/左侧卡片 OCR".
#
# 坐标空间: AppleScript 窗口 position 与 wbclick 同为 CoreGraphics「事件坐标」
#   (原点主屏左上, y 向下, 跨多屏, 负坐标=副屏), 无需 y 翻转.
#
# ★ v2 关键改动: 坐标一律存「相对窗口原点的偏移」, 运行时
#     CG = 当前窗口原点 + 相对偏移
#   这样 WorkBuddy 窗口在主屏/副屏、被拖动后都稳定可用(实测窗口矩形会浮动,
#   曾见 42|108 与 345|-977 两种位置).
#
# 重要: 不要用 `open -a WorkBuddy` —— 它会让窗口矩形查询返回空.
#        只用 `osascript ... activate` 激活即可.
#
# ⚠️ 权限: wbclick 点击需要调用进程(iTerm/Terminal 或 WorkBuddy 定时任务)
#    具备「辅助功能」权限; screencapture 需要「屏幕录制」权限.
#    若手动 bash 跑点击无效(弹框不开), 多半是 iTerm 缺辅助功能权限,
#    可改用 WorkBuddy 定时任务运行(继承完整权限).
#
# 用法:
#   bash workbuddy-checkin.sh            # 执行一次签到领取 (严格模式: 未确认领取即判失败)
#   bash workbuddy-checkin.sh debug      # 仅诊断: 打印窗口/坐标/弹框状态, 不点击
#   bash workbuddy-checkin.sh where-entry# 校准入口: 先把鼠标悬停在左侧"Buddy 加油站"菜单上, 再运行(免回车)
#   bash workbuddy-checkin.sh where      # 校准按钮: 先点开 Buddy 加油站卡片, 鼠标悬停"立即领取", 再运行(免回车)
#   bash workbuddy-checkin.sh probe      # 自动扫描网格定位"Buddy 加油站"菜单热区(成功才会写入 offsets)
#
# ⚠️ 重要: 本脚本严格模式——只有"确认已领取(claimed)"才返回成功(退出码 0)。
#    若头像点击后弹框未打开, 或点击领取后未确认, 一律返回失败(退出码 1)并提示校准,
#    绝不再把"none/弹框未打开"当成"签到完成"。如坐标变了/界面更新, 请用 where-entry / where 重新校准。
# =============================================================================

set -uo pipefail

# ---------- 路径 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT_DIR="$SCRIPT_DIR/snapshot"
OFFSETS_FILE="$SCRIPT_DIR/.wbcheckin.offsets"
WB_CLICK="$SCRIPT_DIR/wbclick"
LOG_FILE="$SCRIPT_DIR/checkin.log"
mkdir -p "$SNAPSHOT_DIR"

# ---------- 窗口默认(实测出现过 42|108 与 345|-977, 运行时以 discover 为准) ----------
WIN_X=42; WIN_Y=108; WIN_W=1200; WIN_H=800
SCALE=2   # 截图像素 / CSS 点, 运行时会按实际截图尺寸重算

# ---------- 弹框状态判定(替代 OCR) ----------
POPUP_BASELINE=""        # 卡片关闭基线截图路径, 由 main 在点击头像前设置
DIFF_OPEN_TH=0.012       # 左下区域差分均值(归一 0..1) > 此值 => 卡片已打开(实测: 开=0.029, 关≈0.0003)

# ---------- 归一化坐标(窗口宽/高比例 NX/NY, 0..1) + 兼容旧像素偏移 ----------
# 设计: 坐标以「窗口宽/高的比例」存储(NX/NY), 运行时
#   CG = 窗口原点 + NX*WIN_W (或 NY*WIN_H)
#   这样窗口缩放、换不同 DPI 的屏都能自适应, 不再依赖本机校准的像素值.
#   仍兼容旧版 .wbcheckin.offsets 里的 *_REL_* 像素偏移(按参考窗口 1200x800 换算成比例).
# 初值(2026-07-30 v5.3.5, 于 1200x800 参考窗口):
#   AVATAR  左下角用户头像中心       约 (59,759)  -> (0.0492, 0.9488)
#   MENU    用户菜单内"Buddy 加油站" 约 (75,330)  -> (0.0625, 0.4125)
#   BTN     "立即领取"按钮中心  (已校正: 原 80,730 偏下 24px 未点中, 实测 75,706 命中)
#                                    (75,706)     -> (0.0625, 0.8825)
REF_W=1200; REF_H=800
DEF_AVATAR_NX=0.0492; DEF_AVATAR_NY=0.9488
DEF_MENU_NX=0.0625;   DEF_MENU_NY=0.4125
DEF_BTN_NX=0.0625;     DEF_BTN_NY=0.8825
AVATAR_NX=$DEF_AVATAR_NX; AVATAR_NY=$DEF_AVATAR_NY
MENU_NX=$DEF_MENU_NX;     MENU_NY=$DEF_MENU_NY
BTN_NX=$DEF_BTN_NX;       BTN_NY=$DEF_BTN_NY
# 兼容: 旧 *_REL_* 像素偏移(若 offsets 文件提供则覆盖上面的比例)
AVATAR_REL_X=""; AVATAR_REL_Y=""; MENU_REL_X=""; MENU_REL_Y=""; BTN_REL_X=""; BTN_REL_Y=""
USE_REL=0
# 旧版绝对坐标格式兼容标记
LEGACY_ABS=0
# 按钮区灰度阈值(0..65535): 浅色"今日已领"按钮明显亮于深色"立即领取"按钮
BTN_BRIGHT_TH=49000       # > 此值 => 已为浅色"今日已领"(今日已签)
BTN_BRIGHT_DELTA=8000     # 点击前后按钮区灰度增量 > 此值 => 领取成功(深->浅)

# ---------- 工具函数 ----------
ts()   { date +%Y%m%d_%H%M%S; }
log()  { local t; t=$(date '+%Y-%m-%d %H:%M:%S'); echo "[$t] $*" | tee -a "$LOG_FILE"; }
# diag: 仅写日志文件 + stderr, 不写 stdout. 供 popup_state 等"返回值在 stdout"的函数使用,
#       避免诊断输出污染 $() 命令替换捕获到的返回值(claimed/unclaimed/none).
diag() { local t; t=$(date '+%Y-%m-%d %H:%M:%S'); echo "[$t] $*" | tee -a "$LOG_FILE" >&2; }

load_offsets() {
  [ -f "$OFFSETS_FILE" ] || return 0
  local k v
  while IFS='=' read -r k v; do
    [ -z "${k:-}" ] && continue
    case "$k" in
      AVATAR_NX) AVATAR_NX="$v" ;; AVATAR_NY) AVATAR_NY="$v" ;;
      MENU_NX)   MENU_NX="$v"   ;; MENU_NY)   MENU_NY="$v"   ;;
      BTN_NX)    BTN_NX="$v"    ;; BTN_NY)    BTN_NY="$v"    ;;
      AVATAR_REL_X) AVATAR_REL_X="$v"; USE_REL=1 ;;
      AVATAR_REL_Y) AVATAR_REL_Y="$v"; USE_REL=1 ;;
      MENU_REL_X)   MENU_REL_X="$v";   USE_REL=1 ;;
      MENU_REL_Y)   MENU_REL_Y="$v";   USE_REL=1 ;;
      BTN_REL_X)    BTN_REL_X="$v";    USE_REL=1 ;;
      BTN_REL_Y)    BTN_REL_Y="$v";    USE_REL=1 ;;
      ENTRY_REL_X)  MENU_REL_X="$v"; USE_REL=1 ;;   # 兼容 v2 旧名: ENTRY_REL 曾代表菜单项
      ENTRY_REL_Y)  MENU_REL_Y="$v"; USE_REL=1 ;;
      ENTRY_X)      LEGACY_ABS=1      ;;   # 旧绝对格式存在
    esac
  done < "$OFFSETS_FILE"
}

# 把归一化比例解析为「相对窗口原点的像素偏移」(运行时随窗口尺寸/DPI 自适应).
# 优先使用 *_REL_* 像素偏移(USE_REL=1, 兼容旧文件), 否则由 NX/NY*当前窗口换算.
resolve_offsets() {
  if [ "$USE_REL" -eq 1 ]; then
    AVATAR_REL_X=${AVATAR_REL_X:-$(awk "BEGIN{printf \"%d\", $AVATAR_NX*$WIN_W}")}
    AVATAR_REL_Y=${AVATAR_REL_Y:-$(awk "BEGIN{printf \"%d\", $AVATAR_NY*$WIN_H}")}
    MENU_REL_X=${MENU_REL_X:-$(awk "BEGIN{printf \"%d\", $MENU_NX*$WIN_W}")}
    MENU_REL_Y=${MENU_REL_Y:-$(awk "BEGIN{printf \"%d\", $MENU_NY*$WIN_H}")}
    BTN_REL_X=${BTN_REL_X:-$(awk "BEGIN{printf \"%d\", $BTN_NX*$WIN_W}")}
    BTN_REL_Y=${BTN_REL_Y:-$(awk "BEGIN{printf \"%d\", $BTN_NY*$WIN_H}")}
    # 反算 NX/NY 以便保存为归一化格式
    AVATAR_NX=$(awk "BEGIN{printf \"%.4f\", $AVATAR_REL_X/$WIN_W}")
    AVATAR_NY=$(awk "BEGIN{printf \"%.4f\", $AVATAR_REL_Y/$WIN_H}")
    MENU_NX=$(awk "BEGIN{printf \"%.4f\", $MENU_REL_X/$WIN_W}")
    MENU_NY=$(awk "BEGIN{printf \"%.4f\", $MENU_REL_Y/$WIN_H}")
    BTN_NX=$(awk "BEGIN{printf \"%.4f\", $BTN_REL_X/$WIN_W}")
    BTN_NY=$(awk "BEGIN{printf \"%.4f\", $BTN_REL_Y/$WIN_H}")
    return 0
  fi
  AVATAR_REL_X=$(awk "BEGIN{printf \"%d\", $AVATAR_NX*$WIN_W}")
  AVATAR_REL_Y=$(awk "BEGIN{printf \"%d\", $AVATAR_NY*$WIN_H}")
  MENU_REL_X=$(awk "BEGIN{printf \"%d\", $MENU_NX*$WIN_W}")
  MENU_REL_Y=$(awk "BEGIN{printf \"%d\", $MENU_NY*$WIN_H}")
  BTN_REL_X=$(awk "BEGIN{printf \"%d\", $BTN_NX*$WIN_W}")
  BTN_REL_Y=$(awk "BEGIN{printf \"%d\", $BTN_NY*$WIN_H}")
}

# 迁移: 旧绝对格式 -> 相对偏移(假设校准时窗口≈当前窗口, 通常成立)
migrate_legacy() {
  [ "$LEGACY_ABS" -eq 0 ] && return 0
  [ -f "$OFFSETS_FILE" ] || return 0
  local ax ay bx by
  ax=$(grep '^ENTRY_X=' "$OFFSETS_FILE" | cut -d= -f2)
  ay=$(grep '^ENTRY_Y=' "$OFFSETS_FILE" | cut -d= -f2)
  bx=$(grep '^BTN_X='   "$OFFSETS_FILE" | cut -d= -f2)
  by=$(grep '^BTN_Y='   "$OFFSETS_FILE" | cut -d= -f2)
  # 旧绝对格式对应的是头像入口, 迁移为 AVATAR_REL
  [ -n "$ax" ] && AVATAR_REL_X=$((ax - WIN_X))
  [ -n "$ay" ] && AVATAR_REL_Y=$((ay - WIN_Y))
  if [ -n "$bx" ] && [ -n "$by" ]; then
    brx=$((bx - WIN_X)); bry=$((by - WIN_Y))
    if [ "$brx" -ge 0 ] && [ "$brx" -le "$WIN_W" ] && [ "$bry" -ge 0 ] && [ "$bry" -le "$WIN_H" ]; then
      BTN_REL_X=$brx; BTN_REL_Y=$bry
    else
      BTN_REL_X=$DEF_BTN_REL_X; BTN_REL_Y=$DEF_BTN_REL_Y
    fi
  fi
  log "已从旧绝对坐标迁移为相对偏移(基于当前窗口 $WIN_X,$WIN_Y)"
  save_offsets
  LEGACY_ABS=0
}

save_offsets() {
  resolve_offsets
  cat > "$OFFSETS_FILE" <<EOF
# WorkBuddy 签到助手校准偏移 (v3: 归一化比例 NX/NY 为主, 兼容旧 *_REL_* 像素)
# 运行时 CG = 窗口原点 + NX*WIN_W (或 NY*WIN_H), 自适应窗口尺寸/DPI.
# REF 窗口 ${REF_W}x${REF_H}. BTN 已校正为 ($(awk "BEGIN{printf \"%d\",$BTN_NX*$REF_W}"),$(awk "BEGIN{printf \"%d\",$BTN_NY*$REF_H}"))) 实测命中"立即领取".
AVATAR_NX=$AVATAR_NX
AVATAR_NY=$AVATAR_NY
MENU_NX=$MENU_NX
MENU_NY=$MENU_NY
BTN_NX=$BTN_NX
BTN_NY=$BTN_NY
AVATAR_REL_X=$AVATAR_REL_X
AVATAR_REL_Y=$AVATAR_REL_Y
MENU_REL_X=$MENU_REL_X
MENU_REL_Y=$MENU_REL_Y
BTN_REL_X=$BTN_REL_X
BTN_REL_Y=$BTN_REL_Y
EOF
  log "已保存校准偏移到 $OFFSETS_FILE"
}

# 激活 WorkBuddy(仅 activate, 禁止 open -a)
activate_workbuddy() {
  osascript -e 'try
    tell application "WorkBuddy" to activate
  on error
    tell application id "com.workbuddy.workbuddy" to activate
  end try' 2>/dev/null
}

# 通过 bundle identifier 读取窗口矩形; 返回 "x|y|w|h" 或空
wb_window_rect() {
  osascript -e '
    set found to ""
    tell application "System Events"
      repeat with p in (processes whose background only is false)
        try
          set bid to bundle identifier of p
        on error
          set bid to ""
        end try
        if bid contains "workbuddy" then
          repeat with w in (windows of p)
            try
              set pos to position of w
              set sz to size of w
              set found to ((item 1 of pos as text) & "|" & (item 2 of pos as text) & "|" & (item 1 of sz as text) & "|" & (item 2 of sz as text))
            end try
          end repeat
        end if
      end repeat
    end tell
    return found' 2>/dev/null
}

# 发现窗口矩形(带重试); 成功写全局 WIN_*; 失败回退默认
discover_window() {
  local rect i
  for i in $(seq 1 5); do
    rect="$(wb_window_rect)"
    if [ -n "$rect" ]; then
      WIN_X=$(echo "$rect" | cut -d'|' -f1)
      WIN_Y=$(echo "$rect" | cut -d'|' -f2)
      WIN_W=$(echo "$rect" | cut -d'|' -f3)
      WIN_H=$(echo "$rect" | cut -d'|' -f4)
      return 0
    fi
    sleep 0.6
  done
  log "WARN: 窗口矩形自动发现失败, 回退默认 ${WIN_X}|${WIN_Y}|${WIN_W}|${WIN_H}"
  return 0
}

# 按窗口矩形截图到指定路径(直接落 snapshot/, 不用 /tmp)
capture() {
  local out="$1"
  screencapture -x -R "${WIN_X},${WIN_Y},${WIN_W},${WIN_H}" "$out" 2>/dev/null
  local iw; iw=$(sips -g pixelWidth "$out" 2>/dev/null | awk -F': ' '/pixelWidth/{print $2}')
  [ -n "${iw:-}" ] && [ "$iw" -gt 0 ] && SCALE=$(( iw / WIN_W ))
  [ "$SCALE" -lt 1 ] && SCALE=1
}

click_cg() { "$WB_CLICK" "$1" "$2"; }

# 按钮区灰度均值(0..65535): 浅色"今日已领"按钮明显亮于深色"立即领取"按钮.
# 截图仅在按钮区域裁剪, 避开卡片头部的"已领N天"等常驻文字, 避免干扰.
# 依赖全局 BTN_REL_X/Y(已解析为像素偏移), 以及 WIN_W/H, SCALE.
btn_brightness() {
  local img="$1"
  [ -f "$img" ] || { echo 0; return; }
  local btw bth cx cy cw ch
  # 按钮尺寸随窗口缩放(参考窗口 1200x800 下约 100x29 像素偏移)
  btw=$(awk "BEGIN{printf \"%d\", 100*$WIN_W/$REF_W}")
  bth=$(awk "BEGIN{printf \"%d\", 29*$WIN_H/$REF_H}")
  cx=$(( (BTN_REL_X - btw/2) * SCALE ))
  cy=$(( (BTN_REL_Y - bth/2) * SCALE ))
  cw=$(( btw * SCALE )); ch=$(( bth * SCALE ))
  [ "$cx" -lt 0 ] && cx=0
  [ "$cy" -lt 0 ] && cy=0
  convert "$img" -crop "${cw}x${ch}+${cx}+${cy}" +repage -colorspace Gray \
    -format '%[mean]' info: 2>/dev/null || echo 0
}

# 弹框状态判定: 图像差分(是否打开) + 左侧卡片 OCR(已领取关键词).
#   -> claimed | unclaimed | none
# 依赖全局 POPUP_BASELINE(弹框关闭基线截图). 缺失时无法差分, 退化为返回 none.
#
# ⚠️ 设计约束:
#   - 对话区本身可能提到"已领取/领取"等词, 因此"已领取"OCR 必须限定在左侧卡片区域,
#     避免把对话文字误判为弹框状态.
#   - "立即领取"按钮文字小且样式化, tesseract 常识别不出; 且实际未领取按钮为浅色
#     中性色, 饱和度/亮度不能可靠区分 claimed/unclaimed. 因此弹框打开后, 只要没有
#     命中已领取关键词, 一律视为 unclaimed, 由主流程点击后的状态变化来验证.
popup_state() {
  local img="$1"
  [ -f "$img" ] || { echo none; return; }

  # --- 0) 左侧卡片 OCR: 命中"今日已领/已领取/领取成功/已签到" -> claimed ---
  # 限定区域避免对话区文字干扰. 新版(v5.3.5)卡片位于窗口左下角 y=600..800 CSS.
  # 注意: tesseract 在 /tmp 下会报 Leptonica "image file not found", 故文件放 snapshot/.
  local card_crop ocr_text
  card_crop=$(mktemp "$SNAPSHOT_DIR/wb_card.XXXXXX.png")
  local cw=$((280*SCALE)) ch=$((200*SCALE)) cx=0 cy=$((600*SCALE))
  convert "$img" -crop "${cw}x${ch}+${cx}+${cy}" +repage "$card_crop" 2>/dev/null
  if [ -s "$card_crop" ]; then
    ocr_text=$(env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy tesseract "$card_crop" stdout --psm 11 -l chi_sim+eng 2>/dev/null)
    # 注意: 不要匹配"已领N天"连续签到计数(卡片头部常驻统计, 与"今日是否已领"无关,
    #       会误判为 claimed 导致跳过点击). 仅以真正的已领取关键词判定今日已领.
    if echo "$ocr_text" | grep -qE "今日已领|已领取|领取成功|已签到"; then
      rm -f "$card_crop"
      diag "popup_state: 左侧卡片 OCR 命中已领取关键词 -> claimed"
      echo claimed; return
    fi
  fi
  rm -f "$card_crop"

  # --- 1) 弹框是否打开: 左下区域(窗口相对 x:0..420, y:600..800)差分 ---
  local pop_open=0
  if [ -n "${POPUP_BASELINE:-}" ] && [ -f "$POPUP_BASELINE" ]; then
    local cw=$((420*SCALE)) ch=$((200*SCALE)) coy=$((600*SCALE))
    local base_crop cur_crop dmean dmax dnorm
    base_crop=$(mktemp -t wb_base.XXXXXX.png)
    cur_crop=$(mktemp -t wb_cur.XXXXXX.png)
    convert "$POPUP_BASELINE" -crop "${cw}x${ch}+0+${coy}" +repage "$base_crop" 2>/dev/null
    convert "$img"            -crop "${cw}x${ch}+0+${coy}" +repage "$cur_crop" 2>/dev/null
    if [ -s "$base_crop" ] && [ -s "$cur_crop" ]; then
      read -r dmean dmax < <(convert "$base_crop" "$cur_crop" -compose difference -composite \
                              -colorspace Gray -format "%[mean] %[max]" info: 2>/dev/null)
      dmean=${dmean:-0}; dmax=${dmax:-1}
      dnorm=$(awk -v m="$dmean" -v x="$dmax" 'BEGIN{ if (x+0==0) print 0; else printf "%.5f", m/x }')
      diag "popup_state: 左下差分均值(归一)=${dnorm} (阈值${DIFF_OPEN_TH})"
      if awk "BEGIN{exit !($dnorm > $DIFF_OPEN_TH)}"; then
        pop_open=1
      fi
    fi
    rm -f "$base_crop" "$cur_crop"
  fi

  if [ "$pop_open" -eq 0 ]; then
    echo none
    return
  fi

  # --- 2) 弹框已打开且无已领取 OCR -> 视为 unclaimed ---
  # 由主流程点击后再验证; 若实际已领取, 点击后仍保持 claimed/none, 验证阶段会正确成功.
  diag "popup_state: 弹框已打开, 未命中已领取关键词 -> unclaimed"
  echo unclaimed; return
}

# ---------- 主流程 ----------
# 防谎报: 只有"弹框确实被确认打开过(POPUP_CONFIRMED_OPEN=1)"且最终态为
#   claimed / 按钮变浅(亮度跃升) / "开了又关(none)", 才算成功; 若从头到尾弹框都没打开,
#   则明确 WARN 并以非 0 退出码收尾, 让调用方(定时任务)能感知失败.
main() {
  load_offsets
  log "=== 签到开始 ==="
  activate_workbuddy; sleep 0.8
  discover_window
  resolve_offsets
  migrate_legacy
  log "窗口矩形: ${WIN_X}|${WIN_Y}|${WIN_W}|${WIN_H}  SCALE=$SCALE"
  log "归一化坐标: AVATAR($AVATAR_NX,$AVATAR_NY) MENU($MENU_NX,$MENU_NY) BTN($BTN_NX,$BTN_NY)"
  log "解析后相对偏移: AVATAR($AVATAR_REL_X,$AVATAR_REL_Y) MENU($MENU_REL_X,$MENU_REL_Y) BTN($BTN_REL_X,$BTN_REL_Y)"

  local ax ay ecx ecy bcx bcy before popup s0 after s1 s2 b0 b1 b2 POPUP_CONFIRMED_OPEN=0
  ax=$((WIN_X+AVATAR_REL_X)); ay=$((WIN_Y+AVATAR_REL_Y))
  ecx=$((WIN_X+MENU_REL_X));  ecy=$((WIN_Y+MENU_REL_Y))
  bcx=$((WIN_X+BTN_REL_X));   bcy=$((WIN_Y+BTN_REL_Y))
  log "头像点击 CG=($ax,$ay)"
  log "Buddy 加油站点击 CG=($ecx,$ecy)"
  log "立即领取点击 CG=($bcx,$bcy)"

  before="$SNAPSHOT_DIR/before_$(ts).png"; capture "$before"
  log "点击前截图: $before"
  POPUP_BASELINE="$before"   # 弹框关闭基线, 供 popup_state 差分对比

  # 0) 若卡片已打开且显示已领取, 直接成功
  local s_baseline
  s_baseline="$(popup_state "$before")"
  log "初始弹框状态: $s_baseline"
  if [ "$s_baseline" = "claimed" ]; then
    log "卡片已打开且显示已领取, 无需重复操作"
    log "=== 签到完成(今日已领) ==="; return 0
  fi

  # 1) 打开用户菜单: 点击左下角头像
  click_cg "$ax" "$ay"; sleep 1.0

  # 2) 打开签到卡片: 点击菜单内"Buddy 加油站"
  click_cg "$ecx" "$ecy"; sleep 1.3
  popup="$SNAPSHOT_DIR/popup_$(ts).png"; capture "$popup"
  s0="$(popup_state "$popup")"
  log "弹框状态(点击Buddy加油站后): $s0"
  case "$s0" in claimed|unclaimed) POPUP_CONFIRMED_OPEN=1;; esac

  # 2b) 归一化坐标未打开卡片 -> 自动探测 Buddy 加油站 热区(自愈)
  if [ "$s0" = "none" ]; then
    log "WARN: 归一化坐标未打开卡片, 尝试自动探测 Buddy 加油站 热区..."
    if auto_probe_menu; then
      ecx=$((WIN_X+MENU_REL_X)); ecy=$((WIN_Y+MENU_REL_Y))
      click_cg "$ecx" "$ecy"; sleep 1.3
      capture "$popup"; s0="$(popup_state "$popup")"
      log "自动探测后卡片状态: $s0 (新 MENU 偏移 $MENU_REL_X,$MENU_REL_Y)"
      case "$s0" in claimed|unclaimed) POPUP_CONFIRMED_OPEN=1;; esac
    fi
  fi

  if [ "$s0" = "none" ]; then
    # 重试: 先点头像重新打开菜单, 再点 Buddy 加油站
    click_cg "$ax" "$ay"; sleep 1.0
    click_cg "$ecx" "$ecy"; sleep 1.3
    capture "$popup"; s0="$(popup_state "$popup")"
    log "重试打开卡片后状态: $s0"
    case "$s0" in claimed|unclaimed) POPUP_CONFIRMED_OPEN=1;; esac
  fi

  if [ "$s0" = "claimed" ]; then
    log "弹框显示今日已领取, 无需重复操作"
    log "=== 签到完成(今日已领) ==="; return 0
  fi

  # 2c) 初始已领判定: 按钮区灰度偏亮 => 已是浅色"今日已领"(今日已签到)
  b0=$(btn_brightness "$popup")
  if awk "BEGIN{exit !($b0 > $BTN_BRIGHT_TH)}"; then
    log "按钮区亮度=$b0 (>阈值$BTN_BRIGHT_TH) => 已为浅色'今日已领', 今日已签到"
    log "=== 签到完成(今日已领) ==="; return 0
  fi

  # 3) 领取: 点击"立即领取"按钮
  click_cg "$bcx" "$bcy"; sleep 1.5
  after="$SNAPSHOT_DIR/after_$(ts).png"; capture "$after"
  s1="$(popup_state "$after")"
  b1=$(btn_brightness "$after")
  log "领取后状态: $s1  按钮亮度 点击前=$b0 点击后=$b1"
  case "$s1" in claimed|unclaimed) POPUP_CONFIRMED_OPEN=1;; esac

  # 成功: OCR 命中已领取 / 按钮明显变浅(深->浅, 领取成功) / 开了又关
  if [ "$s1" = "claimed" ] \
     || awk "BEGIN{exit !($b1 - $b0 > $BTN_BRIGHT_DELTA)}" \
     || { [ "$s0" = "unclaimed" ] && [ "$s1" = "none" ]; }; then
    log "=== 签到完成(已领取) ==="; return 0
  fi

  # 4) 重试一次
  click_cg "$bcx" "$bcy"; sleep 1.5
  capture "$after"; s2="$(popup_state "$after")"
  b2=$(btn_brightness "$after")
  log "重试后状态: $s2  按钮亮度=$b2"
  case "$s2" in claimed|unclaimed) POPUP_CONFIRMED_OPEN=1;; esac

  if [ "$s2" = "claimed" ] || awk "BEGIN{exit !($b2 - $b0 > $BTN_BRIGHT_DELTA)}"; then
    log "=== 签到完成(已领取) ==="; return 0
  fi
  if [ "$s2" = "none" ]; then
    if [ "$POPUP_CONFIRMED_OPEN" -eq 1 ]; then
      log "=== 签到完成(已领取/弹框已关闭) ==="; return 0
    fi
    log "WARN: 弹框未打开, 点击疑似未生效, 签到可能未执行"
    log "      请人工确认 Buddy 加油站/立即领取 偏移, 或改用 WorkBuddy 定时任务(继承完整辅助功能权限)."
    log "=== 签到失败(弹框未打开) ==="
    return 1
  fi

  log "WARN: 点击领取后未确认成功(状态=$s2), 请查看截图人工确认: $after"
  log "=== 签到失败(未确认领取) ==="
  return 1
}

# ---------- 校准子命令 ----------
calibrate_entry() {
  load_offsets; discover_window; resolve_offsets
  echo "[calibrate] 确保鼠标已悬停在 WorkBuddy 左侧\"Buddy 加油站\"菜单上, 然后运行本命令(免回车)."
  local cur ax ay
  cur=$("$WB_CLICK" -w)
  ax=$(echo "$cur" | cut -d',' -f1)
  ay=$(echo "$cur" | cut -d',' -f2)
  MENU_REL_X=$((ax-WIN_X)); MENU_REL_Y=$((ay-WIN_Y))
  if [ "$MENU_REL_X" -lt 0 ] || [ "$MENU_REL_Y" -lt 0 ] || [ "$MENU_REL_X" -gt "$WIN_W" ] || [ "$MENU_REL_Y" -gt "$WIN_H" ]; then
    echo "WARN: 光标相对窗口($MENU_REL_X,$MENU_REL_Y)超出窗口范围, 请把鼠标移到窗口内头像上再运行"
    return 1
  fi
  MENU_NX=$(awk "BEGIN{printf \"%.4f\", $MENU_REL_X/$WIN_W}")
  MENU_NY=$(awk "BEGIN{printf \"%.4f\", $MENU_REL_Y/$WIN_H}")
  save_offsets
  echo "Buddy 加油站入口校准完成: 归一化($MENU_NX,$MENU_NY) 相对偏移($MENU_REL_X,$MENU_REL_Y) -> 当前窗口 CG($ax,$ay)"
}
calibrate_button() {
  load_offsets; discover_window; resolve_offsets
  echo "请先点击左侧\"Buddy 加油站\"打开签到卡片, 把鼠标悬停在'立即领取'按钮上, 然后运行本命令(免回车)."
  local cur bx by
  cur=$("$WB_CLICK" -w)
  bx=$(echo "$cur" | cut -d',' -f1)
  by=$(echo "$cur" | cut -d',' -f2)
  BTN_REL_X=$((bx-WIN_X)); BTN_REL_Y=$((by-WIN_Y))
  if [ "$BTN_REL_X" -lt 0 ] || [ "$BTN_REL_Y" -lt 0 ] || [ "$BTN_REL_X" -gt "$WIN_W" ] || [ "$BTN_REL_Y" -gt "$WIN_H" ]; then
    echo "WARN: 光标相对窗口($BTN_REL_X,$BTN_REL_Y)超出窗口范围, 请把鼠标移到弹框内按钮上再运行"
    return 1
  fi
  BTN_NX=$(awk "BEGIN{printf \"%.4f\", $BTN_REL_X/$WIN_W}")
  BTN_NY=$(awk "BEGIN{printf \"%.4f\", $BTN_REL_Y/$WIN_H}")
  save_offsets
  echo "按钮校准完成: 归一化($BTN_NX,$BTN_NY) 相对偏移($BTN_REL_X,$BTN_REL_Y) -> 当前窗口 CG($bx,$by)"
}

# ---------- 诊断子命令 ----------
debug_mode() {
  load_offsets; activate_workbuddy; sleep 0.8; discover_window; resolve_offsets; migrate_legacy
  echo "窗口矩形: ${WIN_X}|${WIN_Y}|${WIN_W}|${WIN_H}  SCALE=$SCALE"
  echo "归一化坐标: AVATAR($AVATAR_NX,$AVATAR_NY) MENU($MENU_NX,$MENU_NY) BTN($BTN_NX,$BTN_NY)"
  echo "Buddy加油站 相对偏移: ($MENU_REL_X,$MENU_REL_Y) -> CG($(($WIN_X+$MENU_REL_X)),$(($WIN_Y+$MENU_REL_Y)))"
  echo "按钮相对偏移: ($BTN_REL_X,$BTN_REL_Y) -> CG($(($WIN_X+$BTN_REL_X)),$(($WIN_Y+$BTN_REL_Y)))"
  local img="$SNAPSHOT_DIR/debug_$(ts).png"; capture "$img"
  echo "截图: $img"
  echo "弹框按钮状态: $(popup_state "$img")"
  echo "按钮区亮度: $(btn_brightness "$img")  (阈值 已领>$BTN_BRIGHT_TH, 领取增量>$BTN_BRIGHT_DELTA)"
}

# ---------- 自动探测"Buddy 加油站"菜单热区(自适应当前窗口) ----------
# 返回 0 命中并写回 offsets(NX/NY+REL), 返回 1 未命中.
auto_probe_menu() {
  load_offsets; discover_window; resolve_offsets
  # 建立关闭基线, 供 popup_state 差分判定卡片是否打开
  local base="$SNAPSHOT_DIR/probe_base_$(ts).png"; capture "$base"; POPUP_BASELINE="$base"
  local rx ry ax ay shot st hit=""
  # 扫描左侧"Buddy 加油站"菜单所在区域 (x: 0..200 CSS, y: 300..360 CSS)
  local xs=(20 60 100 140 180) ys=(300 315 330 345 360)
  diag "[probe] 窗口矩形 ${WIN_X}|${WIN_Y}|${WIN_W}|${WIN_H}; 扫描左侧 Buddy 加油站 网格..."
  for ry in "${ys[@]}"; do
    for rx in "${xs[@]}"; do
      # 先点标题栏空白关闭可能已开的卡片
      click_cg $((WIN_X+WIN_W/2)) $((WIN_Y+30)); sleep 0.4
      ax=$((WIN_X+rx)); ay=$((WIN_Y+ry))
      click_cg "$ax" "$ay"; sleep 1.3
      shot="$SNAPSHOT_DIR/probe_$(ts).png"; capture "$shot"
      st="$(popup_state "$shot")"
      diag "probe 窗口相对($rx,$ry) -> $st"
      if [ "$st" != "none" ]; then
        hit=1; MENU_REL_X=$rx; MENU_REL_Y=$ry
        MENU_NX=$(awk "BEGIN{printf \"%.4f\", $rx/$WIN_W}")
        MENU_NY=$(awk "BEGIN{printf \"%.4f\", $ry/$WIN_H}")
        save_offsets
        click_cg $((WIN_X+WIN_W/2)) $((WIN_Y+30)); sleep 0.4   # 关卡片
        break 2
      fi
    done
  done
  [ -n "$hit" ]
}

probe_avatar() {
  if auto_probe_menu; then
    echo ">>> 命中 Buddy 加油站 热区: 归一化($MENU_NX,$MENU_NY) 相对($MENU_REL_X,$MENU_REL_Y), 已写入 .wbcheckin.offsets"
  else
    echo "未找到 Buddy 加油站 热区. 可能: (a) 手动 bash 缺辅助功能权限导致点击无效; (b) 菜单在网格外. 建议改用 WorkBuddy 定时任务运行, 或 where-entry 人工校准."
  fi
}

# ---------- 入口 ----------
case "${1:-}" in
  debug)       debug_mode ;;
  where-entry) calibrate_entry ;;
  where)       calibrate_button ;;
  probe)       probe_avatar ;;
  once|"")      main ;;
  *) echo "用法: bash $0 [debug|where-entry|where|probe|once]"; exit 2 ;;
esac
