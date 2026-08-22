# 画风 DNA · 净白淡彩

> 一句话定调：**净白底 + 清晰棕线 + 淡彩上色 + 深棕红锚点。**
> 基于小桃 IP 参考图程序化实测校准（2026-08-21，v2）。

## 实测色板锚点（来自 IP 参考图，生成时必须贴近）

| 色值 | 实测占比 | 用途 |
|---|---|---|
| `#FFFFFF` 净白 | ~48% | 背景主体，像贴纸底板一样干净的白 |
| `#F6F4E5` / `#E6DACF` 奶油/暖米 | ~15% | 次级底色、纸感区块 |
| `#CB9A90` 玫瑰粉 | ~11% | 肤色腮红、毛衣、粉色系主体 |
| `#6F3531` 深棕红 | ~9% | **深色锚点**：头发、深色标注、贴纸文字 |
| 近白系杂色 | 其余 | 高光、留白过渡 |

## 画风规则表

| 维度 | 规则 |
|---|---|
| **画法定性** | 淡彩插画（light-tinted illustration）：净白底上浅色淡彩，颜色浅但**明确存在**；不是重晕染水彩，不是 washed-out |
| **底色/背景** | 大面积净白 `#FFFFFF`（可局部极淡暖白），大量留白，主体占画面 40-60% |
| **线条** | 清晰的棕色轮廓线（**不是纯黑，也不是晕染糊线**）：细、干净、利落，线端可轻微柔化；主体边缘必须读得清楚 |
| **上色** | 浅涂淡彩，色块干净均匀，可有轻微水彩质感但**不模糊不泛滥**；不要重晕染、不要厚涂、不要 3D |
| **色彩浓度** | 低饱和高明度，但必须有一个深色锚点（`#6F3531` 深棕红：头发 + 少量深色元素）撑住画面分量——没有深色锚点整图会苍白漂浮 |
| **主色调** | 白、奶油、玫瑰粉、淡桃、浅棕 |
| **点缀色** | 少量淡蓝/淡紫阴影、淡绿（桃叶）、极少量红色强调 |
| **装饰元素** | **极简原则：默认不加漂浮贴纸小图标**（桃子/小猫/代码标签/TODO 框等一律不画，除非用户明确要求）。画面的全部视觉注意力留给主体和隐喻结构；简约、重点明确、一眼看懂 |
| **文字** | 少量手写体标注（字体方案见 prompt-template.md），棕色或深棕红，短词为主；代码片段用等宽感字体 |
| **质感关键词** | 干净、明亮、淡彩、清晰、透气、简约、主体突出、重点明确 |
| **禁忌** | 纯黑轮廓线、重水彩晕染糊边、整图苍白无深色、高饱和撞色、暗黑风、3D 渲染、米白奶油铺满全图、满版塞满、幼齿感、甜腻少女风、**漂浮贴纸小图标喧宾夺主** |

## 生图 prompt 中的风格锁定段（逐字复用，不要增删改）

```text
Clean light-tinted illustration style: bright and airy, low saturation
but colors clearly present, NOT washed out, NOT heavy watercolor.
Dominant pure white background (#FFFFFF, like a clean sticker sheet),
with small warm cream zones (#F6F4E5, #E6DACF), plenty of white space,
main subject occupies 40-60% of frame.
Crisp thin warm-brown outlines, gently softened line ends — clean ink-line
quality, NOT blurry, NOT watercolor bloom.
Soft flat fills with a light watercolor tint touch; light hand, no heavy washes.
Exact palette anchors (match closely): white #FFFFFF background,
cream #F6F4E5, warm beige #E6DACF, dusty rose #CB9A90 (blush, sweater,
pink objects), deep warm brown-red #6F3531 (hair color and dark accents).
The dark value anchor #6F3531 must be clearly present (hair + a few small
dark details) so the pale palette has visual weight.
Small accents of pale blue/lavender shadows and light green leaves allowed.
Relaxed, precise, tech-themed mood like a programmer's clean sketchbook page.
MINIMALIST composition: single clear focal point, the subject and its
metaphor structure carry all visual attention.
NO floating decorative stickers, NO doodle icons, NO peaches or cats
scattered around, NO code tags or TODO boxes unless explicitly requested —
clean empty space around the subject.
Chinese labels in handwriting style, rendered later with bundled font
(see font strategy) — keep label areas simple and uncluttered.
```

## 与参考项目「小黑」的气质差异

| 维度 | 小黑 | 小桃 |
|---|---|---|
| 情绪 | 空表情、荒诞 | 轻松微笑、淡定从容 |
| 隐喻风格 | 低科技怪诞物理装置 | 编程/技术日常的严谨轻松隐喻 |
| 能量感 | 荒诞劳作 | 松弛但精准 |
| 装饰语言 | 纯手绘物件 | 手账+代码贴纸 |

## 风格高发漂移（生成后重点检查）

- 整图苍白、没有深色 → 重申 dark value anchor #6F3531 must be present（头发深棕红）
- 线条晕染模糊 → 重申 crisp thin warm-brown outlines, NOT blurry, NOT bloom
- 颜色越画越浓、饱和度升高 → 重申 low saturation but colors clearly present
- 背景铺满米白奶油 → 重申 dominant pure white background #FFFFFF
- 轮廓线变黑 → 重申 warm-brown outlines
- 主体撑满画面 → 重申 plenty of white space, 40-60%
- 贴纸装饰泛滥 → 重申 NO floating decorative stickers（极简原则：默认零贴纸）
