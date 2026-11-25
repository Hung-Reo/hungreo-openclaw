#!/usr/bin/env python3
"""Áp luật 'không sửa được → phương án + xin GO' và cập nhật giới hạn 600s vào AGENTS.md Hungreo.
Dùng: python3 apply_agents_rule.py <AGENTS.md> [--write]. Không --write = chỉ in diff + số ký tự."""
import difflib, hashlib, sys
path = sys.argv[1]
old = open(path, encoding="utf-8").read()
EXPECT_SHA = "110b63a51c7a0f47"
if hashlib.sha256(old.encode()).hexdigest()[:16] != EXPECT_SHA:
    sys.exit("ABORT: AGENTS.md đã khác bản đã review (sha) — báo Claude Code")
edits = [
    ("- Runtime Codex. Ngân sách lượt chính là 180s;",
     "- Runtime Codex. Giới hạn cứng của lượt chính là 600s (từ 04/10);"),
    ("- **Ngân sách lượt (180s ≈ 17 bước):**",
     "- **Ngân sách lượt (mục tiêu ~180s ≈ 17 bước; giới hạn cứng 600s):**"),
    ("Checkpoint luôn hơn chờ hết 180s.\n",
     "Checkpoint luôn hơn chờ hết giờ.\n"
     "  - Không tự sửa xong được (thiếu nguồn, cần sửa code/config Production, cần GO) → kết thúc bằng tối đa 3 phương án cụ thể, "
     "đánh dấu 1 Khuyến nghị + lý do 1 dòng, rồi hỏi Hưng GO; không dừng ở \"chưa sửa được\".\n"),
]
new = old
for a, b in edits:
    if new.count(a) != 1:
        sys.exit(f"ABORT: không tìm thấy đúng 1 chỗ: {a[:50]}")
    new = new.replace(a, b)
print("".join(difflib.unified_diff(old.splitlines(True), new.splitlines(True), "before", "after", n=0)))
print(f"chars {len(old)} -> {len(new)} (giới hạn 20000)")
if len(new) >= 20000:
    sys.exit("ABORT: vượt 20000 ký tự")
if "--write" in sys.argv:
    open(path, "w", encoding="utf-8").write(new)
    print("WRITTEN")
