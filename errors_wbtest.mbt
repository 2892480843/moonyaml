// Error-reporting tests: malformed input must fail with useful messages.

///|
fn expect_error(yaml : String, fragment : String) -> Unit {
  try {
    let _ = parse(yaml)
    abort("expected an error containing '\{fragment}', got success")
  } catch {
    e => {
      let msg = "\{e}"
      if !msg.contains(fragment) {
        abort("error message '\{msg}' does not contain '\{fragment}'")
      }
    }
  }
}

///|
test "tab in indentation" {
  expect_error("a:\n\tb: 1\n", "tab")
}

///|
test "undefined alias" {
  expect_error("a: *missing\n", "undefined alias")
}

///|
test "explicit tags rejected" {
  expect_error("a: !!str 123\n", "tags")
}

///|
test "explicit key rejected" {
  expect_error("? complex\n: value\n", "explicit")
}

///|
test "unterminated quote" {
  expect_error("a: 'unclosed\n", "unterminated")
  expect_error("a: \"unclosed\n", "unterminated")
}

///|
test "unterminated flow" {
  expect_error("a: [1, 2\n", "flow")
  expect_error("a: {x: 1\n", "flow")
}

///|
test "missing key separator" {
  expect_error("a: 1\nb\n", "expected ':'")
}

///|
test "bad indentation" {
  expect_error("a: 1\n  b: 2\n", "bad indentation")
}

///|
test "content after document node" {
  expect_error(
    "--- [1, 2]\nstray content\n", "unexpected content after document",
  )
}

///|
test "error carries line number" {
  try {
    let _ = parse("a: 1\nb: 2\n\tc: 3\n")
    abort("expected error")
  } catch {
    e => {
      let msg = "\{e}"
      if !msg.contains("line 3") {
        abort("expected line 3 in '\{msg}'")
      }
    }
  }
}
