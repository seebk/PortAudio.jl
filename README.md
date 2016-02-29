# PortAudio.jl

This module offers realtime audio input and output in Julia based on the
[PortAudio library](http://www.portaudio.com/). It is still under heavy
development and not well documented, yet. See the `examples/` folder to get
an idea of how to use it. Feedback and contributions are welcome!

## Basics

  * call `PortAudio.initialize()` before any other PortAudio related stuff
  * finally call `PortAudio.terminate()` to free any PortAudio ressources
  * use `PortAudio.list_devices()` to print an overview of available
    devices and their device IDs
  * use `PortAudio.get_devices()` to retrieve an array of device info
    structures

NOTE: Buffer underflows/overflows may occur when a script is run for the first time due to JIT compilation.

## Playback

```julia
PortAudio.initialize()

# create a random noise signal
x = convert(Array{Float32}, randn(MersenneTwister(),sample_rate*3,2))
x = x ./ 10

# ID=-1 to use default device
devID = -1

# open stream and play the audio
stream = open(devID, (0, 2), sample_rate, buf_size)
write(stream, x)
close(stream)

PortAudio.terminate()
```

## Recording

```julia
PortAudio.initialize()

# ID=-1 to use default device
devID = -1

# open stream and record a few seconds
stream = open(devID, (2, 0), sample_rate, buf_size)
z = read(stream, 2*sample_rate)
close(stream)

PortAudio.terminate()
```

## Simultaneous playback and recording (duplex stream)

```julia
PortAudio.initialize()

# ID=-1 to use default device
devID = -1

# open a duplex stream (not supported on all host API...)
stream = open(devID, (2, 2), sample_rate, buf_size)

# play some noise and record it at the same time
x = convert(Array{Float32}, randn(MersenneTwister(),sample_rate*2,2))
x = x ./ 10
y = playrec(stream, x)

# close the stream
close(stream)

PortAudio.terminate()
```

## Credits

Most parts of the low-level PortAudio interface was taken from the [AudioIO.jl](https://github.com/ssfrr/AudioIO.jl) module. 
