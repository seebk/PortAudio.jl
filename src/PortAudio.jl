module PortAudio

export PaStream, PaBuffer, PaSample, PaProcessor
export open, close
export read, read!, write, playrec!, playrec

include(Pkg.dir("PortAudio", "deps", "deps.jl"))

# mapping of portaudio types to Julia types
typealias PaTime Cdouble
typealias PaError Cint
typealias PaSampleFormat Culong
# PaStream is always used as an opaque type, so we're always dealing with the
# pointer
typealias PaStream Ptr{Void}
typealias PaDeviceIndex Cint
typealias PaHostApiIndex Cint
typealias PaTime Cdouble
typealias PaHostApiTypeId Cint
typealias PaStreamCallback Void

typealias PaSample Union{Float32, Int32, Int16, Int8, UInt8}
typealias PaBuffer{PaSample} Union{Array{PaSample,1}, Array{PaSample,2}}

# Portaudio error codes
const PA_NO_ERROR = 0
const PA_INPUT_OVERFLOWED = -10000 + 19
const PA_OUTPUT_UNDERFLOWED = -10000 + 20

# PaSampleFormat
const paFloat32 = convert(PaSampleFormat, 0x01)
const paInt32   = convert(PaSampleFormat, 0x02)
const paInt24   = convert(PaSampleFormat, 0x04)
const paInt16   = convert(PaSampleFormat, 0x08)
const paInt8    = convert(PaSampleFormat, 0x10)
const paUInt8   = convert(PaSampleFormat, 0x20)
const paCustomFormat   = convert(PaSampleFormat, 0x00010000)
const paNonInterleaved = convert(PaSampleFormat, 0x80000000)

############ Portaudio structures ############

abstract PaProcessor{FS, Channels}

type PaStreamWrapper
    stream::PaStream
    deviceID::PaDeviceIndex
    sample_rate::Real
    sample_format::PaSampleFormat
    sample_type::Type
    async_io
    buf_size::Integer
    num_inputs::Integer
    num_outputs::Integer
end

type PaStreamParameters
    device::PaDeviceIndex
    channelCount::Cint
    sampleFormat::PaSampleFormat
    suggestedLatency::PaTime
    hostApiSpecificStreamInfo::Ptr{Void}
end

type PaDeviceInfo
    struct_version::Cint
    name::Ptr{Cchar}
    host_api::PaHostApiIndex
    max_input_channels::Cint
    max_output_channels::Cint
    default_low_input_latency::PaTime
    default_low_output_latency::PaTime
    default_high_input_latency::PaTime
    default_high_output_latency::PaTime
    default_sample_rate::Cdouble
end

type PaHostApiInfo
    struct_version::Cint
    api_type::PaHostApiTypeId
    name::Ptr{Cchar}
    deviceCount::Cint
    defaultInputDevice::PaDeviceIndex
    defaultOutputDevice::PaDeviceIndex
end

############ High-level Julia interface ############

initialize() = Pa_Initialize()
terminate() = Pa_Terminate()

"Open a PortAudio stream"
function Base.open(ID::Integer,
                num_IO::Tuple{Integer, Integer}, sample_rate::Real,
                buf_size::Integer=1024, sample_format::PaSampleFormat=paFloat32)

    stream::PaStream

    sample_type::Type
    sample_format == paFloat32  ? sample_type = Float32 :
    sample_format == paInt32    ? sample_type = Int32   :
    sample_format == paInt16    ? sample_type = Int16   :
    sample_format == paInt8     ? sample_type = Int8    :
    sample_format == paUInt8    ? sample_type = UInt8   :
    throw(ArgumentError("Invalid sample format"))

    if ID >= 0
      ID > Pa_GetDeviceCount() && error("Device ID is too big")
      deviceInfo = Pa_GetDeviceInfo(ID)
      deviceInfo.max_input_channels < num_IO[1] && error("Device does not support $(num_IO[1]) input channels")
      deviceInfo.max_output_channels < num_IO[2] && error("Device does not support $(num_IO[2]) output channels")

      inputParameters = PaStreamParameters(ID,
                                              num_IO[1],
                                              sample_format,
                                              deviceInfo.default_low_input_latency,
                                              0)
      outputParameters = PaStreamParameters(ID,
                                              num_IO[2],
                                              sample_format,
                                              deviceInfo.default_low_output_latency,
                                              0)


      stream = Pa_OpenStream(inputParameters, outputParameters, sample_rate, buf_size)
    else
      stream = Pa_OpenDefaultStream(num_IO[1], num_IO[2], sample_format, sample_rate, buf_size)
    end
    stream_wrapper = PaStreamWrapper(stream, ID, sample_rate, sample_format,
                                     sample_type, false, buf_size, num_IO[1], num_IO[2])
end

"Open a PortAudio stream in asynchronous mode and connect it with a callback function"
function Base.open(ID::Integer,
                proc::PaProcessor,
                num_IO::Tuple{Integer, Integer}, sample_rate::Real,
                buf_size::Integer=1024, sample_format::PaSampleFormat=paFloat32)

    stream_wrapper = open(ID, num_IO, sample_rate::Real, buf_size, sample_format)

    tmp_rec_buffer  = zeros(stream_wrapper.sample_type, 20*stream_wrapper.buf_size)
    tmp_play_buffer = zeros(stream_wrapper.sample_type, 20*stream_wrapper.buf_size)

    rec_buffer   = zeros(20*stream_wrapper.buf_size, maximum(num_IO))
    play_buffer  = zeros(20*stream_wrapper.buf_size, maximum(num_IO))

    stream_wrapper.async_io = @async begin
        written::Integer = 1
        read::Integer    = 1
        toread::Integer  = 0
        try
            Pa_StartStream(stream_wrapper.stream)
            while true
                toread = Pa_GetStreamReadAvailable(stream_wrapper.stream)
                if toread > 64
                    ## read samples
                    Pa_ReadStream(stream_wrapper.stream, tmp_rec_buffer, toread)
                    deinterleave(tmp_rec_buffer,
                                 sub(rec_buffer,1:toread,:),
                                 stream_wrapper.num_inputs, toread)
                    read = read + toread

                    #### process
                    proc.process(sub(rec_buffer,1:toread,:), sub(play_buffer,1:toread,:))

                    ## write samples
                    interleave(sub(play_buffer,1:toread,1:stream_wrapper.num_outputs),
                               tmp_play_buffer, stream_wrapper.num_outputs, toread)
                    Pa_WriteStream(stream_wrapper.stream, tmp_play_buffer, toread)
                    written = written + toread
                    sleep(0.001)
                else
                    #Libc.systemsleep(0.002)
                    sleep(0.001) # sleep() causes an increased number of allocations here
                                  # but Libc.systemsleep() does not run other tasks while sleeping
                                  # and blocks the REPL
                end
            end
        catch e
            Pa_StopStream(stream_wrapper.stream)
            if isa(e, InterruptException)
                #
            else
                throw(e)
            end
        end
    end

    return stream_wrapper
end

"Close a PortAudio stream"
function Base.close(stream_wrapper::PaStreamWrapper)
    if isa(stream_wrapper.async_io, Task)
        # send interrupt and wait for task to finish
        Base.throwto(stream_wrapper.async_io, InterruptException())
        wait(stream_wrapper.async_io)
        stream_wrapper.async_io = false
    end
    Pa_CloseStream(stream_wrapper.stream)
end

"Find a PortAudio device by its device name and host API name"
function find_device(device_name::AbstractString, device_api::AbstractString="")
    devices = get_devices()
    device_ID::Integer = -1
    for (i,d) in enumerate(devices)
      if  bytestring(d.name) == bytestring(device_name) &&
          (isempty(device_api) || bytestring(Pa_GetHostApiInfo(d.host_api).name)==device_api)
          device_ID = i-1
          break
      end
    end

    device_ID < 0 && error("Device '$device_name' not found!")
    return device_ID
end

"Get a list of all available PortAudio devices"
function get_devices()
    device_count = Pa_GetDeviceCount()
    pa_devices = PaDeviceInfo[]
    for i in 1:device_count
      push!(pa_devices, Pa_GetDeviceInfo(i-1))
    end
    return pa_devices
end

"Print a formatted list of all PortAudio devices"
function list_devices()
    devices = get_devices()
    for (i,d) in enumerate(devices)
        api_info = Pa_GetHostApiInfo(d.host_api)
        @printf("%3d: %s [%s], [%d/%d]\n", i-1, bytestring(d.name), bytestring(api_info.name), d.max_input_channels, d.max_output_channels)
    end
end

function interleave(deint_buffer, int_buffer, channels::Integer, frames::Integer)
    for f=1:frames
        for c=1:channels
         int_buffer[(f-1)*channels + c] = deint_buffer[f,c]
        end
    end
end

function deinterleave(int_buffer, deint_buffer, channels::Integer, frames::Integer)
    for f=1:frames
        for c=1:channels
         deint_buffer[f,c] = int_buffer[(f-1)*channels + c]
        end
    end
end

"Fill a buffer by a certain amount of samples from a Portaudio stream"
function Base.read!(stream_wrapper::PaStreamWrapper, buffer::PaBuffer, Nframes::Integer=size(buffer,1))
    (stream_wrapper.num_inputs > size(buffer,2) || Nframes > size(buffer,1)) &&
        error("Buffer dimensions do not fit stream parameters")

    tmp_rec_buffer  = zeros(stream_wrapper.sample_type, 20*4096)

    Pa_StartStream(stream_wrapper.stream)
    read::Integer   = 1
    toread::Integer = 0
    while true
        toread = Pa_GetStreamReadAvailable(stream_wrapper.stream)
        if toread > 16
            if read + toread > Nframes
              break
            end
            Pa_ReadStream(stream_wrapper.stream, tmp_rec_buffer, toread)
            deinterleave(tmp_rec_buffer,
                         sub(buffer,read:read+toread-1,:),
                         stream_wrapper.num_inputs, toread)
            read = read + toread
        else
            Libc.systemsleep(0.0005)
            #sleep(0.0005) # sleep() causes an increased number of allocations here
        end
    end
    Pa_StopStream(stream_wrapper.stream)
    nothing
end

"Read a certain amount of samples from a Portaudio stream"
function Base.read(stream_wrapper::PaStreamWrapper, Nframes::Integer)
    buffer = zeros(stream_wrapper.sample_type, Nframes, stream_wrapper.num_inputs)
    read!(stream_wrapper, buffer)
    return buffer
end

"Play and record simultaneously"
function playrec(stream_wrapper::PaStreamWrapper,
                 play_buffer::PaBuffer,
                 Nframes::Integer=size(play_buffer,1))

     rec_buffer = zeros(stream_wrapper.sample_type, Nframes, stream_wrapper.num_inputs)
     playrec!(stream_wrapper, play_buffer, rec_buffer, Nframes)
     return rec_buffer
 end

"Play and record simultaneously using a pre-allocated recording buffer"
function playrec!(stream_wrapper::PaStreamWrapper,
                 play_buffer::PaBuffer, rec_buffer::PaBuffer,
                 Nframes::Integer=size(play_buffer,1))

    (stream_wrapper.num_outputs > size(play_buffer,2) || Nframes > size(play_buffer,1)) ||
    (stream_wrapper.num_inputs > size(rec_buffer,2) ||  Nframes > size(rec_buffer,1)) &&
        error("Buffer dimensions do not fit stream parameters")

    tmp_rec_buffer  = zeros(stream_wrapper.sample_type, 20*4096)
    tmp_play_buffer = zeros(stream_wrapper.sample_type, 20*4096)

    Pa_StartStream(stream_wrapper.stream)
    written::Integer = 1
    read::Integer    = 1
    while true
        towrite = Pa_GetStreamWriteAvailable(stream_wrapper.stream)
        if towrite > 16
            if written + towrite > Nframes
              break
            end
            interleave(sub(play_buffer,written:written+towrite-1,1:stream_wrapper.num_outputs),
                       tmp_play_buffer, stream_wrapper.num_outputs, towrite)
            Pa_WriteStream(stream_wrapper.stream, tmp_play_buffer, towrite)
            written = written + towrite
        end

        toread = Pa_GetStreamReadAvailable(stream_wrapper.stream)
        if toread > 16
            if read + toread > Nframes
              break
            end
            Pa_ReadStream(stream_wrapper.stream, tmp_rec_buffer, toread)
            deinterleave(tmp_rec_buffer,
                         sub(rec_buffer,read:read+toread-1,:),
                         stream_wrapper.num_inputs, toread)
            read = read + toread
        end

        if toread <= 16 && towrite <= 16
            Libc.systemsleep(0.0005)
            #sleep(0.0005) # sleep() causes an increased number of allocations here
        end
    end
    Pa_StopStream(stream_wrapper.stream)
    nothing
end

"Write a buffer to a PortAudio stream"
function Base.write(stream_wrapper::PaStreamWrapper, buffer::PaBuffer, Nframes::Integer=size(buffer,1))
  (stream_wrapper.num_outputs > size(buffer,2) || Nframes > size(buffer,1)) &&
      error("Buffer dimensions do not fit stream parameters")

  tmp_play_buffer = zeros(stream_wrapper.sample_type, 20*4096)

  Pa_StartStream(stream_wrapper.stream)
  written::Integer = 1
  towrite::Integer = 0
  while true
       towrite = Pa_GetStreamWriteAvailable(stream_wrapper.stream)
       if towrite > 16
            if written + towrite > Nframes
            break
            end
            interleave(sub(buffer,written:written+towrite-1,1:stream_wrapper.num_outputs),
                     tmp_play_buffer, stream_wrapper.num_outputs, towrite)
            Pa_WriteStream(stream_wrapper.stream, tmp_play_buffer, towrite)
            written = written + towrite
        else
            Libc.systemsleep(0.0005)
            #sleep(0.0005) # sleep() causes an increased number of allocations here
        end
  end
  Pa_StopStream(stream_wrapper.stream)
  nothing
end

############ Low-level wrappers for Portaudio function calls ############
# Most part of this interface was taken from the
# [AudioIO.jl](https://github.com/ssfrr/AudioIO.jl) module

Pa_GetDeviceInfo(i) = unsafe_load(ccall((:Pa_GetDeviceInfo, libportaudio),
                                 Ptr{PaDeviceInfo}, (PaDeviceIndex,), i))
Pa_GetHostApiInfo(i) = unsafe_load(ccall((:Pa_GetHostApiInfo, libportaudio),
                                 Ptr{PaHostApiInfo}, (PaHostApiIndex,), i))

Pa_GetDeviceCount() = ccall((:Pa_GetDeviceCount, libportaudio), PaDeviceIndex, ())
Pa_GetDefaultInputDevice()  = ccall((:Pa_GetDefaultInputDevice, libportaudio), PaDeviceIndex, ())
Pa_GetDefaultOutputDevice() = ccall((:Pa_GetDefaultOutputDevice, libportaudio), PaDeviceIndex, ())


function Pa_Initialize()
    err = ccall((:Pa_Initialize, libportaudio), PaError, ())
    handle_status(err)
end

function Pa_Terminate()
    err = ccall((:Pa_Terminate, libportaudio), PaError, ())
    handle_status(err)
end

function Pa_StartStream(stream::PaStream)
    err = ccall((:Pa_StartStream, libportaudio), PaError,
                (PaStream,), stream)
    handle_status(err)
end

function Pa_StopStream(stream::PaStream)
    err = ccall((:Pa_StopStream, libportaudio), PaError,
                (PaStream,), stream)
    handle_status(err)
end

function Pa_CloseStream(stream::PaStream)
    err = ccall((:Pa_CloseStream, libportaudio), PaError,
                (PaStream,), stream)
    handle_status(err)
end

function Pa_GetStreamReadAvailable(stream::PaStream)
    avail = ccall((:Pa_GetStreamReadAvailable, libportaudio), Clong,
                (PaStream,), stream)
    avail >= 0 || handle_status(avail)
    avail
end

function Pa_GetStreamWriteAvailable(stream::PaStream)
    avail = ccall((:Pa_GetStreamWriteAvailable, libportaudio), Clong,
                (PaStream,), stream)
    avail >= 0 || handle_status(avail)
    avail
end

function Pa_ReadStream(stream::PaStream, buf::PaBuffer, frames::Integer=length(buf),
                       show_warnings::Bool=true)
    err = ccall((:Pa_ReadStream, libportaudio), PaError,
                (PaStream, Ptr{Void}, Culong),
                stream, buf, frames)
    handle_status(err, show_warnings)
    nothing
end

function Pa_WriteStream(stream::PaStream, buf::PaBuffer, frames::Integer=length(buf),
                        show_warnings::Bool=true)
    err = ccall((:Pa_WriteStream, libportaudio), PaError,
                (PaStream, Ptr{Void}, Culong),
                stream, buf, frames)
    handle_status(err, show_warnings)
    nothing
end

Pa_GetVersion() = ccall((:Pa_GetVersion, libportaudio), Cint, ())

function Pa_GetVersionText()
    versionPtr = ccall((:Pa_GetVersionText, libportaudio), Ptr{Cchar}, ())
    bytestring(versionPtr)
end

function Pa_OpenDefaultStream(inChannels::Integer, outChannels::Integer,
                              sampleFormat::PaSampleFormat,
                              sampleRate::Real, framesPerBuffer::Integer)
    streamPtr::Array{PaStream} = PaStream[0]
    err = ccall((:Pa_OpenDefaultStream, libportaudio),
                PaError, (Ptr{PaStream}, Cint, Cint,
                          PaSampleFormat, Cdouble, Culong,
                          Ptr{PaStreamCallback}, Ptr{Void}),
                streamPtr, inChannels, outChannels, sampleFormat, sampleRate,
                framesPerBuffer, C_NULL, C_NULL)
    handle_status(err)

    streamPtr[1]
end

function Pa_OpenStream(inputParam::PaStreamParameters, outputParam::PaStreamParameters,
                              sampleRate::Real, framesPerBuffer::Integer)
    streamPtr::Array{PaStream} = PaStream[0]

    if inputParam.channelCount == 0
      err = ccall((:Pa_OpenStream, libportaudio),
                  PaError, (Ptr{PaStream}, Ptr{PaStreamParameters}, Ptr{PaStreamParameters},
                            Cdouble, Culong, Culong,
                            Ptr{PaStreamCallback}, Ptr{Void}),
                  streamPtr, C_NULL, &outputParam, sampleRate,
                  framesPerBuffer, 0, C_NULL, C_NULL)
    elseif outputParam.channelCount == 0
      err = ccall((:Pa_OpenStream, libportaudio),
                  PaError, (Ptr{PaStream}, Ptr{PaStreamParameters}, Ptr{PaStreamParameters},
                            Cdouble, Culong, Culong,
                            Ptr{PaStreamCallback}, Ptr{Void}),
                  streamPtr, &inputParam, C_NULL, sampleRate,
                  framesPerBuffer, 0, C_NULL, C_NULL)
    else
      err = ccall((:Pa_OpenStream, libportaudio),
                  PaError, (Ptr{PaStream}, Ptr{PaStreamParameters}, Ptr{PaStreamParameters},
                            Cdouble, Culong, Culong,
                            Ptr{PaStreamCallback}, Ptr{Void}),
                  streamPtr, &inputParam, &outputParam, sampleRate,
                  framesPerBuffer, 0, C_NULL, C_NULL)
    end

    handle_status(err)

    streamPtr[1]
end

function handle_status(err::PaError, show_warnings::Bool=true)
    if err == PA_OUTPUT_UNDERFLOWED || err == PA_INPUT_OVERFLOWED
        if show_warnings
            msg = ccall((:Pa_GetErrorText, libportaudio),
                        Ptr{Cchar}, (PaError,), err)
            warn("libportaudio: " * bytestring(msg))
        end
    elseif err != PA_NO_ERROR
        msg = ccall((:Pa_GetErrorText, libportaudio),
                    Ptr{Cchar}, (PaError,), err)
        error("libportaudio: " * bytestring(msg))
    end
end

end # module
