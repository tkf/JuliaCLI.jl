struct ToSTDOUT end

struct IOConfig
    stdin::Union{String,Nothing}
    stdout::Union{String,Nothing}
    stderr::Union{String,Nothing,ToSTDOUT}
end

function ioconfig(input::AbstractDict{<:AbstractString})
    function pathfor(name)
        stream = get(input, name, nothing)
        stream === nothing && return nothing
        path = get(stream, "path", nothing)
        path == nothing || path isa AbstractString ||
            return ArgumentError("Keyword argument `$name.path` must be a `nothing` or `String`.")
        return path
    end

    function pathforstderr()
        path = pathfor("stderr")
        path === nothing || return path
        stream = get(input, "stderr", nothing)
        stream === nothing && return ToSTDOUT()
        to = get(stream, "to", "file")
        to === "file" && return path
        to in ("file", "stdout") ||
            return ArgumentError("""Keyword argument `stderr.to` must be `"file"` or `"stdout"`.""")
        @assert to === "stdout"
        return ToSTDOUT()
    end

    return IOConfig(
        (@return_exception pathfor("stdin")),
        (@return_exception pathfor("stdout")),
        (@return_exception pathforstderr()),
    )
end

function with_pipe(f)
    pipe = Base.link_pipe!(Pipe())
    reader = @async read(pipe, String)
    result = try
        f(pipe.in)
    finally
        close(pipe)
    end
    return (result, fetch(reader))
end

function with_file(f, path; kwargs...)
    result = open(path; kwargs...) do io
        fileno = fd(io)
        if ccall(:isatty, Cint, (Cint,), fileno) == 1
            tty = Base.TTY(Libc.dup(RawFD(fileno)))
            have_color = Base.have_color
            try
                @eval Base have_color = true
                f(tty)
            finally
                close(tty)
                @eval Base have_color = $have_color
            end
        else
            f(io)
        end
    end
    return (result, nothing)
end

with_stdout(f, ::Nothing) = with_pipe(io -> redirect_stdout(f, io))
with_stderr(f, ::Nothing) = with_pipe(io -> redirect_stderr(f, io))

with_stdout(f, path::AbstractString) =
    with_file(io -> redirect_stdout(f, io), path, write = true)
with_stderr(f, path::AbstractString) =
    with_file(io -> redirect_stderr(f, io), path, write = true)

with_stderr(f, ::ToSTDOUT) = redirect_stderr(f, stdout), nothing

with_stdin(f, ::Nothing) = f(), nothing  # use devnull?
with_stdin(f, path::AbstractString) =
    with_file(io -> redirect_stdin(f, io), path, read = true)

function with_stdio(f, ioconfig::IOConfig)
    (((result, _), err), out) = with_stdout(ioconfig.stdout) do
        with_stderr(ioconfig.stderr) do
            with_stdin(ioconfig.stdin) do
                f()
            end
        end
    end
    return (result, out, err)
end

function with_newlogger(f)
    if stderr isa Base.TTY
        logger = Logging.ConsoleLogger(stderr)
    else
        logger = Base.CoreLogging.SimpleLogger(stderr)
    end
    return Base.CoreLogging.with_logger(f, logger)
end
