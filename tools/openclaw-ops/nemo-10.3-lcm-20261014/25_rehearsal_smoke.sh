#!/usr/bin/env bash
set -Eeuo pipefail
T=/home/hung/sandbox-nemo/ops-10.3-lcm-20261014
C=nemo-rehearsal-103-lcm
KEY=agent:main:ops-lcm-20261014
oc(){ docker exec "$C" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs "$@" < /dev/null; }
for n in 2 3 4; do
 oc agent --session-key "$KEY" --message "Dữ liệu giả của lượt kiểm thử số $n: ghi nhận tiến độ thử nghiệm LCM, không cần công cụ và không gửi ra ngoài. Trả lời ACK_$n." --timeout 90 --json > "$T/rehearsal-turn-$n.json" 2> "$T/rehearsal-turn-$n.err"
done
oc sessions compact "$KEY" --timeout 180000 --json > "$T/rehearsal-compact.json" 2> "$T/rehearsal-compact.err"
python3 - "$T" <<'PY'
import json,sys,pathlib,sqlite3
p=pathlib.Path(sys.argv[1]);s=(p/'rehearsal-compact.json').read_text();d=None
for i,c in enumerate(s):
 if c!='{':continue
 try:d,end=json.JSONDecoder().raw_decode(s[i:]);break
 except Exception:continue
assert d and d.get('ok') and d.get('compacted'), 'compaction did not report success'
db=sqlite3.connect((p/'rehearsal-config/lcm.db').as_uri()+'?mode=ro',uri=True);n=db.execute('select count(*) from summaries').fetchone()[0];assert n>0,'no LCM summaries';print('REHEARSAL_REAL_MODEL_COMPACTION_OK summaries=',n);db.close()
PY
# Restart the isolated gateway; do not restart the serving or other gateways.
docker restart -t 45 "$C" >/dev/null
ready=0
for n in $(seq 1 60); do
 if docker exec "$C" node -e 'fetch("http://127.0.0.1:18796/readyz").then(r=>process.exit(r.status===200?0:1)).catch(()=>process.exit(1))' >/dev/null 2>&1; then ready=1; break; fi
 sleep 2
done
[ "$ready" = 1 ]
oc agent --session-key "$KEY" --message 'Dùng công cụ lcm_grep để kiểm tra mã tủ sách trong dữ liệu giả lượt đầu. Trả lời chỉ mã tủ sách đã tìm thấy, không gửi ra ngoài.' --timeout 120 --json > "$T/rehearsal-recall.json" 2> "$T/rehearsal-recall.err"
python3 - "$T" <<'PY'
import json,sys,pathlib,sqlite3
p=pathlib.Path(sys.argv[1]);s=(p/'rehearsal-recall.json').read_text();d=None
for i,c in enumerate(s):
 if c!='{':continue
 try:d,end=json.JSONDecoder().raw_decode(s[i:]);break
 except Exception:continue
assert d and d.get('status')=='ok'
texts=[x.get('text','') for x in d.get('result',{}).get('payloads',[])];assert any('SEN-731' in x for x in texts),'recall marker absent'
db=sqlite3.connect((p/'rehearsal-config/lcm.db').as_uri()+'?mode=ro',uri=True);assert db.execute('pragma quick_check').fetchone()[0]=='ok';print('REHEARSAL_RESTART_RECALL_SQLITE_OK');db.close()
PY
