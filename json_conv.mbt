// MoonYAML — conversion between YamlValue and the core JSON type.

///|
/// Convert a YAML value to JSON.
///
/// Mapping keys are stringified (`Int` keys become `"1"`, `Bool` keys
/// become `"true"`, ...). Integers larger than 2^53 lose precision in
/// JSON numbers, and duplicate keys produced by stringification keep the
/// last value.
pub fn YamlValue::to_json(self : YamlValue) -> Json {
  match self {
    Null => Json::null()
    Bool(b) => Json::boolean(b)
    Int(i) => Json::number(i.to_double())
    Float(d) => Json::number(d)
    Str(s) => Json::string(s)
    Seq(items) => {
      let arr : Array[Json] = []
      for item in items {
        arr.push(item.to_json())
      }
      Json::array(arr)
    }
    Map(pairs) => {
      let obj : Map[String, Json] = Map([], capacity=16)
      for pair in pairs {
        obj.set(yaml_key_to_string(pair.key), pair.value.to_json())
      }
      Json::object(obj)
    }
  }
}

///|
/// Render a mapping key as the JSON object-member name.
fn yaml_key_to_string(key : YamlValue) -> String {
  match key {
    Str(s) => s
    Null => "null"
    Bool(b) => if b { "true" } else { "false" }
    Int(i) => "\{i}"
    Float(d) => fmt_double(d)
    Seq(_) | Map(_) => key.to_flow_string()
  }
}

///|
/// Convert a JSON value to YAML.
pub fn YamlValue::from_json(json : Json) -> YamlValue {
  match json {
    Json::Null => Null
    Json::True => Bool(true)
    Json::False => Bool(false)
    Number(d, ..) => Float(d)
    Json::String(s) => Str(s)
    Json::Array(items) => {
      let arr : Array[YamlValue] = []
      for item in items {
        arr.push(YamlValue::from_json(item))
      }
      Seq(arr)
    }
    Json::Object(obj) => {
      // core's Map iteration order is unspecified; sort keys so that
      // JSON -> YAML output is deterministic
      let keys : Array[String] = []
      for k, _v in obj {
        keys.push(k)
      }
      keys.sort_by(compare_strings)
      let pairs : Array[YamlPair] = []
      for k in keys {
        pairs.push({
          key: Str(k),
          value: YamlValue::from_json(obj.get(k).unwrap()),
        })
      }
      Map(pairs)
    }
  }
}

///|
fn compare_strings(a : String, b : String) -> Int {
  String::compare(a, b)
}
