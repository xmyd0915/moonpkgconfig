///|
/// Select one of the conventional pkg-config compiler or linker flag groups.
pub(all) enum FlagSelection {
  IncludePaths
  OtherCflags
  LibraryPaths
  Libraries
  OtherLibs
} derive(Eq, @debug.Debug)

///|
/// Keep selected arguments in their original order, with origins and diagnostics.
///
/// Split options retain their operands when both come from the same field.
/// IncludePaths selects -I, while OtherCflags retains -isystem and other options.
/// LibraryPaths selects -L, Libraries selects -l, and OtherLibs retains the rest.
/// GNU linker start/end groups remain intact in OtherLibs.
/// The returned flags are compiler arguments, including their option prefixes.
pub fn FlagResult::select(
  self : FlagResult,
  selection : FlagSelection,
) -> FlagResult {
  let flags : Array[ResolvedFlag] = []
  let mut i = 0
  while i < self.flags.length() {
    let flag = self.flags[i]
    let include_path = flag.value.has_prefix("-I")
    let library_path = flag.value.has_prefix("-L")
    // pkgconf treats MSVC's -lib: spelling as an opaque argument.
    let library = flag.value.has_prefix("-l") && !flag.value.has_prefix("-lib:")
    let keep = match selection {
      IncludePaths => include_path
      OtherCflags => !include_path
      LibraryPaths => library_path
      Libraries => library
      OtherLibs => !library_path && !library
    }
    let end = flag_group_end(self.flags, i)
    if keep {
      for j = i; j < end; j = j + 1 {
        flags.push(self.flags[j])
      }
    }
    i = end
  }
  { flags, diagnostics: self.diagnostics.copy(), }
}

///|
fn flag_group_end(flags : Array[ResolvedFlag], start : Int32) -> Int32 {
  let first = flags[start]
  let mut end = start + 1
  if first.value == "-Wl,--start-group" {
    let mut depth = 1
    while end < flags.length() && same_flag_origin(first, flags[end]) {
      let value = flags[end].value
      end = end + 1
      if value == "-Wl,--start-group" {
        depth = depth + 1
      } else if value == "-Wl,--end-group" {
        depth = depth - 1
        if depth == 0 {
          break
        }
      }
    }
  } else if option_takes_operand(first.value) &&
    end < flags.length() &&
    same_flag_origin(first, flags[end]) {
    end = end + 1
  }
  end
}

///|
fn option_takes_operand(value : String) -> Bool {
  match value {
    "-I"
    | "-L"
    | "-l"
    | "-isystem"
    | "-idirafter"
    | "-iquote"
    | "-include"
    | "-imacros"
    | "-framework"
    | "-Xlinker"
    | "-Xassembler"
    | "-Xpreprocessor"
    | "-arch" => true
    _ => false
  }
}
