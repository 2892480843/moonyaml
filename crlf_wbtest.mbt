// Regression tests for CRLF and unicode handling (found by real-world
// stress testing: String::replace only replaces the first occurrence).

///|
test "crlf multiline" {
  let v = parse("a: 1\r\nb:\r\n  - x\r\n  - 中文内容值\r\nc: 2\r\n")
  inspect(v.to_flow_string(), content="{a: 1, b: [x, 中文内容值], c: 2}")
}

///|
test "crlf quoted with emoji" {
  let v = parse("a: 1\r\nb: \"emoji 🎉 test\"\r\n")
  inspect(v.to_flow_string(), content="{a: 1, b: emoji 🎉 test}")
}

///|
test "crlf everywhere" {
  let v = parse(
    "key: value\r\nnested:\r\n  inner: 1\r\nlist:\r\n  - a\r\n  - b\r\n# comment\r\nlast: true\r\n",
  )
  inspect(
    v.to_flow_string(),
    content="{key: value, nested: {inner: 1}, list: [a, b], last: true}",
  )
}

///|
test "unicode plain and quoted" {
  let v = parse(
    "中文键: 中文值\nemoji: 🚀火箭\ncjk \"quoted\": \"引号内 🎉\"\n",
  )
  inspect(
    v.to_flow_string(),
    content="{中文键: 中文值, emoji: 🚀火箭, cjk \"quoted\": 引号内 🎉}",
  )
}

///|
test "crlf roundtrip" {
  let v1 = parse("a: |\r\n  line one\r\n  line two\r\nb: [1, 2]\r\n")
  let emitted = v1.to_yaml_string()
  let v2 = parse(emitted)
  if v1 != v2 {
    abort("CRLF roundtrip mismatch")
  }
}
