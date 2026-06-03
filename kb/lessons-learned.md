# Lessons Learned — OpenClaw Hungreo

> **Agent instruction:** File này là shared knowledge base cho tất cả agents (Claude Code, hungreo bot, Nemo, Codex). Sau mỗi incident hoặc upgrade có vấn đề, ADD một entry mới ở đầu file (dưới dòng này). KHÔNG xóa entries cũ.

---

### [2026-06-03] 🔥 BREAKING — 5.28 bỏ legacy key `agents.defaults.embeddedPi` → nemotron crash startup

**Loại:** upgrade | breaking-schema-change | nemotron | config-migration | startup-fail
**Discovered by:** Claude Code (Opus 4.8) — restart nemotron FAILED sau upgrade 5.27→5.28

**Triệu chứng:**
- Upgrade 5.28: hungreo + suckhoe restart OK, **nemotron crash-loop** rồi `failed` (restart counter 5, "Start request repeated too quickly").
- Log: `Gateway failed to start: Invalid config ... agents.defaults: Invalid input` (vague, không chỉ field).

**Root cause:**
- 5.28 siết schema → **bỏ hỗ trợ legacy key `agents.defaults.embeddedPi`**, đổi tên thành **`embeddedAgent`**.
- Chỉ **nemotron** còn dùng key cũ `embeddedPi: {executionContract:"strict-agentic"}` (hungreo đã là `embeddedAgent`, suckhoe không có key). → chỉ nemotron chết.
- **FULL diff backup pre-5.28 vs current = KHÔNG khác** → update KHÔNG sửa config; là config cũ (valid ở 5.27) bị 5.28 reject. **Restore backup vô ích.**

**Cách diagnose đúng (không chạy `doctor --fix` mù — nó có thể auto-migrate model/provider):**
1. `config validate` chỉ báo `agents.defaults: Invalid input` (vague).
2. **So keys `agents.defaults` giữa 3 profiles** → tìm key nemotron có mà 2 profile valid không có → `embeddedPi`.
3. ⚠️ **GOTCHA jq:** query `jq "{embeddedPi}" file` đọc ROOT level (`.embeddedPi` = null), KHÔNG phải `.agents.defaults.embeddedPi`. Phải query đúng path → mới thấy value thật `{executionContract:"strict-agentic"}`. Đừng kết luận "null nên xóa được".

**Fix (GIỮ guardrail, không drop):**
```python
# RENAME embeddedPi → embeddedAgent, giữ nguyên value
d["agents"]["defaults"]["embeddedAgent"] = d["agents"]["defaults"].pop("embeddedPi")
# nemotron: {executionContract:"strict-agentic"} — guardrail Nemo, PHẢI giữ
```
Verify: hungreo's `embeddedAgent` cũng `{executionContract:"strict-agentic"}` → confirm tên mới đúng + value khớp. `config validate` → valid → start → ready.

**Lesson cho upgrade workflow (thêm step):**
- Sau restart, nếu 1 profile `failed` với `agents.defaults: Invalid input` → **so keys agents.defaults 3 profiles** để khoanh field legacy bị 5.x bỏ. Đừng `doctor --fix` mù; rename giữ value.
- nemotron hay là profile "lệch" nhất (config cũ nhất) → dễ dính breaking schema trước. Verify nemotron kỹ sau mỗi upgrade.

---

### [2026-06-03] 🔁 Codex fallback variant MỚI — `auth refresh timed out after 10s` (khác `refresh_token_reused` 401)

**Loại:** codex | oauth | model-fallback | session-pin | shared-account | drift-detection
**Discovered by:** Claude Code (health-check skill `openclaw-ops`) → Hưng verify (chat suckhoe vẫn gpt-5.5 bình thường)

**Triệu chứng:**
- Drift-check tổng quát bắt: 1 DM session suckhoe (`8288766754`) pinned `deepseek-v4-pro` (source=auto).
- Log: `[model-fallback/decision] decision=candidate_failed requested=openai-codex/gpt-5.5 candidate=openai-codex/gpt-5.5 reason=timeout next=deepseek detail=auth refresh request timed out after 10s`
- **18 lần trong ngày 02/06, 0 lần ngày 03/06** → transient blip 1 ngày, KHÔNG phải lỗi thường trực.

**Phân biệt với incident 2026-05-24:**
- 2026-05-24 = `refresh_token_reused` (**401**, single-use token bị bot kia invalidate) → fix bằng re-auth device-code.
- 2026-06-03 = **timeout** (refresh request >10s) → KHÔNG phải 401. Gốc nghi: network latency VPS→OAuth, hoặc auth pre-warm chậm (từng thấy "pre-warmed in 52s"), hoặc shared-account contention.

**Bài học verify (quan trọng):** Đừng over-weight 1 drift. Phải check:
1. Drift session có phải của user chính (Hưng) không → ở đây là user LẠ (`8288766754`), session Hưng (`7957776935`) luôn primary OK.
2. Lỗi còn xảy ra HÔM NAY không hay transient hôm qua → `journalctl --since today | grep -c "candidate_failed.*timeout"`.
3. Hưng's lived experience (chat thấy gpt-5.5) là evidence mạnh — đừng bỏ qua.

**Fix drift (stop-first, theo skill openclaw-ops §4):** stop suckhoe → backup sessions.json → pop override fields CHỈ session đó → start → verify drift=0. Backup `sessions.json.bak-<ts>-pre-clear-drift-<userid>`.

**🎯 GỐC RỄ KHÔNG VERSION NÀO FIX:** hungreo + suckhoe **share 1 OAuth account** `hungreo2005@gmail.com` → cùng refresh 1 Codex token → contention/timeout/401 race. Upgrade version chỉ giảm triệu chứng (5.28 có "warm provider auth off main thread" + "honor Codex response timeouts"). **Fix bền thật = tách OAuth account riêng từng bot.** Chasing version để stable = lợi ích giảm dần.

---

### [2026-05-29] ⚠️ Orphaned `plugins.entries` → recurring "plugin not installed" validate warning

**Loại:** config-hygiene | plugins | validate-warning | suckhoe
**Discovered by:** Rùa/bot audit (Hưng relay) → Claude Code verify

**Triệu chứng:** Mỗi lần `config validate`/startup, suckhoe warn:
```
plugins.entries.memory-lancedb: plugin not installed: memory-lancedb — install the official external plugin with: openclaw plugins install @openclaw/memory-lancedb
```

**Root cause:** Config có `plugins.entries."memory-lancedb": {enabled:false}` nhưng package `@openclaw/memory-lancedb` chưa bao giờ được cài (`~/.openclaw-suckhoe/npm/node_modules/@openclaw/` không có). OpenClaw validate vẫn warn cho mọi entry trỏ tới plugin không tồn tại — **kể cả khi `enabled:false`**.

**Fix (zero-risk):** Xóa hẳn key `memory-lancedb` khỏi `plugins.entries`. suckhoe dùng `memorySearch.provider:openai` + `sources:["memory"]` (memory-core built-in), KHÔNG dùng lancedb → entry hoàn toàn thừa. Cần restart suckhoe (plugins.entries không hot-reload). hungreo/nemotron không có entry này.

**Phân biệt false-positive:** Các dòng log chứa chữ "lancedb"/"stale" trên hungreo thực ra là **text báo cáo của bot audit lọt vào journal** (relay raw sub-agent report — pipeline behavior), KHÔNG phải runtime warning. Grep log phải đọc nội dung dòng, đừng chỉ đếm match.

---

### [2026-05-29] 🔑 CLI probe phải set CẢ `OPENCLAW_STATE_DIR` + `--profile` (token/port per-profile)

**Loại:** cli | gateway-auth | multi-profile | gotcha

**Vấn đề:** Mỗi profile có `gateway.auth.token` + `gateway.port` RIÊNG (hungreo 18789, suckhoe 18795, nemotron 18796). CLI command nào nói chuyện với gateway (`channels status --probe`, `agent`, ...) đọc token từ state dir. Nếu gọi **trống** `openclaw channels status` → dùng default `~/.openclaw` token → **mismatch với gateway đích** → auth fail / probe sai.

**Đúng cách (LUÔN set cả 2):**
```bash
OPENCLAW_STATE_DIR=/home/hung/.openclaw-<profile> ~/.npm-global/bin/openclaw --profile <profile> <command>
```
Ví dụ UAT model: `OPENCLAW_STATE_DIR=/home/hung/.openclaw-hungreo ~/.npm-global/bin/openclaw --profile hungreo agent --json ...`

**Verify gateway thật đang nghe đúng port:** `ss -ltnp | rg '18789|18795|18796'`

---

### [2026-05-29] 🔁 RECURRING + NEW SHAPE — 5.27 auto-migrate `openai-codex/`→`openai/` giờ thêm `agentRuntime:{id:"codex"}`

**Loại:** upgrade | auto-migrate | recurring-bug | new-behavior
**Discovered by:** Claude Code (Opus 4.8) — DIFF defensive workflow, Bước 4

**Triệu chứng (lặp lại từ 5.12/5.18/5.22):** Upgrade 5.26 → 5.27, chỉ **hungreo** bị doctor migrate `agents.defaults.model.primary` `openai-codex/gpt-5.5` → `openai/gpt-5.5`. suckhoe + nemotron KHÔNG bị (giả thiết cũ: hungreo có nhiều plugin entries openai/codex/anthropic/google → doctor "rationalize" sang `openai/`).

**MỚI ở 5.27:** migration không chỉ đổi primary string mà còn **thêm field** vào model entry:
```json
"openai/gpt-5.5": { "agentRuntime": { "id": "codex" } }
```
→ 5.27 chủ ý route `openai/gpt-5.5` qua Codex OAuth backend (khớp CHANGELOG: "resolve Codex runtime models before generic routing" + #82864). Tức về lý thuyết vẫn $0. **NHƯNG** vẫn LOSE explicit choice của Hưng + chưa verify đủ → fix vẫn là **restore `openai-codex/gpt-5.5`** (proven-good, validate pass ở 5.27).

**Fix (services đang stopped trong upgrade nên set trực tiếp, không cần lo hot-reload race):**
```python
d["agents"]["defaults"]["model"]["primary"]="openai-codex/gpt-5.5"
# rồi: openclaw --profile hungreo config validate  → "Config valid"
```

**Diff benign khác ở 5.27 (KHÔNG cần restore):**
- Doctor tự dọn duplicate `installs.lossless-claw` (`extensions/` path) → fix luôn duplicate-plugin warning [2026-05-25].
- `lastTouchedVersion` 2026.4.12 → 5.27 (chỉ metadata).
- Thêm `nano-banana-pro:{enabled:false}` + `bundledDiscovery:"compat"` (field mới, vô hại).

**Lesson workflow:** Upgrade stop-first (proper) → 0 broken-window error. Đối lập: upgrade 5.22→5.26 LIVE (session trước) để lại `Cannot find module` ở process cũ lúc shutdown — transient, không hại vì fallback giờ là deepseek (rẻ) + 0 drift, nhưng vẫn vi phạm Hard Rule #1. **Stop-first vẫn bắt buộc.**

---

### [2026-05-25] 🔥 INCIDENT — LCM 0.11.2 Upgrade: nemotron plugin missing & duplicate plugin warning

**Loại:** incident | plugin-install | config-path | verify-workflow

- Khi cài OpenClaw plugin theo profile, bắt buộc set đúng `OPENCLAW_STATE_DIR=/home/hung/.openclaw-<profile>`. Nếu quên, plugin có thể cài nhầm vào shared `~/.openclaw` và profile thật sẽ boot thiếu context engine.
- Dấu hiệu: service vẫn active nhưng request fail với `Context engine "lossless-claw" is not registered. Available engines: legacy`.
- Verify không chỉ dùng `systemctl is-active`; phải check logs sau restart có `ready (... lossless-claw ...)` và không còn `Context engine`.
- Với lossless-claw 0.11.x, install path chuẩn là `~/.openclaw-<profile>/extensions/lossless-claw`; package cũ ở `~/.openclaw-<profile>/npm/node_modules/@martian-engineering/lossless-claw` có thể gây `duplicate plugin id`.
- Trước khi xóa stale plugin folder, phải verify profile/path/version rõ ràng; tốt nhất backup config trước và report command đã chạy.
- Check list sau fix: service state, ExecStart/binary version, ports, config `plugins.installs/entries`, package path versions, journal grep `lossless-claw|duplicate plugin id|Context engine|error|fail|ready`.
- Không claim 100% nếu chưa chạy UAT model call; ghi rõ “config/log verified, no live model UAT unless user approves”.

### [2026-05-24 đêm] 🔥 ROOT CAUSE — suckhoe Codex OAuth `refresh_token_reused` (silent deepseek fallback)

**Loại:** oauth | codex | session-state | shared-account | RECURRING-PATTERN
**Discovered by:** Hưng (UX leak qua /status) → Claude Code (log diagnosis)

**Symptom:**
- `/status` báo `Model: openai-codex/gpt-5.5` (đúng primary)
- Nhưng runtime thật fallback `deepseek/deepseek-v4-pro`
- **Clue định danh nhanh**: `📚 Context: 0/1.0m` trên /status. GPT-5.5 chỉ 256K context; **1.0M = deepseek đang chạy thật**
- Session pin auto sang deepseek; clear pin → recur ngay sau request mới

**Root cause (REAL, không phải session pin):**
- 2 profiles (hungreo + suckhoe) share cùng OAuth account `hungreo2005@gmail.com`
- OpenAI Codex dùng **single-use refresh tokens** — khi hungreo refresh thành công, refresh token cũ bị invalidate
- Suckhoe vẫn giữ refresh token cũ → khi cần refresh → `401 refresh_token_reused`
- Mọi request đến `openai-codex/gpt-5.5` từ suckhoe fail → auto-fallback deepseek → pin session
- Log dấu hiệu: `OpenAI Codex token refresh failed (401)` + `code=refresh_token_reused`

**Fix verified (2026-05-24 đêm):**
1. Re-auth suckhoe qua **device-code flow** (KHÔNG copy token từ hungreo)
2. Set auth profile order: `openai-codex:hungreo2005@gmail.com`
3. `systemctl --user restart openclaw-gateway-suckhoe`
4. UAT cả suckhoe + hungreo đều dùng `openai-codex/gpt-5.5` success, no fallback
5. Both profiles work song song trong vòng test window

**⚠️ KHÔNG dùng làm fix chính: copy `auth-profiles.json` codex entry từ hungreo → suckhoe**
- Quick fix nhưng vẫn share single-use refresh token → bug recur ~10 ngày sau khi token cycle
- Re-auth qua device-code là proper fix

**Hard rule (cập nhật):**
Khi diagnose "session dùng sai model":
1. Đầu tiên check `/status` Context size — clue cho underlying runtime (vd 1.0M ≠ gpt-5.5 256K)
2. Grep gateway log `refresh_token_reused|FailoverError|OAuth.*refresh.*fail`
3. Check `auth-profiles.json` expiry — nếu expired và share account với profile khác → re-auth, đừng copy token

---

### [2026-05-17] Brave provider config can still route to Gemini if Google web-search is enabled

**Loai:** web-search | brave | gemini | plugin-routing | config
**Discovered by:** Codex after Rùa caught `web_search` returning `provider: "gemini"` on `hungreo`.
**Affects:** Profiles with both `plugins.entries.google.enabled = true` and `plugins.entries.brave.enabled = true`, especially when `GEMINI_API_KEY` is present in the Gateway process environment.

**Symptom:**
- `tools.web.search.provider = "brave"`.
- `BRAVE_API_KEY` direct API test returns HTTP 200.
- `web_search` tool call succeeds or runs, but tool result shows:
  ```json
  { "provider": "gemini", "model": "gemini-2.5-flash" }
  ```

**Root cause pattern:**
The Google plugin registers a `web-search: gemini` provider. Runtime web-search metadata can prefer that provider ahead of the top-level `tools.web.search.provider` setting. Checking only `toolSummary.calls = 1` and `failures = 0` is not enough; it proves the tool ran, not that Brave was used.

**Verified fix on `hungreo`:**
1. Keep `tools.web.search.provider = "brave"`.
2. Keep `plugins.entries.brave.enabled = true` and include `brave` in `plugins.allow` when an allowlist exists.
3. Disable Google plugin for the profile:
   ```json
   "plugins": {
     "entries": {
       "google": { "enabled": false }
     }
   }
   ```
4. If `memorySearch.provider = "gemini"` is needed, move the Gemini key into `agents.defaults.memorySearch.remote.apiKey` and remove/clear `GEMINI_API_KEY`/`GOOGLE_API_KEY` from the Gateway service environment so Google web-search is not auto-selected.
5. Restart the affected profile and UAT by parsing the actual tool result, not just `toolSummary`.

**Good UAT evidence:**
```json
{
  "provider": "brave",
  "result_count": 1,
  "first_url": "https://openai.com/news/"
}
```

Also verify `memory_search` if the profile still uses Gemini embeddings.

---

### [2026-05-17] Brave web_search needs the Brave plugin package, not just provider config

**Loai:** web-search | brave | config | plugin-install | lossless-claw
**Discovered by:** Codex during Perplexity → Brave migration on VPS.
**Affects:** Profiles switching `tools.web.search.provider` to `brave` on OpenClaw 2026.5.12.

**Symptom:**
- Direct Brave API test with `BRAVE_API_KEY` returns HTTP 200.
- Config has `tools.web.search.provider = "brave"`.
- But `openclaw config validate` fails:
  ```
  tools.web.search.provider: web_search provider is not available: brave (install or enable plugin "brave", then run openclaw doctor --fix)
  ```

**Root cause:**
On 2026.5.12, the Brave search provider also requires the `@openclaw/brave-plugin` package to be installed and the `plugins.entries.brave.enabled = true` config entry to exist. `BRAVE_API_KEY` alone is not enough.

**Safe fix pattern:**
1. Backup `openclaw.json`, `.env`, `gateway.systemd.env`, and profile npm metadata.
2. Add `BRAVE_API_KEY` to the Gateway env without printing it.
3. Install pinned plugin in each affected profile npm dir:
   ```bash
   npm install --prefix ~/.openclaw-<profile>/npm --omit=dev --save-exact @openclaw/brave-plugin@2026.5.12
   ```
4. Set:
   ```json
   "tools": { "web": { "search": { "enabled": true, "provider": "brave" } } },
   "plugins": { "entries": { "brave": { "enabled": true } } }
   ```
5. If `npm install` removes `lossless-claw` peer symlinks, relink `@mariozechner/pi-*` to the current `@earendil-works/pi-*` packages before restart.
6. Validate config, restart affected service, probe channel status, and run `agent --json` UAT that forces one `web_search` call.

**Gotcha:**
`openclaw plugins install @openclaw/brave-plugin` may fail when `lossless-claw` cross-namespace symlinks are present:
```
managed npm peer dependency scan found package outside managed npm root
```
Using `npm install --prefix ~/.openclaw-<profile>/npm ...` is the narrow workaround; then verify/relink `lossless-claw`.

---

### [2026-05-15] Web search missing can be a `tools.allow` issue even when Perplexity is enabled

**Loai:** web-search | perplexity | config | tool-allowlist
**Discovered by:** Codex during urgent fallback-cost mitigation.
**Affects:** Profiles with explicit `tools.allow` arrays, especially `hungreo`.

**Symptom:**
- Perplexity API key is valid via direct API test.
- `plugins.entries.perplexity.enabled = true`.
- `tools.web.search.enabled = true`.
- But agent says there is no `web_search` tool, and `systemPromptReport.tools.entries` does not include `web_search`.

**Root cause:**
An explicit `tools.allow` array is an allowlist. If it omits `web_search` and `web_fetch`, the web tools are not injected even when the web-search config and Perplexity plugin are enabled.

**Verified fix:**
Add both tools to the profile config:
```json
"tools": {
  "allow": [
    "...",
    "web_search",
    "web_fetch"
  ]
}
```

Then validate and restart/probe the profile. Verification should show:
- `systemPromptReport.tools.entries` includes `web_search` and `web_fetch`
- `result.meta.toolSummary.calls = 1`
- `result.meta.toolSummary.failures = 0`

**Related 2026-05-15 mitigation:**
Changed `hungreo` and `suckhoe` fallbacks from `anthropic/claude-sonnet-4-6` to `deepseek/deepseek-v4-pro` and copied `models.providers.deepseek` plus `DEEPSEEK_API_KEY` env into both profiles to avoid accidental Claude fallback cost.

---

### [2026-05-15] Telegram error bubble can precede successful post-timeout compaction retry

**Loai:** telegram | timeout | compaction | delivery-gap
**Discovered by:** Codex audit after Hưng saw `Something went wrong` from hungreo at 13:10.
**Affects:** Long Telegram DM turns on hungreo, especially research tasks with large existing session context.

**Symptom:**
- User sends a research-heavy Telegram DM.
- Bot replies with:
  ```
  ⚠️ Something went wrong while processing your request. Please try again, or use /new to start a fresh session.
  ```
- Journal shows `CommandLaneTaskTimeoutError` at 210s, but the agent may continue compaction/retry in the background and produce a final assistant answer later.

**Verified incident:**
- Time: 2026-05-15 13:06-13:12 +07
- Session: `/home/hung/.openclaw-hungreo/agents/main/sessions/678536d4-ea9e-4f21-a6b5-dadecc768c3e.jsonl`
- Config: `agents.defaults.timeoutSeconds = 180`; lane timeout fired at 210s.
- First attempt timed out with high prompt usage and triggered:
  ```
  [timeout-compaction] LLM timed out with high prompt token usage (89%); attempting compaction before retry
  ```
- Retry succeeded at 13:12 and wrote a real answer into the session, but no `sendMessage` log was observed after the user-facing error.

**Root cause pattern:**
Long turn duration exceeded the command lane/user-facing timeout before OpenClaw's timeout-compaction retry completed. The retry result can be persisted to the session but not delivered to Telegram after the lane has already failed.

**Debug checklist next time:**
1. Check journal around the user-facing error for `CommandLaneTaskTimeoutError`, `timeout-compaction`, and `run done`.
2. Inspect the matching `.trajectory.jsonl` for a later `model.completed` success.
3. If final answer exists but no `sendMessage` line follows, it is a delivery-gap after timeout, not a provider outage.
4. For immediate user recovery, start `/new` or rerun the answer in a fresh explicit session; avoid reusing the bloated Telegram direct session.

**Likely mitigation:**
- For heavy research from Telegram, use a fresh session (`/new`) or ask hungreo to do a shorter scoped pass first.
- Consider increasing `agents.defaults.timeoutSeconds` only after weighing the UX trade-off: fewer premature errors, but longer waits when a turn is genuinely stuck.

---

### [2026-05-15 tối] ✅ Upgrade 2026.5.18 + lossless-claw 0.11.1 — workflow stop-first hoạt động tốt

**Loại:** upgrade | validation-workflow-pattern | recurring-gotcha

**Outcome:** Upgrade thành công ~10 phút downtime, KHÔNG có cost leak.

**Recurring gotcha (đã catch + restore):**
- **Auto-migrate `openai-codex/gpt-5.5` → `openai/gpt-5.5`** cho hungreo lặp lại (giống 5.12, openclaw 5.18 chưa fix)
- DIFF backup vs current đã catch ngay → restore → KHÔNG tốn tiền
- **MỖI lần upgrade phải DIFF config** — đây là rule cứng vĩnh viễn

**Lossless-claw 0.11.1:**
- Native `@earendil-works/*` deps → KHÔNG cần symlink workaround `@mariozechner/*` nữa
- Khi upgrade từ 0.9.x lên 0.11.x: remove old symlinks, `plugins install --pin --force` auto pull `@earendil-works`
- Schema migration cho `lcm.db` chạy tự động khi gateway boot

**Patch 1 + 2 đều UPSTREAM FIXED trong 2026.5.18** — không cần re-apply runtime patches nữa.

**NEW plugin auto-enabled trong 5.18:** `brave` (web search). Cả 3 profiles có thêm plugin này. Cần verify không tốn API cost (Brave có free tier).

**Workflow stop-first đã prove value:**
- KHÔNG có broken window 5 phút như 5.7 upgrade (đốt $3 Anthropic)
- Hot reload không applicable cho npm install dist files
- Verify 3 tầng (gateway log + sessions.json + CLI UAT) catch được mọi issue trước khi user notice

---

### [2026-05-15] 🔥 GOTCHA — Telegram `streaming.mode: "partial"` leak progress drafts ra DM

**Loại:** telegram | streaming | UI-leak | DM-vs-group | hot-reload-pattern
**Discovered by:** Hưng (catch UI leak) + Rùa-bot (root cause analysis)
**Affects:** Bất kỳ profile nào dùng `channels.telegram.streaming.mode != "off"` — leak trong DM khi agent dùng tools

**Triệu chứng (sau khi đã fix lossless-claw load):**
Bot DM gửi nhiều message trông như "lộ dây điện":
- `Surfacing...`
- `Pearling...` / `Snapping...`
- `🛠️ run test...` / `🩹 Apply Patch` / `🛠️ search...`
- `📊 Session Status: current`
- `🖼️ Image: Mô tả ngắn gọn...`

Sau đó MỚI gửi reply tự nhiên ("Hi Hưng 🐢...").

**Root cause (không phải lossless-claw):**

1. `channels.telegram.streaming.mode = "partial"` (default từ trước upgrade) khiến Telegram channel tạo **draft preview message** khi agent đang xử lý
2. Runtime push **tool progress lines** vào draft preview để hiển thị "live progress" cho user
3. `messages.groupChat.visibleReplies = "message_tool"` chỉ áp dụng cho **group/topic**, KHÔNG áp dụng DM
4. → Trong DM, draft progress bubbles không được suppressed → leak ra
5. Patch 2 (`!embedded && messageTool`) chỉ fix **final reply path** qua message tool, KHÔNG cover **draft/progress streaming path**

**Source code references (openclaw 2026.5.12 dist):**
- `channel-streaming-BfXk-s2d.js`: `["Pearling...", "Snapping...", "Surfacing..."]` — progress draft labels hardcoded
- `reply-delivery-BI4rGjxI.js` + `tool-display-CzQN47mi.js`: "Session Status:" trace lines
- Discord trace line regex: `DISCORD_INTERNAL_TRACE_LINE_RE` filter — không apply cho Telegram path

**Fix (1 dòng config — recommended Option A):**
```json
"channels": {
  "telegram": {
    "streaming": {
      "mode": "off"
    }
  }
}
```

Trade-off:
- ✅ Triệt tiêu draft/progress leak trong DM + group
- ❌ Mất "đang gõ..." indicator → user có thể nghĩ bot treo khi task >5s
- 🟡 Reply cuối vẫn bình thường qua message_tool (Patch 2 vẫn cần thiết)

**Defense-in-depth (Option B/C, chưa apply):**
- `messages.directChat.visibleReplies = "message_tool"` — cover DM path tương tự groupChat
- `messages.visibleReplies = "message_tool"` — top-level cover all
- → Cần verify schema 2026.5.12 có hỗ trợ key này không

**Pattern: Hot reload qua config edit (KHÔNG cần restart)**

OpenClaw có hot reload cho 1 số config keys. `channels.telegram.streaming.mode` là 1 trong số đó:

```bash
# Edit config (no stop needed)
python3 -c "
import json
f='/home/hung/.openclaw-suckhoe/openclaw.json'
d=json.load(open(f))
d['channels']['telegram']['streaming']={'mode':'off'}
json.dump(d, open(f,'w'), indent=2)
"
# Wait ~1-2s — gateway tự detect:
# [reload] config change detected; evaluating reload (channels.telegram.streaming.mode)
# [reload] config hot reload applied (channels.telegram.streaming.mode)
```

So sánh hot reload vs full restart:
| | Hot reload | Full restart |
|---|---|---|
| Downtime | 0ms | 5-10s |
| In-flight messages | Drained tự nhiên | Có thể bị drop nếu chưa flush |
| Side effect | Chỉ reload component bị change | Reload everything |
| Khi nào dùng | Config change đơn lẻ | Khi có pending ops chậm hoặc plugin add/remove |

Note: Nếu gateway có **pending operations** lúc edit, sẽ thấy log `config change requires channel reload (telegram) — deferring until N operations complete` → có thể defer đến full restart. Đây là hành vi của hungreo lúc 07:13 (Rùa edit khi đang xử lý DM trước).

**Hard rule mới cho personal bots (bot user-facing):**

> Mặc định `channels.telegram.streaming.mode = "off"` cho mọi profile có user-facing DM, trừ khi user explicitly muốn live progress. Mặc định "partial" của OpenClaw không phù hợp UX conversational.

Apply across all 3 profiles (đã làm):
- hungreo: off ✅ (Rùa tự apply 2026-05-15 07:13)
- suckhoe: off ✅ (apply 2026-05-15 08:52)
- nemotron: off ✅ (sẵn từ trước)

---

### [2026-05-15] 🔥 GOTCHA — 2026.5.12 rename namespace `@mariozechner/*` → `@earendil-works/*`

**Loại:** upgrade | namespace-rename | lossless-claw-fail | UI-leak
**Discovered by:** Hưng (catch UI leak qua Telegram screenshot — bot lộ "Surfacing..." + "📊 Session Status: current")

**Triệu chứng:**
- Sau upgrade 2026.5.7 → 2026.5.12, `lossless-claw` plugin **fail to load**:
  ```
  [plugins] lossless-claw failed to load: Error: Cannot find module '@mariozechner/pi-coding-agent'
  ```
- Gateway log thiếu `lossless-claw` trong plugins line
- **UI leak**: Bot gửi progress draft messages (`"Surfacing..."`, `"Pearling..."`, `"Snapping..."`) và internal trace lines (`📊 Session Status: current`) làm tin nhắn riêng cho user → "lộ dây điện kỹ thuật"

**Root cause:**
- OpenClaw 2026.5.12 đã rename peer dependency packages từ `@mariozechner/*` → `@earendil-works/*`
- File path: `~/.npm-global/lib/node_modules/openclaw/node_modules/@earendil-works/pi-{agent-core,ai,coding-agent}` (KHÔNG còn `@mariozechner/`)
- Nhưng `@martian-engineering/lossless-claw@0.9.4` (latest) vẫn declare peer dependency cũ:
  ```
  peerDependencies: {
    "@mariozechner/pi-agent-core": ">=0.66 <1",
    "@mariozechner/pi-ai": ">=0.66 <1",
    "@mariozechner/pi-coding-agent": ">=0.66 <1"
  }
  ```
- Symlinks cũ `~/.openclaw-{profile}/npm/node_modules/@mariozechner/pi-*` trỏ vào path không tồn tại nữa → broken
- Khi lossless-claw không load → context engine không buffer agent text → progress drafts + internal traces leak ra Telegram

**Fix (cross-namespace symlink):**
```bash
BASE=~/.npm-global/lib/node_modules/openclaw/node_modules/@earendil-works
for profile in hungreo suckhoe nemotron; do
  TARGET=~/.openclaw-${profile}/npm/node_modules/@mariozechner
  mkdir -p "$TARGET"
  for pkg in pi-agent-core pi-ai pi-coding-agent; do
    rm -f "$TARGET/$pkg"
    ln -s "$BASE/$pkg" "$TARGET/$pkg"
  done
done
```
Note: Symlink hoạt động vì Node module resolution dùng directory location, không kiểm `name` field trong package.json.

**Long-term fix:** Khi `@martian-engineering/lossless-claw@0.9.5+` ra mắt với peer deps `@earendil-works/*`, có thể bỏ symlink workaround.

**Lesson cho upgrade workflow (BẮT BUỘC thêm step):**

Step 7 (verify symlinks) phải được mở rộng:
- Check symlink **EXISTS** ✓ (đã làm)
- Check symlink **NOT BROKEN** (`[ -e "$LINK" ]`, không phải `[ -L "$LINK" ]`)
- Check **gateway log** confirm lossless-claw IN plugins line (sau khi start)
- Check **NO** `Cannot find module` errors trong startup log

Nếu broken → check `~/.npm-global/lib/node_modules/openclaw/node_modules/` cho namespace mới và relink.

---

### [2026-05-24 tối] 🔥 BLINDSPOT — Session auto-pin sang **DEEPSEEK** (không chỉ anthropic!)

**Loại:** session-state | auto-pin | post-upgrade | blindspot
**Discovered by:** Hưng (qua /status thấy suckhoe model=deepseek thay vì gpt-5.5)

**Triệu chứng:**
- Sau upgrade suckhoe 5.18 → 5.22 (lúc 20:14), Hưng `/status` lúc 20:34 → `Model: deepseek/deepseek-v4-pro` (phải là `openai-codex/gpt-5.5`)
- 2 DM sessions của suckhoe bị auto-pin sang deepseek (Hưng + 1 user khác)
- Cron jobs cũng có deepseek state nhưng KHÔNG bị pin (chỉ là last-used)

**Root cause:**
- Sau restart, request đầu tiên có thể fail trên codex OAuth (chưa warmed up)
- OR provider auth pre-warm chậm (log: `provider auth state pre-warmed in 52149ms` cho hungreo)
- Auto-fallback sang `deepseek/deepseek-v4-pro` (configured fallback)
- Pin to session state với `modelOverrideSource=auto`
- Mọi message sau từ user đó → tiếp tục dùng deepseek (sticky pin)

**Tại sao mình MISS lúc verify:**
- Check session script chỉ filter `"claude" in modelOverride` hoặc `"anthropic" in authProfileOverride`
- KHÔNG catch deepseek pin vì lessons-learned trước đó chỉ về Anthropic leak
- **BLINDSPOT**: chỉ check pin-loại-cũ, không generalize check "pin nào KHÁC primary"

**Generalized fix (script):**
```python
# Detect DRIFT: any DM session pinned to non-primary model
primary_model = config["agents"]["defaults"]["model"]["primary"].split("/", 1)[1]
for sk, sv in sessions.items():
    if not sk.startswith("agent:main:telegram:direct:"): continue
    mo_source = sv.get("modelOverrideSource")
    mo = sv.get("modelOverride")
    if mo_source == "auto" and mo and mo != primary_model:
        # DRIFT detected — clear pin
```

**Fix workflow:**
1. Stop service (anti re-flush from memory)
2. Backup sessions.json
3. Clear ONLY DM sessions with auto-pin to non-primary
4. Start service
5. Verify next /status

**Cost impact 2026-05-24 tối:** $0. Deepseek rất rẻ (~$0.001/call), trong 20 phút Hưng + 1 user chat → ~$0.05 max. Không tổn thương như Anthropic incident.

**NEW HARD RULE (cập nhật rule #3):**

OLD rule #3: "Sau MỌI upgrade, audit `sessions.json` cho `modelOverrideSource=auto` + `authProfileOverride=anthropic:manual` → clear"

NEW rule #3 (generalized):
> **Sau MỌI upgrade hoặc restart**, audit `sessions.json` cho **bất kỳ DM session nào** có `modelOverrideSource=auto` với `modelOverride != primary_model` → clear pin để re-resolve về primary.

Filter check phải dùng **drift detection** (so sánh với primary config), không hardcode tên model cụ thể (claude, anthropic, etc.).

**Why this happened despite "cost-safe" fallback (deepseek):**
- User explicit yêu cầu primary = openai-codex/gpt-5.5
- Fallback chỉ là backup nếu primary thật sự fail
- Sticky pin = user mất control, không phải "cost-safe" thì OK
- Workflow guardrail: KHÔNG được giả định pin là OK vì fallback rẻ

---

### [2026-05-24] 🔁 RECURRING — `openai-codex/` → `openai/` auto-migrate vẫn xuất hiện trong 5.22

**Loại:** upgrade | auto-migrate | recurring-bug
**Discovered by:** Claude Code (DIFF defensive workflow)

**Triệu chứng:** Upgrade openclaw 5.18 → 5.22, hungreo's `agents.defaults.model.primary` bị auto-migrate `openai-codex/gpt-5.5` → `openai/gpt-5.5` MẶC DÙ CHANGELOG 5.18 đã claim fix (#82864).

**Tại sao recurring?**
- 5.18 fix (#82864) chỉ route `openai/*` refs → Codex OAuth backend (no cost impact)
- KHÔNG ngăn migration tự xảy ra
- Migration vẫn LOSE user's explicit `openai-codex/*` config choice
- Note: 5.22 CHANGELOG: "Models: prune retired ... with doctor migration to upgrade existing configs to current provider refs" — likely the trigger

**Tại sao chỉ hungreo bị, suckhoe + nemotron không?**
- Suckhoe primary là `openai-codex/gpt-5.5` (giống hungreo) nhưng KHÔNG bị migrate
- Khác biệt duy nhất: hungreo có nhiều plugin entries (`openai`, `codex`, `anthropic`, `google`) trong config; suckhoe ít hơn
- Giả thiết: Doctor migration check `plugins.entries.openai.enabled = true` → conclude rằng nên dùng `openai/` provider thay vì `openai-codex/`
- Cần verify khi rảnh — disable `plugins.entries.openai` cho hungreo có thể prevent migration tương lai

**Fix (cùng quy trình từ 2026-05-15):**
```python
d = json.load(open("/home/hung/.openclaw-hungreo/openclaw.json"))
d["agents"]["defaults"]["model"]["primary"] = "openai-codex/gpt-5.5"
json.dump(d, open(f, "w"), indent=2)
# 5.22 hỗ trợ hot reload model primary → KHÔNG cần restart
```

**5.22 new feature: Hot reload cho `agents.defaults.model.primary`** ← tốt cho fix nhanh
Log line: `[reload] config hot reload applied (agents.defaults.model.primary)`

**Gotcha PHASE 5/6 order:**
- `openclaw update --yes --no-restart` đôi khi tự start services (qua doctor migration logic)
- → Sau khi update xong, services có thể đã RUNNING với OLD override.conf env
- → PHASE 5 update override.conf → daemon-reload KHÔNG đủ; phải EXPLICIT `systemctl restart` để load env mới
- **Hệ quả**: env_VER hiển thị OLD version dù binary thật là NEW
- **Cách verify**: sau PHASE 5, check `systemctl --user show <svc> --property=ActiveEnterTimestamp` — nếu trước thời điểm override.conf change → cần restart

**Workflow improvement:**
```
PHASE 5 (UPDATED): Update override.conf → daemon-reload
PHASE 6 (UPDATED): systemctl restart (không phải start) — đảm bảo fresh env load
```

**Cost impact 2026-05-24:** $0. Vì:
1. Fallback giờ là DeepSeek (rẻ), không phải Anthropic
2. Caught auto-migrate ngay tức thì (PHASE 4 DIFF)
3. Hot reload restored ngay không downtime

---

### [2026-05-15] 🔥 GOTCHA — 2026.5.12 upgrade auto-migrate `openai-codex/` → `openai/` provider

**Loại:** upgrade | config-migration | cost-leak-prevented | CRITICAL
**Discovered by:** Claude Code (caught via runtime model log diff sau upgrade)
**Affects:** Bất kỳ profile nào có primary `openai-codex/*` khi upgrade lên 2026.5.12+

**Triệu chứng:**
- Sau `openclaw update --yes --no-restart` từ 2026.5.7 → 2026.5.12
- Config bị rewrite: `agents.defaults.model.primary: openai-codex/gpt-5.5` → `openai/gpt-5.5`
- Gateway log: `[gateway] agent model: openai/gpt-5.5` (thay vì `openai-codex/gpt-5.5`)
- **Hậu quả nếu không catch:** `openai/gpt-5.5` cần `OPENAI_API_KEY` (paid). Nếu env không có → fail → trigger Anthropic fallback → đốt tiền (lặp lại scenario 2026-05-08).

**Root cause (giả thiết):** Upgrade-time "doctor install repair" hoặc plugin auto-enable logic trong 2026.5.12 — CHANGELOG ghi:
> "Codex startup: treat selectable configured OpenAI agent models as Codex runtime requirements during plugin auto-enable, startup planning, and doctor install repair, so Anthropic-primary configs can still switch to OpenAI/Codex cleanly."

Logic này có thể "rationalize" provider name. Quirk: hungreo bị migrate, suckhoe không bị (chưa rõ tại sao — có thể vì hungreo có plugin entry `openai` trong config, suckhoe không).

**Fix:**
1. Compare backup vs current config sau upgrade — diff `agents.defaults.model.primary`
2. Nếu bị đổi → restore từ backup
3. Stop service trước khi restore, start lại sau

**Script verify auto-migration:**
```python
import json, glob
baks = sorted(glob.glob("/home/hung/.openclaw-{profile}/openclaw.json.bak-*-pre-upgrade-*"))
bd = json.load(open(baks[-1]))
cd = json.load(open("/home/hung/.openclaw-{profile}/openclaw.json"))
bp = bd["agents"]["defaults"]["model"].get("primary")
cp = cd["agents"]["defaults"]["model"].get("primary")
if bp != cp:
    print(f"!! {profile} primary CHANGED: {bp} -> {cp}")
```

**Lesson cho upgrade workflow (BẮT BUỘC thêm step):**

Sau Step 5 (`openclaw update`), thêm Step 5b:
```
5b. DIFF backup vs current openclaw.json — verify config không bị auto-migrate model/provider/auth
   Nếu bị → restore field bị thay đổi (KHÔNG để upgrade tự đổi model)
```

---

### [2026-05-08] 🔥 INCIDENT — Upgrade gây ANTHROPIC API LEAK qua session auto-pin

**Loại:** incident | cost-leak | upgrade | session-state | CRITICAL
**Discovered by:** Hưng (phát hiện qua /status + check Anthropic billing > $3 đốt trong 30 phút)
**Affects:** TẤT CẢ upgrade từ giờ → MUST stop services TRƯỚC khi `npm install`

**Hậu quả:** ~$3 USD đã bị đốt vào Anthropic API key (billed) trong 30 phút từ 15:21 → 15:50, mặc dù config primary luôn là `openai-codex/gpt-5.5` (OAuth ChatGPT subscription, không tốn tiền).

**Chuỗi sự kiện (root cause):**

1. **15:21 — Upgrade `openclaw update --yes --no-restart` chạy KHI service đang LIVE**
   - npm ghi đè files dist của 2026.5.6 → 2026.5.7 dưới chân process đang chạy
   - Process cũ ôm cached imports vào files 2026.5.6 đã bị xóa: `task-registry.maintenance-CvTYvEjK.js`, `hook-runner-global-BaH8wNFP.js`
   
2. **15:21–15:26 — Gateway broken, request handler fail liên tục với `ERR_MODULE_NOT_FOUND`**
   - OpenClaw có cơ chế **silent auto-fallback**: khi primary provider fail → auto-pin session sang fallback (`anthropic/claude-sonnet-4-6`) + lưu pin vào `sessions.json`
   - Pin gồm: `modelOverride`, `providerOverride`, `authProfileOverride: anthropic:manual` với `Source: auto`
   - Sessions bị pin: `agent:main:main`, `agent:main:telegram:direct:7957776935` (DM của user), `agent:main:main` (suckhoe)

3. **15:26:46 — Systemd auto-restart sau crash → process mới (PID 434301) load clean dist**
   - Gateway-level `agent model` log: `openai-codex/gpt-5.5` ✅
   - **NHƯNG**: pins trong `sessions.json` VẪN ở đó → mỗi session/cron trigger trong 30 phút sau đều dùng Anthropic
   
4. **15:50 — Hưng phát hiện qua `/status` Telegram**: `Model: anthropic/claude-sonnet-4-6 · token (anthropic:manual)`

**Tại sao bot tự attribute Hưng đã đổi model:** Claude Code (mình) ban đầu nhìn vào log gateway thấy `agent model: openai-codex/gpt-5.5` → kết luận sai là "đã ổn". Bỏ qua tầng session state. Đây là pattern đã ghi trong memory `feedback_session_auto_pin.md` nhưng không được apply.

**Fix đã áp dụng (15:50):**
- Stop hungreo + suckhoe → re-verify session file sạch sau stop → re-clear safety → start
- Clear chỉ 3 pins trỏ về anthropic (giữ nguyên các pin trỏ tới `openai-codex:default` vì không tốn tiền)
- KHÔNG đụng `openclaw.json` config, KHÔNG đụng `auth.profiles`, KHÔNG đụng `fallbacks` array
- Giữ nguyên Anthropic Sonnet 4.6 làm fallback theo ý Hưng

**Script clear pins (chỉ xoá pin tới anthropic):**
```python
import json, shutil, time
ts = time.strftime("%Y%m%d-%H%M")
for profile in ["hungreo", "suckhoe"]:
    f = f"/home/hung/.openclaw-{profile}/agents/main/sessions/sessions.json"
    d = json.load(open(f))
    cleared = []
    for sk, sv in d.items():
        if not isinstance(sv, dict): continue
        is_a_model = sv.get("modelOverrideSource") == "auto" and "claude" in str(sv.get("modelOverride","")).lower()
        is_a_auth = sv.get("authProfileOverrideSource") == "auto" and "anthropic" in str(sv.get("authProfileOverride","")).lower()
        if is_a_model or is_a_auth:
            for k in ["modelOverride","modelOverrideSource","providerOverride",
                      "authProfileOverride","authProfileOverrideSource",
                      "authProfileOverrideCompactionCount","model","modelProvider"]:
                sv.pop(k, None)
            cleared.append(sk)
    if cleared:
        shutil.copy(f, f + f".bak-{ts}-pre-clear-anthropic-pins")
        json.dump(d, open(f,"w"), indent=2)
```

---

### 🛡️ NEW HARD RULES (mọi agent phải follow từ 2026-05-08)

**Rule 1 — Upgrade workflow MỚI: Stop-first, KHÔNG được update khi service LIVE**

```bash
# SAI (cũ): update khi đang chạy → 5 phút broken window
openclaw update --yes --no-restart  # ❌ service vẫn LIVE

# ĐÚNG (mới):
systemctl --user stop openclaw-gateway-hungreo.service openclaw-gateway-suckhoe.service openclaw-gateway-nemotron.service
OPENCLAW_STATE_DIR=~/.openclaw-hungreo openclaw update --yes --no-restart
# ... apply patches (Patch 2, override.conf, startup.memory, symlinks) ...
systemctl --user start openclaw-gateway-suckhoe.service
# wait ready → start hungreo → wait ready → start nemotron
```

**Rule 2 — Sau MỌI upgrade phải audit `sessions.json` cho 3 profile:**
```bash
grep -l "claude\|anthropic:manual" ~/.openclaw-{hungreo,suckhoe,nemotron}/agents/main/sessions/sessions.json
# Nếu match → check modelOverrideSource=auto → clear (chỉ pin trỏ anthropic)
```

**Rule 3 — TUYỆT ĐỐI cấm tự đổi/thêm/xoá:**
- `agents.defaults.model.*` (primary, fallbacks)
- `auth.profiles.*` (anthropic, openai-codex)  
- Bất kỳ field nào liên quan model/provider/auth trong `openclaw.json`
- → Phải hỏi Hưng trước. Áp dụng cho: Claude Code, hungreo bot, Nemo, Codex, mọi agent.

**Rule 4 — Verify "model thật đang dùng" KHÔNG đủ chỉ nhìn gateway log:**
- Gateway log: `agent model: ...` → là default từ config
- Per-session model: phải check `sessions.json` cho `modelOverride/authProfileOverride/Source=auto`
- Test thật: `/status` từ Telegram (cho thấy model thật đang serve session đó)

---

### [2026-05-08] Upgrade 2026.5.7 — nemotron @mariozechner symlinks bị xóa sau upgrade binary

**Loại:** upgrade | symlink | gotcha
**Discovered by:** Claude Code (Sonnet 4.6)
**Affects:** Nemotron profile (và có thể xảy ra với hungreo/suckhoe trong tương lai)

**Vấn đề:** Sau `openclaw update`, `~/.openclaw-nemotron/npm/node_modules/@mariozechner/` bị tái tạo fresh → symlinks `pi-agent-core`, `pi-ai`, `pi-coding-agent` bị xóa. hungreo/suckhoe không bị lần này nhưng có thể xảy ra bất kỳ lúc nào.

**Triệu chứng:** `ls ~/.openclaw-nemotron/npm/node_modules/@mariozechner/ | grep pi-` → rỗng

**Fix:**
```bash
BASE=~/.npm-global/lib/node_modules/openclaw/node_modules/@mariozechner
for profile in hungreo suckhoe nemotron; do
  TARGET=~/.openclaw-${profile}/npm/node_modules/@mariozechner
  for pkg in pi-agent-core pi-ai pi-coding-agent; do
    [ -e "$TARGET/$pkg" ] || ln -s "$BASE/$pkg" "$TARGET/$pkg" && echo "linked $profile/$pkg"
  done
done
```

**Kết quả 2026.5.7:**

| Patch | File cũ (2026.5.6) | File mới (2026.5.7) | Upstream fix? |
|---|---|---|---|
| Patch 2: message tool in embedded | `openclaw-tools-BDIFP6nv.js` | `openclaw-tools-0ftkmYS3.js` | ❌ Re-applied |

**Checklist sau mỗi upgrade (bổ sung):**
- ✅ Sau `openclaw update` → LUÔN kiểm tra symlinks cả 3 profiles, không chỉ hungreo/suckhoe
- ✅ Recreate nếu thiếu trước khi restart service

---

### [2026-05-07] Upgrade 2026.5.6 — Patch 2 vẫn cần re-apply, toolSummary nằm trong result.meta

**Loại:** upgrade | runtime-patch
**Discovered by:** Claude Code (Sonnet 4.6)
**Affects:** MỌI lần upgrade openclaw khi có Patch 2 active

**Kết quả 2026.5.6:**

| Patch | File cũ (2026.5.4) | File mới (2026.5.6) | Upstream fix? |
|---|---|---|---|
| Patch 1: final-only payload | `pi-embedded-X0afS0ip.js` | N/A (audit không cần, 5.4 đã fix) | ✅ upstream |
| Patch 2: message tool in embedded | `openclaw-tools-Lbc6zzNy.js` | `openclaw-tools-BDIFP6nv.js` | ❌ Re-applied |

**UAT gotcha:** `agent --json` response structure là nested — `toolSummary` nằm ở `result.meta.toolSummary`, KHÔNG phải top-level. Script phải traverse `data["result"]["meta"]["toolSummary"]`.

**Session cũ (codex-final-only-uat-256) trả về 0 payloads** vì UAT session này đã dùng trong 2026.5.4. Dùng session ID mới mỗi lần UAT (thêm suffix phiên bản).

**Upgrade flow chuẩn (2026.5.6, không cần plugin upgrade):**
1. Backup configs
2. `openclaw update --yes --no-restart` (3 profiles) — hungreo kéo npm global, suckhoe/nemotron "Before = After" là bình thường
3. Update `override.conf` hungreo/suckhoe + nemotron service file version
4. Re-apply Patch 2 vào dist file mới
5. Check @mariozechner symlinks — còn intact sau upgrade binary
6. Re-patch `installs.json startup.memory = true` cho hungreo/nemotron (suckhoe đã true)
7. `daemon-reload` → restart hungreo → UAT → restart suckhoe → restart nemotron

---

### [2026-05-06] Upgrade 2026.5.4 + 0.9.4 — audit dist trước khi upgrade khi có runtime patch active

**Loại:** upgrade | runtime-patch | guardrail
**Discovered by:** Claude Code (pre-upgrade audit)
**Affects:** MỌI lần upgrade openclaw khi có active runtime patch

**Pattern đã thiết lập:**
Trước khi upgrade openclaw bất kỳ version nào, nếu có active runtime patch:
1. Unpack tarball mới: `npm pack openclaw@<NEW_VER> && tar xzf ...`
2. Grep từng patched pattern trong dist files mới
3. Nếu upstream đã fix → không cần re-apply
4. Nếu chưa fix → note tên file mới (dist filenames đổi mỗi version!) → re-apply sau upgrade

**Kết quả 2026.5.4:**

| Patch | File cũ (2026.5.3-1) | File mới (2026.5.4) | Upstream fix? |
|---|---|---|---|
| Patch 1: final-only payload | `pi-embedded-CElEZtBc.js` | `pi-embedded-X0afS0ip.js` | ✅ `resolveFinalAssistantVisibleText()` |
| Patch 2: message tool in embedded | `openclaw-tools-D7Zj4hDN.js` | `openclaw-tools-Lbc6zzNy.js` | ❌ Re-applied |

**Patch 2 re-apply command (1 dòng):**
```bash
# File: dist/openclaw-tools-<HASH>.js (grep tên file mới bằng: ls dist/openclaw-tools-*.js)
sed -i 's/\.\.\.!embedded && messageTool ? \[messageTool\] : \[\]/...messageTool ? [messageTool] : []/g' <file>
node --check <file>  # verify syntax OK
```

**UAT command (dùng lại cho lần sau):**
```bash
/home/hung/.npm-global/bin/openclaw --profile hungreo agent --json \
  --timeout 180 --session-id codex-final-only-uat-<VER> \
  --message "UAT final-only check. Use the exec tool to run: printf tool-ok. After the tool result, reply with exactly FINAL_ONLY_OK and no other text."
# Expected: payloads[0].text = "FINAL_ONLY_OK", toolSummary.calls = 1
```

---

### [2026-05-06] Telegram group interim replies + wrong xfeed root cause

**Loại:** incident-audit | telegram | embedded-runner | xfeed
**Discovered by:** Codex read-only audit
**Affects:** `hungreo` Telegram group/topic `learning-research` and any embedded-runner Telegram flow

**Symptoms verified from live logs/session files:**
- `hungreo` topic `learning-research` sent multiple Telegram messages in one agent turn while the agent was still running tools.
- The agent first blamed n8n for raw English scraper posts, but the real source is `hungreo-xfeed` (`/home/hung/Development/hungreo-xfeed/poll.mjs`) via `hungreo-xfeed.timer`.
- `poll.mjs` currently formats raw tweet text with `formatMessage()` and posts it directly to Telegram; it has no Vietnamese summary/key-points/why-it-matters enrichment layer.

**Runtime finding:**
- Config can say `messages.groupChat.visibleReplies = "message_tool"`, but embedded runner may not expose the `message` tool.
- Current OpenClaw code path omits `message` in embedded mode (`!embedded && messageTool`), so group `message_tool` mode can degrade to automatic visible replies.
- Embedded payload building uses all non-empty assistant text blocks, not only the final assistant answer, so interim assistant text can become multiple Telegram sends.

**Do not conclude too early:**
- Do not assume "scraper" means n8n. Read `LOCAL_CONTEXT.md` first and check `hungreo-xfeed.timer` / `~/Development/hungreo-xfeed/` before touching n8n.
- Do not trust config-only proof for Telegram reply behavior. Verify the compiled system prompt and actual `sendMessage` logs for the affected session.
- OpenClaw version upgrade alone may not fix this if the same embedded `message` tool / payload collection code remains in the new dist.

**Preferred fix plan:**
1. Patch xfeed formatting/enrichment separately, with dry-run output before enabling posts.
2. Patch OpenClaw embedded reply payload behavior so external messaging receives only the final assistant answer unless an explicit message tool/send path is used.
3. Test with a non-production or controlled Telegram target first, then restart/probe one service at a time.

**Resolved 2026-05-06 by Codex:**
- No OpenClaw upgrade. Production remained `OpenClaw 2026.5.3-1`.
- Patched `~/Development/hungreo-xfeed/poll.mjs` with structured Telegram formatting and verified via temp-dir `--dry-run` (`posted=0`).
- Patched runtime dist:
  - `pi-embedded-CElEZtBc.js`: final non-empty assistant text only for auto reply payloads.
  - `openclaw-tools-D7Zj4hDN.js`: embedded runs can include the `message` tool.
- Restarted only `openclaw-gateway-hungreo.service`; gateway returned ready with `3 plugins`.
- UAT: `openclaw --profile hungreo agent --json ...` used `exec` once and returned exactly one payload, `FINAL_ONLY_OK`.

---

### [2026-05-04] lossless-claw 0.9.3 released — cosmetic warning FIXED, lcm tools unlock, runtime patch vẫn cần

**Loại:** release-news | upgrade-ready | plugin
**Source:** @jlehman_ tweet 2026-05-04
**Affects:** tất cả 3 profiles (hungreo, suckhoe, nemotron)

**Tóm tắt 0.9.3:**
- cache-aware compaction fires before overflow → ít repeated old instructions hơn
- **lcm tools load on OpenClaw 2026.5.2+** → FIX cosmetic warning `[plugins] plugin must declare contracts.tools`
- Codex, DeepSeek, Bedrock provider fixes
- safer migrations, payloads, and replay

**Implication cho VPS (openclaw 2026.5.2 + Codex runtime patch):**

| Issue | Status |
|-------|--------|
| Cosmetic warning `[plugins] plugin must declare contracts.tools` (4×/startup) | ✅ FIXED bởi 0.9.3 |
| `lcm_*` slash commands không register | ✅ FIXED bởi 0.9.3 |
| Runtime patch `channel-plugin-ids-*.js` (context-engine không activate) | ⚠️ **KHÔNG fix** bởi 0.9.3 — đây là bug openclaw, không phải lossless-claw. Patch vẫn cần. |

**🚨 BLOCKER — 0.9.3 có missing dependency (tested 2026-05-04):**

```
Error: Cannot find module '@mariozechner/pi-coding-agent'
```

0.9.3 requires `@mariozechner/pi-coding-agent@0.72.1` (có trên npm) nhưng **KHÔNG được auto-install** bởi `openclaw plugins install`. Upgrade lên 0.9.3 → lossless-claw không load → bots chỉ còn "2 plugins" → context engine broken.

**✅ RESOLVED 2026-05-04 19:51 +07 — upgrade lên openclaw 2026.5.3-1 + symlink approach.**

**Workaround hoạt động (đã verify cả 3 profiles):**
Packages `@mariozechner/{pi-coding-agent,pi-ai,pi-agent-core}` nằm sẵn trong `openclaw/node_modules/@mariozechner/` (bundled bởi openclaw). Không cần install riêng — chỉ cần symlink vào profile npm:
```bash
BASE=/home/hung/.npm-global/lib/node_modules/openclaw/node_modules/@mariozechner
for profile in hungreo suckhoe nemotron; do
  TARGET=~/.openclaw-$profile/npm/node_modules/@mariozechner
  for pkg in pi-agent-core pi-ai pi-coding-agent; do
    [ -e "$TARGET/$pkg" ] || ln -s "$BASE/$pkg" "$TARGET/$pkg"
  done
done
```

**Lần upgrade lossless-claw tiếp (0.9.4+): verify symlinks còn intact trước khi restart:**
```bash
ls ~/.openclaw-hungreo/npm/node_modules/@mariozechner/ | grep pi-
# Phải thấy: pi-agent-core, pi-ai, pi-coding-agent
```

**Khi nào runtime patch hết cần?**
Check openclaw npm version mới có fix chưa:
```bash
cd /tmp && npm pack openclaw@<NEW_VER>
tar xzf openclaw-*.tgz package/dist/channel-plugin-ids-*.js
grep -c "contextEngineSlotStartupPluginId\|slots\.contextEngine" package/dist/channel-plugin-ids-*.js
# > 0 = upstream đã fix → patch không còn cần thiết khi upgrade lên version đó
```

---

### [2026-05-03] CRITICAL — Active runtime patch trên VPS cho openclaw 2026.5.2 (Codex applied)

**Loại:** runtime-patch | upgrade-blocker | long-run-awareness
**Discovered & fixed by:** Codex (after Claude Code's workaround was insufficient)
**Affects:** **MỌI agent upgrade openclaw trong tương lai**

**TL;DR cho agents tương lai:**

VPS đang chạy openclaw 2026.5.2 với **runtime patch** modify file `dist/channel-plugin-ids-*.js`. Patch này KHÔNG có trong npm. Nếu bạn `npm install -g openclaw@<bất kỳ version>` → patch bị overwrite → `[context-engine] not registered` quay lại.

**Verify patch còn active TRƯỚC khi upgrade:**
```bash
grep -c "contextEngineSlotStartupPluginId" \
  /home/hung/.npm-global/lib/node_modules/openclaw/dist/channel-plugin-ids-*.js
# > 0 = patch active. ≤ 0 = pristine (chưa patch hoặc đã bị overwrite).
```

**Bug upstream (2026.5.2 pristine):**
- File: `dist/channel-plugin-ids-B_qWBF4F.js`
- Function startup-plugin-resolver chỉ check `plugin.startup.memory` (true cho `kind: "memory"`)
- KHÔNG check `slots.contextEngine === plugin.id` → context-engine plugins không được include vào startup
- Triệu chứng: gateway log "2 plugins: memory-core, telegram" (thiếu lossless-claw) → first request → "Context engine not registered"

**Patch của Codex (2 dòng mới):**
```javascript
// Line 337: resolve slot from config
const slot = configuredSlot || activationSourcePlugins.slots.contextEngine;
// Line 344: include plugin in startup if it matches the slot
if (params.contextEngineSlotStartupPluginId === params.plugin.pluginId) return true;
```

**Backup artifacts (KHÔNG XÓA):**
- `/home/hung/backups/openclaw-runtime-patch-20260503-154350/openclaw-global-package-pre-lcm-contextengine-20260503-154350.tgz` — full pre-patch state (98MB)
- `/tmp/openclaw-runtime-patch-20260503/openclaw-2026.5.2.tgz` — patched tarball (27MB), có thể `npm install -g <tarball>` để re-apply

**Re-apply patch sau khi upgrade làm mất nó:**
```bash
npm install -g /tmp/openclaw-runtime-patch-20260503/openclaw-2026.5.2.tgz \
  --prefix /home/hung/.npm-global --ignore-scripts
systemctl --user restart openclaw-gateway-{suckhoe,hungreo,nemotron}.service
# Verify: startup log có "3 plugins: lossless-claw, memory-core, telegram"
```

**Khi nào hết cần patch?**
Check pristine tarball của version mới:
```bash
cd /tmp && npm pack openclaw@<NEW_VER>
tar xzf openclaw-*.tgz package/dist/channel-plugin-ids-*.js
grep -c "contextEngineSlotStartupPluginId\|slots\.contextEngine" package/dist/channel-plugin-ids-*.js
# > 0 = upstream đã fix → patch không còn cần thiết
```

**Co-existing warning (cosmetic, không fix):**
```
[plugins] plugin must declare contracts.tools before registering agent tools
  (plugin=lossless-claw)
```
4 lần/service lúc startup. `lcm_*` slash commands chưa register. Core context engine vẫn work (LCM_VERIFY_OK). Đợi `lossless-claw 0.9.3+`.

---

### [2026-05-03] CROSS-AGENT COLLABORATION — Khi nào nhờ Codex (hoặc agent khác)

**Loại:** workflow | meta
**Discovered by:** Hưng (manual delegation to Codex sau Claude Code spent ~4h)

**Bài học:**

Claude Code session này spent ~4h investigation, tìm đúng file (`channel-plugin-ids-B_qWBF4F.js`) nhưng patch sai layer:
- ❌ Claude Code: patch DATA (`installs.json startup.memory: true`) → fragile, reset mỗi `plugins install`
- ✅ Codex: patch LOGIC (sửa runtime js) → durable, đúng nguồn cơn

**Khi nào delegate sang agent khác (Codex / GPT-5.5 / DeepSeek...):**

1. **Spent > 30 phút mà chưa root-cause** → dừng, summary state cho user, đề nghị delegate
2. **Đã tìm đúng file nhưng patch không work** → có thể đang patch sai layer (data vs logic, runtime vs config)
3. **Cần sửa minified/compiled code** → Codex tốt hơn ở reading + patching dist files
4. **User nói "tốn nhiều token"** → red flag rằng đang đi sai → dừng, không tự gồng tiếp

**Cách handoff context cho agent khác (Hưng làm với Codex):**

Hưng paste cho Codex:
- Triệu chứng cụ thể (error message)
- Những gì đã thử (Claude Code's workarounds)
- File suspect đã tìm ra
- Yêu cầu: "fix root cause, không workaround"

→ Codex apply patch trong < 30 phút.

**Long-run rule cho Claude Code:**

Nếu issue có dấu hiệu cần PATCH RUNTIME CODE (không phải config), explicit báo Hưng:
> "Vấn đề này ở runtime code level, mình có thể workaround bằng config patch (fragile) hoặc nhờ Codex patch runtime trực tiếp (durable). Bạn muốn approach nào?"

---

### [2026-05-03] INVESTIGATION EFFICIENCY — Plugin "not registered" error: check file existence FIRST, không dive vào source code

**Loại:** meta | investigation-process
**Discovered by:** Claude Code (post-mortem session này — mất ~4h và nhiều tokens)
**Affects:** MỌI agent debug plugin/config errors

**Bài học đắt giá từ session 2026-05-03:**

Session này tốn nhiều token/thời gian vì sai hướng điều tra. Root cause thật: **file npm bị xóa → installs.json trỏ path không tồn tại**. Chỉ mất 30 giây verify nếu check đúng thứ tự.

---

**✅ CHECKLIST DEBUG PLUGIN NOT LOADING (làm đúng thứ tự này):**

**Step 1 — 30 giây: Verify file existence** ← ĐÂY LÀ CÁI BỎ QUA GÂY RA WASTE
```bash
# Với bất kỳ plugin nào "not registered" / không load:
python3 -c "
import json, os
for p in ['hungreo','suckhoe','nemotron']:
    with open(f'/home/hung/.openclaw-{p}/plugins/installs.json') as f: d = json.load(f)
    for pl in d.get('plugins',[]):
        if pl.get('pluginId') == 'lossless-claw':
            src = pl.get('source','?')
            print(f'{p}: exists={os.path.exists(src)} path={src}')
"
# Nếu exists=False → DỪNG LẠI, root cause tìm thấy rồi → reinstall
```

**Step 2 — 2 phút: Xem đúng log**
```bash
# Xem temp log JSON (có metadata), KHÔNG chỉ dùng journalctl filter
grep "plugin_name\|context.engine\|not registered\|fallback" /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log
# Journalctl chỉ có stdout, temp log có structured data đầy đủ hơn
```

**Step 3 — Check installs.json trước, KHÔNG đọc dist/**
```bash
# installs.json đã có sẵn: source path, startup flags, origin, version
# ĐỌC installs.json trước (30s) thay vì grep openclaw dist (tốn 20+ phút)
cat ~/.openclaw-<profile>/plugins/installs.json | python3 -c "import json,sys; [print(json.dumps(p,indent=2)) for p in json.load(sys.stdin)['plugins'] if p['pluginId']=='lossless-claw']"
```

---

**❌ NHỮNG GÌ ĐÃ LÀMWASTE THỜI GIAN session 2026-05-03:**

| Hành động | Thời gian lãng phí | Lý do sai |
|-----------|-------------------|-----------|
| Grep openclaw dist/*.js cho plugin loading logic | ~45 min | File minified, complex. installs.json đã có answer |
| Đọc channel-plugin-ids, config-normalization source | ~30 min | Red herring — không liên quan root cause |
| Patch `startup.memory: false→true` nhiều lần | ~20 min | Không giải quyết vấn đề file missing |
| Thử sửa `plugins.slots`, `plugin.slot` in config | ~15 min | Wrong schema, auto-rejected |
| Đọc lossless-claw dist/index.js | ~20 min | Unnecessary — plugin không load vì file missing, không phải code bug |
| **Tổng** | ~130 min | Root cause tìm thấy lúc check `os.path.exists()` |

**Root cause thật chỉ mất 30 giây verify:**
```bash
ls ~/.openclaw-hungreo/npm/node_modules/@martian-engineering/lossless-claw/dist/index.js
# → "NOT FOUND" = tìm thấy rồi
```

---

**NGUYÊN TẮC DEBUG CHO AGENTS SAU NÀY:**

1. **"File exists?" TRƯỚC "Why doesn't it work?"** — 80% plugin errors = missing file/path  
2. **installs.json = source of truth cho 2026.5.x** — đọc đây trước khi đọc dist code  
3. **journalctl + temp log cùng lúc** — journalctl = stdout, temp log = full structured JSON  
4. **"Duplicate plugin id detected" = HARMLESS** — đừng "fix" bằng cách xóa files  
5. **Nếu không rõ sau 15 phút** → dừng, báo Hưng, đừng tự suy luận thêm từ minified code  
6. **Verify từng action** — trước khi làm bước tiếp: confirm step hiện tại đã work chưa  

---

### [2026-05-02] X (Twitter) public scraping 2026 broken — chọn actor reliable + cadence thấp thay vì hourly

**Loại:** integration | cost | research
**Discovered by:** Claude Code (deploy `hungreo-xfeed` service)
**Affects:** Mọi project muốn auto-fetch tweet từ X (không có X API paid)

**Bối cảnh**: Hưng muốn auto-forward tweet từ ~13 AI accounts về Telegram group `learning-research`. Yêu cầu Simple-Safe-Effective + free tier nếu được.

**Lesson 1 — RSS.app marketing misleading**:
- Page `rss.app/bots/twitter-telegram-bot` quảng cáo "checks every 15 minutes on all plans"
- Thực tế free tier (`rss.app/r/plans`): **2 feeds, 24h refresh, 5 posts/feed, không Filters, không Bundle Feeds**
- "15 min" là Telegram bot CHECK interval — nhưng FEED refresh vẫn 24h theo plan
- → Free tier KHÔNG dùng được cho 13 accounts. Đừng tin marketing page, vào `/r/plans` xem limit thật.

**Lesson 2 — Apify Twitter actors 2026 đa số broken hoặc flaky**:
Test 2026-05-02 với token user (cùng token user đang dùng cho YouTube Transcript Scraper):

| Actor | Pricing | Kết quả test |
| ----- | ------- | ------------ |
| `apidojo/tweet-scraper` (V2) | $0.40/1K tweets | ❌ Trả `[{"noResults": true}]` cho mọi handle (karpathy, elonmusk, OpenAI). Run SUCCEEDED nhưng 0 data → actor bị X block. |
| `apidojo/twitter-scraper-lite` | (rental) | ❌ Trả `{"demo": true}` — cần subscription, free user chỉ thấy demo data |
| `kaitoeasyapi/twitter-x-data-tweet-scraper-pay-per-result-cheapest` | $0.25/1K + min charge | ❌ Trả mock data CHARGED khi noResults — chính sách "minimum charge per call" → tốn tiền cho data rác |
| `scraper_one/x-profile-posts-scraper` | $0.40/1K + $0.0025 init | ⚠️ Lần đầu trả 3 tweets karpathy đúng (có timestamp, author...). Lần 2-5 trả `[]` empty. Flaky. |
| `dead00/twitter-profile-scraper-no-cookies` | $0.003/result × 1.2 margin = $0.0036 | ✅ **Reliable**, trả 1 profile object/handle với `latest_tweets[]` nested (5-10 tweets). Pricing PER PROFILE không per tweet → cheaper cho low-tweet-count use case. |

**Root cause chung**: X 2026 block aggressive anonymous scraping. Actors phải chuyển sang residential proxy + guest accounts → cost cao hoặc reliability thấp. Pricing trang Apify Store thường chỉ là "ideal case" — actual cost cao hơn vì retry + failure overhead.

**Lesson 3 — Free $5/tháng credit không đủ cho hourly cadence với 10+ accounts**:

Math reality:
- Mục tiêu user: 13 accounts × 5 tweets × poll mỗi 60 phút (24/ngày)
- Cheapest actor work ($0.0036/profile): 13 × 24 × 30 = 9,360 polls/tháng × $0.0036 = **$33.7/tháng**
- $5 free tier chỉ cover ~5 accounts × 2 polls/ngày → giảm scope nghiêm trọng

**Compromise đã apply (chốt sau 5 vòng tư vấn với user)**:
- 5 accounts thay vì 13: `steipete`, `sama`, `AnthropicAI`, `claudeai`, `openclaw`
- 3 tweets/account/poll thay vì 5
- 12h cadence (07:00 + 19:00 VNT) thay vì 60 phút
- Cost: 60 polls × 5 profiles × $0.0036 = **$1.08/tháng** ✅

**Prevention cho future agents**:

1. **Trước khi propose Apify cho X scraping**: warning user về reality 2026 + math chi tiết. Đừng commit free tier nếu math chưa fit.
2. **Verify actor reliability trước khi build**: chạy 3-5 test calls với 2-3 handles khác nhau, xem có flaky không. Đừng tin Apify Store rating/runs alone.
3. **Pricing audit**: check `pricingPerEvent.actorChargeEvents` chi tiết — vài actor có hidden init fee, minimum charge, hoặc charge cho "noResults".
4. **`noResults` ≠ free**: vài actor (kaitoeasyapi) trả mock data + charge anyway. Đừng giả định empty = $0.
5. **Apify token shared across actors**: 1 token = 1 account = $5 budget chia chung. Nếu user đã dùng cho project khác (vd YouTube Scraper) → còn lại ít hơn $5. **LUÔN check `usage/monthly` trước khi commit cadence**: `curl https://api.apify.com/v2/users/me/limits?token=...`
6. **Alternative khi user không muốn pay**: gợi ý newsletter pipe (TLDR AI, AlphaSignal) → email-to-Telegram, $0/tháng, reliable hơn raw X scrape.

**Service spec final đã deploy**: xem `kb/hungreo-xfeed-runbook.md` và `LOCAL_CONTEXT.md` section 2026-05-02.

**Files trên VPS** (deploy by Claude Code via SSH `hung@72.61.123.33`):
- `~/Development/hungreo-xfeed/poll.mjs` (Node ESM, native fetch, no npm deps)
- `~/Development/hungreo-xfeed/.env` (chmod 600 — secrets in here, NOT in git/runbook)
- `~/.config/systemd/user/hungreo-xfeed.{service,timer}` (oneshot + 07:00/19:00 VNT)

---

### [2026-05-03] lossless-claw "context engine not registered" sau upgrade 2026.5.2 — npm path bị xóa

**Loại:** upgrade | plugin | context-engine
**Discovered by:** Nemo bot (tự báo cáo trong lần chat đầu tiên sau upgrade)
**Affects:** tất cả 3 profiles (hungreo, suckhoe, nemotron)

**Triệu chứng:**
```
[context-engine] Context engine "lossless-claw" is not registered; falling back to default engine "legacy"
```

**Root cause:** Trong quá trình upgrade 2026.4.x → 2026.5.2, chúng ta đã chạy `plugins install --pin --force` để tạo npm/node_modules installs. Sau đó thấy "duplicate plugin id detected" (cả extensions/ lẫn npm/ đều load lossless-claw), đã **xóa npm/node_modules** để loại bỏ duplicate. NHƯNG `installs.json` (file mới trong 2026.5.x) đã được update để trỏ đến npm paths. Sau khi xóa npm dirs → `installs.json` trỏ đến file không tồn tại → 2026.5.2 không load được lossless-claw → "context engine not registered".

**Chain of events:**
1. `plugins install --pin --force` → tạo `npm/node_modules/lossless-claw` + update `installs.json` (source = npm path)
2. Thấy "duplicate plugin id" → xóa `npm/node_modules` để "clean"
3. `installs.json` vẫn trỏ npm path đã xóa → lossless-claw không load được
4. Error xuất hiện khi user gửi tin nhắn đầu tiên

**2026.5.x Plugin Changes (quan trọng):**
- `plugins/installs.json` là file MỚI trong 2026.5.x — track canonical source path cho mỗi plugin
- `startup.memory: false` cho `kind: "context-engine"` — BUG của 2026.5.2 (nên là `true` nhưng không map)  
- Duplicate plugin warning là **cosmetic/harmless** — npm wins over extensions, cả hai đều version 0.9.2
- **KHÔNG XÓA npm/node_modules** một khi `installs.json` đã trỏ vào đó

**Fix áp dụng:**
```bash
OPENCLAW_BIN="/home/hung/.npm-global/bin/openclaw"

# Reinstall lossless-claw cho profile bị thiếu npm path
OPENCLAW_STATE_DIR=~/.openclaw-hungreo $OPENCLAW_BIN plugins install @martian-engineering/lossless-claw@0.9.2 --pin --force
OPENCLAW_STATE_DIR=~/.openclaw-suckhoe $OPENCLAW_BIN plugins install @martian-engineering/lossless-claw@0.9.2 --pin --force

# Patch startup.memory (workaround bug 2026.5.2)
python3 -c "
import json
for p in ['hungreo','suckhoe','nemotron']:
    path = f'/home/hung/.openclaw-{p}/plugins/installs.json'
    with open(path) as f: d = json.load(f)
    for pl in d.get('plugins',[]):
        if pl.get('pluginId') == 'lossless-claw':
            pl['startup']['memory'] = True
    with open(path, 'w') as f: json.dump(d, f, indent=2)
"

# Restart tất cả 3 services
systemctl --user restart openclaw-gateway-suckhoe.service
systemctl --user restart openclaw-gateway-hungreo.service
systemctl --user restart openclaw-gateway-nemotron.service
```

**Verify fix:**
```bash
# Check source exists + startup.memory
for p in hungreo suckhoe nemotron; do
  python3 -c "
import json, os
with open('/home/hung/.openclaw-${p}/plugins/installs.json') as f: d = json.load(f)
for pl in d.get('plugins',[]):
    if pl.get('pluginId') == 'lossless-claw':
        print('${p}: exists=' + str(os.path.exists(pl['source'])) + ' memory=' + str(pl['startup']['memory']))
"
done
# Mong đợi: source_exists=True startup.memory=True cho cả 3

# Check no errors since restart
journalctl --user --since "15:00" --no-pager 2>/dev/null | grep -c "not registered\|fallback.*legacy"
# Mong đợi: 0
```

**Prevention cho future upgrades:**
1. `plugins install --pin --force` tạo npm/node_modules → `installs.json` trỏ vào đó → **ĐỪNG xóa npm dirs**
2. "Duplicate plugin id detected" là harmless — npm wins over extensions. Để yên.
3. Sau upgrade 2026.5.x: verify source_exists=True trong `installs.json` cho lossless-claw
4. `startup.memory: True` cần re-patch mỗi lần chạy lại `plugins install --pin --force`
5. Dùng đúng binary: `/home/hung/.npm-global/bin/openclaw` (không phải `openclaw` trong PATH = 2026.4.x)

**Extensions dirs còn tồn tại nhưng harmless:**
```
~/.openclaw-{profile}/extensions/lossless-claw/  ← old install, vẫn còn
~/.openclaw/extensions/lossless-claw/            ← shared global, vẫn còn
~/.openclaw-{profile}/npm/node_modules/lossless-claw/  ← NEW canonical source
```

---

### [2026-04-28] Nemo dùng main service file thay vì override.conf — update khác hungreo/suckhoe

**Loại:** upgrade | config
**Discovered by:** Claude Code
**Affects:** nemotron

**Root cause:**
Nemo không có `service.d/override.conf` — `OPENCLAW_SERVICE_VERSION` và `ExecStart` nằm thẳng trong `~/.config/systemd/user/openclaw-gateway-nemotron.service`. Nếu copy pattern hungreo/suckhoe (tạo override.conf) mà không biết điều này → có thể conflict hoặc confuse future agents.

**Triệu chứng:**
- Sau upgrade shared binary (2026.4.24 → 2026.4.26), Nemo vẫn báo VER=2026.4.24
- `cat ~/.config/systemd/user/openclaw-gateway-nemotron.service.d/override.conf` → "No such file or directory"
- `OPENCLAW_SERVICE_VERSION` nằm trong main service file, không phải override.conf

**Fix:**
```bash
# Backup
cp ~/.config/systemd/user/openclaw-gateway-nemotron.service \
   ~/.config/systemd/user/openclaw-gateway-nemotron.service.bak-YYYYMMDD-pre-VER

# Update trực tiếp trong main service file
sed -i "s/Description=OpenClaw Gateway (profile: nemotron, vOLD)/Description=OpenClaw Gateway (profile: nemotron, vNEW)/" \
  ~/.config/systemd/user/openclaw-gateway-nemotron.service
sed -i "s/Environment=OPENCLAW_SERVICE_VERSION=OLD/Environment=OPENCLAW_SERVICE_VERSION=NEW/" \
  ~/.config/systemd/user/openclaw-gateway-nemotron.service

systemctl --user daemon-reload
systemctl --user restart openclaw-gateway-nemotron.service

# Verify
PID=$(systemctl --user show openclaw-gateway-nemotron.service --property=MainPID --value)
strings /proc/$PID/environ | grep OPENCLAW_SERVICE_VERSION
```

**Prevention:**
- Khi upgrade Nemo: check `ls ~/.config/systemd/user/openclaw-gateway-nemotron.service.d/` trước
- Nếu không có `override.conf` → update trực tiếp main service file (không tạo override.conf mới)
- Pattern này KHÁC hungreo/suckhoe (dùng override.conf)

**Xem thêm:** `LOCAL_CONTEXT.md` section 2026-04-28

---

### [2026-04-27] OpenRouter shared pool rate-limit cho model mới launch → dùng provider trực tiếp

**Loại:** config | performance
**Discovered by:** Claude Code
**Affects:** nemotron

**Root cause:** DeepSeek V4 Pro/Flash launch ngày 23/04 → toàn bộ user OpenRouter đổ vào cùng lúc → shared pool 429 liên tục. OpenRouter BYOK (Bring Your Own Key) ở `workspaces/default/byok` không apply được vào API calls (khác với `/settings/integrations`). Giải pháp duy nhất là bypass OpenRouter, dùng provider API trực tiếp.

**Triệu chứng:**
- Mọi request tới `openrouter/deepseek/deepseek-v4-pro` đều 429
- Response chậm 35s (retry 4 lần rồi mới fallback)
- OpenRouter BYOK test OK trên UI nhưng không apply vào API calls thực tế
- Bot fallback 100% về Nemotron dù config đúng

**Fix:**
```bash
# 1. Thêm API key provider trực tiếp vào .env
echo 'DEEPSEEK_API_KEY=sk-...' >> ~/.openclaw-nemotron/.env

# 2. Config provider trong openclaw.json
jq '
  .models.mode = "merge" |
  .models.providers.deepseek = {
    "baseUrl": "https://api.deepseek.com/v1",
    "apiKey": "${DEEPSEEK_API_KEY}",
    "api": "openai-completions",
    "models": [{"id": "deepseek-v4-pro", "name": "DeepSeek V4 Pro",
      "reasoning": false, "input": ["text"], "contextWindow": 131072, "maxTokens": 8192}]
  } |
  .agents.defaults.model.primary = "deepseek/deepseek-v4-pro"
' openclaw.json > tmp.json && mv tmp.json openclaw.json
```

**Prevention / Check thường xuyên:**
- Khi model mới launch (< 7 ngày): OpenRouter shared pool LUÔN bị overload → không nên dùng ngay
- Nếu muốn dùng model mới gấp: dùng direct API (nếu provider có OpenAI-compatible endpoint)
- Pattern cấu hình provider trực tiếp: xem `nvidia.md` hoặc `synthetic.md` trong docs/providers

**Xem thêm:** `LOCAL_CONTEXT.md` section 2026-04-27

---

## Template cho entry mới

```
### [YYYY-MM-DD] <Tiêu đề ngắn>

**Loại:** upgrade | bug | config | security | performance
**Discovered by:** <agent name>
**Affects:** hungreo | suckhoe | nemotron | all

**Root cause:** <1-2 câu>

**Triệu chứng:**
- <symptom 1>
- <symptom 2>

**Fix:**
```bash
# lệnh cụ thể
```

**Prevention / Check thường xuyên:**
- <điều cần kiểm tra để tránh lặp lại>

**Xem thêm:** `kb/<file>.md` hoặc `LOCAL_CONTEXT.md`
```

---

## Entries

### 2026-04-23 — `openclaw update --no-restart` không thật sự dùng binary mới sau restart

**Loại:** upgrade  
**Discovered by:** Claude Code (sau khi user báo `/status` vẫn báo version cũ)  
**Affects:** hungreo, suckhoe

**Root cause:**  
`openclaw update --no-restart` cập nhật npm-global binary thành công, NHƯNG đồng thời tạo local fallback runtime tại `~/.openclaw-{profile}/runtime/openclaw-{OLD_VER}-fallback-note/` và ghi đè `service.d/override.conf` để ExecStart trỏ vào runtime local cũ đó — không phải npm-global mới.

**Triệu chứng:**
- `npm list -g openclaw` báo version mới ✓
- `~/.npm-global/bin/openclaw --version` báo version mới ✓
- NHƯNG `/status` trong Telegram vẫn báo version cũ
- `strings /proc/$PID/environ | grep OPENCLAW_SERVICE_VERSION` = `OLD_VER+fallback-note`
- `cat service.d/override.conf` → ExecStart trỏ vào `runtime/openclaw-OLD_VER-fallback-note/`

**Fix:**
```bash
NEW_VER="2026.4.21"   # thay đúng version

for profile in hungreo suckhoe; do
  OVERRIDE_DIR=~/.config/systemd/user/openclaw-gateway-${profile}.service.d
  PORT=$(grep "OPENCLAW_GATEWAY_PORT" ~/.config/systemd/user/openclaw-gateway-${profile}.service | grep -oP '\d{4,5}' | head -1)
  cp "${OVERRIDE_DIR}/override.conf" "${OVERRIDE_DIR}/override.conf.bak-$(date +%Y%m%d-%H%M)"
  cat > "${OVERRIDE_DIR}/override.conf" << EOF
[Unit]
Description=OpenClaw Gateway (profile: ${profile}, v${NEW_VER})

[Service]
ExecStart=
ExecStart=/usr/bin/node /home/hung/.npm-global/lib/node_modules/openclaw/dist/index.js gateway --port ${PORT}
Environment=OPENCLAW_SERVICE_VERSION=${NEW_VER}
EOF
done
systemctl --user daemon-reload
systemctl --user restart openclaw-gateway-suckhoe.service
systemctl --user restart openclaw-gateway-hungreo.service
```

**Verify:**
```bash
PID=$(systemctl --user show openclaw-gateway-hungreo.service --property=MainPID --value)
strings /proc/$PID/environ | grep OPENCLAW_SERVICE_VERSION
# Expected: OPENCLAW_SERVICE_VERSION=2026.4.21 (không có +fallback-note)
```

**Prevention:**  
Luôn kiểm tra `override.conf` sau `openclaw update`. Xem đầy đủ tại `kb/openclaw-upgrade-runbook.md` Bước 5.

---

### 2026-04-23 — Nemotron (Nemo) bị pin nhầm lossless-claw@0.9.1

**Loại:** upgrade  
**Discovered by:** Claude Code (monitor output lúc upgrade)  
**Affects:** nemotron

**Root cause:**  
Nemotron được cài lossless-claw@0.9.1 từ lần cài đầu tiên và bị pin cứng version đó trong config. Khi chạy `openclaw update`, lệnh này respect pin cũ → install 0.9.1 thay vì 0.9.2.

**Triệu chứng:**
- `openclaw update` log báo: `Downloading @martian-engineering/lossless-claw@0.9.1…`
- Trong khi hungreo/suckhoe đúng là `0.9.2`

**Fix:**
```bash
OPENCLAW_STATE_DIR=~/.openclaw-nemotron ~/.npm-global/bin/openclaw \
  --profile nemotron plugins install @martian-engineering/lossless-claw@0.9.2 --pin --force
```

**Prevention:**  
Sau mỗi `openclaw update`, verify plugin version của Nemo riêng:
```bash
OPENCLAW_STATE_DIR=~/.openclaw-nemotron ~/.npm-global/bin/openclaw --profile nemotron plugins list 2>/dev/null | grep lossless-claw
```

---

### 2026-04-23 — Nemo Telegram scope loop (operator.approvals)

**Loại:** config  
**Discovered by:** Claude Code (SSH log check)  
**Affects:** nemotron

**Root cause:**  
Telegram plugin của Nemo luôn cố đăng ký làm native approval handler, yêu cầu scope `operator.approvals`. Device paired với `operator.read` → loop vô tận mỗi 1s.

**Triệu chứng:**
- Log spam: `scope upgrade pending approval (requestId: ...)` mỗi 1 giây
- Bot không respond trên Telegram

**Fix:**
```bash
# Bước 1: đổi exec.ask về "off" trong openclaw.json của nemotron
# (dùng gateway tool hoặc jq để edit config)

# Bước 2: approve pending device scope upgrade qua CLI
OPENCLAW_STATE_DIR=~/.openclaw-nemotron ~/.npm-global/bin/openclaw devices approve --latest

# Bước 3: restart
systemctl --user restart openclaw-gateway-nemotron.service
```

**Prevention:**  
- Nemo nên có `exec.ask: "off"` — commands trong allowlist auto-run, ngoài allowlist bị deny (không hỏi approval)
- Kiểm tra `exec.ask` trong config trước khi deploy Nemo mới

---

### 2026-04-22 — OPENCLAW_SERVICE_VERSION env stale trong service file

**Loại:** upgrade  
**Discovered by:** Claude Code  
**Affects:** hungreo, suckhoe

**Root cause:**  
`OPENCLAW_SERVICE_VERSION` trong main service file bị ghi stale (2026.4.12) từ lần install đầu tiên, trong khi override.conf thực tế ghi version mới hơn. Sed trực tiếp vào main service file không có tác dụng vì override.conf takes precedence.

**Fix:** Update override.conf (không phải main service file). Xem lesson 2026-04-23 ở trên.

---

## Index theo topic

| Topic | Entries liên quan |
|---|---|
| lossless-claw 0.9.3 upgrade | 2026-05-04 (release notes, upgrade path, runtime patch vẫn cần) |
| Runtime patch (context-engine) | 2026-05-03 CRITICAL (Codex applied), 2026-05-03 (investigation efficiency) |
| Cross-agent delegation | 2026-05-03 (khi nào nhờ Codex) |
| override.conf sau upgrade | 2026-04-23 (binary cũ), 2026-04-22 (version stale) |
| Nemo service file pattern | 2026-04-28 (main file thay vì override.conf) |
| Plugin version | 2026-04-23 (Nemo lossless-claw 0.9.1) |
| Nemo scope loop | 2026-04-23 (operator.approvals) |
| X scraping 2026 reality | 2026-05-02 (Apify flaky, cost math, `hungreo-xfeed`) |
| Upgrade workflow | Xem `kb/openclaw-upgrade-runbook.md` |
