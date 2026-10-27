#!/bin/bash
# 10 — HƯNG CHẠY: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 10_apply.sh
# Chèn 1 gạch đầu dòng "kiểm version plugin" vào AGENTS.md của Rùa (Hungreo). Không restart; sau đó Hưng gửi /new.
# Idempotent: đã có marker thì không làm gì.
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
F=$HOME/.openclaw-hungreo/workspace/AGENTS.md
EXPECT=05de36e7   # sha256 8 ký tự của AGENTS.md lúc soạn (18/10)
MARK='<!-- plugin-version-check 2026-10-18 -->'
ANCHOR='- Không tự đổi agents.defaults.model.*'

[ -f "$F" ] || { echo "ABORT: không thấy $F"; exit 1; }
if grep -qF "$MARK" "$F"; then echo "SKIP: đã có ghi chú (marker), không đổi gì"; sha256sum "$F" | cut -c1-8; exit 0; fi
CUR=$(sha256sum "$F" | cut -c1-8)
[ "$CUR" = "$EXPECT" ] || { echo "ABORT: AGENTS.md đã đổi từ lúc soạn (sha $CUR ≠ $EXPECT) — báo Claude soạn lại"; exit 1; }
[ -L "$F" ] && { echo "ABORT: $F là symlink"; exit 1; }
[ "$(grep -c '^- Không tự đổi agents\.defaults\.model\.\*' "$F")" = 1 ] || { echo "ABORT: dòng neo không duy nhất/không có"; exit 1; }

B=$F.bak-$(date +%Y%m%d-%H%M%S)-pre-plugin-version-note
cp -p "$F" "$B"
[ "$(sha256sum "$B" | cut -c1-8)" = "$EXPECT" ] || { echo "ABORT: backup lệch hash"; rm -f "$B"; exit 1; }
echo "BACKUP=$B"

TMP=$(mktemp "$F.tmp.XXXX")
trap 'rm -f "$TMP"' EXIT
python3 - "$F" "$TMP" "$ANCHOR" "$MARK" <<'PY'
import sys
src, out, anchor, mark = sys.argv[1:5]
note = (mark + "\n"
 "- Version plugin/core của một profile: chạy `/home/hung/bin/openclaw --profile <hungreo|suckhoe> plugins inspect <plugin-id>` "
 "(đọc dòng Version + Install path; xem tất cả: `plugins list`). Install path đúng nằm dưới `~/.openclaw-<profile>/npm/`. "
 "`~/.openclaw/` là profile mặc định cũ, không phải Rùa hay Suckhoe — không lấy version ở đó; `plugins.installs` trong openclaw.json "
 "trống là bình thường ở 9.x (bản ghi cài nằm trong state/openclaw.sqlite). Trả lời version kèm lệnh đã chạy.\n")
lines = open(src, encoding="utf-8").read().splitlines(keepends=True)
res, done = [], False
for l in lines:
    res.append(l)
    if not done and l.startswith(anchor):
        res.append(note); done = True
assert done
text = "".join(res)
open(out, "w", encoding="utf-8").write(text)
print("chars:", len(text))
PY
CH=$(python3 -c "import sys;print(len(open(sys.argv[1],encoding='utf-8').read().encode('utf-16-le'))//2)" "$TMP")  # đếm như JS .length
[ "$CH" -lt 20000 ] || { echo "ABORT: $CH ký tự ≥ bootstrapMaxChars 20000 — không áp"; rm -f "$TMP"; exit 1; }
chmod --reference="$F" "$TMP"
mv "$TMP" "$F"

echo "-- readback"
grep -n -A1 -F "$MARK" "$F" | cut -c1-200
echo "diff lines: $(diff "$B" "$F" | grep -c '^>')  (kỳ vọng 2)"
echo "new sha: $(sha256sum "$F" | cut -c1-8)"
echo "OK 10 — giờ Hưng gửi /new cho Rùa rồi hỏi: \"bạn đang xài LCM bản mấy?\" (kỳ vọng 1.1.1 + có nêu lệnh plugins inspect)"
echo "Rollback: ssh … 'bash -s $B' < 99_rollback.sh"
