"""Validate a version tag and extract its changelog for a release."""

import argparse
import os
from pathlib import Path
import re


def prepare_release(root: Path, tag: str) -> tuple[str, str]:
    pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*(\S+)\s*$", pubspec, re.MULTILINE)
    if not match:
        raise ValueError("Missing version in pubspec.yaml")
    version = match.group(1)
    if tag != f"v{version}":
        raise ValueError(f"Tag {tag!r} must match pubspec.yaml version v{version}")

    for filename, pattern in (
        ("android/build.gradle", r"^version\s*=\s*['\"]([^'\"]+)['\"]"),
        (
            "ios/aliyun_fusion_auth.podspec",
            r"^\s*s\.version\s*=\s*['\"]([^'\"]+)['\"]",
        ),
    ):
        native_version = re.search(
            pattern, (root / filename).read_text(encoding="utf-8"), re.MULTILINE
        )
        if not native_version or native_version.group(1) != version:
            raise ValueError(f"{filename} version must be {version}")

    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    heading = re.search(
        rf"^##\s+{re.escape(version)}(?:\s|[（(]|$)[^\n]*$",
        changelog,
        re.MULTILINE,
    )
    if not heading:
        raise ValueError(f"Missing CHANGELOG.md entry for {version}")
    notes = re.split(r"^##\s+", changelog[heading.end() :], maxsplit=1, flags=re.MULTILINE)[0]
    if not notes.strip():
        raise ValueError(f"Empty CHANGELOG.md entry for {version}")
    return version, notes.strip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("--notes", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    try:
        version, notes = prepare_release(root, args.tag)
    except ValueError as error:
        parser.exit(1, f"Release validation failed: {error}\n")
    if args.notes:
        args.notes.write_text(notes, encoding="utf-8")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write(f"version={version}\n")
            output.write(f"prerelease={str('-' in version).lower()}\n")
    print(f"Validated {args.tag}: Dart, Android, iOS, and changelog versions match.")


if __name__ == "__main__":
    main()
