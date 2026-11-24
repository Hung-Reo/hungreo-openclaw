"""Must-keep snapshot and post-Doctor comparison for the Hungreo 11.7 dry-run.

snapshot <profile> <out.json>          : write the must-keep list from a 9.36 profile
compare  <before_dir> <after_profile> <runtime_skills_dir> : diff a migrated copy against it
Read-only on every path it is given.
"""
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys

RETIRED_DECLARATION_PREFIX = "skill-collection-review:"  # retired upstream, docs/automation/cron-jobs/payloads.md
JOB_FIELDS = ("name", "enabled", "agentId", "schedule", "sessionTarget", "delivery",
              "activeHours", "idleOnly", "wakeMode", "scheduledToolPolicy")
EXPECTED_CONFIG_PATHS = {"agents.defaults.heartbeat", "wizard.lastRunAt", "wizard.lastRunVersion"}


def ro(path):
    return sqlite3.connect(Path(path).resolve().as_uri() + "?mode=ro", uri=True, timeout=5)


def jobs(db_path):
    with closing(ro(db_path)) as db:
        rows = db.execute("SELECT job_id, payload_kind, declaration_key, job_json, state_json FROM cron_jobs").fetchall()
    out = {}
    for job_id, kind, decl, raw, state in rows:
        job = json.loads(raw)
        payload = dict(job.get("payload") or {})
        message = payload.pop("message", None)
        out[job_id] = {
            "kind": kind,
            "declarationKey": decl or job.get("declarationKey"),
            **{f: job.get(f) for f in JOB_FIELDS},
            "payload": payload,
            "messageSha256": hashlib.sha256(message.encode()).hexdigest() if message else None,
            "nextRunAtMs": json.loads(state or "{}").get("nextRunAtMs"),
        }
    return out


def disabled_skills(config):
    return sorted(k for k, v in (config.get("skills", {}).get("entries") or {}).items()
                  if isinstance(v, dict) and v.get("enabled") is False)


def snapshot(profile, out):
    profile = Path(profile)
    config = json.loads((profile / "openclaw.json").read_text())
    d = config["agents"]["defaults"]
    data = {
        "jobs": jobs(profile / "state/openclaw.sqlite"),
        "disabledSkills": disabled_skills(config),
        "heartbeat": d.get("heartbeat"),
        "model": d.get("model"),
        "modelPolicyAllow": d.get("modelPolicy", {}).get("allow"),
        "mediaModels": d.get("mediaModels"),
        "pluginsAllow": config.get("plugins", {}).get("allow"),
        "pluginsEnabled": {k: v.get("enabled") for k, v in (config.get("plugins", {}).get("entries") or {}).items()},
    }
    Path(out).write_text(json.dumps(data, ensure_ascii=False, indent=1, sort_keys=True))
    enabled = sum(1 for j in data["jobs"].values() if j["enabled"])
    print(f"must_keep jobs={len(data['jobs'])} enabled={enabled} disabled_skills={len(data['disabledSkills'])}")


def diff_paths(a, b, path=""):
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(a.keys() | b.keys()):
            p = f"{path}.{k}" if path else k
            if k not in a or k not in b:
                yield p
            else:
                yield from diff_paths(a[k], b[k], p)
    elif a != b:
        yield path


def skill_present(name, roots):
    return any((root / name / "SKILL.md").exists() for root in roots)


def compare(before_dir, after_profile, runtime_skills):
    before_dir, after = Path(before_dir), Path(after_profile)
    must = json.loads((before_dir / "must-keep.json").read_text())
    old_cfg = json.loads((before_dir / "openclaw.json").read_text())
    new_cfg = json.loads((after / "openclaw.json").read_text())
    problems, notes = [], []

    # Config: every changed path must be on the expected list.
    old_cfg.pop("meta", None); new_cfg.pop("meta", None)
    roots = [after / "workspace/skills", after / "skills", Path(runtime_skills)]
    for p in diff_paths(old_cfg, new_cfg):
        if p in EXPECTED_CONFIG_PATHS:
            notes.append(f"config expected: {p}")
        elif p.startswith("skills.entries.") and p.count(".") == 2:
            name = p.split(".")[2]
            if name in must["disabledSkills"] and not skill_present(name, roots):
                notes.append(f"config expected: {p} removed, skill no longer installed anywhere")
            else:
                problems.append(f"config: {p} changed and skill '{name}' is still installed")
        else:
            problems.append(f"config unexpected: {p}")

    # Disabled skills stay disabled or are gone from every root.
    new_disabled = set(disabled_skills(new_cfg))
    for name in must["disabledSkills"]:
        if name not in new_disabled and skill_present(name, roots):
            problems.append(f"skill '{name}' was disabled and is now enabled")

    # Model and plugin settings must not move.
    d = new_cfg["agents"]["defaults"]
    for key, now in (("model", d.get("model")), ("modelPolicyAllow", d.get("modelPolicy", {}).get("allow")),
                     ("mediaModels", d.get("mediaModels")), ("pluginsAllow", new_cfg.get("plugins", {}).get("allow"))):
        if must[key] != now:
            problems.append(f"{key} changed")

    # Jobs.
    old_jobs, new_jobs = must["jobs"], jobs(after / "state/openclaw.sqlite")
    hb = [k for k, j in old_jobs.items() if j["kind"] == "heartbeat"]
    if len(hb) != 1:
        problems.append(f"expected 1 legacy heartbeat job, found {len(hb)}")
    for job_id, before in old_jobs.items():
        after_job = new_jobs.get(job_id)
        if after_job is None:
            if (before["declarationKey"] or "").startswith(RETIRED_DECLARATION_PREFIX):
                notes.append(f"job retired upstream: {before['name']} ({job_id}) next={before['nextRunAtMs']}")
            else:
                problems.append(f"job missing: {before['name']} ({job_id}) enabled={before['enabled']}")
            continue
        if job_id in hb:
            continue
        for f in ("kind", "messageSha256", "payload", "nextRunAtMs") + JOB_FIELDS:
            if before.get(f) != after_job.get(f):
                problems.append(f"job {before['name']} changed {f}")
    for job_id in new_jobs.keys() - old_jobs.keys():
        problems.append(f"new job appeared: {new_jobs[job_id]['name']} ({job_id})")

    if hb and hb[0] in new_jobs:
        old, new = old_jobs[hb[0]], new_jobs[hb[0]]
        legacy = must["heartbeat"] or {}
        checks = {
            "agentTurn": new["kind"] == "agentTurn" == new["payload"].get("kind"),
            "schedule": new["schedule"] == old["schedule"],
            "enabled": new["enabled"] == old["enabled"],
            "activeHours": new["activeHours"] == legacy.get("activeHours"),
            "isolated+idleOnly": new["sessionTarget"] == "isolated" and new["idleOnly"] is True,
            "luna+lightContext": new["payload"].get("model") == legacy.get("model") and new["payload"].get("lightContext") is True,
            "skipIfScratchEmpty": new["payload"].get("skipIfScratchEmpty") is True,
            "owner-or-none delivery": (new["delivery"] or {}).get("mode") == "none" or (new["delivery"] or {}).get("target") == "owner",
            "nextRunAtMs": new["nextRunAtMs"] == old["nextRunAtMs"],
        }
        for k, ok in checks.items():
            (notes if ok else problems).append(f"heartbeat {k}: {'ok' if ok else 'FAIL'}")
    elif hb:
        problems.append("heartbeat job missing after migration")

    print(f"jobs before={len(old_jobs)} after={len(new_jobs)}")
    for n in notes:
        print("OK   ", n)
    for p in problems:
        print("FAIL ", p)
    print("RESULT", "PASS" if not problems else f"FAIL ({len(problems)})")
    return 0 if not problems else 1


if __name__ == "__main__":
    if sys.argv[1] == "snapshot":
        snapshot(*sys.argv[2:4])
    else:
        sys.exit(compare(*sys.argv[2:5]))
