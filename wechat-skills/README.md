# 微信公众号三件套 Skill 总结

> 围绕「微信公众号」内容生产与分发的一组 WorkBuddy Skill 总览。本文把三个相关 Skill——**微信公众号工具包 / 微信公众号文章发布 / Wechat Publisher**——的能力、用法与踩坑点统一梳理，方便快速选型与组合使用。

---

## 一、总览与关系

| Skill | 中文名 | 核心定位 | 运行方式 | 主要依赖 |
|---|---|---|---|---|
| `wechat-toolkit` | 微信公众号工具包 | **搜索 → 下载 → 洗稿 → 发布** 全流程 | Node 脚本 | cheerio、Google Chrome、内置 fork 版 wenyan-cli |
| `wechat-article-pro` | 微信公众号文章发布 | 联网搜热点 + 刘润风格长文 + AI 封面 + 发草稿 | 浏览器自动化 | 已登录的公众号后台 |
| `wechat-publisher` | Wechat Publisher | Markdown 一键发草稿（多主题 / 代码高亮） | wenyan-cli | `@wenyan-md/cli` |

三者怎么选：

- 想**从零写原创长文、自带 AI 封面** → `wechat-article-pro`
- 想**拿别人的文章来洗稿 / 改写再发** → `wechat-toolkit`（搜索 + 洗稿 + 发布一条龙）
- 想**自己用 Markdown 写好了，直接发草稿** → `wechat-publisher`（或 `wechat-toolkit` 的发布模块）

> 共同点：最终都落到「微信公众号草稿箱」；发布侧都依赖 `WECHAT_APP_ID` / `WECHAT_APP_SECRET` 与 **IP 白名单**。

---

## 二、wechat-toolkit（微信公众号工具包）

集成四大模块，覆盖公众号内容创作全流程：

| 模块 | 功能 | 触发词示例 |
|------|------|-----------|
| 🔍 搜索 | 按关键词搜公众号文章（搜狗微信） | "搜 XX 的公众号文章" |
| 📰 下载 | 下载正文 / 配图 / 视频（Markdown + HTML） | "下载这篇公众号文章" |
| ✍️ 洗稿 | AI 去痕 + 原创改写 | "帮我洗稿 / 改写这篇文章" |
| 📱 发布 | 发布 Markdown 到草稿箱 | "发布到公众号" |

### 关键命令

```bash
# 1. 搜索（-c 抓正文，-r 解析真实链接，-n 数量，-o 存 JSON）
node {baseDir}/scripts/search/search_wechat.js "关键词" -n 5 -c

# 2. 下载（先 --set-output 设默认路径；--no-image/--no-video 可跳过）
node {baseDir}/scripts/downloader/download.js "<文章URL>"
node {baseDir}/scripts/downloader/download.js "<文章URL>" --set-output ~/Downloads/wechat-articles

# 3. 发布
node {baseDir}/scripts/publisher/publish.js /path/to/article.md
node {baseDir}/scripts/publisher/publish_with_video.js /path/to/article.md   # 含视频必须用这个
```

### 洗稿策略（去 AI 味核心）

- **结构重组**：段落重排 / 拆合、叙事角度切换（时间线 ↔ 问题导向 ↔ 对比 ↔ 故事引入）、论据重组。
- **语言改写**：删意义膨胀句（"里程碑""深远影响"）、去虚假权威（"专家指出"→写来源或删）、去伪深度动词（"赋能""推动进程"→具体动作）、去广告语气（"卓越""极致"）。
- **AI 高频词黑名单**：赋能、闭环、生态、抓手、底层逻辑、范式、沉淀、势能。
- **收敛滥用**：破折号、加粗强调、列表模板（`**X：**…`）、Emoji 泛滥、空洞结尾（"未来可期"）。
- 自带 **21 项 AI 痕迹自检清单**，改写后逐项过一遍；成功标准：读起来像真人写的、信息密度高、结构与原文明显不同。

### 发布侧要点

- frontmatter **必须**含 `title` + `cover`，缺一不可；图片用**绝对路径**且路径**不含空格**。
- 内置 fork 版 wenyan-cli（`vendor/wenyan-cli-main`），首次发布脚本会自动安装。
- 草稿管理：`manage_draft.js get/list/count/delete/publish <MEDIA_ID>`，正式发布 `publish --wait`。
- 12 个内置主题（default / lapis / phycat / rainbow …）+ 自定义主题（aurora / newsroom / sage / ember）。

---

## 三、wechat-article-pro（微信公众号文章发布）

偏「写作 + 排版 + 发草稿」，**不洗稿、不抓取**，强调原创深度长文。

- **联网搜热点**：用 web_fetch 拉主题相关热点。
- **长文写作**：3000–5000 字，参考**刘润公众号风格**——开篇用案例 / 故事切入，引洞察，2–3 个真实案例论证，数据支撑，结尾给明确结论与行动建议；段落短、少 emoji、善用小标题。
- **AI 封面**：用公众号后台自带 AI 配图生成封面并直接上传（不走外部生图）。
- **自动排版**：合理的小标题分层与段落结构。
- **禁项**：末尾**不加任何话题标签**（如 `#xxx`），不用"欢迎在评论区分享"式结尾，不堆 emoji。

### 执行流程（浏览器自动化）

1. 搜热点 → 2. 写刘润风格长文 → 3. 打开 `https://mp.weixin.qq.com/` → 4. 新建「文章」→ 5. 填标题写正文 → 6. 点封面区选「AI 配图」生成并确认 → 7. 点「保存」入草稿箱。

> 前置：用户需**已登录**公众号后台；AI 配图等待 20–60 秒。

---

## 四、wechat-publisher（Wechat Publisher）

最轻量的「Markdown → 草稿箱」封装，基于 [wenyan-cli](https://github.com/caol64/wenyan-cli)。

```bash
# 直接 wenyan-cli
wenyan publish -f article.md -t lapis -h solarized-light

# 或脚本（会自动检测并安装 wenyan-cli）
./scripts/publish.sh /path/to/article.md
```

- **能力**：Markdown 自动转公众号格式、图片自动传微信图床、一键推草稿、多主题、代码高亮、支持本地 / 网络图片。
- **强制 frontmatter**（实测缺一不可，否则报"未能找到文章封面"）：

```markdown
---
title: 文章标题（必填）
cover: https://example.com/cover.jpg   # 必填；相对路径 ./assets/、绝对路径、网络图均可
---
```

- **主题**：内置 `default / lapis / phycat` 等；代码高亮 `atom-one-dark / dracula / github / solarized-light / xcode` 等；`--no-mac-style` 关 Mac 代码块、`--no-footnote` 关链接转脚注；自定义主题 `wenyan theme --add`。

---

## 五、通用踩坑（三个都相关）

| 问题 | 解决 |
|------|------|
| IP 不在白名单（`ip not in whitelist`） | `curl ifconfig.me` 拿到公网 IP，去公众号后台「开发 → 基本配置 → IP 白名单」添加 |
| 缺 frontmatter | 文件头补 `title` + `cover`（wenyan 系强制） |
| 图片路径带空格 / 用相对路径出错 | 一律用**绝对路径**、目录与文件名**不含空格** |
| token 失效（`40001`） | 用 `publish_with_video.js`，内置 token 管理 |
| wenyan-cli 未装 | `npm install -g @wenyan-md/cli`（toolkit 首次会自动装 fork 版） |

凭据配置：

```bash
export WECHAT_APP_ID=your_app_id
export WECHAT_APP_SECRET=your_app_secret
# 也可写进 TOOLS.md，由发布脚本自动读取
```

---

## 六、典型组合工作流

```
A. 原创长文：热点搜索(article-pro) → 刘润风格写作 → AI 封面 → 发草稿
B. 洗稿别人的文：搜索(toolkit) → 洗稿改写 → 发布(toolkit/publisher) → 草稿箱
C. 自有 Markdown：写好 md（带 frontmatter）→ wechat-publisher 一键发草稿
```

> 一句话：要「写」用 article-pro，要「改」用 toolkit，要「发」用 publisher；三者共用同一套微信凭据与 IP 白名单。
