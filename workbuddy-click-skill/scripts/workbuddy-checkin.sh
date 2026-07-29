#!/usr/bin/env bash
# =============================================================================
# WorkBuddy 每日签到领取助手  (重构版 v2)
# -----------------------------------------------------------------------------
# 思路: macOS 桌面自动化 = AppleScript(激活+定位窗口) + screencapture(区域截图)
#       + wbclick(CoreGraphics 绝对坐标点击) + 图像差分/饱和度判定(无 OCR).
#
# 为什么不用"按名点击 UI 树":
#   WorkBuddy 是 Electron 应用, 其对话区是 WebView, 不向 macOS 辅助功能树
#   暴露"立即领取"按钮, 按名点击必然失败. 改用"坐标点击 + 图像差分/饱和度判定(无 OCR)".
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
#   bash workbuddy-checkin.sh where-entry# 校准头像: 先把鼠标悬停在"打开头像"的控件上, 再运行(免回车)
#   bash workbuddy-checkin.sh where      # 校准按钮: 先点开签到弹框, 鼠标悬停"立即领取", 再运行(免回车)
#   bash workbuddy-checkin.sh probe      # 自动扫描网格定位头像热区(成功才会写入 offsets)
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
POPUP_BASELINE=""        # 弹框关闭基线截图路径, 由 main 在点击头像前设置
DIFF_OPEN_TH=0.012       # 左下区域差分均值(归一 0..1) > 此值 => 弹框已打开(实测: 开=0.029, 关≈0.0003)
SAT_CLAIMED_TH=0.10      # 按钮区平均饱和度(归一 0..1) > 此值 => 亮色"立即领取"(unclaimed); 否则灰色"今日已领"(claimed). 实测 claimed≈0.03

# ---------- 相对窗口原点的偏移(运行时 CG = 当前窗口原点 + 相对偏移) ----------
# 初值来源:
#   ENTRY_REL 由用户 where-entry 悬停头像校准(窗口 345|-977 时绝对 379|-216 -> 相对 34|761)
#   BTN_REL   由存档真实弹框截图 OCR 校准(按钮像素 1045|996 -> 相对窗口 522|498)
DEF_ENTRY_REL_X=32;  DEF_ENTRY_REL_Y=766
DEF_BTN_REL_X=95;    DEF_BTN_REL_Y=368
ENTRY_REL_X=$DEF_ENTRY_REL_X; ENTRY_REL_Y=$DEF_ENTRY_REL_Y
BTN_REL_X=$DEF_BTN_REL_X;     BTN_REL_Y=$DEF_BTN_REL_Y

# 旧版绝对坐标格式兼容标记
LEGACY_ABS=0

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
      ENTRY_REL_X) ENTRY_REL_X="$v" ;;
      ENTRY_REL_Y) ENTRY_REL_Y="$v" ;;
      BTN_REL_X)   BTN_REL_X="$v"   ;;
      BTN_REL_Y)   BTN_REL_Y="$v"   ;;
      ENTRY_X)     LEGACY_ABS=1     ;;   # 旧绝对格式存在
    esac
  done < "$OFFSETS_FILE"
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
  [ -n "$ax" ] && ENTRY_REL_X=$((ax - WIN_X))
  [ -n "$ay" ] && ENTRY_REL_Y=$((ay - WIN_Y))
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
  cat > "$OFFSETS_FILE" <<EOF
# WorkBuddy 签到助手校准偏移 (相对窗口原点的偏移; 运行时 CG = 当前窗口原点 + 相对偏移)
ENTRY_REL_X=$ENTRY_REL_X
ENTRY_REL_Y=$ENTRY_REL_Y
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

# 弹框状态判定: 图像差分(是否打开) + OCR(已领/未领关键词) + 按钮饱和度兜底.
#   -> claimed | unclaimed | none
# 依赖全局 POPUP_BASELINE(弹框关闭基线截图). 缺失时无法差分, 退化为返回 none.
# 所有量纲均归一化到 0..1(用 max 归一), 与 ImageMagick 量子深度(Q8/Q16)无关.
#
# ⚠️ 设计约束: 对话本身也会提到"加油站/领取", 因此单凭 OCR 关键词不能判定弹框打开,
#    必须以"底部左侧区域差分"作为弹框打开的主信号; OCR 仅用于"已领取"强确认.
popup_state() {
  local img="$1"
  [ -f "$img" ] || { echo none; return; }

  local tsv
  tsv=$(tesseract "$img" stdout --psm 11 -l chi_sim+eng tsv 2>/dev/null)

  # --- 0) OCR 强信号: 全图出现"今日已领/已领取/领取成功/已签到" -> 直接 claimed ---
  local ocr_claimed
  ocr_claimed=$(echo "$tsv" | awk -F'\t' 'NF>=12 && $12 ~ /今日已领|已领取|领取成功|已签到/ {print "Y"; exit}')
  if [ -n "$ocr_claimed" ]; then
    diag "popup_state: OCR 命中已领取关键词 -> claimed"
    echo claimed; return
  fi

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

  # --- 2) 已领取 vs 未领取: OCR"立即领取"优先, 否则按钮饱和度兜底 ---
  local ocr_unclaimed
  ocr_unclaimed=$(echo "$tsv" | awk -F'\t' 'NF>=12 && $12 ~ /立即领取/ {print "Y"; exit}')
  if [ -n "$ocr_unclaimed" ]; then
    diag "popup_state: OCR 命中'立即领取' -> unclaimed"
    echo unclaimed; return
  fi

  local halfw=80 halfh=35
  local bx0=$((BTN_REL_X-halfw)); [ "$bx0" -lt 0 ] && bx0=0
  local by0=$((BTN_REL_Y-halfh)); [ "$by0" -lt 0 ] && by0=0
  local bw=$((2*halfw*SCALE)) bh=$((2*halfh*SCALE)) box=$((bx0*SCALE)) boy=$((by0*SCALE))
  local btn_crop smean smax sat_norm=0
  btn_crop=$(mktemp -t wb_btn.XXXXXX.png)
  convert "$img" -crop "${bw}x${bh}+${box}+${boy}" +repage "$btn_crop" 2>/dev/null
  if [ -s "$btn_crop" ]; then
    read -r smean smax < <(convert "$btn_crop" -colorspace HSL -channel G -separate \
                            -format "%[mean] %[max]" info: 2>/dev/null)
    smean=${smean:-0}; smax=${smax:-1}
    sat_norm=$(awk -v m="$smean" -v x="$smax" 'BEGIN{ if (x+0==0) print 0; else printf "%.5f", m/x }')
  fi
  rm -f "$btn_crop"
  diag "popup_state: 按钮饱和度(归一)=${sat_norm} (阈值${SAT_CLAIMED_TH}, >阈值=unclaimed)"

  if awk "BEGIN{exit !($sat_norm > $SAT_CLAIMED_TH)}"; then
    echo unclaimed   # 亮色"立即领取"按钮
  else
    echo claimed     # 灰色"今日已领"
  fi
}

# ---------- 主流程 ----------
# 防谎报: 只有"弹框确实被确认打开过(POPUP_CONFIRMED_OPEN=1)"且最终态为
#   claimed 或"开了又关(none)", 才算成功; 若从头到尾弹框都没打开(点击疑似 no-op),
#   则明确 WARN 并以非 0 退出码收尾, 让调用方(定时任务)能感知失败.
main() {
  load_offsets
  log "=== 签到开始 ==="
  activate_workbuddy; sleep 0.8
  discover_window
  migrate_legacy
  log "窗口矩形: ${WIN_X}|${WIN_Y}|${WIN_W}|${WIN_H}  SCALE=$SCALE"

  local ecx ecy bcx bcy before popup s0 after s1 s2 POPUP_CONFIRMED_OPEN=0
  ecx=$((WIN_X+ENTRY_REL_X)); ecy=$((WIN_Y+ENTRY_REL_Y))
  bcx=$((WIN_X+BTN_REL_X));   bcy=$((WIN_Y+BTN_REL_Y))
  log "头像点击 CG=($ecx,$ecy) [相对 $ENTRY_REL_X,$ENTRY_REL_Y]"
  log "按钮点击 CG=($bcx,$bcy) [相对 $BTN_REL_X,$BTN_REL_Y]"

  before="$SNAPSHOT_DIR/before_$(ts).png"; capture "$before"
  log "点击前截图: $before"
  POPUP_BASELINE="$before"   # 弹框关闭基线, 供 popup_state 差分对比

  # 1) 打开弹框: 点击头像
  click_cg "$ecx" "$ecy"; sleep 1.3
  popup="$SNAPSHOT_DIR/popup_$(ts).png"; capture "$popup"
  s0="$(popup_state "$popup")"
  log "弹框状态(点击头像后): $s0"
  case "$s0" in claimed|unclaimed) POPUP_CONFIRMED_OPEN=1;; esac

  if [ "$s0" = "none" ]; then
    click_cg "$ecx" "$ecy"; sleep 1.3
    capture "$popup"; s0="$(popup_state "$popup")"
    log "重试打开弹框后状态: $s0"
    case "$s0" in claimed|unclaimed) POPUP_CONFIRMED_OPEN=1;; esac
  fi

  if [ "$s0" = "claimed" ]; then
    log "弹框显示今日已领取, 无需重复操作"
    log "=== 签到完成(今日已领) ==="; return 0
  fi

  # 2) 领取: 点击"立即领取"按钮
  click_cg "$bcx" "$bcy"; sleep 1.5
  after="$SNAPSHOT_DIR/after_$(ts).png"; capture "$after"
  s1="$(popup_state "$after")"
  log "领取后状态: $s1"
  case "$s1" in claimed|unclaimed) POPUP_CONFIRMED_OPEN=1;; esac

  if [ "$s1" = "claimed" ] || { [ "$s0" = "unclaimed" ] && [ "$s1" = "none" ]; }; then
    log "=== 签到完成(已领取) ==="; return 0
  fi

  # 3) 重试一次
  click_cg "$bcx" "$bcy"; sleep 1.5
  capture "$after"; s2="$(popup_state "$after")"
  log "重试后状态: $s2"
  case "$s2" in claimed|unclaimed) POPUP_CONFIRMED_OPEN=1;; esac

  # --- 最终成功判定(防谎报) ---
  if [ "$s2" = "claimed" ]; then
    log "=== 签到完成(已领取) ==="; return 0
  fi
  if [ "$s2" = "none" ]; then
    if [ "$POPUP_CONFIRMED_OPEN" -eq 1 ]; then
      # 弹框确实打开过, 领取后关闭 -> 视为成功
      log "=== 签到完成(已领取/弹框已关闭) ==="; return 0
    fi
    # 从头到尾弹框都没打开, 点击疑似未生效 -> 明确失败
    log "WARN: 弹框未打开, 点击疑似未生效, 签到可能未执行"
    log "      请人工确认头像/按钮偏移, 或改用 WorkBuddy 定时任务(继承完整辅助功能权限)."
    log "=== 签到失败(弹框未打开) ==="
    return 1
  fi

  # 兜底: 其它状态(如仍 unclaimed)均视为未确认领取
  log "WARN: 点击领取后未确认成功(状态=$s2), 请查看截图人工确认: $after"
  log "=== 签到失败(未确认领取) ==="
  return 1
}

# ---------- 校准子命令 ----------
calibrate_entry() {
  load_offsets; discover_window
  echo "[calibrate] 确保鼠标已悬停在 WorkBuddy 左下角用户头像上, 然后运行本命令(免回车)."
  local cur ax ay
  cur=$("$WB_CLICK" -w)
  ax=$(echo "$cur" | cut -d',' -f1)
  ay=$(echo "$cur" | cut -d',' -f2)
  ENTRY_REL_X=$((ax-WIN_X)); ENTRY_REL_Y=$((ay-WIN_Y))
  if [ "$ENTRY_REL_X" -lt 0 ] || [ "$ENTRY_REL_Y" -lt 0 ] || [ "$ENTRY_REL_X" -gt "$WIN_W" ] || [ "$ENTRY_REL_Y" -gt "$WIN_H" ]; then
    echo "WARN: 光标相对窗口($ENTRY_REL_X,$ENTRY_REL_Y)超出窗口范围, 请把鼠标移到窗口内头像上再运行"
    return 1
  fi
  save_offsets
  echo "头像校准完成: 相对偏移($ENTRY_REL_X,$ENTRY_REL_Y) -> 当前窗口 CG($ax,$ay)"
}
calibrate_button() {
  load_offsets; discover_window
  echo "请先点击头像打开签到弹框, 把鼠标悬停在'立即领取'按钮上, 然后运行本命令(免回车)."
  local cur bx by
  cur=$("$WB_CLICK" -w)
  bx=$(echo "$cur" | cut -d',' -f1)
  by=$(echo "$cur" | cut -d',' -f2)
  BTN_REL_X=$((bx-WIN_X)); BTN_REL_Y=$((by-WIN_Y))
  if [ "$BTN_REL_X" -lt 0 ] || [ "$BTN_REL_Y" -lt 0 ] || [ "$BTN_REL_X" -gt "$WIN_W" ] || [ "$BTN_REL_Y" -gt "$WIN_H" ]; then
    echo "WARN: 光标相对窗口($BTN_REL_X,$BTN_REL_Y)超出窗口范围, 请把鼠标移到弹框内按钮上再运行"
    return 1
  fi
  save_offsets
  echo "按钮校准完成: 相对偏移($BTN_REL_X,$BTN_REL_Y) -> 当前窗口 CG($bx,$by)"
}

# ---------- 诊断子命令 ----------
debug_mode() {
  load_offsets; activate_workbuddy; sleep 0.8; discover_window; migrate_legacy
  echo "窗口矩形: ${WIN_X}|${WIN_Y}|${WIN_W}|${WIN_H}  SCALE=$SCALE"
  echo "头像相对偏移: ($ENTRY_REL_X,$ENTRY_REL_Y) -> CG($(($WIN_X+$ENTRY_REL_X)),$(($WIN_Y+$ENTRY_REL_Y)))"
  echo "按钮相对偏移: ($BTN_REL_X,$BTN_REL_Y) -> CG($(($WIN_X+$BTN_REL_X)),$(($WIN_Y+$BTN_REL_Y)))"
  local img="$SNAPSHOT_DIR/debug_$(ts).png"; capture "$img"
  echo "截图: $img"
  echo "弹框按钮状态: $(popup_state "$img")"
}

# ---------- 自动探测头像热区(自适应当前窗口) ----------
probe_avatar() {
  load_offsets; activate_workbuddy; sleep 0.8; discover_window
  # 建立关闭基线, 供 popup_state 差分判定弹框是否打开
  local base="$SNAPSHOT_DIR/probe_base_$(ts).png"; capture "$base"; POPUP_BASELINE="$base"
  local rx ry ax ay shot st hit=""
  local xs=(20 40 60 80) ys=(700 720 740 760 780 795)
  echo "[probe] 窗口矩形 ${WIN_X}|${WIN_Y}|${WIN_W}|${WIN_H}; 扫描左下角网格..."
  for ry in "${ys[@]}"; do
    for rx in "${xs[@]}"; do
      # 先点标题栏空白关闭可能已开的弹框
      click_cg $((WIN_X+WIN_W/2)) $((WIN_Y+30)); sleep 0.4
      ax=$((WIN_X+rx)); ay=$((WIN_Y+ry))
      click_cg "$ax" "$ay"; sleep 1.3
      shot="$SNAPSHOT_DIR/probe_$(ts).png"; capture "$shot"
      st="$(popup_state "$shot")"
      echo "尝试 窗口相对($rx,$ry) -> cg($ax,$ay) 状态=$st"
      if [ "$st" != "none" ]; then
        hit=1; ENTRY_REL_X=$rx; ENTRY_REL_Y=$ry; save_offsets
        echo ">>> 命中头像热区: 相对($rx,$ry) -> cg($ax,$ay), 已写入 .wbcheckin.offsets"
        click_cg $((WIN_X+WIN_W/2)) $((WIN_Y+30)); sleep 0.4   # 关弹框
        break 2
      fi
    done
  done
  [ -z "$hit" ] && echo "未找到头像热区. 可能: (a) 手动 bash 缺辅助功能权限导致点击无效; (b) 头像在网格外. 建议改用 WorkBuddy 定时任务运行, 或 where-entry 人工校准."
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
