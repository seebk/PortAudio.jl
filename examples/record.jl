using PortAudio

# config
buf_size = 256
sample_rate = 48000

Pa_Initialize()

# use default device
devID = convert(PaDeviceIndex, -1)
# or retrieve a specific device by name
#devID = find_portaudio_device("default")

# open stream and record a few seconds
stream = open(devID, (2, 0), sample_rate, buf_size)
z = read(stream, 2*sample_rate)
close(stream)

# open a duplex stream (not supported on all host API...)
stream = open(devID, (2, 2), sample_rate, buf_size)
# play some noise and record it at the same time
x = convert(Array{Float32}, randn(MersenneTwister(),sample_rate*2,2))
x = x ./ 10
y = playrec(stream, x)
# close the stream
close(stream)

Pa_Terminate()
