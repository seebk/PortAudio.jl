using PortAudio

# config
buf_size = 256
sample_rate = 48000

# create a random noise signal
x = convert(Array{Float32}, randn(MersenneTwister(),sample_rate*3,2))
x = x ./ 10

Pa_Initialize()

# use default device
devID = convert(PaDeviceIndex, -1)
# or retrieve a specific device by name
#devID = find_portaudio_device("default")

# open stream and play the audio
stream = open(devID, (0, 2), sample_rate, buf_size)
write(stream, x)
close(stream)

Pa_Terminate()
