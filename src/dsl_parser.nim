import std/[strutils, tables, math]
import ./types
import ./convert_to_samples

proc timeToFrames(t: float, sr: int): int =
  int(round(t * float(sr)))

proc parseTime(
  tokenNumber: var int, tokens: seq[string]
): seq[ClipTime] =
  result = @[]
  block timeBlock:
    while true:
      inc tokenNumber
      if tokenNumber > tokens.len - 1:
        break timeBlock
      let token = tokens[tokenNumber]
        
      if isDigit(token[^1]):
        inc tokenNumber
        case tokens[tokenNumber]
        of "ms", "milliseconds":
          result.add(ClipTime(
            kind: ClipTimeKind.MILLISECONDS,
            milliseconds: parseFloat(token)
          ))

        of "s", "seconds":
          result.add(ClipTime(
            kind: ClipTimeKind.SECONDS,
            seconds: parseFloat(token)
          ))

        of "m", "minutes":
          result.add(ClipTime(
            kind: ClipTimeKind.MINUTES,
            minutes: parseFloat(token)
          ))

        of "samples":
          result.add(ClipTime(
            kind: ClipTimeKind.SAMPLES,
            samples: parseInt(token)
          ))
        else:
          break timeBlock

      else:
        if token.endsWith("ms"):
          result.add(ClipTime(
            kind: CLipTimeKind.MILLISECONDS,
            milliseconds: parseFloat(token[0..^3])
          ))

        elif token.endsWith("samples"):
          result.add(ClipTime(
            kind: CLipTimeKind.SAMPLES,
            samples: parseInt(token[0..^8])
          ))

        elif token.endsWith("s"):
          result.add(ClipTime(
            kind: CLipTimeKind.SECONDS,
            seconds: parseFloat(token[0..^2])
          ))

        elif token.endsWith("m"):
          result.add(ClipTime(
            kind: CLipTimeKind.MINUTES,
            minutes: parseFloat(token[0..^2])
          ))
        else:
          break timeBlock

proc parseClipLine(
  line: string, 
  lineNumber: int,
  sampleRate: int, 
  aliases: Table[string, string]
): Query[Clip] =
  
  var outputClip = Clip(
    source: ClipSource(
      kind: SourceKind.FILE,
      file: ""
    ),
    destinationStart: @[],
    sourceStart: ClipStart(kind: ClipStartKind.START_FILE),
    sourceEnd: ClipEnd(kind: ClipEndKind.END_FILE),
    volume: (left: 1.0, right: 1.0)
  )

  let tokens = line.splitWhitespace()
  var i = 0

  while i < tokens.len:
    case tokens[i]
    of "AT":
      outputClip.destinationStart = parseTime(i, tokens)
      
    of "INSERT", "MIX":
      outputClip.mixing = if tokens[i] == "INSERT": ClipMixKind.INSERT else: ClipMixKind.MIX
      inc i
      if tokens[i] == "SINE":
        inc i
        let fstr = tokens[i]
        if fstr.endsWith("Hz"):
          outputClip.source = ClipSource(
            kind: SourceKind.SINE,
            sine: parseFloat(fstr[0 ..< fstr.len - 2])
          )
          inc i
        else:
          return Query[Clip](
            kind: QueryKind.FAILURE,
            failure: (line: lineNumber, msg: "Expected Hz in: " & line)
          )

      elif tokens[i] == "NOISE":
        outputClip.source = ClipSource(
          kind: SourceKind.NOISE
        )
        inc i
      
      else:
        outputClip.source = ClipSource(
          kind: SourceKind.FILE,
          file: aliases.getOrDefault(tokens[i], tokens[i])
        )
        inc i  

    of "FROM":
      outputClip.sourceStart = ClipStart(
        kind: ClipStartKind.TIME,
        time: parseTime(i, tokens)
      )

    of "TO":
      outputClip.sourceEnd = ClipEnd(
        kind: ClipEndKind.TIME,
        time: parseTime(i, tokens)
      )

    of "FOR":
      outputClip.sourceEnd = ClipEnd(
        kind: ClipEndKind.DURATION,
        duration: parseTime(i, tokens)
      )

    of "VOLUME":
      inc i
      if i < tokens.len:
        let vol = parseFloat(tokens[i])
        outputClip.volume = (left: vol, right: vol)

      inc i
      if i < tokens.len:
        outputClip.volume.right = parseFloat(tokens[i])
        inc i

    else:
      return Query[Clip](
        kind: QueryKind.FAILURE,
        failure: (
          line: lineNumber,
          msg: "Unknown token '" & tokens[i] & "' in: " & line
        )
      )

  return Query[Clip](
    kind: QueryKind.SUCCESS,
    success: outputClip
  )

proc parseOutputLength(line: string, sampleRate: int): int =
  let parsedLine = line.split(" ")[1..^1]
  var tokenNumber = -1
  return clipTimesToSamples(
    parseTime(tokenNumber, parsedLine), sampleRate
  )

proc parseFileAlias(aliases: var Table[string, string], line: string) =
  let splitLine = line.split(" ")
  if splitLine[0] == "FILE" and splitLine[2] == "ALIAS":
    aliases[splitLine[3]] = splitLine[1]

proc parseCollageFile*(
  filePath: string, sampleRate: int
): Collage = 
  result = Collage(
    sampleRate: sampleRate,
    lengthInSamples: 44100, # in samples 
    aliases: initTable[string, string](), 
    clips: initTable[string, seq[Clip]]() # organized by source
  )

  let lines = readFile(filePath).splitLines()

  for i, line in lines:
    let l = line.strip()
    if l.len == 0 or l.startsWith("//"):
      continue
    
    if l.startsWith("LENGTH"):
      result.lengthInSamples = parseOutputLength(l, sampleRate)

    elif l.startsWith("FILE"):
      parseFileAlias(result.aliases, l)

    else:
      let parsedClip: Query[Clip] = parseClipLine(
        l, i, sampleRate, result.aliases
      )
      if parsedClip.kind == QueryKind.SUCCESS:
        case parsedClip.success.source.kind 
        of SourceKind.FILE:
          result.clips.mgetOrPut(
            parsedClip.success.source.file, @[]
          ).add(parsedClip.success)

        of SourceKind.SINE:
          result.clips.mgetOrPut(
            "SINE", @[]
          ).add(parsedClip.success)

        of SourceKind.NOISE:
          result.clips.mgetOrPut(
            "NOISE", @[]
          ).add(parsedClip.success)
      else:
        quit(parsedClip.failure.msg) 
