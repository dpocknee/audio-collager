# Simple Audio Collager

This is a simple, zero-dependency program that takes in a text file that references other locally-stored .wav files, and collages them together into an output file.  It is a commandline utility that takes in two arguments: the location of the input text file, and the name the output file should be created at.

```./collager input-file.txt output-file.wav```

The default sample rate is 44,100Hz.

## Building

You can use the command `nimble build` or `nim c -d:release -o:bin/collager src/collager.nim` to build the project.  Compiling it in `release` mode _greatly_ improves the speed of the program.

## Text file

The text file is in a Domain Specific Language and should be written in the following format:

```
LENGTH 1m
FILE test/tester.wav ALIAS testAlias

// Comment

AT 0s INSERT SINE 440Hz FOR 1s VOLUME 0.25
AT 1s INSERT NOISE FOR 0.9s VOLUME 0.25

AT 2 seconds INSERT test/tester.wav FROM 5s FOR 50ms
AT 2 seconds 300ms INSERT testAlias FROM 5s FOR 50ms
AT 2 seconds 800 milliseconds INSERT testAlias FROM 10s FOR 25ms
AT 3 seconds INSERT testAlias FROM 10.1s FOR 25ms
AT 3.1s INSERT testAlias FROM 10.3s FOR 25ms

AT 4s INSERT SINE 440Hz FOR 2s VOLUME 0.25
AT 4s MIX test/tester.wav FROM 10s TO 12s
AT 8s MIX test/tester.wav FROM 10s TO 12s VOLUME 1.0 0.0
AT 10s MIX test/tester.wav FROM 10s TO 12s VOLUME 0.0 1.0
```


# DSL

## Times 

Times can be in the following formats:

- seconds
  - `1s`
  - `1.5s`
  - `3 seconds`
  - `3.21 seconds`
- milliseconds
  - `1ms`
  - `1.5ms`
  - `3 milliseconds`
  - `3.21 milliseconds`
- minutes
  - `1m`
  - `1.5m` (equivalent to 90 seconds)
  - `3 minutes`
  - `3.21 minutes`
- samples
  - `500 samples`

These can be combined when chained after each other with spaces in between.  e.g.

```15 minutes 13 seconds 150 milliseconds```

## Header: LENGTH

Each file should start with a `LENGTH` line, defining the length of the output audio file.

## Header: FILE

As it can be tiring writing out the same file path every time, you can assign aliases for any input `.wav` file, that can be used elsehwere in the file.  NOTE: All file paths within the input text file CANNOT contain spaces, otherwise parsing will not be successful.

e.g. `FILE my-long-folder-name/my-even-longer-file-name.wav ALIAS myFile`

## Body

Each line is in the format:

```
AT <time> (INSERT | MIX) <source>
  [FROM <time>]
  [(TO <time> | FOR <duration>)]
  [VOLUME <volumeLeft> [volumeRight]]
```

## AT

The `AT` keyword, followed by a time, indicates a point in the output wav file that an event should start.  `AT 2m 30s ` would indicate a time at 2 minutes and 30 seconds after the start of the output wav file.

## INSERT / MIX

The `INSERT` or `MIX` keyword indicates whether the new event should overwrite or be mixed with audio in the output file.  These keywords should be followed by a sound source.  This can be:

- file path
- file alias
- SINE `<freq>`
- NOISE

```INSERT input-folder/input-file.wav```

```INSERT myfile```

## SINE

The `SINE` keyword should be followed by a frequency in Hertz.  e.g. `SINE 440.0Hz`  It will create a sine wave at the given frequency.

```MIX SINE 325Hz```

## NOISE

The `NOISE` keyword creates white noise.

```INSERT NOISE```

## FROM

For a file path, or file alias, the `FROM` keyword indicates a point in time from the start of the input file.  This is the start of the range that will be copied into the output file.  If there is no `FROM` command, the start of the file will be presumed.  If there is no `FROM`, `FOR` or `TO` commands, the entirety of the file will be copied.

## TO / FOR

`TO` is the endpoint of the range copied from the input file into the output file.  e.g. `AT 2s INSERT my-file.wav FROM 8s TO 9s` would copy the one second of audio between 8 seconds and 9 seconds into `my-file.wav` to a position 2 seconds into the output file.

If `TO` indicates an ending position, `FOR` indicates a duration.  e.g. `AT 2s INSERT my-file.wav FROM 8s FOR 1s` would create the same output as the previous example, except here `FOR` specifies the length of the range to copy, rather than the endpoint.

## VOLUME

`VOLUME` should be followed by one or two numbers between 0 and 1, indicating how loud the input file should be when it is placed into the output file, with 1.0 indicating it's initial volume, and 0.0 indicating silence.  When `VOLUME` is followed by one number, it will apply to both stereo channels, and when it is followed by two numbers, these will apply separately to the left and right audio channel.

- `VOLUME 1.0` both channels full volume
- `VOLUME 0.5` both channels half volume
- `VOLUME 1.0 0.0` (right channel is silent)
- `VOLUME 0.0 1.0` (left channel is silent)
- `VOLUME 0.5 1.0` (left channel is half volume)

When the `VOLUME` is not specified, the volume of the input file is presumed.

## Comments

A comment line should be prefixed with two forward-slashes 

```// This line is a commented.```
