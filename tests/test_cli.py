#!/usr/bin/env python3
"""Black-box CLI and optional Rust differential tests; no runtime dependency."""
import json
import os
from pathlib import Path
import random
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(sys.argv.pop(1) if len(sys.argv) > 1 else ROOT / "json2dir").resolve()
REFERENCE = os.environ.get("JSON2DIR_REFERENCE")


def invoke(root, source, args=(), binary=BINARY, umask=0o022):
    data = source.encode() if isinstance(source, str) else source
    return subprocess.run([str(binary), *args], input=data, cwd=root,
                          capture_output=True, timeout=20, umask=umask)


def snapshot(root):
    result = {}
    for base, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(base) / name
            mode = path.lstat().st_mode
            relative = str(path.relative_to(root))
            result[relative] = (("link", os.readlink(path)) if stat.S_ISLNK(mode) else
                                ("dir", stat.S_IMODE(mode)) if stat.S_ISDIR(mode) else
                                ("file", path.read_bytes(), stat.S_IMODE(mode)))
    return result


class CliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="json2dir-agda-")
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def run_json(self, source, success=True, **kwargs):
        if not isinstance(source, (str, bytes)):
            source = json.dumps(source, ensure_ascii=False)
        result = invoke(self.root, source, **kwargs)
        self.assertEqual(result.returncode, 0 if success else 1,
                         result.stderr.decode(errors="replace"))
        self.assertEqual(result.stdout, b"")
        self.assertEqual(bool(result.stderr), not success)
        return result

    def test_example(self):
        self.run_json((ROOT / "example-tree.json").read_bytes())
        self.assertEqual((self.root / "greeting").read_bytes(), b"Hello, world!")
        self.assertEqual((self.root / "dir/subfile").read_bytes(), b"Content.\n")
        self.assertTrue((self.root / "dir/subdir").is_dir())
        self.assertEqual(os.readlink(self.root / "symlink"), "target path")
        script = self.root / "script"
        self.assertEqual(script.stat().st_mode & 0o111, 0o111)
        self.assertEqual(subprocess.check_output([script]), b"Howdy!\n")

    def test_empty_and_whitespace(self):
        self.run_json(" \r\n\t{} \r\n")
        self.assertEqual(snapshot(self.root), {})

    def test_usage(self):
        for args in [("--help",), ("x",), ("x", "y")]:
            with self.subTest(args=args):
                result = self.run_json(b"invalid", False, args=args)
                self.assertIn(b"Usage: json2dir < file.json", result.stderr)

    def test_unicode_and_escapes(self):
        source = r'{"файл 😀":"Привет\n\t\b\f\r\"\\\/\u0000\ud83d\ude00"}'
        self.run_json(source)
        self.assertEqual((self.root / "файл 😀").read_bytes(),
                         'Привет\n\t\b\f\r"\\/\x00😀'.encode())

    def test_unicode_boundaries(self):
        content = ''.join(chr(n) for n in
                          [0, 0x7f, 0x80, 0x7ff, 0x800, 0xd7ff, 0xe000,
                           0xffff, 0x10000, 0x10ffff])
        for escaped in [True, False]:
            self.run_json(json.dumps({"unicode": content}, ensure_ascii=escaped))
            self.assertEqual((self.root / "unicode").read_bytes(), content.encode())

    def test_invalid_json_has_no_effects(self):
        cases = ["", "f", "3 4", "{}{}", '{"x":}', '{"x":"unterminated}',
                 '{"x":"raw\nnewline"}', r'{"x":"\q"}', r'{"x":"\ud800"}',
                 r'{"x":"\udc00"}', r'{"x":"\ud800\u0041"}', r'{"x":"\u0xx0"}',
                 '{"x":01}', '{"x":-}', '{"x":1.}', '{"x":1e}', '{"x":+1}',
                 '{"x":NaN}', '{"x":Infinity}', '{"x":false,}', '[1,]', '{x:"y"}',
                 '{"x":null // comment\n}', '\ufeff{}', '{"a":"ok","z":}']
        for source in cases:
            with self.subTest(source=source):
                result = self.run_json(source, False)
                self.assertIn(b"couldn't convert stdin to JSON", result.stderr)
                self.assertEqual(snapshot(self.root), {})

    def test_invalid_utf8(self):
        for source in [b"\xff", b"\xc0\xaf", b"\xed\xa0\x80", b"\xf4\x90\x80\x80",
                       b'{"x":"\xe2\x82"}']:
            with self.subTest(source=source):
                self.run_json(source, False)
                self.assertEqual(snapshot(self.root), {})

    def test_stdin_error(self):
        fd = os.open(self.root, os.O_RDONLY)
        try:
            result = subprocess.run([BINARY], cwd=self.root, stdin=fd,
                                    capture_output=True, timeout=20)
        finally:
            os.close(fd)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"couldn't read stdin", result.stderr)

    def test_top_level(self):
        for source in ['"x"', '[]', '0', '-1.25e+3', 'true', 'false', 'null']:
            with self.subTest(source=source):
                result = self.run_json(source, False)
                self.assertIn(b"expected provided JSON to be an object", result.stderr)

    def test_invalid_values(self):
        for value in [None, True, False, 7, 1.5, [], ["link"], ["link", 7],
                      ["script", "x", "y"], ["unknown", "x"], [{}, "x"]]:
            with self.subTest(value=value):
                self.run_json({"bad": value}, False)

    def test_paths(self):
        for key in ["", ".", "..", "/", "/root", "a/b", "./a", "../a", "a/../b", "a\x00b"]:
            with self.subTest(key=key):
                self.run_json({key: "x"}, False)
                self.assertEqual(snapshot(self.root), {})
        self.run_json({".hidden": "yes", "back\\slash": "yes", "-option": "yes"})

    def test_normalized_names_keep_original_io_spelling(self):
        self.run_json({"folder//./": {"child": "x"}}, False)
        self.run_json({"folder//": {}})
        self.run_json({"folder//./": {"child": "x"}})
        self.assertEqual((self.root / "folder/child").read_text(), "x")
        self.run_json({"file/": "x"}, False)

    def test_duplicates_last_wins(self):
        self.run_json('{"x":3,"x":"last"}')
        self.assertEqual((self.root / "x").read_text(), "last")

    def test_sorted_keys_and_partial_failure(self):
        self.run_json('{"z":"later","a":"earlier","m":null}', False)
        self.assertEqual((self.root / "a").read_text(), "earlier")
        self.assertFalse((self.root / "z").exists())

    def test_invalid_value_removes_old_file(self):
        (self.root / "old").write_text("old")
        self.run_json({"old": None}, False)
        self.assertFalse((self.root / "old").exists())

    def test_replacement_and_merge(self):
        self.run_json({"a": "old", "dir": {"old": "keep"}, "link": ["link", "a"]})
        self.run_json({"a": {}, "dir": {"new": "add"}, "link": "plain"})
        self.assertTrue((self.root / "a").is_dir())
        self.assertEqual((self.root / "dir/old").read_text(), "keep")
        self.assertEqual((self.root / "dir/new").read_text(), "add")
        self.assertFalse((self.root / "link").is_symlink())

    def test_existing_directories_stay(self):
        (self.root / "dir").mkdir()
        for value in ["file", ["script", "file"], ["link", "target"]]:
            with self.subTest(value=value):
                self.run_json({"dir": value}, False)
                self.assertTrue((self.root / "dir").is_dir())

    def test_symlink_replacement_keeps_target(self):
        (self.root / "target").write_text("untouched")
        for target in ["target", "missing"]:
            (self.root / "link").symlink_to(target)
            self.run_json({"link": "new"})
            self.assertFalse((self.root / "link").is_symlink())
            self.assertEqual((self.root / "target").read_text(), "untouched")
            self.assertFalse((self.root / "missing").exists())
            (self.root / "link").unlink()

    def test_directory_symlink_replacement(self):
        (self.root / "outside").mkdir()
        (self.root / "dir").symlink_to("outside")
        self.run_json({"dir": {"new": "created"}})
        self.assertFalse((self.root / "dir").is_symlink())
        self.assertFalse((self.root / "outside/new").exists())

    def test_symlink_payload_is_literal(self):
        target = "--target with spaces; $(echo nope) 😀"
        self.run_json({"link": ["link", target]})
        self.assertEqual(os.readlink(self.root / "link"), target)

    def test_nul_in_link_target(self):
        self.run_json({"link": ["link", "before\x00after"]}, False)
        self.assertFalse((self.root / "link").is_symlink())

    def test_umask(self):
        for mask in [0o022, 0o077, 0o777]:
            self.run_json({"file": "x", "script": ["script", "x"]}, umask=mask)
            self.assertEqual(stat.S_IMODE((self.root / "file").stat().st_mode), 0o666 & ~mask)
            self.assertEqual(stat.S_IMODE((self.root / "script").stat().st_mode), (0o666 & ~mask) | 0o111)

    @unittest.skipIf(os.getuid() == 0, "root bypasses permissions")
    def test_unwritable_directory(self):
        child = self.root / "locked"
        child.mkdir()
        child.chmod(0o500)
        try:
            result = self.run_json({"locked": {"file": "x"}}, False)
            self.assertIn(b"./locked/file", result.stderr)
        finally:
            child.chmod(0o700)

    @unittest.skipIf(os.getuid() == 0, "root bypasses permissions")
    def test_unsearchable_empty_directory(self):
        child = self.root / "locked"
        child.mkdir()
        child.chmod(0o600)
        try:
            self.run_json({"locked": {}}, False)
        finally:
            child.chmod(0o700)

    def test_overflow_before_writes_and_duplicates(self):
        for number in ["1e400", "-1e400", "9" * 500, "1.7976931348623158e308"]:
            for source in ['{"a":"x","z":' + number + '}',
                           '{"x":' + number + ',"x":"last"}']:
                with self.subTest(source=source):
                    result = self.run_json(source, False)
                    self.assertIn(b"couldn't convert stdin to JSON", result.stderr)
                    self.assertEqual(snapshot(self.root), {})

    def test_finite_number_duplicate_is_accepted(self):
        for number in ["0e99999", "0e9999999999999999999999", "1e-9999999999999999999",
                       "1.7976931348623157e308", "0.0001", "18446744073709551616"]:
            with self.subTest(number=number):
                self.run_json('{"x":' + number + ',"x":"last"}')

    def test_nesting_limit(self):
        self.run_json('{"x":' * 127 + '{}' + '}' * 127, False)
        self.assertEqual(snapshot(self.root), {})
        self.run_json('{"x":' * 126 + '{}' + '}' * 126)

    def test_large_text(self):
        text = 'Привет 😀\x00\n' * 20000
        self.run_json({"big": text})
        self.assertEqual((self.root / "big").read_bytes(), text.encode())

    def test_wide_object(self):
        self.run_json({f"file-{n:04}": str(n) for n in range(500)})
        self.assertEqual(len(list(self.root.iterdir())), 500)

    @unittest.skipUnless(REFERENCE, "set JSON2DIR_REFERENCE for Rust comparisons")
    def test_rust_differential(self):
        rng = random.Random(20261006)
        def tree(depth):
            result = {}
            for n in range(rng.randrange(1, 6)):
                key = str(n) + rng.choice(["русский", "ascii", "😀", ".dot", "back\\slash"])
                content = ''.join(rng.choice('ab\n\t\x00😀я"\\') for _ in range(rng.randrange(30)))
                kind = rng.randrange(4 if depth else 3)
                result[key] = (content if kind == 0 else ["script", content] if kind == 1 else
                               ["link", "../target"] if kind == 2 else tree(depth - 1))
            return result
        cases = [json.dumps(tree(3), ensure_ascii=bool(n % 2)) for n in range(100)]
        cases += ['{}', '{"x":3,"x":"last"}', '{"a":null,"z":"later"}',
                  '{"dir/./":{}}', '{"dir/":"x"}', '{".":"x"}', '{"x":["oops","x"]}',
                  '{"bad":"\\ud800"}', '{"z":"x","a/b":"bad"}',
                  '{"x":1e400,"x":"last"}', '{"a":"x","z":-1e400}']
        cases += ['{"x":' + number + ',"x":"last"}' for number in
                  ["0e99999", "1e-99999", "1.7976931348623157e308", "1.7976931348623158e308"]]
        cases += ['{"x":' * n + '{}' + '}' * n for n in [126, 127]]
        for source in cases:
            with self.subTest(source=source), tempfile.TemporaryDirectory() as left, tempfile.TemporaryDirectory() as right:
                actual = invoke(left, source)
                expected = invoke(right, source, binary=REFERENCE)
                self.assertEqual(actual.returncode, expected.returncode)
                self.assertEqual(snapshot(left), snapshot(right))


if __name__ == "__main__":
    unittest.main(verbosity=2)
