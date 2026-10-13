#!/bin/bash
# 10 — HƯNG CHẠY. Upgrade Hermes 819cc3cb → stable v0.21.6 (Hưng GO Q2, 11/10/2026).
# Dùng updater chính thức: `hermes update --channel stable` (checkout đúng commit bản publish, không kéo main).
# DRY_RUN=1 → chỉ kiểm điều kiện + chụp trạng thái, không backup lớn, không stop, không update.
# FORCE=1   → bỏ qua chặn "Hermes đang có lượt chạy trong 5 phút gần nhất".
# Chạy: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 10_upgrade.sh
set -u
export TZ=Asia/Ho_Chi_Minh XDG_RUNTIME_DIR=/run/user/$(id -u)
H=~/.hermes; A=$H/hermes-agent; BIN=$HOME/.local/bin/hermes; U=hermes-gateway.service
PY=$H/tools/python-3.14.7+20260901-linux-x64/bin/python3
DRY=${DRY_RUN:-0}; TS=$(date +%Y%m%d-%H%M%S); BK=~/backups/hermes-upgrade-v0216-$TS
[ "$DRY" = 1 ] && BK=/tmp/hermes-upgrade-dry-$TS
mkdir -p "$BK"; chmod 700 "$BK"
log() { echo "$*" | tee -a "$BK/log.txt"; }

state() { # label
  log "== $1 $(date '+%F %T')"
  log "version: $($BIN --version 2>&1 | head -1)"
  log "commit: $(git -C $A rev-parse --short HEAD)  dirty=$(git -C $A status --porcelain | wc -l)"
  log "gateway: $(systemctl --user is-active $U) pid=$(systemctl --user show $U -p MainPID --value)"
  log "journal_mode db=$($PY -c 'import sqlite3,os;print(sqlite3.connect("file:"+os.path.expanduser("~/.hermes/state.db")+"?mode=ro",uri=True).execute("PRAGMA journal_mode").fetchone()[0])' 2>&1) config=$(grep -m1 -E '^\s*journal_mode:' $H/config.yaml | awk '{print $2}')"
  log "cron: $($PY -c 'import json,os;j=json.load(open(os.path.expanduser("~/.hermes/cron/jobs.json")));j=j.get("jobs",j) if isinstance(j,dict) else j;print(len(j),"jobs",sum(1 for x in j if x.get("enabled",True)),"enabled")')"
  for f in config.yaml profiles/vnstock/config.yaml SOUL.md AGENTS.md profiles/vnstock/SOUL.md; do
    [ -f "$H/$f" ] && log "sha $f $(sha256sum "$H/$f" | cut -c1-8)"; done
}

# YAML compare: chỉ in ĐƯỜNG DẪN khoá đổi, không in giá trị (config có chat_id).
yaml_keys() { # file -> sorted "path=hash8"; /usr/bin/python3 có PyYAML và độc lập với bản Hermes đang upgrade
  /usr/bin/python3 - "$1" <<'PY'
import sys,hashlib,yaml
d=yaml.safe_load(open(sys.argv[1])) or {}
def walk(o,p=""):
    if isinstance(o,dict):
        for k,v in o.items(): yield from walk(v,f"{p}.{k}" if p else str(k))
    else: yield p, hashlib.sha256(repr(o).encode()).hexdigest()[:8]
for k,h in sorted(walk(d)): print(f"{k}={h}")
PY
}

log "backup/evidence: $BK"
state BEFORE
yaml_keys $H/config.yaml > "$BK/config.keys.before" 2>>"$BK/log.txt"
yaml_keys $H/profiles/vnstock/config.yaml > "$BK/vnstock.keys.before" 2>>"$BK/log.txt"
log "fallback_model before: $(grep -A2 '^fallback_model:' $H/config.yaml | tr -s ' \n' ' ')"

# Không cắt ngang lượt Hermes đang làm (vd đang sửa PR #71)
recent=$(awk -v t="$(date -d '-5 min' '+%F %T')" 'substr($0,1,19)>=t' $H/logs/agent.log 2>/dev/null | grep -c 'API call #')
log "Hermes API calls 5 phút gần nhất: $recent"
if [ "$recent" -gt 0 ] && [ "${FORCE:-0}" != 1 ]; then log "STOP — Hermes đang làm việc. Chờ xong lượt rồi chạy lại (hoặc FORCE=1)."; exit 2; fi
[ -z "$(git -C $A status --porcelain)" ] || { log "STOP — hermes-agent có file sửa cục bộ; báo Claude Code."; exit 2; }
free_gb=$(df -BG --output=avail ~ | tail -1 | tr -dc 0-9); log "disk free: ${free_gb}G"
[ "$free_gb" -ge 10 ] || { log "STOP — cần ≥10G trống cho bản sao rollback."; exit 2; }
log "plan:"; timeout 120 $BIN update --plan --channel stable 2>&1 | tee -a "$BK/log.txt" | head -12

if [ "$DRY" = 1 ]; then log "DRY_RUN — dừng ở đây."; exit 0; fi

# 1) Bản sao rollback: code + runtime + state (cùng ổ đĩa, giữ quyền)
log "== backup $(date +%T)"
cp -a $A "$BK/hermes-agent" && cp -a $H/tools "$BK/tools" || { log "STOP — copy rollback lỗi"; exit 1; }
mkdir -p "$BK/state/profiles/vnstock" "$BK/state/cron"
for f in config.yaml .env auth.json SOUL.md AGENTS.md gateway_state.json channel_directory.json; do [ -e $H/$f ] && cp -a $H/$f "$BK/state/"; done
cp -a $H/cron/. "$BK/state/cron/"; cp -a $H/profiles/vnstock/. "$BK/state/profiles/vnstock/" 2>/dev/null
for db in state.db kanban.db verification_evidence.db shared-state.db; do
  [ -f $H/$db ] && $PY -c 'import sqlite3,sys;s=sqlite3.connect(sys.argv[1]);d=sqlite3.connect(sys.argv[2]);s.backup(d);d.close()' $H/$db "$BK/state/$db"
done
log "backup size: $(du -sh "$BK" | cut -f1)"

# 2) Stop gateway → update → KHÔNG để updater tự restart
log "== stop gateway $(date +%T)"; systemctl --user stop $U; log "gateway: $(systemctl --user is-active $U)"
log "== hermes update --channel stable $(date +%T)"
timeout 1800 $BIN update --channel stable --backup --yes --no-gateway-restart >"$BK/update.out" 2>&1; rc=$?
tail -25 "$BK/update.out" | grep -viE 'token|secret|api[_-]?key|chat_id' | tee -a "$BK/log.txt"
log "update exit=$rc"
if [ $rc -ne 0 ]; then log "STOP — update lỗi; gateway vẫn TẮT. Báo Claude Code (rollback: 99_rollback.sh $BK)."; exit 1; fi

# 3) Hậu kiểm tĩnh trước khi bật
state AFTER-UPDATE
yaml_keys $H/config.yaml > "$BK/config.keys.after"; yaml_keys $H/profiles/vnstock/config.yaml > "$BK/vnstock.keys.after"
log "config.yaml khoá đổi (chỉ tên khoá):"; diff "$BK/config.keys.before" "$BK/config.keys.after" | grep -E '^[<>]' | sed -E 's/=[0-9a-f]{8}$//' | sort -u | tee -a "$BK/log.txt" | head -40
log "vnstock config khoá đổi:"; diff "$BK/vnstock.keys.before" "$BK/vnstock.keys.after" | grep -E '^[<>]' | sed -E 's/=[0-9a-f]{8}$//' | sort -u | tee -a "$BK/log.txt"
log "fallback_model after: $(grep -A2 '^fallback_model:' $H/config.yaml | tr -s ' \n' ' ')"
jm=$(grep -m1 -E '^\s*journal_mode:' $H/config.yaml | awk '{print $2}')
[ "$jm" = delete ] || log "⚠️ journal_mode config = '$jm' (phải là delete — lesson #109727). Báo Claude Code TRƯỚC khi dùng lâu."
timeout 120 $BIN doctor 2>&1 | grep -viE 'token|secret|api[_-]?key|chat_id' | tail -25 | tee -a "$BK/log.txt"

# 4) Bật gateway, chờ ổn định
since=$(date '+%F %T'); log "== start gateway $since"; systemctl --user start $U
for i in $(seq 1 24); do sleep 5; [ "$(systemctl --user is-active $U)" = active ] && [ $i -ge 4 ] && break; done
log "gateway: $(systemctl --user is-active $U) NRestarts=$(systemctl --user show $U -p NRestarts --value)"
journalctl --user -u $U --since "$since" --no-pager | grep -iE 'error|exception|traceback|telegram|connected|started|cron' | grep -viE 'token|secret|chat_id' | tail -15 | tee -a "$BK/log.txt"
state AFTER-START

# 5) Smoke đường vn-stock (1 lượt Sol nhỏ, cùng lệnh production; kiểm route, không OpenRouter)
log "== smoke vn-stock oneshot"
timeout 180 $BIN -p vnstock -z 'Trả lời đúng một chữ: OK' --provider openai-codex -m gpt-6-sol \
  --usage-file "$BK/smoke-usage.json" --ignore-rules -t todo --reasoning low >"$BK/smoke.out" 2>&1; src=$?
log "smoke exit=$src output=$(head -c 80 "$BK/smoke.out" | tr '\n' ' ')"
[ -f "$BK/smoke-usage.json" ] && log "smoke route: $($PY -c 'import json,sys;d=json.load(open(sys.argv[1]));print({k:v for k,v in d.items() if any(s in k.lower() for s in ("provider","model","fallback","route"))})' "$BK/smoke-usage.json" 2>&1)"
grep -qi openrouter "$BK/smoke.out" "$BK/smoke-usage.json" 2>/dev/null && log "⚠️ OPENROUTER xuất hiện trong smoke — báo Claude Code NGAY."
log "OK 10 — báo Claude Code verify. Hưng nhắn Hermes 1 câu trên Telegram để kiểm tầng người dùng. Rollback: 99_rollback.sh $BK"
