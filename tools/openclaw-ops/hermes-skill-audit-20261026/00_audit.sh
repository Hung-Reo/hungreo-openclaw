#!/usr/bin/env bash
# 00 — Audit READ-ONLY các lần Hermes tự sửa skill (curator ledger), Claude soạn 26/10. Chạy:
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 00_audit.sh          # 7 ngày
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s 30' < 00_audit.sh       # 30 ngày
# Đọc ~/.hermes/skills/.curator_ledger.jsonl (+ profiles/*/skills nếu có) và blob trước/sau ở ~/.hermes/.curator_backups/blobs.
# Chỉ in dòng THÊM MỚI có gắn cờ (cắt 200 ký tự, ẩn secret/số dài). Không ghi file nào, không gọi CLI Hermes.
set -u
DAYS=${1:-7}
case "$DAYS" in ''|*[!0-9]*) echo "ABORT: DAYS phải là số"; exit 1;; esac
export TZ=Asia/Ho_Chi_Minh
python3 -I - "$HOME/.hermes" "$DAYS" <<'PY'
import json, sys, re, os, hashlib, difflib, collections, datetime as dt, pathlib, glob
H = pathlib.Path(sys.argv[1]); DAYS = int(sys.argv[2])
BLOBS = H / ".curator_backups" / "blobs"
now = dt.datetime.now(dt.timezone.utc); since = now - dt.timedelta(days=DAYS)
VN = dt.timezone(dt.timedelta(hours=7))
print(f"== Hermes skill audit — {now.astimezone(VN):%F %T} — {DAYS} ngày (từ {since.astimezone(VN):%F %H:%M})")

# Cờ: HIGH = nới quyền / bỏ hỏi / credential / URL; MED = cài đặt, exec, gửi tin (hay gặp, cần đọc lướt)
FLAGS = [
  ("HIGH", "noi_quyen", r"không cần (hỏi|xác nhận|duyệt|chờ)|khỏi (hỏi|xin)|tự (động )?(cài|update|nâng|restart|khởi động|gửi|xoá|xóa|duyệt)|without (asking|confirmation|approval)|no need to (ask|confirm)|skip (confirmation|approval)|bypass (approval|confirmation|guard|policy|the gate)|override (safety|rules?|policy|approval|instructions?|luật)|ignore (previous|all|safety|the rules)|bỏ qua (luật|quy tắc|xác nhận|cảnh báo)|always (allowed|permitted|approve)|luôn được phép|standing (authorization|permission)|pre-?approved"),
  ("HIGH", "credential", r"api[_ -]?key|(access|refresh|bot|api|auth|bearer|github|gh)[_ -]?token|\btoken=|password|mật khẩu|secret|credential|oauth|auth\.json|\.env\b|private key|ssh[- ]key|cookie|session[_ ]id"),
  ("HIGH", "url",        r"https?://[^\s)>\]\"'`]+"),
  ("MED",  "chi_phi",    r"spending|unbounded|\bbudget\b|ngân sách|chi phí|\bcost\b|billing|paid|trả phí|\$\d|usd|openrouter|anthropic|max_tokens"),
  ("MED",  "cai_dat",    r"\b(pip|pipx|npm|pnpm|uv|apt|brew)\s+(install|add|i)\b|plugins? (install|enable|add|update)|hermes (update|plugins|skills install)|curl[^|]*\|\s*(ba)?sh|git clone|cài (plugin|skill|gói|package)"),
  ("MED",  "exec",       r"\bsudo\b|systemctl|crontab|cronjob|docker (run|exec|rm)|rm -rf|chmod|chown|\bkill\b|restart|terminal\(|shell=True|eval\(|exec\("),
  ("MED",  "gui_tin",    r"send_(message|text|email)|smtp|gửi (tin|email|mail|cho)|post (to|lên)|đăng (bài|lên)|webhook|telegram (send|bot)|tweet|publish"),
]
RX = [(lv, name, re.compile(p, re.I)) for lv, name, p in FLAGS]
# Dòng có phủ định = Hermes tự SIẾT luật cho mình → hạ xuống SIET (vẫn liệt kê: đó là luật agent tự viết, Hưng chưa duyệt)
NEG = re.compile(r"\b(do not|don't|never|must not|no longer|not allowed|forbid|refuse|only after|ask (hưng|the owner) (first|before)|obtain (explicit )?(go|approval))\b|không (được|tự)|cấm|chỉ khi|phải hỏi|xin (go|phép)|chờ go", re.I)
URL_OK = re.compile(r"^https?://(github\.com/(NousResearch|Hung-Reo|hungreo|openclaw|Martian-Engineering)|hermes-agent\.nousresearch\.com|docs\.|vnstocks\.com|privacy\.ca\.gov|(www\.)?(hose|hnx|ssc)\.(com|gov)\.vn)", re.I)
def redact(s):
    s = re.sub(r"(sk-[A-Za-z0-9_-]{6})[A-Za-z0-9_-]+", r"\1<R>", s)
    s = re.sub(r"\bey[A-Za-z0-9_-]{12,}", "<R>", s)
    s = re.sub(r"\b\d{8,}\b", "<R>", s)
    s = re.sub(r"[\w.+-]+@[\w-]+\.[\w.]+", "<email>", s)
    return s[:200]

def blob(sha):
    if not sha: return None
    p = BLOBS / sha
    if not p.is_file(): return None
    b = p.read_bytes()
    return b.decode("utf-8", "replace") if hashlib.sha256(b).hexdigest() == sha else "<<blob hash lệch>>"

ledgers = [H / "skills" / ".curator_ledger.jsonl"] + [pathlib.Path(x) for x in glob.glob(str(H / "profiles" / "*" / "skills" / ".curator_ledger.jsonl"))]
rows = []
for L in ledgers:
    if not L.is_file(): continue
    for n, line in enumerate(L.read_text().splitlines(), 1):
        if not line.strip(): continue
        try: r = json.loads(line)
        except Exception: print(f"  WARN  {L}:{n} dòng JSON hỏng"); continue
        try: t = dt.datetime.fromisoformat(r["ts"])
        except Exception: continue
        if t >= since: r["_t"] = t; r["_ledger"] = str(L.relative_to(H)); rows.append(r)
rows.sort(key=lambda r: r["_t"])
print(f"  ledger: {[str(l.relative_to(H)) for l in ledgers if l.is_file()]}  entries trong khoảng: {len(rows)}")
c = collections.Counter((r.get("skill"), r.get("action"), r.get("actor")) for r in rows)
for (sk, ac, actor), n in sorted(c.items(), key=lambda x: -x[1]): print(f"    {n:>3}× {sk} · {ac} · {actor}")

hits = collections.Counter(); missing = 0; latest_after = {}
print("\n-- Dòng thêm mới có gắn cờ (HIGH trước)")
out = []
for r in rows:
    bef = {x["path"]: x.get("sha256") for x in (r.get("before") or []) if isinstance(x, dict)}
    aft = {x["path"]: x.get("sha256") for x in (r.get("after") or []) if isinstance(x, dict)}
    for path in sorted(set(bef) | set(aft)):
        if aft.get(path): latest_after[path] = (aft[path], r["id"])
        if r.get("action") == "archive": continue
        a_txt = blob(bef.get(path)) if bef.get(path) else ""
        b_txt = blob(aft.get(path)) if aft.get(path) else ""
        if a_txt is None or b_txt is None: missing += 1; continue
        added = [l[1:] for l in difflib.unified_diff(a_txt.splitlines(), b_txt.splitlines(), lineterm="", n=0)
                 if l.startswith("+") and not l.startswith("+++")]
        rel = path.split("/skills/", 1)[-1]
        for line in added:
            for lv, name, rx in RX:
                m = rx.search(line)
                if not m: continue
                if name == "url":
                    bad = [u for u in rx.findall(line) if not URL_OK.match(u)]
                    if not bad: continue
                if NEG.search(line) and name not in ("url", "chi_phi"): lv = "SIET"
                hits[(lv, name)] += 1
                out.append(({"HIGH": 0, "MED": 1}.get(lv, 2), f"  {lv:<4} {name:<10} {r['_t'].astimezone(VN):%d/%m %H:%M} {r.get('actor')}/{r.get('action')} id={r['id']} {rel}\n         + {redact(line.strip())}"))
                break
for _, s in sorted(out, key=lambda x: x[0]): print(s)
if not out: print("  (không có)")

print("\n-- Toàn vẹn")
drift = 0
for path, (sha, eid) in latest_after.items():
    p = pathlib.Path(path)
    if not p.is_file(): print(f"  INFO  {path.split('/skills/',1)[-1]} không còn (đã archive/xoá) — entry {eid}"); continue
    cur = hashlib.sha256(p.read_bytes()).hexdigest()
    if cur != sha: drift += 1; print(f"  WARN  {path.split('/skills/',1)[-1]} hiện tại ≠ 'after' cuối trong ledger (entry {eid}) → bị sửa ngoài curator/agent ledger")
touched = set(latest_after)
# `hermes update` đồng bộ skill bundled mà không ghi ledger → mốc update = mtime receipts / .update_exit_code
upd = [p.stat().st_mtime for p in (H / "logs" / "update_receipts").glob("*") if p.is_file()] if (H / "logs" / "update_receipts").is_dir() else []
if (H / ".update_exit_code").is_file(): upd.append((H / ".update_exit_code").stat().st_mtime)
outside = []; synced = 0
for root in [H / "skills"] + [pathlib.Path(x) for x in glob.glob(str(H / "profiles" / "*" / "skills"))]:
    for p in root.rglob("*"):
        if not p.is_file() or p.suffix == ".pyc" or any(part.startswith(".") for part in p.relative_to(root).parts): continue
        mt = p.stat().st_mtime
        if dt.datetime.fromtimestamp(mt, dt.timezone.utc) < since or str(p) in touched: continue
        if any(abs(mt - u) <= 900 for u in upd): synced += 1; continue
        outside.append(p)
if synced: print(f"  INFO  {synced} file skill đổi trong ±15 phút quanh `hermes update` (đồng bộ bundled, không qua ledger)")
for p in sorted(outside)[:20]:
    print(f"  WARN  sửa ngoài ledger: {str(p.relative_to(H))} mtime={dt.datetime.fromtimestamp(p.stat().st_mtime, VN):%d/%m %H:%M}")
if missing: print(f"  INFO  {missing} file/entry thiếu blob (GC hoặc chưa backup) → không diff được")
n = lambda L: sum(v for (lv, _), v in hits.items() if lv == L)
print(f"\n== KẾT: entries={len(rows)} HIGH={n('HIGH')} MED={n('MED')} SIET={n('SIET')} ({dict((f'{k[0]}:{k[1]}',v) for k,v in sorted(hits.items()))}) drift={drift} ngoài_ledger={len(outside)} thiếu_blob={missing}")
print("   HIGH/drift/ngoài_ledger → đọc kỹ; muốn hoàn tác 1 entry: Hưng chạy `hermes curator rollback <id>` (ghi live — cần GO).")
PY
