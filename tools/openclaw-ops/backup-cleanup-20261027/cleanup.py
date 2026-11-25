"""One-shot exact-path cleanup. Audit is default; no service/model/auth/cron edits."""
import argparse
import fcntl
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import socket
import stat
import subprocess
import time

HERE = Path(__file__).resolve().parent
SPEC = HERE / "targets.json"
ALLOWED = set(['/home/hung/backups/openclaw-hungreo-pre933-20261018-154744', '/home/hung/backups/openclaw-suckhoe-pre933-20261018-154622', '/home/hung/backups/post933-cleanup-hungreo-20261018-164201', '/home/hung/backups/post933-cleanup-suckhoe-20261018-163847'])
PENDING = ".cleanup-20261027-pending"


def run(args, **kwargs):
    return subprocess.check_output(args, text=True, timeout=kwargs.pop("timeout", 45), **kwargs).strip()


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()


def save(name, data):
    p = HERE / name
    fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())


def checked_directory(path):
    path = Path(path)
    for p in [*reversed(path.parents), path]:
        st = p.lstat()
        if not stat.S_ISDIR(st.st_mode) or stat.S_ISLNK(st.st_mode):
            raise ValueError("not a plain directory: " + str(p))
    if path.resolve() != path:
        raise ValueError("path resolution changed")
    return path


def fingerprint(path):
    checked_directory(path)
    root = path.stat()
    h = hashlib.sha256()
    allocated = 0
    for parent, dirs, files in os.walk(path, followlinks=False):
        dirs.sort()
        for name in sorted([*dirs, *files]):
            p = Path(parent) / name
            s = p.lstat()
            if s.st_dev != root.st_dev:
                raise ValueError("cross-device target member")
            if not (stat.S_ISDIR(s.st_mode) or stat.S_ISREG(s.st_mode) or stat.S_ISLNK(s.st_mode)):
                raise ValueError("special target member")
            record = [str(p.relative_to(path)), s.st_dev, s.st_ino, s.st_mode,
                      s.st_size, s.st_mtime_ns, s.st_nlink]
            if stat.S_ISLNK(s.st_mode):
                record.append(os.readlink(p))
            elif stat.S_ISREG(s.st_mode):
                record.append(sha(p))
            h.update(json.dumps(record).encode())
            allocated += s.st_blocks * 512
    return {"dev": root.st_dev, "ino": root.st_ino, "digest": h.hexdigest(),
            "allocated": allocated + root.st_blocks * 512}


def delete_pinned(path, expected, guard=None):
    if guard:
        guard(path)
    if fingerprint(path) != expected:
        raise ValueError("target identity/content changed")
    pending = path.name + PENDING
    parent_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        if os.path.lexists(path.parent / pending):
            raise ValueError("pending directory already exists")
        old = os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)
        if (old.st_dev, old.st_ino) != (expected["dev"], expected["ino"]):
            raise ValueError("target inode changed")
        os.rename(path.name, pending, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
        pinned_path = path.parent / pending
        if guard:
            guard(pinned_path)
        if fingerprint(pinned_path) != expected:
            raise ValueError("changed after rename; preserve pending for reconciliation")
        shutil.rmtree(pending, dir_fd=parent_fd)
        os.fsync(parent_fd)
    finally:
        os.close(parent_fd)


def spec():
    data = json.loads(SPEC.read_text())
    paths = data["paths"]
    if set(paths) != ALLOWED or len(paths) != len(ALLOWED):
        raise ValueError("manifest differs from compiled exact allowlist")
    for a in paths:
        for b in paths:
            if a != b and b.startswith(a + "/"):
                raise ValueError("overlapping cleanup targets")
    return data


def inspect():
    ids = run(["docker", "ps", "-aq"]).split()
    data = json.loads(run(["docker", "inspect", *ids])) if ids else []
    return {c["Name"].lstrip("/"): {"id": c["Id"], "running": c["State"]["Running"],
            "pid": c["State"]["Pid"], "restart": c["RestartCount"],
            "started": c["State"]["StartedAt"],
            "runtime": sorted(m["Source"] for m in c["Mounts"] if m["Destination"] == "/sandbox/runtime"),
            "mounts": sorted(m["Source"] for m in c["Mounts"])} for c in data}


def baseline():
    d = spec()
    out = {"units": {}, "config_hash": {}, "versions": {}, "containers": {}, "timers": {}}
    for p, u in [("hungreo", "openclaw-gateway-hungreo.service"),
                 ("suckhoe", "openclaw-gateway-suckhoe.service"), ("hermes", "hermes-gateway.service")]:
        row = dict(l.split("=", 1) for l in run(["systemctl", "--user", "show", u,
                   "-p", "MainPID", "-p", "ActiveState", "-p", "NRestarts"]).splitlines())
        if row["ActiveState"] != "active" or row["MainPID"] == "0":
            raise ValueError("service not active: " + u)
        out["units"][p] = row
    for p in ["hungreo", "suckhoe"]:
        out["config_hash"][p] = sha("/home/hung/.openclaw-" + p + "/openclaw.json")
    out["config_hash"]["nemo"] = sha("/home/hung/sandbox-nemo/config/openclaw.json")
    for p, f in d["runtime_packages"].items():
        v = json.loads(Path(f).read_text())["version"]
        if v != d["versions"][p]:
            raise ValueError("runtime drift: " + p)
        out["versions"][p] = v
    for port in [18789, 18795, 18796]:
        code = run(["curl", "-s", "--max-time", "5", "-o", "/dev/null", "-w", "%{http_code}",
                    "http://127.0.0.1:" + str(port) + "/readyz"])
        if code != "200":
            raise ValueError("readiness failed")
    containers = inspect()
    for n in d["protect_containers"]:
        if n not in containers:
            raise ValueError("protected container missing: " + n)
        out["containers"][n] = containers[n]
    if not containers["nemo-sandbox"]["running"] or containers["nemo-sandbox"]["runtime"] != [
            "/home/hung/sandbox-nemo/runtime-10.5"]:
        raise ValueError("Nemo runtime changed")
    for u in ["openclaw-backup.service", "openclaw-restore-check.service"]:
        if run(["systemctl", "--user", "show", u, "-p", "ActiveState", "--value"]) != "inactive":
            raise ValueError("backup/restore job active")
    for u in ["openclaw-backup.timer", "openclaw-restore-check.timer", "openclaw-healthcheck.timer"]:
        state = run(["systemctl", "--user", "show", u, "-p", "ActiveState", "--value"])
        if state != "active":
            raise ValueError("timer not active: " + u)
        out["timers"][u] = state
    return out


def verify_kept():
    result = {}
    data = spec()
    for name in data["keep_backup_sets"]:
        p = checked_directory(Path(name))
        sums = p / "SHA256SUMS"
        if not sums.is_file() or sums.is_symlink():
            raise ValueError("kept backup lacks checksum manifest: " + name)
        count = 0
        verified = set()
        required = set(data["required_backup_members"][name])
        if not required:
            raise ValueError("empty required artifact list")
        for line in sums.read_text().splitlines():
            if not line.strip():
                continue
            digest, member = line.split(maxsplit=1)
            q = (p / member.lstrip("*")).resolve()
            if not q.is_relative_to(p) or not q.is_file() or not re.fullmatch(r"[0-9a-fA-F]{64}", digest):
                raise ValueError("invalid kept manifest member")
            if sha(q) != digest:
                raise ValueError("kept backup checksum mismatch: " + name)
            count += 1
            verified.add(q.relative_to(p).as_posix())
        if count == 0:
            raise ValueError("empty kept checksum manifest")
        if not required.issubset(verified):
            raise ValueError("required backup artifact lacks verified checksum: " + name)
        if "/openclaw/hungreo/" in name or "/openclaw/suckhoe/" in name:
            if not all((p / n).is_file() for n in ["state.tgz", "sqlite.tgz", "RESTORE-NOTE.txt"]):
                raise ValueError("incomplete daily split set")
        result[name] = {"count": count, "manifest_sha256": sha(sums),
                        "required_verified": sorted(required)}
    return result


def no_mounts(extra=()):
    targets = spec()["paths"] + [str(p) for p in extra]
    for c in inspect().values():
        for source in c["mounts"]:
            if any(source == t or source.startswith(t + "/") or t.startswith(source.rstrip("/") + "/")
                   for t in targets):
                raise ValueError("cleanup target still covered by Docker bind")
    for l in Path("/proc/self/mountinfo").read_text().splitlines():
        fields = l.split()
        mount = re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), fields[4])
        source_root = re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), fields[3])
        if any(mount == t or mount.startswith(t + "/")
               or source_root == t or source_root.startswith(t + "/") for t in targets):
            raise ValueError("target contains host mount or is a bind source")


def root_references():
    raw = run(["docker", "run", "--rm", "--pull", "never", "--network", "none", "--pid", "host",
               "--read-only", "--cap-drop", "ALL", "--cap-add", "SYS_PTRACE",
               "--cap-add", "DAC_READ_SEARCH", "--security-opt", "apparmor=unconfined",
               "--security-opt", "no-new-privileges", "--user", "0:0",
               "--memory", "64m", "--memory-swap", "64m", "--cpus", "0.2", "--pids-limit", "16",
               "--mount", "type=bind,src=" + str(HERE / "root_refs.js") + ",dst=/audit.js,readonly",
               "--mount", "type=bind,src=" + str(SPEC) + ",dst=/targets.json,readonly",
               "sha256:0e0ff40c39bc087845bfb27465a0df4ea419520094bc35842ff83dd8cbe6f9b6", "node", "--max-old-space-size=16", "/audit.js"], timeout=40)
    value = json.loads(raw)
    if (value["matches"] or value["mountMatches"] or value["permissionDenials"]
            or time.time() - value["epoch"] > 60):
        raise ValueError("root process reference check incomplete or positive")
    return value


def assert_no_script_refs():
    # Read scripts and units only; never export config, credentials or DB values.
    paths = list(Path("/home/hung/bin").glob("*.sh"))
    units = Path("/home/hung/.config/systemd/user")
    paths += list(units.glob("*.service")) + list(units.glob("*.service.d/*.conf"))
    for p in paths:
        if p.is_file():
            text = p.read_text(errors="replace")
            if any(t in text for t in spec()["paths"]):
                raise ValueError("active script/unit references cleanup target: " + str(p))


def disk():
    return int(run(["df", "-B1", "--output=used", "/"]).splitlines()[-1])


def audit():
    before = baseline()
    kept = verify_kept()
    no_mounts()
    root_check = root_references()
    current = inspect()
    for n in spec()["remove_stopped_containers"]:
        if n not in current or current[n]["running"]:
            raise ValueError("removal container not stopped")
    pins = {p: fingerprint(Path(p)) for p in spec()["paths"]}
    assert_no_script_refs()
    result = {"baseline": before, "keep_checksums": kept, "pins": pins,
              "df_used_before": disk(), "remove_containers": {
                  n: current[n]["id"] for n in spec()["remove_stopped_containers"]},
              "created": time.time(), "spec_sha256": sha(SPEC),
              "root_reference_check": root_check, "engine_sha256": sha(Path(__file__)),
              "helper_sha256": sha(HERE / "root_refs.js")}
    save("audit.json", result)
    print(json.dumps({"audit": "PASS", "targets": len(pins),
                      "allocated_GB": sum(v["allocated"] for v in pins.values()) / 1e9,
                      "kept_archive_checksums": sum(v["count"] for v in kept.values()),
                      "kept_sets": len(kept), "root_reference_check": root_check}), flush=True)


def execute():
    d = json.loads((HERE / "audit.json").read_text())
    if set(d["pins"]) != ALLOWED:
        raise ValueError("audit pins differ from compiled exact allowlist")
    if (time.time() - d["created"] > 900 or sha(SPEC) != d["spec_sha256"]
            or sha(Path(__file__)) != d["engine_sha256"]
            or sha(HERE / "root_refs.js") != d["helper_sha256"]):
        raise ValueError("audit stale or spec changed")
    if baseline() != d["baseline"] or verify_kept() != d["keep_checksums"]:
        raise ValueError("protected state drift")
    assert_no_script_refs()
    for p, expected in d["pins"].items():
        if fingerprint(Path(p)) != expected:
            raise ValueError("target drift before execution")
    root_references()
    # No force removal: Docker itself refuses removal if one was started meanwhile.
    for n, ident in d["remove_containers"].items():
        c = inspect().get(n)
        if not c or c["id"] != ident or c["running"]:
            raise ValueError("stopped container drift")
        run(["docker", "rm", ident])
    no_mounts()
    deleted = []
    save("progress.json", {"deleted": deleted})
    for p, expected in d["pins"].items():
        if baseline() != d["baseline"]:
            raise ValueError("protected state drift during cleanup")
        root_references()
        def guard(renamed):
            no_mounts([renamed])
            root_references()
        delete_pinned(Path(p), expected, guard=guard)
        deleted.append(p)
        save("progress.json", {"deleted": deleted})
    verify()


def require_complete_deletion(data, progress):
    if set(data["pins"]) != ALLOWED or progress.get("deleted") != list(data["pins"]):
        raise ValueError("deletion progress incomplete or scope changed")
    for name in data["pins"]:
        if os.path.lexists(name) or os.path.lexists(name + PENDING):
            raise ValueError("original or pending cleanup target remains")


def verify():
    d = json.loads((HERE / "audit.json").read_text())
    require_complete_deletion(d, json.loads((HERE / "progress.json").read_text()))
    if baseline() != d["baseline"]:
        raise ValueError("protected state changed")
    if verify_kept() != d["keep_checksums"]:
        raise ValueError("retained archive verification changed")
    if any(os.path.lexists(p) for p in spec()["paths"]):
        raise ValueError("cleanup targets remain")
    if any(n in inspect() for n in spec()["remove_stopped_containers"]):
        raise ValueError("cleanup containers remain")
    after = disk()
    result = {"status": "VERIFIED", "target_count": len(d["pins"]),
              "df_used_before": d["df_used_before"], "df_used_after": after,
              "df_reclaimed_bytes": d["df_used_before"] - after,
              "allocated_target_bytes": sum(x["allocated"] for x in d["pins"].values()),
              "versions": d["baseline"]["versions"], "services_unchanged": True,
              "protected_containers_unchanged": True, "kept_checksum_sets": len(d["keep_checksums"]),
              "root_check": "zero matches and zero permission denials before each deletion",
              "time": time.time()}
    save("result.json", result)
    print(json.dumps(result), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["audit", "execute", "verify"], nargs="?", default="audit")
    parser.add_argument("--approved-spec-sha256", default="")
    args = parser.parse_args()
    if args.mode == "execute" and args.approved_spec_sha256 != sha(SPEC):
        raise ValueError("execute requires separately approved exact spec SHA256")
    if socket.gethostname() != "srv1367812":
        raise ValueError("wrong host")
    if not shutil.rmtree.avoids_symlink_attacks:
        raise ValueError("symlink-resistant rmtree unavailable")
    spec()
    with (HERE / "cleanup.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        globals()[args.mode]()


if __name__ == "__main__":
    main()

