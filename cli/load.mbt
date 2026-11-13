///|
/// Filesystem result used by native command-line adapters.
pub(all) struct DirectoryLoad {
  packages : @pc.PackageSet
  package_ids : Array[String]
  diagnostics : Array[@pc.Diagnostic]
  diagnostics_by_package : Map[String, Array[@pc.Diagnostic]]
  file_count : Int32
}

///|
/// Return parse or metadata diagnostics for one filename-derived package id.
pub fn DirectoryLoad::diagnostics_for(
  self : DirectoryLoad,
  package_id : String,
) -> Array[@pc.Diagnostic] {
  match self.diagnostics_by_package.get(package_id) {
    Some(problems) => problems.copy()
    None => []
  }
}

///|
fn failed_document(
  path : String,
  code : String,
  message : String,
) -> @pc.Document {
  {
    entries: [],
    diagnostics: [
      { code, message, location: { source: path, line: 1, column: 1, }, },
    ],
  }
}

///|
/// Read one UTF-8 metadata document. File IO errors retain the requested path;
/// invalid UTF-8 returns a diagnostic instead of parsing incomplete text.
/// The default pc_sysrootdir is an expansion input, not a source entry.
pub fn read_document(
  path : String,
  pcfiledir~ : String = ".",
  overrides~ : Map[String, String] = Map([]),
) -> @pc.Document raise @fs.IOError {
  let bytes = try {
    // Attribute lookup can lose its OS error on native Windows. Reject known
    // non-files, but let the actual open report failures of unknown paths.
    let regular = @fs.is_file(path) catch { @fs.IOError(_) => true }
    if !regular {
      raise @fs.IOError("Not a regular file")
    }
    @fs.read_file_to_bytes(path)
  } catch {
    @fs.IOError(message) =>
      raise @fs.IOError("Could not read metadata file \{path}: \{message}")
  }
  let content = @utf8.decode(bytes) catch {
    _ =>
      return failed_document(
        path,
        "PC020",
        "Metadata file is not valid UTF-8: \{path}",
      )
  }
  let effective_overrides = overrides.copy()
  if !effective_overrides.contains("pc_sysrootdir") {
    effective_overrides["pc_sysrootdir"] = ""
  }
  @pc.parse(content, source=path, pcfiledir~, overrides=effective_overrides)
}

///|
/// Read every `.pc` file in one explicit directory. Package identifiers come
/// from filenames, matching the way pkg-config modules are normally named.
pub fn load_directory(
  directory : String,
  overrides~ : Map[String, String] = Map([]),
) -> DirectoryLoad raise @fs.IOError {
  load_directories([directory], overrides~)
}

///|
/// Read `.pc` files from ordered search directories. The first file seen for
/// each package id wins, including when that file contains diagnostics.
pub fn load_directories(
  directories : Array[String],
  overrides~ : Map[String, String] = Map([]),
) -> DirectoryLoad raise @fs.IOError {
  let packages = @pc.PackageSet::new()
  let package_ids : Array[String] = []
  let diagnostics : Array[@pc.Diagnostic] = []
  let diagnostics_by_package : Map[String, Array[@pc.Diagnostic]] = Map([])
  let seen_files : Map[String, Bool] = Map([])
  let mut file_count = 0
  for directory in directories {
    let names = try {
      if !@fs.path_exists(directory) {
        raise @fs.IOError("Path does not exist or cannot be accessed")
      }
      if !@fs.is_dir(directory) {
        raise @fs.IOError("Not a directory")
      }
      @fs.read_dir(directory).to_owned()
    } catch {
      @fs.IOError(message) => {
        let reason = match message {
          "" | "No error" | "Success" =>
            "Directory access failed; filesystem did not provide an error reason"
          _ => message
        }
        raise @fs.IOError(
          "Could not read search directory \{directory}: \{reason}",
        )
      }
    }
    names.sort()
    for name in names {
      if @path.Path(name).extname() != ".pc" {
        continue
      }
      file_count = file_count + 1
      let id = name[0:name.length() - 3].to_owned()
      if seen_files.contains(id) {
        continue
      }
      seen_files[id] = true
      let path = @path.Path(directory).join(@path.Path(name)).to_string()
      let document = read_document(path, pcfiledir=directory, overrides~) catch {
        @fs.IOError(message) => failed_document(path, "PC019", message)
      }
      let file_diagnostics = document.diagnostics.copy()
      for problem in document.diagnostics {
        diagnostics.push(problem)
      }
      if document.diagnostics.is_empty() {
        let problems = packages.add(id, document, source=path)
        if problems.is_empty() {
          package_ids.push(id)
        } else {
          for problem in problems {
            diagnostics.push(problem)
            file_diagnostics.push(problem)
          }
        }
      }
      if !file_diagnostics.is_empty() {
        diagnostics_by_package[id] = file_diagnostics
      }
    }
  }
  { packages, package_ids, diagnostics, diagnostics_by_package, file_count, }
}
