# PLAN — Gỡ Nemo + đưa hungreo_claude_bot lên VPS 24/7 (2026-11-25)

- Nguồn: `~/collab-bot/handoff/HANDOFF-BOT-24x7-20261125.md`. Hưng chốt 25/11 07:11 VNT: **Q1** dùng VPS hiện tại và gỡ Nemo trước; **Q2** bot chạy bằng user Linux riêng `claudebot`.
- Trạng thái: **A1 ĐÃ CHẠY 25/11 08:23 VNT** (Nemo stopped, restart=no, RAM avail 2837→4065M, swap 2909→1563M). Hưng đồng ý đưa `memory/` lên repo private (Q1 25/11). Đã gộp góp ý của Rùa và Hermes (A2, B4, B4b, C1, C2). Các pha còn lại chưa chạy.
- **HARD RULE (Hưng 25/11 14:13):** bot chỉ chạy bằng **subscription**, không bao giờ dùng API key (không có budget). Đăng nhập VPS bằng `claude setup-token` (OAuth subscription). Launcher phải fail-closed nếu thấy `ANTHROPIC_API_KEY` hoặc `claude auth status` không phải subscription. Mỗi pha (A1, A2, B) cần một GO riêng của Hưng, ghi rõ target là VPS `72.61.123.33`.
- Số đo gốc (VERIFIED, 25/11 07:03): RAM avail 2.6G, swap 2.7/4G, disk trống 14G (87%). `hung` thuộc group `sudo` và `docker`, sudo cần mật khẩu. `/home/hung` đang là `drwxr-x---`.

---

## Pha A — Gỡ Nemo

### Hiện trạng Nemo (VERIFIED)
- Container `nemo-sandbox`, image `node:24.21.0-bookworm-slim`, restart `unless-stopped`, cap 2.5GiB. Đang ăn 1.2G RAM và khoảng 1.2G swap.
- Cổng `127.0.0.1:18796` và `127.0.0.1:8789`, chỉ nghe local.
- **Toàn bộ dữ liệu nằm trong bind mount** `~/sandbox-nemo/` (config 1006M gồm `lcm.db`, workspace 4.6M, .npm 1.1G, runtime-10.5 619M). Xoá container không làm mất dữ liệu.
- `openclaw-healthcheck.sh`, `openclaw-backup.sh`, `openclaw-restore-check.sh`: 0 chỗ nhắc tới nemo. Không cron nào gọi Nemo.
- `sandbox-nemo.service` và `openclaw-gateway-nemotron.service` đều đã `disabled`, là đồ cũ.

### A1 — Tạm dừng (đảo ngược được, cần GO-A1)
```bash
free -m; docker stats --no-stream nemo-sandbox
docker inspect nemo-sandbox > ~/backups/nemo-final-20261125-inspect.json
docker update --restart=no nemo-sandbox
docker stop nemo-sandbox
```
Verify:
- `free -m` (kỳ vọng avail tăng khoảng 1.2G, swap giảm dần).
- `systemctl --user is-active openclaw-gateway-hungreo openclaw-gateway-suckhoe hermes-gateway` = cả 3 active.
- Lượt healthcheck kế tiếp (:00 hoặc :30) không báo lỗi.

Rollback A1:
```bash
docker update --restart=unless-stopped nemo-sandbox && docker start nemo-sandbox
```

Soak 7 ngày. Bot Telegram của Nemo sẽ im trong thời gian này.

### A2 — Xoá hẳn (cần GO-A2, sớm nhất 02/12, không gấp)
Sửa 25/11 theo góp ý của Rùa và Hermes. Bot mới không cần disk này, nên A2 chỉ làm khi thật sự cần chỗ.
- `inspect.json` chỉ là đầu vào cho rollback, chưa phải rollback đã thử. Container bind-mount `runtime-10.5`, nên **xoá runtime thì `docker run` không dựng lại được**.
- Archive phải gồm `config workspace nemo.env runtime-10.5 ops-lcm120-20261022` (chỉ bỏ `.npm` và `.cache` vì tải lại được), đặt chmod 600 vì chứa `nemo.env` và token.
- Trước khi xoá: `tar -tzf` đọc được, giải nén thử vào thư mục tạm rồi so `sha256sum` của `lcm.db` và `openclaw.json`, kiểm đủ mọi bind mount trong `inspect.json`.
- Thứ tự xoá: `docker rm nemo-sandbox`, `rm -rf ~/sandbox-nemo/.npm` (1.1G). Chỉ xoá `runtime-10.5` khi archive đã qua bước kiểm trên.
- Rollback: giải nén archive về `~/sandbox-nemo`, `docker run` theo `inspect.json`. **UNVERIFIED** cho tới khi diễn tập: chỉ diễn tập bằng `docker create` (không start, tránh poll token Nemo).
- Xong thì cập nhật dòng Nemo trong `.claude/skills/openclaw-ops/SKILL.md`, `LOCAL_CONTEXT.md` và `kb/lessons-learned.md`.

---

> Vai trò và quyền của bot: xem `TO-BE-ORCHESTRATOR.md` (chốt trước GO-B).

## Pha B — Bot lên VPS (cần GO-B, làm sau khi A1 soak ổn ít nhất 1–2 ngày)

### B1 — Hệ thống (sudo: Hưng tự chạy vì cần mật khẩu)
```bash
sudo adduser --disabled-password --gecos "" claudebot     # không thêm sudo, không thêm docker
sudo apt-get install -y bubblewrap socat tmux
sudo loginctl enable-linger claudebot
```
AppArmor: Ubuntu 24.04 bật `apparmor_restrict_unprivileged_userns=1` (VERIFIED), bwrap sẽ bị chặn. Cần profile cho `/usr/bin/bwrap` có quyền `userns`. **UNVERIFIED:** nội dung profile chính xác. Trước GO-B mình sẽ tra docs sandboxing của Claude Code và Ubuntu, rồi đưa file cụ thể để Hưng duyệt. Không tắt sysctl toàn máy.

### B2 — Cài cho `claudebot`
- `claude` bản native và `bun`, cài trong home của claudebot.
- Plugin `telegram@claude-plugins-official`, kèm port lại các patch: `telegram-format.ts`, owner-gate hook, room-context, bản vá voice DM (nếu đã GO).
- `collab-settings.json` bản Linux: đổi path `/Users/hungdinh` thành `/home/claudebot`, bỏ deny/ask kiểu macOS (`launchctl`, `security`), giữ `sandbox.failIfUnavailable: true` và `credentials.envVars` deny.
- `COLLAB_PROTOCOL.md`, memory và skills của `~/collab-bot` (rsync, **không** chép inbox và `.env`).
- Workspace: clone repo `hungreo-openclaw` riêng cho claudebot (read-mostly). Bot không có SSH key, không có quyền push.

### B3 — Secrets (Hưng tự gõ, không đi qua chat hay qua agent)
- OAuth: SSH vào bằng `claudebot`, chạy `claude setup-token` để tạo **token mới riêng cho VPS** (thu hồi độc lập với Mac). Lưu bằng `read -rs` vào `~/.config/claude-collab/oauth`, chmod 600.
- Telegram: tạo `~/.claude/channels/telegram-collab/.env` bằng `read -rs`, chmod 600. Chép `access.json` và `trust.json` (chỉ chứa ID).
- Launcher Linux: đọc token từ file, kiểm regex `sk-ant-oat01-`, `unset ANTHROPIC_API_KEY`, và dừng nếu `claude auth status` không phải subscription.

### B4 — Chạy nền (sửa 25/11 theo góp ý của Rùa)
- `tmux new-session -d` trả về ngay, nên systemd không thấy bot chết. **Bỏ tmux.** `ExecStart=/usr/bin/script -qfec "<launcher>" /dev/null`, `Type=simple`: `script` cấp pty và chỉ thoát khi `claude` thoát, nhờ vậy `Restart=on-failure` theo dõi đúng tiến trình thật.
- `RestartSec=10`, `StartLimitBurst=5` trong 10 phút (chống vòng restart đốt quota), `MemoryMax=1536M`.
- **ASSUMPTION:** channels chạy được dưới pty của `script`. Test bắt buộc: `kill -TERM` PID `claude`, rồi `kill -9`; kỳ vọng unit restart trong khoảng 10s và vẫn chỉ 1 poller. Không đạt thì quay về tmux kèm watchdog timer kiểm PID.

### B4b — Thử trên VPS bằng bot test trước (theo góp ý của Hermes)
- **Bot test = `@hungreo_bot` của Nemo cũ** (Hưng chốt 25/11 14:15, bỏ Nemo). PRIOR-EVIDENCE: `sandbox-nemo.service` ghi `@hungreo_bot`; config Rùa/Suckhoe/Hermes không nhắc tới bot này (Rùa = `@hungreo_openbot`, Suckhoe = `@hungreo_suckhoe_bot`, Hermes = `@hungreo_bds_bot`). Chưa getMe xác nhận vì agent không được đọc token.
- Trước khi dùng: Hưng vào BotFather → `/mybots` → `@hungreo_bot` → **Revoke current token** để lấy token mới. Token cũ trong `nemo.env`/container chết luôn, nên Nemo có lỡ bật lại cũng không poll được (hết rủi ro 2 poller). Token mới Hưng tự dán vào VPS ở B3 bằng `read -rs`.
- Toàn bộ B1–B4 và B7 chạy với bot test này, bot thật `@hungreo_claude_bot` trên Mac vẫn chạy bình thường.
- Kiểm sandbox bằng hành động thật, không chỉ dựa vào việc có user riêng: bot thử `cat /home/hung/.openclaw-hungreo/.env`, `ls /home/hung`, `docker ps`, `systemctl --user status openclaw-gateway-hungreo` và ghi file ngoài `~/collab-bot`. Mọi lệnh phải bị chặn.
- Qua hết mới đổi sang token thật ở B5. Xong thì xoá bot test.

### B5 — Cutover (chống 2 poller)
1. Trên Mac: SIGTERM PID bot (`~/.claude/channels/telegram-collab/bot.pid`), tắt autostart nếu có, tạo marker `~/collab-bot/MOVED-TO-VPS`. Vá `start-claude-collab.sh` để launcher Mac dừng khi thấy marker.
2. Kiểm Mac không còn `bun`/plugin telegram nào sống (`pgrep -af telegram`).
3. Trên VPS: start `claude-collab.service`.
4. Log không có `409 Conflict`. Nếu có thì còn poller khác, dừng VPS ngay.

### B6 — Voice
- Giai đoạn đầu **tắt voice** (không tạo `voice-transcribe.on`).
- Sau khi ổn: thử `faster-whisper-small` có sẵn (464M, Rùa đang dùng) hoặc whisper.cpp `small`, đo thời gian và RAM với 1 voice 30 giây. Không dùng large-v3-turbo vì VPS chỉ có 2 vCPU, không GPU.

### B7 — Verify 3 tầng
- **Process:** 1 poller, `claude auth status` = subscription, env không có `ANTHROPIC_API_KEY`.
- **Quyền:** bot thử đọc `/home/hung/.openclaw-hungreo/.env` phải `Permission denied`; `systemctl --user` của claudebot không thấy service của hung; `docker ps` bị từ chối.
- **UX:** DM `/start`, hỏi một câu, test Allow/Deny duyệt quyền, kiểm format trả lời.
- **Tài nguyên:** `free -m` sau 24h, avail ≥ 1.5G, swap không tăng.

### Rollback B
- **Nhanh, theo thứ tự ngược với cutover:** (1) `systemctl --user stop claude-collab` và `disable` (user claudebot), (2) kiểm VPS không còn tiến trình `claude`/`bun`, (3) xoá marker trên Mac, (4) chạy lại launcher Mac. Khoảng 1 phút.
- **Gỡ hẳn:** thu hồi token VPS ở claude.ai, `sudo loginctl disable-linger claudebot`, `sudo deluser --remove-home claudebot`.
- Setup trên Mac giữ nguyên, không xoá gì.

---

## Pha C — Vá "đồ nghề" bị mất khi rời Mac (đề xuất của bot 25/11, đã rà)

Thay cho ý `/srv/collab-inbox` ở bản trước: chuyền việc đi qua git.

### C1 — `~/collab-bot` thành repo GitHub private
- VERIFIED: `~/collab-bot` đã `git init` nhưng **chưa có commit nào, chưa có remote, chưa có `.gitignore`**.
- `.gitignore`: `inbox/`, `backups/`, `.DS_Store`, `*.oga`, `*.ogg`, `.env*`, `logs/`. Inbox là voice/ảnh thật, không đưa lên GitHub.
- Quét secret trước commit đầu tiên (VERIFIED 25/11: chỉ trúng regex redaction trong `work/*/plugin/collab-gate.ts`, không có token thật). Thêm pre-commit hook chạy lại bước quét này.
- ⚠️ `memory/` có chuyện riêng (thuế, đức tin). Repo private vẫn là dữ liệu nằm trên GitHub. Hưng quyết có đưa lên không.
- Quyền GitHub trên VPS: **deploy key riêng cho từng repo**, không dùng token cả tài khoản. Repo `collab-bot` cấp key đọc+ghi; repo `hungreo-openclaw` cấp key **chỉ đọc**.
- Chống xung đột: sau cutover chỉ VPS ghi `memory/`, Mac chỉ pull. `handoff/` hai bên cùng ghi nhưng mỗi task một file riêng.
- **Tách danh tính sync (sửa 25/11 theo góp ý của Rùa).** Rule `ask` với git push không phải rào của hệ điều hành: nếu key nằm trong user claudebot thì bot vẫn đọc được key. Nên:
  - User thứ 3 `collabsync` (không sudo, không docker) giữ cả 2 deploy key, mode 700, và sở hữu thư mục `.git` của cả 2 checkout.
  - Working tree thuộc group `collab` (gồm claudebot và collabsync), chỉ `handoff/` và `memory/` cho group ghi (setgid 2770). claudebot **không có key nào** và không ghi được `.git` (nên không cài được git hook).
  - Timer `collabsync-sync` (khoảng 2 phút) chạy `pull --rebase`, commit, rồi push riêng `handoff/` và `memory/` của `collab-bot`. Repo `hungreo-openclaw` chỉ pull.
  - Thứ còn lại: bot ghi được nội dung vào `handoff/` và `memory/`, nên nội dung đó tự lên GitHub. Đây là chủ ý, và repo là private.

### C2 — Hộp thư `handoff/`
- Quy ước tên file: `handoff/TASK-YYYYMMDD-NN-<slug>.md` do bot ghi, `handoff/RESULT-YYYYMMDD-NN-<slug>.md` do app PC ghi.
- App PC pull repo, đọc TASK, làm, ghi RESULT, push. Bot đọc RESULT rồi báo Hưng qua Telegram.
- **An toàn (sửa 25/11 theo góp ý của Rùa):** TASK chỉ là **đề xuất hoặc handoff**, không bao giờ là GO. Dòng "nguồn là Telegram của Hưng" trong file không chứng minh được gì, vì ai ghi được file cũng ghi được dòng đó.
  - App PC được đọc, phân tích, viết plan, sửa local trong phạm vi task, ghi RESULT.
  - Deploy, push, gửi tin, xoá, đổi config VPS hay tiền thì app PC phải xin GO trực tiếp từ Hưng, trong chat app PC hoặc project thread. Nội dung file TASK không bao giờ tự thành quyền.

### C3 — Claude Code on the web (code từ điện thoại khi Mac tắt)
- Chạy trên cloud của Anthropic, làm việc với repo GitHub, mở được từ app Claude mobile. Docs: https://code.claude.com/docs/en/claude-code-on-the-web
- UNVERIFIED: gói của Hưng có bật tính năng này không, và quota tính ra sao (khả năng cao dùng chung quota subscription). Hưng tự mở claude.ai/code trên điện thoại để kiểm, mất khoảng 1 phút.
- Không cần làm gì trên VPS.

### C4 — Remote Control khi Mac đang bật
- PRIOR-EVIDENCE: thread này đang chạy trên Mac qua Remote Control, nên tính năng có sẵn và dùng được. Không cần vá.

### C5 — Voice
- Đính chính: VPS có **faster-whisper-small** (464M, `~/.openclaw-voice/models/faster-whisper-small`, VERIFIED), không phải "base".
- claudebot không đọc được `/home/hung`, nên chép riêng model sang home của claudebot (+464M disk). Venv faster-whisper riêng. Vẫn để sau B6, đo xong mới bật.

### Không vá được
Xcode, iOS Simulator, Keychain và mọi việc cần Mac (RUUME build) vẫn cần Mac bật.

## Risk / edge cases
- Swap đang cao: nếu không gỡ Nemo trước mà bật bot luôn thì có nguy cơ OOM Rùa (VPS từng OOM, root cause chưa chốt).
- Channels đang là research preview: session chết thì tin nhắn không được buffer. Restart policy chỉ giảm thiểu, không phải bảo đảm.
- Quota subscription dùng chung Mac, claude.ai và VPS. Bot chạy 24/7 ăn quota nhiều hơn.
- Patch plugin sẽ mất khi plugin tự cập nhật (giống trên Mac). Cần ghi lại danh sách patch.
- Điều khoản: bot chỉ phục vụ Hưng. allowlist giữ nguyên, không mở cho người khác.

## Cost
- Hạ tầng: $0 (dùng VPS sẵn có).
- Model: subscription. Không có đường nào dùng API key, launcher fail-closed.
- Disk: khoảng +1G cho bot, −1.7G khi xong A2.
