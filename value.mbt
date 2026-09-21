// MoonYAML — value model and YAML 1.2 Core Schema scalar resolution.

///|
/// An ordered key-value pair inside a YAML mapping.
///
/// YAML mappings preserve insertion order; we model them as an array of
/// pairs instead of a hash map so that round-tripping keeps key order.
pub(all) struct YamlPair {
  key : YamlValue
  value : YamlValue
} derive(Eq)

///|
pub extend YamlPair with Eq::{equal, not_equal}

///|
/// Compact flow-style output, convenient in tests and error messages.
pub extend YamlPair with Show::{to_string, output}

///|
/// Compact flow-style output, convenient in tests and error messages.
pub impl Show for YamlPair with fn output(self, logger) {
  logger.write_string(self.key.to_flow_string())
  logger.write_string(": ")
  logger.write_string(self.value.to_flow_string())
}

///|
/// A YAML value.
///
/// The variant set follows the YAML 1.2 Core Schema: plain scalars are
/// resolved to `Null` / `Bool` / `Int` / `Float`, quoted scalars are always
/// `Str`, and collections are ordered sequences and mappings.
pub enum YamlValue {
  Null
  Bool(Bool)
  Int(Int64)
  Float(Double)
  Str(String)
  Seq(Array[YamlValue])
  Map(Array[YamlPair])
} derive(Eq)

///|
pub extend YamlValue with Eq::{equal, not_equal}

///|
/// Compact flow-style output, convenient in tests and error messages.
pub extend YamlValue with Show::{to_string, output}

///|
/// Compact flow-style output, convenient in tests and error messages.
pub impl Show for YamlValue with fn output(self, logger) {
  logger.write_string(self.to_flow_string())
}

///|
/// Look up a string key in a mapping.
pub fn YamlValue::get(self : YamlValue, key : String) -> YamlValue? {
  match self {
    Map(pairs) => {
      let needle : YamlValue = Str(key)
      for pair in pairs {
        if pair.key == needle {
          return Some(pair.value)
        }
      }
      None
    }
    _ => None
  }
}

///|
/// Index a sequence.
pub fn YamlValue::at(self : YamlValue, index : Int) -> YamlValue? {
  match self {
    Seq(items) =>
      if index >= 0 && index < items.length() {
        Some(items[index])
      } else {
        None
      }
    _ => None
  }
}

///|
/// Number of pairs in a mapping, items in a sequence, or 0 otherwise.
pub fn YamlValue::size(self : YamlValue) -> Int {
  match self {
    Seq(items) => items.length()
    Map(pairs) => pairs.length()
    _ => 0
  }
}

// ---------------------------------------------------------------------------
// Core Schema plain-scalar resolution
// ---------------------------------------------------------------------------

///|
fn chars_to_string(cs : Array[Char], from : Int, to : Int) -> String {
  let buf : StringBuilder = StringBuilder::StringBuilder(size_hint=to - from)
  for i = from; i < to; i = i + 1 {
    buf.write_char(cs[i])
  }
  buf.to_string()
}

///|
/// Parse an integer with an explicit radix; `None` on failure or overflow.
fn try_parse_int64(s : String, radix : Int) -> Int64? {
  Some(@string.parse_int64(s, base=radix)) catch {
    _ => None
  }
}

///|
/// Parse a double; `None` on failure.
fn try_parse_double(s : String) -> Double? {
  Some(@string.parse_double(s)) catch {
    _ => None
  }
}

///|
/// Resolve a plain (unquoted) scalar according to the YAML 1.2 Core Schema.
/// Integers that do not fit in an `Int64` are kept as strings.
pub fn resolve_plain(s : String) -> YamlValue {
  match s {
    "" | "~" | "null" | "Null" | "NULL" => Null
    "true" | "True" | "TRUE" => Bool(true)
    "false" | "False" | "FALSE" => Bool(false)
    ".inf" | ".Inf" | ".INF" | "+.inf" | "+.Inf" | "+.INF" =>
      Float(@double.infinity)
    "-.inf" | "-.Inf" | "-.INF" => Float(@double.neg_infinity)
    ".nan" | ".NaN" | ".NAN" => Float(@double.not_a_number)
    _ =>
      if is_core_int(s) {
        let stripped = strip_int_prefix(s)
        match try_parse_int64(stripped.signed, stripped.radix) {
          Some(i) => Int(i)
          None => Str(s) // out of range: keep the original text
        }
      } else if is_core_float(s) {
        match try_parse_double(s) {
          Some(d) => Float(d)
          None => Str(s)
        }
      } else {
        Str(s)
      }
  }
}

///|
priv struct Stripped {
  signed : String // sign + digits, ready for radix parsing
  digits : String // digits only, for validation
  radix : Int
}

///|
/// Strip an optional sign and the `0x` / `0o` base prefix of an integer.
fn strip_int_prefix(s : String) -> Stripped {
  let cs = chars_of(s)
  let n = cs.length()
  let start : Int = if n > 0 && (cs[0] == '+' || cs[0] == '-') { 1 } else { 0 }
  let sign : String = if start == 1 { s[0:1].to_owned() } else { "" }
  if n - start > 2 &&
    cs[start] == '0' &&
    (cs[start + 1] == 'x' || cs[start + 1] == 'X') {
    let digits = chars_to_string(cs, start + 2, n)
    { signed: sign + digits, digits, radix: 16, }
  } else if n - start > 2 &&
    cs[start] == '0' &&
    (cs[start + 1] == 'o' || cs[start + 1] == 'O') {
    let digits = chars_to_string(cs, start + 2, n)
    { signed: sign + digits, digits, radix: 8, }
  } else {
    { signed: s, digits: chars_to_string(cs, start, n), radix: 10, }
  }
}

///|
/// Does `s` match the Core Schema integer production?
/// `[-+]? ( [0-9]+ | 0o [0-7]+ | 0x [0-9a-fA-F]+ )`
fn is_core_int(s : String) -> Bool {
  let stripped = strip_int_prefix(s)
  let digits = chars_of(stripped.digits)
  let len = digits.length()
  if len == 0 {
    return false
  }
  let radix = stripped.radix
  for i = 0; i < len; i = i + 1 {
    let c = digits[i]
    let ok : Bool = if radix == 16 {
      is_dec_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
    } else if radix == 8 {
      c >= '0' && c <= '7'
    } else {
      is_dec_digit(c)
    }
    if !ok {
      return false
    }
  }
  true
}

///|
fn is_dec_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Does `s` match the Core Schema float production?
/// `[-+]? ( [0-9]+ (\. [0-9]*)? | \. [0-9]+ ) ([eE] [-+]? [0-9]+)?`
fn is_core_float(s : String) -> Bool {
  let cs = chars_of(s)
  let len = cs.length()
  let start : Int = if len > 0 && (cs[0] == '+' || cs[0] == '-') {
    1
  } else {
    0
  }
  let mut i = start
  let mut saw_digits = false
  while i < len && is_dec_digit(cs[i]) {
    i = i + 1
    saw_digits = true
  }
  if i < len && cs[i] == '.' {
    i = i + 1
    while i < len && is_dec_digit(cs[i]) {
      i = i + 1
      saw_digits = true
    }
  }
  if !saw_digits {
    return false
  }
  if i < len {
    let e = cs[i]
    if e == 'e' || e == 'E' {
      i = i + 1
      if i < len {
        let sign = cs[i]
        if sign == '+' || sign == '-' {
          i = i + 1
        }
      }
      let mut saw_exp = false
      while i < len && is_dec_digit(cs[i]) {
        i = i + 1
        saw_exp = true
      }
      if !saw_exp {
        return false
      }
    }
  }
  i == len
}
