"""
    struct TensorTrain{ValueType}

Represents a tensor train, also known as MPS.

The tensor train can be evaluated using standard function call notation:
```julia
    tt = TensorTrain(...)
    value = tt([1, 2, 3, 4])
```
The corresponding function is:

    function (tt::TensorTrain{V})(indexset) where {V}

Evaluates the tensor train `tt` at indices given by `indexset`.
"""
mutable struct TensorTrain{ValueType,N} <: AbstractTensorTrain{ValueType}
    sitetensors::Vector{Array{ValueType,N}}

    function TensorTrain{ValueType,N}(sitetensors::AbstractVector{<:AbstractArray{ValueType,N}}) where {ValueType,N}
        for i in 1:length(sitetensors)-1
            if (last(size(sitetensors[i])) != size(sitetensors[i+1], 1))
                throw(ArgumentError(
                    "The tensors at $i and $(i+1) must have consistent dimensions for a tensor train."
                ))
            end
        end

        new{ValueType,N}(sitetensors)
    end
end

"""
    function TensorTrain(sitetensors::Vector{Array{V, 3}}) where {V}

Create a tensor train out of a vector of tensors. Each tensor should have links to the
previous and next tensor as dimension 1 and 3, respectively; the local index ("physical
index" for MPS in physics) is dimension 2.
"""
function TensorTrain(sitetensors::AbstractVector{<:AbstractArray{V,N}}) where {V,N}
    return TensorTrain{V,N}(sitetensors)
end

"""
    function TensorTrain(tci::AbstractTensorTrain{V}) where {V}

Convert a tensor-train-like object into a tensor train. This includes TCI1 and TCI2 objects.

See also: [`TensorCI1`](@ref), [`TensorCI2`](@ref).
"""
function TensorTrain(tci::AbstractTensorTrain{V})::TensorTrain{V,3} where {V}
    return TensorTrain{V,3}(sitetensors(tci))
end

function tensortrain(tci)
    return TensorTrain(tci)
end

function _factorize(
    A::Matrix{V}, method::Symbol; tolerance::Float64, maxbonddim::Int
) where {V}
    if method === :LU
        factorization = rrlu(A, abstol=tolerance, maxrank=maxbonddim)
        return left(factorization), right(factorization), npivots(factorization)
    elseif method === :CI
        factorization = MatrixLUCI(A, abstol=tolerance, maxrank=maxbonddim)
        return left(factorization), right(factorization), npivots(factorization)
    elseif method === :SVD
        factorization = LinearAlgebra.svd(A)
        trunci = min(
            replacenothing(findlast(>(tolerance), factorization.S), 1),
            maxbonddim
        )
        return (
            factorization.U[:, 1:trunci],
            Diagonal(factorization.S[1:trunci]) * factorization.Vt[1:trunci, :],
            trunci
        )
    else
        error("Not implemented yet.")
    end
end

"""
    function compress!(
        tt::TensorTrain{V, N},
        method::Symbol=:LU;
        tolerance::Float64=1e-12,
        maxbonddim=typemax(Int)
    ) where {V, N}

Compress the tensor train `tt` using `LU`, `CI` or `SVD` decompositions.
"""
function compress!(
    tt::TensorTrain{V, N},
    method::Symbol=:LU;
    tolerance::Float64=1e-12,
    maxbonddim::Int=typemax(Int)
) where {V, N}
    for ell in 1:length(tt)-1
        shapel = size(tt.sitetensors[ell])
        left, right, newbonddim = _factorize(
            reshape(tt.sitetensors[ell], prod(shapel[1:end-1]), shapel[end]),
            method; tolerance, maxbonddim
        )
        tt.sitetensors[ell] = reshape(left, shapel[1:end-1]..., newbonddim)
        shaper = size(tt.sitetensors[ell+1])
        nexttensor = right * reshape(tt.sitetensors[ell+1], shaper[1], prod(shaper[2:end]))
        tt.sitetensors[ell+1] = reshape(nexttensor, newbonddim, shaper[2:end]...)
    end

    for ell in length(tt):-1:2
        shaper = size(tt.sitetensors[ell])
        left, right, newbonddim = _factorize(
            reshape(tt.sitetensors[ell], shaper[1], prod(shaper[2:end])),
            method; tolerance, maxbonddim
        )
        tt.sitetensors[ell] = reshape(right, newbonddim, shaper[2:end]...)
        shapel = size(tt.sitetensors[ell-1])
        nexttensor = reshape(tt.sitetensors[ell-1], prod(shapel[1:end-1]), shapel[end]) * left
        tt.sitetensors[ell-1] = reshape(nexttensor, shapel[1:end-1]..., newbonddim)
    end

    nothing
end


"""
Fitting data with a TensorTrain object.
This may be useful when the interpolated function is noisy.
"""
struct TensorTrainFit{ValueType}
    indexsets::Vector{MultiIndex}
    values::Vector{ValueType}
    tt::TensorTrain{ValueType,3}
    offsets::Vector{Int}
end

function TensorTrainFit{ValueType}(indexsets, values, tt) where {ValueType}
    offsets = [0]
    for n in 1:length(tt)
        push!(offsets, offsets[end] + length(tt[n]))
    end
    return TensorTrainFit{ValueType}(indexsets, values, tt, offsets)
end

flatten(obj::TensorTrain{ValueType}) where {ValueType} = vcat(vec.(sitetensors(obj))...)

function to_tensors(obj::TensorTrainFit{ValueType}, x::Vector{ValueType}) where {ValueType}
    return [
        reshape(
            x[obj.offsets[n]+1:obj.offsets[n+1]],
            size(obj.tt[n])
        )
        for n in 1:length(obj.tt)
    ]
end

function _evaluate(tt::Vector{Array{V, 3}}, indexset) where {V}
    only(prod(T[:, i, :] for (T, i) in zip(tt, indexset)))
end

function (obj::TensorTrainFit{ValueType})(x::Vector{ValueType}) where {ValueType}
    tensors = to_tensors(obj, x)
    return sum((abs2(_evaluate(tensors, indexset) - obj.values[i]) for (i, indexset) in enumerate(obj.indexsets)))
end
