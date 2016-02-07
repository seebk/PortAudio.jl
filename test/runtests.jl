using PortAudio
using Base.Test

PortAudio.initialize()

# print list of all available devices
PortAudio.list_devices()

# retrieve list of all available devices
devices = PortAudio.get_devices()

# test interleaving/deinterleaving
num_frames   = 512
for num_channels = 1:6
    print("Interleaving/deinterleaving $num_channels channels and $num_frames frames... ")
    buf_deint  = randn(MersenneTwister(), num_frames, num_channels)
    buf_int    = zeros(num_frames*num_channels)
    buf_res    = zeros(buf_deint)
    PortAudio.interleave(buf_deint, buf_int, num_channels, num_frames)
    PortAudio.deinterleave(buf_int, buf_res, num_channels, num_frames)
    @test buf_deint == buf_res
    println("OK")
end

PortAudio.terminate()
