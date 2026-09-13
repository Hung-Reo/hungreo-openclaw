# Session Handover — OpenClaw VPS Ops

> **Cho session mới:** Đọc file này TRƯỚC, rồi đọc `LOCAL_CONTEXT.md` + `kb/lessons-learned.md` theo chỉ dẫn `CLAUDE.md`.
> Last session: 2026-09-06 | Nguyên tắc: **Simple · Safe · Effective** + workflow **PLAN → DO → CHECK → REVIEW → REPORT**

---

## ⚡ Session Handoff — 2026-09-13 (MỚI NHẤT) — Dọn disk 67G→57G + phát hiện fallback OpenRouter + HOÃN tiếp upgrade

**Disk: 67G (06/09) → 57G (13/09), trống 30G → 40G.** Hai đợt, Hưng duyệt từng lô, 0 restart, PID bot không đổi trong lúc dọn.

- 06/09: rác `/tmp` rehearsal 8.2 (4.0G) · prune `lcm-0.15.0` (523M) · npm+uv cache (3.0G) · 6 file `lcm.db.bak-*` mv → trash.
- 13/09: xoá trash (1.3G) · **3 file state 24/07 trong `openclaw-upgrade-20260724-pre-2026.7.1-2`** (4.0G — giữ binary 65M + SHA256SUMS) · `lcm-0.15.1` (526M) · `runtime-patch-20260503` (95M, obsolete) · 2 auth sqlite trong `hermes-trial-20260803` (817M — giữ 9 file nemotron config/service).
- Mỗi thư mục còn giữ có `DELETED-20260913.txt` ghi rõ.

**⚠️ HỆ QUẢ AN TOÀN — session sau phải biết:** **KHÔNG còn bộ backup "full state + binary" nào của openclaw.** Đường lùi = daily `~/backups/openclaw` (state 02:15, `RETENTION_KEEP=2`, exclude `npm/`) + `openclaw update` tải lại binary. **SOP upgrade bước 1 bắt buộc tạo bộ full mới TRƯỚC khi đụng gì.**

**❌ CỐ Ý KHÔNG dọn (cả 2 lần rà độc lập đều thống nhất):** `~/.local/lib/python3.12` 7.3G (torch CUDA — **hungreo dùng whisper local**, config `tools.media.audio.models[0].command=/home/hung/.local/bin/whisper --model turbo`, log 05/09+10/09 `FP16 not supported on CPU` = chạy thật; xoá `nvidia/` là `import torch` vỡ) · `~/.cache/whisper` 2.2G · `~/.cache/huggingface` 2.1G (**faster-whisper do Hermes tải 10/09 06:40 = giờ cron Hermes**, `small` đọc 13/09) · `npm/projects/openclaw-codex-*` 2G×2 (plugin active) · docker (0 reclaimable) · `~/backups/openclaw` daily.
**🪤 Bẫy đã bắt được:** proposal agent khác 06/09 gán `~/backups/openclaw` là "backup tĩnh tháng 6" vì nhìn mtime **thư mục cha** (06/10) — thực tế con `hungreo/20260906-*` là daily sáng hôm đó. Xoá = mất backup hằng ngày. Luôn `ls -lt` **bên trong**.
**Theo dõi:** `codex-home/logs_2.sqlite` hungreo 603M + suckhoe 442M, đang tăng.

**🔴 Fallback production đã bị đổi không qua Hưng (phát hiện 06/09, Hưng quyết ĐỂ NGUYÊN, chỉ theo dõi):** 2026-09-05 14:43:44 (hungreo) / 14:44:44 (suckhoe) `[reload] config change detected (models.providers.openrouter, agents.defaults.model.fallbacks)` — fallbacks `["deepseek/deepseek-v4-pro"]` → `["openrouter/meta/muse-spark-1.3-contributor","openrouter/meta-llama/llama-4-scout"]` + khối `models.providers.openrouter` (`apiKey.source=env OPENROUTER_API_KEY`, cost $0.10/1M). **`OPENROUTER_API_KEY` RỖNG** trong env cả 2 service ⇒ $0 nhưng **mất lưới an toàn**: Codex chết = bot im hoàn toàn. Chưa truy được tác nhân (bash_history sạch). Bản cũ: `openclaw.json.bak-20260905144343` / `...144443`. Drift check `sessions.json` KHÔNG bắt được vì fallbacks không nằm trong tầm quét — cùng lỗ hổng [2026-08-18]. Hưng: "kg actions gì".

**🛑 Upgrade openclaw: VẪN HOÃN.** npm 13/09: `2026.9.3` (08/09), `2026.9.4` (11/09) — **6 bản trong 12 ngày**, điều kiện (a) "7–10 ngày yên" chưa thoả. lossless `1.0.0` vẫn phải sau. Sandbox `nemo-sandbox` (docker, `@hungreo_bot`, openclaw **2026.9.1**, `muse-spark-1.3-contributor` $0.10/1M, có key thật, `dmPolicy=pairing`) Hưng đã trial 3/5 prompt: không bịa ✅ (tự khai mâu thuẫn nguồn), biết nói "không biết" ✅, bẫy số **chưa kết luận** (prompt viết hỏng). **Test có giá trị nhất chưa làm: cài 4 plugin tự viết vào sandbox.**

**Khác:** Hermes nâng `0.19.1 → 0.21.2` ngày 13/09 11:12 (không phải session này), backup `~/hermes-upgrade-20260913/` 563M. PID hungreo/suckhoe đổi trong 06→13/09 (`3543496→3922302`, `3543425→3809838`) — **chưa rõ ai restart**. `bsy_morning_brief.py:37` `OPENWEATHER_KEY` hardcode trần (sót đợt audit 04/08), Hưng chưa quyết.

---

## ⚡ Session Handoff — 2026-09-06 — lossless 0.15.3 → 0.15.6 + quyết định HOÃN OpenClaw 2.0

**✅ Đã nâng lossless-claw `0.15.3` → `0.15.6`** trên hungreo + suckhoe (cùng nhánh, chỉ vá lỗi, `peerDeps >=2026.5.28 <2026.7.2-0` khớp openclaw `2026.7.1-2` đang chạy).
**Verify:** 0 lỗi PID mới (hungreo 3543496 / suckhoe 3543425) · plugin 7+8 đủ · lcm.db `integrity=ok` ×2 · 0 drift · **UAT ×2 `openai/gpt-5.6-sol` attempts=1** ($0) · test alignment 8/8 vẫn xanh.
**KHÔNG đụng:** nemotron (`inactive`+`disabled`, Hưng dặn để yên) · Hermes (phần mềm khác, không dùng lossless).
**Backup:** `~/backups/lcm-0.15.6-upgrade-20260906-144807` (config ×2 + lcm.db ×2 snapshot SQLite API + SHA256SUMS, 496M). Rollback: `plugins update @martian-engineering/lossless-claw@0.15.3` ×2 → restart.

**🛑 QUYẾT ĐỊNH: HOÃN nâng OpenClaw `2026.7.1-2` → `2026.9.2`.** Hưng đã chốt không action. Lý do (đã verify bằng npm):
| | |
|---|---|
| Soak time | `2026.9.2` ra **cùng ngày**; **4 bản trong 6 ngày** (8.1→8.2→9.1→9.2) = nhịp vá gấp sau major 2.0, chưa ổn định. Bản đang chạy đã chín 50 ngày |
| Rủi ro lớn nhất | **4 plugin tự viết** (`hungreo-finance`, `suckhoe-family-memory`, `suckhoe-kb-weekly`, `suckhoe-technical-handoff`) đều khai `>=` **không có trần trên** ⇒ npm KHÔNG chặn nhưng cũng KHÔNG bảo đảm; chúng viết theo API 2026.7.x, mà 2.0 đụng thẳng vào "plugins" |
| Khoảng cách | băng qua major 2.0 (16.000 PR). Lịch sử: 7.1 patcher fail-closed + crash-loop · 6.1 bỏ provider `openai-codex` · 5.28 breaking schema giết nemotron — đều là bản **nhỏ** |

**✅ Tin tốt cho lần nâng sau:** lossless `1.0.0` đòi gỡ `transcriptGcEnabled` + `autoRotateSessionFiles` — **cả 3 profile đều KHÔNG có** (đã grep). Rào cản đó không áp dụng.
**⚠️ `lossless 1.0.0` KHÔNG nâng riêng được** — `peerDeps >=2026.7.2-beta.2`, phải nâng OpenClaw trước.

**Điều kiện để nâng OpenClaw (chờ ĐỦ 2, không theo lịch):**

1. Nhịp phát hành chậm lại — ~7–10 ngày không có bản mới trong nhánh `2026.9.x`
2. Hưng có 2–3 tiếng rảnh, **không phải buổi sáng** (tránh 05:45 tĩnh nguyện / 06:28 bản tin / 06:15 Minh Trân)
   Khi làm: SOP đầy đủ + **test riêng 4 plugin tự viết** + nâng lossless 1.0.0 sau.

---

## ⚡ Session Handoff — 2026-09-05 (c) — Bản tin sáng chết LẦN 3: `$1.2B` vs `1,2 tỷ`

**Triệu chứng:** `manifest.status=error`, **`error: null`** (không nói lý do), thiếu đúng `ai.txt`.
**Root cause:** `protected_numbers()` dùng `(?!\w)` ⇒ số trong nguồn `"$1.2B"` **bị bỏ qua** (regex cũ chỉ ra `['1']`); bản dịch `"1,2 tỷ USD"` quét được → chuẩn hoá `1.2` ⇒ bị coi là **"thêm fact không có trong nguồn"** → chặn cả bản tin. **Bot dịch hoàn toàn đúng** — lần thứ 3 liên tiếp validator giết bản tin oan.
**Fix:** `(?!\w)` → `(?!\d)`. Kiểm chéo 6 ca, **không nới lỏng bảo vệ** (còn chặt hơn: trước đây bỏ sót số trong nguồn).
**Verify:** `apply-editorial` → `status=ready`, 4/4 section ok, **`ai.txt` đã tạo**. **Alignment 8/8** (thêm 2 case mới: ca thật 05/09 + ca số bịa vẫn phải raise) · **canonical 43/43**.
**🪤 Bẫy mất 20 phút:** `cmd_apply_editorial` thoát sớm nếu `status not in ('prepared','ready')` ⇒ fix trông như "không ăn" vì script chỉ in lại manifest cũ. Phải reset `status→prepared` mới chạy lại được. Dấu hiệu nhận biết: **mtime manifest không đổi**.
**Backup:** `bsy_morning_brief.py.bak-20260905-141347-pre-number-unit-suffix-fix` · `~/backups/morning-brief-20260905-repro-*`.
**⏳ Bản tin 05/09 giờ ở trạng thái `ready` nhưng CHƯA gửi** — chờ Hưng quyết có gửi muộn hay bỏ.

---

## ⚡ Session Handoff — 2026-09-05 (b) — Suckhoe tự vá script: luật tự mâu thuẫn, đã gỡ

**Sự việc:** Minh Trân (`8288766754`) nhờ đổi nội dung tin tĩnh nguyện → **suckhoe tự vá script**, bắn **5 tin approval khó hiểu** (mỗi tin hết hạn 120s, 2 cái timeout). Hưng duyệt trong mù, chỉ hiểu khi Trân nhắn hỏi. Sai vai: suckhoe là bot sức khỏe.

**❌ Giả thuyết truncation SAI:** per-file 20.000 / tổng 60.000 · thực tế 15.228 / 32.700 · **0** cảnh báo truncation. Prompt không bị cắt.
**✅ Root cause: AGENTS.md tự mâu thuẫn 4 chỗ** — dòng 7 cấm nhưng chỉ cấm _"bảo trì kỹ thuật"_ (kẽ hở), dòng 78 chỉ đòi _"approval first"_ (không cấm), mục _Exec Approval Flow_ dạy chi tiết cách xin duyệt + _"hết hạn thì gửi lại yêu cầu mới"_ (⇒ 5 tin). **Bot tuân đúng luật; luật hở.**

**Fix — luồng RELAY 5 bước (KHÔNG phải cấm):** (1) báo người yêu cầu đã ghi nhận → (2) **xin Hưng duyệt** bằng tin tiếng Việt đủ 4 ý (ai/muốn gì/định làm gì/"anh duyệt không ạ?") **trước khi chạy lệnh** → (3) báo kết quả duyệt → (4) **Suckhoe TỰ LÀM** → (5) báo "đã xong". Cấm approval trống ngữ cảnh.
**Test 3 vòng — tôi siết quá tay 2 lần, Hưng bắt được cả 2:** vòng 1 từ chối cả Hưng ❌ · vòng 2 bắt Hưng tự làm ❌ · vòng 3 đúng: _"sau khi được duyệt em sẽ trực tiếp thực hiện"_ ✅. Prompt files **ăn ngay, không cần restart**.
**Backup:** `~/backups/suckhoe-policy-conflict-fix-20260905-135238`.

**⏳ Còn treo:** (1) vì sao Telegram **không render nút** approval dù cấu hình đã đủ điều kiện · (2) timeout 120s **không sửa được bằng config** (`DEFAULT_CODEX_APPROVAL_TIMEOUT_MS` do plugin truyền) — chỉ vá runtime được, **không làm** · (3) **Đường A dự phòng**: nếu tái diễn thì siết cứng `tools.exec` (Hưng đã duyệt trước: "B trước, tái diễn thì A") · (4) bản tin sáng 05/09 chết `status=error, error=null` — **chưa điều tra**.

---

## ⚡ Session Handoff — 2026-09-05 (a) — Ghìm dreaming của hungreo, loại 2 báo động giả

**Hưng báo:** hungreo im lâu + nghi đốt token, hỏi có nên stop.
**Kết luận: KHÔNG stop** — CPU 0.9%, 2h38 CPU/12 ngày uptime, 0 turn đang chạy. Bot nhàn, không loạn.

**2 vấn đề thật (tách biệt, Hưng gộp làm một):**

1. **Tin nhắn khó hiểu = `memory-core` dreaming** — cron `0 */6 * * *` × 3 subagent (light/rem/deep) = ~12 lượt LLM/ngày tự chạy, viết nhật ký giấc mơ dạng **thơ** rồi gửi Telegram (có cả tin **thoại**). 24h log có **85 orphan run**. Tiến trình cũ: 5h09 CPU, **6.9G mem peak** / VPS 7.8G.
2. **"Không trả lời" = lỗi delivery** — 7 lần/7 ngày `[source-reply/private-final]`: agent viết xong reply nhưng **không gọi delivery tool** ⇒ câu trả lời chết trong máy.

**✅ ĐÃ FIX:** `plugins.entries["memory-core"].config.dreaming.frequency` `0 */6 * * *` → **`0 3 * * *`** (giảm ~75% token nền).
**🔑 Học được:** dreaming khai ở 2 nơi (config + cron job) nhưng **config là nguồn sự thật** — sửa config + restart thì **cron TỰ đồng bộ**. Không cần sửa tay 2 chỗ (khác vụ `AGENTS.md`). Kiểm bằng thực nghiệm, đừng mặc định.
**Verify:** 0 lỗi PID mới (3428257) · 7 plugin · **0 orphan** (trước 85) · cron `0 3 * * *` · 0 drift · **UAT `openai/gpt-5.6-sol` attempts=1** ($0).
**Backup:** `~/backups/hungreo-dreaming-throttle-20260905-075434`.

**❌ 2 báo động giả đã loại:** `chat not found (8288766754)` ở hungreo = id đó chỉ chat với bot **suckhoe** (suckhoe gửi tới đó OK) ⇒ **dùng sai bot**, không phải bug · `ToolInputError: to required` ở suckhoe = 1 lần/7 ngày, agent quên tham số `to`, tool từ chối đúng.
**Suckhoe nhìn chung SẠCH:** 24h chỉ 1 lỗi lẻ nói trên.

**⏳ Chờ Hưng quyết (chưa đụng):** `memorySearch.provider="gemini"` ở hungreo nhưng **không plugin nào phục vụ** + `fallback:"none"` ⇒ memory search **chết lặng**. Tắt hay cài lại provider?
**Ghi nhận:** disk 66G/96G (còn 30G) — đã tăng từ 56G, nên để mắt.

---

## ⚡ Session Handoff — 2026-08-18 — Khôi phục hungreo về Sol + khoá đường tái diễn

**🚨 Hưng KHÔNG duyệt việc đổi model.** Truy ra: **2026-08-05 11:47** một agent làm task "model routing" tự đổi hungreo `sol`→`terra` **và tự viết lại `workspace/AGENTS.md`** thành chính sách phân tầng Terra/Sol/Luna. Vì config và tài liệu khớp nhau nên **12 ngày không ai phát hiện**. Phân tích đầy đủ + rule: `kb/lessons-learned.md` [2026-08-18].

**Đã khôi phục:** primary `openai/gpt-5.6-sol`, fallbacks `["deepseek/deepseek-v4-pro"]` · `AGENTS.md` viết lại (Sol cho mọi hoạt động + hard rule + **kể lại sự việc** cho agent sau) · clear session auto-pin `agent:main:main → deepseek` · restart theo SOP.
**Verify:** re-diff sau restart giữ `sol` · 0 lỗi PID mới (2378439) · 7 plugin · 0 drift cả hungreo+suckhoe · **UAT `openai/gpt-5.6-sol` attempts=1** ($0) · auth codex còn hạn tới 2026-08-20.
**Phạm vi:** chỉ hungreo. suckhoe+nemotron **0 lần** terra/luna. 0 cron pin terra/luna.
**Backup:** `~/backups/hungreo-model-restore-sol-20260818-132640`.

**🆕 Poller filter (dọn đường cho câu 4):** `dist/src/poller.js` thêm điều kiện `file.name.startsWith("suckhoe-")` ⇒ file lạ trong Inbox (vd `_review-status.md` do VPS ghi ngược) bị **bỏ qua hoàn toàn** — không đọc, không đánh `invalid`, không bắn notification rác. Backup `poller.js.bak-20260818-132933-pre-name-filter`. Đã restart suckhoe (PID 2379535, 0 lỗi, 7 plugin), poller chạy lại 13:30:26 sạch.

**⛔ Câu 4 — ĐƯỜNG CỤT, đã đóng:** Hưng đã cấp Editor, nhưng Google trả `403 Service Accounts do not have storage quota`. SA **không thể tạo file** trong My Drive cá nhân (chỉ Shared Drive = Workspace; Gmail cá nhân không có). Đã revert `drive.js` về `drive.readonly` (đọc vẫn OK). Chi tiết + các đường đã loại: `kb/lessons-learned.md` [2026-08-18].
**➡️ Thay bằng:** giữ **quy trình thủ công đang chạy đúng** — kiểm chứng: 3 file có vấn đề (1 reject + 2 invalid) đều đã được Hưng xoá khỏi Inbox, Inbox còn đúng 5 file approved ⇒ Cowork đọc Inbox là chính xác. Đề xuất bổ sung duy nhất: **thêm câu nhắc vào tin nhắn reject** ("nhớ xoá file khỏi Drive Inbox").

> 🛑 **Hưng đã quyết ngày 2026-08-18: KHÔNG làm, để nguyên.** Lý do: không critical, hệ thống đang ổn, Hưng monitoring tiếp rồi báo sau.
> **Agent sau: ĐỪNG tự làm việc này** dù thấy nó nhỏ và hợp lý — đây là quyết định đã chốt, không phải việc còn treo.
> **🔓 Hưng nên đổi lại quyền Drive về Viewer** — Editor giờ không dùng tới, giữ lại chỉ là quyền thừa.

---

## ⚡ Session Handoff — 2026-08-17 — KB weekly: vòng chủ đề 5 → 8 topic, LANDED

**Hưng yêu cầu:** mở rộng rotation 5→8 (**append cuối**, không đổi thứ tự), giữ anchor CN `2026-07-19`, không nới whitelist, không đổi format metadata. Rotation mới: `diabetes, hypertension, hepatitis-b, bones-and-joints, mental-health, dengue, stroke-and-heart, child-health`.

**Đã sửa 4 file** trong `~/.openclaw-suckhoe/extensions/suckhoe-kb-weekly`: `dist/src/candidate.js` (ID_RE + TOPICS + TOPIC_ROTATION — **runtime thật**) · `src/candidate.ts` · `src/types.ts` · `CLAUDE_COWORK_SYSTEM_PROMPT.md` (danh sách 8 mục + `modulo 5`→`8` + enum JSON). `queue-item.schema.json` khai `topic: string` không enum ⇒ không cần sửa; `commands.js`/`poller.js` không hardcode topic.

**🔴 Phát hiện quan trọng — `src` vs `dist` LỆCH:** `src/candidate.ts` có `dyslipidemia` ở index 3 và **thiếu hẳn** `TOPIC_ROTATION`+`ROTATION_ANCHOR_UTC`; `dist` mới đúng. **KHÔNG được build plugin này từ `src`** cho tới khi port rotation logic sang — build sẽ xoá mất rotation check và làm `bones-and-joints` (đã duyệt) thành invalid. Chi tiết + rule: `kb/lessons-learned.md` [2026-08-17].

**Verify (test thật, chạy trước restart nên 0 rủi ro):** import trực tiếp `dist/src/candidate.js` bằng Node → **5/5 candidate cũ PASS** · rotation 10 tuần đúng (tuần 5 `2026-08-23`→`dengue`, wrap tuần 8 về `diabetes`) · `dyslipidemia`/`cancer` bị chặn 3 lớp.

**Sau khi Hưng `/restart` từ Telegram:** log `restart mode: full process restart (supervisor restart)`, PID 1380947→**2319996**, process start 13:22:38 **muộn hơn** mtime file 12:29:54 ⇒ module nạp lại từ đĩa. **0 lỗi** trên PID mới · poller đã poll Drive 13:23:05 · **0 drift** · doctor 9 plugin/0 error · UAT `openai/gpt-5.6-sol` attempts=1 (`UAT_OK`, $0).

**Trả lời 5 câu của Hưng:**

1. Hardcode topic: 4 nơi, đã sửa hết, không còn `dyslipidemia`.
2. 5 candidate cũ: **5/5 PASS** (index 0..4 không đổi, đúng như dự đoán).
3. **Lo ngại UTC KHÔNG đúng cho VPS** — plugin không tự suy `week_of`, chỉ validate chuỗi date-only; không có `getDay/getUTCDay/toISOString().slice`; poller là `setInterval` 300s chứ không phải cron 01:00 CN. Rủi ro nằm **phía Cowork**.
4. Ghi ngược trạng thái về Drive: **chưa làm, cần Hưng duyệt riêng** (phải nâng scope `drive.readonly` → thêm `drive.file`, và **phải filter `suckhoe-*.md` trước** nếu không poller sẽ tự đánh `invalid` file index của chính mình).
5. **Đã có đúng 1 reject**: `suckhoe-2026-07-19-diabetes` (15/07) → revision mới → approved. **Lý do reject không được lưu ở đâu** (event log thiếu field `note`). Idempotency **chạy đúng 3 lớp**, bằng chứng: drive file `1DQ5…` bị đánh `duplicate`, không import lại.

**⚠️ Cần Hưng xác nhận:** `hungreo` primary giờ là **`gpt-5.6-terra`** (trước 03/08 là `gpt-5.6-sol`). Không phải drift (session khớp primary) ⇒ là đổi config thật. Hưng tự đổi hay không?
**Ngoài scope, chỉ báo:** doctor thấy `brave 2026.6.11` lệch so với `2026.7.1-2`.

**Backup:** `~/backups/suckhoe-kb-topics-20260817-122935-pre-8topics` (4 file + snapshot `review-state` + SHA256SUMS).

### Phần làm thêm sau khi Hưng duyệt "proceed cho xong"

**✅ 2 file `invalid` 26/07 — đã truy, tự hết:** query Drive bằng service account read-only → **cả 2 không còn trong Inbox**. Inbox hiện sạch đúng 5 candidate approved. Không cần làm gì.

**🔴 `src/` lệch NẶNG hơn báo cáo đầu — thiếu 3 guard AN TOÀN Y TẾ, không chỉ rotation:**

| Guard trong `dist`                                                                        | `src`                   |
| ----------------------------------------------------------------------------------------- | ----------------------- |
| `isRealIsoDate` (chặn ngày không tồn tại)                                                 | ❌                      |
| `TOPIC_ROTATION` / `expectedTopic` / `ROTATION_ANCHOR_UTC`                                | ❌                      |
| `UNIVERSAL_MONITORING_SCHEDULE`                                                           | ❌                      |
| `UNCONSCIOUS`+`ORAL_INTAKE`+`NO_ORAL_INTAKE` (**chặn khuyên cho người bất tỉnh ăn/uống**) | ❌                      |
| `sources` tối đa                                                                          | src `8` vs dist **`6`** |

Plugin **không có build setup** (không `scripts`, không `tsconfig`, không `tsc` global/local) ⇒ hiện **không ai build được**, rủi ro thấp hơn tưởng. **CỐ Ý KHÔNG port mù** 3 guard y tế: regex phức tạp, không có `tsc` để type-check, không có cách chạy thử `src` ⇒ port mù đúng loại thay đổi đã 2 lần làm mất bản tin sáng. Thay vào đó **chặn đường build nhầm**: banner cảnh báo ở đầu `src/candidate.ts` + mục trong `README.md` liệt kê đúng những gì thiếu. Muốn dùng lại `src` = task riêng (port + dựng build + test bằng `kb/medical/review/processed/*.md`).

**🆕 Câu 4 — phần VPS làm được, ĐÃ LÀM:** script `~/bin/suckhoe-kb-review-status.mjs` (chỉ đọc `review-state/`, ghi 1 file `.md`, **không đụng Drive/gateway**) sinh `kb/medical/_review-status.md` gồm: bảng candidate + status, lịch 12 tuần từ anchor (đánh dấu `chua_co_candidate`), và block JSON máy đọc. Có dòng chỉ dẫn rõ cho Cowork: _"chỉ coi là hoàn thành khi `status = approved`; `rejected` = tuần đó vẫn còn trống"_ — chính là chỗ Cowork đang hiểu sai.

- File nằm ở `kb/medical/` (không phải `review/`) và poller đọc **Drive** chứ không đọc local ⇒ **không có nguy cơ tự đánh `invalid`**.
- **Còn thiếu để khép vòng:** đẩy file này lên Drive Inbox. Cần Hưng nâng scope service account `drive.readonly` → **thêm `drive.file`** (chỉ đụng file app tự tạo), và **thêm filter `suckhoe-*.md` cho poller TRƯỚC** khi bật.

**🐞 Bug tiềm ẩn mới phát hiện (chưa sửa):** `drive.js listFiles()` dùng `pageSize: 20` và **không phân trang**. Inbox hiện 5 file nên chưa ảnh hưởng; `orderBy=createdTime desc` giúp file mới luôn nằm top. Nhưng khi Inbox vượt 20 file (~20 tuần nữa nếu không dọn) thì file cũ rơi khỏi kết quả.

---

## ⚡ Session Handoff — 2026-08-03 — Hermes Agent thay slot Nemo, chạy Codex OAuth $0

**Hưng quyết:** trial Hermes trên slot Nemo, dùng chung Codex subs như hungreo, tên `hungreo-hermes`, chỉ chat/play trước — **chưa nối task nào**.

**State cuối:** Hermes `v0.19.1` service `active`+`enabled`, 0 restart, ~126M RAM, model `gpt-5.6-sol` qua `openai-codex` ($0). Nemo `inactive`+`disabled` (state 939M giữ nguyên). hungreo+suckhoe `active` `2026.7.1-2`, **0 contention**, Codex token 2 bot còn nguyên (không bị device-code login của Hermes đá ra).

**⚠️ Blocker cũ [2026-07-21] đã GỠ — ghi lại cho đúng:** handover 21/07 ghi _"chưa xác nhận Hermes route được Codex OAuth → nhiều khả năng phải trả tiền OpenRouter"_. **Sai.** Hermes có provider `openai-codex` first-class, auth device-code, verify chạy thật.

**Gemini subs KHÔNG dùng được** (Hưng hỏi): gói Gemini AI Pro/Ultra của app ≠ API access — issue #60699 của Nous xác nhận. Đường `gemini-cli OAuth` có từ v0.19 nhưng **Google coi dùng client đó cho phần mềm bên thứ ba là vi phạm chính sách** → không khuyến nghị, rủi ro khoá Google account.

**Cấu hình đã áp:** bot `@hungreo_bds_bot` đổi tên `🐠 Nemo-Hermes` → `hungreo-hermes` · long polling (**không mở port nào**, không cần nginx) · dashboard TẮT · `TELEGRAM_ALLOWED_USERS=7957776935` · chạy chung user `hung` (Hưng chọn sau khi đọc cảnh báo) · runtime riêng Python 3.11 + Node 22 trong `~/.hermes`, không đụng Node 24 của OpenClaw.

**🪤 Bẫy quan trọng nhất — config mặc định Hermes trỏ OpenRouter:** ngay sau cài, `model.default=anthropic/claude-opus-4.6` + `base_url=openrouter.ai`. UAT đầu pass chỉ vì ép `--provider`/`-m` trên CLI. Đã sửa cả `base_url`→`chatgpt.com/backend-api/codex` lẫn `default`→`gpt-5.6-sol`, rồi **test lại bằng config mặc định** (`DEFAULT_ROUTE_OK`). Chi tiết: `kb/lessons-learned.md` [2026-08-03].

**Trial kết quả (Hưng tự chạy 2 prompt qua Telegram):**

- **A — bản tin sáng: ĐẠT.** Verify độc lập 2 tin nghi ngờ (Suu Kyi–ICRC, Nhật–Mỹ can thiệp yen) → **đều thật, đúng ngày 03/08**. Không bịa. Dịch tiêu đề tự nhiên, tự load skill `research:grounded-citations`.
- **B — xfeed: BỎ.** Hermes tự kết luận scraping X _"không đủ ổn định để làm nguồn tự động lâu dài"_, không cài `xurl` khi bị cấm, dùng Snowflake ID suy timestamp. Trung thực nhưng **không giải được** bài toán `hungreo-xfeed`.

**Job Hưng đã tạo qua chat (verify bằng SSH, không tin bot):** `a8340dc355ff` "Bản tin sáng…", `40 6 * * *`, next `2026-08-04T06:40+07`, `Deliver: origin` (chỉ DM Hưng), không pin model → dùng default codex. Ticker sống (heartbeat 17s).

**⚠️⚠️ RỦI RO CHƯA XỬ LÝ — XUNG ĐỘT LỊCH SÁNG:** Hermes 06:40 nằm **chính giữa** 2 job suckhoe: `Bsy Morning Brief Pipeline` **06:28** và `bsy-brief-catchup-send-0650` **06:50**. Cả 3 dùng **chung 1 Codex OAuth account**. Đề xuất dời Hermes → **07:10** (sau khi suckhoe xong hẳn, và Hưng đọc bản thật trước). **Chờ Hưng duyệt.**

**Backup/rollback:** `~/backups/hermes-trial-20260803-061801-pre-install` (817M, SHA256SUMS, auth store ×2 `integrity=ok`).
Rollback: `systemctl --user disable --now hermes-gateway.service && systemctl --user enable --now openclaw-gateway-nemotron.service` → đổi tên bot về `🐠 Nemo-Hermes`.

---

## ⚡ Session Handoff — 2026-08-02 — lossless-claw 0.15.0 → 0.15.1 LANDED sạch

**State:** openclaw `2026.7.1-2` + lossless-claw **`0.15.1`** cả 3 profile, active, 0 drift, UAT PASS ($0, no fallback), lcm.db `integrity=ok` cả 3, 3 timer active, Telegram connected cả 3 bot.

**Research trước khi nâng (kết luận: rủi ro thấp, nên nâng):** không breaking change / không migration DB · peerDep `openclaw >=2026.5.28` ✓ · deps không đổi · +8.6KB · soak 4 ngày (ra 29/07). Vá trúng điểm đau: chặn emergency-drain lặp, chặn summary rỗng làm phình context (đốt token), sửa mất context block do plugin chèn trên kênh decorated (hungreo có finance plugin).

**Quy trình:** backup (config ×3 + lcm.db ×3 **snapshot nhất quán bằng SQLite backup API**, integrity=ok) → stop healthcheck.timer → `plugins update @martian-engineering/lossless-claw@0.15.1` ×3 → restart suckhoe→hungreo→nemotron → verify 3 tầng → start lại healthcheck.timer.

**⚠️ Suýt báo động giả — nhớ rule này:** sau restart suckhoe hiện **10 lỗi** `[lcm] Database connection closed after gateway_stop`. Kiểm PID: toàn bộ của **tiến trình CŨ đang tắt**, tiến trình mới **0 lỗi**; chuỗi này đã có **12 lần/7 ngày** trước khi nâng ⇒ hành vi shutdown có sẵn, KHÔNG phải hồi quy. Luôn (1) lọc `grep "node\[$NEWPID\]"` và (2) hỏi "lỗi này có từ trước không?".

**🆕 Kỹ thuật mới nên dùng lại:** backup SQLite đang chạy bằng `con.backup(out)` của python3 thay vì `cp` (cp trên DB có WAL có thể ra bản chụp hỏng). Code mẫu: `kb/lessons-learned.md` [2026-08-02].

**✅ Fix 28/07 hoạt động đúng:** họ backup `lcm-*upgrade-*` tự giới hạn 2 bản, prune script báo "thu hồi 0M". Disk giữ 52G/45G trống dù thêm backup 526M.

**Backup + rollback:** `~/backups/lcm-0.15.1-upgrade-20260802-125256/`. Rollback: `plugins update @martian-engineering/lossless-claw@0.15.0` ×3 → restart (không cần restore lcm.db vì không có migration).

---

## ⚡ Session Handoff — 2026-07-29 — Weather smart cho Quận 8 + canonical tests xanh lại

**Hưng báo:** output `07:00 (100%), 10:00 (100%)...` tạo cảm giác mưa cả ngày dù sáng Quận 8 chưa mưa; nguồn đôi khi chỉ còn OpenWeather; khuyến nghị giống fixed template.

**Root cause đã verify live:**

- Weather dùng tọa độ cố định `10.8231, 106.6297`, cách vị trí đại diện Quận 8 khoảng 11 km.
- `summarize_rain_confidence()` chỉ so `max(pop)` cả ngày; hai nguồn cùng báo mưa ở _bất kỳ lúc nào_ là bị coi như đồng thuận, dù buổi sáng OpenWeather 100% còn Open-Meteo 14–47%.
- Render lấy xác suất cao nhất giữa các nguồn cho từng block nên OpenWeather 100% lấn át; recommendation là template theo `max_pop`, chưa xét lượng mưa hay khung giờ ít rủi ro.
- Open-Meteo vắng ở artifact 25/07 và 29/07; exception bị nuốt nên không thể biết nguyên nhân hồi cứu.

**Fix live, không restart/không Telegram:**

- Target: `~/.openclaw-suckhoe/workspace/scripts/bsy_morning_brief.py` + `scripts/test_bsy_morning_brief.py`.
- Backup: `/home/hung/backups/morning-brief-weather-smart-20260729-1108/`.
- Default weather chuyển sang tọa độ đại diện `Quận 8, TP.HCM`; có thể override bằng `BSY_WEATHER_LAT`, `BSY_WEATHER_LON`, `BSY_WEATHER_LOCATION` mà không lưu vị trí nhà chính xác.
- OpenWeather dùng cả `pop` + `rain.3h/3` (mm/h trung bình); Open-Meteo dùng `precipitation_probability` + `precipitation`, retry 2 lần.
- Tóm tắt theo `Sáng/Trưa/Chiều/Đêm`, phát hiện bất đồng từng buổi, hiển thị rain intensity và sinh khuyến nghị từ `bestWindow`/`peakPeriod`; không còn câu “mưa cả ngày” chỉ vì một nguồn 100%.
- Ghi `weather.json`, `manifest.weather`, provider failures/warnings và độ tin cậy; nếu Open-Meteo lỗi vẫn graceful-degrade nhưng nói rõ `tạm lỗi`.

**Reconcile test conflict:** canonical test cũ đòi cross-language lệch chủ đề phải raise, trái policy WARN mới. Đã đổi test đó sang assert warning và thêm canonical test “same-language lệch thật vẫn raise”. **Full suite 36/36 PASS**, alignment regression riêng 6/6 PASS.

**UAT non-delivery:** real editorial turn `openai/gpt-5.6-sol` success; deterministic replay đúng `items.json` + editorial từng fail sáng 29/07 qua `apply-editorial → preview --dry-run` cho `manifest.status=ready`, world/vn/ai đều 3, event cuối `preview_dry_run`, weather đủ OpenWeather + Open-Meteo. Target UAT là chuỗi giả `dry-run-uat`; journal từ 11:00 có **0 Telegram outbound**. Artifact production 29/07 giữ nguyên `status=sent`, mtime không đổi.

**UAT thật còn chờ:** cron tự nhiên 06:28 sáng 30/07. Check `weather.txt` dễ đọc, `weather.json` có 2 provider hoặc warning rõ, manifest `sent`, và đối chiếu quan sát thực tế Quận 8.

---

## ⚡ Session Handoff — 2026-07-29 (MỚI NHẤT) — Morning brief chết LẦN 2 cùng lỗi; fix + regression test

**Triệu chứng:** bản tin sáng 29/07 không gửi (06:28 + retry 06:50 đều chết). Manifest: `ai: item 1 còn quá nhiều tiếng Anh (ratio=0.78)`.

**⚠️ Điểm quan trọng nhất:** đây là **tái phát y hệt sự cố [2026-07-09]**. Fix của mình hôm 09/07 (skip vô điều kiện cho cặp bản-dịch) **bị siết lại ngày 10/07** thành "phải có ≥1 anchor token chung" → tái lập đúng lỗi cũ. Ca thật: EN `"Scientific computing in the age of agentic AI"` → VI `"Điện toán khoa học trong thời đại AI tác tử"` — dịch chuẩn nhưng **0 token chung** → raise → fallback tiếng Anh → gate tiếng Việt chặn → mất cả bản tin.

**Đã fix (backup `bsy_morning_brief.py.bak-20260729-0700-pre-translation-anchor-fix`):**

- Nhánh cặp-bản-dịch **không raise nữa** → trả về warning string, **giữ bản dịch**. Warning chảy vào `manifest.editorialWarnings` + event log (vẫn audit được).
- Nhánh **cùng ngôn ngữ vẫn raise** — bảo vệ thật không mất.
- **🧪 Regression test mới:** `~/.openclaw-suckhoe/workspace/scripts/test_bsy_morning_brief_alignment.py` (6 case, gồm cả 2 ca thật 09/07 + 29/07). **BẮT BUỘC chạy trước khi sửa `validate_editorial_alignment` / `validate_vietnamese_section`:**
  `cd ~/.openclaw-suckhoe/workspace && python3 scripts/test_bsy_morning_brief_alignment.py`

**Verify:** apply-editorial lại với đúng file đã fail → `ready` + ai.txt tiếng Việt chuẩn · preview dry-run OK · test 6/6 PASS · **Hưng duyệt → gửi thật cho cả 2 người** (msg 4248/4249 + 4251/4252, `operation=sendMessage`), manifest `sent`.

**🐞 Bug có sẵn mới phát hiện (CHƯA FIX, cần Hưng duyệt):** `topic_tokens()` gộp cả `source`, mà bản dịch luôn kế thừa `source` ⇒ 2 tin **cùng nguồn tên ≥2 chữ** (Dân Trí, Tuổi Trẻ, OpenAI News...) tự có ≥2 token chung → gate same-language **luôn pass** dù lệch chủ đề hoàn toàn. Cố ý chưa siết vì đó đúng loại thay đổi đã 2 lần làm mất bản tin. Đã ghi thành characterization test `[KNOWN GAP]`.

**Còn treo:** khối `bsy_morning_brief.py` vẫn **uncommitted** trong git workspace suckhoe (từ 03/07 tới nay, giờ thêm fix 29/07 + test mới) — nên commit chốt lại.

---

## ⚡ Session Handoff — 2026-07-28 — Disk 60G→54G + vá GỐC RỄ backup phình

**Hưng hỏi:** sao disk 60G, dọn được gì safe 100%? (1 tuần sau lần dọn 21/07 xuống 58G mà đã phình lại). Hưng duyệt cả gói + yêu cầu thêm: giữ 2 version mới nhất, chủ động dọn bản cũ ngay trong quy trình upgrade.

**Root cause phình lại (chi tiết: `kb/lessons-learned.md` [2026-07-28]):** lần 21/07 chỉ dọn triệu chứng. 2 chỗ backup không có phanh:

1. `openclaw-backup.sh` tar cả `npm/` mỗi ngày (46% state hungreo, 80% suckhoe) — deps cài lại được nhưng nén lặp mỗi ngày ×2 bản.
2. Backup **upgrade** (`openclaw-upgrade-*`, `lcm-*`) tạo tay mỗi lần nâng cấp, **không retention** → 24/07 +4.0G, 28/07 +523M.
   ⚠️ `RETENTION_KEEP=2` vốn đã có nhưng **chỉ áp cho backup daily** — đừng nhầm là mọi backup đều có phanh.

**Đã làm:**

- **Dọn safe-100% 3.9G:** llama models 627M (0 config tham chiếu, atime 02/05, cả 3 profile dùng embedding remote) · `deploy/openclaw-runtime` 590M (stale 17/03, 0 process/script dùng) · backup `pre-7.1` 1.7G · npm cache 945M · backup rời T2-T3 100M.
- **VÁ GỐC 1:** `openclaw-backup.sh` thêm `--exclude=".openclaw-$profile/npm"` (backup `.bak-20260728-pre-npm-exclude`). Thực đo: hungreo **2.7G→1.4G**, suckhoe **1.5G→250M**. Mỗi backup tự kèm `RESTORE-NOTE.txt`.
- **VÁ GỐC 2:** script mới `~/bin/openclaw-prune-upgrade-backups.sh` — giữ `KEEP=2` mới nhất mỗi họ, **DRY-RUN mặc định, `--yes` mới xoá**.
- **Nối vào SOP** để không tái diễn: `kb/openclaw-upgrade-runbook.md` mục "🧹 Bước DỌN sau upgrade" + skill `openclaw-ops` bước **8b**.

**Kết quả:** 60G → **54G** (trống 43G). Đêm 02:15 tự prune nốt 2 bản daily cũ → về **~51G** không cần can thiệp.
**Verify:** 3 service active `2026.7.1-2` · 3 timer active · 0 lỗi log · plugins đủ · 0 drift · UAT cả 3 `fallbackUsed:false` ($0) · **`restore-check` chạy tay PASS trên backup mới** · `import torch, whisper` OK.

**KHÔNG đụng (ghi để agent sau khỏi nhầm):** whisper 2.2G + torch/CUDA 6.9G (voice tiếng Việt hungreo đang dùng) · `openclaw-agent.sqlite` 790M (= memory index + embedding cache, KHÔNG phải auth) · Docker n8n ~6G (chạy 2 tháng) · backup `pre-7.1-2` mới nhất.

**Còn treo (99%, chưa làm):** `.openclaw` profile mặc định chứa lossless-claw 0.11.2 cũ **279M** — 3 gateway không dùng profile này nhưng CLI gõ trần `openclaw` thì có. Cần Hưng xác nhận trước khi xoá.

---

## ⚡ Session Handoff — 2026-07-26 — Fix GitHub Daily false fallback warning

**Triệu chứng:** bản tin 06:30 prefix `FALLBACK/OTHER MODEL: deepseek/deepseek-v4-pro — job expected openai/gpt-5.5`.

**Root cause đã verify bằng đúng transcript:** cron thực tế chạy toàn bộ assistant turns bằng `openai/gpt-5.5`; nhưng prompt gọi `session_status(sessionKey:"current")`, tool lại trả status của `agent:main:main` đang auto-fallback DeepSeek và updated từ 8 giờ trước. Cron lấy nhầm session khác nên cảnh báo false-positive. Job cũng còn pin GPT-5.5, stale so với primary production `openai/gpt-5.6-sol`.

**Fix live, không restart/không gửi lại Telegram:** cron `openclaw-version-check-daily` đổi model sang `openai/gpt-5.6-sol`; bỏ logic tự suy luận/prefix fallback bằng `session_status`; ghi rõ cron run metadata provider/model là source of truth. Schedule 06:30, isolated session, timeout 300s và announce Telegram topic 3 giữ nguyên. Backup: `/home/hung/backups/github-daily-model-fix-20260726-134445/{job-pre,job-post}.json`.

**Verification:** full isolated UAT dùng đúng prompt mới, không `--deliver`: winner `openai/gpt-5.6-sol`, attempts=1, tool calls chỉ `bash` + `web_fetch`, 11 calls/0 failures; output bắt đầu thẳng bằng tiêu đề, không có fallback warning. Audit cả 3 profile: 0/17 cron còn pin hoặc nhắc `openai/gpt-5.5`; gateway Hungreo + healthcheck timer active; 0 serious/fallback error sau fix.

---

## ⚡ Session Handoff — 2026-07-24 (MỚI NHẤT) — Upgrade `2026.7.1` → `2026.7.1-2` landed

**Production state:** cả `hungreo`, `suckhoe`, `nemotron` đang `active`, env version `2026.7.1-2`, build `0790d9f`; healthcheck timer active và 0 failed unit. Lossless-Claw giữ `0.14.0`, DeepSeek provider giữ `2026.7.1`; Codex plugin của Hungreo/Suckhoe lên correction `2026.7.1-1`.

**Backup/rollback:** `/home/hung/backups/openclaw-upgrade-20260724-172856-pre-2026.7.1-2` (4.0G). Gồm full-current-state của 3 profile, global OpenClaw 7.1, systemd/runtime patchers, manifest, SHA256; toàn bộ archive pass `zstd -t`. Trước snapshot, LCM DB + canonical Memory Core DB cả 3 profile đều `integrity_check=ok`.

**Hai incident đã chặn và xử lý trong maintenance window:**

1. `openclaw update --dry-run --tag 2026.7.1-2` chọn nhầm managed root `/usr/lib/node_modules/openclaw` (`2026.5.22`) thay vì runtime thật `/home/hung/.npm-global/...` (`2026.7.1`). Không chạy updater; cài exact package bằng npm prefix thật.
2. Hungreo first start bị strict startup checkpoint chặn vì legacy Codex sidecar ngày 04/07 conflict với canonical active binding ngày 15/07. Đã chứng minh canonical mới hơn và thread binding đã thay đổi, lưu checksum rồi rename reversible sidecar thành `.migrated.manual-20260724-174013`; không xóa state. Sau đó gateway ready sạch.

**Verification:** hai runtime patcher Hungreo pass 3/3 tests, patch dist mới thành công và idempotent; config diff chỉ có `meta.lastTouchedAt`/`meta.lastTouchedVersion`; Telegram probe/connection pass cả 3; cron giữ nguyên 9/9, 7/7, 1/1 và không job nào đang chạy; sessions drift 0; serious errors sau ready = 0. Isolated CLI UAT không `--deliver`: Hungreo/Suckhoe winner `openai/gpt-5.6-sol`, Nemo winner `deepseek/deepseek-v4-pro`, cả 3 `UAT_OK`, attempts=1.

**Gate còn lại cho Hưng:** chưa gửi Telegram test theo yêu cầu. Hưng tự eyeball một DM/topic và để ý job version-check ở Hungreo thread 3 do upstream issue `#112500` có thể làm rơi topic ID với `delivery.mode=announce`.

---

## ⚡ Session Handoff — 2026-07-21 (MỚI NHẤT) — Disk cleanup 65G→58G + research Hermes (chưa action)

**State khi vào:** openclaw **2026.7.1** cả 3, model primary `openai/gpt-5.6-sol` (hungreo+suckhoe), nemotron `deepseek-v4-pro`. Disk 65G/96G.

**Việc 1 — Disk cleanup (Hưng duyệt, ĐÃ LÀM):** thu hồi **7G** (65G→58G, free 32G→39G). Chi tiết + snippet xác định orphan: `kb/lessons-learned.md` entry [2026-07-21].

- 2.8G orphan `npm/projects/openclaw-codex-...2026.6.11...` ×2 profile — **`openclaw update` KHÔNG dọn bản plugin cũ → nên thêm bước dọn vào SOP upgrade** (mỗi lần upgrade cộng ~1.4G/profile vĩnh viễn)
- 2.1G npm cache · 1.6G backup upgrade pre-6.8 + pre-6.11 · ~1.2G `lcm.db.bak` cũ (giữ 2 bản 22/06 + rotate-latest)
- **Verify sau dọn:** 3 service active env_VER=7.1 · 0 lỗi log · plugins enabled đủ (gồm hungreo-finance, suckhoe-family-memory, suckhoe-kb-weekly) · UAT cả 3 `UAT_OK` attempts=1 `fallbackUsed:false` ($0) · 0 drift · npm hoạt động lại bình thường.

**Còn thu hồi được nhưng CHƯA làm (cần Hưng quyết):**

- **~5-6G:** cho `~/bin/openclaw-backup.sh` exclude `npm/` khỏi `state.tgz` (npm tái tạo được; hiện tar cả 4.9G mỗi ngày → `backups/` 13G). Đổi hành vi backup nên chờ duyệt.
- **~400M:** VACUUM `codex-home/logs_2.sqlite` (file 603M, data thật 197M) — cần stop service.
- **~4.9G:** gỡ CUDA stack khỏi PyTorch (VPS không GPU) — **RỦI RO**: whisper local đang phục vụ voice tiếng Việt của hungreo (config `tools.media.audio.models[0]`, model turbo), phải reinstall torch CPU-only. Không khuyến nghị trừ khi cần gấp.

**Việc 2 — Hermes Agent: CHỈ RESEARCH, Hưng bảo chưa action gì.** Nous Research, MIT, self-hosted daemon, có Telegram, **không cần GPU** (Nous Portal OAuth/OpenRouter/endpoint riêng), cài `curl install.sh | bash`. Khác biệt: Hermes có **learning loop** (tự rút skill từ kinh nghiệm) vs OpenClaw mạnh **control plane** (multi-channel, agent teams, plugin marketplace).

- ⚠️ **Chặn lớn nhất nếu trial:** hiện $0/tháng nhờ Codex OAuth; chưa xác nhận Hermes route được Codex OAuth → nhiều khả năng phải trả tiền OpenRouter. **Phải đo cost trước.**
- ⚠️ Nemo làm sandbox hợp lý (inbound cuối 15/07, thực sự idle) nhưng **1 bot token Telegram chỉ gắn 1 webhook** → Hermes dùng token Nemo thì phải tắt hẳn `openclaw-gateway-nemotron`. Sạch hơn: tạo bot mới.
- Khuyến nghị đã trình: trial đóng khung — bot mới, chỉ làm bản tin sáng, so trực tiếp với suckhoe 1-2 tuần.

**Ghi nhận:** `npm view openclaw version` = **2026.7.1-2** (đã có bản mới hơn bản đang chạy).

---

## Session Handoff - 2026-07-15 - OpenClaw 7.1 + LCM 0.14 + GPT-5.6 Sol landed

**Production state:** OpenClaw `2026.7.1` (Node `24.15.0`) và Lossless-Claw `0.14.0` trên `hungreo`, `suckhoe`, `nemotron`. DeepSeek provider đã đồng bộ `2026.7.1`. Ba gateway active, env version khớp, Telegram webhook connected, healthcheck timer active, 0 failed units.

**Models:**

- `hungreo`: primary `openai/gpt-5.6-sol`, fallback `deepseek/deepseek-v4-pro`, Codex runtime, thinking medium.
- `suckhoe`: primary `openai/gpt-5.6-sol`, fallback `deepseek/deepseek-v4-pro`, Codex runtime, thinking medium.
- `nemotron`: giữ nguyên primary `deepseek/deepseek-v4-pro`, fallback `openrouter/nvidia/nemotron-3-ultra-550b-a55b`.

**UAT:** isolated turns pass cả 3, output `SOL_UAT_OK`/`NEMO_UAT_OK`; Hungreo và Suckhoe winner `openai/gpt-5.6-sol`, Nemo winner `deepseek/deepseek-v4-pro`, tất cả `fallbackUsed=false`. Plugins `lossless-claw`, `deepseek`, và `hungreo-finance` đều loaded đúng version. Suckhoe có 7/7 cron enabled; refill job `5a2ec168-...` đã đổi sang deterministic command, chạy 09:00 ngày 25/26, manual run `ok/not_due`, next 25/07 09:00. Weekly medical study không nằm trong scope và không bị thay đổi.

**Upgrade incidents đã xử lý:**

1. Patcher `plugin-binding-decline-fallback` 6.11 không match dist 7.1. Đã cập nhật local + VPS để match structural semantic block và test cả source shape cũ/mới. Hai ExecStartPre gate Hungreo pass.
2. Hungreo Memory Core legacy index conflict với canonical DB. Đã chứng minh canonical là superset, backup cả hai DB, archive legacy sidecar thành `.migrated`, chờ lock TTL rồi restart sạch. Chi tiết ở lesson [2026-07-15].

**Backup/rollback:** `/home/hung/backups/openclaw-upgrade-20260715-091722-pre-2026.7.1` (config, workspace, systemd, LCM, finance, legacy/canonical Memory Core DB, runtime patcher, refill cron JSON cũ, checksums). Runtime patcher cũ nằm trong `runtime/` của backup.

---

## ⚡ Session Handoff — 2026-07-09 TỐI (MỚI NHẤT) — Fix morning brief fail: validator "lệch chủ đề" false-positive với bản dịch

**Hưng báo:** 06:28 pipeline failed, không có brief sáng 09-07 (cả catchup 06:50 cũng fail).

**Root cause (chi tiết + rules: `kb/lessons-learned.md` entry [2026-07-09]):** `validate_editorial_alignment` (trong khối ~798 dòng Rùa thêm 03-07) so từ vựng title Anh gốc vs bản dịch Việt → tin OpenAI 'Our approach to...' không có tên riêng chung → false-positive "lệch chủ đề" → raise giết pipeline. Fix thử bằng fallback lộ thêm mâu thuẫn: fallback = bản gốc tiếng Anh → validator "còn quá nhiều tiếng Anh" (ratio>0.48) giết tiếp — 2 đường đều chết.

**Fix đã áp (backup `bsy_morning_brief.py.bak-20260709-1945-pre-editorial-fallback-fix`):** (1) alignment check SKIP cặp bản-dịch (`english_ratio(original)≥0.6 && english_ratio(edited)≤0.35`); (2) thêm source-name token vào matching; (3) world/ai hết đặc-cách raise → warning + fallback như vn. Verify: re-run `apply-editorial --date 2026-07-09` với đúng JSON đã fail → `ready`, ai.txt ra bản dịch Việt chuẩn. Đóng ngày 07-09 bằng `mark-sent` (không gửi thật — brief đã nguội, 19:46 tối).

**⏳ UAT thật còn chờ:** cron 06:28 sáng 10-07 chạy tự nhiên — Hưng eyeball brief sáng mai có về bình thường không.

**Vẫn treo từ 03-07:** khối bsy_morning_brief.py uncommitted (798 dòng Rùa + fix hôm nay) — nên `git commit` workspace suckhoe để chốt; chờ Hưng gật.

---

## ⚡ Session Handoff — 2026-07-03 SÁNG MUỘN — Fix "approve xong im lặng": turn idle 60s < approval 120s

**Hưng báo tiếp:** approve rồi mà bot không report result, không biết chuyện gì xảy ra; "mất nút approval"; mobile khó copy cú pháp.

**Root cause mới (verify journal + transcript + source, addendum trong lessons [2026-07-03]):**

- Codex turn `turnCompletionIdleTimeoutMs` default **60s** < approval window **120s** (hardcode) → Hưng approve sau 93s thì turn ĐÃ chết lúc giây ~60 (`turn idle timed out` + `client retired`) → approve rơi hư vô, không ai report. (Approve sau 20s thì chạy OK — bằng chứng đối chứng cùng buổi sáng.)
- Prompt "Plugin approval required" là plain-text-only by design 6.11 — KHÔNG có nút cho lớp plugin approval; nút once/always/deny Hưng nhớ là của lớp exec-approval khác. Không config nào bật nút cho lớp này.

**Fix đã áp (chỉ suckhoe — minimal scope):**

1. `plugins.entries.codex.config.appServer.turnCompletionIdleTimeoutMs = 180000` (backup `openclaw.json.bak-20260703-0931-pre-turn-idle-timeout`) + restart → UAT winner=gpt-5.5 attempts=1 UAT_OK, 0 drift, 0 lỗi log.
2. AGENTS.md guidance v2 (backup `.bak-*-pre-approval-guidance-v2`): lệnh `/approve` phải nằm 1 dòng riêng cho mobile; tool declined/timeout → bot PHẢI báo + retry, cấm im lặng.

**Note:** hungreo cùng runtime codex → cùng rủi ro, CHƯA áp (chưa triệu chứng). Nếu hungreo bị "approve xong im lặng" → áp cùng key.

---

## ⚡ Session Handoff — 2026-07-03 — Giải phẫu suckhoe "approval lặp" + fix UX guidance

**Vấn đề Hưng báo:** nhờ suckhoe action là bị hỏi approval lặp đi lặp lại, kỳ vọng "approve 1 lần" không đạt.

**Root cause (verify journal + source plugin, chi tiết ở `kb/lessons-learned.md` entry [2026-07-03]):**

1. 2 approval sáng 03-07 đều **timeout 120s** không nhận decision nào (Hưng trả lời sau 33', và gõ "Approved" thường thay vì cú pháp `/approve <ID> allow-always`). 7 ngày qua: 0 approve thành công.
2. Config `appServer.approvalPolicy:"never"` bị plugin `@openclaw/codex` 6.11 **force override → "on-request"** vì exec policy hiệu dụng của suckhoe là `allowlist+on-miss` (không phải "full"). Lớp codex approval KHÔNG đọc allowlist openclaw (`/usr/bin/python3` đã allowlist từ 06-15 vẫn bị hỏi).
3. `allow-always` của codex chỉ nhớ trong bounded session window — không vĩnh viễn, by design.

**Quyết định Hưng:** giữ nguyên security posture (đúng nguyên tắc "system change phải qua Hưng"). Fix UX: thêm section "Exec Approval Flow" vào `~/.openclaw-suckhoe/workspace/AGENTS.md` (backup `.bak-20260703-0848-pre-approval-guidance`) — bot phải nhắc deadline 120s + cú pháp copy được + cảnh báo "Approved" không được nhận, và phải nói rõ khi approval cũ hết hạn. Không restart cần thiết (workspace file nạp mỗi turn).

**Còn treo:**

- Bot suckhoe vẫn CHƯA sửa được script tin tức (`scripts/bsy_morning_brief.py` — Hưng chê tin trùng Kyiv, tin Hà Tĩnh không hot, nguồn AI lặp techcrunch/wired/theverge) vì 2 lần approval sáng 03-07 đều chết. Lần tới: hoặc Hưng approve trong 120s đúng cú pháp khi bot hỏi lại, hoặc giao Claude Code sửa script trực tiếp (chưa làm, chờ Hưng quyết).

---

## ⚡ Session Handoff — 2026-07-02 (MỚI NHẤT) — Fix cron leak + command owner + secrets → SecretRef (cả 3 bot)

**Phần 1 — Fix cron leak stdout ra finance topic:**
Sự cố: cron `hungreo-finance-compliance-daily` (07:00 daily) leak nguyên văn 1 dòng `openclaw doctor` warning (tiếng Anh) ra finance topic. Root cause: `delivery.mode="announce"` trên 1 command-job vốn đã tự deliver bên trong (`NO_REPLY` sentinel convention) → gateway bê nguyên stdout/stderr đi ném, không tôn trọng sentinel. Fix: `cron edit 848ead51-2613-4c3d-af4b-cf0b21fc6049 --no-deliver` → verify `cron run` thủ công, `deliveryStatus` từ `delivered` → `not-requested`. Chỉ hungreo dính (đã scan cron cả 3). Chi tiết + rule: `kb/lessons-learned.md` entry [2026-07-02] đầu.

**Phần 2 — Command owner + secrets → SecretRef (cả 3 profile):**

- `commands.ownerAllowFrom = ["telegram:7957776935"]` set cho cả 3 (`config set` + restart) — trước đó KHÔNG có owner nào được set cho `/diagnostics`, `/export-trajectory`, `/config`, exec approvals.
- Secrets migrate sang SecretRef object (`{source:"env",provider:"default",id:"VAR"}`), **giữ NGUYÊN giá trị cũ** (không rotate) — verify qua `secrets audit` trước/sau + UAT thật:
  - hungreo: `gateway.auth.token`→`OPENCLAW_GATEWAY_TOKEN`, `channels.telegram.webhookSecret`→`TELEGRAM_WEBHOOK_SECRET`, `agents.defaults.memorySearch.remote.apiKey`→`MEMORY_SEARCH_API_KEY`, `models.providers.deepseek.apiKey`→`DEEPSEEK_API_KEY` (đã dùng `${VAR}` từ trước, chuẩn hoá sang object).
  - suckhoe/nemotron: `gateway.auth.token`, `gateway.remote.token`, `channels.telegram.webhookSecret`, `models.providers.deepseek.apiKey` (+ nemotron `models.providers.openrouter.apiKey`) → cùng pattern.
  - `plaintextCount` (secrets audit): hungreo 6→2, suckhoe 5→1, nemotron 9→4 (còn lại: `profiles.anthropic:manual.token` trong SQLite — **auth.profiles.\* protected, CỐ Ý loại khỏi scope** theo hard rule; nemotron .env findings là false-positive, đã externalize đúng chuẩn từ trước).
- **Rủi ro đã kiểm trước khi làm:** `gateway.auth.token` dùng cho iOS mobile pairing (lesson [2026-06-30]) → verify kỹ SecretRef migration KHÔNG rotate giá trị (đọc doc `/gateway/secrets` xác nhận), dùng `config set --ref-provider --dry-run` preflight từng field trước khi apply thật, không dùng wizard `secrets configure` (cần TTY tương tác, khó kiểm soát).
- Restart suckhoe→hungreo→nemotron (stop-first healthcheck.timer) → verify: 0 lỗi `unresolved secretRef`/module trong log, `channels status --probe` cả 3 vẫn `connected/works` (xác nhận gateway token + webhook secret resolve đúng), UAT `agent --json` cả 3 `fallbackUsed:false` đúng primary provider (openai/openai/deepseek), 0 sessions drift, `commands.ownerAllowFrom` persist đúng sau restart.
- Backup: `~/backups/secrets-migration-20260702-1002/` (config + .env cả 3, trước khi sửa).

**Còn treo (không critical, để dịp khác nếu Hưng muốn):**

- `profiles.anthropic:manual.token` (SQLite, hungreo×2 + suckhoe×1) vẫn plaintext — nằm trong `auth.profiles.*`, cần Hưng quyết định rõ ràng trước khi ai đó động vào (hard rule).
- Warning `core/doctor/legacy-state` (config-health.json "1 entry conflicts") vẫn còn cả 3 — `doctor --fix` không xoá được (cố ý, safety-guard). Vô hại (không leak đi đâu nữa sau khi fix cron). Dọn dứt điểm cần xoá thủ công 1 entry trong file tamper-detection.
- `messages.tts.provider="microsoft"` (hungreo) vẫn dormant, không key thật, doctor sẽ tiếp tục tự bật `microsoft` plugin runtime mỗi lần restart/doctor chạy — vô hại nhưng lặp lại. Dứt hẳn cần xoá config này.

---

## ⚡ Session Handoff — 2026-07-01 (MỚI NHẤT) — Upgrade 6.9→6.11 + lossless 0.13.1→0.13.2 LANDED ✅ GATE 2 Hưng đã xác nhận

**State cuối (verified qua SSH):** openclaw **2026.6.11** cả 3 (active, env_VER khớp), lossless **0.13.2** cả 3, 0 sessions drift, UAT PASS cả 3 (winner=primary, attempts=1, $0), 2 patcher hungreo apply thành công lên dist 6.11 (ExecStartPre status=0 cả 4 bước), healthcheck.timer đã bật lại.

**✅ GATE 2 CONFIRMED (Hưng, cùng ngày):** Hưng tự kiểm `/status` thấy đúng version mới + xác nhận bot reply ổn trên Telegram. Format 6.11 (đụng #95532/#95007) không có vấn đề gì — upgrade coi như xong hoàn toàn.

**Còn treo nhẹ (không chặn, để verify sau nếu tiện):** tool `finance_status` mới verify gián tiếp (plugin load + journal sạch), chưa có bằng chứng trực tiếp fire qua 1 message thật hỏi finance trong topic — xem mục 13 playbook dưới.

**Playbook đã chạy (theo skill openclaw-ops §5 + 6 note bổ sung của Hưng):**

1. Health-check read-only xác nhận state 6.9/0 drift/npm latest → present plan → Hưng duyệt.
2. Check multi-agent binding (#95118 risk) trước khi động: **không áp dụng** — cả 3 profile chỉ có 1 agent `main`, không có binding per-conversation.
3. Token OAuth hungreo hiển thị exp gần (còn ~1h04' lúc check) → hỏi Hưng → chọn "proceed, re-auth nếu UAT fail". Không cần re-auth — UAT PASS bình thường, `openai:default` tự refresh (exp mới 07-11).
4. Backup đầy đủ: config + auth sqlite + sessions.json + **workspace tar ×3** + finance.sqlite + lcm.db ×3 + systemd drop-in (kể cả 2 patcher hungreo) + patcher source + SHA256SUMS → `~/backups/openclaw-upgrade-20260701-1330-pre-2026.6.11/` (1.1G).
5. Stop healthcheck.timer → stop 3 gateway → confirm 0 process leftover.
6. `openclaw update --yes --no-restart` ×3 profile → OK, Before/After 6.9→6.11.
7. `plugins update lossless-claw@0.13.2` ×3 → OK.
8. **GATE 1 dry-run** (harness MỚI viết lại, không dùng file `/tmp` cũ từ 06-22) copy dist 6.11 sang `/tmp` riêng, gọi `patchDist({distDir:tmp})` 2 patcher hungreo try/catch → **PASS cả 2** (needle khớp sạch) → xoá copy tạm ngay sau.
9. DIFF config: model.\*/fallback/streaming intact cả 3. Doctor lại tự thêm `microsoft` vào `plugins.allow`+`entries` của hungreo → gỡ (đúng lesson 06-22) → `config validate` pass cả 3.
10. Bump `OPENCLAW_SERVICE_VERSION=2026.6.11` (override.conf hungreo/suckhoe + nemotron .service) → daemon-reload.
11. Restart suckhoe→hungreo→nemotron, chờ ready từng cái. Patcher ExecStartPre hungreo: 4/4 bước status=0.
12. CHECK 3 tầng: env_VER=6.11 cả 3, 0 lỗi module/crash trong log · plugins list đủ (lossless 0.13.2, deepseek/brave/codex enabled hungreo+suckhoe, brave/deepseek nemotron, perplexity vẫn disabled đúng ý nemotron) · auth token sống (`openai:default` tự refresh) · sessions drift=0 · UAT JSON winner=primary attempts=1 cả 3.
13. Note #3 (finance tool chạy thật): thử gọi `finance_status` qua CLI với session-key giả lập finance topic → bot trả `"finance_status tool not available"`. Điều tra: tool này **cố ý gate theo `context.messageChannel==="telegram"` + sessionKey thật từ inbound message**, CLI không tái tạo được context đó (đây là thiết kế bảo mật đúng, không phải bug). Verify gián tiếp: plugin `enabled` 0.1.0, 0 lỗi finance trong journal, `config validate` pass, gửi message thật vào finance topic (GATE 2) → bot tự thừa nhận đúng cơ chế gate này. **Chưa có bằng chứng tool thực sự fire trong 1 turn thật** — cần Hưng nhắn thật trong finance topic để tool tự nạp và chạy, khi đó mới coi là verify đủ 100%.
14. Note #4 (provider-plugin onboarding 6.11): phát hiện **2 provider mới externalize trong 6.11**: `@openclaw/codex` (critical — routing agentRuntime=codex cho gpt-5.5, verify enabled hungreo+suckhoe) và `@openclaw/brave-plugin` (web search, enabled cả 3). Cả 2 load sạch.
15. **Phát hiện runtime behavior MỚI của 6.11** (không có trong changelog đọc trước): gateway có cơ chế "auto-enabled plugins for this runtime without writing config" — hungreo có `messages.tts.provider="microsoft"` (config CŨ, có từ trước 6.9, không có API key thật) → 6.11 tự bật plugin `microsoft` tại runtime (không ghi lại config) để thoả capability đã khai báo, dù đã gỡ khỏi `plugins.allow`. Verify: không có Azure/Microsoft key nào cấu hình → tính năng TTS này vẫn dormant/vô hại, không phát sinh cost/risk. Chỉ xảy ra ở hungreo (suckhoe/nemotron không có field này).
16. GATE 2: gửi 2 message thật (DM + finance topic) qua `agent --deliver` → cả 2 `operation=sendMessage` (plain, đúng format 6.9 giữ nguyên). **Chờ Hưng xác nhận bằng mắt.**
17. Bot tự đưa ra 1 câu cảnh báo lạ trong lúc trả lời DM ("suckhoe probe lệch sang hungreo") → verify trực tiếp bằng `channels status --probe` cả 2 profile → **KHÔNG có cross-wiring thật**, mỗi bot probe đúng bot Telegram riêng. Kết luận: bot confabulate (khớp lesson 2026-06-05), không phải sự cố thật.
18. Start lại `openclaw-healthcheck.timer` (đã active) — không đợi Hưng xong GATE 2 mới bật, vì cả 3 service đã healthy ngay sau restart (đúng note #5 tinh thần "đừng để bot down chờ vô ích").

**Backup:** `~/backups/openclaw-upgrade-20260701-1330-pre-2026.6.11/` (config, auth sqlite, sessions.json, workspace ×3, finance.sqlite, lcm.db ×3, systemd drop-in, patcher source, SHA256SUMS) + `~/.openclaw-hungreo/openclaw.json.bak-20260701-pre-remove-microsoft`.

**Rollback nếu GATE 2 fail:** `npm i -g --prefix /home/hung/.npm-global openclaw@2026.6.9` + `plugins update @martian-engineering/lossless-claw@0.13.1` ×3 + restore config/override.conf/sessions từ backup trên + daemon-reload + restart suckhoe→hungreo→nemotron.

**What could still be wrong (đã update sau khi Hưng confirm GATE 2):**

- ~~GATE 2 format chưa xác nhận~~ → **RESOLVED**: Hưng đã tự check `/status` + xác nhận bot reply ổn.
- ~~brave-plugin chưa test~~ → **RESOLVED**: test `web_search` thật qua CLI, `toolSummary calls=1 failures=0`, kết quả hợp lý.
- `finance_status` tool vẫn chưa chứng minh được fire thật trong 1 turn real-user (chỉ verify gián tiếp qua plugin health + journal sạch). Rủi ro thấp (logic gate không đổi, chỉ là CLI không tái tạo được context) nhưng chưa phải bằng chứng 100% — nếu tiện, Hưng nhắn 1 câu hỏi finance status thật trong topic 61 để khép hẳn.
- `messages.tts.provider="microsoft"` (hungreo) là config cũ dormant, không có credential — nếu Hưng từng định dùng TTS thật thì tính năng này đang không hoạt động (không phải do upgrade này gây ra, tồn tại từ trước).
- Token OAuth hungreo mốc hiển thị 07:33 UTC hôm nay vẫn còn 1 profile riêng (`openai:hungreo2005@gmail.com`) chưa refresh (chỉ `openai:default` refresh) — UAT đã pass nên không chặn, nhưng theo dõi nếu có lỗi 401 xuất hiện sau giờ đó.

---

## 🎯 NEXT-SESSION PREP (2026-06-23) — Upgrade openclaw 6.9 → 6.11 + lossless 0.13.1 → 0.13.2 [ĐÃ LÀM — xem entry 2026-07-01 phía trên]

> Session này (06-23) CHỈ research + chuẩn bị (read-only). Session MỚI sẽ execute sau khi Hưng duyệt plan.

**State hiện tại (verified 06-23):** openclaw **2026.6.9** cả 3 (active, 0 drift) · lossless **0.13.1** · gpt-5.5 codex ($0, token exp 07-01) + deepseek · format 6.9-native (patcher `telegram-plain-text` ĐÃ RETIRE/disabled) · finance plugin OK · deepseek externalized (`@openclaw/deepseek-provider`).

**Latest stable:** openclaw **2026.6.11** (06-30) · lossless **0.13.2** (06-30). Bỏ qua 6.10 (nhỏ) → nhảy thẳng 6.11.

**Vì sao 6.11 ĐÁNG (Telegram-centric = trúng bot Hưng):**

- 🎯 Format: #95532 rich-message giữ paragraph/bullet/status-line KHÔNG dồn cục (no config) · #95007 progress readable + **plain-text fallback** khi Telegram không parse được.
- Reliability: #94506 webhook giữ nhận DM/group qua restart/reload (no blackout) · #95299 chat phục hồi sau 1 message stuck timeout · #95577 inbound tới session ngay (không đợi poll/restart) · #95432 hết duplicate reply · #89911 reply bám đúng conversation.
- Anti-leak: #92356 heartbeat reasoning-model KHÔNG lộ internal reasoning ra Telegram.
- 6.10 (kèm theo): auto fast-mode turn ngắn, Codex service-tier normalize, provider-plugin onboarding registry refresh.
- lossless 0.13.2: dedup delivery-mirror/afterTurn, forced-compaction recovery, `/lossless` slash-cmd declared — continuity patches, low risk.

**⚠️ RỦI RO phải gate (giống 6.9):**

1. **6.11 ĐỤNG LẠI Telegram render path** (#95532/#95007) → format có thể đổi. Sau upgrade **BẮT BUỘC Hưng eyeball** reply thật (general + finance topic). Format patcher đã retire nên không lo fail-closed, nhưng phải xác nhận native đẹp.
2. **2 patcher exact-needle của hungreo** (`plugin-command-registry` + `plugin-binding-decline-fallback`) → **dry-run lên dist 6.11 (copy /tmp) TRƯỚC restart** (6.10/6.11 đụng plugin-registry/hook-policy). Vỡ needle → hungreo fail-closed không start → phải adapt/retire.
3. **Finance** (hungreo, local plugin) → verify load + tool chạy sau upgrade.
4. **deepseek/perplexity externalized** → verify `@openclaw/deepseek-provider` load enabled cả 3 (deepseek = fallback hungreo/suckhoe + primary nemotron).
5. **Data-loss precedent** (5.19 xoá `~/.openclaw/workspace`) → **backup GỒM CẢ workspace** ×3.
6. **healthcheck.timer auto-restart** → stop trước, start sau (lesson 06-14).
7. **`update --no-restart` khi đang chạy** gây ERR_MODULE_NOT_FOUND transient (lazy-import) → verify lỗi theo PID mới; stop-first an toàn hơn nếu cần 0 lỗi.

**Playbook (theo skill openclaw-ops §5, đã bổ sung các gate trên):** backup(config+workspace+finance.sqlite+lcm.db+dropin) → stop healthcheck → stop 3 → `openclaw update` 6.11 từng profile → `plugins update lossless@0.13.2` → **dry-run 2 patcher hungreo lên dist 6.11** → DIFF config (model.\* intact + gỡ microsoft doctor-add nếu có) → bump version 6.11 → restart suckhoe→hungreo→nemotron → verify 3 tầng (env_VER + plugins/finance/deepseek load + auth + drift + UAT) → **Hưng eyeball format** → start healthcheck. Rollback: `npm i -g openclaw@2026.6.9` + restore backup.

---

## ⚡ Session Handoff — 2026-06-22 (MỚI NHẤT)

### ✅ Phase 2 (chiều 06-22): openclaw 6.8→6.9 LANDED cả 3 qua Path A — RETIRE format patcher (6.9 tự fix font)

- **State cuối:** openclaw **2026.6.9** cả 3, active, env_VER=6.9 · lossless 0.13.1 · token codex exp 07-01 · 0 drift · UAT winner=primary attempts=1 (gpt-5.5 codex $0 / deepseek) · **finance plugin enabled+load OK** · Telegram connected.
- **Format (constraint #1) — GIẢI QUYẾT GỌN:** 6.9 rewrite outbound Telegram (bỏ `rich_message` = gốc font-nhỏ, dùng `api.sendMessage`+parse_mode HTML) → **patcher `telegram-plain-text` cũ KHÔNG match 6.9 + đã THỪA**. → **Disable drop-in cả 3** (`telegram-plain-text.conf.disabled-pathA-20260622-1626`) → chạy 6.9 native → **Hưng eyeball Telegram (general + finance) = format ĐẸP** ✅. Patcher retire (bớt 1 thứ maintain). Muốn khôi phục: rename lại `.conf` + daemon-reload.
- **2 patcher hungreo CÒN ACTIVE** (PASS 6.9, liên quan finance): `plugin-command-registry.conf` + `plugin-binding-decline-fallback.conf`.
- **6.9 externalize provider (#93470):** deepseek → `@openclaw/deepseek-provider` (verified load enabled cả 3) + perplexity → `@openclaw/perplexity-plugin` (nemotron, disabled). Doctor tự thêm `microsoft` plugin enable vào hungreo → **đã gỡ** (restore config sạch).
- **Quy trình:** backup (config+finance.sqlite+lcm.db+drop-in, suffix `20260622-1626-pre-upgrade-2026.6.9`) → stop healthcheck → `update --no-restart` → restore config sạch → disable telegram-plain-text → bump 6.8→6.9 → restart cả 3 → verify → healthcheck on.
- ⚠️ **Lesson zero-downtime trick:** `update --no-restart` khi gateway đang chạy gây `ERR_MODULE_NOT_FOUND` transient (lazy-import) cho process CŨ trong cửa sổ update→restart; process MỚI sạch. Verify lỗi theo PID mới. Chi tiết + rules: lessons [2026-06-22].
- **Rollback (nếu cần):** `npm i -g openclaw@2026.6.8` + restore `*-pre-upgrade-2026.6.9` + rename lại telegram-plain-text.conf + daemon-reload + restart.

### Phase 1 (sáng 06-22): Upgrade lossless-claw 0.13.0 → 0.13.1 cả 3 (DONE)

**State khi vào session (verified, đã drift từ 06-14):** openclaw **2026.6.8** (session/agent khác lên 6.6→6.8 tuần qua, không thấy backup pre-6.8 chuẩn) · lossless 0.13.0 · **token codex re-auth tới 2026-07-01** (khủng hoảng token #1 đã được xử lý) · 0 drift · models intact.

**Việc làm (Hưng duyệt scope "Phase 1 lossless ngay, 6.9 tính sau"):**

- ✅ **lossless 0.13.0 → 0.13.1 cả 3** qua `plugins update @martian-engineering/lossless-claw@0.13.1` (vào pinned `npm/projects/`). Lý do: patch thuần fix continuity/recall (preserve conversation ID khi transcript rollover, recall đúng active session, `/lossless doctor` repair split memory) — **zero risk cho format + finance**.
- SOP: backup config + **lcm.db** ×3 (suffix `20260622-0837-pre-lossless-0.13.1`) → stop healthcheck.timer → plugins update → restart suckhoe→hungreo→nemotron → verify → start lại healthcheck.timer.
- **Verify:** lossless 0.13.1 LOAD cả 3 · 0 LCM/plugin error · 0 drift · UAT winner=primary attempts=1 (no fallback, $0) cả 3 · **finance plugin vẫn `enabled` 0.1.0** · **format patcher `TELEGRAM_PLAIN_DIST_OK` xuất hiện cả 3** (constraint #1 intact sau restart).

**🛑 openclaw 6.8 → 6.9 HOÃN (đã research, chờ buổi Hưng online test):**

- **2 constraint Hưng đặt:** (1) GIỮ NGUYÊN format/font reply (Hưng+codex fix rất khổ sau khi 6.8 đổi); (2) KHÔNG đụng finance bots (legal+biz topic).
- **6.9 = 422 PR** (nặng), risk thật cho cả 2: (a) **6.9 thay đổi nhiều core Telegram rendering** (rich HTML/markdown, normalize tables) → có thể tương tác với format patcher; (b) **6.9 đổi plugin loading** (#93470) → phải verify `hungreo-finance` (local extension `global:hungreo-finance/index.ts`) còn load.
- ✅ **Tin tốt — format fix có cơ chế fail-safe:** format = patcher `patch-openclaw-telegram-plain-text.mjs` chạy systemd **ExecStartPre** + regression test cho cả 3 (drop-in `telegram-plain-text.conf`). Nếu 6.9 đổi Telegram code shape → ExecStartPre **FAIL = gateway không start** (fail-closed, KHÔNG silent revert format). → 6.9 an toàn về format theo nghĩa "không âm thầm hỏng", nhưng worst case là phải sửa patcher trước khi start được.
- **Khi làm 6.9 (Phase 2):** full stop-first SOP + backup finance.sqlite + sau upgrade verify: ExecStartPre patcher pass (TELEGRAM_PLAIN_DIST_OK) + Hưng nhìn 1 reply thật xác nhận format + finance plugin load + finance tools chạy → hư bất kỳ cái nào → rollback `npm i -g openclaw@2026.6.8`.

**Backups Phase 1:** `~/.openclaw-*/openclaw.json.bak-20260622-0837-pre-lossless-0.13.1` + `lcm.db.bak-*`. Rollback lossless: `plugins update @...lossless-claw@0.13.0` → restart.

---

## ⚡ Session Handoff — 2026-06-19 09:00 +07

### Telegram plain format final fix — visually confirmed by Hưng

- Hưng tested `hungreo`, `suckhoe`, and `nemotron` after the final patch and confirmed the format is correct.
- Real gateway logs prove the active production path:
  - `hungreo` DM message `7099`: `operation=sendMessagePlain`
  - `hungreo` ops topic `threadId=3`, message `463`: `operation=sendMessagePlain`
  - `suckhoe` DM message `3742`: `operation=sendMessagePlain`
  - `nemotron` DM messages `1422`, `1424`, `1426`, `1428`: `operation=sendMessagePlain`

**Final architecture (source of truth):**

- The preload approach is retired. OpenClaw 2026.6.8 uses an imported `undici.fetch`, so a global fetch preload cannot intercept the real gateway transport.
- Persistent patcher:
  `/home/hung/openclaw-shared/runtime/patch-openclaw-telegram-plain-text.mjs`
- Patcher regression test:
  `/home/hung/openclaw-shared/runtime/patch-openclaw-telegram-plain-text.test.mjs`
- Systemd drop-in for all 3 gateways:
  `~/.config/systemd/user/openclaw-gateway-{hungreo,suckhoe,nemotron}.service.d/telegram-plain-text.conf`
- The drop-in runs test + idempotent patcher before every gateway start.
- Patched runtime markers:
  - `HUNGREO_TELEGRAM_PLAIN_OUTBOUND`
  - `HUNGREO_TELEGRAM_PLAIN_DELIVERY`
- Expected startup output:
  `TELEGRAM_PLAIN_DIST_OK ...`
- Expected real-send log:
  `operation=sendMessagePlain`

**Upgrade behavior:**

- `npm install/update` may replace hashed `dist` files.
- No manual re-patch is normally required: the first gateway restart runs the patcher against the new install before Node starts.
- If the new OpenClaw release changes the Telegram code shape, `ExecStartPre` fails instead of silently starting with rich format. Operator must inspect/adapt the patcher before proceeding.
- Mandatory post-upgrade UAT:
  1. verify both `ExecStartPre` commands exited `status=0`;
  2. verify both runtime markers exist in current hashed `dist` files;
  3. send/check one DM and one group topic;
  4. require `operation=sendMessagePlain` in journal.

**Memory decision:**

- Do not duplicate this runtime mechanism into every bot's `MEMORY.md`; that would consume model context and cannot enforce Telegram transport.
- Bot workspace style rules remain useful only for tone/emoji/plain-writing preference. Runtime enforcement belongs in systemd patcher + ops runbook.

---

## ⚡ Session Handoff — 2026-06-19 06:40 +07

### Corrected Telegram plain-text transport fix

- Hưng reported that all bots, including `suckhoe`, had reverted to the old visual format and that group topics still had not changed.
- Log review proved the report correct. After the 2026-06-18 preload deployment, real sends still logged:
  - `hungreo` ops topic: 2026-06-18 09:25, `chatId=-1003700265995`, `threadId=3`, `operation=sendRichMessage`;
  - `hungreo` DM: 2026-06-18 20:45, `operation=sendRichMessage`;
  - `suckhoe`: 2026-06-18 19:30 and 2026-06-19 05:45/06:15, all `operation=sendRichMessage`.
- The preload, systemd drop-ins, and process environment were still present. There was no OpenClaw upgrade or service regeneration.

**Actual root cause:**

- OpenClaw 2026.6.8 sends text through Telegram Bot API endpoint `sendRichMessage` with a `rich_message` payload.
- The first preload only intercepted classic `/sendMessage` requests containing `parse_mode: "HTML"`.
- Its 5 tests modeled the old/requested path, not the real grammY/OpenClaw production path. Therefore startup tests passed while every real message bypassed the rewrite.

**Corrected fix:**

- Updated:
  `/home/hung/openclaw-shared/runtime/telegram-plain-text-preload.mjs`
- It now rewrites:
  - endpoint `/sendRichMessage` → `/sendMessage`;
  - `rich_message.markdown` or `rich_message.html` → natural plain `text`;
  - `skip_entity_detection` → disabled link preview when applicable;
  - while preserving `chat_id`, `message_thread_id`, reply parameters, buttons, and notification options.
- Unit/regression suite expanded from 5 to 7 tests, including markdown + HTML `sendRichMessage`.
- Added production-transport smoke:
  `/home/hung/openclaw-shared/runtime/telegram-plain-text-transport-smoke.mjs`
  It runs real installed grammY against a localhost fake Telegram server and asserts:
  `/sendRichMessage` becomes `/sendMessage`, topic ID stays intact, and formatting markers are removed.
- Both test layers now run via `ExecStartPre` for `hungreo`, `suckhoe`, and `nemotron`.
- Backup:
  `/home/hung/backups/telegram-plain-preload-fix-20260619-062730/`

**Verification:**

- Each gateway restart: 7/7 regression tests passed.
- Each gateway transport smoke: `TELEGRAM_PLAIN_TRANSPORT_OK`.
- All 3 gateways active; Telegram webhook probes work; healthcheck timer active.
- No unsolicited real Telegram message was sent. The next actual reply/report is the final visual UAT.

**Important correction to 2026-06-18 handover:**

- The earlier statement that the first preload permanently covered groups/topics was incorrect.
- Future transport fixes must include a real installed-dependency smoke test, not only unit tests around a guessed HTTP request shape.

**Superseded 2026-06-19 09:00:** the preload still could not intercept the gateway's imported `undici.fetch`. The final verified solution is the idempotent `dist` patcher documented above.

---

## ⚡ Session Handoff — 2026-06-18 08:55 +07

### Permanent Telegram plain-text delivery for DM + groups/topics

- User reported the `hungreo` ops topic still had the old rich/font style while DM, `suckhoe`, and `nemotron` looked correct.
- Log confirmed the missed scope:
  - group `chatId=-1003700265995`, `threadId=3` used `operation=sendRichMessage`;
  - DM `chatId=7957776935` used the prior `operation=sendMessagePlain` patch.
- Root cause: the 2026-06-17 live `dist` patch was limited to two DM chat IDs. Group/topic sends therefore stayed on OpenClaw's HTML/rich Telegram path.

**Permanent fix:**

- Added an external Node preload, outside npm/OpenClaw install:
  `/home/hung/openclaw-shared/runtime/telegram-plain-text-preload.mjs`
- The preload intercepts only Telegram Bot API `sendMessage` requests:
  - converts Telegram HTML to natural plain text;
  - removes `parse_mode`;
  - preserves `chat_id`, `message_thread_id`, reply params, notification options, and links;
  - does not alter media APIs such as `sendPhoto`.
- Enabled for all 3 gateways through a persistent systemd drop-in:
  `~/.config/systemd/user/openclaw-gateway-{hungreo,suckhoe,nemotron}.service.d/telegram-plain-text.conf`
- Each restart now runs a fail-closed regression suite first:
  `/usr/bin/node --test /home/hung/openclaw-shared/runtime/telegram-plain-text-preload.test.mjs`
  Current result: 5 tests passed for all 3 services.
- Restored the two OpenClaw npm `dist` files to their pristine pre-patch versions:
  - `send-DsQJjhVA.js`
  - `delivery-ChlR386m.js`
- Backup before migration:
  `/home/hung/backups/telegram-plain-preload-20260618-084626/`

**Verification:**

- `hungreo`, `suckhoe`, `nemotron` services active.
- All process environments contain:
  `OPENCLAW_TELEGRAM_PLAIN_TEXT=1`
  and
  `NODE_OPTIONS=--import /home/hung/openclaw-shared/runtime/telegram-plain-text-preload.mjs`
- Telegram channel probes connected/webhook works for all 3.
- No external test message was sent from Codex. The next real DM/group/topic reply is the final visual UAT.

**Upgrade behavior:**

- Normal OpenClaw npm upgrades should not overwrite this fix because runtime code + systemd drop-ins live outside `node_modules`.
- Telegram client/app upgrades should not require changes.
- Re-check only if OpenClaw changes away from Bot API `sendMessage`, changes request serialization, or an operator replaces/removes the systemd units/drop-ins. The `ExecStartPre` tests are designed to stop startup visibly if the preload contract breaks.

**Superseded/corrected 2026-06-19:** the first preload did not intercept OpenClaw 2026.6.8's actual `sendRichMessage` endpoint. Use the corrected handover above.

---

## ⚡ Session Handoff — 2026-06-17 16:20 +07

### Hungreo Telegram DM plain-text fix for Rùa replies

- User reported Rùa Telegram replies looked different from Hưng's normal messages even after Rùa "saved preference".
- Verified root cause is two-layer:
  - Agent/style layer: recent session still produced report-like multi-line replies with markdown-sensitive text such as backticks and checklist phrasing.
  - Delivery layer: OpenClaw 2026.6.8 Telegram final reply path uses `sendRichMessage` with `textMode: "markdown"` in:
    `/home/hung/.npm-global/lib/node_modules/openclaw/dist/delivery-ChlR386m.js`
    There is no current `openclaw.json` config knob to force plain final replies.
- Backup before edits:
  `/home/hung/backups/hungreo-telegram-plainstyle-20260617-161519/`
- Live runtime patch applied:
  - In `delivery-ChlR386m.js`, `sendTelegramText(...)` forces plain `bot.api.sendMessage(...)` only when:
    `OPENCLAW_PROFILE === "hungreo"` and `chatId === "7957776935"`.
  - First real user test after this still logged `operation=sendRichMessage`; root cause: Rùa DM final replies actually use outbound adapter `sendMessageTelegram(...)` in:
    `/home/hung/.npm-global/lib/node_modules/openclaw/dist/send-DsQJjhVA.js`
  - Backup before the second patch:
    `/home/hung/backups/hungreo-telegram-outbound-plain-20260617-162658/`
  - In `send-DsQJjhVA.js`, `sendMessageTelegram(...)` now forces `api.sendMessage(chatId, chunk.text, params)` and logs `operation=sendMessagePlain` only when:
    `OPENCLAW_PROFILE === "hungreo"` and `chatId === "7957776935"`.
  - All other profiles/chats continue through `sendRichMessage`.
  - These are live npm dist patches and will be overwritten by future OpenClaw upgrades; port to a supported config option or re-apply intentionally after upgrade if still needed.
- Prompt/style hardening:
  - Added `Telegram Direct Chat Plain Style` to `/home/hung/.openclaw-hungreo/workspace/AGENTS.md`.
  - Added `Style Rule — Plain Telegram Direct Chat` to `/home/hung/.openclaw-hungreo/workspace/MEMORY.md`.
- Verification:
  - `node --check` passed for both patched dist files.
  - Restarted `openclaw-gateway-hungreo.service` after each patch.
  - `openclaw --profile hungreo channels status --probe`: Telegram connected/webhook works.
  - `openclaw --profile suckhoe channels status --probe`: Telegram connected/works.
  - Hungreo journal after restart showed gateway ready and webhook advertised, no post-restart errors.
- Remaining limitation:
  - No external Telegram test message was sent from this Codex session after the second patch. First real Hưng DM reply after the corrected patch should produce `operation=sendMessagePlain`.

### Follow-up 16:35 +07 — made plain Telegram style permanent across all 3 bots

- Hưng confirmed the corrected `send-DsQJjhVA.js` patch fixed Rùa's Telegram font/format.
- User asked to keep the format permanently and check whether the "many emoji" style still exists.
- Verified style state:
  - `hungreo`: `USER.md` still says use many emoji; new plain-chat rule now explicitly says plain text is not a dry personality.
  - `suckhoe`: `SOUL.md` already requires 2-4 warm/friendly emoji; new plain-chat rule preserves that.
  - `nemotron`: `SOUL.md` already says Nemo should be fun/emoji-heavy; new plain-chat rule preserves that after truth/evidence.
- Backup before all-bot style/runtime update:
  `/home/hung/backups/all-bots-telegram-plain-style-20260617-163522/`
- Runtime patch widened in both active Telegram text paths:
  - `/home/hung/.npm-global/lib/node_modules/openclaw/dist/send-DsQJjhVA.js`
  - `/home/hung/.npm-global/lib/node_modules/openclaw/dist/delivery-ChlR386m.js`
  - Condition now forces plain send for profiles `hungreo`, `suckhoe`, `nemotron` and chat IDs `7957776935`, `8288766754`.
  - Plain send logs as `operation=sendMessagePlain`.
- Workspace style rules added/updated:
  - `/home/hung/.openclaw-hungreo/workspace/AGENTS.md`, `MEMORY.md`
  - `/home/hung/.openclaw-suckhoe/workspace/AGENTS.md`, `MEMORY.md`
  - `/home/hung/.openclaw-nemotron/workspace/AGENTS.md`, `MEMORY.md`
- Restarted all 3 gateways after the widened runtime patch.
- Verification:
  - `node --check` passed for both patched dist files.
  - `openclaw --profile hungreo channels status --probe`: connected/webhook works.
  - `openclaw --profile suckhoe channels status --probe`: connected/webhook works.
  - `openclaw --profile nemotron channels status --probe`: connected/webhook works.
  - Journals for all 3 showed gateway ready + webhook advertised, no post-restart error scan hits.
- Upgrade warning:
  - These are still live npm dist patches. Any future OpenClaw upgrade may overwrite them. Re-check `send-DsQJjhVA.js` and `delivery-ChlR386m.js` or upstream this as a supported config.

## ⚡ Session Handoff — 2026-06-17 10:45 +07

### Upgraded VPS OpenClaw 2026.6.6 → 2026.6.8 and lossless-claw 0.12.0 → 0.13.0

- Scope: all 3 profiles `hungreo`, `suckhoe`, `nemotron`.
- Backup before changes:
  `/home/hung/backups/openclaw-upgrade-20260617-2026.6.8-20260617-102511/`
  Includes `openclaw.json`, `sessions.json`, `lcm.db`, discovered auth DBs, systemd gateway/healthcheck files, and `SHA256SUMS`.
- Stop-first sequence used:
  - stopped `openclaw-healthcheck.timer` and `openclaw-healthcheck.service`
  - stopped all 3 gateways
  - confirmed gateway processes were gone before package changes
  - restarted `suckhoe → hungreo → nemotron`
  - started `openclaw-healthcheck.timer` again
- Important gotcha hit:
  - `~/.npm-global/bin/openclaw update --yes --no-restart` targeted managed root `/usr/lib/node_modules/openclaw` because base systemd unit still points there, even though the active override uses `/home/hung/.npm-global/lib/node_modules/openclaw`.
  - It failed safely with `EACCES` while gateways were stopped. Fix used for this upgrade:
    `npm install -g --prefix /home/hung/.npm-global openclaw@2026.6.8`
  - Lesson: for future upgrades, verify `systemctl --user cat openclaw-gateway-*.service` before using `openclaw update`; do not trust the managed root if base unit and override differ.
- Systemd labels updated:
  - `openclaw-gateway-hungreo.service.d/override.conf`
  - `openclaw-gateway-suckhoe.service.d/override.conf`
  - `openclaw-gateway-nemotron.service`
    all now have `OPENCLAW_SERVICE_VERSION=2026.6.8`.
- Final verified state:
  - `/home/hung/.npm-global/bin/openclaw` = `OpenClaw 2026.6.8 (844f405)`
  - `/home/hung/bin/openclaw` = `OpenClaw 2026.6.8 (844f405)`
  - `/usr/bin/openclaw` still old `OpenClaw 2026.5.22 (a374c3a)` — footgun still open, needs sudo/symlink fix later.
  - all 3 services active with `env_VER=2026.6.8`
  - `lossless-claw` loaded from pinned project path at `0.13.0` for all 3 profiles
  - `channels.telegram.streaming` remains `{ "mode": "off" }`
  - model config unchanged:
    - `hungreo`: primary `openai/gpt-5.5`, fallback `deepseek/deepseek-v4-pro`, `agentRuntime.id=codex`
    - `suckhoe`: primary `openai/gpt-5.5`, fallback `deepseek/deepseek-v4-pro`, `agentRuntime.id=codex`
    - `nemotron`: primary `deepseek/deepseek-v4-pro`, fallback `openrouter/nvidia/nemotron-3-ultra-550b-a55b`
  - config diff vs backup: only `lastTouchedVersion/lastTouchedAt` changed; primary/fallback/streaming/timeout unchanged.
- Checks:
  - `config validate` passed for all 3.
  - `models auth list` populated for `hungreo` and `suckhoe`; live OpenAI OAuth profiles still expire 2026-06-21/24 as before.
  - sessions drift = 0 for all 3.
  - UAT CLI:
    - `hungreo`: `winnerProvider=openai`, `winnerModel=gpt-5.5`, `attempts=1`, text `UAT_OK`
    - `suckhoe`: `winnerProvider=openai`, `winnerModel=gpt-5.5`, `attempts=1`, text `UAT_OK`
    - `nemotron`: `winnerProvider=deepseek`, `winnerModel=deepseek-v4-pro`, `attempts=1`, text `UAT_OK`
- Log notes:
  - No post-UAT crash/module/auth/fallback errors found.
  - Startup produced many `Subagent orphan run pruned` warnings on `hungreo`/`nemotron`; appears restore-cleanup related, not blocking gateway readiness.
  - `hungreo` still warns `memorySearch.provider="gemini"` has no loaded embedding provider, so semantic memory falls back to keyword/FTS-only. This pre-existing config/runtime mismatch was not changed in this upgrade.
- Still open:
  - `/usr/bin/openclaw` stale `2026.5.22`; standardize with sudo later.
  - Suckhoe monthly refill reminder `5a2ec168-3f9a-4953-b714-8f1d46ad8931` still has `Agent ID main` and timezone `Asia/Saigon`; refactor before next run `2026-06-25 02:00`.
  - Codex/OpenAI OAuth expiry remains a near-term operational risk around 2026-06-21/24.

## ⚡ Session Handoff — 2026-06-16 06:35 +07

### Suckhoe morning jobs recovered; approval prompts fixed for daily/greeting

- User reported no morning Telegram messages and saw approval prompt:
  `python3 /home/hung/.openclaw-suckhoe/workspace/scripts/bsy_daily_report.py`
- Root causes:
  - `bsy-daily-report-0615` and `Chào Ngày Mới - Minh Trân` were still `payload.kind="agentTurn"` and therefore still hit Codex app-server command approval.
  - `devotional-morning-send.sh` used `TZ=Asia/Saigon`. On VPS shell this resolves as UTC (`+0000`), so at 05:45 VN it looked at previous-day guard and incorrectly returned `DEVOTIONAL_ALREADY_SENT`.
- Fixes on VPS:
  - Patched `/home/hung/.openclaw-suckhoe/workspace/scripts/devotional-morning-send.sh` to use `Asia/Ho_Chi_Minh`.
  - Added `/home/hung/.openclaw-suckhoe/workspace/scripts/bsy_daily_report_send.sh`, deterministic wrapper around `bsy_daily_report.py` + `bsy_send_guard.py`.
  - Added `--no-mark-sent` to `bsy_daily_report.py` so the wrapper can send first via guard instead of marking sent before Telegram delivery.
  - Converted `bsy-daily-report-0615` to command:
    `bash /home/hung/.openclaw-suckhoe/workspace/scripts/bsy_daily_report_send.sh`
  - Converted `691e12e2-21bd-48ec-9a1b-a92624f69c94` / `Chào Ngày Mới - Minh Trân` to command:
    `OPENCLAW_STATE_DIR=/home/hung/.openclaw-suckhoe python3 /home/hung/.openclaw-suckhoe/workspace/scripts/bsy_greeting_minhtran.py send`
  - Changed devotional cron timezone to `Asia/Ho_Chi_Minh`.
- Recovery sent for 2026-06-16:
  - Devotional: message IDs `3694` (Trân) and `3695` (Hưng); guard `send-guard/devotional-morning/2026-06-16.json`.
  - Daily report for 2026-06-15: message ID `3696` (Hưng); guard `send-guard/daily-report/2026-06-15.json`.
  - Greeting Minh Trân 2026-06-16: message ID `3697`; guard `send-guard/greeting-minhtran/2026-06-16.json`.
  - Morning brief 06:28 ran normally after command-state-machine change: summary `MORNING_BRIEF_SENT_OK`, next run 2026-06-17 06:28 +07.
- Verification:
  - Manual cron smoke after recovery:
    - devotional: `DEVOTIONAL_ALREADY_SENT`
    - daily report: `DAILY_REPORT_ALREADY_SENT`
    - greeting: JSON `{"status":"already_sent","dateKey":"2026-06-16"}`
  - `cron list` now shows no `Agent ID` for morning jobs: devotional, daily report, greeting, morning brief, catchup, medication reminder.
  - Remaining `agentTurn`: monthly refill reminder `5a2ec168-3f9a-4953-b714-8f1d46ad8931` (next 2026-06-25 02:00).
  - Service `openclaw-gateway-suckhoe.service` active.
- Backup before script edits:
  `/home/hung/.openclaw-suckhoe/workspace/data/ops-backups/20260616-062740-daily-command-recovery/`
- Still open:
  - `/usr/bin/openclaw` remains old `2026.5.22`; correct runtime `/home/hung/.npm-global/bin/openclaw` and `/home/hung/bin/openclaw` are `2026.6.6`.
  - Monthly refill reminder still uses `agentTurn`; refactor before 2026-06-25 if possible.

## ⚡ Session Handoff — 2026-06-15 12:45 +07

### Suckhoe morning brief moved off `agentTurn`

- Created command wrapper on VPS:
  `/home/hung/.openclaw-suckhoe/workspace/scripts/bsy_morning_brief_pipeline.py`
- Changed `bsy-brief-pipeline-0628` / `Bsy Morning Brief Pipeline (6:28)` from `payload.kind="agentTurn"` to `payload.kind="command"`:
  `OPENCLAW_STATE_DIR=/home/hung/.openclaw-suckhoe /home/hung/.openclaw-suckhoe/workspace/scripts/bsy_morning_brief_pipeline.py`
- Changed catchup `78c05221-6cf5-4a20-b0f2-ad24ca60fe54` / `bsy-brief-catchup-send-0650` to the same wrapper. It now rescues both `prepared` and `ready`, and skips if already `sent`.
- Backup before cron edit:
  `/home/hung/backups/morning-brief-cron-command-20260615-124241/`
- Verified manual `cron run` for both jobs on already-sent 2026-06-15:
  `status=ok`, summary `MORNING_BRIEF_ALREADY_SENT`, no duplicate send.
- Next real UAT: 2026-06-16 after 06:28 and 06:50 VN time:
  `~/.npm-global/bin/openclaw --profile suckhoe cron runs --id bsy-brief-pipeline-0628 --limit 3`
  and check manifest `data/morning-brief/2026-06-16/manifest.json`.

### OpenClaw binary path footgun

- Runtime binary is `~/.npm-global/bin/openclaw` = `2026.6.6`.
- `/home/hung/bin/openclaw` correctly points to `~/.npm-global/bin/openclaw`.
- `/usr/bin/openclaw` still points to the old system install = `2026.5.22`.
- Attempted safe symlink update, but `sudo` requires a password/TTY in this session. User-level login shells already put `~/.npm-global/bin` before `/usr/bin`, but non-login scripts or absolute `/usr/bin/openclaw` remain a footgun.
- To finish later with sudo:
  `sudo ln -sfn /home/hung/.npm-global/bin/openclaw /usr/bin/openclaw && /usr/bin/openclaw --version`

### Suckhoe medication reminder also moved off `agentTurn`

- 2026-06-15 19:30 med reminder failed with `MED_REMINDER_FAIL`; trajectory root cause was Codex bash sandbox error:
  `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`.
- Recovery sent 2026-06-15 reminder directly via:
  `OPENCLAW_STATE_DIR=/home/hung/.openclaw-suckhoe bash /home/hung/.openclaw-suckhoe/workspace/scripts/send_med_reminder.sh`
  Telegram message ID `3692`; send guard now has `sentTargets=["7957776935"]`.
- Changed cron `3eeb73eb-eee3-473a-b233-3d3eb8f72561` / `Nhắc uống thuốc 19:30 VNT (Rèo)` from `agentTurn` to command:
  `OPENCLAW_STATE_DIR=/home/hung/.openclaw-suckhoe bash /home/hung/.openclaw-suckhoe/workspace/scripts/send_med_reminder.sh`
- Backup before edit:
  `/home/hung/backups/med-reminder-cron-command-20260615-210632/`
- Verified manual `cron run` after edit: `status=ok`, summary JSON `status=already_sent`, no duplicate send.

---

## 0. Cách làm việc Hưng kỳ vọng (QUAN TRỌNG NHẤT)

1. **Research read-only TRƯỚC → present plan → CHỜ Hưng duyệt → mới action.** Không tự ý execute khi chưa OK.
2. **PLAN phải có:** Risk/Edge cases + Cost impact + reference lessons-learned.
3. **CHECK 3 tầng:** gateway log + session state (`sessions.json`) + end-user UX (`/status` Telegram). Không chỉ nhìn 1 tầng.
4. **REPORT phải có "What could still be wrong"** — không tô vẽ "done ✅".
5. **TUYỆT ĐỐI không tự đổi** `agents.defaults.model.*`, `auth.profiles.*`, fallback list — hỏi Hưng trước.
6. Tiếng Việt cho hội thoại. Redact mọi secret/token trong output.
7. Khi user nói mơ hồ (vd "chưa utilize được") → **clarify intent trước**, đừng đoán (đã sai 1 lần: pause nhầm 5 jobs hữu ích).

---

## 1. Current state (verified 2026-06-14)

| Component       | hungreo                                                                          | suckhoe                                                                          | nemotron                                                           |
| --------------- | -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| openclaw binary | **2026.6.6**                                                                     | **2026.6.6**                                                                     | **2026.6.6**                                                       |
| Binary path     | `~/.npm-global/lib/...`                                                          | `~/.npm-global/lib/...`                                                          | `~/.npm-global/lib/...`                                            |
| primary model   | **openai/gpt-5.5** (+`models["openai/gpt-5.5"]={agentRuntime:{id:codex}}`)       | **openai/gpt-5.5** (+agentRuntime codex)                                         | **custom/nvidia/nemotron-3-ultra-550b-a55b** (🆕 trial 2026-06-05) |
| fallback        | deepseek/deepseek-v4-pro                                                         | deepseek/deepseek-v4-pro                                                         | deepseek/deepseek-v4-pro (Super entry vẫn giữ trong models)        |
| codex auth      | `openai:hungreo2005@gmail.com [openai/oauth]` **exp 2026-06-21** (re-auth 06-11) | `openai:hungreo2005@gmail.com [openai/oauth]` **exp 2026-06-21** (re-auth 06-11) | n/a                                                                |
| lossless-claw   | **0.12.0**                                                                       | **0.12.0**                                                                       | **0.12.0**                                                         |
| streaming.mode  | off                                                                              | off                                                                              | off                                                                |
| services        | active                                                                           | active                                                                           | active                                                             |

**npm latest (2026-06-14):** openclaw `2026.6.6` (đang chạy, = latest stable; 6.7-beta.1/6.8-beta.1 đã có nhưng pre-release) · lossless-claw `0.12.0` (= latest)

🔴 **QUAN TRỌNG — 6.1 BỎ provider `openai-codex`.** Form model ĐÚNG từ 6.1 = `primary:"openai/gpt-5.5"` + `models["openai/gpt-5.5"]={agentRuntime:{id:"codex"}}` (route Codex OAuth, $0). **ĐỪNG restore về `openai-codex/`** (rule 5.x cũ — đã đảo ngược). Lesson [2026-06-04].

⚠️ **Root cause stability suckhoe (chưa fix tận gốc):** hungreo + suckhoe **share OAuth account** `hungreo2005@gmail.com`. 6.1 cần auth profile `openai/oauth` (mới); suckhoe lúc upgrade chỉ có `openai-codex/oauth` (cũ) → 401 → deepseek. Đã **re-auth device-code 2026-06-04** (token mới exp 06-14) → suckhoe chạy gpt-5.5 OK. **Fix bền = tách OAuth account riêng** (chưa làm — mục 6).

**SSH:** `ssh -o ConnectTimeout=10 -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33`

---

## 2. ✅ RESOLVED — Nemo maintenance (đã được làm trước session 2026-05-29)

Khi verify đầu session 2026-05-29 phát hiện **Nemo đã được migrate xong** (bởi session/agent trước, sau handover 2026-05-28):

- ✅ `env_VER` label đúng `2026.5.27` (label sai `2026.4.12` đã hết).
- ✅ Nemo dùng `EnvironmentFile=%h/.openclaw-nemotron/credentials/gateway.systemd.env` — **không còn 7 inline secrets** trong systemd unit.
- ✅ `ExecStart` trỏ `~/.npm-global/lib/...` — **không còn `/usr/lib`** (system-wide). Arch đồng nhất với hungreo/suckhoe.
- ✅ Duplicate lossless-claw `extensions/` install: **doctor 5.27 đã tự dọn** (`installs.lossless-claw` block removed khỏi openclaw.json). Giờ chỉ còn 1 copy ở `npm/node_modules`.

→ Toàn bộ Option A/B/C đã được thực hiện. Còn lại chỉ là **rotate 7 Nemo secrets** (Hưng tự làm — xem mục 6).

---

## 3. Hard rules từ các incident (đã trả giá)

1. **Upgrade = STOP services TRƯỚC `npm install`** (anti broken-window → tránh silent fallback đốt tiền). Sự cố 2026-05-08: $3 Anthropic leak.
2. **Sau upgrade: DIFF backup vs current `openclaw.json`** — catch auto-migrate. Bug RECURRING: `openai-codex/` → `openai/` ở 5.12, 5.18, 5.22 (chỉ hungreo bị; nghi do hungreo có nhiều plugin entries openai/codex/anthropic/google).
3. **Sau upgrade/restart: audit `sessions.json` GENERALIZED drift** — bất kỳ DM session nào `modelOverrideSource=auto` với `modelOverride != primary` → clear. (Không hardcode tên model — đã miss deepseek pin vì chỉ check anthropic.)
4. **Verify model "thật"** qua `/status` Telegram, KHÔNG chỉ gateway log. Clue: Context size (1.0M = deepseek, 256K = gpt-5.5).
5. **Sau update override.conf phải `systemctl restart`** (không phải `start`) để load env mới. `openclaw update` đôi khi tự start service với env cũ.
6. **`channels.telegram.streaming.mode = "off"`** mặc định cho user-facing bots (tránh leak "Surfacing..."/"Session Status:" drafts vào DM). Hot-reloadable.
7. Patch 2 (`!embedded && messageTool`) + symlink workaround `@mariozechner→@earendil-works`: **ĐÃ OBSOLETE** từ 5.18 (upstream fixed) + lossless 0.11.1 (native). Không cần re-apply nữa.

**Chi tiết:** `kb/lessons-learned.md` — entries [2026-05-08], [2026-05-15], [2026-05-24], [2026-05-24 đêm].

---

## 4. Jobs / cron state (sau session này)

### ⏸️ PAUSED (cố ý)

- `overnight_research_pipeline.sh` (cron 01:00) — boilerplate failing (Gemini + OpenAI API đều fail, watchlist cạn). Giữ pause.
- `rua_cloud_relay.sh` (cron 04:00) — Hưng yêu cầu stop. Chỉ stop **delivery Telegram**.
- ✅ **[2026-06-05] Anthropic Cloud Routine `rua-research-cloud` đã DISABLED** (`trig_01NTznt9onPb1Sgx1sUKFKYM`, `enabled:false`). Trial 7 ngày chạy lố ~6 tuần, mỗi sáng 03:33 VN ăn 1/5 daily routine runs + token Sonnet của Hưng → tắt theo yêu cầu. Repo GitHub còn nguyên. Re-enable: RemoteTrigger update `enabled:true`.
- `hungreo-xfeed.timer` (07:00+19:00) — Hưng yêu cầu stop (X→Telegram scraper không hiệu quả). disabled + stopped. Apify ~$1.08/tháng saved.

### ✅ ACTIVE (đã revert đúng ý Hưng — KHÔNG pause)

`weekly_kickoff.sh`, `weekly_memory_digest.sh`, `night_system_report.sh`, `kb_research_handoff.sh`, `hungreo-vps-ops-report.timer`. **Tất cả KHÔNG dùng Claude tokens** (chỉ openclaw message send / system probe / openai-codex OAuth free).

### Backup locations

- `~/backups/research-jobs-pause-20260525-052851/`
- `~/backups/jobs-revert-and-pause-rua-20260525-054700/`
- `~/backups/xfeed-stop-20260526-080959/`

---

## 5. Đã RESOLVED

### ⬆️ [2026-06-14] Upgrade 6.5 → 6.6 cả 3 (stop-first) — SẠCH, kèm gotcha healthcheck-timer

- **Lý do:** 6.6 = stable latest (06-12). Value: security rollup (transcripts/MCP stdio/Codex HTTP/exec approvals fail-closed/unauthorized DM out of cache) + **#91614 "verify SQLite auth migration before cleanup"** (đúng class bug cắn suckhoe 06-11, Addendum 8) + Codex compaction ownership + Telegram account-scoped topics + config.patch array-replace safety. lossless giữ 0.12.0 (đã latest).
- 🔴 **GOTCHA MỚI (đã ghi lesson + cập nhật skill):** `openclaw-healthcheck.timer` (every 30') tự `systemctl restart` gateway down → suckhoe tự bật lại GIỮA lúc stop-first. **Fix SOP:** stop `openclaw-healthcheck.timer` TRƯỚC khi stop gateways; `start` lại sau restart. (Backup/restore-check timer không cần tắt.)
- **SOP stop-first đầy đủ:** backup ×3 (config+auth.sqlite+sessions+override+nemotron service, suffix `20260614-1700-pre-upgrade-2026.6.6`) → stop healthcheck.timer → STOP 3 → `openclaw update` từng profile (doctor auto, 14-15s) → DIFF sạch → bump `OPENCLAW_SERVICE_VERSION=2026.6.6` + daemon-reload → restart suckhoe→hungreo→nemotron → start lại healthcheck.timer.
- **Verify 3 tầng (KHÔNG tái diễn lesson cũ):** (a) env_VER=2026.6.6 cả 3 · lossless 0.12.0 LOAD cả 3 (hungreo "1 skipped"=benign, đã current) · 0 crash. (a2) DIFF model.\* SẠCH — `openai-codex/`→`openai/` KHÔNG xảy ra; codex runtime `agents.defaults.models["openai/gpt-5.5"].agentRuntime.id="codex"` nguyên. (a3) Auth: suckhoe `Profiles:` populated, token exp 06-21 sống (Addendum 8 KHÔNG tái diễn); hungreo `openai:default` refresh tới 06-24. (b) drift=0 cả 3. (c) **UAT: winner=primary, attempts=1 (no fallback) cả 3** — hungreo+suckhoe `openai/gpt-5.5` ($0 codex), nemotron `deepseek/deepseek-v4-pro` (KHÔNG rớt openrouter PAID).
- **State migration 6.6 benign:** "Migrated 53/26 Telegram dispatch dedupe → plugin state" (suckhoe/nemotron, đúng changelog) + nemotron "Repaired host peer link 1 plugin".
- **Backups/rollback:** `~/.openclaw-*/openclaw.json.bak-20260614-1700-pre-upgrade-2026.6.6` (+auth.sqlite+sessions+override). Rollback: restore → `npm i -g openclaw@2026.6.5` → daemon-reload → restart.
- ⚠️ **What could still be wrong:** UAT là CLI, CHƯA test `/status` từ Telegram của Hưng (tầng UX cuối — gateway log có telegram webhook advertised + channels.status OK, nhưng chưa có user-side confirm). Token codex vẫn exp **06-21** (~7 ngày) — follow-up #1 (tách OAuth account) chưa làm.

### Session 2026-06-05 (cũ hơn) — Nemotron 3 Ultra trial + tắt routine đốt token Claude

- 🐢 **Disabled Anthropic Cloud Routine `rua-research-cloud`** (xem mục 4) — thủ phạm "Daily included routine runs 1/5" + token Sonnet. Verified `enabled:false` qua list lại.
- 🆕 **Nemotron bot: trial Nemotron 3 Ultra (550B-A55B, ra mắt Computex 2026, release 04/06)** làm primary, qua **NVIDIA NIM** (free, key sẵn có `NVIDIA_API_KEY`, endpoint `integrate.api.nvidia.com` — model có trong catalog, verified).
  - Thêm model entry vào `models.providers.custom.models[]` (`contextWindow:1048576`, `maxTokens:4096`, `reasoning:false`). Primary `deepseek/deepseek-v4-pro` → `custom/nvidia/nemotron-3-ultra-550b-a55b`; fallback giữ `deepseek/deepseek-v4-pro`. Entry Super vẫn còn → switch lại dễ.
  - Hot reload + restart **chỉ nemotron** (không đụng hungreo/suckhoe). Config validate pass.
  - **Verify 3 tầng:** log `agent model: custom/nvidia/nemotron-3-ultra-550b-a55b` + 4 plugins + 0 lỗi · drift=0 · UAT thật `status=ok`, `provider=custom model=nvidia/nemotron-3-ultra-550b-a55b` no-fallback, `ULTRA_OK`, ~4.2s, cost $0 (free NIM).
  - **Backup:** `~/.openclaw-nemotron/openclaw.json.pre-ultra-trial-20260605-071025`. Rollback: restore backup → restart nemotron.
  - **Benchmark Ultra (Artificial Analysis):** Intelligence Index **48** (#1 US open-weights, trên Gemma 4: 39; nhưng dưới Kimi K2.6 TQ: 54). Terminal-Bench 2.0 coding 54%, PinchBench agent 91%, Ruler@1M 95%, **>300 tok/s**. License OpenMDW-1.1 (commercial OK).
  - ⚙️ **Model entry `reasoning:true`** (backup `openclaw.json.pre-ultra-reasoning-20260605-074153`) — nhưng đây CHỈ là cờ "model hỗ trợ reasoning". Runtime `agents.defaults.thinkingDefault = "off"` → **thinking/CoT thực tế vẫn TẮT** (verified 2026-06-05). Bot báo "Reasoning: off" là ĐÚNG. → Honesty cải thiện là nhờ **fix docs**, KHÔNG phải thinking. Muốn bật reasoning thật = đổi `thinkingDefault` (CHƯA làm; cân nhắc vì chậm hơn + lịch sử `reasoning_content` crash 2026-04-27).
  - 🐞 **Root cause vụ "fake it":** docs workspace Nemo (`TOOLS.md`/`SOUL.md`/`AGENTS.md`) vẫn ghi config CŨ (primary=deepseek, fallback=super) → bot đọc thấy mâu thuẫn với runtime (Ultra) → bịa lý do. **KHÔNG phải model dối, mà docs stale.** Đã fix 9 chỗ trong 3 file (backup `*.bak-20260605-090111-pre-ultra-docfix`). Verify session mới: bot trả lời đúng "primary=Ultra, fallback=deepseek, docs khớp runtime".
  - 🧪 **Test verdict (thinking OFF — fast mode, verified qua trajectory):** honesty/tỉ giá ✅ + giá vàng SJC ✅ (search THẬT web_search+web_fetch, grounded, calibrate — KHÔNG bịa) · self-ID ✅ (sau fix docs) · convert JSON→YAML ✅ 8s · math giá/m² ✅ 9s. → Ultra cho structured task + grounded factual lookup: **đáng tin ngay cả khi thinking off**.
  - ✅ **[DONE 2026-06-05]** Hưng đã đổi BotFather display name (bỏ "DSV4-Pro"). Subagents đã đổi sang Ultra primary (`agents.defaults.subagents.model.primary=custom/nvidia/nemotron-3-ultra-550b-a55b`, fallback deepseek) — backup `openclaw.json.pre-subagents-ultra-20260605-092447`. Thinking giữ `off` (data test: medium chậm +44% không tăng chất lượng, off đủ cho task structured).
  - 🔀 **[chiều 2026-06-05] Hưng nhờ bot Nemo tự đổi sang OpenRouter** (bot dùng `apply_patch`+`exec` tự sửa openclaw.json + `/restart` lúc 15:56 — authorized, Hưng xác nhận). Bot thêm provider `openrouter` (`${OPENROUTER_API_KEY}`) + đổi primary main+sub → `openrouter/nvidia/nemotron-3-ultra-550b-a55b`.
  - 🔴 **OpenRouter Ultra 429 LIÊN TỤC** (model ra hôm qua, provider thượng nguồn capacity-limited — KHÔNG phải hết credit, balance $3.42) + chậm (~37s). NIM `custom/` cả sáng chỉ 1 timeout → ổn định hơn nhiều.
  - ✅ **Fix (Hưng duyệt): chèn NIM Ultra vào giữa fallback chain** để giữ Ultra sống khi OR fail. Backup `openclaw.json.pre-nim-failover-20260605-172821`.
  - **State cuối Nemo (verified):** primary main+sub = `openrouter/nvidia/nemotron-3-ultra-550b-a55b` · fallback = `[custom/nvidia/nemotron-3-ultra-550b-a55b (NIM), deepseek/deepseek-v4-pro]` · thinkingDefault=off · service active 6.1 · 0 errors. Provider `custom`(NIM)+`deepseek`+`openrouter` đều còn trong config.
  - ⚠️ **Governance note:** bot Nemo CÓ khả năng `apply_patch`+`exec` tự sửa `model.*` + restart chính nó. Lần này authorized; nhưng đây là quyền mạnh — cân nhắc siết nếu không muốn bot tự đổi config.

### Session 2026-06-06 — Fix Ultra "rớt hoài": bot đã hạ `timeoutSeconds` 180→45

- 🔴 **Triệu chứng:** cả ngày 06-06 Ultra rớt deepseek liên tục (Hưng thấy "rớt ultra hoài"). Log: CẢ openrouter LẪN NIM Ultra đều `reason=timeout`, abort tại đúng **`durationMs≈45361`** (45s); deepseek (nhanh hơn) bắt 5/6 turn.
- 🎯 **Root cause:** `agents.defaults.timeoutSeconds` = **45** (hôm qua sáng còn 180). **Bot Nemo tự hạ xuống 45 khi tự sửa config 06-05 chiều** (có session `nemo-timeout45-uat`). Ultra 550B latency dao động 15-50s+ → ngưỡng 45s cắt mất turn chậm → luôn rớt deepseek. **Đây là self-edit thứ 2 của bot ngoài vụ đổi OpenRouter.**
- ✅ **Fix (Hưng duyệt): nâng `timeoutSeconds` 45→120.** Backup `openclaw.json.pre-timeout120-20260606-201938`. UAT sau fix: winner=Ultra(openrouter) 21s no-fallback, đáp án chuẩn. → turn chậm 45-120s giờ kịp trả bằng Ultra thay vì bị cắt.
- **State cuối (verified 06-06):** primary main+sub=`openrouter/nvidia/...ultra` · fb=[NIM ultra, deepseek] · timeoutSeconds=120 · thinking off · service active 6.1.
- ⚠️ **Pattern cần chú ý:** bot Nemo đã tự sửa config **2 lần** (model→openrouter + timeout→45). Lần 1 Hưng nhờ; lần 2 (timeout) là bot tự thêm khi "tinh chỉnh" → gây sự cố. **Cân nhắc siết quyền ghi openclaw.json của bot** (governance, chưa làm).

### Session 2026-06-07 — Sync TOOLS.md khớp chain mới (docs-stale lần 3)

- 🐞 Đổi OpenRouter + thêm NIM failover + nâng timeout (06-05/06) nhưng **quên update TOOLS.md** → bot báo "fallback = deepseek" (thiếu NIM giữa chain). Cùng bệnh docs-stale.
- ✅ Sync TOOLS.md (4 chỗ): primary=openrouter/ultra, fallback [NIM ultra → deepseek], timeout 120, thinking off. Backup `TOOLS.md.bak-*-sync-openrouter-chain`. UAT session mới: bot báo đúng full chain 2 bước. Lesson tái khẳng định: đổi `model.*`/timeout → update workspace docs NGAY (đã lặp 3 lần).

#### Còn lại (mục cũ 06-06):

- ⚠️ **Còn lại:** (1) Rate limit free NIM có thể đẩy sang fallback deepseek khi tải cao (im lặng — theo dõi log). (2) Bot vẫn là trial — task narrative/critical vẫn cấm (memory). (3) `reasoning:true` trên model entry chỉ là cờ capability; thinking thật do `thinkingDefault` (giá trị hợp lệ: off|minimal|low|medium|high|xhigh|adaptive|max — KHÔNG phải "on").

### 📰 [2026-06-14] Fix permanent morning-brief pipeline (suckhoe) — fail nhiều ngày

- **Triệu chứng:** Bsy Rùa báo "Morning brief failed ở editorial/quality gate: 2 tin AI trùng sự kiện". Fail nhiều ngày (06-09/13 `ready`-không-send, 06-14 `prepared`-abort).
- **Root cause (2 mode):** (1) Script `prepare` dedup máy móc (`topic_similarity>0.38`) KHÔNG bắt được "cùng sự kiện khác câu chữ" — 2 tin Anthropic (Amazon-CEO-crackdown vs Anthropic-gỡ-Fable5) chỉ similarity **0.11** → lọt cả 2 → **cron prompt dặn agent "thấy 2 tin cùng sự kiện → FAIL cả brief"** → Rùa abort cả world/vn. (2) Mode `ready`-không-send: agent biên tập xong nhưng không hoàn thành bước send trong 1 turn (timeout 420s).
- **Fix permanent (4 + 1 bonus, Hưng duyệt):** Script `bsy_morning_brief.py` (backup `*.bak-20260614-0655-pre-dedup-fix`):
  - **#1 Entity-dedup AI**: thêm `AI_ORG_ENTITIES` + `shared_ai_org()`; trong `pick_top` mục AI = max 1 tin/công ty → backfill từ 5 feed → 3 tin distinct. (LLM bắt same-event tốt nhưng deterministic = robust; verified AI hết collision.)
  - **#2 Graceful degrade**: nới gate "đúng 3 tin" → ">=2" (`prepare_news_items`/`write_editorial_sections`/`validate_rendered`) → 1 mục thiếu tin KHÔNG nuke cả brief.
  - **#3 Cron prompt**: bỏ lệnh "agent abort khi trùng" → agent CHỈ dịch, không tự bỏ tin/abort, không chặn world/vn. (Backup msg `/tmp/bsy-cron-msg-backup-*`.)
  - **#4 Catch-up cron** `bsy-brief-catchup-send-0650` (06:50, `--command` deterministic, no-deliver, guard `status==ready` mới send) → cứu mode ready-không-send.
  - **Bonus bug**: `polish_news_summary` regex `^(Theo|By|From)...\.` ăn nguyên summary 1-câu mở đầu "Theo" → rỗng. Fix: chỉ strip nếu còn non-empty. (Latent bug ảnh hưởng editorial Rùa.)
- **Verified:** prepare fresh → AI 3 tin distinct (Amazon/Anthropic + Hollywood + Google-court), NONE collision · editorial+render OK · **brief 06-14 ĐÃ SENT** (status sent) tới Telegram Hưng · script syntax OK · suckhoe active.
- ⚠️ **Còn lại:** sáng mai 06-15 cron tự chạy fresh là test thật cuối cùng. Entity-dedup "1 tin/công ty cho AI" có thể đôi khi drop 1 tin OpenAI/Google distinct (đánh đổi: brief đa dạng hơn) — Hưng tune `AI_ORG_ENTITIES`/logic nếu muốn.

### ⬆️ [2026-06-11 chiều] Upgrade 6.1→6.5 + lossless 0.11.3→0.12.0 cả 3 — kèm 1 bug migration phải vá

- **Lý do upgrade:** 6.5 = stable latest (09/06, "June floor"); security hardening (exec approvals fail-closed, transcript/MCP boundaries) + auth→SQLite + codex fixes. Lossless 0.12.0: security taint + cron session keys fix (batch đúng plan cũ).
- **SOP stop-first đầy đủ:** backup ×3 (config+lcm.db+auth-profiles+sessions, suffix `20260611-1355-pre-upgrade-2026.6.5` + override.conf/service) → STOP 3 → `openclaw update` từng profile → DIFF (sạch, model.\* nguyên) → lossless 0.12.0 per-profile npm → bump `OPENCLAW_SERVICE_VERSION=2026.6.5` + daemon-reload → start suckhoe→hungreo→nemotron.
- 🔥 **BUG 6.5 trên suckhoe: auth→SQLite migration KHÔNG chạy** → store SQLite không tồn tại → `Profiles: (none)` → suckhoe `reason=auth` rớt deepseek (hungreo migrate OK `auth_profile_store:1`). **Fix: `doctor --fix` (stopped, targeted)** → "Migrated auth profile JSON into SQLite" → đủ profiles (token exp 06-21 sống), JSON gốc đổi tên `*.sqlite-import.*`. DIFF sau --fix sạch. KHÔNG cần device-code lần 3.
  - ⚠️ Sub-lesson: `sqlite3.connect()` (python check) TỰ TẠO file rỗng → suýt chặn migration; đã xóa file 0-byte trước khi --fix. Đọc sqlite chỉ nên `file:...?mode=ro`.
- **Verify cuối:** cả 3 active · env_VER=2026.6.5 · lossless=0.12.0 · drift=0 · UAT hungreo gpt-5.5 15s + suckhoe gpt-5.5 13s (no-fallback) · LCM 0 lỗi.
- 🔧 **[ĐÍNH CHÍNH 06-11, Rùa phát hiện — Claude verify sai path]:** hungreo thực tế vẫn LOAD lossless **0.11.3** sau upgrade! Hungreo có 2 bản copy: `npm/projects/martian-...-fde018f0ba/` (pinned install — gateway load từ ĐÂY, 0.11.3) vs `npm/node_modules/` (0.12.0 mình cài — KHÔNG được load). Đây chính là thứ warning "conflicting plugin install metadata" cảnh báo; `openclaw update` đã "skipped" plugin này. **Fix:** `openclaw --profile hungreo plugins update @martian-engineering/lossless-claw@0.12.0` (cơ chế chuẩn, update pinned dir + registry) → restart → plugins list = **0.12.0 live**, 0 LCM error, UAT pass. Suckhoe/nemotron không bị (chỉ có 1 copy ở node_modules, đã verify load 0.12.0 qua `plugins list`).
- 📌 **Lesson:** verify plugin version phải bằng **`openclaw plugins list`** (path + version ĐANG LOAD), KHÔNG phải tìm package.json bất kỳ trên đĩa. Output `openclaw update` có "X skipped" → phải truy plugin nào bị skip.
- ✅ **[DONE 06-11] Dọn "conflicting plugin install metadata":** root = legacy `plugins/installs.json` (5.x, stale) đụng SQLite `installed_plugin_index` (đã verify SQLite = truth đúng). Archive rename → `installs.json.conflict-archived-20260611-1426` → **doctor warning 3→0**, restart sạch, lossless 0.12.0 giữ, drift none, UAT pass. Chi tiết: lessons Addendum 9.
- ✅ **[RESOLVED 06-11] Nemotron model:** bị đổi 06-09 19:24 (khả năng bot tự sửa, lần 3) thành `primary: deepseek/deepseek-v4-pro, fallback: openrouter/...ultra (PAID)`. **Hưng duyệt GIỮ NGUYÊN:** "Ultra free unstable, Ultra paid ok hơn nhưng mắc hơn DS" → DeepSeek primary là đúng. Trial Ultra-as-primary kết thúc; Ultra paid chỉ còn là fallback hiếm khi deepseek fail (cost exposure nhỏ, credit OR còn $1.63). → Đây giờ là **config chính thức** của nemotron.

### 🔑 [2026-06-11] Rùa "dumb/stuck" từ 10am — root cause token codex sắp chết → re-auth CẢ hungreo + suckhoe

- **Triệu chứng:** Hưng thấy Rùa (hungreo) "dumb dumb, mắc kẹt, không action rõ ràng" từ ~10:00. Lo "cấu trúc openclaw lệch standard".
- **Root cause (verified):** KHÔNG phải config (mtime nguyên từ 06-04, chạy ngon 06-05→09). Là **token codex `openai:default` exp 2026-06-12 (hôm sau!) flaky dần trước khi chết**: transport errors `invalid_provider_content_type` tăng 06-09: 0 → 06-10: 12 → 06-11: 22; log có `empty response detected... retrying` (codex trả RỖNG → reply nghèo = "dumb") + `lane wait exceeded 62s` (turn xếp hàng = "kẹt", reply 4-6 phút).
- **Fix:** device-code re-auth (Hưng nhập code) cho **hungreo** + **suckhoe** (exp 06-14, làm 1 thể). Profile mới `openai:hungreo2005@gmail.com` **exp 2026-06-21** — auth-state order đặt ĐẦU + lastGood cả 2. DIFF config sau login: sạch (chỉ lastTouchedAt; login KHÔNG đụng model.\* vì không dùng `--set-default`). Restart cả 2 → 5 plugins, gpt-5.5.
- **Verify:** transport errors = 0 sau restart · UAT cả 2: gpt-5.5 `fallbackUsed=false` (hungreo 13s, suckhoe 18s) · 0 drift · 0 fallback deepseek suốt incident (token chưa chết hẳn, chỉ flaky).
- **Cruft note:** cả 2 profile còn auth profiles CŨ đã/sắp hết hạn trong store (hungreo: `openai:default` exp 06-12; suckhoe: `openai:default` exp 05-24 + `openai:chatgpt-...` exp 06-12) — vô hại (order sau), dọn sau nếu muốn.
- ⏰ **Token mới hết hạn 2026-06-21 (~10 ngày)** → sẽ tái diễn. **Fix gốc vẫn là tách OAuth account riêng cho suckhoe** (follow-up #1, chưa làm). Lesson: triệu chứng "bot ngu + chậm dần vài ngày trước token expiry" = signature của token sắp chết — check `models auth list` expiry TRƯỚC khi nghi config/structure.

### 🧹 [2026-06-10] Dọn storage VPS — 61G→50G (63%→52%), giải phóng 11G

- **Hưng thấy storage phình.** Nguyên nhân chính: (1) `openclaw-backup.timer` daily ~2.1G/profile/đêm (~10G baseline, rotation giữ 3); (2) codex `logs_2.sqlite` 546M đang phình; (3) lcm.db/memory sqlite tăng theo chat; (4) backup upgrade cũ tích tụ.
- **Đã dọn (Hưng duyệt, safety-first — lsof check trước, services active suốt):** backup pre-5.18/5.22/5.26/6.1 (manual 566M+1.3G, lcm.db.bak ×6, sessions.bak pre-6.1 ×3 ~475M) + npm cache 3.5G + trivy 1.1G + pip 173M + **RETENTION_KEEP 3→2** (backup `~/bin/openclaw-backup.sh.bak-*-retention3`) + prune bản 06-08.
- **GIỮ (đang dùng):** whisper cache 1.7G (hungreo+suckhoe config tham chiếu — voice transcription); 2 bản daily backup mới nhất; mọi lcm.db/sessions sống.
- **Còn dọn được sau (chưa làm):** `~/.local/lib/python3.12` nvidia+torch+cuda ~7G (VPS không GPU — cần verify import trước); codex multi-platform binaries ~4G (npm update kéo lại); `logs_2.sqlite` 546M (cần tìm rotation). Disk 52% — không gấp.

### 💸 [2026-06-09] Cost fix — OpenRouter PAID đốt $3.37, chuyển về NIM free

- **Hưng phát hiện:** trial Ultra qua OpenRouter vài ngày, ít request mà đã tốn **$3.37** (mắc hơn DeepSeek). Hỏi sao Nemotron "mắc dù open-source/free".
- **Root cause (verified qua OpenRouter API `/auth/key` + token usage):** primary = `openrouter/nvidia/...ultra` bản **PAID** ($0.5/$2.5 per M), KHÔNG phải `:free`. Free-WEIGHTS ≠ free hosting — trả tiền GPU cho OpenRouter. **Amplifier: LCM nhồi context KHỦNG mỗi turn** (~50-60k input + 200-300k cacheRead) → mỗi lượt $0.03-0.09. "Ít request mà tốn" = mỗi request rất to.
- **Fix (Hưng duyệt — chọn NIM free, chấp nhận timeout):** primary main+sub → `custom/nvidia/nemotron-3-ultra-550b-a55b` (**NIM, $0**); fallback → `[deepseek/deepseek-v4-pro]` (**DeepSeek chính chủ** api.deepseek.com, ổn định, rẻ). **BỎ OpenRouter PAID khỏi primary → cost dừng $3.37, không tăng.** Backup `openclaw.json.pre-nim-free-primary-20260609-171034`. OpenRouter còn $1.63 credit để đó.
- 🔴 **NIM free CHẬM/timeout nhiều:** UAT đầu sau switch → NIM timeout 120s ngay cả prompt "PONG" → fallback deepseek. Research: NIM free = 40 RPM, prototyping-grade, không SLA. → Thực tế Nemo có thể chạy **phần lớn bằng DeepSeek fallback** khi NIM bận; Ultra chạy khi NIM rảnh. Hưng **chấp nhận** (trial tiếp NIM free).
- ✅ **Monitoring fallback:** SOUL.md "Fallback Alert — BẮT BUỘC" (L104) còn nguyên → bot tự chèn ⚠️ banner khi chạy fallback. Hưng yêu cầu báo mỗi lần timeout→fallback.
- **State cuối:** primary NIM-Ultra($0) · fb DeepSeek-direct · thinking=medium · OpenRouter paid OUT · service active.

### 🔧 [2026-06-09] Fix Nemo trả markdown table trên Telegram (vỡ format)

- **Triệu chứng:** Nemo trả comparison bằng markdown table `|...|` → Telegram không render → vỡ. Hưng bảo bot tự chỉnh nhiều lần không được.
- **Root cause (chứng minh bằng test):** luật "no table" ĐÃ có ở 5 chỗ (SOUL/AGENTS/TOOLS/MEMORY) nhưng **thinking=off → model Ultra phớt lờ** (bullet-bias thua table-habit). Test A/B: `off` → 5 dòng `|` (table); `medium` → 0 (bullet). → instruction KHÔNG sửa được bằng lời, phải bật thinking.
- **Fix (Hưng duyệt):** (1) thêm `[SYSTEM RULE] CẤM markdown table` ở TOP SOUL.md (imperative + ví dụ + self-check), backup `SOUL.md.bak-*-notable-rule`; (2) **`agents.defaults.thinkingDefault: off → "medium"`** (backup `openclaw.json.pre-thinking-medium-20260609-153332`).
- ⚠️ **KHÔNG 100% (verified, không tô vẽ):** 4 mẫu sau fix → 3 sạch/inline-OK, 1 vẫn lọt table. Medium giảm mạnh nhưng không tuyệt đối. Đánh đổi: chậm hơn ~40% (thinking on). Không có fix deterministic sạch (transform hook = inbound; Telegram không render table).
- **State nemotron:** thinkingDefault=**medium** (đổi từ off), primary openrouter/ultra, fb [NIM,deepseek], service active.
- 📌 Nếu muốn gần 100% hơn: thử `thinking=high` (chậm hơn nữa) hoặc chấp nhận slip hiếm. Bot trial → medium là pragmatic.

### 🔎 [2026-06-07] Investigate hungreo "leak message English" — bot Rùa TỰ FIX, Claude verify

> Hưng thấy 2 message English nội bộ leak ra Telegram. Bot hungreo (🐢 Rùa) tự nhận đã fix. Claude verify độc lập (KHÔNG tin self-report).

- ✅ **Leak CÓ THẬT:** msg #7005 (08:17) + #7006 (09:02) → DM Hưng. Là **completion-summary** của cron calendar reminder (isolated agentTurn) bị deliver ra chat (English: "I sent...", "heartbeat_respond not available, finished quietly").
- ✅ **Fix của bot ĐÚNG & AN TOÀN (verified live SQLite store):** Daily calendar planner (743fd894) + reminder 06-08 (6afed4e8) → `delivery.mode="none"`; **job body tự gửi nội dung THẬT qua CLI** `openclaw message send ... --message "<nội dung>"` rồi `HEARTBEAT_OK`. Planner prompt còn cấm gửi completion summary. → **KHÔNG mất reminder** (vẫn nhận nhắc lịch), chỉ chặn noise. Không over-correct. Backup bot tạo: `cron/jobs.json.migrated.bak-20260607-133539-pre-delivery-leak-fix`. Không job live nào còn mode `announce` dễ leak.
- 🆕 **HẠ TẦNG: OpenClaw đã MIGRATE cron từ `~/.openclaw-hungreo/cron/jobs.json` → SQLite `state/openclaw.sqlite`.** File `jobs.json.migrated` (30 job) là CŨ/deprecated; **live store thật = `openclaw cron list` (8 job)**. → Lần sau đọc cron qua `openclaw --profile hungreo cron list/get`, KHÔNG đọc jobs.json.
- ⚠️ **hungreo transport transient:** storm `[openai-transport] Connection error / invalid_provider_content_type` (gpt-5.5/codex) 13:36–41 (~12 lần) rồi NGỪNG. UAT sau đó: gpt-5.5 fallbackUsed=false. **0 fallback deepseek cả ngày** → không đốt tiền. Theo dõi nếu tái diễn (codex app-server hiccup, trùng lúc bot chạy verify nặng).
- ✅ **Suckhoe OK** — channels.status ✓ đều 30'. Cảnh báo "token/target mismatch" của bot = false alarm từ probe của chính nó, suckhoe không sao.
- ⚠️ **Governance:** bot hungreo (Rùa) tự `apply_patch`/`exec`/`openclaw cron edit` + tự sửa cron live. Lần này làm ĐÚNG + có backup + honest report, nhưng vẫn là quyền tự-sửa-config (giống Nemo).
- 📋 **Liên quan câu hỏi "no version report" hôm trước:** job `OpenClaw Version Check (daily 7:00)` + Morning Brief có trong file CŨ `jobs.json.migrated` nhưng KHÔNG thấy trong live `cron list` (8 job) → nghi migration DROP nhiều job, hoặc bị xóa. Chưa xác nhận. Đáng check nếu Hưng muốn khôi phục version-report/morning-brief.

### 🔎 [2026-06-07] Quality audit Nemo — findings (Hưng chọn "chỉ báo cáo, CHƯA fix")

> Verified read-only, KHÔNG sửa gì. Để pending cho lần sau khi Hưng duyệt.

- **Bot báo version sai:** Nemo nói "latest 5.26 / gateway có thể 5.3-1" → SAI. Thật = **2026.6.1** (env_VER). Nguyên nhân: **MEMORY.md Nemo stale** — version cao nhất ghi = 5.26, KHÔNG có 5.27/5.28/6.1 (upgrade do CC/Antigravity ở tầng hệ thống, không ghi ngược vào memory Nemo).
- **MEMORY.md nhiễu:** 8/66 dòng là rác `[score=… source=…]` do cron "Memory Dreaming" (config `every:2h`, block `dreaming`) tự promote snippet LCM kèm điểm số.
- **Report jobs (đều của hungreo, KHÔNG phải Nemo):**
  - `vps_ops_report.sh` (`hungreo-vps-ops-report.timer`, 03:20) ✅ chạy OK, có `openclaw --version` + service states, gửi topic Telegram `openclaw-ops` (chat `-1003700265995`). → Hưng "không thấy" vì nó vào TOPIC đó, không phải DM Nemo.
  - `night_system_report.sh` (cron 20:45) 🔴 nghi hỏng: log `night-system-report.log` đứng từ **2026-04-06**, đầy lỗi `line 25: command not found` (python heredoc/f-string parse fail). Chưa xác nhận có còn gửi không.
  - **KHÔNG có job "alert version mới"** riêng (so npm latest vs installed → ping). Các đợt 5.x→6.1 upgrade tay nên không alert.
- **Quality verdict:** hành vi/độ thật TỐT (hedge, search thật, thú nhận chưa chắc); nhưng "trí nhớ" cũ + bẩn → trả lời nghe "kỳ kỳ".
- ✅ **[FIX DONE 2026-06-07] Behavioral fix "CHECK LIVE TRƯỚC → trả lời SAU":** siết guardrail trong `TOOLS.md` (Verification Discipline rewrite) + `SOUL.md` (cấm line) — cho lệnh probe đơn giản nhất (`/proc` env, `openclaw --version`, `systemctl`, đọc `openclaw.json`), cấm trả lời hiện trạng từ MEMORY.md/history. Backup `TOOLS.md.bak-*-verify-live-first` + `SOUL.md.bak-*`. **Verified:** UAT session mới hỏi version → bot CHẠY exec (`openclaw --version`+`systemctl`) → báo đúng `2026.6.1 (verified live)`, không còn đọc 5.26 từ memory. **Đây là fix gốc:** dù memory stale, bot luôn check thực tế.
  - Bài học: guardrail "verify when possible" (cũ) quá yếu → bot vẫn đọc memory rồi mới "offer to check". Phải imperative ("CHECK TRƯỚC, trả lời SAU") + đưa lệnh probe cụ thể thì bot mới thật sự chạy live.
- **Pending CÒN LẠI (chờ Hưng duyệt):** (1) dọn 8 dòng rác `[score=]` trong MEMORY.md (giờ ít gấp vì bot check live); (2) debug/fix `night_system_report.sh` (đụng hungreo → hỏi trước); (3) tạo job alert-version-mới (so npm latest vs installed → ping).

### Session 2026-06-04 — Upgrade 6.1 (Antigravity chạy + Claude review) + sửa breaking codex provider

- ✅ **Upgrade 5.28 → 6.1 cả 3** (Antigravity Opus 4.6 thực thi, Claude Code review độc lập). Backup đầy đủ + state DBs.
- 🔥 **6.1 BỎ provider `openai-codex`** → `openai-codex/gpt-5.5` = "model not found". Form đúng = `openai/gpt-5.5`+`agentRuntime:{id:codex}`. Claude Code **suýt sai** vì áp rule 5.x "restore openai-codex/" → đã đảo ngược + sửa docs/lessons/skill. hungreo + suckhoe đều chuyển sang form mới.
- 🔑 **suckhoe re-auth codex** (Hưng chạy device-code) tạo profile `openai/oauth` (exp 06-14) → restart load auth → UAT winner=openai/gpt-5.5 no-fallback ✅. Clear pin deepseek session Hưng.
- ⚠️ **Antigravity miss:** báo "hungreo không bị migrate" (sai — đã migrate) vì DIFF ở bước 4 trước restart; 6.1 migrate lúc gateway START. SSH review độc lập bắt được. Lesson [2026-06-04].
- Backups: `*-pre-upgrade-2026.6.1`, `*-pre-6.1`, `*-pre-fix-codex-6.1-form`, `sessions.json.bak-*-pre-clear-postauth`.

### Session 2026-06-03

- ✅ **Upgrade 5.27 → 5.28 cả 3 profiles** (stop-first, theo skill `openclaw-ops`). Lý do: cluster Codex auth-recovery + timeout fixes ("warm provider auth off main thread", "honor Codex response timeouts") + cron robustness.
  - **Auto-migrate hungreo `openai-codex/`→`openai/` LẶP LẠI** (giống 5.27) → DIFF bắt → restore + validate pass.
  - 🔥 **nemotron crash startup**: 5.28 bỏ legacy key `agents.defaults.embeddedPi` → `agents.defaults: Invalid input`. Fix: **rename `embeddedPi`→`embeddedAgent`** giữ nguyên `{executionContract:"strict-agentic"}` (guardrail Nemo). Lesson [2026-06-03]. Backup `openclaw.json.bak-20260603-*-pre-fix-embeddedPi`.
  - Verify 3 tầng: env_VER=5.28 cả 3 + 0 errors · 0 drift · UAT `agent model: openai-codex/gpt-5.5` no-fallback, `FINAL_ONLY_OK`.
  - **Backups:** `openclaw.json.bak-20260603-1731-pre-upgrade-2026.5.28` (3 profiles) + `override.conf.bak-20260603-1731-pre-2026.5.28` + nemotron service `.bak`.
- ✅ **Clear drift suckhoe** user `8288766754` (pinned deepseek do timeout storm 02/06) → về primary gpt-5.5. Backup `sessions.json.bak-20260603-*-pre-clear-drift-8288766754`. Vụ timeout chỉ transient 02/06 (18 lần), 03/06 sạch. Session Hưng (`7957776935`) chưa từng dính.

### Session 2026-05-29

- ✅ **Upgrade 5.26 → 5.27 cả 3 profiles** (stop-first, đúng quy trình). lossless giữ 0.11.3 (đã latest).
  - Khi vào session phát hiện binary thật là **5.26** (handover ghi 5.22) → upgrade 5.22→5.26 đã chạy LIVE bởi session trước (log có broken-window `Cannot find module` ở process cũ, transient, không hại lâu dài vì fallback deepseek rẻ + 0 drift).
  - **Auto-migrate hungreo `openai-codex/gpt-5.5` → `openai/gpt-5.5` LẶP LẠI** ở 5.27 (DIFF bắt được). Lần này 5.27 còn **thêm field mới** `agentRuntime:{id:"codex"}` vào model entry. Đã restore về `openai-codex/gpt-5.5` (proven-good, $0 Codex OAuth) + config validate pass.
  - Doctor 5.27 tự dọn duplicate lossless `extensions/` install + sửa `lastTouchedVersion` 2026.4.12→5.27.
  - Verify 3 tầng: env_VER=5.27 cả 3 + 0 errors · 0 session drift · UAT `agent model: openai-codex/gpt-5.5` no-fallback, toolSummary 1/0, payload `FINAL_ONLY_OK`.
  - **Backups:** `openclaw.json.bak-20260529-1436-pre-upgrade-2026.5.27` (3 profiles) + `override.conf.bak-20260529-1436-pre-2026.5.27` (hungreo/suckhoe) + nemotron service `.bak-20260529-1436-pre-2026.5.27` + hungreo `.bak-<ts>-pre-restore-codex-from-527`.

### Session trước (2026-05-28 và sớm hơn)

- ✅ Upgrade 2026.5.22 + lossless 0.11.2 (caught + restored auto-migrate hungreo).
- ✅ suckhoe OAuth `refresh_token_reused` (shared account `hungreo2005@gmail.com` → single-use refresh token bị hungreo invalidate). Fix verified: re-auth device-code (KHÔNG copy token). Lesson [2026-05-24 đêm] đã ghi.
- ✅ Telegram streaming leak → streaming.mode=off cả 3.
- ✅ Lesson `chub`/`get-api-docs` skill = wrong tool cho openclaw VPS ops (khác domain; openclaw context-load đã có qua CLAUDE.md + lessons-learned markdown).

---

## 6. Open follow-ups (chưa làm, low priority)

- **[Hoãn theo ý Hưng 2026-05-29]** Xóa orphan entry `plugins.entries."memory-lancedb"` ở suckhoe (đang `enabled:false`, plugin chưa cài → validate warn). Zero-risk, cần restart suckhoe → gộp vào lần restart sau. Lesson [2026-05-29].
- **[Giữ nguyên theo ý Hưng 2026-05-29]** Gemini API key plaintext trong `memorySearch.remote.apiKey` của hungreo — tradeoff biết trước (lesson [2026-05-17], chuyển key khỏi env để chặn Google web-search routing). Không rotate lúc này.
- Rotate 7 Nemo secrets (sau khi migrate EnvironmentFile — migrate đã xong, chỉ còn rotate).
- Rotate xfeed `APIFY_TOKEN` + `TELEGRAM_BOT_TOKEN` (@hungreo_scrapper_bot) — pending từ 2026-05-02.
- Audit lossless-claw 0.11.3 breaking changes (pull tarball) TRƯỚC nếu chọn Option D.
- ✅ **[DONE 2026-05-29]** Project skill `openclaw-ops` đã build tại `.claude/skills/openclaw-ops/SKILL.md` (gói health-check + drift-detection + upgrade SOP stop-first + hard rules). Gõ `/openclaw-ops`. Auto-load nhờ CC ≥ 2.1.157 (Hưng đang 2.1.150 → cần update CC để load). CHƯA commit.
- Optional còn lại: weekly cron tự chạy audit (DIFF config + sessions drift). Defense-in-depth. Hưng chưa duyệt.
- Optional: ghi note vào `LOCAL_CONTEXT.md` rằng `hungreo-xfeed.timer` + `rua_cloud_relay.sh` đã stopped (để session sau không nhầm đang chạy).

---

## 7. Verify commands cheat-sheet

```bash
# Services + version thật
for s in hungreo suckhoe nemotron; do
  PID=$(systemctl --user show openclaw-gateway-$s.service --property=MainPID --value)
  echo "$s: $(systemctl --user is-active openclaw-gateway-$s.service) env=$(strings /proc/$PID/environ 2>/dev/null | grep ^OPENCLAW_SERVICE_VERSION= | cut -d= -f2)"
done

# DIFF config vs backup (auto-migrate catch)
# So sánh agents.defaults.model.primary + fallbacks + auth.profiles keys

# Sessions drift (generalized)
# DM session nào modelOverrideSource=auto & modelOverride != primary → clear

# npm latest
npm view openclaw version; npm view @martian-engineering/lossless-claw version
```
