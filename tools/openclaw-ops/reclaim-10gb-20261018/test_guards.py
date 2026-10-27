import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from cleanup import checked_directory, fingerprint, delete_pinned, verify_kept, spec, inspect


class Guards(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.target = self.root / "old"
        self.target.mkdir()
        (self.target / "data").write_text("old snapshot")
        self.outside = self.root / "outside"
        self.outside.mkdir()
        (self.outside / "must-survive").write_text("live")

    def tearDown(self):
        self.tmp.cleanup()

    def test_symlink_target_refused(self):
        self.target.rename(self.root / "real")
        self.target.symlink_to(self.outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            checked_directory(self.target)

    def test_symlink_parent_refused(self):
        (self.root / "alias").symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            checked_directory(self.root / "alias" / "old")

    def test_inode_replacement_refused(self):
        before = fingerprint(self.target)
        self.target.rename(self.root / "original")
        self.target.mkdir()
        (self.target / "data").write_text("old snapshot")
        with self.assertRaises(ValueError):
            delete_pinned(self.target, before)

    def test_content_change_refused(self):
        before = fingerprint(self.target)
        (self.target / "data").write_text("changed")
        with self.assertRaises(ValueError):
            delete_pinned(self.target, before)

    def test_symlink_inside_never_followed(self):
        (self.target / "external").symlink_to(self.outside, target_is_directory=True)
        before = fingerprint(self.target)
        delete_pinned(self.target, before)
        self.assertFalse(self.target.exists())
        self.assertTrue((self.outside / "must-survive").exists())

    def test_existing_pending_refused(self):
        before = fingerprint(self.target)
        self.target.with_name(self.target.name + ".cleanup-20261018-pending").mkdir()
        with self.assertRaises(ValueError):
            delete_pinned(self.target, before)
        self.assertTrue(self.target.exists())

    def test_retained_backup_corruption_refused(self):
        import hashlib
        data = self.target / "state.tgz"
        data.write_bytes(b"valid")
        digest = hashlib.sha256(data.read_bytes()).hexdigest()
        (self.target / "SHA256SUMS").write_text(digest + "  state.tgz\n")
        data.write_bytes(b"BROKE")
        with patch("cleanup.spec", return_value={"keep_backup_sets": [str(self.target)], "required_backup_members": {str(self.target): ["state.tgz"]}}):
            with self.assertRaises(ValueError):
                verify_kept()

    def test_retained_manifest_escape_refused(self):
        (self.target / "SHA256SUMS").write_text("0" * 64 + "  ../outside/must-survive\n")
        with patch("cleanup.spec", return_value={"keep_backup_sets": [str(self.target)], "required_backup_members": {str(self.target): ["state.tgz"]}}):
            with self.assertRaises(ValueError):
                verify_kept()

    def test_unapproved_manifest_target_refused(self):
        import json
        manifest = self.root / "targets.json"
        manifest.write_text(json.dumps({"paths": [str(self.outside)]}))
        with patch("cleanup.SPEC", manifest):
            with self.assertRaises(ValueError):
                spec()

    def test_missing_required_checksum_refused(self):
        import hashlib
        (self.target / "state.tgz").write_bytes(b"state")
        (self.target / "sqlite.tgz").write_bytes(b"CORRUPTED")
        digest = hashlib.sha256(b"state").hexdigest()
        (self.target / "SHA256SUMS").write_text(digest + "  state.tgz\n")
        data = {"keep_backup_sets": [str(self.target)], "required_backup_members": {str(self.target): ["state.tgz", "sqlite.tgz"]}}
        with patch("cleanup.spec", return_value=data):
            with self.assertRaises(ValueError):
                verify_kept()

    def test_guard_rechecks_renamed_target(self):
        before = fingerprint(self.target)
        calls = []
        def guard(path):
            calls.append(path)
            if path.name.endswith("-pending"):
                raise ValueError("new mount detected")
        with self.assertRaises(ValueError):
            delete_pinned(self.target, before, guard)
        self.assertEqual(len(calls), 2)
        pending = self.target.with_name(self.target.name + ".cleanup-20261018-pending")
        self.assertTrue((pending / "data").is_file())

    def test_docker_mount_order_is_not_state_drift(self):
        import json
        c = {"Name": "/nemo", "Id": "id", "RestartCount": 0,
             "State": {"Running": True, "Pid": 99, "StartedAt": "unchanged"},
             "Mounts": [{"Source": "/runtime", "Destination": "/sandbox/runtime"},
                        {"Source": "/config", "Destination": "/sandbox/config"}]}
        first = json.dumps([c])
        c["Mounts"].reverse()
        second = json.dumps([c])
        with patch("cleanup.run", side_effect=["id", first, "id", second]):
            self.assertEqual(inspect(), inspect())


if __name__ == "__main__":
    unittest.main()

