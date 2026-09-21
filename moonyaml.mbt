// MoonYAML — a YAML 1.2 core-schema parser, emitter and YAML/JSON
// converter for MoonBit.
//
// Entry points live in this file; the value model, parser and emitter are
// split across value.mbt, parser.mbt and emitter.mbt.

///|
/// Parse the first YAML document in `input`. An empty input yields `Null`.
pub fn parse(input : String) -> YamlValue raise YamlError {
  let docs = parse_documents(input)
  if docs.length() == 0 {
    Null
  } else {
    docs[0]
  }
}

///|
/// Parse every YAML document in `input` (`---` separated).
pub fn parse_all(input : String) -> Array[YamlValue] raise YamlError {
  parse_documents(input)
}
