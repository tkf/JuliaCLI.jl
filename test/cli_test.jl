#!/bin/bash
# -*- mode: julia -*-
#=
JULIA="${JULIA:-julia}"
JULIA_CMD="${JULIA_CMD:-$JULIA --color=yes --startup-file=no}"
exec $JULIA_CMD -e 'include(popfirst!(ARGS))' "${BASH_SOURCE[0]}" "$@"
=#

module CLITest

using Test

const jlcli = joinpath(dirname(@__DIR__), "jlcli", "jlcli.py")

function test_cli(args)
    julia = Base.julia_cmd().exec[1]
    project = Base.active_project()
    cmd = `$jlcli --julia=$julia --project=$project $args`

    println()
    printstyled("_" ^ displaysize(stdout)[2]; color=:blue)
    @info "Executing a command:" cmd
    flush(stdout)
    flush(stderr)

    @test success(pipeline(cmd; stdout=stdout, stderr=stderr))
end

@testset begin
    test_cli(`--print-result --eval VERSION`)
    test_cli(`--print-result --callany='Statistics=10745b16-79ce-11e8-11f9-7d13ad32a3b2:std' '{"args":[[1,2,3]]}'`)
    test_cli(`--print-result --adhoccli='Unicode=4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5:normalize' -- -h`)
    test_cli(`--print-result --adhoccli='Unicode=4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5:normalize' -- --casefold JuLiA`)
end

end  # module
