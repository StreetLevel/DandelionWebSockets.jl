import WebSocketClient: AbstractHandlerTaskProxy, AbstractWriterTaskProxy, AbstractClientTaskProxy,
    on_text, on_binary,
    state_connecting, state_open, state_closing, state_closed,
    write, handle, FrameFromServer

import Base.==

@mock MockHandlerTaskProxy AbstractHandlerTaskProxy
@mockfunction(MockHandlerTaskProxy,
    on_text, on_binary,
    state_connecting, state_open, state_closing, state_closed)

@mock MockWriterTaskProxy AbstractWriterTaskProxy
@mockfunction MockWriterTaskProxy write

#
# A fake RNG allows us to deterministically test functions that would otherwise behave
# pseudo-randomly.
#

type FakeRNG <: AbstractRNG
    values::Array{UInt8, 1}

    FakeRNG(v::Array{UInt8, 1}) = new(copy(v))
end

FakeRNG() = FakeRNG(Array{UInt8, 1}())

function Base.rand(rng::FakeRNG, ::Type{UInt8}, n::Int)
    @fact rng.values --> x -> !isempty(x)
    splice!(rng.values, 1:n)
end

#
# A lot of tests use WebSocket frames, naturally, so these are common frames that all tests can use.
#

nomask = Array{UInt8,1}()
mask = b"\x37\xfa\x21\x3d"

# A single frame with payload "Hello"
test_frame1 = Frame(true,  OPCODE_TEXT,         false, 5, 0, nomask, b"Hello")

# Two fragments of a text message with payload "Hello"
test_frame2 = Frame(false, OPCODE_TEXT,         false, 3, 0, nomask, b"Hel")
test_frame3 = Frame(true,  OPCODE_CONTINUATION, false, 2, 0, nomask, b"lo")

# A single text frame, masked, with body "Hello"
test_frame4 = Frame(true,  OPCODE_TEXT, true, 5, 0, mask, b"\x7f\x9f\x4d\x51\x58")

mask2 = b"\x17\x42\x03\x7f"

# Two masked fragments, one initial and one final. They are masked by two different masks.
test_frame5 = Frame(false, OPCODE_TEXT, true, 3, 0, mask, b"\x7f\x9f\x4d")
test_frame6 = Frame(true, OPCODE_CONTINUATION, true, 2, 0,  mask2, b"\x7b\x2d")

# Two binary fragments, one initial and one final.
frame_bin_start = Frame(false, OPCODE_BINARY,       false, 3, 0, nomask, b"Hel")
frame_bin_final = Frame(true,  OPCODE_CONTINUATION, false, 2, 0, nomask, b"lo")
frame_bin_1     = Frame(true,  OPCODE_BINARY,       false, 5, 0, nomask, b"Hello")

server_close_frame = Frame(true, OPCODE_CLOSE, false, 0, 0, nomask, b"")
client_close_reply = Frame(true, OPCODE_CLOSE, true, 0, 0, mask, b"")
server_ping_frame = Frame(true, OPCODE_PING, false, 0, 0, nomask, b"")
client_pong_frame = Frame(true, OPCODE_PONG, true, 0, 0, mask, b"")
server_ping_frame_w_pay = Frame(true, OPCODE_PING, false, 5, 0, nomask, b"Hello")
client_pong_frame_w_pay = Frame(true, OPCODE_PONG, true, 5, 0, mask, b"\x7f\x9f\x4d\x51\x58")

#
# To accurately test a fake TCPSocket I need a blocking stream.
# The implementation below is meant to be simple, not performant or good.
#
type BlockingStream <: IO
    buf::IOBuffer
end

function blocking_read(s::BlockingStream)
    x = nothing
    while true
        try
            x = read(s.buf, UInt8)
            return x
        catch ex
            if !isa(ex, EOFError)
                rethrow(ex)
            end
        end
        sleep(0.05)
    end
    x
end

function Base.read(s::BlockingStream, ::Type{UInt8})
    blocking_read(s)
end

function Base.read(s::BlockingStream, ::Type{Array{UInt8, 1}}, n::Int)
    buf = Array{UInt8, 1}(n)
    for i in 1:n
        buf[i] = blocking_read(s)
    end
    buf
end

function Base.read(s::BlockingStream, ::Type{UInt64})
    buf = read(s, Array{UInt8, 1}, 8)
    x::UInt64 =
        buf[1] << 56 | buf[2] << 48 << buf[3] << 40 | buf[4] << 32 |
        buf[5] << 24 | buf[6] << 16 << buf[7] << 8  | buf[8]
    x
end

function Base.read(s::BlockingStream, ::Type{UInt16})
    buf = read(s, Array{UInt8, 1}, 2)
    x::UInt16 = buf[1] << 8 | buf[2]
    x
end

#
# MockClientLogic mocks ClientLogic, and should have used the @mock macro, except that there are
# issues with FactCheck and doing asserts in other tasks. This custom mock ensures that all asserts
# are done afterwards, in the same task that created it.
#

==(a::FrameFromServer, b::FrameFromServer) = a.frame == b.frame

type MockClientLogic <: AbstractClientTaskProxy
    actuals::Vector{MockCall}
    expected::Vector{MockCall}

    MockClientLogic(expected::Vector{MockCall}) = new([], expected)
end

function call(m::MockClientLogic, s::Symbol, args...)
    push!(m.actuals, (s, collect(args)))
end

function check(m::MockClientLogic)
    #while !isempty(m.expected)
    #    @fact m.actuals --> not(isempty) "Expecting calls $(m.expected), but no more actual calls"
    #    (expected_func, expected_args) = shift!(m.expected)
    #    (actual_func, actual_args) = shift!(m.actuals)
    #
    #    @fact actual_func --> expected_func
    #    @fact actual_args --> expected_args
    #end

    @fact m.actuals --> m.expected
end

handle(m::MockClientLogic, args...) = call(m, :handle, args...)
