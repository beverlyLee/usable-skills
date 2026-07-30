# 美团领券 Skill（meituan/skill）

一个自包含的「美团每日领券」项目 skill：一键领取 WorkBuddy 渠道配置的每日活动券，
并配套每日定时任务与登录态过期后的重登指引。

> 与官方 `meituan-coupon-workbuddy` skill 共用同一套 **美团 EDS Claw 后端**和本地 token 文件，
> 但本 skill 仅依赖自身 `scripts/` 目录，**不绑定官方 skill 的安装路径**，可整目录拷贝独立使用。

---

## 能力概览

| 能力 | 说明 |
|------|------|
| 一键领券 | 运行入口脚本，自动找 token → 远程校验 → 发券 |
| 每日自动领 | 已通过 WorkBuddy 定时任务（每天 10:00 北京时间）接入，token 有效期内全自动 |
| 登录态记忆 | 登录后 token 持久化到本地磁盘，有效期内每天复用，无需重登 |
| 过期友好 | token 失效/缺失时输出 `relogin_hint`，定时任务自动把一步重登步骤甩给你 |

---

## 目录结构

```
meituan/skill/
├── README.md                   # 本文件
├── .gitignore                  # 忽略 Python 缓存 / 运行日志等本地产物
├── SKILL.md                    # skill 元信息（能力 / 时区 / 隐私规则 / 用法）
├── scripts/
│   ├── daily_issue.py          # ★ 统一入口：找 token → 远程校验 → 发券
│   ├── auth.py                 # 认证模块（登录态校验 / 过期检测）
│   ├── issue.py                # 发券脚本（每日领取码防重，每人每天一次）
│   ├── query.py                # 可领权益查询
│   ├── common.py               # 公共配置（读 config.json）
│   ├── skill_cache_cli.py      # 本地 token 读写封装
│   ├── config.json             # 渠道配置（subChannelCode）
│   └── daily_issue.log         # 运行日志（本地产物，已 gitignore）
└── references/
    ├── auth-flow.md            # 登录流程说明
    ├── cron-rules.md           # 定时领券规则
    └── response-copy.md        # 回复话术模板
```

---

## 快速开始

### 前置条件
- 已登录：在 WorkBuddy 中调用「美团领券」skill 完成 **手机号 + 短信验证码** 登录一次。
  （登录态会被写入 `~/.xiaomei-workspace/skills_local_cache/.shared/mt_auth_tokens.json`）
- 受管 Python（含 `httpx`）：`/Users/liboyang/.workbuddy/binaries/python/envs/default/bin/python`
  - 可用环境变量 `MEITUAN_PY` 覆盖解释器路径，便于其他机器复用。

### 手动领一次
```bash
cd /Users/liboyang/WorkBuddy/getscoreworkbuddy/meituan/skill/scripts
/Users/liboyang/.workbuddy/binaries/python/envs/default/bin/python daily_issue.py
```

成功输出示例（一行 JSON）：
```json
{"success": true, "step": "issue", "is_first_issue": true, "coupon_count": 5, "coupons": [...]}
```
> `is_first_issue: false` 表示今天已领过，服务端防重机制自动拦截，不会重复发放。

---

## 每日自动领券（已接入）

定时任务 `automation-1785338855524`（WorkBuddy 自动化）已配置：
- **频率**：每天 10:00（北京时间，`RRULE:FREQ=DAILY;BYHOUR=10;BYMINUTE=0`）
- **动作**：运行 `meituan/skill/scripts/daily_issue.py`，并把 JSON 结果汇报给你。
- **过期提醒**：若 JSON 带 `relogin_hint`，会自动把重登步骤贴出。

> 想立刻验证（不等 10:00）：在 WorkBuddy 对该自动化点「立即运行」，或直接跑上面的命令。

---

## 退出码

| 码 | 含义 |
|----|------|
| 0 | 领取成功（含今天已领过被防重拦截） |
| 1 | 未找到已登录 token / token-verify 运行异常 |
| 2 | token 失效（需重新登录） |
| 3 | token-verify 返回缺少字段 |
| 4 | 发券脚本异常 |
| 5 | 发券被服务端拒绝（已领取 / 活动结束 / 配额耗尽等） |

---

## 重要规则与边界

1. **时区**：强制 `TZ=Asia/Shanghai`。美团按北京时间生成每日领取码，必须用东八区，否则 UTC 跨日会错位。
2. **登录态会过期**：美团**没有 refresh token 机制**，服务端 token 过期后必须人工重新登录
   （手机号 + 短信验证码）。本 skill 能「记住」登录态，但**无法做到永久免登录**——这是美团侧限制。
3. **隐私**：token 仅存本地磁盘，不进仓库（见 `.gitignore`），不外传。
4. **领券数量随活动变动**：每人每天可领的活动券数量由美团服务端决定，会随时间调整
   （实测从 6 张变为 5 张），以脚本实际返回的 `coupon_count` 为准。

---

## 同步官方 skill 更新

后端脚本（`scripts/` + `references/`）是从官方 `meituan-coupon-workbuddy` skill 拷贝而来。
若官方 skill 升级，重新拷贝一次即可同步：

```bash
SRC=/Users/liboyang/.workbuddy/skills/meituan-coupon-workbuddy
DST=/Users/liboyang/WorkBuddy/getscoreworkbuddy/meituan/skill
cp "$SRC/scripts/"{auth.py,issue.py,query.py,common.py,skill_cache_cli.py,config.json} "$DST/scripts/"
cp "$SRC/references/"{auth-flow.md,cron-rules.md,response-copy.md} "$DST/references/"
```
