using PortAudio

# config
buf_size = 256
sample_rate = 48000

# create a random noise signal
x = convert(Array{Float32}, randn(MersenneTwister(),sample_rate*3,2))
x = x ./ 10

# simply play a single buffer
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
