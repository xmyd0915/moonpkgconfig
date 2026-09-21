///|
/// Filesystem result used by native command-line adapters.
pub(all) struct DirectoryLoad {
  packages : @pc.PackageSet
  package_ids : Array[String]
  diagnostics : Array[@pc.Diagnostic]
  diagnostics_by_package : Map[String, Array[@pc.Diagnostic]]
  file_count : Int
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
/// Read every `.pc` file in one explicit directory. Package identifiers come
/// from filenames, matching the way pkg-config modules are normally named.
pub fn load_directory(directory : String) -> DirectoryLoad raise @fs.IOError {
  let packages = @pc.PackageSet::new()
  let package_ids : Array[String] = []
  let diagnostics : Array[@pc.Diagnostic] = []
  let diagnostics_by_package : Map[String, Array[@pc.Diagnostic]] = Map([])
  let names = @fs.read_dir(directory).to_owned()
  names.sort()
  let mut file_count = 0
  for name in names {
    if @path.Path(name).extname() != ".pc" {
      continue
    }
    file_count = file_count + 1
    let id = name[0:name.length() - 3].to_owned()
    let path = @path.Path(directory).join(@path.Path(name)).to_string()
    let content = @fs.read_file_to_string(path)
    let document = @pc.parse(content, source=path, pcfiledir=directory)
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
  { packages, package_ids, diagnostics, diagnostics_by_package, file_count, }
}
