macro something(args...)
    something_impl(collect(args))
end

function something_impl(args)
    ex = quote
        throw(ArgumentError("All evaluated as `nothing`s."))
    end
    for x in reverse(args)
        ex = quote
            x = $(esc(x))
            if x !== nothing
                x
            else
                $ex
            end
        end
    end
    return ex
end
