# juejin-tech-column · 掘金技术专栏写作 skill

> 给一个框架/技术内容，直接产出可发布的**掘金技术长文 / 专栏连载**。在核心方法 `viral-tech-explainer` 之上叠加掘金调性/规则/人群。偏实战、代码多、技术准确、含可运行示例与架构图。

## 能力概览

- **输入**：框架名 + 真反常识点（最好用源码/CLI 差异佐证）+ 3–5 应用场景 + 2–3 竞品 + 封面意象。
- **输出**：`juejin-<主题>-1.md`（标题含技术栈关键词 + 标签 3–5 + 代码先行 + 分节 + 收尾）+ 原理图（首选 mermaid 代码块）+ 可选 `.html` 展示版。
- **平台铁律**：掘金**只在「Markdown 编辑器」下渲染 mermaid**；富文本粘贴会静默丢图 + 泄漏「代码解读/复制代码」外壳。
- **写作铁律**（来自实战复盘，详见 SKILL.md）：事实兜底（不编造数据）/ 去 AI 味（humanizer-zh）/ 多图型（2–3 种图型搭配）/ mermaid 验证（mmdc 真渲染 + quadrantChart 约束）/ 发布前质量门。

## 与其他两个写文章 skill 的关系

| Skill | 平台 | 图怎么处理 | 发布方式 |
|-------|------|-----------|---------|
| **juejin-tech-column**（本） | 稀土掘金 | mermaid 代码块原生渲染，发布前 mmdc 验证 | 手动进 Markdown 编辑器导入（无 API） |
| wechat-mp-tech-column | 微信公众号 | mermaid 转 PNG 再嵌（平台不渲染源码） | wenyan-cli 一键推草稿箱 |
| xhs-tech-column | 小红书 | 不写 mermaid，统一 3:4 图卡 | 手动传 7 图 + 粘贴文案（无 API） |

## 典型用法

```
用户：用 juejin-tech-column 写 Harbor 的分层架构，反常识点"它本质是考试中心不是训练框架"
→ 产出 juejin-harbor-arch.md（代码先行 + 6 层栈 mermaid + 竞品对比 + 下篇预告）
```

## 依赖

- `viral-tech-explainer`（核心叙事引擎，必装）
- `humanizer-zh` / `humanize-ai-text`（去 AI 味）
- `mmdc`（@mermaid-js/mermaid-cli，发布前验证 mermaid 语法）
- ImageGen + ImageMagick（封面图）
