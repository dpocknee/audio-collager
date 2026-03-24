# Simple Audio Collager

This is a simple, zero-dependency program that takes in a text file that references other locally-stored .wav files, and collages them together into an output file.  It is a commandline utility that takes in two arguments: the location of the input text file, and the name the output file should be created at.

```./collager input-file.txt output-file.wav```

The default sample rate is 44,100Hz.

## Building

You can use the command `nimble build` or `nim c -o:bin/collager src/collager.nim` to build the project.  

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

Each line is in the format:

```
AT <time> (INSERT | MIX) <source>
  [FROM <time>]
  [(TO <time> | FOR <duration>)]
  [VOLUME <volumeLeft> [volumeRight]]
```

Where `<source>` can be:
- file path
- alias
- SINE <freq>
- NOISE
