# JuliaCLI: Command line interface framework for Julia without JIT-compilation overhead

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://tkf.github.io/JuliaCLI.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://tkf.github.io/JuliaCLI.jl/dev)
[![Build Status](https://travis-ci.com/tkf/JuliaCLI.jl.svg?branch=master)](https://travis-ci.com/tkf/JuliaCLI.jl)
[![Codecov](https://codecov.io/gh/tkf/JuliaCLI.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/tkf/JuliaCLI.jl)
[![Coveralls](https://coveralls.io/repos/github/tkf/JuliaCLI.jl/badge.svg?branch=master)](https://coveralls.io/github/tkf/JuliaCLI.jl?branch=master)

Note: JuliaCLI does not work on Windows at the moment.

## Installation

```julia
(1.x) pkg> add https://github.com/tkf/JSONRPC.jl

(1.x) pkg> dev https://github.com/tkf/JuliaCLI.jl
```

(Note: I use `dev` for JuliaCLI.jl so that `jlcli` script would be at
the stable location.)

```console
$ ln -s ~/.julia/dev/JuliaCLI/jlcli/jlcli.py ~/bin/jlcli
```

In the above command, I'm assuming `~/bin` is in `$PATH`.

## Run CLI backend server

```console
$ cd ~/.julia/dev/JuliaCLI/scripts

$ ./serve.jl
```

Use `JULIA_CLI_REVISE=true ./serve.jl` instead if you want to reload
updates in the CLI worker processes (recommended).

## Example: instantaneous REPL

```console
$ jlcli --usemain --eval 'Base.run_main_repl(true, false, true, true, false)'
```

First run takes some time. But if you exit once and re-run the same
command, it is instantaneous.

## Example: `jlfmt`

[`jlfmt`](https://github.com/tkf/jlfmt) is a command-line interface to
[JuliaFormatter.jl](https://github.com/domluna/JuliaFormatter.jl).

```julia
(1.x) pkg> dev https://github.com/tkf/jlfmt
```

```console
$ ln -s ~/.julia/dev/jlfmt/bin/jlfmt ~/bin

$ jlfmt --help  # first run takes some time
```
