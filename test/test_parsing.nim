import std/[unittest]
import ../src/dsl_parser

suite "Time parsing: milliseconds":
  test "split ms":
    var tokenCounter = -1
    let actual = parseTime(tokenCounter, @["0.2", "ms"])[0]
    check(actual.kind == ClipTimeKind.MILLISECONDS)
    check(actual.milliseconds == 0.2)
  test "split milliseconds":
    var tokenCounter = -1
    let actual = parseTime(tokenCounter, @["2", "milliseconds"])[0]
    check(actual.kind == ClipTimeKind.MILLISECONDS)
    check(actual.milliseconds == 2.0)
  test "combined ms":
    var tokenCounter = -1
    let actual = parseTime(tokenCounter, @["8ms"])[0]
    check(actual.kind == ClipTimeKind.MILLISECONDS)
    check(actual.milliseconds == 8.0)

suite "Time parsing: seconds":
  test "split s":
    var tokenCounter = -1
    let actual = parseTime(tokenCounter, @["0.2", "s"])[0]
    check(actual.kind == ClipTimeKind.SECONDS)
    check(actual.seconds == 0.2)
  test "split seconds":
    var tokenCounter = -1
    let actual = parseTime(tokenCounter, @["0.2", "seconds"])[0]
    check(actual.kind == ClipTimeKind.SECONDS)
    check(actual.seconds == 0.2)
  test "combined s":
    var tokenCounter = -1
    let actual = parseTime(tokenCounter, @["0.2s"])[0]
    check(actual.kind == ClipTimeKind.SECONDS)
    check(actual.seconds == 0.2)
    
suite "Time parsing: minutes":
  test "split m":
    var tokenCounter = -1
    let actual = parseTime(tokenCounter, @["1.5", "m"])[0]
    check(actual.kind == ClipTimeKind.MINUTES)
    check(actual.minutes == 1.5)
  test "split minutes":
    var tokenCounter = -1
    let actual = parseTime(tokenCounter, @["1.5", "minutes"])[0]
    check(actual.kind == ClipTimeKind.MINUTES)
    check(actual.minutes == 1.5)
  test "combined s":
    var tokenCounter = -1
    let actual = parseTime(tokenCounter, @["1.5m"])[0]
    check(actual.kind == ClipTimeKind.MINUTES)
    check(actual.minutes == 1.5)

suite "Time parsing: samples":
  test "split samples":
    var tokenCounter = -1
    let actual = parseTime(tokenCounter, @["15", "samples"])[0]
    check(actual.kind == ClipTimeKind.SAMPLES)
    check(actual.samples == 15)
