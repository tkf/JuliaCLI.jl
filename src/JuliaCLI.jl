module JuliaCLI

import JSONRPC
using Base: Process
using Parameters: @unpack
using Pkg: TOML

include("rpcutils.jl")
include("utils.jl")
include("workers.jl")
include("broker.jl")
include("scripts.jl")

end # module
