// Round-trip tests: parse -> emit -> parse must be stable.

///|
fn roundtrip(yaml : String) -> Unit raise {
  let v1 = parse(yaml)
  let emitted = v1.to_yaml_string()
  let v2 = parse(emitted)
  if v1 != v2 {
    println("original:  \{v1.to_flow_string()}")
    println("emitted:   \{emitted}")
    println("reparsed:  \{v2.to_flow_string()}")
    abort("round-trip mismatch")
  }
  let emitted2 = v2.to_yaml_string()
  if emitted != emitted2 {
    abort("emission not stable")
  }
}

///|
test "roundtrip structures" {
  roundtrip("a: 1\nb: [1, 2, 3]\nc:\n  d: hello\ne:\n  - x\n  - y: 1\n")
  roundtrip("- a\n- b: 1\n  c: [1, 2]\n- - 1\n  - 2\n")
  roundtrip("top: {a: 1, b: {c: 2}}\n")
  roundtrip(
    "k8s:\n  apiVersion: apps/v1\n  kind: Deployment\n  metadata:\n    name: web\n    labels:\n      app: web\n  spec:\n    replicas: 3\n",
  )
}

///|
test "roundtrip scalars" {
  roundtrip("i: 42\nf: 1.5\nt: true\nn: null\ns: hello\nq: \"123\"\n")
  roundtrip("neg: -17\nhex: 0x1f\nexp: 1e-3\n")
}

///|
test "roundtrip block scalars" {
  roundtrip("text: |\n  line one\n  line two\n")
  roundtrip("text: |-\n  no trailing\n")
  roundtrip("text: |+\n  keep all\n\n")
  roundtrip("folded: >\n  one two\n  three\n\n  para two\n")
}

///|
test "roundtrip anchors" {
  roundtrip("a: &x 1\nb: *x\n")
  roundtrip("base: &b\n  k: v\nref: *b\n")
}

///|
test "roundtrip multiline strings" {
  roundtrip("key: this is\n  a folded value\n")
  roundtrip("key: \"has \\\"quotes\\\" and\\nnewline\"\n")
}

///|
test "roundtrip multi-doc" {
  let docs = parse_all("a: 1\n")
  let emitted = to_yaml_all(docs)
  let docs2 = parse_all(emitted)
  if docs != docs2 {
    abort("multi-doc roundtrip mismatch")
  }
}

///|
test "roundtrip empty and edge collections" {
  roundtrip("a: []\nb: {}\n")
  roundtrip("[]\n")
  roundtrip("{}\n")
}
