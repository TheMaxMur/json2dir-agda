# Sources and notices

- Rust behavior reference: [alurm/json2dir](https://github.com/alurm/json2dir),
  commit `b2072fb5515a603024c123297b27dcaabfdf098a`. The notice from its
  `LICENSE` is retained in the root `LICENSE`.
- Name specification and theorem counterparts:
  [tsalkenov/json2dir-lean](https://github.com/tsalkenov/json2dir-lean), commit
  `1d307a44d04a690fdc142ae7b219ede83195dd27`. `Json2dir.Spec` and
  `Json2dir.Proofs` adapt the specification in `Spec.lean`. Its WTFPL text is
  retained in `LICENSE.lean`.
- Number range behavior: [serde_json 1.0.141](https://github.com/serde-rs/json/tree/v1.0.141),
  default non-`float_roundtrip` parsing in `src/de.rs`. `Json2dir.Number`
  implements the bounded significand and exponent range algorithm in Agda.
  The MIT license option is retained in `LICENSE.serde_json`.

No Rust or Lean runtime/code is included in the application. Agda generates
its own backend code during compilation; generated files are ignored.
