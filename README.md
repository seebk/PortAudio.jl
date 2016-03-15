# PortAudio.jl

This module offers realtime audio input and output in Julia based on the
[PortAudio library](http://www.portaudio.com/). It is still under heavy
development and not well documented, yet. See the `examples/` folder to get
an idea of how to use it. Feedback and contributions are welcome!

## Basics
  * use `PortAudio.list_devices()` to print an overview of available
    devices and their device IDs
  * use `PortAudio.get_devices()` to retrieve an array of device info
    structures
  * `PortAudio.initialize()` and `PortAudio.terminate()` will be called  
    automatically by all PortAudio.jl high-level API functions. However, it
    can be called manually to trigger device initialization at a specific
    instant, too.

NOTE: Buffer underflows/overflows may occur when a script is run for the first time due to JIT compilation.

## Playback

```julia
# create a random noise signal
x = convert(Array{Float32}, randn(MersenneTwister(),sample_rate*3,2))
x = x ./ 10

# simply play a single buffer
play(x, sample_rate)

# open a stream and play the audio
devID = -1 # default device
stream = open(devID, (0, 2), sample_rate, buf_size)
write(stream, x)
close(stream)
```

## Recording

```julia
# simply record a few samples
y = record(2*sample_rate, 2, sample_rate)

# open a stream and record a few seconds
devID = -1 # default device
stream = open(devID, (2, 0), sample_rate, buf_size)
z = read(stream, 2*sample_rate)
close(stream)
```

## Simultaneous playback and recording (duplex stream)

```julia
# create a random noise signal
x = convert(Array{Float32}, randn(MersenneTwister(),sample_rate*3,2))
x = x ./ 10

# simply play a single buffer and record simultaneosly
y = playrec(x, sample_rate)


# use default device
devID = -1
# or retrieve a specific device by name
#devID = PortAudio.find_device("default")

# open a duplex stream (not supported on all host API...)
# and read and write at the same time
stream = open(devID, (2, 2), sample_rate, buf_size)
z = readwrite(stream, x)
close(stream)
```

## Credits

Most parts of the low-level PortAudio interface was taken from the [AudioIO.jl](https://github.com/ssfrr/AudioIO.jl) module.
