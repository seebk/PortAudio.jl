# PortAudio.jl

This module offers realtime audio input and output in Julia based on the
[PortAudio library](http://www.portaudio.com/). It is still under heavy
development and not well documented, yet. See the `examples/` folder to get
an idea of how to use it. Feedback and contributions are welcome!

## Basics

  * call `Pa_Initialize()` before any other PortAudio related stuff
  * finally call `Pa_Terminate()` to free any PortAudio ressources
  * use `list_portaudio_devices()` to print an overview of available
    devices and their device IDs
  * use `get_portaudio_devices()` to retrieve an array of device info
    structures

## Playback

```julia
Pa_Initialize()

# ID=-1 to use default device
devID = convert(PaDeviceIndex, -1)

# open stream and play the audio
stream = open(devID, (0, 2), sample_rate, buf_size)
write(stream, x)
close(stream)

Pa_Terminate()
```

## Recording

```julia
Pa_Initialize()

# ID=-1 to use default device
devID = convert(PaDeviceIndex, -1)

# open stream and read a few seconds of audio
stream = open(devID, (2, 0), sample_rate, buf_size)
x = read(stream, 2*sample_rate)
close(stream)

Pa_Terminate()
```
