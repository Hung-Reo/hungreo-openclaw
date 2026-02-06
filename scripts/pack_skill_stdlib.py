#!/usr/bin/env python3
import os, sys, zipfile

def pack(src_dir: str, out_path: str):
    src_dir = os.path.abspath(src_dir)
    with zipfile.ZipFile(out_path, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(src_dir):
            dirs.sort()
            files.sort()
            for fn in files:
                p = os.path.join(root, fn)
                rel = os.path.relpath(p, src_dir)
                # ensure skill root folder name is included in archive
                arc = os.path.join(os.path.basename(src_dir), rel)
                z.write(p, arcname=arc)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print('usage: pack_skill_stdlib.py <skill-dir> <out.skill>', file=sys.stderr)
        sys.exit(2)
    pack(sys.argv[1], sys.argv[2])
    print('ok', sys.argv[2])
