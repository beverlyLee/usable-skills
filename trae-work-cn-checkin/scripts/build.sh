#!/usr/bin/env bash
# build.sh — 编译 Trae Work CN 签到助手的两个零依赖 macOS 工具.
#
#   wbclick : CoreGraphics 屏幕绝对坐标点击/移动/读光标 (辅助功能权限)
#   winfo   : CoreGraphics Window Server 枚举窗口, 输出 windowID|x|y|w|h|owner|title
#
# 前置: macOS + 命令行开发者工具(clang). 通常已随 Xcode CLT 安装.
#   xcode-select --install    # 若 clang 不存在
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "[build] 编译 wbclick ..."
clang -O2 -framework CoreGraphics -framework CoreFoundation -o wbclick wbclick.c

echo "[build] 编译 winfo ..."
clang -O2 -framework ApplicationServices -framework CoreFoundation -o winfo winfo.c

echo "[build] 完成 -> $(pwd)/wbclick, $(pwd)/winfo"
"$DIR/wbclick" -d >/dev/null 2>&1 && echo "[build] wbclick 自检通过(主显示器尺寸可读)" || echo "[build] WARN: wbclick 运行需 辅助功能 权限"
