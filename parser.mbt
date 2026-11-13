///| Expand only variables defined earlier, as pkg-config does.

///|
/// The map can include caller-provided builtins such as pcfiledir.
pub fn expand(
  value : String,
  variables : Map[String, String],
  location~ : Location,
) -> Result[String, Diagnostic] {
  expand_limited(
    value, variables, location, 1048576, "Expanded value exceeds 1 Mi UTF-16 code units",
  )
}

///|
fn expand_limited(
  value : String,
  variables : Map[String, String],
  location : Location,
  limit : Int32,
  limit_message : String,
) -> Result[String, Diagnostic] {
  let chars = value.to_array()
  let out = StringBuilder()
  let mut expanded_length = 0
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '$' && i + 1 < chars.length() && chars[i + 1] == '$' {
      if expanded_length == limit {
        return Err(diag("PC009", limit_message, location))
      }
      out.write_char('$')
      expanded_length = expanded_length + 1
      i = i + 2
    } else if chars[i] == '$' && i + 1 < chars.length() && chars[i + 1] == '{' {
      let start = i
      i = i + 2
      let name_start = i
      while i < chars.length() && chars[i] != '}' {
        i = i + 1
      }
      let at = { ..location, column: location.column + start, }
      if i == chars.length() {
        return Err(diag("PC003", "Unclosed variable reference", at))
      }
      let name = chars_text(chars, name_start, i)
      match variables.get(name) {
        Some(v) => {
          if v.length() > limit - expanded_length {
            return Err(diag("PC009", limit_message, location))
          }
          expanded_length = expanded_length + v.length()
          out.write_string(v)
        }
        None => return Err(diag("PC004", "Undefined variable: " + name, at))
      }
      i = i + 1
    } else {
      let width = if chars[i].to_int() > 65535 { 2 } else { 1 }
      if width > limit - expanded_length {
        return Err(diag("PC009", limit_message, location))
      }
      out.write_char(chars[i])
      expanded_length = expanded_length + width
      i = i + 1
    }
  }
  Ok(out.to_string())
}

///|
// String lengths and both expansion limits count UTF-16 code units, not bytes.
priv struct ExpansionBudget {
  mut remaining : Int32
  mut exhausted : Bool
}

///|
fn valid_key(name : String) -> Bool {
  !name.is_empty() &&
  name
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_' ||
    c == '.' ||
    c == '-'
  })
}

///| Parse .pc syntax with ordered substitution, comments and continuations.

///|
/// Deliberately strict about duplicate definitions and undefined variables.
pub fn parse(
  content : String,
  source~ : String = "input.pc",
  pcfiledir~ : String = ".",
  overrides~ : Map[String, String] = Map([]),
) -> Document {
  let entries : Array[Entry] = []
  let diagnostics : Array[Diagnostic] = []
  let budget = { remaining: 1048576, exhausted: false, }
  let variables : Map[String, String] = { "pcfiledir": pcfiledir }
  for name, value in overrides {
    if name != "pcfiledir" {
      variables[name] = value
    }
  }
  let defined_variables : Map[String, Bool] = Map([])
  let fields : Map[String, Bool] = Map([])
  let chars = content.to_array()
  let line = StringBuilder()
  let mut physical_line = 1
  let mut start_line = 1
  let mut i = if chars.length() > 0 && chars[0] == '\u{FEFF}' { 1 } else { 0 }
  while i < chars.length() {
    let c = chars[i]
    if c == '\\' && i + 1 < chars.length() {
      let next = chars[i + 1]
      if next == '\n' ||
        (next == '\r' && i + 2 < chars.length() && chars[i + 2] == '\n') {
        physical_line = physical_line + 1
        i = i + (if next == '\r' { 3 } else { 2 })
        continue
      }
      // Escaped hashes are literal, other escapes belong to the fragment parser.
      if next == '#' {
        line.write_char('#')
      } else {
        line.write_char(c)
        line.write_char(next)
      }
      i = i + 2
      continue
    }
    if c == '#' {
      while i < chars.length() && chars[i] != '\n' {
        i = i + 1
      }
      continue
    }
    if c == '\n' {
      parse_line(
        line.to_string(),
        source,
        start_line,
        variables,
        overrides,
        defined_variables,
        fields,
        entries,
        diagnostics,
        budget,
      )
      limit_document_diagnostics(diagnostics, budget)
      if budget.exhausted {
        break
      }
      line.reset()
      physical_line = physical_line + 1
      start_line = physical_line
    } else {
      line.write_char(c)
    }
    i = i + 1
  }
  parse_line(
    line.to_string(),
    source,
    start_line,
    variables,
    overrides,
    defined_variables,
    fields,
    entries,
    diagnostics,
    budget,
  )
  limit_document_diagnostics(diagnostics, budget)
  { entries, diagnostics, }
}

///|
fn limit_document_diagnostics(
  diagnostics : Array[Diagnostic],
  budget : ExpansionBudget,
) -> Unit {
  if diagnostics.length() > 100 && diagnostics[100].code != "PC021" {
    let omitted = diagnostics.pop().unwrap()
    diagnostics.push(
      diag(
        "PC021",
        "Diagnostic limit of 100 reached; parsing stopped before further diagnostics",
        omitted.location,
      ),
    )
    budget.exhausted = true
  }
}

///|
fn parse_line(
  text : String,
  source : String,
  line_number : Int32,
  variables : Map[String, String],
  overrides : Map[String, String],
  defined_variables : Map[String, Bool],
  fields : Map[String, Bool],
  entries : Array[Entry],
  diagnostics : Array[Diagnostic],
  budget : ExpansionBudget,
) -> Unit {
  if budget.exhausted || text.is_blank() {
    return
  }
  let chars = text.to_array()
  let mut start = 0
  while start < chars.length() && whitespace(chars[start]) {
    start = start + 1
  }
  let location = { source, line: line_number, column: start + 1, }
  let mut split = start
  while split < chars.length() && chars[split] != '=' && chars[split] != ':' {
    split = split + 1
  }
  if split == chars.length() {
    diagnostics.push(
      diag("PC001", "Expected variable=value or Field: value", location),
    )
    return
  }
  let name = chars_text(chars, start, split).trim().to_owned()
  if !valid_key(name) {
    diagnostics.push(diag("PC002", "Invalid key: " + name, location))
    return
  }
  let kind = if chars[split] == '=' { Variable } else { Field }
  let field_name = field_key(name)
  if (
      kind == Variable &&
      (name == "pcfiledir" || defined_variables.contains(name))
    ) ||
    (kind == Field && fields.contains(field_name)) {
    diagnostics.push(
      diag("PC005", "Duplicate or reserved definition: " + name, location),
    )
    return
  }
  let mut value_start = split + 1
  while value_start < chars.length() && whitespace(chars[value_start]) {
    value_start = value_start + 1
  }
  let raw = chars_text(chars, value_start, chars.length()).trim_end().to_owned()
  let value_location = { ..location, column: value_start + 1, }
  let document_limited = budget.remaining < 1048576
  let limit = if document_limited { budget.remaining } else { 1048576 }
  let limit_message = if document_limited {
    "Document expansion exceeds 1 Mi UTF-16 code units"
  } else {
    "Expanded value exceeds 1 Mi UTF-16 code units"
  }
  match expand_limited(raw, variables, value_location, limit, limit_message) {
    Err(d) => {
      diagnostics.push(d)
      if d.code == "PC009" {
        budget.exhausted = true
      }
    }
    Ok(expanded_value) => {
      let value = match kind {
        Variable => overrides.get(name).unwrap_or(expanded_value)
        Field => expanded_value
      }
      // Overrides must not bypass either limit. Count discarded expansion work
      // too, so many overridden values cannot repeatedly consume the budget.
      let size = if value.length() > expanded_value.length() {
        value.length()
      } else {
        expanded_value.length()
      }
      if size > limit {
        diagnostics.push(diag("PC009", limit_message, value_location))
        budget.exhausted = true
        return
      }
      budget.remaining = budget.remaining - size
      entries.push({ kind, name, raw, value, location, value_location, })
      match kind {
        Variable => {
          variables[name] = value
          defined_variables[name] = true
        }
        Field => fields[field_name] = true
      }
    }
  }
}
