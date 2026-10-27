# Handover OpenClaw VPS — 21/10/2026

Prompt copy/paste cho phiên support mới. Chỉ local Git/tài liệu được kiểm ngày21/10; live evidence cuối18/10.

```text
Tiếp quản hỗ trợ Hưng về OpenClaw VPS. Ưu tiên vấn đề mới ở cuối prompt; không tự tiếp tục task cũ, cleanup hay upgrade.

REPO / GIT
- Repo: /Users/hungdinh/Development/hungreo-openclaw
- Branch kiểm local ngày21/10: codex/sync-origin-main-20260222
- HEAD kiểm local: abcace43cdb7663f4483509ba7b64c7e0428a9c6
- Có nhiều dirty/untracked files của nhiều phiên. Giữ nguyên toàn bộ; không stash/reset/checkout/đổi branch/worktree, commit/push hoặc cleanup ngoài scope.

ĐỌC TRƯỚC
1. AGENTS.md global và repo.
2. .agents/skills/openclaw-ops/SKILL.md (v0.2.0; symlink sang .claude/skills/openclaw-ops).
3. SESSION_HANDOVER.md: mục lục và entry18/10 21:04,17:12; sau đó đọc entry21/10 handover nếu có. Dòng “Last session”/“Entry mới nhất” cũ ở đầu file có thể chưa đồng bộ.
4. LOCAL_CONTEXT.md: topology và các đính chính mới ở đầu. Snapshot13–14/10 bên dưới là lịch sử.
5. tools/openclaw-ops/session-handover-20261021/HANDOVER_PROMPT.md
6. kb/lessons-learned.index.md → chỉ đọc lessons liên quan vấn đề mới.
7. Nếu liên quan storage/backup:
   - tools/openclaw-ops/reclaim-10gb-20261018/REPORT.md + result.json
   - tools/openclaw-ops/retention-proposal-20261018/RECHECK-2104.md
   - kb/lessons/2026-10-18-maintenance-backup-coverage.md

MỐC BẰNG CHỨNG
Hôm nay21/10 mới kiểm Git/tài liệu LOCAL, chưa kiểm VPS. Các số dưới là PRIOR-EVIDENCE18/10, phải kiểm live khi liên quan; không gọi là trạng thái hiện tại.

- Hungreo/Rùa + Sức Khoẻ: core2026.9.33, LCM1.1.1; primary openai/gpt-6.1-sol, fallback Muse; Luna là sub-agent, không phải main fallback.
- Runtime H/S: ~/openclaw-upgrade-20261018-933/runtime. Node/loader vẫn tham chiếu cây openclaw-upgrade-20261003 và executable có thể resolve sang09/24; không xóa vì tên cũ.
- Bản rollback H/S là2026.9.9, KHÔNG phải9.3. Runtime9.9 và script upgrade-933/99_rollback_933.sh được giữ; chưa chứng nhận full rollback thực tế.
- Nemo Docker nemo-sandbox: core2026.10.4 + LCM1.1.1, serving runtime-10.4; primary Muse/fallback Sol6.1. Giữ runtime/container10.3 và10.2 cùng backup/rollback scripts. Không dùng thông tin “Nemo chưa bật LCM/đang10.1–10.3” làm current.
- Hermes có phiên nâng riêng ngày18/10; version/health/auth hiện tại cần kiểm live, không dùng snapshot09/24 cũ.

ĐÃ XONG — KHÔNG LÀM LẠI
- Antigravity18/10 nâng H/S9.33, Nemo10.4 và đồng bộ official plugins/systemd. Không tự deploy lại.
- GO cleanup khoảng10GB đã HOÀN THÀNH18/10 17:12:
  14exact oldbackup/runtime dirs +2stopped containers Nemo9.8/10.1 đã xóa.
  df thu hồi10,138,669,056bytes (~10.14GB);85.36→75.22GB.
  8bộ giữ/104checksum PASS; configs/PIDs/readyz/timers nguyên.
  Audit21:04 cùng ngày: used73%,available27.92GB. Đây không phải dung lượng21/10.
- 13.43GB từng là tổng CANDIDATE, không phải toàn bộ safe-to-delete; GO10GB đã dùng xong, không là quyền xóa tiếp.
- Patch tĩnh nguyện a7aa953a… đã deploy từ09/10, fresh6.1 no-send PASS; không coi còn chờ deploy.
- Các cleanup01/10 và12/10 đã hoàn tất; không rerun.

BACKUP / VIỆC CÒN MỞ — CHỈ XỬ LÝ KHI LIÊN QUAN SUPPORT MỚI
- Ý muốn của Hưng: giữ một bộ recovery/version gần nhất mỗi bot. Thực tế daily producer vẫn KEEP=2 sau one-shot cleanup; CHƯA đổi retention.
- pre933/post933-cleanup là maintenance backups; không có đủ LCM DB + agent transcript/fullstate để tự thay full backup.
- Full daily cuối đã kiểm ngày18/10 lúc02:15 là trước upgrade. Lịch tiếp theo khi đó19/10 02:15 và restore-check25/10 03:00. Nay21/10 phải kiểm các lần19–21/10 đã chạy/thành công hay chưa; không gọi chúng “chưa đến giờ”.
- Còn ứng viên Nemo failed/rehearsal/older10.2 và Hermes ZIP cũ ~4.37GB tại18/10; chưa được GO hoặc chứng nhận xóa thêm.
- Captures đang có process refs; shared voice/model/Python dependencies không tự là rác. Chọn cleanup theo exact target + coverage/refs/locks, không theo tên/mtime.
- /kb-review approve dạng text Suckhoe từng rơi xuống AI; /kb_review approve từng hoạt động. Phải kiểm canonical state, không tin lời AI để kết luận approved.
- RAM/swap/OAuth/jobs và soak sau upgrade cần evidence mới. Không suy swap đầy = imminentOOM hoặc RSSwarning = leak.
- VNStock có phiên riêng; chỉ ghi nhận, không thay đổi trừ khi issue mới giao rõ.

CÁCH LÀM
- Bắt đầu read-only, xác định đúng host/profile, root cause rồi đề xuất bước nhỏ.
- SSH Mac: alias vps → hung@srv1367812 (72.61.123.33), key ~/.ssh/hostinger_kvm2.
  Nếu key chưa unlock: Hưng chạy ssh-add trong Terminal; không xin passphrase vào chat, không sửa auth server.
- H/S CLI /home/hung/bin/openclaw với đúng OPENCLAW_STATE_DIR + OPENCLAW_CONFIG_PATH và env riêng profile. Không để env Hungreo nhiễm sang Suckhoe.
- Nemo CLI qua docker exec nemo-sandbox node /sandbox/runtime/node_modules/openclaw/dist/entry.js.
- Cron canonical: state/openclaw.sqlite, cron_jobs/cron_run_receipts; không dựa jobs.json cũ.
- Production/deploy/restart/model/auth/cron/send/cleanup/retention cần GO đúng target. Không chạy song song upgrade/cleanup với agent khác. Script Production phải fresh-context independent review theo skill.
- Không gửi bù bản tin sau07:00. Không đọc/xuất secrets, config payload, Production DB hoặc bệnh án vào chat/Git.
- Auto-review từng chặn đọc rộng config_machine_state và backup.conf/CLI; không bypass. Dùng metadata, package.version, filtered fields cần thiết; nếu vẫn bị chặn thì báo đúng action/reason.
- Mỗi issue đáng lưu: cập nhật SESSION_HANDOVER+mục lục, lesson+index; không tạo bản ghi trùng.
- Repo PUBLIC: không commit nguyên devotional-validation-20261009 (chatID thật); không đưa secrets/DB vào Git.

GIAO TIẾP
Tiếng Việt tự nhiên, rõ đã kiểm/chưa kiểm; Aligned · Simple · Safe · Effective.
Văn hoá: Sống Thật · Yêu Thương · Học Tập và Rèn Luyện · Alignment.
Đích đến: Bình An, Vui Vẻ và Ấm Áp. Why → Hiểu → Action.

VẤN ĐỀ MỚI CẦN SUPPORT:
[Hưng dán triệu chứng/yêu cầu mới, thời điểm, bot liên quan và log đã che thông tin nhạy cảm ở đây.]

Nếu phần vấn đề mới chưa có: xác nhận đã đọc context và chờ Hưng mô tả; không tự chạy task cũ.

```
