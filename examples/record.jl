using PortAudio

# config
buf_size = 256
sample_rate = 48000

Pa_Initialize()

# use default device
devID = convert(PaDeviceIndex, -1)
# or retrieve a specific device by name
#devID = find_portaudio_device("default")

# open stream and play the audio
stream = open(devID, (2, 0), sample_rate, buf_size)
x = read(stream, 2*sample_rate)
close(stream)

Pa_Terminate()
