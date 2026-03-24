import std/[tables]

type
  AudioBuffer* = object
    sampleRate*: int
    channels*: int
    data*: seq[float]

type
  SourceKind* {.pure.} = enum
    FILE, SINE, NOISE

  ClipSource* = object
    case kind*: SourceKind
    of SourceKind.FILE:
      file*: string # file path or alias
    of SourceKind.SINE:
      sine*: float # for sine
    of SourceKind.NOISE: discard

type
  ClipTimeKind* {.pure.} = enum
    SAMPLES, SECONDS, MILLISECONDS, MINUTES

  ClipTime* = object
    case kind*: ClipTimeKind
    of ClipTimeKind.SAMPLES:
      samples*: int
    of ClipTimeKind.SECONDS:
      seconds*: float
    of ClipTimeKind.MILLISECONDS:
      milliseconds*: float
    of ClipTimeKind.MINUTES:
      minutes*: float

type
  ClipStartKind* {.pure.} = enum
    START_FILE, TIME

  ClipStart* = object
    case kind*: ClipStartKind
    of ClipStartKind.TIME:
      time*: seq[ClipTime]
    of ClipStartKind.START_FILE: discard

type
  ClipEndKind* {.pure.} = enum
    TIME, DURATION, END_FILE

  ClipEnd* = object
    case kind*: ClipEndKind
    of ClipEndKind.TIME:
      time*: seq[ClipTime]
    of ClipEndKind.DURATION:
      duration*: seq[ClipTime]
    of ClipEndKind.END_FILE: discard

type
  ClipMixKind* {.pure.} = enum
    INSERT, MIX 

type
  Clip* = object
    source*: ClipSource
    destinationStart*: seq[ClipTime]
    sourceStart*: ClipStart
    sourceEnd*: ClipEnd
    mixing*: ClipMixKind
    volume*: tuple[left, right: float]

type
  ClipSamples* = object
    destinationStart*: int
    sourceStart*: int
    sourceEnd*: int
    mixing*: ClipMixKind
    volume*: tuple[left, right: float]

type
  QueryKind* {.pure.} = enum
    SUCCESS, FAILURE

  Query*[T] = object
    case kind*: QueryKind
    of QueryKind.SUCCESS:
      success*: T
    of QueryKind.FAILURE:
      failure*: tuple[line: int, msg: string]
type
  Collage* = object
    sampleRate*: int
    lengthInSamples*: int
    aliases*: Table[string, string]
    clips*: Table[string, seq[Clip]]
