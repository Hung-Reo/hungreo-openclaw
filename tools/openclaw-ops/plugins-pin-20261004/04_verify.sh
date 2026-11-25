#!/bin/bash
# 04 — Claude Code chạy (read-only + 2 lượt UAT ngắn). Kiểm 3 tầng sau bảo trì.
export TZ=Asia/Ho_Chi_Minh
OC=/home/hung/bin/openclaw
B=/home/hung/backups/maint-20261004-plugins
date
echo "== (a) gateway: versions + load errors since restart"
for p in hungreo suckhoe; do
  u=openclaw-gateway-$p.service
  since=$(systemctl --user show $u -p ActiveEnterTimestamp --value | awk '{print $2" "$3}')
  echo "-- $p active=$(systemctl --user is-active $u) since=$since NRestarts=$(systemctl --user show $u -p NRestarts --value)"
  journalctl --user -u $u --since "$since" --no-pager | grep -E "http server listening|Cannot find module|plugin.*(fail|error)|Invalid input" | cut -c1-230 | head -6
  OPENCLAW_STATE_DIR=$HOME/.openclaw-$p timeout 90 $OC --profile $p plugins list --json 2>/dev/null |
    python3 -c 'import json,sys;d=json.load(sys.stdin);ps=d.get("plugins",d);print("  ",{x["id"]:(x.get("version"),x.get("status")) for x in ps if x.get("origin")=="global"})'
done
echo "== (a2) config DIFF vs backup SAU restart (bắt auto-migration lúc start)"
for p in hungreo suckhoe; do
python3 - "$HOME/.openclaw-$p/openclaw.json" "$B/$p/openclaw.json" "$p" <<'EOF'
import json, sys
def flat(d, p=""):
    o = {}
    if isinstance(d, dict):
        for k, v in d.items(): o.update(flat(v, p + "." + k))
    else: o[p] = d
    return o
a = flat(json.load(open(sys.argv[1]))); b = flat(json.load(open(sys.argv[2])))
ks = [k for k in sorted(set(a) | set(b)) if a.get(k) != b.get(k)]
sens = lambda k: any(x in k.lower() for x in ("token", "key", "secret", "password"))
print(sys.argv[3], "changed keys:", len(ks))
for k in ks: print("  ", k, "| old=", "<R>" if sens(k) else b.get(k), "| new=", "<R>" if sens(k) else a.get(k))
EOF
done
echo "== (a3) unpinned finding còn không"
for p in hungreo suckhoe; do
  OPENCLAW_STATE_DIR=$HOME/.openclaw-$p timeout 180 $OC --profile $p security audit --json 2>/dev/null |
    python3 -c 'import json,sys;d=json.load(sys.stdin);f=[x for x in d["findings"] if x["checkId"]=="plugins.installs_unpinned_npm_specs"];print(sys.argv[1],d["summary"],(f[0]["detail"].replace(chr(10)," / ")[:200] if f else "unpinned: none"))' $p
done
echo "== (a4) suckhoe auth + memory index"
OPENCLAW_STATE_DIR=$HOME/.openclaw-suckhoe timeout 60 $OC --profile suckhoe models auth list 2>&1 | grep -E "openai:hungreo" | sed -E 's/(ey[A-Za-z0-9_-]{10,})/<R>/g'
OPENCLAW_STATE_DIR=$HOME/.openclaw-suckhoe OPENCLAW_CONFIG_PATH=$HOME/.openclaw-suckhoe/openclaw.json timeout 90 $OC --profile suckhoe memory status --agent main 2>&1 | grep -iE "files|chunks|dirty|vector" | head -5
echo "== (a5) skill google-sheets đã ra khỏi workspace"
ls -d /home/hung/.openclaw-hungreo/workspace/skills/google-sheets 2>/dev/null || echo "  gone (backup: $B/skills/google-sheets)"
echo "== (c) UAT_OK (winner phải openai/gpt-6-sol, attempts=1)"
for p in hungreo suckhoe; do
  OPENCLAW_STATE_DIR=$HOME/.openclaw-$p timeout 200 $OC --profile $p agent --json --session-id uat-plugins-20261004-$p \
    --message "Reply with exactly UAT_OK and nothing else." 2>/dev/null |
    python3 -c 'import json,sys
d=json.load(sys.stdin);r=d.get("result",d);m=r.get("meta",{}).get("executionTrace",{})
print(sys.argv[1],"winner=",m.get("winnerProvider"),m.get("winnerModel"),"attempts=",len(m.get("attempts") or []),"text=",(r.get("payloads") or [{}])[0].get("text"))' $p
done
echo "== 403 sau restart (suckhoe)"
since=$(systemctl --user show openclaw-gateway-suckhoe.service -p ActiveEnterTimestamp --value | awk '{print $2" "$3}')
journalctl --user -u openclaw-gateway-suckhoe.service --since "$since" --no-pager | grep -c "403 Forbidden"
