#!/usr/bin/env python3
"""Build Gatita's Debug app, sign it with a steady identity, put it in /Applications, and open it.

  scripts/install_app.py                      build, sign, install, and relaunch
  scripts/install_app.py --create-identity    make the local signing identity first (once), then do the above
  scripts/install_app.py --identities         list what it can sign with, and say which it would use
  scripts/install_app.py --adhoc              sign ad hoc anyway (macOS then forgets Gatita's permissions)
  scripts/install_app.py --dry-run            say what it would do without doing it

Why the signing matters: macOS keeps Input Monitoring (⌘⌘ in other apps), Screen Recording, and the Keychain
"Always Allow" for one code identity. An ad-hoc build is its own identity, so every rebuild loses all three. A build
signed with a certificate keeps one identity, so they stay. The certificate can be an Apple Development one (Xcode,
Settings, Accounts, Manage Certificates) or the local self-signed one that --create-identity makes.
"""

import argparse
import os
import plistlib
import re
import secrets
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import NamedTuple

import release

REPO = Path(__file__).resolve().parent.parent
APP = Path("/Applications/Gatita.app")
WORK = Path.home() / "Library" / "Caches" / "gatita-install"
LOGIN_KEYCHAIN = Path.home() / "Library" / "Keychains" / "login.keychain-db"
LOCAL_IDENTITY = "Gatita Local Signing"
APPLE_PREFIXES = ("Apple Development", "Mac Developer", "Developer ID Application")
CODE_SUFFIXES = {".framework", ".dylib", ".appex", ".xpc", ".bundle", ".app"}
IDENTITY_LINE = re.compile(r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"(.*)"(?:\s+\((.*)\))?\s*$')

OPENSSL_CONFIG = f"""[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = {LOCAL_IDENTITY}
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
"""


class Identity(NamedTuple):
    hash: str
    name: str
    problem: str | None


# --- Choosing what to sign with ---------------------------------------------------------------------------------

def parse_identities(text: str) -> list[Identity]:
    """The identities in `security find-identity -p codesigning` output, once each. A self-signed certificate is
    listed with a problem (macOS does not trust it) but can still sign."""
    found: dict[str, Identity] = {}
    for line in text.splitlines():
        match = IDENTITY_LINE.match(line)
        if match:
            digest, name, problem = match.groups()
            found.setdefault(digest.upper(), Identity(digest.upper(), name, problem))
    return list(found.values())


def pick_identity(identities: list[Identity], wanted: str | None = None) -> Identity | None:
    """The one asked for by name or hash; else our own local certificate; else a good Apple one; else nothing."""
    if wanted:
        return next((i for i in identities if i.name == wanted or i.hash.startswith(wanted.upper())), None)
    for identity in identities:
        if identity.name == LOCAL_IDENTITY:
            return identity
    return next((i for i in identities if i.problem is None and i.name.startswith(APPLE_PREFIXES)), None)


def signature_kind(codesign_output: str) -> str:
    """"ad hoc", or the name of the certificate that signed, from `codesign -dvvv`."""
    if "Signature=adhoc" in codesign_output:
        return "ad hoc"
    for line in codesign_output.splitlines():
        if line.startswith("Authority="):
            return line.split("=", 1)[1]
    return "unknown"


def designated_requirement(codesign_output: str) -> str | None:
    """The "designated => ..." line of `codesign -dr -`. It is what macOS compares to decide whether a permission
    still belongs to the app: with a certificate it stays the same from build to build, ad hoc it changes."""
    return next((line for line in codesign_output.splitlines() if line.startswith("designated =>")), None)


# --- What to sign -----------------------------------------------------------------------------------------------

def main_executable(app: Path) -> str:
    with open(app / "Contents" / "Info.plist", "rb") as handle:
        return plistlib.load(handle)["CFBundleExecutable"]


def nested_code(app: Path) -> list[Path]:
    """Code inside the app that is signed before the app itself: frameworks, plug-ins, and the extra files next to
    the main executable (a Debug build keeps its code in dylibs there)."""
    contents = app / "Contents"
    found: list[Path] = []
    for folder in ("Frameworks", "PlugIns"):
        found += sorted(p for p in (contents / folder).glob("*") if p.suffix in CODE_SUFFIXES)
    main = main_executable(app)
    found += sorted(p for p in (contents / "MacOS").glob("*") if p.is_file() and p.name != main)
    return found


def sign_commands(app: Path, identity: str, keychain: str | None) -> list[list[str]]:
    """The codesign commands, nested code first. "-" as the identity signs ad hoc."""
    def command(path: Path) -> list[str]:
        base = ["codesign", "--force", "--sign", identity]
        if keychain:
            base += ["--keychain", str(keychain)]
        return base + ["--preserve-metadata=entitlements", str(path)]
    return [command(p) for p in nested_code(app)] + [command(app)]


# --- Doing it ---------------------------------------------------------------------------------------------------

def list_identities(keychain: str | None = None) -> list[Identity]:
    command = ["security", "find-identity", "-p", "codesigning"] + ([str(keychain)] if keychain else [])
    return parse_identities(subprocess.run(command, text=True, capture_output=True).stdout)


def create_identity(keychain: str | None, dry_run: bool) -> None:
    """Makes the self-signed code-signing certificate and its key, and puts both in the keychain. Only codesign may
    use the key without asking. Nothing is trusted system-wide."""
    if any(i.name == LOCAL_IDENTITY for i in list_identities(keychain)):
        print(f"The identity '{LOCAL_IDENTITY}' already exists.")
        return
    target = Path(keychain) if keychain else LOGIN_KEYCHAIN
    print(f"Making the self-signed certificate '{LOCAL_IDENTITY}' in {target}.")
    if dry_run:
        return
    password = secrets.token_hex(16)
    with tempfile.TemporaryDirectory() as folder:
        folder = Path(folder)
        (folder / "openssl.cnf").write_text(OPENSSL_CONFIG)
        subprocess.run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "key.pem",
                        "-out", "cert.pem", "-days", "3650", "-config", "openssl.cnf"],
                       cwd=folder, check=True, capture_output=True)
        subprocess.run(["/usr/bin/openssl", "pkcs12", "-export", "-inkey", "key.pem", "-in", "cert.pem", "-out",
                        "id.p12", "-passout", f"pass:{password}"], cwd=folder, check=True, capture_output=True)
        subprocess.run(["security", "import", str(folder / "id.p12"), "-k", str(target), "-P", password,
                        "-T", "/usr/bin/codesign"], check=True, capture_output=True)
    print("Done. The first time it signs, macOS asks whether codesign may use the key: choose Always Allow.")


def gatita_running() -> bool:
    return subprocess.run(["pgrep", "-f", f"{APP}/Contents/MacOS/Gatita"], capture_output=True).returncode == 0


def quit_gatita() -> None:
    if not gatita_running():
        return
    subprocess.run(["osascript", "-e", 'tell application "Gatita" to quit'], capture_output=True)
    for _ in range(8):
        if not gatita_running():
            return
        time.sleep(1)
    subprocess.run(["pkill", "-f", f"{APP}/Contents/MacOS/Gatita"])
    time.sleep(2)
    if gatita_running():
        raise SystemExit("Gatita is still running. Quit it, then run this again.")


def app_version(app: Path) -> str:
    with open(app / "Contents" / "Info.plist", "rb") as handle:
        return plistlib.load(handle)["CFBundleShortVersionString"]


def build(derived: Path) -> Path:
    WORK.mkdir(parents=True, exist_ok=True)
    log = WORK / "build.log"
    print(f"Building the Debug app (the log is {log}) ...")
    command = ["xcodebuild", "-project", str(REPO / "Gatita.xcodeproj"), "-scheme", "Gatita",
               "-destination", "platform=macOS", "-configuration", "Debug", "-derivedDataPath", str(derived),
               "CODE_SIGNING_ALLOWED=NO", "build"]
    with open(log, "w") as handle:
        result = subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        errors = [line for line in log.read_text(errors="replace").splitlines() if "error:" in line][:12]
        raise SystemExit("The build failed:\n" + "\n".join(errors))
    built = derived / "Build" / "Products" / "Debug" / "Gatita.app"
    expected = release.read_project_version(release.PBXPROJ.read_text())[0]
    if app_version(built) != expected:
        raise SystemExit(f"The built app is {app_version(built)} but the project says {expected}.")
    return built


def sign(app: Path, identity: str, keychain: str | None) -> None:
    for command in sign_commands(app, identity, keychain):
        result = subprocess.run(command, text=True, capture_output=True)
        if result.returncode != 0:
            hint = ""
            if "no identity found" in result.stderr:
                hint = f"\nMake it once with:  python3 scripts/install_app.py --create-identity"
            elif "User interaction is not allowed" in result.stderr or "errSecInternalComponent" in result.stderr:
                hint = "\nUnlock your login keychain, and choose Always Allow when macOS asks about the key."
            raise SystemExit(f"Signing failed ({Path(command[-1]).name}):\n{result.stderr.strip()}{hint}")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)


def replace_installed(staged: Path) -> Path | None:
    """Moves the old app aside (never deletes it first), copies the new one in, and keeps the last three old ones."""
    old_folder = WORK / "old"
    kept = None
    if APP.exists():
        old_folder.mkdir(parents=True, exist_ok=True)
        kept = old_folder / f"Gatita-{app_version(APP)}-{time.strftime('%H%M%S')}.app"
        shutil.move(str(APP), str(kept))
    try:
        subprocess.run(["ditto", str(staged), str(APP)], check=True)
    except Exception:
        if kept:
            shutil.move(str(kept), str(APP))
        raise
    older = sorted(old_folder.glob("Gatita-*.app"), key=lambda p: p.stat().st_mtime, reverse=True)[3:]
    for path in older:
        shutil.rmtree(path, ignore_errors=True)
    return kept


def main() -> None:
    parser = argparse.ArgumentParser(description="Build, sign, install, and relaunch Gatita.")
    parser.add_argument("--identity", help="sign with this identity (a name or the start of its hash)")
    parser.add_argument("--adhoc", action="store_true", help="sign ad hoc; macOS then forgets Gatita's permissions")
    parser.add_argument("--create-identity", action="store_true", help="make the local signing identity first")
    parser.add_argument("--identities", action="store_true", help="list the identities and exit")
    parser.add_argument("--keychain", help="use this keychain instead of the default ones (for testing)")
    parser.add_argument("--no-launch", action="store_true", help="install but do not open the app")
    parser.add_argument("--dry-run", action="store_true", help="say what would happen without doing it")
    args = parser.parse_args()

    if args.create_identity:
        create_identity(args.keychain, args.dry_run)
    identities = list_identities(args.keychain)
    chosen = pick_identity(identities, args.identity or os.environ.get("GATITA_SIGN_IDENTITY"))

    if args.identities:
        for identity in identities:
            note = "" if identity.problem is None else "  (macOS does not trust it, which is fine for signing Gatita)"
            print(f"{identity.hash[:10]}  {identity.name}{note}")
        print("Would sign with:", chosen.name if chosen and not args.adhoc else "nothing: ad hoc")
        return

    if args.adhoc or chosen is None:
        name = "-"
        print("Signing ad hoc: macOS will forget Gatita's permissions again. Fix that once with:\n"
              "  python3 scripts/install_app.py --create-identity" if chosen is None and not args.adhoc else
              "Signing ad hoc, as asked.")
    else:
        name = chosen.hash if args.keychain else chosen.name
        print(f"Signing with '{chosen.name}'.")

    if args.dry_run:
        print("Dry run: would build, sign, quit Gatita, replace /Applications/Gatita.app, and open it.")
        return

    derived = WORK / "dd"
    built = build(derived)
    staged = WORK / "stage" / "Gatita.app"
    shutil.rmtree(staged.parent, ignore_errors=True)
    staged.parent.mkdir(parents=True)
    subprocess.run(["ditto", str(built), str(staged)], check=True)
    sign(staged, name, args.keychain)

    quit_gatita()
    kept = replace_installed(staged)
    if not args.no_launch:
        subprocess.run(["open", str(APP)])
        for _ in range(10):
            if gatita_running():
                break
            time.sleep(1)

    details = subprocess.run(["codesign", "-dvvv", str(APP)], text=True, capture_output=True).stderr
    shown = subprocess.run(["codesign", "-dr", "-", str(APP)], text=True, capture_output=True)
    print(f"Installed Gatita {app_version(APP)}, signed: {signature_kind(details)}.")
    print(designated_requirement(shown.stdout + shown.stderr) or "")
    if kept:
        print(f"The old copy is at {kept}.")
    if not args.no_launch and not gatita_running():
        print("Gatita did not start. Open it from Applications.")


if __name__ == "__main__":
    main()
