import std/[math, sequtils]
import ./types

# ---------------- WAV ----------------
proc readInt16LE(data: string, pos: int): int16 =
  cast[int16](ord(data[pos]) or (ord(data[pos+1]) shl 8))

proc readInt32LE(data: string, pos: int): int32 =
  cast[int32](ord(data[pos]) or (ord(data[pos+1]) shl 8) or
    (ord(data[pos+2]) shl 16) or (ord(data[pos+3]) shl 24))

proc loadWav*(path: string): AudioBuffer =
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

  return AudioBuffer(sampleRate: sampleRate, channels: channels, data: samples)

# ---------------- RESAMPLE ----------------

proc resample*(buf: AudioBuffer, newRate: int): AudioBuffer =
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

  return AudioBuffer(sampleRate: newRate, channels: ch, data: outData)

proc toStereo*(buf: AudioBuffer): AudioBuffer =
  if buf.channels == 2:
    return buf

  var it = 0
  let outData = newSeqWith(buf.data.len * 2):
    let i = it div 2
    buf.data[i]

  return AudioBuffer(sampleRate: buf.sampleRate, channels: 2, data: outData)

# ---------------- WRITE ----------------

proc createWav*(buf: AudioBuffer): string =
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

  return header & bytes

