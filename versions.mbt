///|
/// Compare two package versions using the segment rules used by pkg-config
/// implementations: separators are ignored, numeric segments compare by
/// magnitude, numeric segments sort after alphabetic segments, and `~` sorts
/// before every other segment.
///
/// The result is negative, zero, or positive when `left` is respectively less
/// than, equal to, or greater than `right`.
pub fn compare_versions(left : String, right : String) -> Int {
  let a = left.to_array()
  let b = right.to_array()
  let mut ai = 0
  let mut bi = 0
  while true {
    while ai < a.length() && !version_alnum(a[ai]) && a[ai] != '~' {
      ai = ai + 1
    }
    while bi < b.length() && !version_alnum(b[bi]) && b[bi] != '~' {
      bi = bi + 1
    }
    if (ai < a.length() && a[ai] == '~') || (bi < b.length() && b[bi] == '~') {
      if ai >= a.length() || a[ai] != '~' {
        return 1
      }
      if bi >= b.length() || b[bi] != '~' {
        return -1
      }
      ai = ai + 1
      bi = bi + 1
      continue
    }
    if ai >= a.length() || bi >= b.length() {
      break
    }
    let a_numeric = version_digit(a[ai])
    let b_numeric = version_digit(b[bi])
    if a_numeric && !b_numeric {
      return 1
    }
    if !a_numeric && b_numeric {
      return -1
    }
    let mut a_end = ai
    let mut b_end = bi
    if a_numeric {
      while a_end < a.length() && version_digit(a[a_end]) {
        a_end = a_end + 1
      }
      while b_end < b.length() && version_digit(b[b_end]) {
        b_end = b_end + 1
      }
      let mut a_value = ai
      let mut b_value = bi
      while a_value < a_end && a[a_value] == '0' {
        a_value = a_value + 1
      }
      while b_value < b_end && b[b_value] == '0' {
        b_value = b_value + 1
      }
      let a_length = a_end - a_value
      let b_length = b_end - b_value
      if a_length != b_length {
        return if a_length < b_length { -1 } else { 1 }
      }
      let mut offset = 0
      while offset < a_length {
        if a[a_value + offset] != b[b_value + offset] {
          return if a[a_value + offset] < b[b_value + offset] { -1 } else { 1 }
        }
        offset = offset + 1
      }
    } else {
      while a_end < a.length() && version_alpha(a[a_end]) {
        a_end = a_end + 1
      }
      while b_end < b.length() && version_alpha(b[b_end]) {
        b_end = b_end + 1
      }
      let mut offset = 0
      let common = if a_end - ai < b_end - bi { a_end - ai } else { b_end - bi }
      while offset < common {
        if a[ai + offset] != b[bi + offset] {
          return if a[ai + offset] < b[bi + offset] { -1 } else { 1 }
        }
        offset = offset + 1
      }
      if a_end - ai != b_end - bi {
        return if a_end - ai < b_end - bi { -1 } else { 1 }
      }
    }
    ai = a_end
    bi = b_end
  }
  while ai < a.length() && !version_alnum(a[ai]) && a[ai] != '~' {
    ai = ai + 1
  }
  while bi < b.length() && !version_alnum(b[bi]) && b[bi] != '~' {
    bi = bi + 1
  }
  if ai < a.length() && a[ai] == '~' {
    return -1
  }
  if bi < b.length() && b[bi] == '~' {
    return 1
  }
  if ai < a.length() {
    1
  } else if bi < b.length() {
    -1
  } else {
    0
  }
}

///|
/// Test an installed version against one parsed dependency requirement.
pub fn Requirement::matches(
  self : Requirement,
  installed_version : String,
) -> Bool {
  if self.op == Any {
    return true
  }
  let order = compare_versions(installed_version, self.version)
  match self.op {
    Any => true
    Equal => order == 0
    NotEqual => order != 0
    Less => order < 0
    LessEqual => order <= 0
    Greater => order > 0
    GreaterEqual => order >= 0
  }
}

///|
fn version_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn version_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn version_alnum(c : Char) -> Bool {
  version_digit(c) || version_alpha(c)
}
