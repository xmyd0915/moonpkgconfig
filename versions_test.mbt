///|
test "version comparison handles numeric magnitude and leading zeroes" {
  @debug.assert_eq(@moonpkgconfig.compare_versions("1.9", "1.10"), -1)
  @debug.assert_eq(@moonpkgconfig.compare_versions("01.002", "1.2"), 0)
  @debug.assert_eq(@moonpkgconfig.compare_versions("2.0", "1.99"), 1)
}

///|
test "version comparison handles alpha separators and prerelease tilde" {
  @debug.assert_eq(@moonpkgconfig.compare_versions("1.0alpha", "1.0beta"), -1)
  @debug.assert_eq(@moonpkgconfig.compare_versions("1_0", "1.0"), 0)
  @debug.assert_eq(@moonpkgconfig.compare_versions("1.0~rc1", "1.0"), -1)
  @debug.assert_eq(@moonpkgconfig.compare_versions("1.0rc1", "1.0"), 1)
}

///|
test "requirements match installed package versions" {
  let requirements = @moonpkgconfig.parse_requirements(
    "a >= 1.2, b < 3, c = 01.0, d != 2, e, f <= 4, g > 5",
  ).unwrap()
  @debug.assert_eq(requirements[0].matches("1.10"), true)
  @debug.assert_eq(requirements[1].matches("3"), false)
  @debug.assert_eq(requirements[2].matches("1.0"), true)
  @debug.assert_eq(requirements[3].matches("2"), false)
  @debug.assert_eq(requirements[3].matches("2.0"), true)
  @debug.assert_eq(requirements[4].matches("anything"), true)
  @debug.assert_eq(requirements[5].matches("4"), true)
  @debug.assert_eq(requirements[6].matches("5~rc1"), false)
}
