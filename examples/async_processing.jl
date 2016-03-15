using PortAudio, DSP

# config
buf_size = 1024
sample_rate = 48000
num_channels = 2

# use default device
devID = -1

# -----
# this is a simple bandpass filter PaProcessor type
type FilterProcessor{FS, Channels} <: PaProcessor{FS, Channels}
    filt
    process::Function
    function FilterProcessor(f1, f2, order)
      proc = new()
      proc.filt = []
      for c=1:Channels
          responsetype = Bandpass(f1, f2, fs=FS)
          designmethod = Butterworth(order)
          tmp = digitalfilter(responsetype, designmethod)
          tmp = convert(PolynomialRatio, tmp)
          push!(proc.filt, DF2TFilter(tmp))
      end

      proc.process = function (input_buffer, output_buffer)
          for c=1:size(input_buffer,2)
              output_buffer[:,c] = filt(proc.filt[c], input_buffer[:,c]) ./ 2
          end
      end

      return proc
    end
end
# ------

# -----
# Main part starts here

println("""\n\nThis is a realtime audio IO demo. It will read from the soundcard input,
process samples with a bandpass filter and finally send it directly to the speakers.\n""")
println("""WARNING: this may cause a feedback loop. Increase the volume of your
speakers slowly and carefully! (Press any key to continue, CTRL-C to abort...)""")
readline(STDIN)

# create a filter processor object
filtproc = FilterProcessor{sample_rate, num_channels}(1000, 2000, 4)

 # open the stream and connect it with the callback
stream = open(devID, filtproc, (num_channels, num_channels), sample_rate, buf_size)

println("Stream is running. Press CTRL-C to stop it...")
try
    while true
        sleep(0.001)
    end
catch e
    if isa(e, InterruptException)
        close(stream)
    else
        throw(e)
    end
end
