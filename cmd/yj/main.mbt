// yj — convert between YAML and JSON.
//
//   yj config.yml           # YAML -> JSON (pretty-printed)
//   yj -r config.json       # JSON -> YAML
//   yj -e 'a: 1'            # convert a literal string
//   yj -a stream.yml        # all documents, as a JSON array

///|
/// CLI-level error (bad usage, unreadable file, invalid input).
suberror CliError {
  CliMsg(String)
}

///|
impl Show for CliError with fn output(self, logger) {
  match self {
    CliMsg(m) => logger.write_string(m)
  }
}

///|
const USAGE : String =
  #|yj 0.1.0 — convert between YAML and JSON
  #|
  #|Usage:
  #|  yj <file.yml>            YAML -> JSON (pretty-printed)
  #|  yj -r <file.json>        JSON -> YAML
  #|  yj -e '<text>'           convert a literal string instead of a file
  #|  yj -a <file.yml>         all documents, emitted as a JSON array
  #|
  #|Options:
  #|  -r, --reverse   JSON -> YAML (default is YAML -> JSON)
  #|  -e, --eval      argument is literal text, not a file path
  #|  -a, --all       convert every document in a multi-document stream
  #|  -c, --compact   compact (single-line) JSON output
  #|  -h, --help      show this help

///|
fn emit_json(j : Json, compact : Bool) -> Unit {
  if compact {
    println(j.stringify())
  } else {
    println(j.stringify(indent=2))
  }
}

///|
fn read_input(path : String) -> String raise CliError {
  if !@fs.path_exists(path) {
    raise CliMsg("yj: file not found: \{path}")
  }
  @fs.read_file_to_string(path) catch {
    _ => raise CliMsg("yj: cannot read \{path}")
  }
}

///|
fn run(args : Array[String]) -> Unit raise CliError {
  let mut reverse = false
  let mut literal = false
  let mut all = false
  let mut compact = false
  let mut input : String? = None
  for arg in args {
    match arg {
      "-r" | "--reverse" => reverse = true
      "-e" | "--eval" => literal = true
      "-a" | "--all" => all = true
      "-c" | "--compact" => compact = true
      "-h" | "--help" => {
        println(USAGE)
        return
      }
      _ => {
        if arg.length() > 0 && arg.get_char(0).unwrap() == '-' && arg != "-" {
          raise CliMsg("yj: unknown option: \{arg}")
        }
        if input is Some(_) {
          raise CliMsg("yj: unexpected extra argument: \{arg}")
        }
        input = Some(arg)
      }
    }
  }
  let text : String = match input {
    Some(t) => if literal { t } else { read_input(t) }
    None => raise CliMsg("yj: missing input")
  }
  if reverse {
    let json = @json.parse(text) catch { _ => raise CliMsg("yj: invalid JSON") }
    println(@yaml.YamlValue::from_json(json).to_yaml_string())
  } else if all {
    let docs = @yaml.parse_all(text) catch {
      _ => raise CliMsg("yj: invalid YAML")
    }
    let items : Array[Json] = []
    for doc in docs {
      items.push(doc.to_json())
    }
    emit_json(Json::array(items), compact)
  } else {
    let v = @yaml.parse(text) catch { _ => raise CliMsg("yj: invalid YAML") }
    emit_json(v.to_json(), compact)
  }
}

///|
fn main {
  let args = @env.args()
  // drop the program name (argv[0]) if present
  let rest : Array[String] = []
  for i, arg in args {
    if i == 0 {
      continue
    }
    rest.push(arg)
  }
  run(rest) catch {
    e => {
      println("\{e}")
      @sys.exit(1)
    }
  }
}
