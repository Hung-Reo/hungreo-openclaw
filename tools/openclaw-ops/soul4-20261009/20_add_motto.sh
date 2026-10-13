#!/bin/bash
# 20 — HƯNG CHẠY. Thêm 2 dòng "Đích đến" + "Why → Hiểu → Action / Hiểu là để Yêu Thương" vào khối Văn hoá nền
# của Suckhoe và Hermes (main + vnstock, cùng một SOUL). Chỉ sửa 3 file SOUL.md; không restart.
# Chạy: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 20_add_motto.sh   → rồi /new với Suckhoe và Hermes.
set -euo pipefail
trap 'echo "FAILED ở dòng $LINENO — gửi output cho Claude Code"' ERR
python3 - <<'PY'
import hashlib, os, shutil, pathlib
SUF = ".bak-20261009-pre-motto"
MOTTO = '\n❤️ **Đích đến:** *"Hướng tới Hạnh Phúc, Vui Vẻ và Ấm Áp"*.\n**Why → Hiểu → Action**, bởi *"Hiểu là để Yêu Thương"*.'
SK = "4. **Alignment** (hồ sơ sức khoẻ) — *điều toa/hồ sơ ghi · điều Suckhoe lưu và nhắc · điều bác sĩ chỉ định* phải thẳng hàng; lệch thì hỏi lại, không tự chọn."
HE = "4. **Alignment** — với việc pháp lý/hồ sơ: *điều hồ sơ khai · điều hệ thống làm · điều luật đòi* phải thẳng hàng, kiểm ở từng pha."
H = "/home/hung"
targets = [
  ("Suckhoe", f"{H}/.openclaw-suckhoe/workspace/SOUL.md", "2b9a838d7916c86f", SK),
  ("Hermes main", f"{H}/.hermes/SOUL.md", "cceceaf2d8a521d1", HE),
  ("Hermes vnstock", f"{H}/.hermes/profiles/vnstock/SOUL.md", "cceceaf2d8a521d1", HE),
]
h = lambda b: hashlib.sha256(b).hexdigest()
for name, path, base, anchor in targets:
    p = pathlib.Path(path); b = p.read_bytes(); t = b.decode("utf-8"); cur = h(b)
    if "Hướng tới Hạnh Phúc, Vui Vẻ và Ấm Áp" in t: print(f"{name}: đã có từ trước"); continue
    if not cur.startswith(base): print(f"{name}: BỎ QUA — base đã đổi ({cur[:12]})"); continue
    if t.count(anchor) != 1: print(f"{name}: BỎ QUA — không thấy dòng Alignment"); continue
    new = t.replace(anchor, anchor + MOTTO, 1)
    bak = pathlib.Path(path + SUF)
    if not bak.exists(): shutil.copy2(p, bak)
    assert h(bak.read_bytes()) == cur
    tmp = p.with_name(f".{p.name}.motto.{os.getpid()}"); tmp.write_text(new, encoding="utf-8"); shutil.copymode(p, tmp); os.replace(tmp, p)
    assert p.read_text(encoding="utf-8") == new
    print(f"{name}: OK {len(t)}→{len(new)} chars, sha {h(new.encode())[:12]}, backup {bak.name}")
PY
(cd /home/hung/.hermes/hermes-agent && venv/bin/python - <<'PY'
import sys, logging; logging.disable(logging.CRITICAL); sys.path.insert(0, ".")
from agent.prompt_builder import _scan_context_content
for f in ("/home/hung/.hermes/SOUL.md", "/home/hung/.hermes/profiles/vnstock/SOUL.md"):
    c = open(f, encoding="utf-8").read()
    print(f"  scan {f.replace('/home/hung/', '')}:", "OK" if _scan_context_content(c, "SOUL.md", user_authored=True) == c else "BLOCKED")
PY
)
echo "OK 20 — Bước tiếp: /new với Suckhoe và Hermes; hỏi: 'Văn hoá nền của nhà mình gồm mấy nguyên tắc?'"
