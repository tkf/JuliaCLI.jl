using Documenter, JuliaCLI

makedocs(;
    modules=[JuliaCLI],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/tkf/JuliaCLI.jl/blob/{commit}{path}#L{line}",
    sitename="JuliaCLI.jl",
    authors="Takafumi Arakaki <aka.tkf@gmail.com>",
    assets=String[],
)

deploydocs(;
    repo="github.com/tkf/JuliaCLI.jl",
)
