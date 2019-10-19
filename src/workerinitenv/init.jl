module __JuliaCLIInit

project, = ARGS

@debug "Loading packages..."

import JSONRPC
import Logging
using Pkg: Pkg, TOML
using Sockets: listen

include("../rpcutils.jl")
include("../evalutils.jl")

if lowercase(get(ENV, "JULIA_CLI_REVISE", "false")) == "true"
    try
        @eval begin
            using Revise: Revise, revise
            revise_success() = isempty(Revise.queue_errors)
        end
    catch err
        @error "using Revise" exception = (err, catch_backtrace())
    end
end
if !@isdefined revise
    revise() = nothing
    revise_success() = true
end

@debug "Loading packages...DONE"

function apicall(f, commonopts)
    cwd = commonopts.cwd
    ioconfig = commonopts.ioconfig
    ignorereturn = commonopts.ignorereturn
    (result, backtrace), out, err = with_stdio(ioconfig) do
        with_newlogger() do

            revise()
            if !revise_success()
                exit(113)  # TODO: don't
                return JSONRPC.Error(ReviseError, "Revise failed"), nothing
            end

            try
                cd(f, cwd), nothing
            catch err
                err, sprint(showerror, err, catch_backtrace())
            end
        end
    end
    if backtrace !== nothing || result isa Exception
        if result isa LoadError
            result = result.error
        end
        data = (stdout = out, stderr = err, backtrace = backtrace)
        return JSONRPC.usererror(sprint(showerror, result), data)
    end
    return (result = ignorereturn ? nothing : result, stdout = out, stderr = err)
end

function getcommonoptions(input)
    cwd = get(input, "cwd", pwd())
    cwd isa AbstractString || return ArgumentError("Keyword argument `cwd` must be of type `String`.")

    _ioconfig = @return_exception ioconfig(input)

    ignorereturn = get(input, "ignorereturn", false)
    ignorereturn isa Bool || return ArgumentError("Keyword argument `ignorereturn` must be a `nothing` or `Bool`.")

    commonopts = (cwd = cwd, ioconfig = _ioconfig, ignorereturn = ignorereturn)
    return commonopts
end

function eval_api(input)
    @require_keyword_arguments input
    @debug "eval_api" input

    code = get(input, "code", nothing)
    code isa AbstractString || return ArgumentError("Keyword argument `code` of type `String` is required.")

    usemain = get(input, "usemain", false)
    usemain isa Bool || return ArgumentError("Keyword argument `usemain` must be of type `Bool`.")

    args = @return_exception getstrings(input, "args")
    commonopts = @return_exception getcommonoptions(input)

    namespace = usemain ? Main : Module()
    @debug "Evaluating" code = Text(code) args namespace
    return apicall(commonopts) do
        append!(empty!(Base.ARGS), args)
        Base.include_string(namespace, code)
    end
end

function getcallable(input)
    pkgname = get(input, "pkgname", nothing)
    pkgname isa AbstractString || return ArgumentError("Keyword argument `pkgname` of type `String` is required.")

    pkguuid = get(input, "pkguuid", nothing)
    pkguuid isa AbstractString || return ArgumentError("Keyword argument `pkguuid` of type `String` is required.")
    pkguuid = @try Base.UUID(pkguuid)

    main = get(input, "main", nothing)
    main isa AbstractString || return ArgumentError("Keyword argument `main` of type `String` is required.")

    pkgid = Base.PkgId(pkguuid, pkgname)
    pkg = @try Base.require(pkgid)
    return @try mapfoldl(Symbol, getproperty, split(main, "."); init = pkg)
end

function callmain_api(input)
    @require_keyword_arguments input
    @debug "callmain_api" input

    commonopts = @return_exception getcommonoptions(input)
    f = @return_exception getcallable(input)
    args = @return_exception getstrings(input, "args")
    return apicall(commonopts) do
        Base.invokelatest(f, args)
    end
end

function callany_api(input)
    @require_keyword_arguments input
    @debug "callany_api" input

    commonopts = @return_exception getcommonoptions(input)

    args = get(input, "args", [])
    args isa AbstractVector || return ArgumentError("Keyword argument `args` must be of type `Vector`")
    args = refine_values(args)

    kwargs = get(input, "kwargs", Dict())
    kwargs isa AbstractDict || return ArgumentError("Keyword argument `kwargs` must be of type `Dict`")
    kwargs = Dict(Symbol(k) => v for (k, v) in refine_values(kwargs))

    f = @return_exception getcallable(input)
    return apicall(commonopts) do
        Base.invokelatest(f, args...; kwargs...)
    end
end

function help_api(input)
    @require_keyword_arguments input
    @debug "help_api" input
    mime = get(input, "mime", "text/plain")
    commonopts = @return_exception getcommonoptions(input)
    f = @return_exception getcallable(input)

    # Print to the terminal directly if appropriate:
    if mime === "text/plain" && commonopts.ioconfig.stdout !== nothing
        return apicall(commonopts) do
            show(stdout, mime, Docs.doc(f))
            println(stdout)
            return (result = nothing, output = nothing)
        end
    end

    docstr = sprint(show, mime, Docs.doc(f)) * "\n"
    return (result = nothing, output = docstr)
end

dispatcher = Dict(
    # JSONRPC method name => implementation
    "eval" => eval_api,
    "callmain" => callmain_api,
    "callany" => callany_api,
    "help" => help_api,
)

function project_toml_from_manifest_toml(
    projectpath::AbstractString,
    manifestpath::AbstractString,
)
    open(projectpath, write = true) do io
        project_toml_from_manifest_toml(io, manifestpath)
    end
end

function project_toml_from_manifest_toml(io::IO, manifestpath::AbstractString)
    manifest = TOML.parsefile(manifestpath)
    deps = map(keys(manifest), values(manifest)) do k, v
        k => v[1]["uuid"]
    end

    println(io, "[deps]")
    for (pkg, uuid) in deps
        println(io, pkg, " = ", repr(uuid))
    end
end

function as_proper_project(f, project)
    if startswith(project, "@") ||
       isdir(project) || basename(project) in ("Project.toml", "JuliaProject.toml")
        return f(Base.load_path_expand(project))
    end

    mktempdir() do dir
        cp(project, joinpath(dir, "Manifest.toml"))
        tomlpath = joinpath(dir, "Project.toml")
        project_toml_from_manifest_toml(tomlpath, project)
        @debug("Project.toml created", Project_toml = Text(read(tomlpath, String)))

        f(tomlpath)
    end
end

let periodstr = get(ENV, "JULIA_CLI_PERIODIC_GC", "no")
    if all(isdigit, periodstr)
        period = parse(Int, periodstr)
        @debug "Calling `GC.gc()` every $period seconds..."
        @async while true
            sleep(period)
            GC.gc()
        end
    end
end

mktempdir(prefix = "juliacli_") do dir
    path = joinpath(dir, "socket")
    @debug "Launching worker server at: $path"
    server = listen(path)
    println(path)
    close(stdout)
    redirect_stdout(stderr)  # required for `Pkg.activate`?
    try
        as_proper_project(project) do project
            Pkg.activate(project)
            JSONRPC.serve(dispatcher, server, JSONRPC.NDJSON)
        end
    catch err
        @error "JSONRPC.serve" exception = (err, catch_backtrace())
    finally
        @debug "Stopped worker server at: $path"
    end
end

end
