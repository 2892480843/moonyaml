test "emit smoke" {
  let v : YamlValue = Map([
    { key: Str("name"), value: Str("moonyaml") },
    { key: Str("version"), value: Str("0.1.0") },
    { key: Int(3L), value: Bool(true) },
    {
      key: Str("deps"),
      value: Seq([Str("core"), Str("string")]),
    },
    {
      key: Str("script"),
      value: Map([
        { key: Str("run"), value: Str("moon test") },
      ]),
    },
  ])
  inspect(v.to_yaml_string(), content=
#|name: moonyaml
#|version: 0.1.0
#|3: true
#|deps:
#|  - core
#|  - string
#|script:
#|  run: moon test
#|
  )
  inspect(v.to_flow_string(), content="{name: moonyaml, version: 0.1.0, 3: true, deps: [core, string], script: {run: moon test}}")
}

test "resolve plain" {
  inspect(resolve_plain("123"), content="123")
  inspect(resolve_plain("1.5"), content="1.5")
  inspect(resolve_plain("true"), content="true")
  inspect(resolve_plain("~"), content="null")
  inspect(resolve_plain("0x1f"), content="31")
  inspect(resolve_plain("hello"), content="hello")
}
