# Runbook: nâng một profile OpenClaw 9.36 lên 2026.11.7

> Bản đã chạy thành công cho **hungreo (Rùa)** ngày 24/11/2026, lần thứ 5. Bốn lần trước đều tự rollback sạch.
> Dùng lại được cho **suckhoe** và các profile khác: đổi tên profile, unit, port và đường dẫn.
> Đọc kèm: `kb/lessons/2026-11-24-openclaw-117-cutover.md` (vì sao có từng bước) và `tools/openclaw-ops/hungreo-117-sol62-20261123/` (script thật, README, ISSUE-LOG).
> Mọi agent (Claude Code, Codex, Gemini, bot) đều phải theo. Bước nào cần GO thì ghi rõ GO.

## 0. Cần có trước

| Mục                         | Cách kiểm                                                                   | Ngưỡng                                                                                                    |
| --------------------------- | --------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Disk trống                  | `df -h /home`                                                               | ≥ 15G, tức bản sao profile + 5G. Mỗi lần rollback giữ lại 1 bản candidate 6–7G, nên dọn trước khi thử lại |
| Runtime 11.7 staged         | `$UPGRADE/runtime/node_modules/openclaw` + `npm-cache`                      | Đã có, chạy `--version` ra `2026.11.7`                                                                    |
| Không job sắp chạy          | `profile-check.py idle`                                                     | Không cron nào đến hạn trong 20 phút. Heartbeat 2h: bắt đầu ngay sau lượt heartbeat                       |
| Model đích có trong account | `jq -r '.client_version' codex-home/models_cache.json` + `grep gpt-6.2-sol` | Danh sách model **phụ thuộc phiên bản Codex client** (xem mục 5)                                          |

## 1. Rà config trước khi chạy

1. `agents.defaults.heartbeat` bị 11.7 từ chối. Doctor sẽ chuyển nó thành automation `agentTurn`, isolated và idle-only. Chốt trước cadence, active hours, model và delivery.
2. Lập danh sách phải giữ: `compare.py snapshot <profile> must-keep.json` (tất cả job, skill đang tắt, model, fallback, plugin).
3. Kiểm 2 thứ mà 11.7 **cố ý gỡ**:
   - Job `skill-collection-review:*` (curator Skill Workshop hằng tuần) bị xoá ở mỗi lần nạp cron store. Không giữ được bằng config, chỉ có thể tạo lại thành job thường với tên khác.
   - `skills.entries.nano-banana-pro` bị Doctor xoá vô điều kiện. Nếu `workspace/skills/nano-banana-pro` còn, skill sẽ **thành bật**. Phải dời thư mục đó ra `workspace/.retired-skills-117/` trước Doctor (cutover.sh đã làm sẵn).
4. Plugin local viết bằng TypeScript (`openclaw.extensions: ["./index.ts"]`) có thể không nạp được. 11.7 chỉ cho **15 giây cứng** để chuẩn bị nguồn TS, và `hungreo-finance` cần 17,6 giây. Đóng gói trước (mục 4).

## 2. Dry-run trên bản sao (Rùa vẫn online)

- Copy: `rsync -aHAX --exclude=/tmp/ --exclude=/cache/ --exclude='*-shm' --exclude='*-wal'`, sau đó `snapdb.py` (dùng SQLite backup API, `quick_check` từng DB).
- Trên bản sao: xoá `state_leases`, `agent_database_leases` và `tmp/openclaw-1001/*.lock`, nếu không Doctor sẽ thấy gateway live đang giữ lock.
- Chạy trong Docker: `--network none`, mount bản sao **đúng path live** (config chứa đường dẫn tuyệt đối), runtime ro, `--memory 3g`.
- HOME và /tmp phải nằm trên disk, không trên tmpfs, nếu không Doctor sẽ OOM ở bước "Database engines".
- **Không** test đổi model hay OAuth trên bản sao có mạng: bản sao có thể xoay refresh token của live.
- Script mẫu: `dryrun2.sh`, `dryrun2-resume.sh`, `docker-run.sh`, `inner.sh`, `compare.py`.

## 3. Cutover (`cutover.sh apply-heartbeat`, cần GO)

Chạy trên VPS bằng `nohup setsid … &` để không phụ thuộc máy Mac. Theo dõi bằng cách đọc log tìm `UPGRADE_OK|ROLLED_BACK|ROLLBACK_FAILED`. **Không** dùng `pgrep -f` với chuỗi có trong chính lệnh ssh, vì nó sẽ tự khớp và treo.

Thứ tự phase và các bẫy đã vá:

| Phase            | Bẫy 11.7                                                                                                                   | Đã vá trong script                                                                                                      |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| PRECHECK/PRECOPY | job đến hạn trong 20 phút                                                                                                  | kiểm `idle` hai lần                                                                                                     |
| STOP_BACKUP      | —                                                                                                                          | checksum + `quick_check` 3 DB                                                                                           |
| MIGRATE          | Doctor **tự restart gateway** ("Gateway restarted and verified after Doctor maintenance") ở chế độ đầy đủ, mở lại Telegram | ghi HOLD drop-in (`SKIP_CHANNELS`, `SKIP_CRON`) **trước** Doctor; sau Doctor `unit stop` + `wait_stopped`               |
| MIGRATE          | `check config/heartbeat` báo lệch vì 3 thay đổi dự kiến                                                                    | `profile-check.py` chấp nhận đúng `wizard.lastRun*`, entry `nano-banana-pro` đã dời, job curator; ngoài ra lệch là dừng |
| PLUGINS          | `plugins update` **chỉ chạy offline** và bị từ chối ("requires exclusive offline state ownership")                         | Doctor đã đưa plugin lên 11.7; plugin nào dry-run báo "is up to date" thì bỏ qua                                        |
| (trước START)    | `models auth list` **chỉ chạy offline**, nên bị từ chối khi gateway đang chạy                                              | chạy khi gateway còn dừng, retry 3 lần                                                                                  |
| MODEL_CHECK      | model đích chưa có trong account                                                                                           | lượt thật qua gateway (`oc agent`), kiểm không fallback, không api-key                                                  |
| OPEN_TRAFFIC     | —                                                                                                                          | channel probe + config/heartbeat check lần cuối                                                                         |

Mỗi lần fail, script tự rollback: profile 11.7 được dời vào `$B/post-cutover.*/profile`, bản 9.36 được trả lại, rồi start và kiểm readyz. Downtime mỗi lần thử khoảng 11–15 phút.

## 4. Plugin local TS → bundle JS (cần GO khi áp vào live)

```bash
J=/path/finance-js; cp -a extensions/<plugin> $J; rm -rf $J/node_modules
$UPGRADE/runtime/node_modules/.bin/esbuild <plugin>/index.ts --bundle --platform=node --format=esm \
  --target=node24 --external:openclaw --external:'openclaw/*' --outfile=$J/dist/index.js
# package.json: "openclaw.extensions": ["./dist/index.js"], và XOÁ khối "dependencies"
# (còn khối đó thì 11.7 đòi node_modules và báo thiếu deps)
```

Áp vào live: backup thư mục plugin, dừng gateway và healthcheck timer, thay thư mục, `plugins registry --refresh` (offline), start, kiểm log `http server listening (N plugins: … <plugin> …)`. Script: `apply-finance.sh`. Từ đó về sau, sửa `src/*.ts` phải build lại bundle.

## 5. Model đích không có trong account

Danh sách model trong `codex-home/models_cache.json` do server trả về **theo phiên bản Codex client**:

- 9.36 đi kèm Codex 0.160.0: không có `gpt-6.2-sol`.
- 11.7 đi kèm Codex 0.170.0: có `gpt-6.2-sol` (cache lúc 17:46 ngày 24/11).

Lúc cutover, cache vẫn là bản do 0.160 ghi, nên `config set` báo "Unknown model". Cách làm: nâng runtime với model cũ trước, đợi gateway 11.7 làm mới cache, kiểm lại danh sách, rồi đổi model ở một bước riêng có GO.

## 6. Hậu kiểm 3 tầng

1. Config/job: `compare.py compare` PASS; số job đúng; heartbeat có lượt kế tiếp; `nano-banana-pro` không còn.
2. Session/model: log không có fallback, Anthropic hay api-key; `readyz` 200 cả 2 bot; healthcheck timer active.
3. User: Hưng gõ `/status` trên Telegram (version, model, `Auth: oauth`) và thử một lệnh của từng plugin.

Còn mở sau Rùa: watcher hot-reload config báo "watch observation worker stopped" 3/3 lần. Đổi config phải restart mới có hiệu lực.

## 7. Dọn

Chỉ giữ 1 bản 9.36 (backup `$B` của lần thành công) khoảng 1 tuần, cộng tối đa 1 candidate để đối chiếu. Hook guardrail chặn agent `rm -r` đường dẫn có `.openclaw`, nên lệnh xoá đưa cho Hưng tự chạy.
