function parse_script(script::AbstractString)
    optlines = String[]
    codelines = String[]
    open(script) do file
        while true
            l = readline(file)
            l === "# ```julia" && @goto juliafound
            l === "# ```jlcli" && break
            eof(file) && return
        end
        while true
            l = readline(file)
            l === "# ```" && break
            push!(optlines, l)
            eof(file) && return
        end
        while true
            l = readline(file)
            l === "# ```julia" && break
            eof(file) && return
        end
        @label juliafound
        while true
            l = readline(file)
            l === "# ```" && break
            push!(codelines, l)
            eof(file) && return
        end
    end
    if isempty(codelines)
        return ErrorException("No ```julia ... ``` block in script: $script")
    end
    if !all(startswith(l, "# ") for l in optlines)
        return ErrorException(string(
            "Invalid ```jlcli ... ``` block in script: $script\n",
            "Some lines do not start with `# `."
        ))
    end
    if !all(startswith(l, "# ") for l in codelines)
        return ErrorException(string(
            "Invalid ```julia ... ``` block in script: $script\n",
            "Some lines do not start with `# `."
        ))
    end
    strip2(l) = chop(l, head=2, tail=0)
    map!(strip2, codelines, codelines)
    map!(strip2, optlines, optlines)

    # TODO: use parser
    optsetup = join(optlines, "\n")
    m = Module()
    try
        include_string(m, optsetup)
    catch err
        return err
    end
    if :julia ∈ names(m)
        julia = m.julia
        julia isa AbstractString ||
            return ArgumentError("`julia` option must be a `String`. Got:\n$julia")
    else
        julia = "julia"
    end

    project = realpath(script)
    code = join(codelines, "\n")
    return (julia = julia, project = project, code = code)
end


function compilescript(
    io::IO,
    code,
    manifest::AbstractString;
    julia::Union{AbstractString, Nothing} = nothing,
)
    print(
        io,
        """
        #!/usr/bin/env jlcli
        # This file is created by JuliaCLI.jl
        """,
    )
    if julia !== nothing
        print(
            io,
            """
            #
            # ```jlcli
            # julia = $(repr(julia))
            # ```
            """,
        )
    end
    print(
        io,
        """
        #
        # ```julia
        """
    )
    for line in split(code, "\n")
        println(io, "# ", line)
    end
    print(
        io,
        """
        # ```
        #
        """
    )
    write(io, read(manifest))
end


function compilescript(
    scriptpath::AbstractString,
    code,
    manifest::AbstractString;
    julia::Union{AbstractString, Nothing} = nothing,
    overwrite::Bool = false,
)
    if isfile(scriptpath) && !overwrite
        error("File `$scriptpath` exists.")
    end
    open(scriptpath, write=true) do io
        compilescript(io, code, manifest; julia=julia)
    end
    Base.Filesystem.chmod(scriptpath, 0o777)
end
