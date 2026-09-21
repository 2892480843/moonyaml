// MoonYAML — emitter: serialize YamlValue back to YAML text.
//
// Block style is used for collections, with compact notation inside
// sequence items (`- key: value`). Multi-line strings are emitted as
// literal block scalars when safe to do so, and double-quoted otherwise.

///|
/// Serialize to YAML text using block style.
pub fn YamlValue::to_yaml_string(self : YamlValue, indent? : Int = 2) -> String {
  if indent < 1 {
    abort("indent must be at least 1")
  }
  let buf : StringBuilder = StringBuilder::StringBuilder(size_hint=64)
  self.emit_at(buf, 0, indent)
  buf.to_string()
}

///|
/// Serialize several documents, separated by `---` markers.
pub fn to_yaml_all(docs : Array[YamlValue], indent? : Int = 2) -> String {
  if indent < 1 {
    abort("indent must be at least 1")
  }
  let buf : StringBuilder = StringBuilder::StringBuilder(size_hint=64)
  for doc in docs {
    buf.write_string("---\n")
    doc.emit_at(buf, 0, indent)
  }
  buf.to_string()
}

///|
/// Serialize to a single-line flow representation, e.g. `{a: 1, b: [x, y]}`.
/// Used for `Show` output and error messages.
pub fn YamlValue::to_flow_string(self : YamlValue) -> String {
  let buf : StringBuilder = StringBuilder::StringBuilder(size_hint=32)
  self.emit_flow(buf)
  buf.to_string()
}

///|
/// Emit `self` at line start with indentation `col`.
fn YamlValue::emit_at(
  self : YamlValue,
  buf : StringBuilder,
  col : Int,
  step : Int,
) -> Unit {
  write_indent(buf, col)
  self.emit_inline(buf, col, step)
}

///|
fn write_indent(buf : StringBuilder, col : Int) -> Unit {
  let mut n = 0
  while n < col {
    buf.write_char(' ')
    n = n + 1
  }
}

///|
/// Emit `self` with the cursor already at column `col` (the caller has
/// written the indentation, possibly `- ` for a sequence item, or `key: `).
fn YamlValue::emit_inline(
  self : YamlValue,
  buf : StringBuilder,
  col : Int,
  step : Int,
) -> Unit {
  match self {
    Map(pairs) =>
      if pairs.length() == 0 {
        buf.write_string("{}\n")
      } else {
        for i, pair in pairs {
          if i > 0 {
            write_indent(buf, col)
          }
          emit_pair(pair, buf, col, step)
        }
      }
    Seq(items) =>
      if items.length() == 0 {
        buf.write_string("[]\n")
      } else {
        for i, item in items {
          if i > 0 {
            write_indent(buf, col)
          }
          buf.write_string("- ")
          item.emit_inline(buf, col + 2, step)
        }
      }
    Str(s) =>
      if is_block_scalar_safe(s) {
        emit_block_scalar(s, buf, col, step)
      } else {
        buf.write_string(emit_str(s))
        buf.write_char('\n')
      }
    scalar => {
      buf.write_string(emit_scalar_text(scalar))
      buf.write_char('\n')
    }
  }
}

///|
/// Emit one `key: value` pair; the cursor is at column `col`.
fn emit_pair(
  pair : YamlPair,
  buf : StringBuilder,
  col : Int,
  step : Int,
) -> Unit {
  match pair.key {
    Map(_) | Seq(_) => {
      // Complex keys need explicit `? ` notation; we emit it even though
      // moonyaml's own parser does not accept it back.
      buf.write_string("? ")
      pair.key.emit_inline(buf, col + 2, step)
      write_indent(buf, col)
      buf.write_string(": ")
      pair.value.emit_inline(buf, col + 2, step)
    }
    _ => {
      buf.write_string(emit_key_text(pair.key))
      buf.write_string(":")
      match pair.value {
        Map(pairs) =>
          if pairs.length() == 0 {
            buf.write_string(" {}\n")
          } else {
            buf.write_char('\n')
            pair.value.emit_at(buf, col + step, step)
          }
        Seq(items) =>
          if items.length() == 0 {
            buf.write_string(" []\n")
          } else {
            buf.write_char('\n')
            pair.value.emit_at(buf, col + step, step)
          }
        Str(s) =>
          if is_block_scalar_safe(s) {
            buf.write_char(' ')
            emit_block_scalar(s, buf, col, step)
          } else {
            buf.write_string(" ")
            buf.write_string(emit_str(s))
            buf.write_char('\n')
          }
        _ => {
          buf.write_string(" ")
          buf.write_string(emit_scalar_text(pair.value))
          buf.write_char('\n')
        }
      }
    }
  }
}

///|
/// Emit a multi-line string as a literal block scalar with a chomping
/// indicator. The cursor is at column `col` (start of the header).
fn emit_block_scalar(
  s : String,
  buf : StringBuilder,
  col : Int,
  step : Int,
) -> Unit {
  let content_indent = col + step
  // chomping: strip (`-`, no trailing newline), clip (default, one),
  // keep (`+`, all trailing newlines)
  let mut chomp : String = "-"
  let mut body : String = s
  if s.has_suffix("\n\n") {
    chomp = "+"
  } else if s.has_suffix("\n") {
    chomp = ""
    body = s[0:s.length() - 1].to_owned()
  }
  buf.write_string("|")
  buf.write_string(chomp)
  buf.write_char('\n')
  let mut at_line_start : Bool = true
  for c in body {
    if at_line_start && c != '\n' {
      write_indent(buf, content_indent)
    }
    buf.write_char(c)
    at_line_start = c == '\n'
  }
  // the final newline terminates the last line; it is not part of the
  // content when chomping strips it
  if !body.has_suffix("\n") {
    buf.write_char('\n')
  }
}

///|
/// Can `s` be represented as a literal block scalar? We require: at least
/// one newline, no carriage returns, no trailing whitespace on any line,
/// no leading newline, and no line consisting only of spaces.
fn is_block_scalar_safe(s : String) -> Bool {
  if !s.contains("\n") || s.contains("\r") {
    return false
  }
  if s.length() > 0 && s.get_char(0).unwrap() == '\n' {
    return false
  }
  let mut line_start = 0
  let len = s.length()
  let mut finished = false
  while !finished {
    let mut line_end = line_start
    while line_end < len && s.get_char(line_end).unwrap() != '\n' {
      line_end = line_end + 1
    }
    if line_end > line_start {
      let last : Int = line_end - 1
      let c = s.get_char(last).unwrap()
      if c == ' ' || c == '\t' {
        return false
      }
      let mut only_spaces = true
      for i = line_start; i < line_end; i = i + 1 {
        if s.get_char(i).unwrap() != ' ' {
          only_spaces = false
          break
        }
      }
      if only_spaces {
        return false
      }
    }
    if line_end >= len {
      finished = true
    } else {
      line_start = line_end + 1
    }
  }
  true
}

///|
/// Render a scalar as YAML text suitable for a mapping key.
fn emit_key_text(key : YamlValue) -> String {
  match key {
    Str(s) => emit_str_key(s)
    _ => emit_scalar_text(key)
  }
}

///|
/// Render any scalar as plain text (`null`, `true`, `12`, `1.5`, ...).
fn emit_scalar_text(v : YamlValue) -> String {
  match v {
    Null => "null"
    Bool(b) => if b { "true" } else { "false" }
    Int(i) => "\{i}"
    Float(d) => fmt_double(d)
    Str(s) => emit_str(s)
    _ => ""
  }
}

///|
/// Render a string scalar in flow/plain context, quoting when necessary.
fn emit_str(s : String) -> String {
  if is_plain_safe(s) {
    s
  } else {
    escape_double_quoted(s)
  }
}

///|
/// Keys get slightly stricter rules: no `:` anywhere, since a colon inside
/// a key is easy to misread.
fn emit_str_key(s : String) -> String {
  if is_plain_safe(s) && !s.contains(":") {
    s
  } else {
    escape_double_quoted(s)
  }
}

///|
/// Format a double the way YAML round-trips it: integral values gain a
/// `.0` suffix so they resolve back to `Float` rather than `Int`.
fn fmt_double(d : Double) -> String {
  if d.is_nan() {
    return ".nan"
  }
  if d.is_inf() {
    return if d > 0 { ".inf" } else { "-.inf" }
  }
  let s : String = "\{d}"
  let has_dot_or_exp = s.contains(".") || s.contains("e") || s.contains("E")
  if has_dot_or_exp {
    s
  } else {
    s + ".0"
  }
}

///|
/// Is `s` safe to emit as a plain (unquoted) scalar? Conservative: any
/// indicator character, leading/trailing space, tab, control character,
/// `": "`, `" #"`, or a value that would resolve to a non-string type
/// disqualifies it.
fn is_plain_safe(s : String) -> Bool {
  let len = s.length()
  if len == 0 {
    return false
  }
  let first = s.get_char(0).unwrap()
  let last = s.get_char(len - 1).unwrap()
  if first == ' ' || last == ' ' {
    return false
  }
  if is_indicator(first) {
    return false
  }
  // would resolve to a different type?
  match resolve_plain(s) {
    Str(inner) => if inner != s { return false }
    _ => return false
  }
  for i = 0; i < len; i = i + 1 {
    let c = s.get_char(i).unwrap()
    if c == ':' {
      // ": " or a trailing ":" is dangerous
      if i + 1 == len || s.get_char(i + 1).unwrap() == ' ' {
        return false
      }
    }
    if c == '#' && i > 0 && s.get_char(i - 1).unwrap() == ' ' {
      return false
    }
    if c == '\t' || c == '\n' || c == '\r' {
      return false
    }
    if c.to_int() < 0x20 {
      return false
    }
  }
  true
}

///|
/// Is `c` a YAML indicator character that may not start a plain scalar?
fn is_indicator(c : Char) -> Bool {
  c == '-' ||
  c == '?' ||
  c == ':' ||
  c == ',' ||
  c == '[' ||
  c == ']' ||
  c == '{' ||
  c == '}' ||
  c == '#' ||
  c == '&' ||
  c == '*' ||
  c == '!' ||
  c == '|' ||
  c == '>' ||
  c == '\'' ||
  c == '"' ||
  c == '%' ||
  c == '@' ||
  c == '`'
}

///|
/// Double-quote and escape a string.
fn escape_double_quoted(s : String) -> String {
  let buf : StringBuilder = StringBuilder::StringBuilder(
    size_hint=s.length() + 2,
  )
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\t' => buf.write_string("\\t")
      '\r' => buf.write_string("\\r")
      '\u{0b}' => buf.write_string("\\v")
      '\u{0c}' => buf.write_string("\\f")
      '\u{08}' => buf.write_string("\\b")
      '\u{07}' => buf.write_string("\\a")
      '\u{1b}' => buf.write_string("\\e")
      _ => {
        let n = c.to_int()
        if n < 0x20 {
          buf.write_string("\\u")
          buf.write_string(hex4(n))
        } else {
          buf.write_char(c)
        }
      }
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
fn hex4(n : Int) -> String {
  let digits = "0123456789abcdef"
  let d3 = n & 0xf
  let d2 = (n >> 4) & 0xf
  let d1 = (n >> 8) & 0xf
  let d0 = (n >> 12) & 0xf
  "\{digits.get_char(d0).unwrap()}\{digits.get_char(d1).unwrap()}\{digits.get_char(d2).unwrap()}\{digits.get_char(d3).unwrap()}"
}

///|
/// Flow-style emission: `{a: 1, b: [x, y]}`.
fn YamlValue::emit_flow(self : YamlValue, buf : StringBuilder) -> Unit {
  match self {
    Null => buf.write_string("null")
    Bool(b) => buf.write_string(if b { "true" } else { "false" })
    Int(i) => buf.write_string("\{i}")
    Float(d) => buf.write_string(fmt_double(d))
    Str(s) => buf.write_string(emit_str(s))
    Seq(items) => {
      buf.write_char('[')
      for i, item in items {
        if i > 0 {
          buf.write_string(", ")
        }
        item.emit_flow(buf)
      }
      buf.write_char(']')
    }
    Map(pairs) => {
      buf.write_char('{')
      for i, pair in pairs {
        if i > 0 {
          buf.write_string(", ")
        }
        match pair.key {
          Str(_) | Bool(_) | Int(_) | Float(_) | Null =>
            buf.write_string(emit_key_text(pair.key))
          _ => pair.key.emit_flow(buf)
        }
        buf.write_string(": ")
        pair.value.emit_flow(buf)
      }
      buf.write_char('}')
    }
  }
}
