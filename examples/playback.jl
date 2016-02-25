using PortAudio

# config
buf_size = 256
sample_rate = 48000

# create a random noise signal
x = convert(Array{Float32}, randn(MersenneTwister(),sample_rate*3,2))
x = x ./ 10

PortAudio.initialize()

# use default device
devID = -1
# or retrieve a specific device by name
#devID = PortAudio.find_device("default")

# open stream and play the audio
stream = open(devID, (0, 2), sample_rate, buf_size)
write(stream, x)
close(stream)

PortAudio.terminate()
