struct WorkerSpec
    julia::String
    project::String
end

WorkerSpec(julia, ::Nothing) = WorkerSpec(julia, "@v#.#")

function initcommand(spec::WorkerSpec)
    cmd = `$(spec.julia) --startup-file=no $workerinitscript $(spec.project)`
    env = copy(ENV)
    env["JULIA_PROJECT"] = workerinitenv
    # env["JULIA_LOAD_PATH"] = "@"
    return setenv(cmd, env)
end

struct Worker
    spec::WorkerSpec
    process::Process
    client::JSONRPC.Client
end

workerinitenv = joinpath(@__DIR__, "workerinitenv", "Project.toml")
workerinitscript = joinpath(@__DIR__, "workerinitenv", "init.jl")

function Worker(spec::WorkerSpec)

    # TODO: don't
    run(`$(spec.julia) --startup-file=no --project=$workerinitenv -e "using Pkg; Pkg.instantiate()"`)

    cmd = initcommand(spec)
    @debug(
        "Launching a worker...",
        cmd = setenv(cmd, nothing),
        jl_env = [e for e in cmd.env if startswith(e, "JULIA_")],
    )

    pipe = Pipe()
    process = run(pipeline(cmd, stdout = pipe, stderr = stderr); wait = false)

    reader = @async readline(pipe)
    for i in 1:1000
        istaskdone(reader) && break
        process_exited(process) && break
        sleep(0.1)
        @debug "Waiting for worker..."
    end
    if !istaskdone(reader)
        @debug "Failed to launch a worker" spec process.exitcode
        process_exited(process) || kill(process)
        wait(process)
        let cmd = setenv(cmd, nothing)
            error("Process $cmd exited with code $(process.exitcode)")
        end
    end

    local client
    try
        path = fetch(reader)
        @debug "Worker started at: $path"
        client = JSONRPC.client(path, JSONRPC.NDJSON)
        close(pipe)
        @assert client.eval(code = "1")["result"] == 1
    catch
        kill(process)
        wait(process)
        rethrow()
    end
    return Worker(spec, process, client)
end

Base.isopen(worker::Worker) = isopen(worker.client)

request(worker::Worker, method::AbstractString, params) =
    fetch(JSONRPC.async_request(worker.client, method, params))

struct WorkerPool
    spec::WorkerSpec
    semaphore::Base.Semaphore
    available::Vector{Worker}
    # working::Set{Worker}
end
# Maybe use one semaphore for all pools handled by a broker?

WorkerPool(spec::WorkerSpec, limit::Integer = Sys.CPU_THREADS) =
    WorkerPool(spec, Base.Semaphore(limit), Worker[])

function acquiring(f, semaphore)
    Base.acquire(semaphore)
    try
        return f()
    finally
        Base.release(semaphore)
    end
end

function withworker!(f, pool::WorkerPool)
    acquiring(pool.semaphore) do
        if isempty(pool.available)
            worker = Worker(pool.spec)
        else
            worker = pop!(pool.available)
        end
        # push!(pool.working, worker)
        try
            f(worker)
        finally
            if isopen(worker)
                push!(pool.available, worker)
            end
            # delete!(pool.working, worker)
        end
    end
end
