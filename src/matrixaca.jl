mutable struct MatrixACA{T} <: AbstractMatrixCI{T}
    rowindices::Vector{Int}
    colindices::Vector{Int}

    u::Matrix{T} # u_k(x): (nrows, npivot)
    v::Matrix{T} # v_k(y): (npivot, ncols)
    alpha::Vector{T} # α = 1/δ: (npivot)

    function MatrixACA(
        ::Type{T},
        nrows::Int, ncols::Int
    ) where {T<:Number}
        return new{T}(Int[], Int[], zeros(nrows, 0), zeros(0, ncols), T[])
    end

    function MatrixACA(
        A::AbstractMatrix{T},
        firstpivot::Union{CartesianIndex{2},Tuple{Int,Int},Pair{Int,Int}}
    ) where {T<:Number}
        return new{T}(
            [firstpivot[1]], [firstpivot[2]],
            A[:, [firstpivot[2]]], A[[firstpivot[1]], :],
            [1 / A[firstpivot[1], firstpivot[2]]])
    end
end

nrows(aca::MatrixACA) = size(aca.u, 1)
ncols(aca::MatrixACA) = size(aca.v, 2)
npivots(aca::MatrixACA) = size(aca.u, 2)

function availablerows(aca::MatrixACA{T}) where {T}
    return setdiff(1:nrows(aca), aca.rowindices)
end

function availablecols(aca::MatrixACA{T}) where {T}
    return setdiff(1:ncols(aca), aca.colindices)
end

"""
Compute u_k(x) for all x
"""
function uk(aca::MatrixACA{T}, A) where {T}
    k = length(aca.colindices)
    yk = aca.colindices[end]
    result = copy(A[:, yk])
    u, v = aca.u, aca.v
    for l in 1:k-1
        xl = aca.rowindices[l]
        result -= (v[l, yk] / u[xl, l]) * u[:, l]
    end
    return result
end

function addpivotcol!(aca::MatrixACA{T}, a::AbstractMatrix{T}, yk::Int) where {T}
    push!(aca.colindices, yk)
    aca.u = hcat(aca.u, uk(aca, a))
end

"""
Compute v_k(y) for all y
"""
function vk(aca::MatrixACA{T}, A) where {T}
    k = length(aca.rowindices)
    xk = aca.rowindices[end]
    result = copy(A[xk, :])
    u, v = aca.u, aca.v
    for l in 1:k-1
        xl = aca.rowindices[l]
        result -= (u[xk, l] / u[xl, l]) * v[l, :]
    end
    return result
end

function addpivotrow!(aca::MatrixACA{T}, a::AbstractMatrix{T}, xk::Int) where {T}
    push!(aca.rowindices, xk)
    aca.v = vcat(aca.v, transpose(vk(aca, a)))
end

"""
    function addpivot!(a::AbstractMatrix{T}, aca::MatrixACA{T})

Find and add a new pivot according to the ACA algorithm in Kumar 2016 ()
"""
function addpivot!(
    a::AbstractMatrix{T},
    aca::MatrixACA{T},
    pivotindices::Union{CartesianIndex{2},Tuple{Int,Int},Pair{Int,Int}}
) where {T}
    addpivotcol!(aca, a, pivotindices[2])
    addpivotrow!(aca, a, pivotindices[1])
    push!(aca.alpha, 1 / aca.u[pivotindices[1], end])
end

function addpivot!(a::AbstractMatrix{T}, aca::MatrixACA{T}) where {T}
    availcols = availablecols(aca)
    yk = availcols[argmax(abs.(aca.v[end, availcols]))]
    addpivotcol!(aca, a, yk)

    availrows = availablerows(aca)
    xk = availrows[argmax(abs.(aca.u[availrows, end]))]
    addpivotrow!(aca, a, xk)

    push!(aca.alpha, 1 / aca.u[xk, end])
end

function Base.Matrix(aca::MatrixACA{T})::Matrix{T} where {T}
    return aca.u * Diagonal(aca.alpha) * aca.v
end

function evaluate(aca::MatrixACA{T})::Matrix{T} where {T}
    return Matrix(aca)
end

function evaluate(aca::MatrixACA{T}, i::Int, j::Int)::T where {T}
    if isempty(aca)
        return T(0)
    else
        np = npivots(aca)
        left = reshape(view(aca.u, i, :), 1, np)
        right = reshape(view(aca.v, :, j), np, 1)
        return (left*Diagonal(aca.alpha)*right)[1, 1]
    end
end

function submatrix(
    aca::MatrixACA{T},
    rows::Union{AbstractVector{Int},Colon,Int},
    cols::Union{AbstractVector{Int},Colon,Int}
)::Matrix{T} where {T}
    if isempty(aca)
        return zeros(
            T,
            _lengthordefault(rows, nrows(aca)),
            _lengthordefault(cols, ncols(aca)))
    else
        return sum(aca.u[rows, i] * aca.alpha[i] * aca.v[i, cols]' for i in 1:rank(aca))
        # return aca.u[rows, :] * Diagonal(aca.alpha) * aca.v[:, cols]
    end
end

# function adaptivecrossinterpolate(
#     a::AbstractMatrix{T};
#     tolerance=1e-6,
#     maxiter=200,
#     firstpivot=argmax(abs.(a))
# ) where {T}
#     aca = MatrixACA(a, firstpivot)
# end

function setcols!(
    aca::MatrixACA{T},
    newpivotrows::AbstractMatrix{T},
    permutation::Vector{Int}
) where {T}
    aca.colindices = permutation[aca.colindices]

    # Permute old elements
    tempv = Matrix{T}(undef, size(newpivotrows))
    tempv[:, permutation] = aca.v
    aca.v = tempv

    # Insert new elements
    newindices = setdiff(1:size(newpivotrows, 2), permutation)
    for k in 1:size(newpivotrows, 1)
        aca.v[k, newindices] = newpivotrows[k, newindices]
        for l in 1:k-1
            aca.v[k, newindices] -= aca.v[l, newindices] *
                                    (aca.u[aca.rowindices[k], l] * aca.alpha[l])
        end
    end
end

function setrows!(
    aca::MatrixACA{T},
    newpivotcols::AbstractMatrix{T},
    permutation::Vector{Int}
) where {T}
    aca.rowindices = permutation[aca.rowindices]

    # Permute old elements
    tempu = Matrix{T}(undef, size(newpivotcols))
    tempu[permutation, :] = aca.u
    aca.u = tempu

    # Insert new elements
    newindices = setdiff(1:size(newpivotcols, 1), permutation)
    for k in 1:size(newpivotcols, 2)
        aca.u[newindices, k] = newpivotcols[newindices, k]
        for l in 1:k-1
            aca.u[newindices, k] -= aca.u[newindices, l] *
                                    (aca.v[l, aca.colindices[k]] * aca.alpha[l])
        end
    end
end
