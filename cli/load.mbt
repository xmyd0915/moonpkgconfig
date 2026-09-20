///|
/// Filesystem result used by native command-line adapters.
pub(all) struct DirectoryLoad {
  packages : @pc.PackageSet
  package_ids : Array[String]
  diagnostics : Array[@pc.Diagnostic]
  file_count : Int
}

///|
/// Read every `.pc` file in one explicit directory. Package identifiers come
/// from filenames, matching the way pkg-config modules are normally named.
pub fn load_directory(directory : String) -> DirectoryLoad raise @fs.IOError {
  let packages = @pc.PackageSet::new()
  let package_ids : Array[String] = []
  let diagnostics : Array[@pc.Diagnostic] = []
  let names = @fs.read_dir(directory).to_owned()
  names.sort()
  let mut file_count = 0
  for name in names {
    if @path.Path(name).extname() != ".pc" {
      continue
    }
    file_count = file_count + 1
    let path = @path.Path(directory).join(@path.Path(name)).to_string()
    let content = @fs.read_file_to_string(path)
    let document = @pc.parse(content, source=path, pcfiledir=directory)
    for problem in document.diagnostics {
      diagnostics.push(problem)
    }
    if document.diagnostics.is_empty() {
      let id = name[0:name.length() - 3].to_owned()
      let problems = packages.add(id, document, source=path)
      if problems.is_empty() {
        package_ids.push(id)
      } else {
        for problem in problems {
          diagnostics.push(problem)
        }
      }
    }
  }
  { packages, package_ids, diagnostics, file_count, }
}
