///|
fn package_text(shape : String, size : Int, index : Int) -> String {
  let text = StringBuilder()
  text.write_string(
    "Name: p\{index}\nDescription: generated benchmark\nVersion: 1\n",
  )
  if index == 0 && (shape == "wide" || shape == "shared" || shape == "virtual") {
    text.write_string("Requires: ")
    let end = if shape == "shared" { size - 1 } else { size }
    for i = 1; i < end; i = i + 1 {
      if i > 1 {
        text.write_string(", ")
      }
      text.write_string(if shape == "virtual" { "v\{i} >= 1" } else { "p\{i}" })
    }
    text.write_string("\n")
  } else if (shape == "chain" || shape == "broken") && index + 1 < size {
    text.write_string("Requires: p\{index + 1}\n")
  } else if shape == "broken" && index + 1 == size {
    text.write_string("Requires: missing\n")
  } else if shape == "shared" && index > 0 && index + 1 < size {
    text.write_string("Requires: p\{size - 1}\n")
  }
  if shape == "virtual" && index > 0 {
    text.write_string("Provides: v\{index} = 1\n")
  }
  text.write_string("Cflags: -I/fixture/p\{index}\nLibs: -lp\{index}\n")
  text.to_string()
}

///|
fn main {
  let args = @env.args()
  if args.length() != 4 {
    println(
      "Usage: benchmark <chain|wide|shared|virtual|broken> <size> <load|resolve|cflags|path-last|paths|check>",
    )
    println(
      "       benchmark expansion <size> <expand-variable|expand-literal>",
    )
    @sys.exit(2)
  }
  let shape = args[1]
  let size = @string.parse_int(args[2]) catch { _ => 0 }
  let operation = args[3]
  if shape == "expansion" &&
    size >= 4 &&
    size <= 2097152 &&
    (operation == "expand-variable" || operation == "expand-literal") {
    let chunk = "x".repeat(size)
    let variables : Map[String, String] = { "chunk": chunk }
    let value = if operation == "expand-literal" { chunk } else { "${chunk}" }
    let start = @bench.monotonic_clock_start()
    let result = @pc.expand(value, variables, location={
      source: "boundary.pc",
      line: 1,
      column: 1,
    })
    let elapsed_us = @bench.monotonic_clock_end(start)
    let checksum = match result {
      Ok(value) => {
        if size > 1048576 || value.length() != size {
          abort("Incorrect expansion boundary")
        }
        size
      }
      Err(problem) => {
        if size <= 1048576 || problem.code != "PC009" {
          abort("Incorrect expansion rejection")
        }
        1
      }
    }
    println(
      Json::object({
        "shape": Json(shape),
        "size": Json(size),
        "operation": Json(operation),
        "load_us": Json(0),
        "elapsed_us": Json(elapsed_us),
        "checksum": Json(checksum),
      }).stringify(),
    )
    return
  }
  if size < 4 ||
    size > 100000 ||
    !(shape == "chain" ||
    shape == "broken" ||
    shape == "wide" ||
    shape == "shared" ||
    shape == "virtual") {
    println("Invalid benchmark shape or size (4..100000)")
    @sys.exit(2)
  }
  let start = @bench.monotonic_clock_start()
  let packages = @pc.PackageSet::new()
  for i = 0; i < size; i = i + 1 {
    let id = "p\{i}"
    let document = @pc.parse(package_text(shape, size, i), source=id + ".pc")
    if !packages.add(id, document).is_empty() {
      abort("Invalid generated package")
    }
  }
  let load_us = @bench.monotonic_clock_end(start)
  let start = @bench.monotonic_clock_start()
  let checksum : Int64 = match operation {
    "load" => size.to_int64()
    "resolve" => {
      let result = packages.resolve("p0")
      if !expected_diagnostics(result.diagnostics, shape) ||
        result.order.length() != size ||
        result.order[size - 1] != "p0" {
        abort("Incorrect resolution")
      }
      result.order.length().to_int64()
    }
    "cflags" => {
      let result = packages.collect_cflags("p0")
      if !expected_diagnostics(result.diagnostics, shape) ||
        result.flags.length() != size ||
        result.flags[0].package_id != "p0" {
        abort("Incorrect compiler flags")
      }
      result.flags.length().to_int64()
    }
    "path-last" => {
      let result = packages.dependency_path("p0", "p\{size - 1}")
      let expected = if shape == "chain" || shape == "broken" {
        size
      } else if shape == "shared" {
        3
      } else {
        2
      }
      if result.length() != expected ||
        result[0] != "p0" ||
        result[result.length() - 1] != "p\{size - 1}" {
        abort("Incorrect last dependency path")
      }
      result.length().to_int64()
    }
    "paths" => {
      let paths = packages.dependency_paths("p0")
      let mut length = 0L
      for i = 0; i < size; i = i + 1 {
        let path = paths.path_to("p\{i}")
        length = length + path.length().to_int64()
      }
      let expected = if shape == "chain" || shape == "broken" {
        size.to_int64() * (size.to_int64() + 1L) / 2L
      } else if shape == "shared" {
        size.to_int64() * 2L
      } else {
        size.to_int64() * 2L - 1L
      }
      if length != expected {
        abort("Incorrect dependency path lengths")
      }
      length
    }
    "check" => {
      if !expected_diagnostics(packages.check_all(), shape) {
        abort("Incorrect graph diagnostics")
      }
      size.to_int64()
    }
    _ => {
      println("Invalid benchmark operation")
      @sys.exit(2)
      0L
    }
  }
  let elapsed_us = if operation == "load" {
    load_us
  } else {
    @bench.monotonic_clock_end(start)
  }
  println(
    Json::object({
      "shape": Json(shape),
      "size": Json(size),
      "operation": Json(operation),
      "load_us": Json(load_us),
      "elapsed_us": Json(elapsed_us),
      "checksum": Json(checksum),
    }).stringify(),
  )
}

///|
fn expected_diagnostics(
  diagnostics : Array[@pc.Diagnostic],
  shape : String,
) -> Bool {
  if shape == "broken" {
    diagnostics.length() == 1 &&
    diagnostics[0].code == "PC015" &&
    diagnostics[0].message == "Required package not found: missing"
  } else {
    diagnostics.is_empty()
  }
}
