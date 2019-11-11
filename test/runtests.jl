import JuliaCLI

@async JuliaCLI.serve()  # TODO: don't
let path = joinpath(DEPOT_PATH[1], "jlcli", "socket")
    for i in 1:100
        isfile(path) && break
        sleep(0.1)
    end
end

include("cli_test.jl")
