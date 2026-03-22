import std/[os, strutils, parseutils, tables, math, sequtils]

type
  AudioBuffer = object
    sampleRate: int
    channels: int
    data: seq[float]

  Clip = object
    startSrcFrames: int
    lengthFrames: int   # -1 = until end
    startDstFrames: int
    volL: float
    volR: float

  Project = object
    lengthFrames: int
    clipsBySource: Table[string, seq[Clip]]

# ---------------- TIME ----------------

proc parseTime(s: string): float =
  var val: float
  discard parseFloat(s.replace("s",""), val)
  val

proc timeToFrames(t: float, sr: int): int =
  int(round(t * float(sr)))

# ---------------- WAV ----------------

proc readInt16LE(data: string, pos: int): int16 =
  cast[int16](ord(data[pos]) or (ord(data[pos+1]) shl 8))

proc readInt32LE(data: string, pos: int): int32 =
  cast[int32](ord(data[pos]) or (ord(data[pos+1]) shl 8) or
              (ord(data[pos+2]) shl 16) or (ord(data[pos+3]) shl 24))

proc loadWav(path: string): AudioBuffer =
  let bytes = readFile(path)

  var pos = 12
  var sampleRate = 44100
  var channels = 1
  var dataStart = 0
  var dataSize = 0

  while pos + 8 <= bytes.len:
    let id = bytes[pos..pos+3]
    let size = readInt32LE(bytes, pos+4)

    if id == "fmt ":
      channels = int(readInt16LE(bytes, pos+10))
      sampleRate = int(readInt32LE(bytes, pos+12))
    elif id == "data":
      dataStart = pos + 8
      dataSize = size
      break

    pos += 8 + int(size)

  let sampleCount = dataSize div 2
  var it = -1
  let samples = newSeqWith(sampleCount):
    it += 1
    readInt16LE(bytes, dataStart + it * 2).float / 32768.0

  AudioBuffer(sampleRate: sampleRate, channels: channels, data: samples)

# ---------------- RESAMPLE ----------------

proc resample(buf: AudioBuffer, newRate: int): AudioBuffer =
  if buf.sampleRate == newRate:
    return buf

  let ch = buf.channels
  let inFrames = buf.data.len div ch
  let ratio = newRate.float / buf.sampleRate.float
  let outFrames = int(round(inFrames.float * ratio))

  var outData = newSeq[float](outFrames * ch)

  for i in 0..<outFrames:
    let srcPos = i.float / ratio
    let i0 = int(srcPos)
    let i1 = min(i0 + 1, inFrames - 1)
    let t = srcPos - i0.float

    for c in 0..<ch:
      let s0 = buf.data[i0 * ch + c]
      let s1 = buf.data[i1 * ch + c]
      outData[i * ch + c] = s0*(1-t) + s1*t

  AudioBuffer(sampleRate: newRate, channels: ch, data: outData)

proc toStereo(buf: AudioBuffer): AudioBuffer =
  if buf.channels == 2:
    return buf

  var it = 0
  let outData = newSeqWith(buf.data.len * 2):
    let i = it div 2
    buf.data[i]

  AudioBuffer(sampleRate: buf.sampleRate, channels: 2, data: outData)

# ---------------- PARSING ----------------

proc parseClip(line: string, sr: int, aliases: Table[string,string]): (string, Clip) =
  let parts = line.split("@")
  if parts.len != 2:
    quit("Invalid line: " & line)

  let left = parts[0].strip()
  let right = parts[1].strip()

  var startDstFrames: int
  var srcPart: string
  var volPart = ""

  if left.endsWith("s"):
    startDstFrames = timeToFrames(parseTime(left), sr)
    srcPart = right
  else:
    let rparts = right.split("*")
    startDstFrames = timeToFrames(parseTime(rparts[0].strip()), sr)
    srcPart = left
    if rparts.len > 1: volPart = rparts[1]

  if srcPart.contains("*"):
    let sp = srcPart.split("*")
    srcPart = sp[0].strip()
    volPart = sp[1]

  var volL = 1.0
  var volR = 1.0

  if volPart.len > 0:
    let v = volPart.strip().splitWhitespace()
    if v.len == 1:
      volL = parseFloat(v[0])
      volR = volL
    elif v.len == 2:
      volL = parseFloat(v[0])
      volR = parseFloat(v[1])

  let tokens = srcPart.splitWhitespace()
  let src = aliases.getOrDefault(tokens[0], tokens[0])

  var startSrcFrames = 0
  var lengthFrames = -1

  if tokens.len >= 2:
    startSrcFrames = timeToFrames(parseTime(tokens[1]), sr)

  if tokens.len == 4:
    if tokens[2] == "-":
      let endT = parseTime(tokens[3])
      lengthFrames = timeToFrames(endT, sr) - startSrcFrames
    elif tokens[2] == "+":
      lengthFrames = timeToFrames(parseTime(tokens[3]), sr)

  (src, Clip(
    startSrcFrames: startSrcFrames,
    lengthFrames: lengthFrames,
    startDstFrames: startDstFrames,
    volL: volL,
    volR: volR
  ))

proc parseProject(path: string, sr: int): Project =
  let lines = readFile(path).splitLines()

  var aliases = initTable[string,string]()
  var clipsBySource = initTable[string, seq[Clip]]()
  var totalLength = 0.0

  for line in lines:
    let l = line.strip()
    if l.len == 0 or l.startsWith("//"):
      continue

    if l.startsWith("length"):
      totalLength = parseTime(l.split(":")[1].strip())

    elif l.startsWith("file"):
      let parts = l.split("=")
      let name = parts[0].split(":")[1].strip()
      aliases[name] = parts[1].strip()

    else:
      let (src, clip) = parseClip(l, sr, aliases)
      clipsBySource.mgetOrPut(src, @[]).add(clip)

  Project(
    lengthFrames: timeToFrames(totalLength, sr),
    clipsBySource: clipsBySource
  )

# ---------------- MIX ----------------

proc mixProject(p: Project, sr: int): AudioBuffer =
  let totalSamples = p.lengthFrames * 2
  var mix = newSeq[float](totalSamples)

  for src, clips in p.clipsBySource:
    let buf =
      loadWav(src)
      .resample(sr)
      .toStereo()

    let totalBufFrames = buf.data.len div 2

    for clip in clips:
      let framesAvailable = max(0, totalBufFrames - clip.startSrcFrames)

      let framesToCopy =
        if clip.lengthFrames < 0:
          framesAvailable
        else:
          min(clip.lengthFrames, framesAvailable)

      var si = clip.startSrcFrames * 2
      var di = clip.startDstFrames * 2

      for i in 0..<framesToCopy:
        if di+1 >= mix.len: break

        mix[di] += buf.data[si] * clip.volL
        mix[di+1] += buf.data[si+1] * clip.volR

        si += 2
        di += 2

  AudioBuffer(sampleRate: sr, channels: 2, data: mix)

# ---------------- WRITE ----------------

proc writeWav(path: string, buf: AudioBuffer) =
  var data = newSeq[int16](buf.data.len)

  for i, s in buf.data:
    data[i] = int16(clamp(s, -1.0, 1.0) * 32767)

  let bytes = cast[string](data)

  var header = ""

  proc addStr(s: string) = header.add(s)
  proc add32(i: int32) =
    for shift in [0,8,16,24]:
      header.add(chr((i shr shift) and 0xFF))
  proc add16(i: int16) =
    header.add(chr(i and 0xFF))
    header.add(chr((i shr 8) and 0xFF))

  addStr("RIFF")
  add32(int32(36 + bytes.len))
  addStr("WAVE")

  addStr("fmt ")
  add32(16)
  add16(1)
  add16(buf.channels.int16)
  add32(buf.sampleRate.int32)
  add32((buf.sampleRate * buf.channels * 2).int32)
  add16((buf.channels * 2).int16)
  add16(16)

  addStr("data")
  add32(bytes.len.int32)

  writeFile(path, header & bytes)

# ---------------- MAIN ----------------

if paramCount() != 3:
  quit("Usage: program <samplerate> <input.txt> <output.wav>")

let sr = parseInt(paramStr(1))
let project = parseProject(paramStr(2), sr)
let resultBuf = mixProject(project, sr)

writeWav(paramStr(3), resultBuf)
echo "Done."
