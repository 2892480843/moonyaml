// Whitebox tests for the parser (same package: can see internals).

test "simple mapping" {
  let v = parse("a: 1\nb: hello\n")
  inspect(v.to_flow_string(), content="{a: 1, b: hello}")
}

test "nested mapping" {
  let v = parse("a:\n  b: 1\n  c: 2\nd: 3\n")
  inspect(v.to_flow_string(), content="{a: {b: 1, c: 2}, d: 3}")
}

test "sequence of scalars" {
  let v = parse("- a\n- b\n- c\n")
  inspect(v.to_flow_string(), content="[a, b, c]")
}

test "sequence of mappings (compact)" {
  let v = parse("- name: alice\n  age: 30\n- name: bob\n  age: 25\n")
  inspect(
    v.to_flow_string(),
    content="[{name: alice, age: 30}, {name: bob, age: 25}]",
  )
}

test "mapping of sequences" {
  let v = parse("items:\n  - a\n  - b\nother: x\n")
  inspect(v.to_flow_string(), content="{items: [a, b], other: x}")
}

test "seq at same column as key" {
  let v = parse("items:\n- a\n- b\nother: x\n")
  inspect(v.to_flow_string(), content="{items: [a, b], other: x}")
}

test "nested sequences" {
  let v = parse("- - a\n  - b\n- - c\n")
  inspect(v.to_flow_string(), content="[[a, b], [c]]")
}

test "flow seq and map" {
  let v = parse("a: [1, 2, 3]\nb: {x: 1, y: two}\n")
  inspect(v.to_flow_string(), content="{a: [1, 2, 3], b: {x: 1, y: two}}")
}

test "flow json style" {
  let v = parse("{\"a\": 1, \"b\": [true, null]}")
  inspect(v.to_flow_string(), content="{a: 1, b: [true, null]}")
}

test "flow spanning lines" {
  let v = parse("a: [\n  1,\n  2,\n]\n")
  inspect(v.to_flow_string(), content="{a: [1, 2]}")
}

test "scalar types" {
  let v = parse(
#|i: 42
#|neg: -7
#|hex: 0x1f
#|oct: 0o17
#|flt: 3.14
#|exp: 1e3
#|t: true
#|f: False
#|n: null
#|nil: ~
#|s: hello world
  )
  inspect(
    v.to_flow_string(),
    content="{i: 42, neg: -7, hex: 31, oct: 15, flt: 3.14, exp: 1000.0, t: true, f: false, n: null, nil: null, s: hello world}",
  )
}

test "quoted scalars" {
  let v = parse(
#|single: 'it''s'
#|double: "line1\nline2"
#|typed: "123"
#|spaced: "  padded  "
  )
  inspect(
    v.to_flow_string(),
    content="{single: it's, double: \"line1\\nline2\", typed: \"123\", spaced: \"  padded  \"}",
  )
}

test "plain multiline scalar" {
  let v = parse("key: this is\n  a folded value\nother: x\n")
  inspect(v.to_flow_string(), content="{key: this is a folded value, other: x}")
}

test "comments everywhere" {
  let v = parse(
#|# leading comment
#|a: 1 # trailing comment
#|# between entries
#|b: 2
  )
  inspect(v.to_flow_string(), content="{a: 1, b: 2}")
}

test "anchors and aliases" {
  let v = parse("base: &b\n  x: 1\nuse: *b\n")
  inspect(v.to_flow_string(), content="{base: {x: 1}, use: {x: 1}}")
}

test "inline anchor" {
  let v = parse("name: &n bob\nalias: *n\n")
  inspect(v.to_flow_string(), content="{name: bob, alias: bob}")
}

test "merge key" {
  let v = parse(
#|default: &d
#|  timeout: 30
#|  retries: 3
#|prod:
#|  <<: *d
#|  retries: 10
  )
  inspect(
    v.to_flow_string(),
    content="{default: {timeout: 30, retries: 3}, prod: {timeout: 30, retries: 10}}",
  )
}

test "merge key sequence" {
  let v = parse(
#|a: &a
#|  x: 1
#|b: &b
#|  y: 2
#|c:
#|  <<: [*a, *b]
  )
  inspect(v.to_flow_string(), content="{a: {x: 1}, b: {y: 2}, c: {x: 1, y: 2}}")
}

test "literal block scalar" {
  let v = parse("text: |\n  line one\n  line two\n")
  inspect(v.get("text").unwrap().to_flow_string(), content="\"line one\\nline two\\n\"")
}

test "literal strip" {
  let v = parse("text: |-\n  no newline\n")
  inspect(v.get("text").unwrap().to_flow_string(), content="no newline")
}

test "literal keep" {
  let v = parse("text: |+\n  keep\n\n")
  inspect(v.get("text").unwrap().to_flow_string(), content="\"keep\\n\\n\"")
}

test "folded block scalar" {
  let v = parse("text: >\n  folded into\n  one line\n\n  second para\n")
  inspect(
    v.get("text").unwrap().to_flow_string(),
    content="\"folded into one line\\nsecond para\\n\"",
  )
}

test "multiple documents" {
  let docs = parse_all("---\na: 1\n---\nb: 2\n")
  inspect(docs.length(), content="2")
  inspect(docs[0].to_flow_string(), content="{a: 1}")
  inspect(docs[1].to_flow_string(), content="{b: 2}")
}

test "document without marker" {
  let docs = parse_all("a: 1\n")
  inspect(docs.length(), content="1")
  inspect(docs[0].to_flow_string(), content="{a: 1}")
}

test "empty input" {
  inspect(parse("").to_flow_string(), content="null")
  inspect(parse_all("").length(), content="0")
}

test "comments only input" {
  inspect(parse_all("# nothing here\n\n").length(), content="0")
}

test "top level scalar" {
  let v = parse("just a string\n")
  inspect(v.to_flow_string(), content="just a string")
}

test "empty values" {
  let v = parse("a:\nb: ~\nc:\n  d:\n")
  inspect(v.to_flow_string(), content="{a: null, b: null, c: {d: null}}")
}

test "empty collections" {
  let v = parse("a: []\nb: {}\n")
  inspect(v.to_flow_string(), content="{a: [], b: {}}")
}

test "duplicate keys last wins" {
  let v = parse("a: 1\na: 2\n")
  inspect(v.to_flow_string(), content="{a: 2}")
}

test "non-string keys" {
  let v = parse("1: one\ntrue: yes\n2.5: x\n")
  inspect(v.to_flow_string(), content="{1: one, true: yes, 2.5: x}")
}

test "deep nesting" {
  let v = parse("a:\n  b:\n    c:\n      d: deep\n")
  inspect(v.to_flow_string(), content="{a: {b: {c: {d: deep}}}}")
}
