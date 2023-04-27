function maxabs(
    maxval::T,
    updates::AbstractArray{T}
) where {T}
    return reduce(
        (x, y) -> max(abs(x), abs(y)),
        updates,
        init=maxval
    )
end

"""
    function optfirstpivot(
        f,
        localdims::Union{Vector{Int},NTuple{N,Int}},
        firstpivot::MultiIndex=ones(Int, length(localdims));
        maxsweep=1000
    ) where {N}

Optimize the first pivot for a tensor cross interpolation.

Arguments:
- `f` is function to be interpolated.
- `localdims::Union{Vector{Int},NTuple{N,Int}}` determines the local dimensions of the function parameters (see [`crossinterpolate`](@ref)).
- `fistpivot::MultiIndex=ones(Int, length(localdims))` is the starting point for the optimization. It is advantageous to choose it close to a global maximum of the function.
- `maxsweep` is the maximum number of optimization sweeps. Default: `1000`.

See also: [`crossinterpolate`](@ref)
"""
function optfirstpivot(
    f,
    localdims::Union{Vector{Int},NTuple{N,Int}},
    firstpivot::Vector{Int}=ones(Int, length(localdims));
    maxsweep=1000
) where {N}
    n = length(localdims)
    valf = abs(f(firstpivot))
    pivot = copy(firstpivot)

    for _ in 1:maxsweep
        valf_prev = valf
        for i in 1:n
            for d in 1:localdims[i]
                bak = pivot[i]
                pivot[i] = d
                if abs(f(pivot)) > valf
                    valf = abs(f(pivot))
                else
                    pivot[i] = bak
                end
            end
        end
        if valf_prev == valf
            break
        end
    end

    return pivot
end
