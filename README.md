# json2dir in Agda

A Unix CLI port of [alurm/json2dir](https://github.com/alurm/json2dir).
Reads a JSON object from stdin and creates its directory tree in the current
directory. JSON parsing, Unicode escapes, number validation, name checks,
duplicate handling, ordering, traversal and CLI behavior are written in Agda.

| JSON value | Filesystem entry |
| --- | --- |
| Object | Directory; recursively materialize its children |
| String | UTF-8 file, without an added newline |
| `["link", target]` | Symbolic link with the literal target |
| `["script", content]` | UTF-8 file with all three execute bits set |

The root must be an object. Other values, malformed arrays and unknown tags
are errors. The CLI accepts no arguments, writes errors to stderr and exits
with status 1; success exits with status 0 and produces no terminal output.

## Build and run

With Nix installed:

```sh
make bootstrap
make
make test
mkdir output
cd output
../json2dir < ../example-tree.json
```

`make bootstrap` installs a project-local toolchain under `.tools/agda`, using
the pinned `flake.lock`. It does not change the global profile. The checked
toolchain is **Agda 2.8.0 / GHC 9.10.3**. No Agda standard library is required;
the source imports only the compiler's built-in modules.

Alternatively, build and test the package in the Nix sandbox:

```sh
nix build 'path:.#default'
mkdir output
cd output
../result/bin/json2dir < ../example-tree.json
```

`nix develop path:.` provides the build environment. Packages are defined for
macOS and Linux, on arm64 and x86-64. Local validation was performed on macOS
arm64. Windows is unsupported because the OS bindings use POSIX operations.

With an existing Agda/GHC environment, run `make` directly. GHC needs the
`bytestring`, `text`, `directory`, `unix` and `ieee754` packages available.
Override `AGDA` or `PYTHON` if needed. To install the executable:

```sh
make install PREFIX="$HOME/.local"
```

## Implementation

Agda's [GHC backend](https://agda.readthedocs.io/en/v2.8.0/tools/compilers.html)
generates Haskell and compiles it into the executable. The only handwritten
backend code consists of imports and small `COMPILE GHC` bindings in
`src/Json2dir/Native.agda`: stdin, strict UTF-8 decoding/encoding, exceptions,
arguments, exit status and OS primitives. Filesystem policy and permission
bit arithmetic stay in Agda. The program invokes no shell commands and uses
no external JSON parser. Python is used only by the test driver.

| Module | Responsibility |
| --- | --- |
| `Json2dir.Base` | Built-ins, list helpers, result type |
| `Json2dir.Value` | JSON AST; sorted insertion with last duplicate winning |
| `Json2dir.Json` | Total recursive-descent JSON parser, strings and surrogate pairs |
| `Json2dir.Number` | Number range validation using Agda's built-in Float operations |
| `Json2dir.Spec` | Certified name checker and JSON-to-entry classifier |
| `Json2dir.Proofs` | Checked safety and classification theorems |
| `Json2dir.Native` | Trusted runtime and POSIX boundary |
| `Json2dir.Tree` | File replacement, directory traversal and script permissions |
| `Main` | CLI and diagnostics |

The pure modules, including parser and proofs, use `{-# OPTIONS --safe #-}`.
Recursive parsing and traversal use decreasing, input-derived fuel; container
nesting follows serde_json's default counter limit of 128 (at most 127 open
containers). No termination overrides, holes or assumed proof lemmas are used.
`Native` contains the trusted IO declarations required by the compiler backend.

## Checked properties

The name checks and classification proofs follow
[tsalkenov/json2dir-lean's specification](https://github.com/tsalkenov/json2dir-lean/blob/1d307a44d04a690fdc142ae7b219ede83195dd27/Spec.lean)
(commit `1d307a44d04a690fdc142ae7b219ede83195dd27`, WTFPL).
The executable calls these same checked functions.

```sh
make verify
```

| Lean theorem | Agda theorem |
| --- | --- |
| `interpretParts_safe` | `interpretParts-safe` |
| `parseName_safe` | `parseName-safe` |
| `parseName_noTraversal` | `parseName-noTraversal` |
| `classify_directory` | `classify-directory` |
| `classify_file` | `classify-file` |
| `classify_link` | `classify-link` |
| `classify_script` | `classify-script` |
| `classify_unknown_kind` | `classify-unknown-kind` |
| `classify_empty_array` | `classify-empty-array` |
| `classify_null` | `classify-null` |
| `classify_bool` | `classify-bool` |
| `classify_num` | `classify-num` |

Accepted names carry a proof that their normalized component is nonempty,
neither `.` nor `..`, and contains neither `/` nor NUL. The additional
`parseName-single-component` theorem proves that the normalized component list
is exactly that singleton and that there is no root/current-directory prefix.
Classification theorems establish the conversion table with preserved payloads
and children, plus rejection of unsupported scalars and arrays. The unknown-tag
theorem takes boolean comparison results for both tag names as its premises.

These proofs establish properties of the pure name checker and classifier.
Parser semantic correctness, IO correctness and equivalence to Rust for all
inputs are not proved.

## Compatibility and tests

The reference used for comparison is Rust json2dir commit
`b2072fb5515a603024c123297b27dcaabfdf098a`, with serde_json 1.0.141.

- Keys are processed in lexical order, and the last duplicate wins.
- An existing file or symlink is removed before classifying its replacement.
  Existing directories are reused and keep unrelated children.
- Script permissions preserve the newly created file's mode and add `0o111`,
  including when the process has a restrictive umask.
- Full JSON syntax, strict input UTF-8 and numeric overflow are checked before
  creating entries. Even an overflowing number overwritten by a duplicate key
  rejects the document. Underflow and zero with a large exponent are accepted.
- Paths are checked using normalized components, while IO retains the original
  key spelling. Rust's behavior for trailing `/` and `/./` is preserved.
- NUL in a key is rejected by the name checker; Rust reports a later OS error.
  OS error wording also differs. Validation/IO failures may leave partial output,
  as in the reference. Directory traversal has the same concurrent symlink
  race limitations as the original utility.

`make test` runs 30 black-box tests covering the example, Unicode boundaries,
invalid syntax/UTF-8, CLI errors, overwrite and merge behavior, permission
failures, umasks, duplicate keys, depth limits, large payloads and wide objects.
To enable the additional Rust comparison within that suite:

```sh
JSON2DIR_REFERENCE=/absolute/path/to/rust/json2dir make test
```

The differential test compares exit status, file bytes, directory/file modes
and literal symlink targets over deterministic generated trees and edge cases.
It does not require identical error strings.

## License

The port uses the permissive notice in `LICENSE`, retaining the Rust reference's
notice. The Agda name specification and proofs adapted from Lean are WTFPL;
see `third_party/LICENSE.lean`. The numeric range algorithm follows
serde_json 1.0.141 under its MIT option; see `third_party/LICENSE.serde_json`.
