// Blackbox tests: exercise the library exactly as an external user would.

///|
test "public api parse and emit" {
  let v : @moonyaml.YamlValue = @moonyaml.parse(
    (
      #|server:
      #|  host: localhost
      #|  port: 8080
      #|  debug: true
      #|features: [yaml, json]
    ),
  )
  inspect(
    v.to_flow_string(),
    content="{server: {host: localhost, port: 8080, debug: true}, features: [yaml, json]}",
  )
  inspect(
    v.get("server").unwrap().get("port").unwrap().to_flow_string(),
    content="8080",
  )
}

///|
test "public api accessors" {
  let v = @moonyaml.parse("items: [a, b, c]\n")
  let items = v.get("items").unwrap()
  inspect(items.size(), content="3")
  inspect(items.at(1).unwrap().to_flow_string(), content="b")
  inspect(v.get("missing") is None, content="true")
}

///|
test "public api json conversion" {
  let v = @moonyaml.parse("a: 1\nb: [x, y]\n")
  let j = v.to_json()
  inspect(j.stringify(), content="{\"a\":1,\"b\":[\"x\",\"y\"]}")
  let back = @moonyaml.YamlValue::from_json(j)
  inspect(back.to_flow_string(), content="{a: 1.0, b: [x, y]}")
}

///|
test "public api multi document" {
  let docs = @moonyaml.parse_all("---\none: 1\n---\ntwo: 2\n---\nthree: 3\n")
  inspect(docs.length(), content="3")
  inspect(docs[2].to_flow_string(), content="{three: 3}")
  let expected : String =
    #|---
    #|one: 1
    #|---
    #|two: 2
    #|---
    #|three: 3
    #|
  inspect(@moonyaml.to_yaml_all(docs, indent=2), content=expected)
}

///|
test "public api error type" {
  try {
    let _ = @moonyaml.parse("a: [1, 2\n")
    fail("expected a parse error")
  } catch {
    @moonyaml.ParseError(_, _) => () // correct error type
    _ => fail("wrong error type")
  }
}
