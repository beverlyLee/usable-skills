/*
 * winfo.c - 通过 CoreGraphics Window Server 枚举屏幕上的窗口, 输出核心坐标系下的窗口矩形.
 *
 * 坐标空间: kCGWindowBounds 返回的 CGRect 与 CoreGraphics 事件坐标(CGWarpMouseCursorPosition /
 *   CGEvent) 完全一致, 原点为主屏左上, y 向下, 跨多屏(副屏可为负坐标). 这与 screencapture -l
 *   以及本项目的 wbclick 点击工具处于同一坐标系, 因此可作为唯一可信源, 消除 System Events
 *   position 与 CoreGraphics 之间的坐标空间偏差.
 *
 * 用法:
 *   winfo              列出所有屏幕上的普通窗口
 *   winfo <filter>     仅列出 owner 名称或 bundle 含 filter(不区分大小写) 的窗口
 *
 * 每行输出: windowID|x|y|w|h|ownerName|windowTitle
 */
#include <stdio.h>
#include <string.h>
#include <ApplicationServices/ApplicationServices.h>

static int ci_strstr(const char *hay, const char *needle) {
    if (!hay || !needle) return 0;
    size_t hl = strlen(hay), nl = strlen(needle);
    if (nl == 0) return 1;
    if (hl < nl) return 0;
    for (size_t i = 0; i + nl <= hl; i++) {
        size_t j;
        for (j = 0; j < nl; j++) {
            char a = hay[i + j]; if (a >= 'A' && a <= 'Z') a += 32;
            char b = needle[j];  if (b >= 'A' && b <= 'Z') b += 32;
            if (a != b) break;
        }
        if (j == nl) return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    const char *filter = (argc > 1) ? argv[1] : NULL;

    CFArrayRef wins = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    if (!wins) return 1;

    CFIndex n = CFArrayGetCount(wins);
    for (CFIndex i = 0; i < n; i++) {
        CFDictionaryRef d = CFArrayGetValueAtIndex(wins, i);

        CFNumberRef layer = CFDictionaryGetValue(d, kCGWindowLayer);
        int l = -1;
        if (layer) CFNumberGetValue(layer, kCFNumberIntType, &l);
        if (l != 0) continue; /* 仅普通层级窗口 */

        char oname[512] = {0};
        CFStringRef owner = CFDictionaryGetValue(d, kCGWindowOwnerName);
        if (owner) CFStringGetCString(owner, oname, sizeof(oname), kCFStringEncodingUTF8);

        char tname[1024] = {0};
        CFStringRef title = CFDictionaryGetValue(d, kCGWindowName);
        if (title) CFStringGetCString(title, tname, sizeof(tname), kCFStringEncodingUTF8);

        if (filter) {
            if (!ci_strstr(oname, filter) && !ci_strstr(tname, filter)) continue;
        }

        int wid = 0;
        CFNumberRef winid = CFDictionaryGetValue(d, kCGWindowNumber);
        if (winid) CFNumberGetValue(winid, kCFNumberIntType, &wid);

        CGRect r = CGRectZero;
        CFDictionaryRef bounds = CFDictionaryGetValue(d, kCGWindowBounds);
        if (bounds) CGRectMakeWithDictionaryRepresentation(bounds, &r);

        printf("%d|%.0f|%.0f|%.0f|%.0f|%s|%s\n",
               wid, r.origin.x, r.origin.y, r.size.width, r.size.height, oname, tname);
    }
    CFRelease(wins);
    return 0;
}
