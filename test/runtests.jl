import TensorCrossInterpolation as TCI
using Test
using LinearAlgebra
import ITensors

include("_quantics.jl")

include("test_util.jl")
include("test_sweepstrategies.jl")
include("test_indexset.jl")
include("test_cachedfunction.jl")
include("test_matrixci.jl")
include("test_matrixaca.jl")
include("test_matrixlu.jl")
include("test_tensorci.jl")
include("test_tensorci2.jl")
include("test_tensortrain.jl")

if VERSION.major >= 2 || (VERSION.major == 1 && VERSION.minor >= 9)
    @testset "ITensor conversion interface" begin
        include("test_ttmpsconversion.jl")
        include("test_mpsutil.jl")
    end
end
