///|
fn main {
  let input =
    #|prefix=/opt/example
    #|libdir=${prefix}/lib
    #|includedir=${prefix}/include
    #|Name: imagekit
    #|Description: Example C image library
    #|Version: 1.2.0
    #|Requires: codec >= 2.0
    #|Requires.private: compression >= 1.0
    #|Libs: -L${libdir} -limagekit
    #|Libs.private: -lm
    #|Cflags: -I${includedir} -DIMAGEKIT=1
  let document = @pc.parse(input, source="imagekit.pc")
  for
    field in [
      "Name", "Version", "Libs", "Cflags", "Requires", "Requires.private",
    ] {
    match document.field(field) {
      Some(e) =>
        println(
          "\{e.name}: \{e.value} [\{e.location.source}:\{e.location.line}]",
        )
      None => ()
    }
  }
  @debug.debug(document.diagnostics)
}
