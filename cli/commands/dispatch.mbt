///|
fn usage() -> Unit {
  println("Usage: moonpkgconfig <inspect|query|check> [arguments]")
  println("  inspect <file.pc> [--json]")
  println("  query <directory> <package> <mode> [options]")
  println("  check <directory> [--path <directory>]... [--json]")
  println("Use moonpkgconfig <command> --help for command options.")
}

///|
/// Run the installed command with process arguments, including argv[0].
pub fn run(args : Array[String]) -> Unit {
  if args.length() < 2 {
    usage()
    @sys.exit(2)
    return
  }
  if args[1] == "--help" || args[1] == "-h" {
    usage()
    return
  }
  let command_args = [args[1]]
  for i = 2; i < args.length(); i = i + 1 {
    command_args.push(args[i])
  }
  match args[1] {
    "inspect" => inspect(command_args, command="moonpkgconfig inspect")
    "query" => query(command_args, command="moonpkgconfig query")
    "check" => check(command_args, command="moonpkgconfig check")
    _ => {
      println("Unknown command: \{args[1]}")
      usage()
      @sys.exit(2)
    }
  }
}
