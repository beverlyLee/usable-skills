#!/usr/bin/env bash
# =============================================================================
# Trae Work CN 每日签到助手
# -----------------------------------------------------------------------------
# 思路: macOS 桌面自动化 = AppleScript(激活+定位窗口) + screencapture(区域截图)
#       + wbclick(CoreGraphics 绝对坐标点击) + 图像差分/OCR 判定.
#
# 流程:
#   1. 激活 Trae Work CN 窗口.
#   2. 点击左下角用户名/头像, 打开用户菜单.
#   3. 在用户菜单内寻找"每日签到领200积分"按钮:
#      - 若存在则点击, 完成签到.
#      - 若显示"今日已签"则跳过.
#   4. 通过 OCR / 状态变化确认签到成功.
#
# 坐标空间: AppleScript 窗口 position 与 wbclick 同为 CoreGraphics「事件坐标」
#   (原点主屏左上, y 向下, 跨多屏, 负坐标=副屏), 无需 y 翻转.
#
# ★ 关键: 坐标一律存「相对窗口原点的偏移」, 窗口移动/换屏/缩放后仍稳定.
#
# 用法:
#   bash trae-work-cn-checkin.sh            # 执行一次签到
#   bash trae-work-cn-checkin.sh debug      # 诊断: 打印窗口/坐标/菜单状态, 不点击
#   bash trae-work-cn-checkin.sh windows    # 列出所有候选 Trae 窗口(bundle/名称/标题/rect)
#   bash trae-work-cn-checkin.sh where-entry# 校准入口: 鼠标悬停左下角用户名上, 然后运行
#   bash trae-work-cn-checkin.sh where      # 校准按钮: 打开用户菜单, 鼠标悬停右侧"签到"/"今日已签"胶囊上, 然后运行
#   bash trae-work-cn-checkin.sh reset      # 清除校准偏移, 恢复默认比例
#
# ⚠️ 严格模式: 只有"确认已签到(claimed)"或"菜单确实打开且成功点击"才返回 0.
#    若菜单未打开或状态未确认, 返回 1, 绝不说谎成功.
# =============================================================================

set -uo pipefail

# ---------- 路径 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT_DIR="$SCRIPT_DIR/snapshot"
OFFSETS_FILE="$SCRIPT_DIR/.traecheckin.offsets"
WB_CLICK="$SCRIPT_DIR/wbclick"
WININFO="$SCRIPT_DIR/winfo"      # CoreGraphics Window Server 枚举工具(输出坐标与 wbclick 同源)
LOG_FILE="$SCRIPT_DIR/checkin.log"
mkdir -p "$SNAPSHOT_DIR"

# ---------- 应用配置 ----------
# 目标应用: Trae Work CN (务必区别于 "Trae Solo CN" / "Trae CN", 避免误开!)
# ⚠️ 严格约束: 本脚本只操作标题含 "Work CN" 的窗口, 绝不激活/触碰 "Trae Solo CN".
#   因此 activate_trae() 不再按 bundle 猜测(旧版会误激活 cn.trae.solo.app), 改为按窗口标题匹配。
BUNDLE_IDS=("cn.trae.work.app" "cn.trae.app" "cn.trae.solo.app")
APP_BUNDLE=""
# 窗口标题/owner 命中此关键字才视为目标(用于 winfo/pick 过滤), 精准排除 "Trae CN"
TARGET_HINT="Work CN"

# ---------- 窗口默认(仅在探测失败时作为初始占位, 不会用于点击) ----------
WIN_X=100; WIN_Y=100; WIN_W=1400; WIN_H=900
WIN_ID=""                       # CoreGraphics windowID, 用于 -l 精确截图(避免抓到桌面)
SCALE=2

# ---------- 弹框/菜单状态判定 ----------
POPUP_BASELINE=""        # 菜单关闭基线截图路径
DIFF_OPEN_TH=0.015       # 左下区域差分均值(归一 0..1) > 此值 => 菜单已打开

# ---------- 归一化坐标(相对窗口宽高比例 NX/NY) ----------
# 首次部署需通过 where-entry / where 校准; 校准前用以下默认猜测值.
DEF_AVATAR_NX=0.0450; DEF_AVATAR_NY=0.9500  # 左下角用户名/头像 (左缘, 近底边)
DEF_BTN_NX=0.1000;    DEF_BTN_NY=0.7600     # 用户菜单内"每日签到"按钮
AVATAR_NX=$DEF_AVATAR_NX; AVATAR_NY=$DEF_AVATAR_NY
BTN_NX=$DEF_BTN_NX;         BTN_NY=$DEF_BTN_NY
AVATAR_REL_X=""; AVATAR_REL_Y=""; BTN_REL_X=""; BTN_REL_Y=""  # 运行时现算, 不持久化

# ---------- 工具函数 ----------
ts()   { date +%Y%m%d_%H%M%S; }
log()  { local t; t=$(date '+%Y-%m-%d %H:%M:%S'); echo "[$t] $*" | tee -a "$LOG_FILE"; }
diag() { local t; t=$(date '+%Y-%m-%d %H:%M:%S'); echo "[$t] $*" | tee -a "$LOG_FILE" >&2; }

# 主显示器尺寸(点坐标): 返回 "w|h"
main_display_size() {
  local out; out=$("$WB_CLICK" -d 2>/dev/null)
  [ -z "$out" ] && return
  local w h
  w=$(echo "$out" | awk '{print $1}')
  h=$(echo "$out" | awk '{print $2}')
  echo "${w}|${h}"
}

# 判断矩形是否"几乎等同于整块显示器"(真正的全屏伪窗口).
# 仅当 尺寸与显示器几乎相等 且 锚定在屏幕原点 时判定为 1.
# 注意: Trae 即使最大化也只是接近整屏(留边距/菜单栏), 不会被误判.
is_screen_like_rect() {
  local x="$1" y="$2" w="$3" h="$4"
  local ds; ds=$(main_display_size)
  [ -z "$ds" ] && { echo 0; return; }
  local sw=${ds%|*}; local sh=${ds#*|}
  awk -v x="$x" -v y="$y" -v w="$w" -v h="$h" -v sw="$sw" -v sh="$sh" 'BEGIN{
    if (sw<=0 || sh<=0) { print 0; exit }
    tol = 4
    if (w >= sw - tol && h >= sh - tol && x <= tol && y <= tol) print 1
    else print 0
  }'
}

# ★ 唯一可信源: 归一化比例 NX/NY (0..1, 相对窗口宽高).
#   像素偏移永远由 NX/NY * 当前窗口尺寸 现算, 不持久化, 因此窗口移动/缩放/换屏均稳定.
#   这一节只认 NX/NY, 忽略任何遗留的 *_REL_* 像素键.
load_offsets() {
  [ -f "$OFFSETS_FILE" ] || return 0
  local k v
  while IFS='=' read -r k v; do
    [ -z "${k:-}" ] && continue
    case "$k" in
      AVATAR_NX) AVATAR_NX="$v" ;; AVATAR_NY) AVATAR_NY="$v" ;;
      BTN_NX)    BTN_NX="$v"    ;; BTN_NY)    BTN_NY="$v"    ;;
    esac
  done < "$OFFSETS_FILE"
}

# 永远按当前窗口尺寸把比例换算成像素偏移 (相对窗口原点).
resolve_offsets() {
  AVATAR_REL_X=$(awk "BEGIN{printf \"%d\", $AVATAR_NX*$WIN_W}")
  AVATAR_REL_Y=$(awk "BEGIN{printf \"%d\", $AVATAR_NY*$WIN_H}")
  BTN_REL_X=$(awk "BEGIN{printf \"%d\", $BTN_NX*$WIN_W}")
  BTN_REL_Y=$(awk "BEGIN{printf \"%d\", $BTN_NY*$WIN_H}")
}

save_offsets() {
  resolve_offsets
  cat > "$OFFSETS_FILE" <<EOF
# Trae Work CN 签到助手校准偏移 (v2: 纯归一化比例, 自适应窗口移动/缩放)
# 运行时: 像素偏移 = NX*WIN_W (或 NY*WIN_H), 绝对 CG = 窗口原点 + 像素偏移.
# AVATAR = 左下角用户名/头像入口; BTN = 用户菜单内"每日签到"按钮.
AVATAR_NX=$AVATAR_NX
AVATAR_NY=$AVATAR_NY
BTN_NX=$BTN_NX
BTN_NY=$BTN_NY
EOF
  log "已保存校准偏移到 $OFFSETS_FILE (纯比例, 像素偏移运行时现算)"
}

# 判断某个 bundle 是否是已知 Trae
is_known_trae_bundle() {
  local bid="$1"
  local b
  for b in "${BUNDLE_IDS[@]}"; do
    [ "$b" = "$bid" ] && return 0
  done
  return 1
}

# 查询当前 frontmost 进程的 bundle id
frontmost_bundle() {
  osascript -e '
    tell application "System Events"
      try
        set p to first application process whose frontmost is true
        return bundle identifier of p
      on error
        return ""
      end try
    end tell' 2>/dev/null
}

# 校验 Trae 是否已经是当前最前应用
is_trae_frontmost() {
  local bid; bid=$(frontmost_bundle)
  [ -n "$bid" ] && is_known_trae_bundle "$bid"
}

# 等待 Trae 成为最前应用, 超时返回 1
ensure_trae_frontmost() {
  local max_wait="${1:-6}"
  local i
  for i in $(seq 1 $((max_wait*2))); do
    if is_trae_frontmost; then
      diag "Trae 已位于最前"
      return 0
    fi
    sleep 0.5
  done
  return 1
}

# 仅操作 Trae Work CN, 绝不触碰 Trae Solo CN / 其它变体.
# 通过窗口标题匹配 "Work CN" 定位进程并置前, 完全不依赖 bundle id 猜测,
# 因此不会误激活 "Trae Solo CN" (旧版按 bundle 循环会误命中 cn.trae.solo.app).
activate_trae() {
  local raised
  # 关键: 不要先把 windows of p 存到变量里; System Events 在跨进程迭代时,
  # 把窗口引用存到变量后会导致后续读取 title 等属性为空或串到前台应用.
  # 直接迭代 (repeat with w in (windows of p)) 才能稳定读到 Trae 窗口标题.
  raised=$(osascript -e '
    tell application "System Events"
      repeat with p in (processes whose background only is false)
        try
          repeat with w in (windows of p)
            try
              set t to (title of w) as string
            on error
              set t to ""
            end try
            if t contains "Work CN" then
              set frontmost of p to true
              try
                perform action "AXRaise" of w
              end try
              return "raised:" & (name of p)
            end if
          end repeat
        on error
          -- 某些进程无法枚举窗口, 继续下一个
        end try
      end repeat
    end tell
    return ""' 2>/dev/null)
  if [ -n "$raised" ]; then
    APP_BUNDLE="$raised"
    log "已置前 Trae Work CN 窗口: $raised"
  else
    log "WARN: 未找到标题含 'Work CN' 的窗口, 跳过置前(仍按窗口坐标点击, 由状态校验判定)."
  fi
  return 0
}

# 返回所有候选 Trae 窗口, 每行 "bundle|name|title|x|y|w|h"
list_trae_windows() {
  osascript -e '
    set knownBundles to {"cn.trae.solo.app", "cn.trae.app", "com.trae.app"}
    set out to ""
    tell application "System Events"
      repeat with p in (processes whose background only is false)
        try
          set bid to bundle identifier of p
        on error
          set bid to ""
        end try
        if bid is in knownBundles then
          set pn to name of p
          repeat with w in (windows of p)
            try
              set t to title of w
            on error
              set t to "(no title)"
            end try
            try
              set pos to position of w
              set sz to size of w
              set out to out & bid & "|" & pn & "|" & t & "|" & (item 1 of pos as text) & "|" & (item 2 of pos as text) & "|" & (item 1 of sz as text) & "|" & (item 2 of sz as text) & "\n"
            end try
          end repeat
        end if
      end repeat
    end tell
    return out' 2>/dev/null
}

# 从候选窗口列表中挑一个真实窗口: 硬性优先 "Trae Work CN", 否则取面积最大的.
# 关键: 排除 "Trae CN" / Trae 国际版等其它变体, 绝不选错应用.
pick_window() {
  list_trae_windows | awk -F'|' '
    ($6+0) < 50 || ($7+0) < 50 { next }   # 跳过退化窗口
    tolower($3) ~ /solo/ { next }          # 硬性排除 Trae Solo CN, 绝不选中
    {
      area = ($6+0) * ($7+0)
      title = tolower($3)
      score = area
      # 第一优先: 标题含 "work cn" / "trae work" -> Trae Work CN
      if (title ~ /work cn|trae work/) score += 1e15
      # 次选: 含 trae(仍可能被 "Trae CN" 命中, 仅在无 Work CN 时回退)
      else if (title ~ /trae/) score += 1e12
      if (score > best) { best = score; line = $0 }
    }
    END { if (best > 0) print line }'
}

# 通过 CoreGraphics Window Server 枚举 Trae Work CN 窗口, 每行: windowID|x|y|w|h|owner|title
# 先用 TARGET_HINT("Work CN") 精确过滤; 若空则退化为全部窗口, 由 winfo_pick 按 Work CN 优先挑选.
winfo_trae_windows() {
  [ -x "$WININFO" ] || return 0
  local out
  out=$("$WININFO" "$TARGET_HINT" 2>/dev/null)
  if [ -z "$out" ]; then
    out=$("$WININFO" 2>/dev/null)
  fi
  echo "$out"
}

# 从一批 winfo 行中挑一个真实 Trae Work CN 窗口: 硬性优先 "Work CN", 否则面积最大.
# 关键: 排除 "Trae CN" / Trae 国际版等其它变体.
winfo_pick() {
  # 只接受明确含 "Work CN" / "Trae Work" 的窗口, 不再用松散的 "trae" 关键词回退,
  # 否则 iTerm2/Terminal 等窗口标题里的 "trae-work-cn-checkin" 会被误中.
  awk -F'|' '
    ($4+0) < 50 || ($5+0) < 50 { next }
    tolower($6) ~ /solo/ || tolower($7) ~ /solo/ { next }   # 硬性排除 Trae Solo CN
    {
      area = ($4+0) * ($5+0)
      lo6 = tolower($6); lo7 = tolower($7)
      # 唯一判定: owner/title 明确含 "work cn" / "trae work" -> Trae Work CN
      if (lo6 ~ /work cn|trae work/ || lo7 ~ /work cn|trae work/) {
        score = area + 1e15
        if (score > best) { best = score; line = $0 }
      }
    }
    END { if (best > 0) print line }'
}

# 根据窗口矩形(来自 System Events)在全量 winfo 列表中回查 windowID, 容差 8px.
# 用途: System Events 兜底发现窗口时也能拿到 windowID, 让 capture() 走稳固的 -l 截图.
winfo_find_id_by_rect() {
  [ -x "$WININFO" ] || return 0
  local tx=$1 ty=$2 tw=$3 th=$4
  "$WININFO" 2>/dev/null | awk -F'|' -v tx="$tx" -v ty="$ty" -v tw="$tw" -v th="$th" '
    ($4+0) < 50 || ($5+0) < 50 { next }
    {
      dx = ($2+0) - tx; dy = ($3+0) - ty; dw = ($4+0) - tw; dh = ($5+0) - th;
      if (dx*dx + dy*dy + dw*dw + dh*dh <= 64) { print $1; exit }
    }'
}

discover_window() {
  local line rx ry rw rh wid i
  # 优先从环境变量读取(调试用)
  if [ -n "${TRAECHECKIN_WIN_RECT:-}" ]; then
    WIN_X=$(echo "$TRAECHECKIN_WIN_RECT" | cut -d'|' -f1)
    WIN_Y=$(echo "$TRAECHECKIN_WIN_RECT" | cut -d'|' -f2)
    WIN_W=$(echo "$TRAECHECKIN_WIN_RECT" | cut -d'|' -f3)
    WIN_H=$(echo "$TRAECHECKIN_WIN_RECT" | cut -d'|' -f4)
    WIN_ID=""
    log "使用环境变量窗口矩形: ${WIN_X}|${WIN_Y}|${WIN_W}|${WIN_H}"
    return 0
  fi

  # 首选: CoreGraphics Window Server(坐标与 wbclick 同源, 且可拿到 windowID 用于 -l 精确截图)
  if [ -x "$WININFO" ]; then
    for i in $(seq 1 8); do
      line="$(winfo_trae_windows | winfo_pick)"
      if [ -n "$line" ]; then
        wid=$(echo "$line" | cut -d'|' -f1)
        rx=$(echo "$line" | cut -d'|' -f2)
        ry=$(echo "$line" | cut -d'|' -f3)
        rw=$(echo "$line" | cut -d'|' -f4)
        rh=$(echo "$line" | cut -d'|' -f5)
        if [ "$rw" -lt 50 ] || [ "$rh" -lt 50 ]; then
          diag "WARN: winfo 探测到退化窗口 ${wid}|${rx}|${ry}|${rw}|${rh}, 忽略并继续探测"
          sleep 0.6
          continue
        fi
        WIN_ID=$wid; WIN_X=$rx; WIN_Y=$ry; WIN_W=$rw; WIN_H=$rh
        log "通过 CoreGraphics 发现 Trae 窗口(windowID=$WIN_ID): ${WIN_X}|${WIN_Y}|${WIN_W}|${WIN_H}"
        return 0
      fi
      sleep 0.6
    done
    log "WARN: winfo 未直接命中 Trae 窗口, 回退到 System Events 探测..."
  fi

  # 回退: System Events(无 windowID, 截图将退化为区域截图)
  for i in $(seq 1 8); do
    line="$(pick_window)"
    if [ -n "$line" ]; then
      rx=$(echo "$line" | cut -d'|' -f4)
      ry=$(echo "$line" | cut -d'|' -f5)
      rw=$(echo "$line" | cut -d'|' -f6)
      rh=$(echo "$line" | cut -d'|' -f7)
      if [ "$rw" -lt 50 ] || [ "$rh" -lt 50 ]; then
        diag "WARN: 探测到退化窗口 ${rx}|${ry}|${rw}|${rh}, 忽略并继续探测"
        sleep 0.6
        continue
      fi
      WIN_X=$rx; WIN_Y=$ry; WIN_W=$rw; WIN_H=$rh
      WIN_ID="$(winfo_find_id_by_rect "$WIN_X" "$WIN_Y" "$WIN_W" "$WIN_H")"
      if [ -n "$WIN_ID" ]; then
        log "发现 Trae 窗口(System Events + 回查 windowID=$WIN_ID): ${WIN_X}|${WIN_Y}|${WIN_W}|${WIN_H}"
      else
        log "发现 Trae 窗口(System Events, 无 windowID, 截图退化为区域): ${WIN_X}|${WIN_Y}|${WIN_W}|${WIN_H}"
      fi
      return 0
    fi
    sleep 0.6
  done
  log "ERROR: 窗口矩形自动发现失败, 无法安全定位点击坐标. 请确认:"
  log "  1. Trae 应用正在运行且窗口可见;"
  log "  2. WorkBuddy/终端 已授予 辅助功能 和 屏幕录制 权限;"
  log "  3. 当前目标为 Trae Work CN(显示名 TRAE SOLO CN / Trae Work CN);"
  log "  4. 或设置环境变量 TRAECHECKIN_WIN_RECT=x|y|w|h."
  log "候选 Trae 窗口列表(CoreGraphics):"
  winfo_trae_windows | sed 's/^/  /' | tee -a "$LOG_FILE"
  log "候选 Trae 窗口列表(System Events):"
  list_trae_windows | sed 's/^/  /' | tee -a "$LOG_FILE"
  return 1
}

capture() {
  local out="$1"
  if [ -n "${WIN_ID:-}" ]; then
    # 按 windowID 精确截图(去除窗口阴影): 直接抓取 Trae 窗口内容, 不受屏幕合成/前置渲染影响.
    # 内容原点即窗口左上, 与归一化坐标体系一致.
    screencapture -x -o -l "$WIN_ID" "$out" 2>/dev/null
  else
    # 回退: 区域截图(仅在无 windowID 时使用)
    screencapture -x -R "${WIN_X},${WIN_Y},${WIN_W},${WIN_H}" "$out" 2>/dev/null
  fi
  local iw; iw=$(sips -g pixelWidth "$out" 2>/dev/null | awk -F': ' '/pixelWidth/{print $2}')
  if [ -n "${iw:-}" ] && [ "$iw" -gt 0 ] && [ "$WIN_W" -gt 0 ]; then
    SCALE=$(awk -v iw="$iw" -v w="$WIN_W" 'BEGIN{ if(w==0){print 1; exit} s=iw/w; if(s<1)s=1; printf "%.0f", s }')
  fi
  [ "$SCALE" -lt 1 ] && SCALE=1
}

click_cg() { "$WB_CLICK" "$1" "$2"; }

# 菜单弹框状态判定: 图像差分(是否打开) + OCR("今日已签" / "每日签到").
# 返回: claimed | unclaimed | none
#   claimed:  已签到(今日已签)
#   unclaimed: 未签到, 存在每日签到按钮
#   none:     菜单未打开
popup_state() {
  local img="$1"
  [ -f "$img" ] || { echo none; return; }

  # 0) 左侧菜单区域 OCR: 命中"今日已签/已签到/已签" -> claimed
  local menu_crop ocr_text
  menu_crop=$(mktemp "$SNAPSHOT_DIR/trae_menu.XXXXXX.png")
  # 用户菜单从窗口左下角头像向上展开, 签到行在菜单上半部分.
  # 裁剪左侧 500px、顶部 80% 区域, 确保覆盖签到行(文字在左, 胶囊在右).
  local mw=$((500*SCALE)) mh=$(( (WIN_H * 4 / 5) * SCALE )) mx=0 my=0
  convert "$img" -crop "${mw}x${mh}+${mx}+${my}" +repage "$menu_crop" 2>/dev/null
  if [ -s "$menu_crop" ]; then
    # 放大+锐化提升小字/灰底标签识别率
    local pre="${menu_crop}.pre.png"
    convert "$menu_crop" -resize 200% -sharpen 0x1.0 "$pre" 2>/dev/null || cp "$menu_crop" "$pre"
    ocr_text=$(env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy tesseract "$pre" stdout --psm 6 -l chi_sim+eng 2>/dev/null)
    rm -f "$pre"
    if echo "$ocr_text" | grep -qE "今日已签|已签到|已签"; then
      rm -f "$menu_crop"
      diag "popup_state: 菜单 OCR 命中已签关键词 -> claimed"
      echo claimed; return
    fi
    if echo "$ocr_text" | grep -qE "每日签到|领.*积分|签到"; then
      rm -f "$menu_crop"
      diag "popup_state: 菜单 OCR 命中签到关键词 -> unclaimed"
      echo unclaimed; return
    fi
  fi
  rm -f "$menu_crop"

  # 1) 菜单是否打开: 左侧区域差分(菜单覆盖左半边)
  local pop_open=0
  if [ -n "${POPUP_BASELINE:-}" ] && [ -f "$POPUP_BASELINE" ]; then
    local cw=$((500*SCALE)) ch=$(( (WIN_H * 4 / 5) * SCALE )) coy=0
    local base_crop cur_crop dmean dmax dnorm
    base_crop=$(mktemp -t trae_base.XXXXXX.png)
    cur_crop=$(mktemp -t trae_cur.XXXXXX.png)
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

  # 弹框已打开但未命中 OCR 关键词 -> 视为 unclaimed(保守: 尝试点击)
  diag "popup_state: 菜单已打开, 未命中已签关键词 -> unclaimed"
  echo unclaimed; return
}

# ---------- 主流程 ----------
main() {
  load_offsets
  log "=== Trae Work CN 签到开始 ==="
  activate_trae
  if ! ensure_trae_frontmost 8; then
    # 不硬失败: 截图用 -l windowID 抓取, 不受前置影响; 点击坐标按真实窗口位置计算,
    # 后续 before/after 状态校验会捕获真正的失败. 这样定时任务不会因"非最前"直接放弃.
    log "WARN: 未能确认 Trae 已置前(frontmost=$(frontmost_bundle)), 仍尝试点击, 由状态校验判定成败."
  else
    diag "Trae 已位于最前"
  fi
  sleep 0.5
  discover_window || { log "=== 签到失败(无法定位窗口) ==="; return 1; }
  resolve_offsets
  log "窗口矩形: ${WIN_X}|${WIN_Y}|${WIN_W}|${WIN_H}  windowID=${WIN_ID:-无}  SCALE=$SCALE"
  log "归一化坐标: AVATAR($AVATAR_NX,$AVATAR_NY) BTN($BTN_NX,$BTN_NY)"
  log "解析后相对偏移: AVATAR($AVATAR_REL_X,$AVATAR_REL_Y) BTN($BTN_REL_X,$BTN_REL_Y)"

  local ax ay bcx bcy before popup s0 after s1 POPUP_CONFIRMED_OPEN=0
  ax=$((WIN_X+AVATAR_REL_X)); ay=$((WIN_Y+AVATAR_REL_Y))
  bcx=$((WIN_X+BTN_REL_X));   bcy=$((WIN_Y+BTN_REL_Y))
  log "用户名点击 CG=($ax,$ay)"
  log "签到按钮点击 CG=($bcx,$bcy)"

  before="$SNAPSHOT_DIR/before_$(ts).png"; capture "$before"
  log "点击前截图: $before"
  POPUP_BASELINE="$before"

  # 0) 若菜单已打开且显示已签, 直接成功
  local s_baseline
  s_baseline="$(popup_state "$before")"
  log "初始菜单状态: $s_baseline"
  if [ "$s_baseline" = "claimed" ]; then
    log "菜单已打开且显示已签, 无需重复操作"
    log "=== 签到完成(今日已签) ==="; return 0
  fi

  # 1) 打开用户菜单: 点击左下角用户名/头像
  click_cg "$ax" "$ay"; sleep 1.2

  popup="$SNAPSHOT_DIR/popup_$(ts).png"; capture "$popup"
  s0="$(popup_state "$popup")"
  log "菜单状态(点击用户名后): $s0"
  case "$s0" in claimed|unclaimed) POPUP_CONFIRMED_OPEN=1;; esac

  if [ "$s0" = "claimed" ]; then
    log "菜单显示今日已签, 无需重复操作"
    log "=== 签到完成(今日已签) ==="; return 0
  fi

  if [ "$s0" = "none" ]; then
    # 重试一次
    log "WARN: 菜单未打开, 重试..."
    click_cg "$ax" "$ay"; sleep 1.2
    capture "$popup"; s0="$(popup_state "$popup")"
    log "重试后菜单状态: $s0"
    case "$s0" in claimed|unclaimed) POPUP_CONFIRMED_OPEN=1;; esac
  fi

  if [ "$s0" = "none" ]; then
    log "WARN: 菜单始终未打开, 请校准左下角用户名入口偏移"
    log "=== 签到失败(菜单未打开) ==="
    return 1
  fi

  # 2) 点击签到按钮
  click_cg "$bcx" "$bcy"; sleep 1.5
  after="$SNAPSHOT_DIR/after_$(ts).png"; capture "$after"
  s1="$(popup_state "$after")"
  log "点击签到按钮后状态: $s1"
  case "$s1" in claimed|unclaimed) POPUP_CONFIRMED_OPEN=1;; esac

  if [ "$s1" = "claimed" ]; then
    log "=== 签到完成(已签到) ==="; return 0
  fi

  if [ "$s1" = "none" ] && [ "$POPUP_CONFIRMED_OPEN" -eq 1 ]; then
    # 菜单从 unclaimed 变为关闭, 可能签到成功弹窗出现或菜单消失
    log "=== 签到完成(菜单关闭, 疑似成功) ==="; return 0
  fi

  # 3) 重试一次
  log "首次点击未确认成功, 重试..."
  click_cg "$bcx" "$bcy"; sleep 1.5
  capture "$after"; s1="$(popup_state "$after")"
  log "重试后状态: $s1"
  if [ "$s1" = "claimed" ] || { [ "$s1" = "none" ] && [ "$POPUP_CONFIRMED_OPEN" -eq 1 ]; }; then
    log "=== 签到完成(已签到) ==="; return 0
  fi

  log "WARN: 点击签到后未确认成功, 请查看截图人工确认: $after"
  log "=== 签到失败(未确认签到) ==="
  return 1
}

# ---------- 校准子命令 ----------
calibrate_entry() {
  load_offsets; discover_window || { echo "ERROR: 无法发现 Trae 窗口, 校准中止"; return 1; }; resolve_offsets
  echo "[calibrate] 确保鼠标已悬停在 Trae 左下角用户名/头像上, 然后运行本命令(免回车)."
  local cur ax ay
  cur=$("$WB_CLICK" -w)
  ax=$(echo "$cur" | cut -d',' -f1)
  ay=$(echo "$cur" | cut -d',' -f2)
  AVATAR_REL_X=$((ax-WIN_X)); AVATAR_REL_Y=$((ay-WIN_Y))
  if [ "$AVATAR_REL_X" -lt 0 ] || [ "$AVATAR_REL_Y" -lt 0 ] || [ "$AVATAR_REL_X" -gt "$WIN_W" ] || [ "$AVATAR_REL_Y" -gt "$WIN_H" ]; then
    echo "WARN: 光标相对窗口($AVATAR_REL_X,$AVATAR_REL_Y)超出窗口范围, 请把鼠标移到窗口内用户名上再运行"
    return 1
  fi
  AVATAR_NX=$(awk "BEGIN{printf \"%.4f\", $AVATAR_REL_X/$WIN_W}")
  AVATAR_NY=$(awk "BEGIN{printf \"%.4f\", $AVATAR_REL_Y/$WIN_H}")
  save_offsets
  echo "用户名入口校准完成: 归一化($AVATAR_NX,$AVATAR_NY) 相对偏移($AVATAR_REL_X,$AVATAR_REL_Y) -> 当前窗口 CG($ax,$ay)"
}

calibrate_button() {
  load_offsets; discover_window || { echo "ERROR: 无法发现 Trae 窗口, 校准中止"; return 1; }; resolve_offsets
  echo "请先点击左下角用户名打开用户菜单, 把鼠标悬停在右侧'签到'胶囊按钮(或'今日已签'灰标)上, 然后运行本命令(免回车)."
  local cur bx by
  cur=$("$WB_CLICK" -w)
  bx=$(echo "$cur" | cut -d',' -f1)
  by=$(echo "$cur" | cut -d',' -f2)
  BTN_REL_X=$((bx-WIN_X)); BTN_REL_Y=$((by-WIN_Y))
  if [ "$BTN_REL_X" -lt 0 ] || [ "$BTN_REL_Y" -lt 0 ] || [ "$BTN_REL_X" -gt "$WIN_W" ] || [ "$BTN_REL_Y" -gt "$WIN_H" ]; then
    echo "WARN: 光标相对窗口($BTN_REL_X,$BTN_REL_Y)超出窗口范围, 请把鼠标移到弹窗内按钮上再运行"
    return 1
  fi
  BTN_NX=$(awk "BEGIN{printf \"%.4f\", $BTN_REL_X/$WIN_W}")
  BTN_NY=$(awk "BEGIN{printf \"%.4f\", $BTN_REL_Y/$WIN_H}")
  save_offsets
  echo "签到按钮校准完成: 归一化($BTN_NX,$BTN_NY) 相对偏移($BTN_REL_X,$BTN_REL_Y) -> 当前窗口 CG($bx,$by)"
}

# ---------- 诊断子命令 ----------
debug_mode() {
  load_offsets; activate_trae
  sleep 0.5
  if ! discover_window; then
    echo ""
    echo "候选 Trae 窗口列表(CoreGraphics):"
    winfo_trae_windows | sed 's/^/  /'
    echo "候选 Trae 窗口列表(System Events):"
    list_trae_windows | sed 's/^/  /'
    return 1
  fi
  resolve_offsets
  echo "窗口矩形: ${WIN_X}|${WIN_Y}|${WIN_W}|${WIN_H}  windowID=${WIN_ID:-无}  SCALE=$SCALE"
  echo "归一化坐标: AVATAR($AVATAR_NX,$AVATAR_NY) BTN($BTN_NX,$BTN_NY)"
  echo "用户名入口相对偏移: ($AVATAR_REL_X,$AVATAR_REL_Y) -> CG($(($WIN_X+$AVATAR_REL_X)),$(($WIN_Y+$AVATAR_REL_Y)))"
  echo "签到按钮相对偏移: ($BTN_REL_X,$BTN_REL_Y) -> CG($(($WIN_X+$BTN_REL_X)),$(($WIN_Y+$BTN_REL_Y)))"
  # 截图: 使用 -l windowID 抓取, 不依赖 Trae 是否置前(窗口内容直接来自 Window Server).
  local img="$SNAPSHOT_DIR/debug_$(ts).png"; capture "$img"
  echo "截图: $img"
  if is_trae_frontmost; then
    echo "[OK] Trae 已位于最前, 点击将命中窗口本体."
  else
    echo "[WARN] Trae 当前非最前(frontmost=$(frontmost_bundle)); 截图已是窗口本体(-l 抓取, 不受前置影响), 但真实点击需 Trae 置前. 在 iTerm 中运行可获得完整点击流程."
  fi
  POPUP_BASELINE="$img"
  echo "菜单状态: $(popup_state "$img")"
}

list_windows_mode() {
  echo "主显示器尺寸(点): $(main_display_size)"
  if [ -x "$WININFO" ]; then
    echo "候选 Trae 窗口(CoreGraphics, windowID|x|y|w|h|owner|title):"
    winfo_trae_windows | sed 's/^/  /'
  fi
  echo "候选 Trae 窗口(System Events, bundle|name|title|x|y|w|h):"
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local rx ry rw rh
    rx=$(echo "$line" | cut -d'|' -f4)
    ry=$(echo "$line" | cut -d'|' -f5)
    rw=$(echo "$line" | cut -d'|' -f6)
    rh=$(echo "$line" | cut -d'|' -f7)
    local flag=""
    [ "$(is_screen_like_rect "$rx" "$ry" "$rw" "$rh")" -eq 1 ] && flag=" [SCREEN-LIKE-IGNORED]"
    echo "  $line$flag"
  done < <(list_trae_windows)
}

reset_offsets() {
  rm -f "$OFFSETS_FILE"
  echo "已清除校准偏移 $OFFSETS_FILE, 下次将使用内置默认比例."
}

# ---------- 入口 ----------
case "${1:-}" in
  debug)       debug_mode ;;
  windows)     list_windows_mode ;;
  where-entry) calibrate_entry ;;
  where)       calibrate_button ;;
  reset)       reset_offsets ;;
  once|"")      main ;;
  *) echo "用法: bash $0 [debug|windows|where-entry|where|reset|once]"; exit 2 ;;
esac
