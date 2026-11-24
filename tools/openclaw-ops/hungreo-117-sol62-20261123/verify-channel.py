import json
from pathlib import Path
import sys

raw = Path(sys.argv[1]).read_text()
result, _ = json.JSONDecoder().raw_decode(raw[raw.find("{"):])
accounts = result.get("channelAccounts", {}).get("telegram", [])
if not accounts:
    channel = result.get("channels", {}).get("telegram")
    accounts = [channel] if isinstance(channel, dict) else []
if not accounts or not all(
    a.get("running") is True and a.get("probe", {}).get("ok") is True
    for a in accounts if a.get("enabled", True)
) or not any(a.get("enabled", True) for a in accounts):
    raise RuntimeError("Telegram running/probe evidence missing")
print("telegram_running=yes telegram_probe=ok")
