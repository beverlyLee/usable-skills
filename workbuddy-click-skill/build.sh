#!/usr/bin/env bash
# =============================================================================
# build.sh — 编译 wbclick (WorkBuddy 签到助手配套坐标点击工具)
# -----------------------------------------------------------------------------
# wbclick 的二进制在不同 macOS 机型/架构(x86_64 / arm64)上并不通用,
# 拿到新机器请重新编译(需要 macOS 命令行工具 clang, 通常随 Xcode CLT 自带).
#   xcode-select --install   # 若尚未安装 clang
# =============================================================================
set -euo pipefail

# 进入 scripts/ 目录(wbclick.c / 产物 wbclick 都在那里)
cd "$(dirname "${BASH_SOURCE[0]}")/scripts"

# 优先用隔离的 managed 运行时里的 clang(若存在), 否则回退系统 clang
CLANG_BIN="$(command -v clang || true)"
if [ -z "$CLANG_BIN" ]; then
  echo "ERROR: 未找到 clang, 请先运行  xcode-select --install" >&2
  exit 1
fi

echo ">>> 使用编译器: $CLANG_BIN"
echo ">>> 编译 wbclick.c ..."
"$CLANG_BIN" -O2 -framework CoreGraphics -framework CoreFoundation -o wbclick wbclick.c

echo ">>> 完成: $(pwd)/wbclick"
"$CLANG_BIN" --version | head -1
file wbclick 2>/dev/null || true
