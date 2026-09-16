///| Tokenize compiler/linker fragments without executing shell expansion.

///|
/// Supports quoted spaces, empty arguments and escaped characters.
pub fn split_flags(
  value : String,
  source? : String = "flags",
) -> Result[Array[String], Diagnostic] {
  let chars = value.to_array()
  let result : Array[String] = []
  let token = StringBuilder()
  let mut quote : Char? = None
  let mut started = false
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '\\' && quote != Some('\'') {
      if i + 1 == chars.length() {
        return Err(
          diag("PC007", "Trailing escape in flags", {
            source,
            line: 1,
            column: i + 1,
          }),
        )
      }
      let next = chars[i + 1]
      if quote == Some('"') &&
        next != '"' &&
        next != '\\' &&
        next != '$' &&
        next != '`' &&
        next != '\n' {
        token.write_char('\\')
      }
      if next != '\n' {
        token.write_char(next)
      }
      started = true
      i = i + 2
      continue
    }
    match quote {
      Some(q) => if c == q { quote = None } else { token.write_char(c) }
      None =>
        if c == '\'' || c == '"' {
          quote = Some(c)
          started = true
        } else if whitespace(c) {
          if started {
            result.push(token.to_string())
            token.reset()
            started = false
          }
        } else {
          token.write_char(c)
          started = true
        }
    }
    i = i + 1
  }
  if quote != None {
    return Err(
      diag("PC006", "Unclosed quote in flags", {
        source,
        line: 1,
        column: chars.length() + 1,
      }),
    )
  }
  if started {
    result.push(token.to_string())
  }
  Ok(result)
}
