# Pha 0 — baseline + đọc diff LCM 1.1.1 → 1.2.0 (21/10/2026 09:29–10:10, read-only)

Script: `00_baseline.sh` (chỉ đếm, không đọc nội dung tin). Không ghi gì lên VPS.

## 1. Diff migration (VERIFIED: đọc `gh api compare v1.1.1...v1.2.0`, 14 commit)

- `src/db/migration.ts`: **chỉ thêm 3 bảng mới**, đều `CREATE TABLE IF NOT EXISTS`: `conversation_transcript_cursors`, `transcript_user_replay_keys`, `conversation_transcript_gaps`. Không `ALTER`/`DROP` bảng cũ. → 1.1.1 chạy lại trên DB đã migrate gần như chắc là được (bảng lạ bị bỏ qua). Đây vẫn là ASSUMPTION cho tới khi rehearsal thử rollback.
- Code đổi lớn: thêm `transcript-delta-sync.ts` (990 dòng); bỏ `reconcile-plan.ts`, `transcript-anchor-audit.ts`, 858 dòng `batch-dedup.ts`, 535 dòng `conversation-store.ts`. Cách chống trùng giờ dựa vào cursor và entry id, không đối chiếu toàn bộ nữa → **kiểm duplicate là bài test bắt buộc**.
- **Điểm sống còn:** 1.2.0 cần host có `readSessionTranscriptVisibleMessageDelta` + `readSessionTranscriptRawDelta`. Thiếu thì chỉ log capability error và **không ingest** (không còn đường cũ để lùi về).
  - VERIFIED: 9.33 (`dist/plugin-sdk/session-transcript-runtime.js`) và Nemo 10.4 **đều có** cả 2 hàm. Chữ ký và hành vi có khớp không thì UNVERIFIED → rehearsal.
- Rollback chính thức: `release-rollback-version: 1.1.1`.

## 2. Baseline (VERIFIED 21/10 09:29)

|                                      | Hungreo                          | Suckhoe         | Nemo                |
| ------------------------------------ | -------------------------------- | --------------- | ------------------- |
| Core / LCM                           | 9.33 / 1.1.1                     | 9.33 / 1.1.1    | 10.4 / 1.1.1        |
| Up từ                                | 18/10 16:45                      | 18/10 16:40     | 18/10 15:42         |
| RSS / VmSwap                         | 1548 / 631 MiB                   | 1343 / 460 MiB  | cgroup 1,11/2,5 GiB |
| rss_threshold/ngày (18→21/10)        | 77 · 167 · **261** · 99 (tới 9h) | 2 · 1 · 0 · 2   | 1 · 1 · 10          |
| Đỉnh RSS/ngày                        | 1,65–**2,16 GiB**                | 1,51–1,59 GiB   | —                   |
| lcm.db + wal                         | **636 MiB**                      | 93 MiB          | 2 MiB               |
| conversations (active)               | 2102 (982)                       | 710 (611)       | 4 (3)               |
| messages / summaries                 | 51.474 / 997                     | 11.261 / 65     | **126 / 0**         |
| messages chưa có transcript_entry_id | 44.471 (86%)                     | 9.080 (81%)     | 18                  |
| dup entry_id / dup identity_hash     | 0 / 4.186                        | 0 / 1.408       | 0 / 7               |
| Hội thoại lớn nhất (msgs)            | 8.327 · 6.716 · 2.045            | 753 · 609 · 388 | 94                  |
| "Lỗ" summary→context tail (#1252)    | conv lớn nhất 86 msgs            | 129 msgs        | —                   |
| quick_check / lossless lỗi 7 ngày    | ok / 0                           | ok / 0          | ok / 0              |

Swap VPS 2711/4095 MiB (`/swapfile` đầy, `/swapfile2` 760 MiB). RAM available 2,7 GiB.

**Nhận xét:**

- **Nemo không đại diện cho LCM**: có 126 messages, 0 summary, chưa compaction lần nào. Canary trên Nemo chỉ chứng minh plugin load được và ingest tin mới, không chứng minh migration DB lớn hay compaction. → Rehearsal clone Hungreo là bắt buộc, không thể thay bằng Nemo.
- 86% messages Hungreo chưa có entry id (dữ liệu cũ). Migration 1.2.0 "không nhập lịch sử trước entry cuối còn thấy được" và ghi phần thiếu vào `conversation_transcript_gaps`. Cần đếm gaps sau migration và chắc nó không nhập lại 44k tin.
- `dup identity_hash` là baseline (có thể là tin trùng nội dung hợp lệ). Sau 1.2.0 chỉ cần **không tăng bất thường**.
- Không đo được độ trễ LCM bằng log hiện có. `reply resolver timings` chỉ in ở lượt có voice, và phần lớn thời gian nằm ở `apply_media_understanding`, không phải LCM. 1.2.0 có log debug cho từng lần drain → đo trong rehearsal.
- Nemo trên 10.4: rss_threshold giảm từ 227–244/ngày (10.3) còn 1–10/ngày. Workload Nemo nhẹ nên **chưa** kết luận 10.4 chữa được RSS (UNVERIFIED).

## 3. Issue tracker LCM (VERIFIED 21/10 ~10:00)

- Chưa có issue nào về 1.2.0 (bản mới ra khoảng 13h).
- #1252 OPEN (1.1.1, core 9.9): tin bị đẩy khỏi fresh tail chưa được tóm tắt, tạo "lỗ" mà `lcm_expand` không với tới. Comment sau đó đính chính rằng lỗ được lấp khi compaction chạy. Hungreo và Suckhoe đều có lỗ đúng kiểu này (86 và 129 msgs) → hiện tượng **đang có trên 1.1.1**, không phải do 1.2.0.
- #1255 OPEN (1.1.1): ngưỡng compaction tính theo `contextWindow` của provider, nên đổi route model có thể dời ngưỡng gấp 5 lần và compaction dừng lặng lẽ. **Liên quan**: khi bot chạy fallback Muse (OpenRouter), context window có thể khác Sol 6.1 → theo dõi compaction lúc chạy fallback. Ảnh hưởng cả 1.1.1 lẫn 1.2.0.
- PR #1259 MERGED 20/10: giữ summary để thử lại khi OpenClaw reload runtime. Chưa rõ đã vào 1.2.0 chưa (UNVERIFIED).

## 4. Gate sang Pha 1/2

- Tới **≥24/10** chưa có issue regression 1.2.0 nghiêm trọng (ingest dừng, duplicate, migration lỗi) → làm tiếp.
- Rehearsal (clone Hungreo trên 9.33 với đúng live-gates patch) phải đo được: thời gian và RAM đỉnh lúc migrate lần đầu, số gaps, messages trước/sau (không nhập lại lịch sử), compaction và recall chạy, restart giữ cursor, rollback 1.1.1 trên DB đã migrate chạy được.
- RAM: clone gateway cần khoảng 1,2–1,5 GiB trong khi available 2,7 GiB → chạy rehearsal ngoài giờ job, transport và cron OFF, có giới hạn thời gian, dừng ngay khi xong.
