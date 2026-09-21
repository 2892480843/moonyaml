# MoonYAML

**A YAML 1.2 core-schema parser, emitter, and YAML/JSON converter — written entirely in [MoonBit](https://www.moonbitlang.com).**

MoonBit's package registry already had TOML, CSV and jq-style JSON querying; YAML was the missing piece. MoonYAML fills that gap with a from-scratch parser focused on the subset of YAML that real-world configuration files actually use, backed by a round-trip test suite.

## Features

- **Block structures** — nested mappings and sequences, compact `- key: value` notation, sequences at the same column as their key
- **Flow collections** — `[a, b]`, `{x: 1}` (may span lines), JSON-style `{"a": 1}` input works as-is
- **Scalars** — plain scalars with YAML 1.2 Core Schema type resolution (`null` / `bool` / `int` incl. `0x`, `0o` / `float` incl. `.inf`, `.nan`), single- and double-quoted strings with escapes, multi-line folding
- **Block scalars** — literal `|` and folded `>` with `+` / `-` chomping indicators and explicit indentation
- **Anchors & aliases** — `&anchor`, `*alias`, and merge keys `<<: *base` (including sequences of merge sources)
- **Multi-document streams** — `---` / `...` markers, `%YAML` directives skipped
- **Emitter** — block-style output with compact sequence notation, literal block scalars for multi-line strings, conservative plain-scalar safety analysis (anything ambiguous gets quoted)
- **Round-trip guarantee** — `parse → emit → parse` is verified stable by the test suite
- **Errors with line numbers** — every rejection reports `line N: <reason>` via the `YamlError` suberror type

## Scope (read this)

MoonYAML targets the **YAML 1.2 Core Schema practical subset**. Deliberately out of scope, reported as clear errors:

- explicit tags (`!!str`, `!custom`)
- explicit complex keys (`? key`)
- tabs used for indentation (always an error, as in the spec)

Duplicate keys: last value wins, first position kept. Mapping order is preserved. JSON numbers are `Double` on the JSON side; integers beyond 2⁵³ lose precision when converted to JSON.

## Install

```bash
moon add a111/moonyaml
```

## Library usage

```moonbit
let doc : YamlValue = @moonyaml.parse(
#|server:
#|  host: localhost
#|  port: 8080
)

doc.get("server").unwrap().get("port").unwrap()  // Int(8080)
doc.to_yaml_string()                              // emit back to YAML
doc.to_json().stringify(indent=2)                 // JSON via moonbitlang/core
```

Main API:

| Function | Description |
|---|---|
| `parse(input) -> YamlValue raise YamlError` | first document (`Null` for empty input) |
| `parse_all(input) -> Array[YamlValue] raise YamlError` | every document |
| `YamlValue::to_yaml_string(indent~=2)` | serialize (block style) |
| `to_yaml_all(docs, indent~=2)` | serialize documents with `---` separators |
| `YamlValue::to_flow_string()` | single-line flow representation |
| `YamlValue::to_json()` / `YamlValue::from_json(Json)` | JSON interop |
| `YamlValue::get(key)` / `at(i)` / `size()` | accessors |

The `YamlValue` type: `Null · Bool(Bool) · Int(Int64) · Float(Double) · Str(String) · Seq(Array[YamlValue]) · Map(Array[YamlPair])` — mappings are ordered arrays of pairs, and both derive `Eq` and `Show`.

## The `yj` CLI

```bash
moon run cmd/yj -- config.yml          # YAML -> JSON (pretty)
moon run cmd/yj -- -r config.json      # JSON -> YAML
moon run cmd/yj -- -e 'a: [1, 2]'      # convert a literal string
moon run cmd/yj -- -a stream.yml       # all documents as a JSON array
moon run cmd/yj -- -c config.yml       # compact JSON
```

Build a native binary with `moon build --target native cmd/yj`.

Note: MoonBit's native runtime does not expose stdin yet, so `yj` reads files (or the `-e` literal) rather than pipes.

## Development

```bash
moon check --deny-warn   # type-check, zero warnings enforced
moon test                # 54 tests
moon fmt                 # format
```

CI (GitHub Actions) runs the same steps on every push.

### Project layout

| File | Contents |
|---|---|
| `value.mbt` | `YamlValue` model, Core Schema scalar resolution |
| `parser.mbt` | cursor, scanner, block/flow parser, block scalars, document driver |
| `emitter.mbt` | block-style serializer, quoting analysis |
| `json_conv.mbt` | `YamlValue` ↔ core `Json` |
| `moonyaml.mbt` | public entry points |
| `cmd/yj/` | the CLI |
| `*_wbtest.mbt` / `*_test.mbt` | whitebox / blackbox tests |

## Testing strategy

- **Structure matrix** — 32 cases covering nesting, flow, quoting, anchors, merges, block scalars, multi-doc
- **Round-trip properties** — `parse(emit(parse(x))) == parse(x)` and stable emission for families of inputs
- **Error contract** — 10 cases asserting that malformed input fails *with the expected message fragment and line number*
- **Blackbox tests** — the public API exercised as an external package would

## License

Apache-2.0
