/*
 * wbclick — 零依赖的 macOS 坐标点击工具 (WorkBuddy 签到助手配套)
 * ----------------------------------------------------------------
 * 用 CoreGraphics 在屏幕绝对坐标处执行一次左键点击。
 * 不依赖 cliclick / brew, 仅链接系统框架, 可随项目分发。
 *
 * 用法:
 *   wbclick <x> <y>          在 (x,y) 处点击一次
 *   wbclick -m <x> <y>       仅移动光标到 (x,y), 不点击 (校准用)
 *   wbclick -w               打印当前光标屏幕绝对坐标 "x,y" (校准用)
 *   wbclick -s               打印主显示器高度 (Quartz 坐标系, 用于坐标换算)
 *   wbclick -d               打印主显示器尺寸 "w h" (事件坐标空间, 点)
 *   wbclick -h               显示帮助
 *
 * 坐标说明: 本工具使用 CoreGraphics「事件坐标」空间, 原点在「主显示器左上角」, y 轴向下,
 *           与 AppleScript 的窗口 position 完全相同 (同一全局坐标系, 跨多屏)。
 *           => 脚本侧无需做任何 y 翻转, 直接把 AppleScript 读到的窗口坐标传给本工具即可。
 *           (注意: CGDisplayBounds 的显示器矩形才是「原点左下 y 向上」, 但鼠标事件/AppleScript
 *            用的是上面的「事件坐标」空间, 二者不要混淆。)
 *
 * 前置: 运行此工具的进程需已授权 macOS「辅助功能」权限。
 * 编译: clang -O2 -framework CoreGraphics -framework CoreFoundation -o wbclick wbclick.c
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CGDirectDisplay.h>

static void usage(const char *prog) {
    fprintf(stderr,
        "用法:\n"
        "  %s <x> <y>       在屏幕绝对坐标 (x,y) 处左键点击一次\n"
        "  %s -m <x> <y>    仅移动光标到 (x,y), 不点击 (校准用)\n"
        "  %s -w            打印当前光标屏幕绝对坐标 \"x,y\" (校准用)\n"
        "  %s -s            打印主显示器高度 (Quartz 坐标, 用于坐标换算)\n"
        "  %s -d            打印主显示器尺寸 \"w h\" (点)\n"
        "  %s -h            显示此帮助\n",
        prog, prog, prog, prog, prog, prog);
}

/* 打印主显示器高度 (Quartz 坐标系, 原点左下, y 向上) */
static int print_main_screen_height(void) {
    CGRect b = CGDisplayBounds(CGMainDisplayID());
    printf("%d\n", (int)b.size.height);
    return 0;
}

/* 打印主显示器尺寸 w h (事件坐标空间用点, 仅尺寸) */
static int print_main_display_size(void) {
    CGRect b = CGDisplayBounds(CGMainDisplayID());
    printf("%d %d\n", (int)b.size.width, (int)b.size.height);
    return 0;
}

/* 读取当前光标屏幕绝对坐标, 输出 "x,y" 到 stdout */
static int print_cursor_position(void) {
    CGEventRef ev = CGEventCreate(NULL);
    CGPoint loc = CGEventGetLocation(ev);
    CFRelease(ev);
    printf("%d,%d\n", (int)loc.x, (int)loc.y);
    return 0;
}

int main(int argc, char **argv) {
    int move_only = 0;
    int argi = 1;

    /* 只把 -m/-w/-s/-d/-h 当选项; 负数坐标(如 -386)不能误解析为选项. */
    if (argc >= 2 && argv[1][0] == '-' && argv[1][1] != '\0' &&
        (argv[1][1] == 'm' || argv[1][1] == 'w' || argv[1][1] == 's' || argv[1][1] == 'd' || argv[1][1] == 'h') &&
        argv[1][2] == '\0') {
        if (argv[1][1] == 'h') { usage(argv[0]); return 0; }
        if (argv[1][1] == 'w') { return print_cursor_position(); }
        if (argv[1][1] == 's') { return print_main_screen_height(); }
        if (argv[1][1] == 'd') { return print_main_display_size(); }
        if (argv[1][1] == 'm') { move_only = 1; argi = 2; }
    }

    if (argc - argi < 2) { usage(argv[0]); return 2; }

    int x = atoi(argv[argi]);
    int y = atoi(argv[argi + 1]);
    CGPoint pt = CGPointMake((CGFloat)x, (CGFloat)y);

    CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, pt, kCGMouseButtonLeft);
    CGEventRef up   = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp,   pt, kCGMouseButtonLeft);

    if (move_only) {
        /* 仅移动光标, 不按下任何键 */
        CGEventRef move = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, pt, kCGMouseButtonLeft);
        CGEventPost(kCGHIDEventTap, move);
        CFRelease(move);
        fprintf(stderr, "moved cursor to (%d,%d)\n", x, y);
    } else {
        CGEventPost(kCGHIDEventTap, down);
        /* 短暂按下间隔, 模拟真实点击 */
        usleep(50000);
        CGEventPost(kCGHIDEventTap, up);
        fprintf(stderr, "clicked at (%d,%d)\n", x, y);
    }

    CFRelease(down);
    CFRelease(up);
    return 0;
}
