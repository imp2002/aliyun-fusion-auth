import subprocess
import tempfile
import unittest
from pathlib import Path

from prepare_release import prepare_release, read_version, stage_package


class ReleaseValidationTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.write("pubspec.yaml", "name: example\nversion: 0.1.8\n")
        self.write("CHANGELOG.md", "## 0.1.8（2026-10-25）\n\n- Fixed cleanup.\n\n## 0.1.7\n\n- Old notes.\n")
        self.git("init", "-q")
        self.git("config", "user.name", "Release test")
        self.git("config", "user.email", "release@example.com")
        self.commit("Initial package")
        self.git("tag", "v0.1.7")
        self.write("change.txt", "Test change\n")
        self.commit("Improve authentication cleanup")

    def write(self, filename, content):
        target = self.root / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def commit(self, message):
        self.git("add", ".")
        self.git("-c", "commit.gpgsign=false", "commit", "-qm", message)

    def test_stable_release_extracts_only_its_notes(self):
        self.assertEqual(
            prepare_release(self.root, "v0.1.8"),
            ("0.1.8", "- Fixed cleanup.\n"),
        )

    def test_tag_must_match_pubspec(self):
        with self.assertRaisesRegex(ValueError, "must match pubspec"):
            prepare_release(self.root, "v0.1.9")

    def test_missing_changelog_entry_uses_commits_since_previous_tag(self):
        self.write("CHANGELOG.md", "## 0.1.80\n\n- Different version.\n")
        self.assertEqual(
            prepare_release(self.root, "v0.1.8"),
            ("0.1.8", "- Improve authentication cleanup\n"),
        )

    def test_empty_changelog_entry_uses_commits(self):
        self.write("CHANGELOG.md", "## 0.1.8\n\n## 0.1.7\n\n- Old notes.\n")
        self.assertIn("Improve authentication cleanup", prepare_release(self.root, "v0.1.8")[1])

    def test_prerelease_tag_is_supported(self):
        for filename in (
            "pubspec.yaml",
            "CHANGELOG.md",
        ):
            target = self.root / filename
            target.write_text(target.read_text().replace("0.1.8", "0.1.9-beta.1"))
        self.assertEqual(prepare_release(self.root, "v0.1.9-beta.1")[0], "0.1.9-beta.1")

    def test_quoted_version_with_comment(self):
        self.write("pubspec.yaml", 'version: "0.1.9-beta.1+2" # Package version\n')
        self.assertEqual(read_version(self.root), "0.1.9-beta.1+2")

    def test_only_pubspec_needs_to_change_for_next_release(self):
        self.write("pubspec.yaml", "name: example\nversion: 0.1.9\n")
        self.commit("Release 0.1.9")
        version, notes = prepare_release(self.root, "v0.1.9")
        self.git("tag", "v0.1.9")
        self.assertEqual(prepare_release(self.root, "v0.1.9")[1], notes)
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / "package"
            stage_package(self.root, package, version, notes)
            self.assertEqual(read_version(package), "0.1.9")
            self.assertIn("## 0.1.9\n", (package / "CHANGELOG.md").read_text())
            self.assertIn("Improve authentication cleanup", (package / "CHANGELOG.md").read_text())
            self.assertFalse((package / ".git").exists())
        self.assertNotIn("0.1.9", (self.root / "CHANGELOG.md").read_text())
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_uncommitted_source_is_rejected(self):
        self.write("pubspec.yaml", "name: example\nversion: 0.1.9\n")
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "Commit changes"):
                stage_package(self.root, Path(directory) / "package", "0.1.9", "- Release.\n")

    def test_current_repository_release_metadata(self):
        root = Path(__file__).resolve().parents[2]
        version = read_version(root)
        self.assertEqual(prepare_release(root, f"v{version}")[0], version)


if __name__ == "__main__":
    unittest.main()
