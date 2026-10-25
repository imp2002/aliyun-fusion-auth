import re
import tempfile
import unittest
from pathlib import Path

from prepare_release import prepare_release


class ReleaseValidationTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.write("pubspec.yaml", "name: example\nversion: 0.1.8\n")
        self.write("android/build.gradle", "version = '0.1.8'\n")
        self.write("ios/aliyun_fusion_auth.podspec", "  s.version = '0.1.8'\n")
        self.write("CHANGELOG.md", "## 0.1.8（2026-10-25）\n\n- Fixed cleanup.\n\n## 0.1.7\n\n- Old notes.\n")

    def write(self, filename, content):
        target = self.root / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def test_stable_release_extracts_only_its_notes(self):
        self.assertEqual(
            prepare_release(self.root, "v0.1.8"),
            ("0.1.8", "- Fixed cleanup.\n"),
        )

    def test_tag_must_match_pubspec(self):
        with self.assertRaisesRegex(ValueError, "must match pubspec"):
            prepare_release(self.root, "v0.1.9")

    def test_native_versions_must_match(self):
        for filename in ("android/build.gradle", "ios/aliyun_fusion_auth.podspec"):
            with self.subTest(filename=filename):
                target = self.root / filename
                original = target.read_text()
                target.write_text(original.replace("0.1.8", "0.1.7"))
                with self.assertRaisesRegex(ValueError, "version must be"):
                    prepare_release(self.root, "v0.1.8")
                target.write_text(original)

    def test_missing_changelog_entry_is_rejected(self):
        self.write("CHANGELOG.md", "## 0.1.80\n\n- Different version.\n")
        with self.assertRaisesRegex(ValueError, "Missing CHANGELOG"):
            prepare_release(self.root, "v0.1.8")

    def test_empty_changelog_entry_is_rejected(self):
        self.write("CHANGELOG.md", "## 0.1.8\n\n## 0.1.7\n\n- Old notes.\n")
        with self.assertRaisesRegex(ValueError, "Empty CHANGELOG"):
            prepare_release(self.root, "v0.1.8")

    def test_prerelease_tag_is_supported(self):
        for filename in (
            "pubspec.yaml",
            "android/build.gradle",
            "ios/aliyun_fusion_auth.podspec",
            "CHANGELOG.md",
        ):
            target = self.root / filename
            target.write_text(target.read_text().replace("0.1.8", "0.1.9-beta.1"))
        self.assertEqual(prepare_release(self.root, "v0.1.9-beta.1")[0], "0.1.9-beta.1")

    def test_current_repository_release_metadata(self):
        root = Path(__file__).resolve().parents[2]
        version = re.search(r"^version:\s*(\S+)", (root / "pubspec.yaml").read_text(), re.MULTILINE).group(1)
        self.assertEqual(prepare_release(root, f"v{version}")[0], version)


if __name__ == "__main__":
    unittest.main()
