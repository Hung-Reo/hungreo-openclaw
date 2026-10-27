#!/usr/bin/env python3
"""Verify fixed daily archives; write only private temporary SQLite copies.

Run on the VPS under nice/ionice. No bot boot, network calls, extraction of
workspace files, or changes to backup sources. Prints checks, never DB rows.
"""
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import tarfile
import tempfile

BASE = Path('/home/hung/backups/openclaw')
GENERATION = '20261027-021528'
CRITICAL = ('state/openclaw.sqlite', 'agents/main/agent/openclaw-agent.sqlite', 'lcm.db')
LIMIT = 2 * 1024**3


def verify(profile):
    backup = BASE / profile / GENERATION
    expected = {}
    for line in (backup / 'SHA256SUMS').read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        name = name.lstrip('*')
        if name.startswith('./'):
            name = name[2:]
        if name not in ('state.tgz', 'sqlite.tgz') or name in expected:
            raise ValueError('unexpected or duplicate checksum member')
        expected[name] = digest
    assert set(expected) == {'state.tgz', 'sqlite.tgz'}
    for name, digest in expected.items():
        h = hashlib.sha256()
        with (backup / name).open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                h.update(block)
        assert h.hexdigest() == digest, 'checksum mismatch'

    prefix = '.openclaw-' + profile + '/'
    config_found = False
    with tarfile.open(backup / 'state.tgz', 'r|gz') as archive:
        for member in archive:
            name = member.name[2:] if member.name.startswith('./') else member.name
            if name == prefix + 'openclaw.json':
                assert not config_found and member.isfile() and member.size < 1024**2
                assert isinstance(json.load(archive.extractfile(member)), dict)
                config_found = True
    assert config_found, 'missing config'

    # Only known fixed filenames are written. No archive path is used as a
    # destination, so archive symlinks/traversal cannot redirect extraction.
    with tempfile.TemporaryDirectory(prefix='openclaw-backup-check-20261027-') as temp:
        scratch = Path(temp)
        assert shutil.disk_usage(scratch).free > 12 * 1024**3, 'insufficient reserve'
        restored = {}
        total = 0
        with tarfile.open(backup / 'sqlite.tgz', 'r|gz') as archive:
            for member in archive:
                name = member.name[2:] if member.name.startswith('./') else member.name
                for relative in CRITICAL:
                    wanted = prefix + relative
                    if name in (wanted + '-wal', wanted + '-journal'):
                        assert member.size == 0, 'snapshot has nonempty transaction companion'
                    if name != wanted:
                        continue
                    assert member.isfile() and relative not in restored
                    total += member.size
                    assert total <= LIMIT, 'scratch limit exceeded'
                    path = scratch / ('critical-' + str(len(restored)) + '.sqlite')
                    with path.open('xb') as output:
                        shutil.copyfileobj(archive.extractfile(member), output, 1024 * 1024)
                    assert path.stat().st_size == member.size
                    restored[relative] = path
        assert set(restored) == set(CRITICAL), 'missing critical DB'
        checks = {}
        for relative, path in restored.items():
            connection = sqlite3.connect(path.as_uri() + '?mode=ro&immutable=1', uri=True)
            try:
                assert connection.execute('PRAGMA quick_check').fetchall() == [('ok',)]
                checks[relative] = {'quick_check': 'ok', 'bytes': path.stat().st_size}
            finally:
                connection.close()
        result = {'profile': profile, 'generation': GENERATION, 'sha256': '2/2 PASS',
                  'config_json': 'PASS', 'sqlite': checks, 'scratch_removed': False}
    result['scratch_removed'] = not scratch.exists()
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    for profile in ('suckhoe', 'hungreo'):
        verify(profile)
