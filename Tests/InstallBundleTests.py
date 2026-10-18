"""The installer must keep launchd's bundle identity and roll back failed copies."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('installer', Path(__file__).parents[1] / 'Tools/install-bundle.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.app('new.app', 'new')
        self.destination = self.app('Aster.app', 'old')

    def app(self, name, value):
        path = self.root / name / 'Contents'
        path.mkdir(parents=True)
        (path / 'value').write_text(value)
        return path.parent

    def fake_stage(self, source, destination, transaction, signing_identity=None):
        candidate = transaction / destination.name
        shutil.copytree(source, candidate)
        return candidate

    def test_update_preserves_bundle_identity(self):
        inode = self.destination.stat().st_ino
        with patch.object(installer, 'stage', self.fake_stage), patch.object(installer, 'verify'):
            installer.install(self.source, self.destination)
        self.assertEqual(self.destination.stat().st_ino, inode)
        self.assertEqual((self.destination / 'Contents/value').read_text(), 'new')
        self.assertEqual((self.source / 'Contents/value').read_text(), 'new')

    def test_failed_installed_verification_restores_old_contents(self):
        inode = self.destination.stat().st_ino
        with patch.object(installer, 'stage', self.fake_stage), patch.object(installer, 'verify', side_effect=RuntimeError('invalid')):
            with self.assertRaises(RuntimeError):
                installer.install(self.source, self.destination)
        self.assertEqual(self.destination.stat().st_ino, inode)
        self.assertEqual((self.destination / 'Contents/value').read_text(), 'old')

    def test_stage_failure_never_moves_old_app(self):
        with patch.object(installer, 'stage', side_effect=RuntimeError('invalid')):
            with self.assertRaises(RuntimeError):
                installer.install(self.source, self.destination)
        self.assertEqual((self.destination / 'Contents/value').read_text(), 'old')

    def test_first_install(self):
        destination = self.root / 'First.app'
        with patch.object(installer, 'stage', self.fake_stage):
            installer.install(self.source, destination)
        self.assertEqual((destination / 'Contents/value').read_text(), 'new')

    def test_symlink_is_rejected(self):
        destination = self.root / 'Linked.app'
        destination.symlink_to(self.destination)
        with self.assertRaises(ValueError):
            installer.install(self.source, destination)
        self.assertEqual((self.destination / 'Contents/value').read_text(), 'old')

    def test_unchanged_helper_keeps_inode(self):
        relative = 'Contents/Library/LaunchServices/battery-care'
        current = self.destination / relative
        replacement = self.source / relative
        current.parent.mkdir(parents=True)
        replacement.parent.mkdir(parents=True)
        current.write_text('same code, old signing timestamp')
        replacement.write_text('same code, new signing timestamp')
        with patch.object(installer, 'code_identity', return_value=('hash', 'certificate and identifier')):
            installer.preserve_unchanged_helpers(self.source, self.destination)
        self.assertEqual(current.stat().st_ino, replacement.stat().st_ino)

    def test_changed_helper_is_not_reused(self):
        relative = 'Contents/Library/LaunchServices/battery-care'
        current = self.destination / relative
        replacement = self.source / relative
        current.parent.mkdir(parents=True)
        replacement.parent.mkdir(parents=True)
        current.write_text('old code')
        replacement.write_text('new code')
        with patch.object(installer, 'code_identity', side_effect=[('old', 'certificate'), ('new', 'certificate')]), \
                patch.object(installer, 'helper_is_registered', return_value=False):
            installer.preserve_unchanged_helpers(self.source, self.destination)
        self.assertNotEqual(current.stat().st_ino, replacement.stat().st_ino)
        self.assertEqual(replacement.read_text(), 'new code')

    def test_active_changed_helper_blocks_update(self):
        relative = 'Contents/Library/LaunchServices/battery-care'
        current = self.destination / relative
        replacement = self.source / relative
        current.parent.mkdir(parents=True)
        replacement.parent.mkdir(parents=True)
        current.write_text('old code')
        replacement.write_text('new code')
        with patch.object(installer, 'code_identity', side_effect=[('old', 'certificate'), ('new', 'certificate')]), \
                patch.object(installer, 'helper_is_registered', return_value=True):
            with self.assertRaises(RuntimeError):
                installer.preserve_unchanged_helpers(self.source, self.destination)
        self.assertEqual(current.read_text(), 'old code')

    def test_identity_uses_both_codesign_output_streams(self):
        result = SimpleNamespace(returncode=0, stdout='designated => certificate and identifier\n', stderr='CDHash=abcdef\n')
        with patch.object(installer.subprocess, 'run', return_value=result):
            self.assertEqual(installer.code_identity(self.source), ('abcdef', 'certificate and identifier'))

    def test_unknown_registration_result_blocks_update(self):
        result = SimpleNamespace(returncode=1, stdout='', stderr='Operation not permitted')
        with patch.object(installer.subprocess, 'run', return_value=result):
            with self.assertRaises(RuntimeError):
                installer.helper_is_registered('battery-care')

    def test_failed_rollback_keeps_recovery_copy(self):
        original_replace = installer.os.replace

        def replace(source, destination):
            if Path(source).name == 'PreviousContents':
                raise OSError('rollback unavailable')
            return original_replace(source, destination)

        with patch.object(installer, 'stage', self.fake_stage), \
                patch.object(installer, 'verify', side_effect=RuntimeError('invalid')), \
                patch.object(installer.os, 'replace', replace):
            with self.assertRaises(OSError):
                installer.install(self.source, self.destination)
        retained = list(self.root.glob('.aster-install-*/PreviousContents/value'))
        self.assertEqual(len(retained), 1)
        self.assertEqual(retained[0].read_text(), 'old')


if __name__ == '__main__':
    unittest.main()
