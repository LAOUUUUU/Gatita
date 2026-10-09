#!/usr/bin/env python3
"""Bump Gatita's version and build the release files from the command line.

  scripts/release.py bump 0.0.5              set the version, and the build number + 1
  scripts/release.py bump 0.0.5 --build 7    set the version and the build number
  scripts/release.py build                   build the version already in the project (no bump)
  scripts/release.py release 0.0.5           bump, then build
  scripts/release.py build --skip-tests      build without running the macOS tests
  scripts/release.py build --dry-run         print the steps without running them

`build` writes the macOS zip, the iPhone and iPad .ipa, SHA256SUMS.txt, and the Sideloadly guide to
~/Documents/Gatita-releases/<version>-alpha/. Run it again to rebuild a version after a fix; existing
files there are replaced. The script never commits, tags, or publishes.
"""

import argparse
import hashlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PBXPROJ = REPO / "Gatita.xcodeproj" / "project.pbxproj"
CHANGELOG = REPO / "CHANGELOG.md"
TEMPLATE = REPO / "scripts" / "release-templates" / "INSTALL-IPA-WITH-SIDELOADLY.md"
RELEASES = Path.home() / "Documents" / "Gatita-releases"
SCHEME = "Gatita"

VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")
MARKETING = re.compile(r"MARKETING_VERSION = ([^;]+);")
BUILD = re.compile(r"CURRENT_PROJECT_VERSION = ([^;]+);")


def read_project_version(text: str) -> tuple[str, int]:
    """The version and build number the project uses. Every target must agree."""
    marketing = set(MARKETING.findall(text))
    builds = set(BUILD.findall(text))
    if len(marketing) != 1 or len(builds) != 1:
        raise SystemExit(f"the targets disagree on the version: {sorted(marketing)} / {sorted(builds)}")
    return marketing.pop(), int(builds.pop())


def write_project_version(text: str, version: str, build: int) -> str:
    """Sets the version and build number on every target."""
    text = MARKETING.sub(f"MARKETING_VERSION = {version};", text)
    return BUILD.sub(f"CURRENT_PROJECT_VERSION = {build};", text)


def check_version(version: str, current: str | None = None) -> None:
    """A version is MAJOR.MINOR.PATCH, and a bump must go up. Numbers never reset."""
    if not VERSION_PATTERN.match(version):
        raise SystemExit(f"'{version}' is not MAJOR.MINOR.PATCH, for example 0.0.5")
    if current is not None and parse(version) <= parse(current):
        raise SystemExit(f"{version} is not newer than {current}. Versions only go up.")


def parse(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def check_changelog(version: str) -> None:
    """The release notes must exist before a build, so each release says what changed."""
    if f"## {version} alpha" not in CHANGELOG.read_text(encoding="utf-8"):
        raise SystemExit(f"CHANGELOG.md has no '## {version} alpha' section. Add the release notes first.")


def run(command: list[str], log: Path, dry_run: bool, cwd: Path = REPO) -> None:
    print("$ " + " ".join(command))
    if dry_run:
        return
    with log.open("w", encoding="utf-8") as handle:
        result = subprocess.run(command, cwd=cwd, stdout=handle, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        tail = "\n".join(log.read_text(encoding="utf-8", errors="replace").splitlines()[-25:])
        raise SystemExit(f"failed ({result.returncode}): {' '.join(command)}\nlast lines of {log}:\n{tail}")


def bump(version: str, build: int | None, dry_run: bool) -> None:
    text = PBXPROJ.read_text(encoding="utf-8")
    current, current_build = read_project_version(text)
    check_version(version, current)
    new_build = build if build is not None else current_build + 1
    print(f"version {current} (build {current_build}) -> {version} (build {new_build})")
    if not dry_run:
        PBXPROJ.write_text(write_project_version(text, version, new_build), encoding="utf-8")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check_built_app(app: Path, version: str, build: int) -> None:
    """The app inside the file must carry the version we meant to ship."""
    plist_path = app / "Contents" / "Info.plist"
    if not plist_path.exists():
        plist_path = app / "Info.plist"
    info = plistlib.loads(plist_path.read_bytes())
    if info.get("CFBundleShortVersionString") != version or info.get("CFBundleVersion") != str(build):
        raise SystemExit(f"{app.name} reports {info.get('CFBundleShortVersionString')} "
                         f"({info.get('CFBundleVersion')}), expected {version} ({build})")


def build(skip_tests: bool, dry_run: bool) -> None:
    text = PBXPROJ.read_text(encoding="utf-8")
    version, build_number = read_project_version(text)
    check_version(version)
    check_changelog(version)

    out = RELEASES / f"{version}-alpha"
    work = Path(tempfile.mkdtemp(prefix="gatita-release-"))
    print(f"building {version} (build {build_number}) into {out}")
    print(f"derived data and logs in {work}")

    if not skip_tests:
        run(["xcodebuild", "-project", "Gatita.xcodeproj", "-scheme", SCHEME,
             "-destination", "platform=macOS", "-derivedDataPath", str(work / "test"),
             "CODE_SIGNING_ALLOWED=NO", "test"], work / "test.log", dry_run)

    run(["xcodebuild", "-project", "Gatita.xcodeproj", "-scheme", SCHEME, "-configuration", "Release",
         "-destination", "platform=macOS", "-derivedDataPath", str(work / "mac"),
         "CODE_SIGNING_ALLOWED=NO", "build"], work / "mac.log", dry_run)
    run(["xcodebuild", "-project", "Gatita.xcodeproj", "-scheme", SCHEME, "-configuration", "Release",
         "-destination", "generic/platform=iOS", "-derivedDataPath", str(work / "ios"),
         "CODE_SIGNING_ALLOWED=NO", "build"], work / "ios.log", dry_run)
    if dry_run:
        print("dry run: nothing was built or written")
        return

    mac_app = work / "mac" / "Build" / "Products" / "Release" / f"{SCHEME}.app"
    ios_app = work / "ios" / "Build" / "Products" / "Release-iphoneos" / f"{SCHEME}.app"
    check_built_app(mac_app, version, build_number)
    check_built_app(ios_app, version, build_number)

    out.mkdir(parents=True, exist_ok=True)
    mac_zip = out / f"{SCHEME}-{version}-alpha-macos.zip"
    ipa = out / f"{SCHEME}-{version}-alpha-ios.ipa"
    for stale in (mac_zip, ipa):
        stale.unlink(missing_ok=True)

    subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(mac_app), str(mac_zip)], check=True)

    payload = work / "pkg" / "Payload"
    shutil.rmtree(work / "pkg", ignore_errors=True)
    payload.mkdir(parents=True)
    shutil.copytree(ios_app, payload / ios_app.name, symlinks=True)
    subprocess.run(["zip", "-qr", "-X", str(ipa), "Payload"], cwd=work / "pkg", check=True)

    sums = "".join(f"{sha256(path)}  {path.name}\n" for path in (mac_zip, ipa))
    (out / "SHA256SUMS.txt").write_text(sums, encoding="utf-8")
    (out / "INSTALL-IPA-WITH-SIDELOADLY.md").write_text(
        TEMPLATE.read_text(encoding="utf-8").replace("{version}", version), encoding="utf-8")

    print(sums, end="")
    print(f"done: {out}")
    print("next: review the files, then commit and tag when you are ready. This script does not do that.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    bump_cmd = commands.add_parser("bump", help="set the version and build number")
    bump_cmd.add_argument("version")
    bump_cmd.add_argument("--build", type=int, help="build number (default: the current one + 1)")
    bump_cmd.add_argument("--dry-run", action="store_true")

    build_cmd = commands.add_parser("build", help="build the version in the project")
    build_cmd.add_argument("--skip-tests", action="store_true")
    build_cmd.add_argument("--dry-run", action="store_true")

    release_cmd = commands.add_parser("release", help="bump, then build")
    release_cmd.add_argument("version")
    release_cmd.add_argument("--build", type=int)
    release_cmd.add_argument("--skip-tests", action="store_true")
    release_cmd.add_argument("--dry-run", action="store_true")

    args = parser.parse_args()
    if args.command == "bump":
        bump(args.version, args.build, args.dry_run)
    elif args.command == "build":
        build(args.skip_tests, args.dry_run)
    else:
        bump(args.version, args.build, args.dry_run)
        build(args.skip_tests, args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
