---
name: openclaw-ops
version: 0.2.1
description: |
  OpenClaw VPS ops cho fork Hungreo — upgrade, audit, drift-check, health-check cho 4 hệ
  (hungreo/Rùa, suckhoe, nemo-sandbox Docker, hermes-gateway) trên Hostinger VPS (72.61.123.33).
  Áp dụng workflow Aligned · Simple · Safe · Effective, stop-first + dry-run thật + verify 3 tầng +
  cost-safety hard rules đã trả giá qua nhiều incident. Dùng khi user nói tới: "upgrade openclaw",
  "audit bot", "check VPS", "drift", "lossless-claw", "LCM", "plugin drift", "restart gateway",
  "openclaw health", "nemo", "hermes", hoặc bất kỳ task runtime/deployment nào trên VPS openclaw.
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
---

# /openclaw-ops — OpenClaw VPS Ops (Hungreo fork, v0.2.1)

Skill này gói SOP vận hành các bot OpenClaw + Hermes trên VPS (`srv1367812` / `72.61.123.33`) để **không re-derive context mỗi session** (dùng chung cho cả Claude Code, Codex và Antigravity qua symlink `.agents/skills/openclaw-ops`).
Nguyên tắc: **Aligned · Simple · Safe · Effective** + **Grill & Align → Root Cause → Plan & Spec → Do (Red-Loop) → Check (Green) → UAT → Show-Me → Retro**.

## 0. BẮT BUỘC đọc trước khi action (thứ tự)

1. `tools/openclaw-ops/session-handover-20261018/HANDOVER_PROMPT.md` (hoặc thư mục `session-handover-*` mới nhất) — Trạng thái, Việc mở, Cách làm.
2. `SESSION_HANDOVER.md` — Mục lục + các entry mới nhất ở đầu file.
3. `LOCAL_CONTEXT.md` — Topology, ports, paths, SSH.
4. `kb/lessons-learned.index.md` → `kb/lessons/2026-10-*.md` — Incidents đã trả giá (grep pattern liên quan task).
5. `tools/openclaw-ops/lcm-111-20261015/README.md` (`00_precheck.sh`, `10_upgrade.sh`, `20_verify.sh`, `99_rollback.sh`) — Khuôn mẫu chuẩn cho mọi script nâng cấp core/plugin. Bản mới nhất theo khuôn này: `node-24221-rehearsal-934-20261026/` (Node + core 9.34) và `lcm-120-20261025/` (LCM 1.2.0 + `30_soak.sh`).

**Research read-only TRƯỚC → present plan (tối đa 3 phương án, 1 Recommended) → CHỜ Hưng GO rõ → mới action.**

## 1. Topology chuẩn hiện tại (9.x / 10.x — cập nhật 2026-10-26)

| Hệ                | Dịch vụ / Container                                                     | Cổng                       | Runtime / Core                                                                                                                                                       | Context / DB chính                                                                                                                        | Model Primary / Fallback                                                                                                        |
| ----------------- | ----------------------------------------------------------------------- | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| **Hungreo (Rùa)** | `systemd --user openclaw-gateway-hungreo.service`                       | `:18789` (webhook `:8787`) | Staged `openclaw@2026.9.34` (`~/openclaw-upgrade-20261026-934/runtime`) + `Node v24.22.1` (`~/openclaw-node-24.22.1/node`) + preload `patch-binding-loader-hook.mjs` | `lossless-claw@1.2.0` (`~/.openclaw-hungreo/lcm.db`), state `state/openclaw.sqlite`, transcript `agents/main/agent/openclaw-agent.sqlite` | Primary: `openai/gpt-6.1-sol` (Codex OAuth) · Sub: `openai/gpt-6-luna` · Fallback: `openrouter/meta/muse-spark-1.3-contributor` |
| **Suckhoe**       | `systemd --user openclaw-gateway-suckhoe.service`                       | `:18795` (webhook `:8788`) | Staged `openclaw@2026.9.34` (`~/openclaw-upgrade-20261026-934/runtime`) + `Node v24.22.1` (`~/openclaw-node-24.22.1/node`) + preload `patch-binding-loader-hook.mjs` | `lossless-claw@1.2.0` (`~/.openclaw-suckhoe/lcm.db`), state `state/openclaw.sqlite`, transcript `agents/main/agent/openclaw-agent.sqlite` | Primary: `openai/gpt-6.1-sol` (Codex OAuth) · Sub: `openai/gpt-6-luna` · Fallback: `openrouter/meta/muse-spark-1.3-contributor` |
| **Nemo (Canary)** | Docker `nemo-sandbox` (`sandbox-nemo.service`, cap `1.5 CPU / 2.5 GiB`) | `:18796`                   | Staged `openclaw@2026.10.5` (`/home/hung/sandbox-nemo/runtime-10.5` → `/sandbox/runtime:ro`)                                                                         | `lossless-claw@1.2.0` (`/sandbox/home/.openclaw/lcm.db`), config `/home/hung/sandbox-nemo/config`                                         | Primary: `openrouter/meta/muse-spark-1.3-contributor` · Fallback: `openai/gpt-6.1-sol`                                          |
| **Hermes**        | `systemd --user hermes-gateway.service`                                 | —                          | `~/.hermes` (`SOUL.md` + `AGENTS.md` tại cwd `~/.hermes`)                                                                                                            | SQLite state trong `~/.hermes`                                                                                                            | ChatGPT OAuth                                                                                                                   |

- **Swap VPS:** 4 GiB (`/swapfile`, `swappiness=10`).
- **Node & Loader:** Service core `9.34` dùng `Node v24.22.1` tại `/home/hung/openclaw-node-24.22.1/node` và loader hook ở `/home/hung/openclaw-upgrade-20261003/live-gates/` (runtime rollback `9.33` tại `/home/hung/openclaw-upgrade-20261018-933/runtime` và Node rollback `v24.21.0` tại `/home/hung/openclaw-upgrade-20261003/node`) — **TUYỆT ĐỐI KHÔNG XOÁ** thư mục runtime/live-gates cũ khi `ExecStart` hoặc rollback còn tham chiếu (lesson `2026-10-18-one-recovery-set-retention.md`).

## 2. Hard Rules: Cost-Safety, Security & Harness Guardrails (TUYỆT ĐỐI)

- **DENY (Cấm tuyệt đối — khớp `tools/claude-code-guardrails/guardrails.sh`):**
  - **KHÔNG tự đổi** `agents.defaults.model.*`, `auth.profiles.*`, `fallbacks`, `.slots` → phải có GO riêng của Hưng.
  - **KHÔNG** `git push --force`, `git clean -f`, `git checkout/restore .`, `git stash drop/clear` (bảo vệ tuyệt đối dirty/untracked files của các phiên agent khác đang chạy song song).
  - **KHÔNG** `rm -rf ~/.openclaw*` hoặc `rm -rf ~/.hermes*`.
- **Bảo mật & Quyền riêng tư:**
  - **KHÔNG BAO GIỜ in secret/token/API key/chat ID/email** ra output hay lưu vào repo (chỉ đếm số lượng biến hoặc in SHA256 prefix 8–10 ký tự).
  - **Transcript của Suckhoe chứa hồ sơ y tế gia đình** → TUYỆT ĐỐI không trích nội dung bệnh án vào chat hoặc repo.
  - Repo `hungreo-openclaw` là **PUBLIC**: trước khi commit phải quét chat ID, email, `sk-`, `eyJ` (kể cả base64); chỉ commit/push khi Hưng yêu cầu rõ.
- **Stop-First & Timer Discipline:**
  - Mọi thao tác nâng cấp core/plugin trên `hungreo`/`suckhoe` phải **tắt `openclaw-healthcheck.timer` + `openclaw-healthcheck.service` TRƯỚC**, rồi **STOP gateway TRƯỚC** khi chạy `npm install` hoặc `openclaw plugins update`. Sau khi gateway `ready` và pass `/readyz` HTTP 200 mới bật lại `openclaw-healthcheck.timer`.
- **Dry-Run Thật (Lesson `2026-10-12` & `2026-10-11`):**
  - Trước khi stop dịch vụ, bắt buộc chạy thử từng lệnh ghi bằng chế độ không ghi của chính công cụ:
    - `openclaw --profile <p> plugins update <spec> --dry-run`
    - `openclaw --profile <p> config set ... --dry-run` (chú ý tên model có dấu chấm phải bọc ngoặc vuông: `agents.defaults.models["openai/gpt-6.1-sol"]...`)
    - `hermes update --check --channel <x>`
- **Backup SQLite an toàn (Lesson `2026-10-08` & `2026-10-15`):**
  - Đọc SQLite khi bot đang chạy hoặc vừa dừng luôn mở URI `?mode=ro` (`sqlite3.connect("file:...?mode=ro", uri=True)`), đóng kết nối trước khi kiểm tra PID mở file, và **không chép file `-shm`** khi backup (chỉ chép `.sqlite` + `-wal` sau khi service đã stop và `pragma quick_check` = `ok`).
- **Review Fresh-Context:**
  - Mọi bộ script Production (`tools/openclaw-ops/<task>-<date>/`) phải được review độc lập (subagent fresh-context) để bắt lỗi bẫy `set -e` / `pipefail` / rollback trước khi chạy trên VPS.

## 3. Cách gọi CLI đúng chuẩn trên VPS (Chống Env Pollution)

> **CẢNH BÁO QUAN TRỌNG (VERIFIED 2026-10-18):**
> Cả `hungreo` và `suckhoe` đều cấu hình `gateway.auth.token` = `SecretRef(env: OPENCLAW_GATEWAY_TOKEN)` và `channels.telegram.botToken` = `SecretRef(env: TELEGRAM_BOT_TOKEN)`.
>
> - Nếu chạy lệnh kiểm tra `suckhoe` từ bên trong tiến trình của `hungreo` (hoặc shell đã export sẵn biến môi trường của `hungreo`), `process.env` sẽ kế thừa cả `OPENCLAW_GATEWAY_PORT=18789`, `OPENCLAW_PROFILE=hungreo`, `OPENCLAW_SYSTEMD_UNIT`, `OPENCLAW_GATEWAY_TOKEN` và `TELEGRAM_BOT_TOKEN` của `hungreo` → khiến lệnh đi nhầm cổng `18789`, báo `AUTH_TOKEN_MISMATCH` hoặc probe nhầm vào `@hungreo_openbot`!
> - **Quy tắc:** Luôn xoá sạch toàn bộ biến `OPENCLAW_*` + `TELEGRAM_BOT_TOKEN` kế thừa và truyền tường minh `OPENCLAW_GATEWAY_PORT`, `OPENCLAW_STATE_DIR`, `OPENCLAW_CONFIG_PATH`, `OPENCLAW_SYSTEMD_UNIT` của đúng service đích.

```bash
# Hàm chuẩn gọi CLI cho hungreo hoặc suckhoe (an toàn cả từ SSH lẫn từ exec của Rùa)
oc_profile() {
  local P="$1"; shift
  local D="$HOME/.openclaw-$P"
  local PORT=$([ "$P" = suckhoe ] && echo 18795 || echo 18789)
  (
    for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
    unset TELEGRAM_BOT_TOKEN
    set -a
    [ -f "$D/gateway.systemd.env" ] && . "$D/gateway.systemd.env"
    set +a
    OPENCLAW_PROFILE="$P" \
    OPENCLAW_STATE_DIR="$D" \
    OPENCLAW_CONFIG_PATH="$D/openclaw.json" \
    OPENCLAW_GATEWAY_PORT="$PORT" \
    OPENCLAW_SYSTEMD_UNIT="openclaw-gateway-$P.service" \
      /home/hung/bin/openclaw --profile "$P" "$@" < /dev/null
  )
}

# Gọi CLI cho Nemo (Docker)
oc_nemo() {
  docker exec nemo-sandbox node /sandbox/runtime/node_modules/openclaw/dist/entry.js "$@"
}
```

## 4. Health-check Read-Only chuẩn (Chạy đầu mỗi phiên)

Sử dụng lại `tools/openclaw-ops/lcm-120-20261025/30_soak.sh` (LCM 1.2.0: cursors/gaps/dup, capability_error, reset/lượt, OAuth) cho `suckhoe` và `hungreo`, kết hợp khối dưới + drift ở mục 4b, kiểm tra `nemo-sandbox`, `hermes-gateway` và `free -m`:

```bash
# 1. Hungreo & Suckhoe (systemd + SQLite mode=ro + LCM 1.2.0)
for p in suckhoe hungreo; do
  U="openclaw-gateway-$p.service"
  D="$HOME/.openclaw-$p"
  PORT=$([ "$p" = suckhoe ] && echo 18795 || echo 18789)
  PID=$(systemctl --user show "$U" -p MainPID --value)
  SINCE=$(systemctl --user show "$U" -p ActiveEnterTimestamp --value | awk '{print $2" "$3}')
  echo "== $p: $(systemctl --user is-active "$U") pid=$PID since=$SINCE NRestarts=$(systemctl --user show "$U" -p NRestarts --value) readyz=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/readyz)"
  echo "   rss_MiB=$(( $(awk '/VmRSS/{print $2}' /proc/$PID/status 2>/dev/null || echo 0)/1024 ))"
  jq -c '{primary:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks,slot:.plugins.slots.contextEngine,stream:.channels.telegram.streaming.mode}' "$D/openclaw.json"
  # Kiểm biến env trong gateway.systemd.env có đủ trong /proc/$PID/environ (chỉ in tên biến thiếu, KHÔNG in giá trị)
  miss=$(for v in $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$D/gateway.systemd.env" | cut -d= -f1); do strings "/proc/$PID/environ" | grep -q "^$v=" || echo -n "$v "; done)
  deg=$(journalctl --user -u "$U" --since "$SINCE" --no-pager | grep -cE 'SECRETS_(DEGRADED|OWNER_UNAVAILABLE)' || true)
  echo "   env_missing=[${miss}] secrets_degraded=${deg}"
done

# 2. Nemo (Docker container nemo-sandbox)
docker inspect nemo-sandbox --format 'nemo: status={{.State.Status}} started={{.State.StartedAt}} restarts={{.RestartCount}} oom={{.State.OOMKilled}}'
echo "   nemo readyz=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz)"
docker stats --no-stream --format '   nemo cpu={{.CPUPerc}} mem={{.MemUsage}}' nemo-sandbox

# 3. Hermes + RAM/Swap/Disk
echo "hermes: $(systemctl --user is-active hermes-gateway.service) since=$(systemctl --user show hermes-gateway.service -p ActiveEnterTimestamp --value)"
free -m
df -h /
```

## 4b. Sessions drift (9.3x+: session nằm trong SQLite) — read-only, chạy sau MỌI restart/upgrade

Luật cứng 3 (`CLAUDE.md`). Từ 9.3x không còn `agents/main/sessions/sessions.json`; mỗi session là 1 row `session_nodes` trong `agents/main/agent/openclaw-agent.sqlite`, cột `entry_json` chứa `modelOverride`, `modelOverrideSource`, `providerOverride`, `authProfileOverride`, `authProfileOverrideSource` (VERIFIED trên 9.34, 26/10). Kiểm 2 loại pin:

- **MODEL_DRIFT:** session không phải subagent có `modelOverrideSource=auto` và model ≠ primary (incident 2026-05-24: Suckhoe bị auto-pin sang deepseek). Subagent pin theo `delegation`/sub model (vd `gpt-6-luna`) là bình thường, chỉ đếm.
- **AUTH_PIN_DEAD:** `authProfileOverride` trỏ vào profile đã hết hạn hoặc không còn trong `models auth list` (profile hạn 1970 vẫn còn trên cả 2 bot).

```bash
for p in suckhoe hungreo; do
  D=$HOME/.openclaw-$p
  AUTH=$( ( set -a; . "$D/gateway.systemd.env"; set +a; OPENCLAW_STATE_DIR=$D OPENCLAW_CONFIG_PATH=$D/openclaw.json \
           timeout 90 /home/hung/bin/openclaw --profile "$p" models auth list --json </dev/null 2>/dev/null ) )
  python3 - "$p" <<PY
import sqlite3, json, sys, collections, hashlib, datetime as dt
p = sys.argv[1]; D = f"/home/hung/.openclaw-{p}"
h = lambda s: hashlib.sha256(s.encode()).hexdigest()[:8]          # không in profile id (chứa email)
raw = r'''$AUTH'''; d = None
for i, ch in enumerate(raw):
    if ch in "[{":
        try: d, _ = json.JSONDecoder().raw_decode(raw[i:]); break
        except Exception: pass
P = (d or {}).get("profiles") if isinstance(d, dict) else d
P = P.items() if isinstance(P, dict) else [(x.get("id"), x) for x in (P or [])]
def fe(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k.lower() in ("expires", "expiresat") and not isinstance(v, (dict, list)): return v
            r = fe(v)
            if r is not None: return r
now = dt.datetime.now(dt.timezone.utc); live = {}
for pid, pr in P:
    e = fe(pr)
    try: t = dt.datetime.fromisoformat(str(e).replace("Z", "+00:00"))
    except Exception: t = None
    live[pid] = bool(t and t > now)
prim = json.load(open(f"{D}/openclaw.json"))["agents"]["defaults"]["model"]["primary"]
c = sqlite3.connect(f"file:{D}/agents/main/agent/openclaw-agent.sqlite?mode=ro", uri=True)
drift, sub, pins = [], 0, collections.Counter()
for key, ej in c.execute("select session_key, entry_json from session_nodes where entry_json is not null"):
    try: e = json.loads(ej)
    except Exception: continue
    kind = ":".join(key.split(":")[:4])                              # bỏ phần ID, không in chat ID
    a = e.get("authProfileOverride")
    if a and ":subagent:" not in key:
        state = "SỐNG" if live.get(a) else ("CHẾT/hết hạn" if a in live else "KHÔNG CÓ trong auth list")
        pins[(a.split(":")[0] + ":#" + h(a), state)] += 1
    mo = e.get("modelOverride")
    if e.get("modelOverrideSource") != "auto" or not mo: continue
    if ":subagent:" in key: sub += 1; continue
    ref = f'{e.get("providerOverride") or e.get("modelProvider")}/{mo}'
    if ref != prim and mo != prim.split("/")[-1]: drift.append(f"{kind} -> {ref}")
bad = sum(n for (_, s), n in pins.items() if s != "SỐNG")
print(f"{p}: primary={prim} MODEL_DRIFT={len(drift)} {drift[:5]} subagent_pins={sub}")
print(f"   auth profiles: " + ", ".join(f'{k.split(":")[0]}:#{h(k)}={"sống" if v else "chết"}' for k, v in live.items()))
print(f"   authProfileOverride (non-subagent): {dict(pins)}  → AUTH_PIN_DEAD={bad}")
PY
done
```

Kỳ vọng: `MODEL_DRIFT=0`. Kết quả 26/10 20:50 (9.34): cả 2 bot `MODEL_DRIFT=0`; Hungreo `AUTH_PIN_DEAD=4`, đều là session cũ đã `done` (group Telegram 15/07 và 25/10, binding finance 01/08), chưa thấy ảnh hưởng.

Nếu có drift hoặc pin chết trên session đang dùng: **KHÔNG sửa SQLite bằng tay.** Cách gỡ pin chính thống trên 9.3x (CLI `openclaw sessions …` hoặc lệnh trong chat) **chưa kiểm (UNVERIFIED)**, nên tra docs và `--help` trước rồi soạn script stop-first + backup, chờ Hưng GO.

## 5. Khuôn mẫu Script Production (`00` / `10` / `20` / `99`)

Mọi thay đổi Production trên VPS đều đóng gói thành thư mục `tools/openclaw-ops/<ten-viec>-<YYYYMMDD>/`:

1. `00_precheck.sh`: Chỉ đọc + chạy `--dry-run` cho mọi lệnh dự kiến ghi.
2. `10_apply.sh` (hoặc `10_upgrade.sh`):
   - Nhận tham số từng bot (`suckhoe` trước, kiểm xong mới chạy `hungreo`).
   - Có `trap 'on_err $LINENO' ERR` phân biệt rõ `PHASE=precheck|stop|backup|update|start|done` và in sẵn lệnh `99_rollback.sh` nếu dừng sau khi đã stop.
   - Tắt `openclaw-healthcheck.timer` → stop service → đợi cổng đóng → kiểm `pragma quick_check` (`?mode=ro`) → backup (`openclaw.json`, `state/openclaw.sqlite*`, `lcm.db*`, `npm/projects`, systemd drop-ins) + tạo và verify `SHA256SUMS`.
   - Khi nâng cấp core hoặc plugin npm ngoài (`@openclaw/codex`, `@openclaw/brave-plugin`, `@openclaw/deepseek-provider`, `@openclaw/parallel-plugin`, `@openclaw/typesafe`, `@martian-engineering/lossless-claw`): kiểm tra và relink `node_modules/openclaw` (peerDependency) trong `~/.openclaw-<p>/npm/projects/*/node_modules/openclaw` trỏ đúng về runtime mới (lesson `2026-10-08-openclaw99-canary.md`).
   - Diff phẳng `openclaw.json` so với bản backup; tự động `ABORT` nếu bất kỳ khoá cấm nào (`.model`, `.auth`, `fallback`, `.slots`) bị thay đổi ngoài ý muốn.
   - Start service → chờ `[gateway] ready` và `/readyz` = `200` → bật lại `openclaw-healthcheck.timer`.
3. `20_verify.sh`: Read-only xác minh version, `gateway status --deep`, `channels status --probe`, SQLite `quick_check`, log `error|fail|warn`, RAM/Swap. **Sau mỗi restart/upgrade phải CHECK đủ 3 tầng** (luật cứng 4; `readyz=200` hay "probe works" chưa đủ):
   - (a) **Runtime thật** qua `/proc/<PID>`: `exe --version`, `cmdline` (runtime + `--import` live-gates), env `OPENCLAW_SERVICE_VERSION`. Không tin `openclaw --version` gõ không kèm `--profile` (wrapper rơi về runtime mặc định cũ).
   - (b) **Config:** diff phẳng `openclaw.json` với backup (0 khoá đổi ngoài phạm vi) **và** diff cả thư mục `~/.config/systemd/user/openclaw-gateway-<p>.service.d/` trước/sau.
   - (c) **Env key** (lesson 2026-10-06: upgrade 9.8 làm mất `EnvironmentFile`, 6 key biến mất 3 ngày dù `active` + UAT vẫn PASS): chạy khối mục 4 → `env_missing=[]` và `secrets_degraded=0` cho từng profile. Hungreo giữ `EnvironmentFile` trong drop-in riêng `zzzz-envfile.conf`.
   - (d) **Auth:** `oc_profile <p> models auth list --json` từng profile, chỉ in tiền tố profile và hạn. Phải có ≥1 profile Codex còn hạn; nếu `(none)` hoặc tất cả hết hạn thì stop và báo Hưng, không tự re-auth.
   - (e) **Drift:** mục 4b, `MODEL_DRIFT=0`; `AUTH_PIN_DEAD` chỉ chấp nhận được trên session cũ đã `done`.
   - (f) **UAT:** ưu tiên Hưng nhắn Telegram 1 câu thường + 1 câu hỏi lại chuyện cũ (chờ ~30–60s sau `readyz`). Chỉ khi Hưng GO mới chạy UAT bằng CLI (tạo 1 lượt model thật và 1 session mới): `oc_profile <p> agent --json --timeout 150 --session-id uat-<VER> --message "Reply with exactly UAT_OK and nothing else."`. Trên 9.34, cờ `--json`, `--session-id`, `-m/--message` và `--timeout` đã kiểm qua `--help` (26/10). Tên trường winner/attempts trong JSON trên 9.34 chưa kiểm (UNVERIFIED), nên đọc output thật lần đầu rồi mới viết parser. `attempts>1` hoặc winner khác primary thì nghĩa là đã chạy fallback (Muse qua OpenRouter, tốn tiền).
   - (g) **Log từ lúc start:** 0 `fallback`/`failover`, 0 `anthropic`, 0 `capability_error`, 0 `Cannot find module`; cron đầu tiên sau cutover vẫn gửi (vd Suckhoe 19:30).
4. `99_rollback.sh`: Hỗ trợ khôi phục toàn vẹn từ `BACKUP_DIR` (cất bản lỗi vào `<BACKUP_DIR>/failed-*`, trả lại file + symlink peer + systemd drop-in + `daemon-reload` + start service + bật lại `openclaw-healthcheck.timer`).

---

_v0.2.1 (2026-10-26, Claude Code soạn, Hưng duyệt 26/10): khôi phục các bước kiểm sau restart bị rơi ở v0.2.0, gồm drift sessions (cách mới cho 9.3x: `session_nodes`), `models auth list`, env-key, UAT; sửa ghi chú LCM 1.1.1 → 1.2.0. Các bước cũ ở v0.1 (bản HEAD `34c2e65798`, mục 4–5) dùng `sessions.json`/`openclaw update`, không còn đúng trên 9.3x nên không chép nguyên văn._
