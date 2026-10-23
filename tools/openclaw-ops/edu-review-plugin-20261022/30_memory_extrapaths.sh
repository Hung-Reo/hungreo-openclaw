#!/bin/bash
# 30 — GO-R: cho Rùa tra phiếu giáo dục ĐÃ DUYỆT qua memory_search.
#   ssh hungreo-claude-vps 'bash -s hungreo [dry|apply|rollback <BACKUP_DIR>]' < 30_memory_extrapaths.sh
# Cách làm giống Suckhoe (extraPaths → kb/medical/approved, 04/10): thêm đúng 1 đường dẫn vào
# agents.entries.main.memory.search.extraPaths bằng MỘT config patch, rồi `memory index --force`.
# Sự cố 04/10 (Suckhoe): đổi phạm vi index khi CHƯA có khoá embeddings → memory_search 0 kết quả. Precheck bắt buộc:
# provider + khoá có mặt, index sạch, baseline search có kết quả; sau khi đổi phải ra lại >= baseline.
# Không đổi model/auth/fallback/slots. Không in secret, không in nội dung memory (chỉ đếm + đường dẫn file khớp).
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
P=${1:-}; MODE=${2:-dry}; RB=${3:-}
[ "$P" = hungreo ] || { echo "ABORT: chỉ dành cho hungreo"; exit 1; }
D=$HOME/.openclaw-$P; U=openclaw-gateway-$P.service; PORT=18789; OC=/home/hung/bin/openclaw
EDU=/home/hung/openclaw-shared/kb/education/approved
B=$HOME/backups/edu-memory-$P-$(date +%Y%m%d-%H%M%S)
TMPD=$(mktemp -d); chmod 700 "$TMPD"; trap 'rm -rf "$TMPD"' EXIT
mask() { sed -E -e '/sk-|eyJ/d' -e 's/[0-9]{8,}/<N>/g'; }
oc() { ( for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done; unset TELEGRAM_BOT_TOKEN
         set -a; . "$D/gateway.systemd.env"; set +a; cd /tmp
         OPENCLAW_PROFILE=$P OPENCLAW_STATE_DIR=$D OPENCLAW_CONFIG_PATH=$D/openclaw.json OPENCLAW_GATEWAY_PORT=$PORT \
         OPENCLAW_SYSTEMD_UNIT=$U timeout 900 $OC --profile $P "$@" < /dev/null ) 2>&1 | mask; return "${PIPESTATUS[0]}"; }
# Không qua mask(): mask thay số dài thành <N> làm hỏng JSON (score 0.<N>). Chỉ in đường dẫn file khớp, không in snippet.
oc_raw() { ( for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done; unset TELEGRAM_BOT_TOKEN
             set -a; . "$D/gateway.systemd.env"; set +a; cd /tmp
             OPENCLAW_PROFILE=$P OPENCLAW_STATE_DIR=$D OPENCLAW_CONFIG_PATH=$D/openclaw.json OPENCLAW_GATEWAY_PORT=$PORT \
             OPENCLAW_SYSTEMD_UNIT=$U timeout 300 $OC --profile $P "$@" < /dev/null ) 2>/dev/null; }
hits() { oc_raw memory search "$1" --json | jq -r '[.results[]?.path] | unique | .[]' 2>/dev/null || true; }
BASEQ="Rùa vận hành OpenClaw Hungreo"   # câu chắc chắn có trong memory cũ
EDUQ="Bộ chuẩn phát triển trẻ em năm tuổi đã bị bãi bỏ"   # nội dung chỉ có trong EDU-2026-W43 approved

status_line() { oc memory status | grep -E "^(Provider|Sources|Indexed|Dirty|Vector store|Batch):" | tr '\n' ' '; echo; }

if [ "$MODE" = rollback ]; then
  case "$RB" in "$HOME"/backups/edu-memory-hungreo-*) ;; *) echo "ABORT: rollback cần ~/backups/edu-memory-hungreo-*"; exit 1 ;; esac
  OLD=$(cat "$RB/extraPaths.before.json")
  jq -n --argjson x "$OLD" '{agents:{entries:{main:{memory:{search:{extraPaths:$x}}}}}}' > "$TMPD/rb.json"
  oc config patch --file "$TMPD/rb.json" | tail -2
  oc memory index --force | tail -3
  echo "  sau rollback: $(status_line)"
  echo "  baseline hits: $(hits "$BASEQ" | wc -l)  edu hits: $(hits "$EDUQ" | grep -c education || true)"
  echo "ROLLBACK DONE"; exit 0
fi

echo "== [0] precheck ($(date '+%F %T'))"
[ "$(systemctl --user is-active $U)" = active ] || { echo "ABORT: $U không active"; exit 1; }
jq -e '.agents.entries.main.memory.search | .provider and .model and (.remote.apiKey != null)' $D/openclaw.json >/dev/null || { echo "ABORT: memory search chưa có provider/model/khoá"; exit 1; }
[ -s $D/credentials/memory-embeddings.key ] || { echo "ABORT: thiếu file khoá embeddings"; exit 1; }
[ -d "$EDU" ] && ls "$EDU"/EDU-*.md >/dev/null 2>&1 || { echo "ABORT: $EDU chưa có phiếu approved"; exit 1; }
S0=$(status_line); echo "  trước: $S0"
grep -q "Dirty: no" <<<"$S0" || { echo "ABORT: index đang dirty, để yên"; exit 1; }
CUR=$(jq -c '.agents.entries.main.memory.search.extraPaths // []' $D/openclaw.json)
jq -e --arg e "$EDU" 'index($e)==null' <<<"$CUR" >/dev/null || { echo "  extraPaths đã có $EDU — không cần đổi"; exit 0; }
NEW=$(jq -c --arg e "$EDU" '. + [$e]' <<<"$CUR")
BASE_N=$(hits "$BASEQ" | wc -l); EDU_N0=$(hits "$EDUQ" | grep -c education || true)
echo "  baseline hits=$BASE_N  edu hits (trước)=$EDU_N0  extraPaths: $CUR → $NEW"
[ "$BASE_N" -ge 1 ] || { echo "ABORT: baseline search 0 kết quả — memory_search đang không khỏe"; exit 1; }
jq -n --argjson x "$NEW" '{agents:{entries:{main:{memory:{search:{extraPaths:$x}}}}}}' > "$TMPD/patch.json"
oc config patch --file "$TMPD/patch.json" --dry-run | tail -2
if [ "$MODE" = dry ]; then echo "OK dry — chưa đổi gì"; exit 0; fi

echo "== [1] backup -> $B"
mkdir -p "$B"; chmod 700 "$B"
cp -p $D/openclaw.json "$B/"
printf '%s' "$CUR" > "$B/extraPaths.before.json"
python3 - "$D/agents/main/agent/openclaw-agent.sqlite" "$B/openclaw-agent.sqlite" <<'PY'
import sqlite3,sys
src=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True); dst=sqlite3.connect(sys.argv[2])
src.backup(dst); dst.close(); src.close()
PY
python3 -c "import sqlite3,sys;print('  backup quick_check:',sqlite3.connect(sys.argv[1]).execute('pragma quick_check').fetchone()[0])" "$B/openclaw-agent.sqlite"
(cd "$B" && sha256sum openclaw.json extraPaths.before.json openclaw-agent.sqlite > SHA256SUMS)
du -sh "$B" | cut -f1

echo "== [2] patch extraPaths + memory index --force"
SINCE=$(date '+%F %T'); PID0=$(systemctl --user show $U -p MainPID --value)
oc config patch --file "$TMPD/patch.json" | tail -2
[ "$(jq -c '.agents.entries.main.memory.search.extraPaths' $D/openclaw.json)" = "$NEW" ] || { echo "ABORT: readback extraPaths sai — chạy rollback $B"; exit 1; }
sleep 10
echo "  gateway sau patch: $(systemctl --user is-active $U) pid_changed=$([ "$(systemctl --user show $U -p MainPID --value)" = "$PID0" ] && echo no || echo YES)"
journalctl --user -u $U --since "$SINCE" --no-pager | grep -iE "reload|memory|restart" | mask | cut -c1-200 | tail -5 || true
oc memory index --force | tail -3

echo "== [3] kiểm"
S1=$(status_line); echo "  sau: $S1"
BASE_N1=$(hits "$BASEQ" | wc -l); EDU_HITS=$(hits "$EDUQ" | grep education || true)
echo "  baseline hits=$BASE_N1 (trước $BASE_N)"; echo "  edu hits: ${EDU_HITS:-0 kết quả}"
FAIL=""
[ "$BASE_N1" -ge 1 ] || FAIL="baseline 0 kết quả"
[ -n "$EDU_HITS" ] || FAIL="$FAIL; chưa tìm ra phiếu approved"
grep -q "Dirty: no" <<<"$S1" || FAIL="$FAIL; index dirty"
RZ=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/readyz); [ "$RZ" = 200 ] || FAIL="$FAIL; readyz=$RZ"
if [ -n "$FAIL" ]; then echo "CHECK FAILED: $FAIL"; echo "  rollback: ssh hungreo-claude-vps 'bash -s hungreo rollback $B' < 30_memory_extrapaths.sh"; exit 1; fi
echo "BACKUP=$B"
echo "OK 30 — Hưng hỏi Rùa 1 câu về phiếu W43 để kiểm tầng người dùng"
