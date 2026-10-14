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

While it builds, one line shows the step, a bar, how far along the whole build is, and the time so far.
The percentage comes from the last build's log length and step times, kept in
~/Documents/Gatita-releases/release-steps.json.
"""

import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PBXPROJ = REPO / "Gatita.xcodeproj" / "project.pbxproj"
CHANGELOG = REPO / "CHANGELOG.md"
TEMPLATE = REPO / "scripts" / "release-templates" / "INSTALL-IPA-WITH-SIDELOADLY.md"
RELEASES = Path.home() / "Documents" / "Gatita-releases"
SCHEME = "Gatita"
STEP_HISTORY = RELEASES / "release-steps.json"

# What each step takes when there is no earlier build to go by: log lines and seconds (0.0.7, from scratch).
USUAL_STEPS = {
    "test": {"lines": 7880, "seconds": 128},
    "mac": {"lines": 2090, "seconds": 222},
    "ios": {"lines": 2600, "seconds": 236},
    "package": {"lines": 0, "seconds": 10},
}

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


def bar(fraction: float, width: int) -> str:
    filled = int(max(0.0, min(1.0, fraction)) * width)
    return "█" * filled + "░" * (width - filled)


def duration(seconds: float) -> str:
    whole = int(seconds)
    return f"{whole // 60}:{whole % 60:02d}"


def step_fraction(lines: int, usual_lines: int, seconds: float, usual_seconds: float) -> float:
    """How far a step is: its log lines and its time, each against the last build's, averaged. xcodebuild logs
    in bursts and then goes quiet for minutes while it optimizes, so time keeps the bar moving. A step with no
    log goes by time alone. It stays at 99% until the step ends."""
    parts = [min(part, 0.99) for part, usual in ((lines, usual_lines), (seconds, usual_seconds)) if usual > 0
             for part in [part / usual]]
    return sum(parts) / len(parts) if parts else 0


def overall(weights: list[float], step: int, fraction: float) -> float:
    """How far the whole build is, with each step counted by how long it usually takes."""
    total = sum(weights)
    if total <= 0:
        return 0
    done = sum(weights[:step]) + (weights[step] * fraction if step < len(weights) else 0)
    return done / total


def status_line(number: int, count: int, title: str, fraction: float, seconds: float, width: int = 30) -> str:
    return f"Step {number} of {count}  {title}  {bar(fraction, width)}  {int(fraction * 100)}%  {duration(seconds)}"


def load_history(path: Path) -> dict:
    try:
        history = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return history if isinstance(history, dict) else {}


def expected(history: dict, key: str) -> dict:
    """The last build's log lines and seconds for a step, or the usual ones."""
    step = history.get(key)
    if isinstance(step, dict) and isinstance(step.get("lines"), int) and isinstance(step.get("seconds"), (int, float)):
        return {"lines": step["lines"], "seconds": step["seconds"]}
    return USUAL_STEPS[key]


def remember_step(path: Path, key: str, lines: int, seconds: float) -> None:
    history = load_history(path)
    history[key] = {"lines": lines, "seconds": round(seconds)}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(history, indent=2) + "\n", encoding="utf-8")


class Progress:
    """Shows the step, a bar, the percentage of the whole build, and the time so far. In a terminal it is one
    line redrawn five times a second; elsewhere (a pipe or a log) a line when each step starts and ends."""

    def __init__(self, steps: list[tuple[str, str]], history_path: Path, stream=None):
        self.steps = steps
        self.keys = [key for key, _ in steps]
        self.history_path = history_path
        self.history = load_history(history_path)
        self.weights = [expected(self.history, key)["seconds"] for key in self.keys]
        self.stream = stream or sys.stdout
        self.live = self.stream.isatty()
        self.started = time.monotonic()

    def line(self, index: int, fraction_of_step: float) -> str:
        fraction = overall(self.weights, index, fraction_of_step)
        seconds = time.monotonic() - self.started
        number, title = index + 1, self.steps[index][1]
        room = shutil.get_terminal_size().columns - len(status_line(number, len(self.steps), title, fraction, seconds, 0))
        return status_line(number, len(self.steps), title, fraction, seconds, max(10, min(30, room - 1)))

    def show(self, text: str, final: bool = False) -> None:
        if self.live:
            self.stream.write("\r\033[K" + text + ("\n" if final else ""))
        else:
            self.stream.write(text + "\n")
        self.stream.flush()

    def follow(self, index: int, worker: threading.Thread, lines: list[int], started: float) -> None:
        """Redraws the line until the worker is done."""
        usual = expected(self.history, self.keys[index])
        while worker.is_alive():
            worker.join(0.2)
            if self.live:
                fraction = step_fraction(lines[0], usual["lines"], time.monotonic() - started, usual["seconds"])
                self.show(self.line(index, fraction))

    def run(self, key: str, command: list[str], log: Path, cwd: Path = REPO) -> None:
        """Runs one xcodebuild step, writing its output to the log and counting lines for the bar."""
        index = self.keys.index(key)
        started = time.monotonic()
        lines = [0]
        self.show(self.line(index, 0))
        with log.open("w", encoding="utf-8") as handle:
            process = subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, errors="replace")

            def copy() -> None:
                for text in process.stdout:
                    handle.write(text)
                    lines[0] += 1

            reader = threading.Thread(target=copy, daemon=True)
            reader.start()
            try:
                self.follow(index, reader, lines, started)
            except KeyboardInterrupt:
                process.terminate()
                self.show("stopped", final=True)
                raise
            code = process.wait()
        if code != 0:
            self.show(f"✗ {self.steps[index][1]}  {duration(time.monotonic() - started)}", final=True)
            tail = "\n".join(log.read_text(encoding="utf-8", errors="replace").splitlines()[-25:])
            raise SystemExit(f"failed ({code}): {' '.join(command)}\nlast lines of {log}:\n{tail}")
        self.finished(index, lines[0], started)

    def work(self, key: str, action):
        """Runs a step done in Python, such as packaging, and returns what it returns."""
        index = self.keys.index(key)
        started = time.monotonic()
        self.show(self.line(index, 0))
        outcome = {}

        def act() -> None:
            try:
                outcome["result"] = action()
            except BaseException as error:  # handed to the main thread below
                outcome["error"] = error

        worker = threading.Thread(target=act, daemon=True)
        worker.start()
        self.follow(index, worker, [0], started)
        if "error" in outcome:
            self.show(f"✗ {self.steps[index][1]}  {duration(time.monotonic() - started)}", final=True)
            raise outcome["error"]
        self.finished(index, 0, started)
        return outcome.get("result")

    def finished(self, index: int, lines: int, started: float) -> None:
        seconds = time.monotonic() - started
        remember_step(self.history_path, self.keys[index], lines, seconds)
        self.show(f"✓ {self.steps[index][1]}  {duration(seconds)}", final=True)

    def finish(self) -> None:
        self.show(f"Done  {bar(1, 30)}  100%  {duration(time.monotonic() - self.started)}", final=True)


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

    steps = []
    if not skip_tests:
        steps.append(("test", "Tests", ["xcodebuild", "-project", "Gatita.xcodeproj", "-scheme", SCHEME,
                                        "-destination", "platform=macOS", "-derivedDataPath", str(work / "test"),
                                        "CODE_SIGNING_ALLOWED=NO", "test"]))
    steps.append(("mac", "Mac app", ["xcodebuild", "-project", "Gatita.xcodeproj", "-scheme", SCHEME,
                                     "-configuration", "Release", "-destination", "platform=macOS",
                                     "-derivedDataPath", str(work / "mac"), "CODE_SIGNING_ALLOWED=NO", "build"]))
    steps.append(("ios", "iPhone and iPad app", ["xcodebuild", "-project", "Gatita.xcodeproj", "-scheme", SCHEME,
                                                 "-configuration", "Release", "-destination", "generic/platform=iOS",
                                                 "-derivedDataPath", str(work / "ios"), "CODE_SIGNING_ALLOWED=NO",
                                                 "build"]))
    if dry_run:
        for _, _, command in steps:
            print("$ " + " ".join(command))
        print("dry run: nothing was built or written")
        return

    progress = Progress([(key, title) for key, title, _ in steps] + [("package", "Packaging")], STEP_HISTORY)
    for key, _, command in steps:
        progress.run(key, command, work / f"{key}.log")
    sums = progress.work("package", lambda: package(work, out, version, build_number))
    progress.finish()

    print(sums, end="")
    print(f"done: {out}")
    print("next: review the files, then commit and tag when you are ready. This script does not do that.")


def package(work: Path, out: Path, version: str, build_number: int) -> str:
    """Checks the built apps' versions, then writes the zip, the .ipa, the checksums, and the guide."""
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
    return sums


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
