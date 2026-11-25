"""Replace every WAL database in the copy with a consistent online backup of the live file."""
from contextlib import closing
import os, sqlite3, sys
from pathlib import Path
live, copy = map(Path, sys.argv[1:3])
for wal in sorted(live.rglob("*-wal")):
    src = Path(str(wal)[:-4])
    if not src.is_file() or src.parent.name == "tmp":
        continue
    rel = src.relative_to(live)
    if rel.parts[0] in ("tmp", "cache"):
        continue
    dst = copy / rel
    tmp = dst.with_name(dst.name + ".dryrun-tmp")
    with closing(sqlite3.connect(src.resolve().as_uri() + "?mode=ro", uri=True, timeout=30)) as s, \
         closing(sqlite3.connect(tmp)) as d:
        s.backup(d)
        ok = d.execute("PRAGMA quick_check").fetchone()[0]
    for suffix in ("", "-wal", "-shm"):
        p = Path(str(dst) + suffix)
        if p.exists():
            p.unlink()
    os.replace(tmp, dst)
    print(f"snap {rel} quick_check={ok}")
