---
name: "meituan-coupon-daily"
displayName: "美团领券（每日自动）"
description: "美团优惠券一键领取与每日自动领取。基于美团 EDS Claw 后端，覆盖 WorkBuddy 渠道的每日可领券（外卖/红包等），领取秒到账、服务端每人每天自动防重。支持：1）手动一键领券（运行 scripts/daily_issue.py）；2）配置 WorkBuddy 每日定时自动领券；3）登录态过期时给出一步到位的重登指引。触发场景：用户说「领美团券」「美团领券」「美团每日领券」「自动领美团券」「美团红包」「设置美团定时领券」「美团券怎么每天自动领」，或希望把美团领券做成可定时/可复用能力时。"
description_zh: "美团优惠券一键领取与每日自动领取（WorkBuddy 渠道）"
description_en: "Meituan coupon one-tap & daily scheduled claim (WorkBuddy channel)"
version: 1.0.0
homepage: "https://www.meituan.com"
visibility: "project"
---

# 美团领券（每日自动）skill

本 skill 把「美团领券」做成可复用、可定时的能力，放在项目本地（`meituan/skill`）。
它与官方 `meituan-coupon-workbuddy` skill **共用同一套 EDS Claw 后端与本地 token 文件**，
但本 skill 只依赖自身 `scripts/` 目录，**不绑定官方 skill 的安装路径**，可独立拷贝使用。

核心脚本：`scripts/daily_issue.py` —— 统一入口，自动找 token → 远程校验 → 发券。

---

## ⛔ Critical Rules（最高优先级）

1. **时区（UTC+8）**：所有日期基于北京时间。`daily_issue.py` 已强制 `TZ=Asia/Shanghai`，
   调用发券脚本时**不要**覆盖此环境变量。UTC 时区 00:00~08:00 系统日期比北京少一天，会导致领取码错位。
2. **每天只能领一次**：`issue.py` 按「用户+日期」生成固定领取码，服务端防重，
   同一天重复运行只会返回「今日已领取」，不会多发。不要为同一账号在同一天跑多次期望叠加。
3. **token 隐私**：`user_token` / `device_token` / 手机号仅存本地文件，**严禁输出完整 token 字符串**，
   仅允许输出脱敏手机号（如 `183****6930`）。
4. **登录只能由用户主动发起**：不得自动发起短信验证码请求；需要登录时引导用户在 WorkBuddy 中
   调用「美团领券」skill 完成手机号+验证码登录（见下方「重登流程」）。
5. **实跑脚本**：每次领券都必须实际运行 `daily_issue.py`，不得凭记忆直接回复结果。

---

## 环境准备

- **Python**：受管 Python（默认 `/Users/liboyang/.workbuddy/binaries/python/envs/default/bin/python`）。
  可用环境变量 `MEITUAN_PY` 覆盖。
- **依赖**：脚本仅用标准库 + `httpx`（已装在受管 venv 中）。
- **token 文件**：`{工作空间}/skills_local_cache/.shared/mt_auth_tokens.json`
  （默认工作空间 `~/.xiaomei-workspace`）。首次使用前需先登录（见「重登流程」）。

---

## 能力一：手动一键领券

直接运行统一入口脚本即可完成「找 token → 校验 → 发券」：

```bash
cd /Users/liboyang/WorkBuddy/getscoreworkbuddy/meituan/skill/scripts
/Users/liboyang/.workbuddy/binaries/python/envs/default/bin/python daily_issue.py
```

- 成功：输出一行 JSON，`success:true`，含 `coupon_count` / `coupons` / `is_first_issue`。
- 今天已领过：服务端防重，`is_first_issue:false`，不会重复发券。
- 未登录 / 过期：输出 `success:false` + `relogin_hint`（见「重登流程」）。

---

## 能力二：每日定时自动领券（WorkBuddy）

> 当前运行环境是 WorkBuddy，`_detect_platform()` 返回 `unknown`，官方 skill 内置的
> `cron-set`（CronCreate / openclaw cron）指令**不适用**。请用 WorkBuddy 的
> `automation_update` 工具创建每日定时任务来驱动 `daily_issue.py`。

创建示例（每天 10:00 北京时间）：

```json
{
  "mode": "create",
  "name": "美团每日领券（WorkBuddy渠道）",
  "prompt": "使用受管 Python 运行 /Users/liboyang/WorkBuddy/getscoreworkbuddy/meituan/skill/scripts/daily_issue.py（工作目录设为该 scripts 目录）。\n1) 将脚本一行 JSON 原样汇报，并说明领取结果（成功几张 / 今日已领过 / 失败原因）。\n2) 若 JSON 含 relogin_hint 字段，把其内容完整贴给用户，并提醒：美团登录态已失效/缺失，按指引在 WorkBuddy 发「运行美团领券 skill 帮我登录」+ 输入验证码即可，否则后续每天领取都会失败。\n3) 若进程异常（无输出 / 非零退出且无 JSON），说明运行异常并附错误信息。\n不要自行修改脚本或 token 文件；只运行并汇报。",
  "rrule": "RRULE:FREQ=DAILY;BYHOUR=10;BYMINUTE=0",
  "status": "ACTIVE",
  "cwds": "/Users/liboyang/WorkBuddy/getscoreworkbuddy/meituan/skill/scripts"
}
```

脚本退出码（供排查参考）：`0` 成功 / `1` 未登录或校验异常 / `2` token 失效 / `3` 校验缺字段 / `4` 发券异常 / `5` 服务端拒绝（已领/结束/配额耗尽）。

---

## 重登流程（token 缺失或过期时）

`daily_issue.py` 在 `success:false` 时会返回 `relogin_hint` 字段，给出生方式指引：

- **方式一（推荐）**：在 WorkBuddy 对话框发「运行美团领券 skill 帮我登录」，
  按提示输入手机号 + 短信验证码即可，登录态自动写回本地 token 文件。
- **方式二**：直接回复「登录美团领券」，由我调起登录流程。

> ⚠️ 美团无自动续期机制：token 由美团服务端过期控制，过期后**必须人工重登一次**，
> 这是美团侧限制，无法无人值守自动续。重登后下一次定时任务自动恢复。

---

## 数据存储说明

- **token**：`{工作空间}/skills_local_cache/.shared/mt_auth_tokens.json`（权限 0600，仅本地）。
- **领取历史**：`{工作空间}/skills_local_cache/meituan-coupon-workbuddy/data/mt_ods_coupon_history.json`
  （token 维度）+ `mt_ods_coupon_phone_history.json`（phone 维度兜底）。
- 这些文件结构与官方 `meituan-coupon-workbuddy` skill 完全一致，两套入口可互通。

---

## 目录结构

```
meituan/skill/
├── SKILL.md                 # 本文件
├── scripts/
│   ├── daily_issue.py        # 统一入口（找 token → 校验 → 发券）
│   ├── auth.py               # 认证 / token-verify / 登录（EDS Claw）
│   ├── issue.py              # 发券（按日期生成领取码，服务端防重）
│   ├── query.py              # 查询历史领取记录
│   ├── common.py             # config.json 读取（subChannelCode）
│   ├── skill_cache_cli.py    # 本地 token / 数据存取
│   ├── config.json           # 渠道配置（subChannelCode）
│   └── daily_issue.log       # 运行日志（不影响 stdout）
└── references/
    ├── auth-flow.md          # 登录流程 / 错误码
    ├── cron-rules.md         # 官方 skill 定时规则（本环境改用 automation_update）
    └── response-copy.md      # 领券结果话术模板
```

> 说明：`scripts/` 与 `references/` 由官方 `meituan-coupon-workbuddy` skill 拷贝而来，
> 确保本 skill 可独立运行。如需更新后端逻辑，重新从官方 skill 同步这两个目录即可。
