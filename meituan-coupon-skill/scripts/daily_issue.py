#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
美团领券 skill —— 一键 / 每日自动领券入口
=========================================
本脚本是「美团领券」项目 skill 的统一入口，负责：
  1. 在候选工作空间里找到已登录的美团 user_token
     （登录信息由美团认证模块写入 {ws}/skills_local_cache/.shared/mt_auth_tokens.json）
  2. 调用 auth.py token-verify 远程校验（过期时认证模块会自动清空 user_token）
  3. 若有效，调用 issue.py 发券（服务端自动防重复领取，每人每天一次）
  4. 若无效（未登录 / 已过期），输出结构化提示（含 relogin_hint）方便下一步重登

与官方 meituan-coupon-workbuddy skill 共用同一套 EDS Claw 后端与本地 token 文件，
但本脚本只依赖同目录下的 scripts/，可独立放置、不绑定官方 skill 的安装路径。

用法：
  python3 daily_issue.py                         # 自动探测工作空间并发券
  MEITUAN_PY=/path/to/python python3 daily_issue.py   # 指定 Python 解释器
  SKILL_CACHE_WORKSPACE=/path python3 daily_issue.py   # 指定 token 工作空间

退出码：
  0  领取成功（含今天已领过被服务端防重拦截）
  1  找不到已登录的 token（需先登录）或 token-verify 运行异常
  2  token 失效（需重新登录）
  3  token-verify 返回缺少字段
  4  发券脚本异常
  5  发券被服务端拒绝（已领取 / 活动结束 / 配额耗尽等）
"""

import os
import sys
import json
import subprocess
from datetime import datetime

# ── 路径常量 ──────────────────────────────────────────────────────────
# 脚本自身所在目录即为 skill 的 scripts/ 目录，保证自包含
SKILL_SCRIPTS = os.path.dirname(os.path.abspath(__file__))
# 优先使用受管 Python；可通过环境变量覆盖，便于其他机器复用
MANAGED_PY = os.environ.get(
    "MEITUAN_PY",
    "/Users/liboyang/.workbuddy/binaries/python/envs/default/bin/python",
)
TOKEN_FILE_REL = os.path.join("skills_local_cache", ".shared", "mt_auth_tokens.json")

# 候选工作空间（按优先级）：显式 env → 已知默认路径 → 常见根目录
CANDIDATE_WORKSPACES = [
    os.environ.get("SKILL_CACHE_WORKSPACE"),
    os.environ.get("AGENT_WORKSPACE"),
    os.environ.get("CLAUDE_WORKSPACE"),
    os.environ.get("XIAOMEI_WORKSPACE"),
    os.path.expanduser("~/.xiaomei-workspace"),
    os.path.expanduser("~/.openclaw/workspace"),
    "/Users/liboyang/WorkBuddy",
    os.path.expanduser("~"),
]

LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "daily_issue.log")

# ── 重登指引（token 缺失 / 过期时给出，便于定时任务汇报后一步操作）────────
RELOGIN_HINT_NEVER = (
    "尚未登录美团领券：\n"
    "  方式一（推荐）：在 WorkBuddy 对话框发「运行美团领券 skill 帮我登录」，"
    "按提示输入手机号 + 短信验证码即可，登录态会自动写回本地。\n"
    "  方式二：直接回复我「登录美团领券」，我来帮你调起登录流程。\n"
    "登录成功后本地会保存 token，之后每天定时任务自动领券，无需再操作。"
)

RELOGIN_HINT_EXPIRED = (
    "美团服务端 token 已过期（美团无自动续期机制，必须人工重登）：\n"
    "  方式一（推荐）：在 WorkBuddy 对话框发「运行美团领券 skill 帮我登录」，"
    "按提示输入手机号 + 短信验证码即可，登录态会自动写回本地。\n"
    "  方式二：直接回复我「登录美团领券」，我来帮你调起登录流程。\n"
    "重登成功后，下一次定时任务会自动继续领券，无需再做任何操作。"
)


def _log(msg: str):
    """追加一行运行日志（不影响 stdout 的 JSON 输出）。"""
    try:
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"[{ts}] {msg}\n")
    except Exception:
        pass


def find_workspace_with_token() -> str | None:
    """扫描候选工作空间，返回存在有效 user_token 的那个。

    注意：token 文件里的条目 key 未必等于 skill 目录名
    （实测为 'meituan-c-user-auth' 而非 'meituan-coupon-workbuddy'），
    所以这里扫描所有顶层 key，取第一个含非空 user_token 的条目，
    避免 key 名漂移导致误报“未找到 token”。
    """
    for ws in CANDIDATE_WORKSPACES:
        if not ws:
            continue
        ws = os.path.expanduser(ws)
        token_path = os.path.join(ws, TOKEN_FILE_REL)
        if not os.path.exists(token_path):
            continue
        try:
            with open(token_path, encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            continue
        if not isinstance(data, dict):
            continue
        for key, entry in data.items():
            if isinstance(entry, dict) and entry.get("user_token"):
                _log(f"FOUND token in {token_path} (key={key})")
                return ws
    return None


def _run(cmd, env) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=SKILL_SCRIPTS,
        env=env,
        timeout=60,
    )


def _emit(obj: dict) -> str:
    return json.dumps(obj, ensure_ascii=False)


def main() -> int:
    ws = find_workspace_with_token()
    if not ws:
        out = {
            "success": False,
            "step": "find_token",
            "message": "未找到已登录的美团 token，需先完成登录。",
            "relogin_hint": RELOGIN_HINT_NEVER,
        }
        print(_emit(out))
        _log("FAIL find_token: 未找到已登录的 token")
        return 1

    env = os.environ.copy()
    env["SKILL_CACHE_WORKSPACE"] = ws
    env["PYTHONPATH"] = SKILL_SCRIPTS
    # 美团领券按北京时间（UTC+8）生成每日领取码，强制时区避免 UTC 跨日错位
    env["TZ"] = "Asia/Shanghai"

    # 1) 远程校验 token
    r = _run([MANAGED_PY, "auth.py", "token-verify"], env)
    if r.returncode != 0 or not r.stdout.strip():
        out = {
            "success": False,
            "step": "token_verify",
            "returncode": r.returncode,
            "raw_stdout": r.stdout.strip(),
            "raw_stderr": r.stderr.strip(),
        }
        print(_emit(out))
        _log(f"FAIL token_verify rc={r.returncode} err={r.stderr.strip()[:200]}")
        return 1

    try:
        v = json.loads(r.stdout)
    except Exception:
        out = {"success": False, "step": "token_verify", "raw_stdout": r.stdout.strip()}
        print(_emit(out))
        _log("FAIL token_verify: stdout 非 JSON")
        return 1

    if not v.get("valid"):
        reason = v.get("reason", "unknown")
        out = {
            "success": False,
            "step": "token_verify",
            "valid": False,
            "reason": reason,
            "message": "美团 token 已失效（服务端过期），需重新登录。",
            "relogin_hint": RELOGIN_HINT_EXPIRED,
        }
        print(_emit(out))
        _log(f"FAIL token_verify: valid=False reason={reason}")
        return 2

    token = v.get("user_token")
    phone = v.get("phone_masked", "")
    if not token or not phone:
        out = {"success": False, "step": "token_verify", "message": "token-verify 未返回 user_token / phone_masked"}
        print(_emit(out))
        _log("FAIL token_verify: 缺少 user_token/phone_masked")
        return 3

    # 2) 发券
    r = _run([MANAGED_PY, "issue.py", "--token", token, "--phone-masked", phone], env)
    if r.returncode != 0 or not r.stdout.strip():
        out = {
            "success": False,
            "step": "issue",
            "returncode": r.returncode,
            "raw_stdout": r.stdout.strip(),
            "raw_stderr": r.stderr.strip(),
        }
        print(_emit(out))
        _log(f"FAIL issue rc={r.returncode} err={r.stderr.strip()[:200]}")
        return 4

    try:
        i = json.loads(r.stdout)
    except Exception:
        out = {"success": False, "step": "issue", "raw_stdout": r.stdout.strip()}
        print(_emit(out))
        _log("FAIL issue: stdout 非 JSON")
        return 4

    if i.get("success"):
        out = {
            "success": True,
            "step": "issue",
            "is_first_issue": i.get("is_first_issue"),
            "coupon_count": i.get("coupon_count"),
            "coupons": i.get("coupons"),
        }
        print(_emit(out))
        _log(f"OK issue first={i.get('is_first_issue')} count={i.get('coupon_count')}")
        return 0
    else:
        out = {
            "success": False,
            "step": "issue",
            "code": i.get("code"),
            "error": i.get("error"),
            "message": i.get("message"),
        }
        print(_emit(out))
        _log(f"FAIL issue code={i.get('code')} error={i.get('error')} msg={i.get('message')}")
        return 5


if __name__ == "__main__":
    sys.exit(main())
