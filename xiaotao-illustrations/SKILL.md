---
name: "xiaotao-illustrations"
description: "Generates light-watercolor illustrations with fixed chibi character XiaoTao for Chinese articles. Invoke when user asks for article illustrations, 小桃, 配图, or comic-style explanatory images."
---

# 小桃配图 · XiaoTao Illustrations

把中文文章里的判断、流程、状态和隐喻，变成一张张净白淡彩、有小桃参与的 16:9 正文配图。

净白淡彩 | 小桃 IP | 编程技术隐喻 | 准确严谨又轻松 | Trae Skill

## 这个 Skill 是什么

小桃配图用来指导 AI Agent 为中文文章、帖子、博客、文档和技术内容生成正文配图。

它不是通用插画 prompt，不是 PPT 信息图模板，不是甜系萌系插画。它的核心目标是：先准确理解文章里的认知锚点，再把其中一个判断、流程、结构、状态或隐喻，变成一张有记忆点的 16:9 浅色水彩解释图。

默认视觉 IP 是"小桃"：一个 Q 版棕发、圆银框眼镜、桃子发夹的程序员女孩。小桃不是吉祥物，不是贴纸，也不是站在角落里的装饰物，而是正在认真参与系统运转的、轻松但严谨的工作者。

**构图第一原则：准确。** 隐喻必须精确对应文章的认知锚点，宁可简化，不可画错。检验标准：读者只看图和标注词、不看原文，能猜出原句意思且不会猜偏。

## 视觉风格

参见 references/style-dna.md。

一句话：净白底 + 清晰棕线 + 淡彩上色 + 深棕红发色锚点 + 手账代码贴纸感（实测色板锚点见 style-dna.md）。

## 角色 IP

参见 references/character-ip.md。

默认视觉 IP 是"小桃"：Q 版棕发圆银眼镜桃子发夹的程序员女孩，气质轻松、严谨、情绪稳定。小桃必须承担核心动作，不是装饰。

## 工作流程

1. 读取用户提供的文章/主题/Markdown/截图/代码片段
2. 提炼核心观点、认知转折、流程结构和适合视觉化的段落
3. 先输出 shot list（参见 references/prompt-template.md 的 shot list 模板）：每张图只选一个认知锚点，隐喻逻辑链写全
4. 用户确认 shot list 后，为每张图（构图拿不准时先查 assets/examples/EXAMPLES.md 里最接近的实测样例做参照）：
   a. 选构图类型（参见 references/composition-patterns.md）
   b. 发明一个编程/技术隐喻（终端、调试、架构、CI/CD、代码日常），画面结构必须与概念逻辑一一对应
   c. 让小桃承担核心动作，表情轻松/严谨
   d. 用 references/prompt-template.md 的生图模板组装 prompt：[角色锁定]+[风格锁定] 逐字复用，只填 [本图内容]
   e. 调用图像生成工具，16:9 横版，分辨率 2560×1440（图像后端最小像素限制 3686400）
   f. 按 references/qa-checklist.md 逐项自检（内容准确性优先），不通过则调整重生成
   g. 如需精确中文标注且模型直绘错字，用 assets/fonts/ 包内字体程序叠字（叠字代码示例见 references/prompt-template.md）
5. 保存最终图片到 assets/<article-slug>-illustrations/
6. 报告每张图的用途、路径和建议放置位置

## 字体说明（重要）

本 Skill 内置开源字体（assets/fonts/）：

- 霞鹜文楷（LXGW WenKai，SIL OFL）——中文手写风标注
- JetBrains Mono（SIL OFL）——代码/等宽标注

渲染文字时必须使用包内字体相对路径，禁止引用系统字体，保证任何机器上输出一致。许可证文件随包分发（assets/fonts/OFL-Licenses.md）。

## 用法示例

### 只做配图规划

```text
先不要生图。分析下面这篇文章哪里值得配图，输出 5 张左右的 shot list。
每张写清楚：放在哪段后、主题、核心意思、构图类型、小桃在做什么、标注词。
<粘贴文章>
```

### 直接生成正文配图

```text
把下面这篇文章生成 4 张小桃正文配图。
要求：16:9 横版、净白淡彩风、小桃轻松但严谨地承担核心动作。
<粘贴文章>
```

### 为单个概念生成一张图

```text
为"信任不是喊出来的，而是一块证据一块证据铺过去"生成一张小桃配图。
小桃必须承担核心动作，编程/技术场景，隐喻要准确。
```

### 技术内容配图

```text
为这段关于 debug/架构/部署/重构 的内容生成 3 张小桃配图。
小桃要轻松但精准地搞定技术问题。
```

## 参考文件

- references/style-dna.md —— 画风规则（净白淡彩，含实测色板锚点）
- references/character-ip.md —— 小桃角色设定
- references/composition-patterns.md —— 8 种构图类型（准确性优先，含图层/尺寸适配/单一角色规则）
- references/prompt-template.md —— Shot list + 生图 prompt 模板 + 字体方案
- references/qa-checklist.md —— 生成后自检清单（5 组）
- assets/examples/EXAMPLES.md —— 8 种构图实测样例索引 + 风格量化基准
- assets/fonts/ —— 内置字体（霞鹜文楷 + JetBrains Mono + 许可证）

## 注意事项

- 图片里的中文文字越短越稳定，标注词优先从原文提取原词。
- 每张图只讲一个核心结构，不要把文章做成说明书。
- 小桃必须承担核心动作；如果去掉小桃画面仍然完全成立，说明小桃太装饰了。
- AI 图像模型可能出现错字、幻觉标签、肢体畸变、风格漂移或多余标题，生成后必须按 QA 清单检查。
- 如果中文错字严重，优先减少标注词重生成，或改用包内字体程序叠字。
