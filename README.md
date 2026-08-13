# usable-skills

> 可复用、自包含的 WorkBuddy / 桌面自动化 Skill 合集。每个 Skill 都能整体下载、拷贝到任意位置直接运行。

---

## 📚 已收录 Skill

| Skill | 平台 | 简介 |
|---|---|---|
| [`workbuddy-click-skill`](workbuddy-click-skill/) | macOS | WorkBuddy 桌面端每日自动签到领积分。打开「Buddy 加油站」抽屉 → 点击「立即领取」，内置相对坐标 + 图像判定 + 防假成功机制。 |
| [`meituan-coupon-skill`](meituan-coupon-skill/) | Web/API | 美团 WorkBuddy 渠道每日自动领券（EDS Claw）。一键领券 + 每日定时（WorkBuddy 自动化）+ 登录态记忆 + 过期友好重登指引；登录态仅存本地，不含任何账号信息。 |
| [`trae-work-cn-checkin`](trae-work-cn-checkin/) | macOS | Trae Work CN 桌面端每日自动签到。点击左下角用户名 → 弹出用户菜单 → 点击「签到」按钮；采用归一化相对坐标（抗窗口移动/缩放），并按 Window Server 窗口 ID 截图（避免拍到桌面），带严格防假成功判定。 |
| [`juejin-tech-column`](juejin-tech-column/) | 稀土掘金 | 掘金技术专栏写作：给框架内容产出可发布技术长文/连载（代码先行 + mermaid 原生渲染 + 发布前 mmdc 验证）。内置写作铁律（事实兜底 / 去 AI 味 / 多图型 / 质量门）。 |
| [`wechat-mp-tech-column`](wechat-mp-tech-column/) | 微信公众号 | 公众号技术专栏写作：产出深度长文/合集（总分总 3000–8000 字 + mermaid 转 PNG + 全内联粘贴版）。内置写作铁律（事实兜底 / 去 AI 味 / 多图型 / 质量门）。 |
| [`xhs-tech-column`](xhs-tech-column/) | 小红书 | 小红书技术图文写作：产出图卡驱动笔记（封面 + 6 张 3:4 信息卡 + 图与文匹配）。内置写作铁律（事实兜底 / 去 AI 味 / 质量门；mermaid 弱化为图卡）。 |

---

## 🧭 如何使用某个 Skill

1. 克隆仓库（或单独下载某个 Skill 文件夹）：
   ```bash
   git clone -b create https://github.com/beverlyLee/usable-skills.git
   ```
2. 进入对应文件夹，按其中的 `README.md` / `SKILL.md` 部署。
3. 多数 Skill 首次使用需要**校准坐标或编译原生工具**，细节见各自目录。

---

## 🤝 贡献

欢迎提交新的可复用 Skill：在仓库下新建一个独立文件夹，包含 `SKILL.md` 与必要的
脚本 / 文档，然后提 Pull Request 即可。
