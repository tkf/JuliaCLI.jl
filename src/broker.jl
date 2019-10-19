struct Broker
    workers::Dict{WorkerSpec, WorkerPool}
end

Broker() = Broker(Dict())

function request!(broker::Broker, spec::WorkerSpec, method::AbstractString, params)
    withworker!(get!(broker.workers, spec, WorkerPool(spec))) do worker
        return request(worker, method, params)
    end
end

function evalon!(
    broker::Broker,
    spec::WorkerSpec,
    code::AbstractString,
    options::AbstractDict,
)
    @assert !haskey(options, "code")  # what about `:code`?
    params = merge(Dict("code" => code), options)
    return request!(broker, spec, "eval", params)
end

function popspec!(options)
    julia = pop!(options, "julia", nothing)
    julia isa AbstractString ||
        return ArgumentError("Keyword argument `julia` of type `String` is required.")

    project = pop!(options, "project", nothing)
    project isa AbstractString || project === nothing ||
        return ArgumentError("Keyword argument `project` must be a `String`.")

    return WorkerSpec(julia, project)
end

struct EvalAPI
    broker::Broker
end

function (api::EvalAPI)(input)
    if !(input isa AbstractDict)
        return ArgumentError("API `eval` requires keyword argument.")
    end
    # Pass-through unhandled arguments to the worker:
    options = copy(input)

    spec = @return_exception popspec!(options)

    code = pop!(options, "code", nothing)
    code isa AbstractString ||
        return ArgumentError("Keyword argument `code` of type `AbstractString` is required.")

    return evalon!(api.broker, spec, code, options)
end

struct RunAPI
    broker::Broker
end

function (api::RunAPI)(input)
    if !(input isa AbstractDict)
        return ArgumentError("API `run` requires keyword argument.")
    end
    # Pass-through unhandled arguments to the worker:
    options = copy(input)

    script = pop!(options, "script", nothing)
    script isa AbstractString ||
        return ArgumentError("Keyword argument `script` of type `String` is required.")

    @unpack julia, project, code = @return_exception parse_script(script)

    return evalon!(api.broker, WorkerSpec(julia, project), code, options)
end

struct CallMainAPI
    broker::Broker
end

function (api::CallMainAPI)(input)
    if !(input isa AbstractDict)
        return ArgumentError("API `callmain` requires keyword argument.")
    end
    # Pass-through unhandled arguments to the worker:
    options = copy(input)

    spec = @return_exception popspec!(options)
    return request!(api.broker, spec, "callmain", options)
end

struct CallAnyAPI
    broker::Broker
end

function (api::CallAnyAPI)(input)
    if !(input isa AbstractDict)
        return ArgumentError("API `callany` requires keyword argument.")
    end
    # Pass-through unhandled arguments to the worker:
    options = copy(input)

    spec = @return_exception popspec!(options)
    return request!(api.broker, spec, "callany", options)
end

struct HelpAPI
    broker::Broker
end

function (api::HelpAPI)(input)
    if !(input isa AbstractDict)
        return ArgumentError("API `help` requires keyword argument.")
    end
    # Pass-through unhandled arguments to the worker:
    options = copy(input)

    spec = @return_exception popspec!(options)
    return request!(api.broker, spec, "help", options)
end

struct AdHocCLIAPI
    broker::Broker
end

function option_as_kwargname(opt::AbstractString)
    opt = replace(opt, r"^--?" => "")
    opt = replace(opt, "-" => "_")
    return opt
end

function auto_parse_option(val::AbstractString)
    return @something(
        tryparse(Bool, val),
        tryparse(Int, val),
        tryparse(Float64, val),
        val,
    )
end

function parse_adhoc_cli_args(cliargs::AbstractVector)
    args = String[]
    kwargs = Dict{String,Any}()
    for a in cliargs
        if startswith(a, "-")
            if occursin("=", a)
                k, v = split(a, "="; limit=2)
                kwargs[option_as_kwargname(k)] = auto_parse_option(v)
            else
                kwargs[option_as_kwargname(a)] = true
            end
        else
            push!(args, a)
        end
    end
    return args, kwargs
end

function (api::AdHocCLIAPI)(input)
    if !(input isa AbstractDict)
        return ArgumentError("API `adhoccli` requires keyword argument.")
    end
    # Pass-through unhandled arguments to the worker:
    options = copy(input)

    spec = @return_exception popspec!(options)
    cliargs = @return_exception getstrings(options, "args")

    if ["--help"] == cliargs || ["-h"] == cliargs
        return request!(api.broker, spec, "help", options)
    end

    options["args"], options["kwargs"] = parse_adhoc_cli_args(cliargs)
    return request!(api.broker, spec, "callany", options)
end

function serve(server)
    broker = Broker()
    dispatcher = Dict{String, Any}(
        "eval" => EvalAPI(broker),
        "run" => RunAPI(broker),
        "callmain" => CallMainAPI(broker),
        "callany" => CallAnyAPI(broker),
        "help" => HelpAPI(broker),
        "adhoccli" => AdHocCLIAPI(broker),
    )
    JSONRPC.serve(dispatcher, server, JSONRPC.NDJSON)
end

function serve()
    path = joinpath(DEPOT_PATH[1], "jlcli", "socket")
    jlclidir = dirname(path)
    if !isdir(jlclidir)
        mkpath(jlclidir)
    end
    serve(path)
end
