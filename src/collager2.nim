import std/[os, strutils, parseutils, tables, math]

type
  AudioBuffer = object
    sampleRate: int
    channels: int
    data: seq[float]

  Clip = object
    source: string
    startSrcFrames: int
    lengthFrames: int
    startDstFrames: int
    volL: float
    volR: float

# ---------------- WAV ----------------

proc readInt16LE(data: string, pos: int): int16 =
  cast[int16](ord(data[pos]) or (ord(data[pos+1]) shl 8))

proc readInt32LE(data: string, pos: int): int32 =
  cast[int32](ord(data[pos]) or (ord(data[pos+1]) shl 8) or
              (ord(data[pos+2]) shl 16) or (ord(data[pos+3]) shl 24))

proc loadWav(path: string): AudioBuffer =
  let bytes = readFile(path)

  if bytes.len < 44 or bytes[0..3] != "RIFF" or bytes[8..11] != "WAVE":
    quit("Invalid WAV: " & path)

  var pos = 12
  var sampleRate = 44100
  var channels = 1
  var dataStart = 0
  var dataSize = 0

  while pos + 8 <= bytes.len:
    let chunkId = bytes[pos..pos+3]
    let chunkSize = readInt32LE(bytes, pos+4)

    if chunkId == "fmt ":
      channels = int(readInt16LE(bytes, pos+10))
      sampleRate = int(readInt32LE(bytes, pos+12))
    elif chunkId == "data":
      dataStart = pos + 8
      dataSize = chunkSize
      break

    pos += 8 + int(chunkSize)

  let sampleCount = dataSize div 2
  var samples = newSeq[float](sampleCount)

  for i in 0..<sampleCount:
    let s = readInt16LE(bytes, dataStart + i*2)
    samples[i] = s.float / 32768.0

  AudioBuffer(sampleRate: sampleRate, channels: channels, data: samples)

# ---------------- RESAMPLE ----------------
proc resample(buf: AudioBuffer, newRate: int): AudioBuffer =
  if buf.sampleRate == newRate:
    return buf

  let channels = buf.channels
  let inFrames = buf.data.len div channels
  let ratio = newRate.float / buf.sampleRate.float
  let outFrames = int(round(inFrames.float * ratio))

  var outValue = newSeq[float](outFrames * channels)

  for i in 0..<outFrames:
    let srcPos = i.float / ratio
    let i0 = int(srcPos)
    let i1 = min(i0 + 1, inFrames - 1)
    let t = srcPos - i0.float

    for ch in 0..<channels:
      let s0 = buf.data[i0 * channels + ch]
      let s1 = buf.data[i1 * channels + ch]
      outValue[i * channels + ch] = s0*(1-t) + s1*t

  AudioBuffer(sampleRate: newRate, channels: channels, data: outValue)

# proc resample(buf: AudioBuffer, newRate: int): AudioBuffer =
#   if buf.sampleRate == newRate:
#     return buf

#   let ratio = newRate.float / buf.sampleRate.float
#   let newLen = int(buf.data.len.float * ratio)

#   var outValue = newSeq[float](newLen)

#   for i in 0..<newLen:
#     let srcPos = i.float / ratio
#     let i0 = int(srcPos)
#     let i1 = min(i0 + 1, buf.data.len - 1)
#     let t = srcPos - i0.float
#     outValue[i] = buf.data[i0]*(1-t) + buf.data[i1]*t

#   AudioBuffer(sampleRate: newRate, channels: buf.channels, data: outValue)

# ---------------- CHANNELS ----------------

proc toStereo(buf: AudioBuffer): AudioBuffer =
  if buf.channels == 2:
    return buf

  var outValue = newSeq[float](buf.data.len * 2)
  for i, s in buf.data:
    outValue[i*2] = s
    outValue[i*2+1] = s

  AudioBuffer(sampleRate: buf.sampleRate, channels: 2, data: outValue)

# ---------------- WAV WRITE ----------------

proc writeWav(path: string, buf: AudioBuffer) =
  var data = newSeq[int16](buf.data.len)

  for i, s in buf.data:
    let v = clamp(s, -1.0, 1.0)
    data[i] = int16(v * 32767)

  let dataBytes = cast[string](data)

  var header = ""

  proc addStr(s: string) = header.add(s)
  proc add32(i: int32) =
    header.add(chr(i and 0xFF))
    header.add(chr((i shr 8) and 0xFF))
    header.add(chr((i shr 16) and 0xFF))
    header.add(chr((i shr 24) and 0xFF))

  proc add16(i: int16) =
    header.add(chr(i and 0xFF))
    header.add(chr((i shr 8) and 0xFF))

  addStr("RIFF")
  add32(int32(36 + dataBytes.len))
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
  add32(dataBytes.len.int32)

  writeFile(path, header & dataBytes)

# ---------------- TIME ----------------

proc parseTime(s: string): float =
  var val: float
  discard parseFloat(s.replace("s",""), val)
  val

proc timeToFrames(t: float, sr: int): int =
  int(round(t * float(sr)))

# ---------------- MAIN ----------------

if paramCount() != 3:
  quit("Usage: program <samplerate> <input.txt> <output.wav>")

let targetRate = parseInt(paramStr(1))
let inputFile = paramStr(2)
let outputFile = paramStr(3)

let lines = readFile(inputFile).splitLines()

var aliases = initTable[string,string]()
var clips: seq[Clip] = @[]
var totalLength = 0.0

# -------- Parse --------

for line in lines:
  let l = line.strip()
  if l.len == 0 or l.startsWith("//"):
    continue

  if l.startsWith("length"):
    totalLength = parseTime(l.split(":")[1].strip())

  elif l.startsWith("file"):
    let parts = l.split("=")
    let name = parts[0].split(":")[1].strip()
    let path = parts[1].strip()
    aliases[name] = path

  else:
    let parts = l.split("@")
    if parts.len != 2:
      quit("Invalid line: " & l)

    var left = parts[0].strip()
    var right = parts[1].strip()

    var startDstFrames: int
    var srcPart: string
    var volPart = ""

    # Detect which side is time
    if left.endsWith("s"):
      # format: 0s @ source ...
      startDstFrames = timeToFrames(parseTime(left), targetRate)
      srcPart = right
    else:
      # format: source ... @ 0s
      let rparts = right.split("*")
      startDstFrames = timeToFrames(parseTime(rparts[0].strip()), targetRate)
      srcPart = left
      if rparts.len > 1:
        volPart = rparts[1]

    # volume
    var volL = 1.0
    var volR = 1.0

    if srcPart.contains("*"):
      let sp = srcPart.split("*")
      srcPart = sp[0].strip()
      volPart = sp[1]

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
      startSrcFrames = timeToFrames(parseTime(tokens[1]), targetRate)

    if tokens.len == 4:
      if tokens[2] == "-":
        let endT = parseTime(tokens[3])
        lengthFrames = timeToFrames(endT, targetRate) - startSrcFrames
      elif tokens[2] == "+":
        lengthFrames = timeToFrames(parseTime(tokens[3]), targetRate)

    clips.add(Clip(
      source: src,
      startSrcFrames: startSrcFrames,
      lengthFrames: lengthFrames,
      startDstFrames: startDstFrames,
      volL: volL,
      volR: volR
    ))

# -------- Load audio --------

var cache = initTable[string, AudioBuffer]()

# Note to David - this is probably why it's so slow - it is opening and closing the source wav file for each clip.  It needs a function that groups together everything during the parsing stage.
for clip in clips:
  if not cache.hasKey(clip.source):
    var buf = loadWav(clip.source)
    buf = resample(buf, targetRate)
    buf = toStereo(buf)
    cache[clip.source] = buf

# -------- Allocate fixed buffer --------

let maxFrames = timeToFrames(totalLength, targetRate)
var mix = newSeq[float](maxFrames * 2)

# -------- Mixing --------

for clip in clips:
  let buf = cache[clip.source]

  let srcStart = clip.startSrcFrames * 2
  let dstStart = clip.startDstFrames * 2

  let totalBufFrames = buf.data.len div 2
  let framesAvailable = max(0, totalBufFrames - clip.startSrcFrames)

  let framesToCopy =
    if clip.lengthFrames < 0:
      framesAvailable
    else:
      min(clip.lengthFrames, framesAvailable)

  var si = srcStart
  var di = dstStart

  for i in 0..<framesToCopy:
    if di+1 >= mix.len:
      break

    mix[di] += buf.data[si] * clip.volL
    mix[di+1] += buf.data[si+1] * clip.volR

    si += 2
    di += 2

# -------- Write --------

writeWav(outputFile, AudioBuffer(sampleRate: targetRate, channels: 2, data: mix))

echo "Done."