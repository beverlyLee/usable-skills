# xhs-tech-column · 小红书技术专栏写作 skill

> 给一个框架/技术内容，直接产出可发布的**小红书图文笔记**。在核心方法 `viral-tech-explainer` 之上叠加小红书调性/规则/人群。偏图驱动、口语化、情绪化标题、保姆级干货；代码弱则转图示。

## 能力概览

- **输入**：框架名 + 一个真反常识点 + 3–5 应用场景 + 2–3 竞品 + 封面意象。
- **输出**：`xhs-<主题>-1.md`（标题 ≤20 字、首屏 ≤1000 字或图内文字全进正文）+ 7 张统一 1080×1440 配图（封面/流程/场景/对比/避坑/步骤/带走）+ `xhs-<主题>-1-publish.txt`（纯文本发布稿）。
- **平台铁律**：**图与文匹配黄金法则**——配图里所有实质文字原样进正文；正文约 1000 字处折叠，API 发布硬上限 1000 字；封面 3:4（≥1080×1440）大字 ≤15 字。
- **写作铁律**（来自实战复盘，详见 SKILL.md）：事实兜底 / 去 AI 味 / 多图型（图卡驱动，不写 mermaid）/ mermaid 在小红书弱化为图卡 / 发布前质量门。

## 与其他两个写文章 skill 的关系

| Skill | 平台 | 图怎么处理 | 发布方式 |
|-------|------|-----------|---------|
| juejin-tech-column | 稀土掘金 | mermaid 代码块原生渲染，发布前 mmdc 验证 | 手动进 Markdown 编辑器导入（无 API） |
| wechat-mp-tech-column | 微信公众号 | mermaid 转 PNG 再嵌（平台不渲染源码） | wenyan-cli 一键推草稿箱 |
| **xhs-tech-column**（本） | 小红书 | 不写 mermaid，统一 3:4 图卡 | 手动传 7 图 + 粘贴文案（无 API） |

## 典型用法

```
用户：用 xhs-tech-column 写 Harbor 一篇，类比"考试中心"，讲清它干嘛的
→ 产出 xhs-harbor-1.md + 7 张 1080×1440 图卡（封面大字"一张图搞懂 Harbor"+ 流程/场景/对比/避坑/步骤/带走）
→ 手动传图 + 粘贴 publish.txt
```

## 依赖

- `viral-tech-explainer`（核心叙事引擎，必装）
- `humanizer-zh` / `humanize-ai-text`（去 AI 味）
- ImageGen + ImageMagick + Pillow（3:4 图卡，①②③ 替代 emoji）
- `xiaohongshu-tool-v3`（仅数据洞察，不发布）/ `z-xhs-note`（仅文案 + 封面提示词）
