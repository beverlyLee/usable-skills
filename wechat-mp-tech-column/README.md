# wechat-mp-tech-column · 微信公众号技术专栏写作 skill

> 给一个框架/技术内容，直接产出可发布的**公众号深度长文 / 合集连载**。在核心方法 `viral-tech-explainer` 之上叠加公众号调性/规则/人群。偏深度、有观点、逻辑分段、排版讲究、系列合集。

## 能力概览

- **输入**：框架名 + 真反常识点 + 3–5 应用场景（决策者/架构师视角）+ 2–3 竞品 + 封面意象。
- **输出**：`wechat-<主题>-1.md`（标题 15–25 字 + 摘要 blockquote + 开头 300 字张力 + 总分总 3000–8000 字）+ 原理图（mermaid 转 PNG）+ `wechat-<主题>-1-paste.html`（全内联样式零 class 粘贴版，可直接粘进编辑器）。
- **平台铁律**：公众号原生**不渲染 mermaid 源码**，图须 mmdc / Kroki 转 PNG 再嵌；粘贴版必须全内联 `style=`（class 会被整体剥离）。
- **写作铁律**（来自实战复盘，详见 SKILL.md）：事实兜底 / 去 AI 味 / 多图型（2–3 节一图）/ mermaid 验证（转 PNG 前 mmdc）/ 发布前质量门。

## 与其他两个写文章 skill 的关系

| Skill | 平台 | 图怎么处理 | 发布方式 |
|-------|------|-----------|---------|
| juejin-tech-column | 稀土掘金 | mermaid 代码块原生渲染，发布前 mmdc 验证 | 手动进 Markdown 编辑器导入（无 API） |
| **wechat-mp-tech-column**（本） | 微信公众号 | mermaid 转 PNG 再嵌（平台不渲染源码） | wenyan-cli 一键推草稿箱 |
| xhs-tech-column | 小红书 | 不写 mermaid，统一 3:4 图卡 | 手动传 7 图 + 粘贴文案（无 API） |

## 典型用法

```
用户：用 wechat-mp-tech-column 写 Harbor 系列第二篇，讲清六个核心词汇
→ 产出 wechat-harbor-2.md + 全内联 paste.html（六词权力关系图 PNG + 900×383 封面）
→ wechat-toolkit 的 publish.js 一键推草稿箱
```

## 依赖

- `viral-tech-explainer`（核心叙事引擎，必装）
- `wechat-toolkit`（发布通道：wenyan-cli + 微信 API，凭证在 `.env`）
- `humanizer-zh` / `humanize-ai-text`（去 AI 味）
- `mmdc` / Kroki（mermaid 转 PNG）
- ImageGen + ImageMagick（900×383 横版封面）
