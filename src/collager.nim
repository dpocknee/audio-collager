import std/[os, strutils, parseutils, tables, sequtils, math]

type
  AudioBuffer = object
    sampleRate: int
    channels: int
    data: seq[float] # interleaved

  Clip = object
    source: string
    startSrc: float
    duration: float
    startDst: float
    volL: float
    volR: float

# ---------------- WAV LOADING ----------------

proc readInt16LE(data: string, pos: int): int16 =
  result = cast[int16](ord(data[pos]) or (ord(data[pos+1]) shl 8))

proc readInt32LE(data: string, pos: int): int32 =
  result = cast[int32](ord(data[pos]) or (ord(data[pos+1]) shl 8) or
                       (ord(data[pos+2]) shl 16) or (ord(data[pos+3]) shl 24))

proc loadWav(path: string): AudioBuffer =
  let bytes = readFile(path)

  if bytes[0..3] != "RIFF" or bytes[8..11] != "WAVE":
    quit("Invalid WAV: " & path)

  var pos = 12
  var sampleRate = 44100
  var channels = 1
  var dataStart = 0
  var dataSize = 0

  while pos < bytes.len:
    let chunkId = bytes[pos..pos+3]
    let chunkSize = readInt32LE(bytes, pos+4)

    if chunkId == "fmt ":
      channels = readInt16LE(bytes, pos+10)
      sampleRate = readInt32LE(bytes, pos+12)
    elif chunkId == "data":
      dataStart = pos + 8
      dataSize = chunkSize
      break

    pos += 8 + chunkSize

  var samples: seq[float] = @[]
  let sampleCount = dataSize div 2

  for i in 0..<sampleCount:
    let s = readInt16LE(bytes, dataStart + i*2)
    samples.add(s.float / 32768.0)

  result = AudioBuffer(sampleRate: sampleRate, channels: channels, data: samples)

# ---------------- RESAMPLING ----------------

proc resample(buf: AudioBuffer, newRate: int): AudioBuffer =
  if buf.sampleRate == newRate:
    return buf

  let ratio = newRate.float / buf.sampleRate.float
  let newLen = int(buf.data.len.float * ratio)

  var outValue = newSeq[float](newLen)

  for i in 0..<newLen:
    let srcPos = i.float / ratio
    let i0 = int(srcPos)
    let i1 = min(i0 + 1, buf.data.len - 1)
    let t = srcPos - i0.float
    outValue[i] = buf.data[i0]*(1-t) + buf.data[i1]*t

  result = AudioBuffer(sampleRate: newRate, channels: buf.channels, data: outValue)

# ---------------- CHANNEL CONVERSION ----------------

proc toStereo(buf: AudioBuffer): AudioBuffer =
  if buf.channels == 2:
    return buf

  var outValue: seq[float] = @[]
  for s in buf.data:
    outValue.add(s)
    outValue.add(s)

  result = AudioBuffer(sampleRate: buf.sampleRate, channels: 2, data: outValue)

# ---------------- WRITE WAV ----------------

proc writeWav(path: string, buf: AudioBuffer) =
  var data: seq[int16] = @[]

  for s in buf.data:
    let v = clamp(s, -1.0, 1.0)
    data.add(int16(v * 32767))

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

# ---------------- PARSER ----------------

proc parseTime(s: string): float =
  var val: float
  discard parseFloat(s.replace("s",""), val)
  return val

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
    var parts = l.split("@")
    let left = parts[0].strip()
    let right = parts[1].strip()

    let dstTime = parseTime(right.split("*")[0].strip())

    var volL = 1.0
    var volR = 1.0

    if right.contains("*"):
      let v = right.split("*")[1].strip().splitWhitespace()
      if v.len == 1:
        volL = parseFloat(v[0])
        volR = volL
      elif v.len == 2:
        volL = parseFloat(v[0])
        volR = parseFloat(v[1])

    let tokens = left.splitWhitespace()
    let srcName = tokens[0]
    let src = aliases.getOrDefault(srcName, srcName)

    var startSrc = 0.0
    var duration = -1.0

    if tokens.len == 2:
      startSrc = parseTime(tokens[1])
    elif tokens.len == 4:
      startSrc = parseTime(tokens[1])
      if tokens[2] == "-":
        duration = parseTime(tokens[3]) - startSrc
      elif tokens[2] == "+":
        duration = parseTime(tokens[3])

    clips.add(Clip(source: src, startSrc: startSrc,
                   duration: duration, startDst: dstTime,
                   volL: volL, volR: volR))

# ---------------- PROCESS ----------------

let totalSamples = int(totalLength * float(targetRate)) * 2
var mix = newSeq[float](totalSamples)

var cache = initTable[string, AudioBuffer]()

for clip in clips:
  if not cache.hasKey(clip.source):
    var buf = loadWav(clip.source)
    buf = resample(buf, targetRate)
    buf = toStereo(buf)
    cache[clip.source] = buf

  let buf = cache[clip.source]

  let startSampleSrc = int(clip.startSrc * float(targetRate)) * 2
  let startSampleDst = int(clip.startDst * float(targetRate)) * 2

  var lengthSamples =
    if clip.duration < 0:
      buf.data.len - startSampleSrc
    else:
      int(clip.duration * float(targetRate)) * 2

  for i in 0..<lengthSamples div 2:
    let si = startSampleSrc + i*2
    let di = startSampleDst + i*2

    if di+1 >= mix.len or si+1 >= buf.data.len:
      break

    mix[di] += buf.data[si] * clip.volL
    mix[di+1] += buf.data[si+1] * clip.volR

# normalize (optional safety)
var maxVal = 0.0
for s in mix:
  maxVal = max(maxVal, abs(s))

if maxVal > 1.0:
  for i in 0..<mix.len:
    mix[i] /= maxVal

writeWav(outputFile, AudioBuffer(sampleRate: targetRate, channels: 2, data: mix))

echo "Done."
