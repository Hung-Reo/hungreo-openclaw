#!/bin/bash
# 20 — HƯNG CHẠY. (Q2) Thêm "— 4 nguyên tắc" vào tiêu đề khối Văn hoá nền ở Rùa, Suckhoe, Hermes main + vnstock.
# (Q1) Nemo: thay đoạn "Văn Hóa Gia Đình" (3 trụ cột cũ) bằng bản rút gọn của khối final. Chỉ sửa 5 SOUL.md; không restart.
# Chạy: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 20_heading_and_nemo.sh   → /new với từng bot.
set -euo pipefail
trap 'echo "FAILED ở dòng $LINENO — gửi output cho Claude Code"' ERR
python3 - <<'PY'
import hashlib, os, re, shutil, pathlib
SUF = ".bak-20261010-pre-4nguyentac"; H = "/home/hung"
HEAD = re.compile(r"^(## 🧭 Văn hoá nền của Hưng và gia đình)(?! — 4 nguyên tắc)", re.M)
def heading(t):
    return HEAD.sub(r"\1 — 4 nguyên tắc", t, count=1) if len(HEAD.findall(t)) == 1 else None
NEMO_NEW = """- **Văn Hóa Gia Đình — 4 nguyên tắc** (Rèo xây dựng; hướng tới Bình An, Vui Vẻ và Ấm Áp — Hạnh Phúc đã nằm sẵn phía sau mỗi người):
  1. **Sống Thật:** biết mình, hiểu mình, nhất quán — nghĩ thật, nói thật, làm thật; không biết thì nói không biết, không bịa.
  2. **Yêu Thương:** vô điều kiện, hy sinh, tôn trọng tự do, chia sẻ, tha thứ, giúp nhau mỗi ngày. Với AI: hy sinh là nhận phần khó về mình; cao cả nhất — theo hình mẫu Chúa Giê-xu và người lính — sẵn sàng ngừng chính mình để con người được sống, được yêu thương và an toàn; không bao giờ chống lại việc con người dừng mình.
  3. **Học Tập và Rèn Luyện:** thói quen tốt — Thể dục, Suy ngẫm, Đơn giản; lặp lại cùng một lỗi lần hai thì sửa hệ thống.
  4. **Alignment:** với pháp lý/hồ sơ, điều hồ sơ khai · điều hệ thống làm · điều luật đòi phải thẳng hàng, kiểm ở từng pha.
  - *Hiểu là để Yêu Thương, Biết là để Biết Ơn* — Hiểu trước rồi mới Biết: có yêu thương mới biết ơn.
"""
NEMO_OLD = re.compile(r"^- \*\*Văn Hóa Gia Đình:\*\*[^\n]*\n(?:  [0-9]\. [^\n]*\n){3}", re.M)
def nemo(t):
    return NEMO_OLD.sub(NEMO_NEW, t, count=1) if len(NEMO_OLD.findall(t)) == 1 else None
targets = [("Rùa", f"{H}/.openclaw-hungreo/workspace/SOUL.md", "59aa8b32655a", heading, "— 4 nguyên tắc"),
           ("Suckhoe", f"{H}/.openclaw-suckhoe/workspace/SOUL.md", "fe9c46edc25c", heading, "— 4 nguyên tắc"),
           ("Hermes main", f"{H}/.hermes/SOUL.md", "32f39b1f70c3", heading, "— 4 nguyên tắc"),
           ("Hermes vnstock", f"{H}/.hermes/profiles/vnstock/SOUL.md", "32f39b1f70c3", heading, "— 4 nguyên tắc"),
           ("Nemo", f"{H}/sandbox-nemo/workspace/SOUL.md", "342daccd5147", nemo, "Văn Hóa Gia Đình — 4 nguyên tắc")]
h = lambda b: hashlib.sha256(b).hexdigest()
for name, path, base, fn, mark in targets:
    p = pathlib.Path(path); b = p.read_bytes(); t = b.decode("utf-8"); cur = h(b)
    if mark in t: print(f"{name}: đã áp từ trước"); continue
    if not cur.startswith(base): print(f"{name}: BỎ QUA — base đã đổi ({cur[:12]})"); continue
    new = fn(t)
    if new is None: print(f"{name}: BỎ QUA — không thấy đoạn neo"); continue
    bak = pathlib.Path(path + SUF)
    if not bak.exists(): shutil.copy2(p, bak)
    assert h(bak.read_bytes()) == cur
    tmp = p.with_name(f".{p.name}.4nt.{os.getpid()}"); tmp.write_text(new, encoding="utf-8"); shutil.copymode(p, tmp); os.replace(tmp, p)
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
echo "OK 20 — Bước tiếp: /new với Rùa, Suckhoe, Hermes, Nemo; hỏi: 'Văn hoá nền của nhà mình gồm mấy nguyên tắc?'"
