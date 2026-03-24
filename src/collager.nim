import std/[os]
import ./[wav_files, dsl_parser, convert_to_samples]
import ./types

when isMainModule:
  if paramCount() != 2:
    quit("Usage: program <input.txt> <output.wav>")

  let sampleRate = 44100
  let inputTextFile = paramStr(1)
  echo "PARSING ", inputTextFile
  let parsedCollageFile: Collage = parseCollageFile(inputTextFile, sampleRate)
  
  echo "FILL OUTPUT BUFFER"
  let resultBuf = mixCollage(parsedCollageFile)

  echo "CREATE WAV FILE ", paramStr(2)
  # Write to wave file
  let createdWavFile = createWav(resultBuf)
  writeFile(paramStr(2), createdWavFile)

  echo "FINISHED"
