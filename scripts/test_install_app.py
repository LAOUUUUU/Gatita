"""Tests for install_app.py: choosing a signing identity and building the signing steps.
Run: python3 -m unittest discover -s scripts"""

import plistlib
import tempfile
import unittest
from pathlib import Path

import install_app

# What `security find-identity -p codesigning` prints: every identity, then the ones macOS trusts.
# A self-signed certificate is listed with a problem and is not counted as valid, yet it can still sign.
LOCAL_ONLY = """\
Policy: Code Signing
  Matching identities
  1) C112008746644CBC3BABBC9CC7D44CB4E898B486 "Gatita Local Signing" (CSSMERR_TP_NOT_TRUSTED)
     1 identities found

  Valid identities only
     0 valid identities found
"""

APPLE_AND_LOCAL = """\
Policy: Code Signing
  Matching identities
  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Development: Jane Doe (ABCDE12345)"
  2) C112008746644CBC3BABBC9CC7D44CB4E898B486 "Gatita Local Signing" (CSSMERR_TP_NOT_TRUSTED)
  3) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "Some Other Cert" (CSSMERR_TP_NOT_TRUSTED)
     3 identities found

  Valid identities only
  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Development: Jane Doe (ABCDE12345)"
     1 valid identities found
"""

NOTHING = """\
Policy: Code Signing
  Matching identities
     0 identities found

  Valid identities only
     0 valid identities found
"""


class ReadingIdentities(unittest.TestCase):
    def test_lists_each_identity_once_with_its_problem(self):
        found = install_app.parse_identities(APPLE_AND_LOCAL)
        self.assertEqual([i.name for i in found],
                         ["Apple Development: Jane Doe (ABCDE12345)", "Gatita Local Signing", "Some Other Cert"])
        self.assertIsNone(found[0].problem)
        self.assertEqual(found[1].problem, "CSSMERR_TP_NOT_TRUSTED")
        self.assertEqual(found[1].hash, "C112008746644CBC3BABBC9CC7D44CB4E898B486")

    def test_nothing_found_is_an_empty_list(self):
        self.assertEqual(install_app.parse_identities(NOTHING), [])
        self.assertEqual(install_app.parse_identities(""), [])


class ChoosingAnIdentity(unittest.TestCase):
    def test_our_own_certificate_works_even_though_macos_does_not_trust_it(self):
        found = install_app.parse_identities(LOCAL_ONLY)
        self.assertEqual(install_app.pick_identity(found).name, "Gatita Local Signing")

    def test_our_own_certificate_wins_over_an_apple_one(self):
        found = install_app.parse_identities(APPLE_AND_LOCAL)
        self.assertEqual(install_app.pick_identity(found).name, "Gatita Local Signing")

    def test_an_apple_certificate_is_used_when_it_is_the_only_good_one(self):
        found = [i for i in install_app.parse_identities(APPLE_AND_LOCAL) if i.name.startswith("Apple")]
        self.assertEqual(install_app.pick_identity(found).name, "Apple Development: Jane Doe (ABCDE12345)")

    def test_other_untrusted_certificates_are_not_used_on_their_own(self):
        found = [i for i in install_app.parse_identities(APPLE_AND_LOCAL) if i.name == "Some Other Cert"]
        self.assertIsNone(install_app.pick_identity(found))

    def test_nothing_to_pick_from(self):
        self.assertIsNone(install_app.pick_identity([]))

    def test_an_identity_asked_for_by_name_or_hash_is_used(self):
        found = install_app.parse_identities(APPLE_AND_LOCAL)
        self.assertEqual(install_app.pick_identity(found, wanted="Some Other Cert").name, "Some Other Cert")
        self.assertEqual(install_app.pick_identity(found, wanted="bbbbbbbb").name, "Some Other Cert")
        self.assertIsNone(install_app.pick_identity(found, wanted="No Such Cert"))


class WhatToSign(unittest.TestCase):
    def make_app(self, root: Path) -> Path:
        app = root / "Gatita.app"
        (app / "Contents" / "MacOS").mkdir(parents=True)
        (app / "Contents" / "Frameworks" / "Foo.framework").mkdir(parents=True)
        (app / "Contents" / "PlugIns" / "Bar.appex").mkdir(parents=True)
        (app / "Contents" / "Resources").mkdir(parents=True)
        for name in ["Gatita", "Gatita.debug.dylib", "__preview.dylib"]:
            (app / "Contents" / "MacOS" / name).write_bytes(b"x")
        (app / "Contents" / "Resources" / "notes.txt").write_text("not code")
        with open(app / "Contents" / "Info.plist", "wb") as f:
            plistlib.dump({"CFBundleExecutable": "Gatita", "CFBundleShortVersionString": "0.0.8"}, f)
        return app

    def test_reads_the_main_executable_from_the_plist(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(install_app.main_executable(self.make_app(Path(tmp))), "Gatita")

    def test_nested_code_is_found_and_the_main_executable_and_resources_are_not(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = self.make_app(Path(tmp))
            names = [p.relative_to(app).as_posix() for p in install_app.nested_code(app)]
        self.assertEqual(names, ["Contents/Frameworks/Foo.framework", "Contents/PlugIns/Bar.appex",
                                 "Contents/MacOS/Gatita.debug.dylib", "Contents/MacOS/__preview.dylib"])

    def test_nested_code_is_signed_before_the_app(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = self.make_app(Path(tmp))
            commands = install_app.sign_commands(app, "Gatita Local Signing", keychain=None)
        self.assertEqual(len(commands), 5)
        self.assertEqual(commands[-1][-1], str(app))
        for command in commands:
            self.assertEqual(command[:4], ["codesign", "--force", "--sign", "Gatita Local Signing"])
            self.assertIn("--preserve-metadata=entitlements", command)
            self.assertNotIn("--keychain", command)

    def test_a_keychain_is_passed_on(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = self.make_app(Path(tmp))
            commands = install_app.sign_commands(app, "ID", keychain="/tmp/test.keychain-db")
        for command in commands:
            index = command.index("--keychain")
            self.assertEqual(command[index + 1], "/tmp/test.keychain-db")

    def test_ad_hoc_signing_uses_a_dash(self):
        with tempfile.TemporaryDirectory() as tmp:
            commands = install_app.sign_commands(self.make_app(Path(tmp)), "-", keychain=None)
        self.assertEqual(commands[0][3], "-")


class ReadingARequirement(unittest.TestCase):
    def test_finds_the_designated_requirement_among_other_lines(self):
        text = 'Executable=/Applications/Gatita.app/Contents/MacOS/Gatita\ndesignated => identifier "Gatita.Gatita" and certificate leaf = H"AB"\n'
        self.assertEqual(install_app.designated_requirement(text),
                         'designated => identifier "Gatita.Gatita" and certificate leaf = H"AB"')

    def test_none_when_there_is_none(self):
        self.assertIsNone(install_app.designated_requirement("Executable=/x\n"))


class ReadingASignature(unittest.TestCase):
    def test_ad_hoc(self):
        self.assertEqual(install_app.signature_kind("Identifier=Gatita\nSignature=adhoc\nTeamIdentifier=not set"), "ad hoc")

    def test_a_certificate(self):
        text = "Identifier=Gatita.Gatita\nAuthority=Gatita Local Signing\nTeamIdentifier=not set"
        self.assertEqual(install_app.signature_kind(text), "Gatita Local Signing")

    def test_unreadable(self):
        self.assertEqual(install_app.signature_kind(""), "unknown")


if __name__ == "__main__":
    unittest.main()
