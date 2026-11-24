from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import sys
import time

# OC_CHECK_PROFILE lets the offline dry-run point the checks at a copy.
PROFILE = Path(os.environ.get("OC_CHECK_PROFILE", "/home/hung/.openclaw-hungreo"))
OLD_MODEL = "openai/gpt-6.1-sol"
NEW_MODEL = "openai/gpt-6.2-sol"
DATABASES = ("state/openclaw.sqlite", "agents/main/agent/openclaw-agent.sqlite", "lcm.db")
# 11.7 Doctor changes verified in the 23/11 dry-run (README "Offline Doctor dry-run").
# wizard.* is run metadata; nano-banana-pro is a retired bundled skill whose entry Doctor always deletes.
EXPECTED_CHANGED_PATHS = {"wizard.lastRunAt", "wizard.lastRunVersion"}
RETIRED_SKILL = "nano-banana-pro"
RETIRED_SKILL_ARCHIVE = "workspace/.retired-skills-117"
# The weekly Skill Workshop curator is deleted by 11.7 on every cron store load (Hưng: drop it, 24/11).
RETIRED_JOB_DECLARATION_PREFIX = "skill-collection-review:"


def read_json(path):
    return json.loads(Path(path).read_text())


def connection(path):
    return sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True, timeout=4)


def require(condition, label):
    if not condition:
        raise RuntimeError(label)


def idle():
    with closing(connection(PROFILE / DATABASES[0])) as db:
        require(not db.execute(
            "SELECT 1 FROM task_runs WHERE status IN ('running','pending','queued','starting') LIMIT 1"
        ).fetchone(), "active task")
        require(not db.execute(
            "SELECT 1 FROM operator_approvals WHERE status='pending' LIMIT 1"
        ).fetchone(), "pending approval")
        jobs = [json.loads(row[0]) for row in db.execute("SELECT state_json FROM cron_jobs WHERE enabled=1")]
        require(not any(job.get("runningAtMs") for job in jobs), "cron running")
        now = time.time() * 1000
        require(not any(0 < (job.get("nextRunAtMs") or 0) < now + 20 * 60 * 1000 for job in jobs),
                "cron due in the next 20 minutes")
    print("idle=yes cron_window=20m")


def databases(profile):
    for name in DATABASES:
        with closing(connection(profile / name)) as db:
            require(db.execute("PRAGMA quick_check").fetchall() == [("ok",)], f"quick_check failed: {name}")
            print(f"quick_check=ok {name} schema={db.execute('PRAGMA user_version').fetchone()[0]}")


def protected_system_helper(process):
    command = (process / "comm").read_text().strip()
    scope = (process / "cgroup").read_text().rstrip().rsplit("/", 1)[-1]
    if command in ("systemd", "(sd-pam)") and scope == "init.scope":
        return
    if command == "gpg-agent" and scope == "gpg-agent.service":
        return
    if command == "sshd" and scope.startswith("session-") and scope.endswith(".scope"):
        return
    raise RuntimeError(f"Uninspectable process {process.name} ({command})")


def writers(require_idle=True):
    trouble = []
    for process in Path("/proc").glob("[0-9]*"):
        try:
            if process.stat().st_uid != os.getuid() or int(process.name) in (os.getpid(), os.getppid()):
                continue
            for fd in (process / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                    if target.startswith(str(PROFILE) + "/"):
                        info = (process / "fdinfo" / fd.name).read_text()
                        flags = next(line.split()[1] for line in info.splitlines() if line.startswith("flags:"))
                        if int(flags, 8) & os.O_ACCMODE:
                            trouble.append(int(process.name))
                except (FileNotFoundError, ProcessLookupError):
                    continue
        except PermissionError:
            try:
                protected_system_helper(process)
            except FileNotFoundError:
                continue
        except (FileNotFoundError, ProcessLookupError):
            continue
    if require_idle:
        require(not trouble, f"profile still has writable file handles, PIDs={sorted(set(trouble))}")
        print("profile_writers=0")
    else:
        print(f"profile_writer_scan_access=ok process_count={len(set(trouble))}")


def batch(original, target):
    defaults = original["agents"]["defaults"]
    require(defaults["model"]["primary"] == OLD_MODEL, "Unexpected model baseline")
    require(NEW_MODEL not in defaults["models"], "6.2 model already configured")
    old = defaults["models"][OLD_MODEL]
    require(old == {"agentRuntime": {"id": "codex"}}, "Unexpected old model registry entry")
    allowed = defaults["modelPolicy"]["allow"]
    require(isinstance(allowed, list) and OLD_MODEL in allowed and NEW_MODEL not in allowed,
            "Unexpected model policy")
    target.write_text(json.dumps([
        {"path": "agents.defaults.models[\"openai/gpt-6.2-sol\"]", "value": old},
        {"path": "agents.defaults.modelPolicy.allow", "value": [*allowed, NEW_MODEL]},
        {"path": "agents.defaults.model.primary", "value": NEW_MODEL},
    ]))


def expected_config(original, model_is_updated):
    original.pop("meta", None)
    if model_is_updated:
        defaults = original["agents"]["defaults"]
        defaults["models"][NEW_MODEL] = defaults["models"][OLD_MODEL]
        defaults["modelPolicy"]["allow"].append(NEW_MODEL)
        defaults["model"]["primary"] = NEW_MODEL
    return original


def diff_paths(left, right, path=""):
    if isinstance(left, dict) and isinstance(right, dict):
        for key in sorted(left.keys() | right.keys()):
            field = f"{path}.{key}" if path else key
            if key not in left or key not in right:
                yield field
            else:
                yield from diff_paths(left[key], right[key], field)
    elif left != right:
        yield path


def config_check(old_config, updated):
    expected = expected_config(read_json(old_config), updated)
    actual = read_json(PROFILE / "openclaw.json")
    actual.pop("meta", None)
    changed = [p for p in diff_paths(expected, actual) if p not in EXPECTED_CHANGED_PATHS]
    retired_entry = f"skills.entries.{RETIRED_SKILL}"
    if retired_entry in changed:
        require(expected["skills"]["entries"][RETIRED_SKILL] == {"enabled": False}, "Retired skill entry was not a plain disable")
        require(not (PROFILE / "workspace/skills" / RETIRED_SKILL).exists(), "Retired skill is still installed and would become enabled")
        require((PROFILE / RETIRED_SKILL_ARCHIVE / RETIRED_SKILL / "SKILL.md").is_file(), "Retired skill archive is missing")
        changed.remove(retired_entry)
    require(not changed, "Unexpected changed config fields: " + ", ".join(changed))
    print(f"config_preserved=yes sol62_primary={updated}")


def jobs(profile):
    with closing(connection(profile / DATABASES[0])) as db:
        rows = db.execute("SELECT job_id, payload_kind, job_json, declaration_key FROM cron_jobs").fetchall()
    require(len({row[0] for row in rows}) == len(rows), "Ambiguous cron job partition")
    return {job_id: (kind, {**json.loads(raw), "_declarationKey": decl or json.loads(raw).get("declarationKey")})
            for job_id, kind, raw, decl in rows}


def heartbeat_scratch(profile, heartbeat_id):
    with closing(connection(profile / DATABASES[0])) as db:
        row = db.execute("SELECT content FROM cron_job_scratch WHERE job_id = ?", (heartbeat_id,)).fetchone()
    return row[0] if row else None


def heartbeat_next_run(profile, heartbeat_id):
    with closing(connection(profile / DATABASES[0])) as db:
        row = db.execute("SELECT state_json FROM cron_jobs WHERE job_id = ?", (heartbeat_id,)).fetchone()
    return json.loads(row[0]).get("nextRunAtMs")


def check_heartbeat(source, result, verify_next_run=False):
    old_profile = Path(source)
    config = read_json(old_profile / "openclaw.json")
    legacy = config["agents"]["defaults"]["heartbeat"]
    original = jobs(old_profile)
    migrated = jobs(Path(result))
    ids = [job_id for job_id, (kind, _) in original.items() if kind == "heartbeat"]
    require(len(ids) == 1, "Expected exactly one legacy heartbeat")
    heartbeat_id = ids[0]
    retired = {job_id for job_id, (_, job) in original.items()
               if (job.get("_declarationKey") or "").startswith(RETIRED_JOB_DECLARATION_PREFIX)}
    require(retired <= original.keys() - migrated.keys(), "A retired curator job survived migration")
    require(original.keys() - retired == migrated.keys(), "Automation identities or count changed")
    original = {k: v for k, v in original.items() if k not in retired}
    for job_id, (kind, before) in original.items():
        after_kind, after = migrated[job_id]
        if job_id == heartbeat_id:
            continue
        require(kind == after_kind, "An unrelated automation changed payload kind")
        for field in ("name", "schedule", "enabled", "agentId", "sessionTarget", "payload", "delivery", "activeHours", "idleOnly"):
            require(before.get(field) == after.get(field), f"An unrelated automation changed {field}")

    old_job = original[heartbeat_id][1]
    kind, new_job = migrated[heartbeat_id]
    payload = new_job.get("payload", {})
    delivery = new_job.get("delivery", {})
    require(kind == payload.get("kind") == "agentTurn", "Heartbeat did not become an agent-turn automation")
    require(new_job.get("schedule") == old_job["schedule"], "Heartbeat schedule or anchor changed")
    require(new_job.get("enabled") == old_job["enabled"], "Heartbeat enabled state changed")
    require(new_job.get("activeHours") == legacy.get("activeHours"), "Heartbeat active hours changed")
    require(new_job.get("sessionTarget") == "isolated" and new_job.get("idleOnly") is True, "Heartbeat is not isolated/idle-only")
    require(payload.get("model") == "openai/gpt-5.6-luna" and payload.get("lightContext") is True,
            "Heartbeat model or context setting changed")
    require(payload.get("skipIfScratchEmpty") is True, "Missing empty-checklist guard")
    require(delivery.get("mode") == "none" or delivery.get("target") == "owner", "Heartbeat gained a non-owner delivery route")
    scratch = heartbeat_scratch(Path(result), heartbeat_id)
    prior_scratch = heartbeat_scratch(old_profile, heartbeat_id)
    if prior_scratch is None:
        prior_scratch = (old_profile / "workspace" / "HEARTBEAT.md").read_text()
    # 9.36 already runs the heartbeat from DB scratch (3,674 chars on 24/11), not HEARTBEAT.md; Doctor keeps it.
    require(scratch and 0 < len(scratch) <= 16384, "Heartbeat checklist did not migrate or was larger than expected")
    require(scratch.strip() == prior_scratch.strip(), "Heartbeat checklist content changed")
    if verify_next_run:
        old_due = heartbeat_next_run(old_profile, heartbeat_id)
        require(old_due and old_due > time.time() * 1000, "The original heartbeat occurrence is already due")
        require(heartbeat_next_run(Path(result), heartbeat_id) == old_due, "The next heartbeat occurrence changed")
    print("heartbeat_migrated=1 every=2h session=isolated model=gpt-5.6-luna")
    print(f"heartbeat_checklist_size={len(scratch)} delivery_mode={delivery.get('mode')} unrelated_automations_preserved={len(original)-1} retired_curator_jobs={len(retired)}")


def approved_run(result, model="gpt-6.2-sol", marker="RUA_SOL62_OK"):
    raw = result.read_text()
    start = raw.find("{")
    require(start >= 0, "No JSON model receipt")
    root, _ = json.JSONDecoder().raw_decode(raw[start:])
    require(root.get("status") in ("ok", "completed"), "Model receipt reports an unsuccessful turn")
    payload = root.get("result", root)
    meta = payload.get("meta", {})
    agent_meta = meta.get("agentMeta", {})
    require(agent_meta.get("model") == model and agent_meta.get("provider") == "openai",
            "Unexpected model or provider in actual gateway turn")
    trace = meta.get("executionTrace", {})
    require(not agent_meta.get("fallbackAttempts") and not trace.get("fallbackUsed"),
            "Model fallback detected")
    if trace.get("winnerModel"):
        require(trace["winnerModel"] == model, "Unexpected execution trace winner")
    require(meta.get("requestShaping", {}).get("authMode") not in ("api-key", "api_key"),
            "API key auth detected on the actual gateway turn")
    require([p.get("text", "").strip() for p in payload.get("payloads", [])] == [marker],
            "Unexpected reply in model test")
    print(f"model_receipt=ok provider=openai model={model} marker={marker}")


actions = {
    "idle": idle,
    "writers": writers,
    "writer-scan-access": lambda: writers(require_idle=False),
    "db": lambda: databases(Path(sys.argv[2])),
    "batch": lambda: batch(read_json(sys.argv[2]), Path(sys.argv[3])),
    "config": lambda: config_check(sys.argv[2], sys.argv[3] == "updated"),
    "heartbeat": lambda: check_heartbeat(sys.argv[2], sys.argv[3], "verify-next-run" in sys.argv[4:]),
    "receipt": lambda: approved_run(Path(sys.argv[2]), *sys.argv[3:5]),
}
if __name__ == "__main__":
    actions[sys.argv[1]]()
