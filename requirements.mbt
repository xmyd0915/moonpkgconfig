///|
/// Parse Requires/Requires.private/Conflicts expressions. No version solver yet.
pub fn parse_requirements(
  value : String,
  source? : String = "Requires",
) -> Result[Array[Requirement], Diagnostic] {
  let chars = value.to_array()
  let result : Array[Requirement] = []
  let mut i = 0
  while i < chars.length() {
    while i < chars.length() && (whitespace(chars[i]) || chars[i] == ',') {
      i = i + 1
    }
    if i == chars.length() {
      break
    }
    let start = i
    while i < chars.length() &&
          !whitespace(chars[i]) &&
          chars[i] != ',' &&
          !is_op(chars[i]) {
      i = i + 1
    }
    if i == start {
      return Err(
        diag("PC008", "Expected dependency name", {
          source,
          line: 1,
          column: i + 1,
        }),
      )
    }
    let name = chars_text(chars, start, i)
    while i < chars.length() && whitespace(chars[i]) {
      i = i + 1
    }
    let mut op = Any
    let mut version = ""
    if i < chars.length() && is_op(chars[i]) {
      let op_start = i
      while i < chars.length() && is_op(chars[i]) {
        i = i + 1
      }
      op = match chars_text(chars, op_start, i) {
        "=" => Equal
        "!=" => NotEqual
        "<" => Less
        "<=" => LessEqual
        ">" => Greater
        ">=" => GreaterEqual
        _ =>
          return Err(
            diag("PC008", "Invalid version operator", {
              source,
              line: 1,
              column: op_start + 1,
            }),
          )
      }
      while i < chars.length() && whitespace(chars[i]) {
        i = i + 1
      }
      let version_start = i
      while i < chars.length() && !whitespace(chars[i]) && chars[i] != ',' {
        i = i + 1
      }
      version = chars_text(chars, version_start, i)
      if version.is_empty() || version.iter().any(is_op) {
        return Err(
          diag("PC008", "Missing or malformed dependency version", {
            source,
            line: 1,
            column: version_start + 1,
          }),
        )
      }
    }
    result.push({ name, op, version, })
  }
  Ok(result)
}

///|
fn is_op(c : Char) -> Bool {
  c == '=' || c == '!' || c == '<' || c == '>'
}
