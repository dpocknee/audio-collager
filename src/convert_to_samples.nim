import std/[tables, math, sequtils, random]
import ./types
import ./wav_files

proc clipTimesToSamples*(
  times: seq[ClipTime], sampleRate: int
): int =
  var totalSamples = 0.0

  for t in times:
    case t.kind
    of ClipTimeKind.SAMPLES:
      totalSamples += t.samples.float

    of ClipTimeKind.SECONDS:
      totalSamples += t.seconds * float(sampleRate)

    of ClipTimeKind.MILLISECONDS:
      totalSamples += (t.milliseconds / 1000.0) * float(sampleRate)

    of ClipTimeKind.MINUTES:
      totalSamples += (t.minutes * 60.0) * float(sampleRate)

  return int(round(totalSamples))

proc generateNoiseSamples(
  clipSamples: ClipSamples
): seq[tuple[left, right: float]] = 
  result = @[]
  for i in clipSamples.sourceStart..<clipSamples.sourceEnd:
    let noiseVal = rand(1.0) * 2.0 - 1.0
    result.add((
      left: noiseVal * clipSamples.volume.left, 
      right: noiseVal * clipSamples.volume.right
    ))

func generateSineSamples(
  clipSamples: ClipSamples,
  frequency: float,
  sampleRate: int
): seq[tuple[left, right: float]] = 
  result = @[]
  var counter = 0
  for s in clipSamples.sourceStart..<clipSamples.sourceEnd:
    let t = float(counter) / float(sampleRate)
    let v = sin(2 * PI * frequency * t)
    result.add((
      left: v * clipSamples.volume.left,
      right: v * clipSamples.volume.right
    ))
    counter += 1

func generateFileSamples(
  clipSamples: ClipSamples,
  fileSamples: seq[float]
): seq[tuple[left, right: float]] = 
  result = @[]
  for sample in clipSamples.sourceStart..clipSamples.sourceEnd:
    let stereoSample = sample * 2
    if stereoSample < fileSamples.len:
      result.add((
        left: fileSamples[stereoSample] * clipSamples.volume.left,
        right: fileSamples[stereoSample + 1] * clipSamples.volume.right
      ))

proc convertToSamples*(
  clip: Clip, fileLength: int, sampleRate: int
): ClipSamples = 
  result = ClipSamples(
    destinationStart: 0,
    sourceStart: 0,
    sourceEnd: fileLength,
    mixing: clip.mixing,
    volume: clip.volume
  )

  result.destinationStart = clipTimesToSamples(
    clip.destinationStart, sampleRate
  )

  if clip.sourceStart.kind == ClipStartKind.TIME:
    result.sourceStart = clipTimesToSamples(
      clip.sourceStart.time, sampleRate
    )

  case clip.sourceEnd.kind
  of ClipEndKind.TIME:
    result.sourceEnd = clipTimesToSamples(
      clip.sourceEnd.time, sampleRate
    )
  of ClipEndKind.DURATION:
    result.sourceEnd = result.sourceStart + clipTimesToSamples(
      clip.sourceEnd.duration, sampleRate
    )
  of ClipEndKind.END_FILE: discard

proc mixSamples(
  buffer: var seq[float], 
  samples: seq[tuple[left, right: float]],
  clip: ClipSamples 
) =
  for i, sample in samples:
    let location = i * 2
    let destStart = clip.destinationStart * 2
    if (destStart + location) < buffer.len:
      case clip.mixing
      of ClipMixKind.INSERT:
        buffer[destStart + location] = sample.left
        buffer[destStart + location + 1] = sample.right
      of ClipMixKind.MIX:
        buffer[destStart + location] += sample.left
        buffer[destStart + location + 1] += sample.right

proc mixCollage*(collage: Collage): AudioBuffer =
  result = AudioBuffer(
    sampleRate: collage.sampleRate, 
    channels: 2, 
    data: newSeqWith(collage.lengthInSamples * 4, 0.0)
  )

  for src, clips in collage.clips:
    if src == "SINE":
      for clip in clips:
        let convertedToSamples: ClipSamples = convertToSamples(
          clip, 
          result.data.len, 
          collage.sampleRate
        )
        let sineSamples: seq[tuple[left: float, right: float]] = generateSineSamples(
          convertedToSamples,
          clip.source.sine,
          collage.sampleRate
        )
        result.data.mixSamples(sineSamples, convertedToSamples)

    elif src == "NOISE":
      for clip in clips:
        let convertedToSamples = convertToSamples(
          clip, result.data.len, collage.sampleRate
        )
        let noiseSamples: seq[tuple[left: float, right: float]] = generateNoiseSamples(
          convertedToSamples,
        )
        result.data.mixSamples(noiseSamples, convertedToSamples)
    
    else:
      echo "--- ", src, " --- "
      for clip in clips:
        let fileBuffer = loadWav(src).resample(collage.sampleRate).toStereo()
        let convertedToSamples = convertToSamples(
          clip, fileBuffer.data.len, collage.sampleRate
        )
        echo "  DESTINATION ", convertedToSamples.destinationStart, " SOURCE (", convertedToSamples.sourceStart, " - ", convertedToSamples.sourceEnd, ") VOLUME (",  convertedToSamples.volume.left, ", ", convertedToSamples.volume.right, ")"
        let fileSamples = generateFileSamples(
          convertedToSamples, fileBuffer.data
        )
        result.data.mixSamples(fileSamples, convertedToSamples)
