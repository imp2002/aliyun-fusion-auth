"""Validate a version tag and prepare a publishable package from Git."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile


def read_version(root: Path) -> str:
    pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(
        r"^version:[ \t]*['\"]?([^\s'\"#]+)['\"]?[ \t]*(?:#.*)?$",
        pubspec,
        re.MULTILINE,
    )
    if not match:
        raise ValueError("Missing version in pubspec.yaml")
    return match.group(1)


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def commit_notes(root: Path, version: str) -> str:
    previous = subprocess.run(
        [
            "git", "describe", "--tags", "--abbrev=0", "--match", "v[0-9]*",
            "--exclude", f"v{version}",
        ],
        cwd=root,
        capture_output=True,
        text=True,
    )
    revision = f"{previous.stdout.strip()}..HEAD" if previous.returncode == 0 else "HEAD"
    notes = git(root, "log", "--no-merges", "--format=- %s", revision)
    return (notes or f"- Release {version}.") + "\n"


def prepare_release(root: Path, tag: str | None = None) -> tuple[str, str]:
    version = read_version(root)
    if tag is not None and tag != f"v{version}":
        raise ValueError(f"Tag {tag!r} must match pubspec.yaml version v{version}")

    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    heading = re.search(
        rf"^##\s+{re.escape(version)}(?:\s|[（(]|$)[^\n]*$",
        changelog,
        re.MULTILINE,
    )
    if heading:
        notes = re.split(
            r"^##\s+", changelog[heading.end() :], maxsplit=1, flags=re.MULTILINE
        )[0].strip()
        if notes:
            return version, notes + "\n"
    return version, commit_notes(root, version)


def stage_package(root: Path, target: Path, version: str, notes: str) -> None:
    if git(root, "status", "--porcelain"):
        raise ValueError("Commit changes before preparing a release package")
    target.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryFile() as archive:
        subprocess.run(["git", "archive", "HEAD"], cwd=root, stdout=archive, check=True)
        archive.seek(0)
        subprocess.run(["tar", "-xf", "-", "-C", str(target)], stdin=archive, check=True)

    changelog = target / "CHANGELOG.md"
    contents = changelog.read_text(encoding="utf-8")
    heading = re.search(
        rf"^##\s+{re.escape(version)}(?:\s|[（(]|$)[^\n]*$",
        contents,
        re.MULTILINE,
    )
    if heading:
        following = re.search(r"^##\s+", contents[heading.end() :], re.MULTILINE)
        end = heading.end() + following.start() if following else len(contents)
        contents = contents[:heading.end()] + "\n\n" + notes + "\n" + contents[end:]
    else:
        first = re.search(r"^##\s+", contents, re.MULTILINE)
        start = first.start() if first else len(contents)
        contents = contents[:start] + f"## {version}\n\n{notes}\n" + contents[start:]
    changelog.write_text(contents, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", nargs="?")
    parser.add_argument("--notes", type=Path)
    parser.add_argument("--package-dir", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    try:
        version, notes = prepare_release(root, args.tag)
        if args.package_dir:
            stage_package(root, args.package_dir, version, notes)
    except ValueError as error:
        parser.exit(1, f"Release validation failed: {error}\n")
    if args.notes:
        args.notes.write_text(notes, encoding="utf-8")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write(f"version={version}\n")
            output.write(f"prerelease={str('-' in version).lower()}\n")
    print(f"Prepared version {version} from pubspec.yaml.")


if __name__ == "__main__":
    main()
