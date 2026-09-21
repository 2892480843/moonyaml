// MoonYAML — parser: recursive descent over a character cursor.
//
// Supported subset of YAML 1.2:
//   * block mappings and sequences (nested, compact `- key: value`)
//   * flow collections `[...]` / `{...}` (may span lines)
//   * plain, single-quoted and double-quoted scalars (multi-line folding)
//   * literal `|` and folded `>` block scalars with chomping indicators
//   * anchors `&a`, aliases `*a`, merge keys `<<`
//   * comments and multiple documents (`---` / `...`)
// Not supported (reported as errors): explicit tags `!!str`, complex
// keys `? key`, tabs used for indentation.

///|
/// A YAML parse error: a message plus the 1-based line where it occurred.
pub(all) suberror YamlError {
  ParseError(String, Int)
} derive(Eq)

///|
pub extend YamlError with Eq::{equal, not_equal}

///|
pub extend YamlError with Show::{to_string, output}

///|
/// Errors render as `ParseError(<message>, <line>)`.
pub impl Show for YamlError with fn output(self, logger) {
  match self {
    ParseError(msg, line) =>
      logger.write_string("ParseError(\"\{msg}\", \{line})")
  }
}

///|
/// Internal parser state: a cursor over the source text.
priv struct Parser {
  src : String
  len : Int
  mut idx : Int // code-unit index of the next character
  mut line : Int // 1-based line of `idx`
  anchors : Map[String, YamlValue]
}

///|
/// Result of looking for the next content line.
priv enum Seek {
  Content(Int) // content starts here, at the given column
  Eof
  DocStart
  DocEnd
}

///|
/// Format a parse error with line information.
fn err(p : Parser, msg : String) -> YamlError {
  ParseError("line \{p.line}: \{msg}", p.line)
}

// ---------------------------------------------------------------------------
// Cursor primitives
// ---------------------------------------------------------------------------

///|
/// Character at the cursor, or `None` at end of input.
fn peek(p : Parser) -> Char? {
  if p.idx < p.len {
    p.src.get_char(p.idx)
  } else {
    None
  }
}

///|
/// Character `off` code units ahead of the cursor.
fn peek_at(p : Parser, off : Int) -> Char? {
  let i = p.idx + off
  if i < p.len {
    p.src.get_char(i)
  } else {
    None
  }
}

///|
/// Consume one character and advance the cursor.
fn bump(p : Parser) -> Char {
  let c = p.src.get_char(p.idx).unwrap()
  let units : Int = if c.to_int() > 0xFFFF { 2 } else { 1 }
  p.idx = p.idx + units
  if c == '\n' {
    p.line = p.line + 1
  }
  c
}

///|
/// Is the cursor at end of line (or end of input)?
fn at_eol(p : Parser) -> Bool {
  p.idx >= p.len || peek(p) == Some('\n')
}

///|
/// Column (0-based) of the cursor within its line.
fn cur_col(p : Parser) -> Int {
  let mut i = p.idx - 1
  let mut col = 0
  while i >= 0 {
    let c = p.src.get_char(i)
    if c == Some('\n') {
      break
    }
    if c != Some('\r') {
      col = col + 1
    }
    i = i - 1
  }
  col
}

///|
/// Skip spaces on the current line.
fn skip_spaces(p : Parser) -> Unit {
  while peek(p) == Some(' ') {
    ignore(bump(p))
  }
}

///|
/// Consume the rest of the current line, not including the newline.
fn skip_to_eol(p : Parser) -> Unit {
  while !at_eol(p) {
    ignore(bump(p))
  }
}

///|
/// Consume the newline at the cursor (if any).
fn consume_newline(p : Parser) -> Unit {
  if p.idx < p.len && peek(p) == Some('\n') {
    ignore(bump(p))
  }
}

///|
/// After a complete node on the current line, skip trailing spaces and an
/// optional comment, then move to the start of the next line.
fn finish_line(p : Parser) -> Unit raise YamlError {
  skip_spaces(p)
  match peek(p) {
    Some('#') => skip_to_eol(p)
    None => return
    Some('\n') => ()
    Some(c) => raise err(p, "unexpected content after value: '\{c}'")
  }
  consume_newline(p)
}

///|
/// From the start of a line, find the next line with content. Skips blank
/// lines, comments and `%` directives; stops at document markers.
fn seek_content(p : Parser) -> Seek raise YamlError {
  // we should be at a line start; if not, finish the line first
  if p.idx < p.len && peek(p) != Some('\n') && p.idx > 0 {
    let prev = p.src.get_char(p.idx - 1)
    if prev != Some('\n') {
      finish_line(p)
    }
  }
  while true {
    if p.idx >= p.len {
      return Eof
    }
    // measure indentation
    let mut col = 0
    while peek(p) == Some(' ') {
      ignore(bump(p))
      col = col + 1
    }
    match peek(p) {
      None => return Eof
      Some('\n') => {
        ignore(bump(p))
        continue
      }
      Some('\t') =>
        raise err(p, "tab characters are not allowed in indentation")
      Some('#') => {
        skip_to_eol(p)
        consume_newline(p)
        continue
      }
      Some('%') => {
        if col == 0 {
          skip_to_eol(p)
          consume_newline(p)
          continue
        }
        return Content(col)
      }
      _ => {
        if col == 0 && at_marker(p) {
          if peek(p) == Some('-') {
            return DocStart
          }
          return DocEnd
        }
        return Content(col)
      }
    }
  }
  abort("unreachable")
}

///|
/// Is the cursor at a `---` or `...` marker (at column 0)?
fn at_marker(p : Parser) -> Bool {
  if cur_col(p) != 0 {
    return false
  }
  let c = peek(p)
  if c != Some('-') && c != Some('.') {
    return false
  }
  let c1 = c.unwrap()
  if peek_at(p, 1) != Some(c1) || peek_at(p, 2) != Some(c1) {
    return false
  }
  match peek_at(p, 3) {
    None => true
    Some('\n') => true
    Some(' ') => true
    _ => false
  }
}

///|
/// Rewind the cursor to the start of the current line.
fn rewind_line_start(p : Parser) -> Unit {
  while p.idx > 0 && p.src.get_char(p.idx - 1) != Some('\n') {
    p.idx = p.idx - 1
  }
}

///|
/// Consume a document marker line (marker plus optional trailing comment).
fn consume_marker(p : Parser) -> Unit {
  ignore(bump(p))
  ignore(bump(p))
  ignore(bump(p))
  skip_spaces(p)
  if peek(p) == Some('#') {
    skip_to_eol(p)
  }
  consume_newline(p)
}

// ---------------------------------------------------------------------------
// Scalar scanning
// ---------------------------------------------------------------------------

///|
/// Is `c` a character that may appear in an anchor or alias name?
fn is_name_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == '-' ||
  c == '.'
}

///|
/// Scan an anchor or alias name; the cursor is on `&` or `*`.
fn scan_name(p : Parser) -> String {
  ignore(bump(p)) // & or *
  let start = p.idx
  while peek(p) != None {
    let c = peek(p).unwrap()
    if !is_name_char(c) {
      break
    }
    ignore(bump(p))
  }
  p.src[start:p.idx].to_owned()
}

///|
/// Fold line breaks for multi-line flow scalars: `parts` are the content
/// pieces of each line; blank lines become newlines, single breaks fold
/// to spaces.
fn fold_lines(parts : Array[String]) -> String {
  let buf : StringBuilder = StringBuilder::StringBuilder(size_hint=32)
  let mut pending_blanks = 0
  let mut first = true
  for part in parts {
    if part.length() == 0 {
      pending_blanks = pending_blanks + 1
      continue
    }
    if first {
      first = false
    } else if pending_blanks > 0 {
      let mut n = pending_blanks
      while n > 0 {
        buf.write_char('\n')
        n = n - 1
      }
    } else {
      buf.write_char(' ')
    }
    pending_blanks = 0
    buf.write_string(part)
  }
  buf.to_string()
}

///|
/// Scan a single-quoted scalar; the cursor is on the opening `'`.
fn scan_single_quoted(p : Parser) -> String raise YamlError {
  ignore(bump(p))
  let parts : Array[String] = []
  let line = StringBuilder::StringBuilder(size_hint=32)
  while true {
    match peek(p) {
      None => raise err(p, "unterminated single-quoted scalar")
      Some('\'') =>
        if peek_at(p, 1) == Some('\'') {
          line.write_char('\'')
          ignore(bump(p))
          ignore(bump(p))
        } else {
          ignore(bump(p))
          parts.push(line.to_string())
          return fold_lines(parts)
        }
      Some('\n') => {
        // fold: trim trailing spaces of this line, leading of the next
        let text = line.to_string()
        parts.push(trim_right_spaces(text))
        line.reset()
        ignore(bump(p))
        skip_spaces(p)
        if peek(p) == Some('\n') {
          // blank line inside the scalar
          let mut blanks = 0
          while peek(p) == Some('\n') {
            parts.push("")
            ignore(bump(p))
            skip_spaces(p)
            blanks = blanks + 1
          }
          ignore(blanks)
        }
      }
      Some(c) => {
        line.write_char(c)
        ignore(bump(p))
      }
    }
  }
  abort("unreachable")
}

///|
fn trim_right_spaces(s : String) -> String {
  let cs = chars_of(s)
  let mut end = cs.length()
  while end > 0 && cs[end - 1] == ' ' {
    end = end - 1
  }
  chars_to_string(cs, 0, end)
}

///|
/// Read `n` hex digits and return their value.
fn hex_value(p : Parser, n : Int) -> Int raise YamlError {
  let mut value = 0
  let mut count = 0
  while count < n {
    match peek(p) {
      Some(c) => {
        let d : Int = if c >= '0' && c <= '9' {
          c.to_int() - '0'.to_int()
        } else if c >= 'a' && c <= 'f' {
          c.to_int() - 'a'.to_int() + 10
        } else if c >= 'A' && c <= 'F' {
          c.to_int() - 'A'.to_int() + 10
        } else {
          raise err(p, "invalid hex escape in double-quoted scalar")
        }
        value = value * 16 + d
        ignore(bump(p))
        count = count + 1
      }
      None => raise err(p, "unterminated escape in double-quoted scalar")
    }
  }
  value
}

///|
/// Scan a double-quoted scalar; the cursor is on the opening `"`.
fn scan_double_quoted(p : Parser) -> String raise YamlError {
  ignore(bump(p))
  let parts : Array[String] = []
  let line = StringBuilder::StringBuilder(size_hint=32)
  while true {
    match peek(p) {
      None => raise err(p, "unterminated double-quoted scalar")
      Some('"') => {
        ignore(bump(p))
        parts.push(line.to_string())
        return fold_lines(parts)
      }
      Some('\\') => {
        ignore(bump(p))
        match peek(p) {
          None => raise err(p, "unterminated escape in double-quoted scalar")
          Some(e) =>
            match e {
              '0' => {
                line.write_char('\u{0}')
                ignore(bump(p))
              }
              'a' => {
                line.write_char('\u{07}')
                ignore(bump(p))
              }
              'b' => {
                line.write_char('\u{08}')
                ignore(bump(p))
              }
              't' | '\t' => {
                line.write_char('\t')
                ignore(bump(p))
              }
              'n' => {
                line.write_char('\n')
                ignore(bump(p))
              }
              'v' => {
                line.write_char('\u{0b}')
                ignore(bump(p))
              }
              'f' => {
                line.write_char('\u{0c}')
                ignore(bump(p))
              }
              'r' => {
                line.write_char('\r')
                ignore(bump(p))
              }
              'e' => {
                line.write_char('\u{1b}')
                ignore(bump(p))
              }
              ' ' => {
                line.write_char(' ')
                ignore(bump(p))
              }
              '"' => {
                line.write_char('"')
                ignore(bump(p))
              }
              '/' => {
                line.write_char('/')
                ignore(bump(p))
              }
              '\\' => {
                line.write_char('\\')
                ignore(bump(p))
              }
              'N' => {
                line.write_char('\u{85}')
                ignore(bump(p))
              }
              '_' => {
                line.write_char('\u{a0}')
                ignore(bump(p))
              }
              'L' => {
                line.write_char('\u{2028}')
                ignore(bump(p))
              }
              'P' => {
                line.write_char('\u{2029}')
                ignore(bump(p))
              }
              'x' => {
                ignore(bump(p))
                let v = hex_value(p, 2)
                line.write_char(int_to_char(p, v))
              }
              'u' => {
                ignore(bump(p))
                let v = hex_value(p, 4)
                line.write_char(int_to_char(p, v))
              }
              'U' => {
                ignore(bump(p))
                let v = hex_value(p, 8)
                line.write_char(int_to_char(p, v))
              }
              '\n' => {
                // escaped line break: join lines without folding
                ignore(bump(p))
                skip_spaces(p)
              }
              other =>
                raise err(
                  p,
                  "unknown escape sequence '\\\{other}' in double-quoted scalar",
                )
            }
        }
      }
      Some('\n') => {
        let text = line.to_string()
        parts.push(trim_right_spaces(text))
        line.reset()
        ignore(bump(p))
        skip_spaces(p)
        while peek(p) == Some('\n') {
          parts.push("")
          ignore(bump(p))
          skip_spaces(p)
        }
      }
      Some(c) => {
        line.write_char(c)
        ignore(bump(p))
      }
    }
  }
  abort("unreachable")
}

///|
fn int_to_char(_p : Parser, v : Int) -> Char {
  match Int::to_char(v) {
    Some(c) => c
    None => abort("invalid unicode escape")
  }
}

///|
/// Does a plain scalar end at this colon? In block context the colon must
/// be followed by a space or end of line; in flow context a `,` `]` `}`
/// also terminates.
fn colon_terminates(p : Parser, in_flow : Bool) -> Bool {
  match peek_at(p, 1) {
    None => true
    Some('\n') => true
    Some(' ') => true
    Some(c) => in_flow && (c == ',' || c == ']' || c == '}')
  }
}

///|
/// Scan a plain scalar segment on the current line. Stops at end of line,
/// a comment (` #`), a terminating colon, or (in flow context) at any of
/// `, [ ] { }`. Returns the trimmed text.
fn scan_plain_segment(p : Parser, in_flow : Bool) -> String {
  let start = p.idx
  let mut last_significant = p.idx
  while !at_eol(p) {
    let c = peek(p).unwrap()
    if c == '#' && p.idx > start && p.src.get_char(p.idx - 1) == Some(' ') {
      break
    }
    if c == ':' && colon_terminates(p, in_flow) {
      break
    }
    if in_flow && (c == ',' || c == '[' || c == ']' || c == '{' || c == '}') {
      break
    }
    ignore(bump(p))
    if c != ' ' {
      last_significant = p.idx
    }
  }
  let mut end = last_significant
  if end < start {
    end = start
  }
  p.src[start:end].to_owned()
}

///|
/// Collect the remaining lines of a multi-line plain scalar in block
/// context. Each continuation line must be indented beyond `parent` and
/// must not look like a new key, sequence item or marker.
fn plain_continuation(p : Parser, parent : Int) -> Array[String] {
  let parts : Array[String] = []
  while true {
    // cursor is at the start of a line here
    let save = p.idx
    let save_line = p.line
    let mut col = 0
    while peek(p) == Some(' ') {
      ignore(bump(p))
      col = col + 1
    }
    if at_marker(p) {
      p.idx = save
      p.line = save_line
      return parts
    }
    if at_eol(p) || peek(p) == Some('#') {
      // blank or comment line: only continues the scalar when deeper
      // content follows; probe ahead without consuming
      if plain_probe_deeper(p, parent) {
        skip_to_eol(p)
        consume_newline(p)
        parts.push("")
        continue
      }
      p.idx = save
      p.line = save_line
      return parts
    }
    if col <= parent {
      p.idx = save
      p.line = save_line
      return parts
    }
    let c = peek(p).unwrap()
    // a new block structure cannot continue a plain scalar
    if c == '-' &&
      (
        peek_at(p, 1) == Some(' ') ||
        peek_at(p, 1) == Some('\n') ||
        peek_at(p, 1) == None
      ) {
      p.idx = save
      p.line = save_line
      return parts
    }
    if c == '&' || c == '*' || c == '!' {
      p.idx = save
      p.line = save_line
      return parts
    }
    // a `key:` line at deeper indent is a mapping, not a continuation
    let seg = scan_plain_segment(p, false)
    skip_spaces(p)
    if peek(p) == Some(':') && colon_terminates(p, false) {
      p.idx = save
      p.line = save_line
      return parts
    }
    parts.push(seg)
    // move to the next line
    if peek(p) == Some('#') {
      skip_to_eol(p)
    }
    if at_eol(p) {
      consume_newline(p)
    } else {
      // defensive: stop on unexpected trailing content
      return parts
    }
  }
  abort("unreachable")
}

///|
/// From a blank/comment line inside a plain scalar, check whether some
/// later content line is indented beyond `parent` (without consuming
/// anything).
fn plain_probe_deeper(p : Parser, parent : Int) -> Bool {
  let mut probe = p.idx
  while probe < p.len {
    // skip the rest of the current line
    while probe < p.len && p.src.get_char(probe) != Some('\n') {
      probe = probe + 1
    }
    if probe >= p.len {
      return false
    }
    probe = probe + 1 // newline
    let mut c2 = 0
    while probe < p.len && p.src.get_char(probe) == Some(' ') {
      probe = probe + 1
      c2 = c2 + 1
    }
    if probe >= p.len {
      return false
    }
    let ch = p.src.get_char(probe).unwrap()
    if ch == '\n' || ch == '#' {
      continue // blank or comment line, keep probing
    }
    return c2 > parent
  }
  false
}

// ---------------------------------------------------------------------------
// Node dispatch
// ---------------------------------------------------------------------------

///|
/// Parse a node in block context. The cursor is on the first content
/// character of a line, at column `col`; `parent` is the indentation that
/// nested content must exceed (the owning key or dash column).
fn parse_block_node(
  p : Parser,
  col : Int,
  parent : Int,
) -> YamlValue raise YamlError {
  match peek(p) {
    None => return Null
    Some('!') => raise err(p, "explicit tags are not supported")
    Some('&') => {
      let name = scan_name(p)
      skip_spaces(p)
      let value : YamlValue = if at_eol(p) || peek(p) == Some('#') {
        // node content follows on deeper lines
        match seek_content(p) {
          Content(c2) =>
            if c2 > parent {
              parse_block_node(p, c2, parent)
            } else {
              rewind_line_start(p)
              Null
            }
          _ => Null
        }
      } else {
        parse_block_node(p, cur_col(p), parent)
      }
      p.anchors.set(name, value)
      return value
    }
    Some('*') => {
      let name = scan_name(p)
      match p.anchors.get(name) {
        Some(v) => return v
        None => raise err(p, "undefined alias '*\{name}'")
      }
    }
    _ => ()
  }
  let c = peek(p).unwrap()
  if c == '|' || c == '>' {
    return parse_block_scalar(p, parent)
  }
  if c == '[' || c == '{' {
    return parse_flow_node(p)
  }
  if c == '-' &&
    (
      peek_at(p, 1) == Some(' ') ||
      peek_at(p, 1) == Some('\n') ||
      peek_at(p, 1) == None
    ) {
    return parse_block_seq(p, col)
  }
  if c == '?' && peek_at(p, 1) == Some(' ') {
    raise err(p, "explicit mapping keys (`? key`) are not supported")
  }
  // scalar or block mapping: scan a key candidate
  let save = p.idx
  let save_line = p.line
  match c {
    '\'' => ignore(scan_single_quoted(p))
    '"' => ignore(scan_double_quoted(p))
    _ => ignore(scan_plain_segment(p, false))
  }
  skip_spaces(p)
  if peek(p) == Some(':') && colon_terminates(p, false) {
    // it is a mapping; rewind and parse it properly
    p.idx = save
    p.line = save_line
    return parse_block_map(p, col)
  }
  // plain multi-line scalar document/value
  p.idx = save
  p.line = save_line
  parse_plain_scalar(p, parent)
}

///|
/// Parse a plain (possibly multi-line) scalar starting at the cursor.
fn parse_plain_scalar(p : Parser, parent : Int) -> YamlValue {
  let first = scan_plain_segment(p, false)
  let parts : Array[String] = [first]
  skip_spaces(p)
  if peek(p) == Some('#') {
    skip_to_eol(p)
  }
  if at_eol(p) {
    consume_newline(p)
    let rest = plain_continuation(p, parent)
    for part in rest {
      parts.push(part)
    }
  }
  resolve_plain(fold_lines(parts))
}

// ---------------------------------------------------------------------------
// Block mappings and sequences
// ---------------------------------------------------------------------------

///|
/// Insert a pair into an ordered mapping; on duplicate keys the later
/// value wins but keeps the key's original position.
fn insert_pair(pairs : Array[YamlPair], pair : YamlPair) -> Unit {
  for i = 0; i < pairs.length(); i = i + 1 {
    if pairs[i].key == pair.key {
      pairs[i] = pair
      return
    }
  }
  pairs.push(pair)
}

///|
/// Apply a merge source (a mapping, or a sequence of mappings) into
/// `pairs`; keys already present are not overridden.
fn apply_merge(
  p : Parser,
  pairs : Array[YamlPair],
  src : YamlValue,
) -> Unit raise YamlError {
  match src {
    Map(src_pairs) =>
      for sp in src_pairs {
        let mut exists = false
        for existing in pairs {
          if existing.key == sp.key {
            exists = true
            break
          }
        }
        if !exists {
          pairs.push({ key: sp.key, value: sp.value, })
        }
      }
    Seq(items) =>
      for item in items {
        apply_merge(p, pairs, item)
      }
    _ =>
      raise err(
        p, "merge key `<<` requires a mapping or a sequence of mappings",
      )
  }
}

///|
/// Parse the value part after `key:`. Handles nested block nodes, block
/// scalars, flow collections, anchors and aliases, and multi-line plain
/// scalars. `key_col` is the column of the owning key.
fn parse_map_value(p : Parser, key_col : Int) -> YamlValue raise YamlError {
  skip_spaces(p)
  if peek(p) == Some('#') {
    skip_to_eol(p)
  }
  if at_eol(p) {
    // value on following lines (or null)
    consume_newline(p)
    match seek_content(p) {
      Content(c2) => {
        if c2 > key_col {
          return parse_block_node(p, c2, key_col)
        }
        if c2 == key_col {
          // a sequence may sit at the same column as its key
          let c = peek(p).unwrap()
          if c == '-' &&
            (
              peek_at(p, 1) == Some(' ') ||
              peek_at(p, 1) == Some('\n') ||
              peek_at(p, 1) == None
            ) {
            return parse_block_seq(p, c2)
          }
        }
        rewind_line_start(p)
        return Null // empty value; cursor stays at the content line
      }
      DocStart | DocEnd => {
        rewind_line_start(p)
        return Null
      }
      Eof => return Null
    }
  }
  // inline value
  match peek(p).unwrap() {
    '!' => raise err(p, "explicit tags are not supported")
    '&' => {
      let name = scan_name(p)
      skip_spaces(p)
      let value : YamlValue = if at_eol(p) || peek(p) == Some('#') {
        skip_to_eol(p)
        consume_newline(p)
        match seek_content(p) {
          Content(c2) =>
            if c2 > key_col {
              parse_block_node(p, c2, key_col)
            } else {
              rewind_line_start(p)
              Null
            }
          _ => Null
        }
      } else {
        parse_map_value_inline(p, key_col)
      }
      p.anchors.set(name, value)
      return value
    }
    '*' => {
      let name = scan_name(p)
      match p.anchors.get(name) {
        Some(v) => return v
        None => raise err(p, "undefined alias '*\{name}'")
      }
    }
    _ => ()
  }
  parse_map_value_inline(p, key_col)
}

///|
/// Parse an inline value that starts on the key's line.
fn parse_map_value_inline(
  p : Parser,
  key_col : Int,
) -> YamlValue raise YamlError {
  match peek(p).unwrap() {
    '|' | '>' => parse_block_scalar(p, key_col)
    '[' | '{' => parse_flow_node(p)
    '\'' => {
      let s = scan_single_quoted(p)
      Str(s)
    }
    '"' => {
      let s = scan_double_quoted(p)
      Str(s)
    }
    _ => parse_plain_scalar(p, key_col)
  }
}

///|
/// Parse a block mapping whose first key starts at the cursor (column
/// `col`).
fn parse_block_map(p : Parser, col : Int) -> YamlValue raise YamlError {
  let pairs : Array[YamlPair] = []
  while true {
    // cursor is on the first content character of a key line
    let key : YamlValue = match peek(p).unwrap() {
      '\'' => Str(scan_single_quoted(p))
      '"' => Str(scan_double_quoted(p))
      '[' | '{' => parse_flow_node(p)
      '&' => {
        let name = scan_name(p)
        skip_spaces(p)
        let k : YamlValue = match peek(p).unwrap() {
          '\'' => Str(scan_single_quoted(p))
          '"' => Str(scan_double_quoted(p))
          '[' | '{' => parse_flow_node(p)
          _ => resolve_plain(scan_plain_segment(p, false))
        }
        p.anchors.set(name, k)
        k
      }
      '*' => {
        let name = scan_name(p)
        match p.anchors.get(name) {
          Some(v) => v
          None => raise err(p, "undefined alias '*\{name}'")
        }
      }
      _ => {
        let text = scan_plain_segment(p, false)
        if text.length() == 0 {
          raise err(p, "expected a mapping key")
        }
        resolve_plain(text)
      }
    }
    skip_spaces(p)
    if peek(p) != Some(':') || !colon_terminates(p, false) {
      raise err(p, "expected ':' after mapping key")
    }
    ignore(bump(p)) // ':'
    // merge key?
    let is_merge : Bool = match key {
      Str(s) => s == "<<"
      _ => false
    }
    let value : YamlValue = parse_map_value(p, col)
    if is_merge {
      apply_merge(p, pairs, value)
    } else {
      insert_pair(pairs, { key, value, })
    }
    // find the next entry
    match seek_content(p) {
      Content(c2) => {
        if c2 < col {
          rewind_line_start(p)
          return Map(pairs)
        }
        if c2 > col {
          raise err(p, "bad indentation: expected column \{col}, found \{c2}")
        }
        // c2 == col: next key (or junk, reported by the loop)
      }
      DocStart | DocEnd => {
        rewind_line_start(p)
        return Map(pairs)
      }
      Eof => return Map(pairs)
    }
  }
  abort("unreachable")
}

///|
/// Parse a block sequence whose first dash is at the cursor (column
/// `col`).
fn parse_block_seq(p : Parser, col : Int) -> YamlValue raise YamlError {
  let items : Array[YamlValue] = []
  while true {
    // cursor is on '-'
    ignore(bump(p))
    skip_spaces(p)
    if peek(p) == Some('#') || at_eol(p) {
      // item content on following lines
      if peek(p) == Some('#') {
        skip_to_eol(p)
      }
      consume_newline(p)
      match seek_content(p) {
        Content(c2) =>
          if c2 > col {
            items.push(parse_block_node(p, c2, col))
          } else {
            items.push(Null)
          }
        _ => items.push(Null)
      }
    } else {
      // compact notation: item starts on the dash line
      let item_col = cur_col(p)
      items.push(parse_block_node(p, item_col, col))
      // after an inline item we may still be mid-line (scalar consumed it)
    }
    // find the next dash
    match seek_content(p) {
      Content(c2) => {
        if c2 < col {
          rewind_line_start(p)
          return Seq(items)
        }
        if c2 > col {
          raise err(p, "bad indentation: expected column \{col}, found \{c2}")
        }
        let c = peek(p).unwrap()
        if c == '-' &&
          (
            peek_at(p, 1) == Some(' ') ||
            peek_at(p, 1) == Some('\n') ||
            peek_at(p, 1) == None
          ) {
          continue
        }
        // not a dash at this column: the sequence ends here
        rewind_line_start(p)
        return Seq(items)
      }
      DocStart | DocEnd => {
        rewind_line_start(p)
        return Seq(items)
      }
      Eof => return Seq(items)
    }
  }
  abort("unreachable")
}

// ---------------------------------------------------------------------------
// Block scalars
// ---------------------------------------------------------------------------

///|
/// Parse a literal (`|`) or folded (`>`) block scalar; the cursor is on
/// the indicator. `parent` is the indentation the content must exceed.
fn parse_block_scalar(p : Parser, parent : Int) -> YamlValue raise YamlError {
  let style = bump(p) // '|' or '>'
  let mut chomp : String = "clip"
  let mut explicit_indent : Int = 0
  // indicator characters: digits and +/-, in any order
  while true {
    match peek(p) {
      Some('+') => {
        chomp = "keep"
        ignore(bump(p))
      }
      Some('-') => {
        chomp = "strip"
        ignore(bump(p))
      }
      Some(c) =>
        if c >= '1' && c <= '9' {
          explicit_indent = c.to_int() - '0'.to_int()
          ignore(bump(p))
        } else {
          break
        }
      None => break
    }
  }
  skip_spaces(p)
  if peek(p) == Some('#') {
    skip_to_eol(p)
  }
  if !at_eol(p) {
    raise err(p, "unexpected content after block scalar header")
  }
  consume_newline(p)
  // collect raw lines belonging to the scalar
  let lines : Array[String] = []
  let mut trailing_empties = 0
  while true {
    if p.idx >= p.len {
      break
    }
    // read one raw line
    let start = p.idx
    while !at_eol(p) {
      ignore(bump(p))
    }
    let raw = p.src[start:p.idx].to_owned()
    consume_newline(p)
    // classify the line
    let indent = count_leading_spaces(raw)
    if indent == raw.length() {
      // empty or whitespace-only line
      lines.push("")
      trailing_empties = trailing_empties + 1
      continue
    }
    trailing_empties = 0
    if indent <= parent {
      // this line ends the scalar; rewind to its start
      p.idx = start
      p.line = p.line - 1
      break
    }
    lines.push(raw)
    ignore(indent)
  }
  // drop trailing empty lines (re-added only for `keep`)
  while lines.length() > 0 && lines[lines.length() - 1].length() == 0 {
    ignore(lines.pop())
  }
  if chomp == "keep" {
    let mut n = trailing_empties
    while n > 0 {
      lines.push("")
      n = n - 1
    }
  }
  // determine content indentation
  let content_indent : Int = if explicit_indent > 0 {
    parent + explicit_indent
  } else {
    let mut found = 0
    for line in lines {
      if line.length() > 0 {
        found = count_leading_spaces(line)
        break
      }
    }
    found
  }
  // strip the content indentation from each line
  let stripped : Array[String] = []
  for line in lines {
    if line.length() == 0 {
      stripped.push("")
    } else {
      // count leading spaces by characters: a surrogate pair must not
      // split an indexing step
      let cs = chars_of(line)
      let mut idx = 0
      while idx < cs.length() && idx < content_indent && cs[idx] == ' ' {
        idx = idx + 1
      }
      stripped.push(chars_to_string(cs, idx, cs.length()))
    }
  }
  let body : String = if style == '|' {
    join_lines(stripped)
  } else {
    fold_block(stripped, content_indent)
  }
  // apply chomping
  let content : String = match chomp {
    "strip" => trim_trailing_newlines(body)
    "clip" => {
      let t = trim_trailing_newlines(body)
      if t.length() == 0 {
        ""
      } else {
        t + "\n"
      }
    }
    _ => body
  }
  Str(content)
}

///|
fn count_leading_spaces(s : String) -> Int {
  let mut n = 0
  let cs = chars_of(s)
  while n < cs.length() && cs[n] == ' ' {
    n = n + 1
  }
  n
}

///|
/// Join lines with newlines (literal style); every line is terminated by
/// a newline, and chomping decides how many of the trailing ones survive.
fn join_lines(lines : Array[String]) -> String {
  let buf : StringBuilder = StringBuilder::StringBuilder(size_hint=32)
  for line in lines {
    buf.write_string(line)
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
/// Fold a block scalar (folded style): single line breaks between
/// non-empty, non-indented lines become spaces; blank lines become
/// newlines; more-indented lines are kept literally.
fn fold_block(lines : Array[String], content_indent : Int) -> String {
  let buf : StringBuilder = StringBuilder::StringBuilder(size_hint=32)
  let mut prev_kind : Int = 0 // 0 = none, 1 = normal, 2 = more-indented
  let mut pending_breaks = 0
  for line in lines {
    if line.length() == 0 {
      pending_breaks = pending_breaks + 1
      continue
    }
    let more_indented = line.length() > 0 && line.get_char(0) == Some(' ')
    let kind : Int = if more_indented { 2 } else { 1 }
    if prev_kind == 0 {
      // first line: pending blank lines were leading empties
      if pending_breaks > 0 {
        let mut n = pending_breaks
        while n > 0 {
          buf.write_char('\n')
          n = n - 1
        }
      }
    } else if pending_breaks > 0 {
      let mut n = pending_breaks
      while n > 0 {
        buf.write_char('\n')
        n = n - 1
      }
    } else if prev_kind == 2 || kind == 2 {
      buf.write_char('\n')
    } else {
      buf.write_char(' ')
    }
    pending_breaks = 0
    prev_kind = kind
    buf.write_string(line)
  }
  // trailing line breaks
  if pending_breaks > 0 {
    let mut n = pending_breaks
    while n > 0 {
      buf.write_char('\n')
      n = n - 1
    }
  }
  ignore(content_indent)
  buf.to_string()
}

///|
fn trim_trailing_newlines(s : String) -> String {
  let cs = chars_of(s)
  let mut end = cs.length()
  while end > 0 && cs[end - 1] == '\n' {
    end = end - 1
  }
  chars_to_string(cs, 0, end)
}

// ---------------------------------------------------------------------------
// Flow collections
// ---------------------------------------------------------------------------

///|
/// Skip whitespace, line breaks and comments inside flow collections.
fn skip_flow_ws(p : Parser) -> Unit raise YamlError {
  while true {
    match peek(p) {
      None => raise err(p, "unexpected end of input inside flow collection")
      Some(' ') => ignore(bump(p))
      Some('\n') => ignore(bump(p))
      Some('\t') => ignore(bump(p))
      Some('\r') => ignore(bump(p))
      Some('#') => {
        skip_to_eol(p)
        consume_newline(p)
      }
      _ => return
    }
  }
}

///|
/// Parse a flow node: `[...]`, `{...}`, a quoted scalar, an alias, or a
/// plain scalar. The cursor is on the node's first character.
fn parse_flow_node(p : Parser) -> YamlValue raise YamlError {
  match peek(p).unwrap() {
    '[' => parse_flow_seq(p)
    '{' => parse_flow_map(p)
    '\'' => Str(scan_single_quoted(p))
    '"' => Str(scan_double_quoted(p))
    '&' => {
      let name = scan_name(p)
      skip_flow_ws(p)
      let value = parse_flow_node(p)
      p.anchors.set(name, value)
      value
    }
    '*' => {
      let name = scan_name(p)
      match p.anchors.get(name) {
        Some(v) => v
        None => raise err(p, "undefined alias '*\{name}'")
      }
    }
    '!' => raise err(p, "explicit tags are not supported")
    '?' => raise err(p, "explicit mapping keys (`? key`) are not supported")
    _ => {
      let text = scan_plain_segment(p, true)
      if text.length() == 0 {
        raise err(p, "expected a value inside flow collection")
      }
      resolve_plain(text)
    }
  }
}

///|
/// Parse a flow sequence; the cursor is on `[`.
fn parse_flow_seq(p : Parser) -> YamlValue raise YamlError {
  ignore(bump(p))
  let items : Array[YamlValue] = []
  while true {
    skip_flow_ws(p)
    match peek(p) {
      Some(']') => {
        ignore(bump(p))
        return Seq(items)
      }
      None => raise err(p, "unterminated flow sequence")
      _ => ()
    }
    items.push(parse_flow_node(p))
    skip_flow_ws(p)
    match peek(p) {
      Some(',') => ignore(bump(p))
      Some(']') => {
        ignore(bump(p))
        return Seq(items)
      }
      Some(c) =>
        raise err(p, "expected ',' or ']' in flow sequence, found '\{c}'")
      None => raise err(p, "unterminated flow sequence")
    }
  }
  abort("unreachable")
}

///|
/// Parse a flow mapping; the cursor is on `{`.
fn parse_flow_map(p : Parser) -> YamlValue raise YamlError {
  ignore(bump(p))
  let pairs : Array[YamlPair] = []
  while true {
    skip_flow_ws(p)
    match peek(p) {
      Some('}') => {
        ignore(bump(p))
        return Map(pairs)
      }
      None => raise err(p, "unterminated flow mapping")
      _ => ()
    }
    // key
    let key : YamlValue = match peek(p).unwrap() {
      '[' | '{' | '\'' | '"' | '&' | '*' => parse_flow_node(p)
      _ => {
        let text = scan_plain_segment(p, true)
        if text.length() == 0 {
          raise err(p, "expected a key inside flow mapping")
        }
        resolve_plain(text)
      }
    }
    let is_merge : Bool = match key {
      Str(s) => s == "<<"
      _ => false
    }
    skip_flow_ws(p)
    let value : YamlValue = match peek(p) {
      Some(':') => {
        ignore(bump(p))
        skip_flow_ws(p)
        match peek(p) {
          Some(',') | Some('}') => Null
          _ => parse_flow_node(p)
        }
      }
      _ => Null
    }
    if is_merge {
      apply_merge(p, pairs, value)
    } else {
      insert_pair(pairs, { key, value, })
    }
    skip_flow_ws(p)
    match peek(p) {
      Some(',') => ignore(bump(p))
      Some('}') => {
        ignore(bump(p))
        return Map(pairs)
      }
      Some(c) =>
        raise err(p, "expected ',' or '}' in flow mapping, found '\{c}'")
      None => raise err(p, "unterminated flow mapping")
    }
  }
  abort("unreachable")
}

// ---------------------------------------------------------------------------
// Document driver
// ---------------------------------------------------------------------------

///|
/// Parse all documents in the source text.
fn parse_documents(src : String) -> Array[YamlValue] raise YamlError {
  let normalized = src
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let p : Parser = {
    src: normalized,
    len: normalized.length(),
    idx: 0,
    line: 1,
    anchors: Map([], capacity=8),
  }
  // skip a UTF-8 BOM if present
  if p.len > 0 && peek(p) == Some('\u{feff}') {
    ignore(bump(p))
  }
  let docs : Array[YamlValue] = []
  while true {
    match seek_content(p) {
      Eof => return docs
      DocEnd => {
        consume_marker(p)
        continue
      }
      DocStart => {
        consume_marker(p)
        docs.push(parse_document_node(p))
        continue
      }
      Content(_) => {
        if docs.length() > 0 {
          raise err(p, "unexpected content between documents")
        }
        docs.push(parse_document_node(p))
        continue
      }
    }
  }
  abort("unreachable")
}

///|
/// Parse one document node; the cursor is just after a `---` marker or on
/// the first content character.
fn parse_document_node(p : Parser) -> YamlValue raise YamlError {
  // an inline node is only possible right after a marker on the same line
  let mid_line : Bool = p.idx > 0 && p.src.get_char(p.idx - 1) != Some('\n')
  if mid_line {
    skip_spaces(p)
    if !at_eol(p) && peek(p) != Some('#') {
      let v = parse_block_node(p, cur_col(p), -1)
      match seek_content(p) {
        Eof => return v
        DocStart | DocEnd => return v
        Content(_) => raise err(p, "unexpected content after document node")
      }
    }
  }
  match seek_content(p) {
    Content(col) => {
      let v = parse_block_node(p, col, -1)
      match seek_content(p) {
        Eof => return v
        DocStart | DocEnd => return v
        Content(_) => raise err(p, "unexpected content after document node")
      }
    }
    DocStart | DocEnd | Eof => return Null
  }
}
