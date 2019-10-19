macro return_exception(ex)
    quote
        ans = $(esc(ex))
        ans isa Exception && return ans
        ans
    end
end

macro require_keyword_arguments(input)
    quote
        if !($(esc(input)) isa AbstractDict)
            return ArgumentError("Require keyword argument.")
        end
    end
end

macro ensure_exception(ex)
    quote
        err = $(esc(ex))
        if err isa Exception
            err
        else
            @error "Caught a non-exception type." exception = (err, catch_backtrace())
            ErrorException("Non-exception type `$(typeof(err))` is thrown.")
        end
    end
end

function try_impl(ex)
    quote
        try
            $(esc(ex))
        catch err
            return @ensure_exception err
        end
    end
end

@eval macro $(:try)(ex)
    try_impl(ex)
end

refine_values(x) = x
refine_values(x::AbstractVector) = refine_values.(x)
refine_values(x::AbstractDict) = Dict(zip(keys(x), refine_values.(values(x))))

function getstrings(dict, key)
    try
        return append!(String[], get(dict, key, []))
    catch err
        @debug "Converting `$key` failed." exception = (err, catch_backtrace())
        return ArgumentError("Keyword argument `$key` must be of a vector of strings.")
    end
end

const ReviseError = -3857439168074868810
