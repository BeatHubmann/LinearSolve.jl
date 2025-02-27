macro get_cacheval(cache, algsym)
    quote
        if $(esc(cache)).alg isa DefaultLinearSolver
            getfield($(esc(cache)).cacheval, $algsym)
        else
            $(esc(cache)).cacheval
        end
    end
end

_ldiv!(x, A, b) = ldiv!(x, A, b)

function _ldiv!(x::Vector, A::Factorization, b::Vector)
    # workaround https://github.com/JuliaLang/julia/issues/43507
    copyto!(x, b)
    ldiv!(A, x)
end

#RF Bad fallback: will fail if `A` is just a stand-in
# This should instead just create the factorization type.
function init_cacheval(alg::AbstractFactorization, A, b, u, Pl, Pr, maxiters::Int, abstol,
    reltol, verbose::Bool, assumptions::OperatorAssumptions)
    do_factorization(alg, convert(AbstractMatrix, A), b, u)
end

## LU Factorizations

"""
`LUFactorization(pivot=LinearAlgebra.RowMaximum())`

Julia's built in `lu`. Equivalent to calling `lu!(A)`
    
* On dense matrices, this uses the current BLAS implementation of the user's computer,
which by default is OpenBLAS but will use MKL if the user does `using MKL` in their
system.
* On sparse matrices, this will use UMFPACK from SuiteSparse. Note that this will not
cache the symbolic factorization.
* On CuMatrix, it will use a CUDA-accelerated LU from CuSolver.
* On BandedMatrix and BlockBandedMatrix, it will use a banded LU.

## Positional Arguments

* pivot: The choice of pivoting. Defaults to `LinearAlgebra.RowMaximum()`. The other choice is
  `LinearAlgebra.NoPivot()`.
"""
struct LUFactorization{P} <: AbstractFactorization
    pivot::P
end

"""
`GenericLUFactorization(pivot=LinearAlgebra.RowMaximum())`

Julia's built in generic LU factorization. Equivalent to calling LinearAlgebra.generic_lufact!.
Supports arbitrary number types but does not achieve as good scaling as BLAS-based LU implementations.
Has low overhead and is good for small matrices.

## Positional Arguments

* pivot: The choice of pivoting. Defaults to `LinearAlgebra.RowMaximum()`. The other choice is
  `LinearAlgebra.NoPivot()`.
"""
struct GenericLUFactorization{P} <: AbstractFactorization
    pivot::P
end

function LUFactorization()
    pivot = @static if VERSION < v"1.7beta"
        Val(true)
    else
        RowMaximum()
    end
    LUFactorization(pivot)
end

function GenericLUFactorization()
    pivot = @static if VERSION < v"1.7beta"
        Val(true)
    else
        RowMaximum()
    end
    GenericLUFactorization(pivot)
end

function do_factorization(alg::LUFactorization, A, b, u)
    A = convert(AbstractMatrix, A)
    if A isa AbstractSparseMatrixCSC
        return lu(SparseMatrixCSC(size(A)..., getcolptr(A), rowvals(A), nonzeros(A)),
            check = false)
    else
        fact = lu!(A, alg.pivot, check = false)
    end
    return fact
end

function do_factorization(alg::GenericLUFactorization, A, b, u)
    A = convert(AbstractMatrix, A)
    fact = LinearAlgebra.generic_lufact!(A, alg.pivot, check = false)
    return fact
end

function init_cacheval(alg::Union{LUFactorization, GenericLUFactorization}, A, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.lu_instance(convert(AbstractMatrix, A))
end

const PREALLOCATED_LU = ArrayInterface.lu_instance(rand(1, 1))

function init_cacheval(alg::Union{LUFactorization, GenericLUFactorization},
    A::Matrix{Float64}, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    PREALLOCATED_LU
end

function init_cacheval(alg::Union{LUFactorization, GenericLUFactorization},
    A::AbstractSciMLOperator, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    nothing
end

@static if VERSION < v"1.9-"
    function init_cacheval(alg::Union{LUFactorization, GenericLUFactorization},
        A::Union{Diagonal, SymTridiagonal}, b, u, Pl, Pr,
        maxiters::Int, abstol, reltol, verbose::Bool,
        assumptions::OperatorAssumptions)
        nothing
    end
end

## QRFactorization

"""
`QRFactorization(pivot=LinearAlgebra.NoPivot(),blocksize=16)`

Julia's built in `qr`. Equivalent to calling `qr!(A)`.
    
* On dense matrices, this uses the current BLAS implementation of the user's computer
which by default is OpenBLAS but will use MKL if the user does `using MKL` in their
system.
* On sparse matrices, this will use SPQR from SuiteSparse
* On CuMatrix, it will use a CUDA-accelerated QR from CuSolver.
* On BandedMatrix and BlockBandedMatrix, it will use a banded QR.
"""
struct QRFactorization{P} <: AbstractFactorization
    pivot::P
    blocksize::Int
    inplace::Bool
end

function QRFactorization(inplace = true)
    pivot = @static if VERSION < v"1.7beta"
        Val(false)
    else
        NoPivot()
    end
    QRFactorization(pivot, 16, inplace)
end

function do_factorization(alg::QRFactorization, A, b, u)
    A = convert(AbstractMatrix, A)
    if alg.inplace && !(A isa SparseMatrixCSC) && !(A isa GPUArraysCore.AbstractGPUArray)
        fact = qr!(A, alg.pivot)
    else
        fact = qr(A) # CUDA.jl does not allow other args!
    end
    return fact
end

function init_cacheval(alg::QRFactorization, A, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.qr_instance(convert(AbstractMatrix, A), alg.pivot)
end

const PREALLOCATED_QR = ArrayInterface.qr_instance(rand(1, 1))

@static if VERSION < v"1.7beta"
    function init_cacheval(alg::QRFactorization{Val{false}}, A::Matrix{Float64}, b, u, Pl,
        Pr,
        maxiters::Int, abstol, reltol, verbose::Bool,
        assumptions::OperatorAssumptions)
        PREALLOCATED_QR
    end
else
    function init_cacheval(alg::QRFactorization{NoPivot}, A::Matrix{Float64}, b, u, Pl, Pr,
        maxiters::Int, abstol, reltol, verbose::Bool,
        assumptions::OperatorAssumptions)
        PREALLOCATED_QR
    end
end

function init_cacheval(alg::QRFactorization, A::AbstractSciMLOperator, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    nothing
end

@static if VERSION < v"1.9-"
    function init_cacheval(alg::QRFactorization,
        A::Union{Diagonal, SymTridiagonal, Tridiagonal}, b, u, Pl, Pr,
        maxiters::Int, abstol, reltol, verbose::Bool,
        assumptions::OperatorAssumptions)
        nothing
    end
end

## CholeskyFactorization

"""
`CholeskyFactorization(; pivot = nothing, tol = 0.0, shift = 0.0, perm = nothing)`

Julia's built in `cholesky`. Equivalent to calling `cholesky!(A)`.

## Keyword Arguments

* pivot: defaluts to NoPivot, can also be RowMaximum.
* tol: the tol argument in CHOLMOD. Only used for sparse matrices.
* shift: the shift argument in CHOLMOD. Only used for sparse matrices.
* perm: the perm argument in CHOLMOD. Only used for sparse matrices.
"""
struct CholeskyFactorization{P, P2} <: AbstractFactorization
    pivot::P
    tol::Int
    shift::Float64
    perm::P2
end

function CholeskyFactorization(; pivot = nothing, tol = 0.0, shift = 0.0, perm = nothing)
    if pivot === nothing
        pivot = @static if VERSION < v"1.8beta"
            Val(false)
        else
            NoPivot()
        end
    end
    CholeskyFactorization(pivot, 16, shift, perm)
end

@static if VERSION > v"1.8-"
    function do_factorization(alg::CholeskyFactorization, A, b, u)
        A = convert(AbstractMatrix, A)
        if A isa SparseMatrixCSC
            fact = cholesky!(A; shift = alg.shift, check = false, perm = alg.perm)
        elseif alg.pivot === Val(false) || alg.pivot === NoPivot()
            fact = cholesky!(A, alg.pivot; check = false)
        else
            fact = cholesky!(A, alg.pivot; tol = alg.tol, check = false)
        end
        return fact
    end
else
    function do_factorization(alg::CholeskyFactorization, A, b, u)
        A = convert(AbstractMatrix, A)
        if A isa SparseMatrixCSC
            fact = cholesky!(A; shift = alg.shift, perm = alg.perm)
        elseif alg.pivot === Val(false) || alg.pivot === NoPivot()
            fact = cholesky!(A, alg.pivot)
        else
            fact = cholesky!(A, alg.pivot; tol = alg.tol)
        end
        return fact
    end
end

function init_cacheval(alg::CholeskyFactorization, A, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.cholesky_instance(convert(AbstractMatrix, A), alg.pivot)
end

@static if VERSION < v"1.8beta"
    cholpivot = Val(false)
else
    cholpivot = NoPivot()
end

const PREALLOCATED_CHOLESKY = ArrayInterface.cholesky_instance(rand(1, 1), cholpivot)

function init_cacheval(alg::CholeskyFactorization, A::Matrix{Float64}, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    PREALLOCATED_CHOLESKY
end

function init_cacheval(alg::CholeskyFactorization,
    A::Union{Diagonal, AbstractSciMLOperator}, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    nothing
end

@static if VERSION < v"1.9beta"
    function init_cacheval(alg::CholeskyFactorization,
        A::Union{SymTridiagonal, Tridiagonal}, b, u, Pl, Pr,
        maxiters::Int, abstol, reltol, verbose::Bool,
        assumptions::OperatorAssumptions)
        nothing
    end

    function init_cacheval(alg::CholeskyFactorization,
        A::Adjoint{<:Number, <:Array}, b, u, Pl, Pr,
        maxiters::Int, abstol, reltol, verbose::Bool,
        assumptions::OperatorAssumptions)
        nothing
    end
end

## LDLtFactorization

struct LDLtFactorization{T} <: AbstractFactorization
    shift::Float64
    perm::T
end

function LDLtFactorization(shift = 0.0, perm = nothing)
    LDLtFactorization(shift, perm)
end

function do_factorization(alg::LDLtFactorization, A, b, u)
    A = convert(AbstractMatrix, A)
    if !(A isa SparseMatrixCSC)
        fact = ldlt!(A)
    else
        fact = ldlt!(A, shift = alg.shift, perm = alg.perm)
    end
    return fact
end

function init_cacheval(alg::LDLtFactorization, A, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol,
    verbose::Bool, assumptions::OperatorAssumptions)
    nothing
end

function init_cacheval(alg::LDLtFactorization, A::SymTridiagonal, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.ldlt_instance(convert(AbstractMatrix, A))
end

## SVDFactorization

"""
`SVDFactorization(full=false,alg=LinearAlgebra.DivideAndConquer())`

Julia's built in `svd`. Equivalent to `svd!(A)`.
    
* On dense matrices, this uses the current BLAS implementation of the user's computer
which by default is OpenBLAS but will use MKL if the user does `using MKL` in their
system.
"""
struct SVDFactorization{A} <: AbstractFactorization
    full::Bool
    alg::A
end

SVDFactorization() = SVDFactorization(false, LinearAlgebra.DivideAndConquer())

function do_factorization(alg::SVDFactorization, A, b, u)
    A = convert(AbstractMatrix, A)
    fact = svd!(A; full = alg.full, alg = alg.alg)
    return fact
end

function init_cacheval(alg::SVDFactorization, A::Matrix, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.svd_instance(convert(AbstractMatrix, A))
end

const PREALLOCATED_SVD = ArrayInterface.svd_instance(rand(1, 1))

function init_cacheval(alg::SVDFactorization, A::Matrix{Float64}, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    PREALLOCATED_SVD
end

function init_cacheval(alg::SVDFactorization, A, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    nothing
end

@static if VERSION < v"1.9-"
    function init_cacheval(alg::SVDFactorization,
        A::Union{Diagonal, SymTridiagonal, Tridiagonal}, b, u, Pl, Pr,
        maxiters::Int, abstol, reltol, verbose::Bool,
        assumptions::OperatorAssumptions)
        nothing
    end
end

## BunchKaufmanFactorization

"""
`BunchKaufmanFactorization(; rook = false)`

Julia's built in `bunchkaufman`. Equivalent to calling `bunchkaufman(A)`.
Only for Symmetric matrices.

## Keyword Arguments

* rook: whether to perform rook pivoting. Defaults to false.
"""
Base.@kwdef struct BunchKaufmanFactorization <: AbstractFactorization
    rook::Bool = false
end

function do_factorization(alg::BunchKaufmanFactorization, A, b, u)
    A = convert(AbstractMatrix, A)
    fact = bunchkaufman!(A, alg.rook; check = false)
    return fact
end

function init_cacheval(alg::BunchKaufmanFactorization, A::Symmetric{<:Number, <:Matrix}, b,
    u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.bunchkaufman_instance(convert(AbstractMatrix, A))
end

const PREALLOCATED_BUNCHKAUFMAN = ArrayInterface.bunchkaufman_instance(Symmetric(rand(1,
    1)))

function init_cacheval(alg::BunchKaufmanFactorization,
    A::Symmetric{Float64, Matrix{Float64}}, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    PREALLOCATED_BUNCHKAUFMAN
end

function init_cacheval(alg::BunchKaufmanFactorization, A, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    nothing
end

## GenericFactorization

"""
`GenericFactorization(;fact_alg=LinearAlgebra.factorize)`: Constructs a linear solver from a generic
    factorization algorithm `fact_alg` which complies with the Base.LinearAlgebra
    factorization API. Quoting from Base:
    
      * If `A` is upper or lower triangular (or diagonal), no factorization of `A` is
        required. The system is then solved with either forward or backward substitution.
        For non-triangular square matrices, an LU factorization is used.
        For rectangular `A` the result is the minimum-norm least squares solution computed by a
        pivoted QR factorization of `A` and a rank estimate of `A` based on the R factor.
        When `A` is sparse, a similar polyalgorithm is used. For indefinite matrices, the `LDLt`
        factorization does not use pivoting during the numerical factorization and therefore the
        procedure can fail even for invertible matrices.

## Keyword Arguments

* fact_alg: the factorization algorithm to use. Defaults to `LinearAlgebra.factorize`, but can be
  swapped to choices like `lu`, `qr`
"""
struct GenericFactorization{F} <: AbstractFactorization
    fact_alg::F
end

GenericFactorization(; fact_alg = LinearAlgebra.factorize) = GenericFactorization(fact_alg)

function do_factorization(alg::GenericFactorization, A, b, u)
    A = convert(AbstractMatrix, A)
    fact = alg.fact_alg(A)
    return fact
end

function init_cacheval(alg::GenericFactorization{typeof(lu)}, A, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterface.lu_instance(convert(AbstractMatrix, A))
end
function init_cacheval(alg::GenericFactorization{typeof(lu!)}, A, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterface.lu_instance(convert(AbstractMatrix, A))
end

function init_cacheval(alg::GenericFactorization{typeof(lu)},
    A::StridedMatrix{<:LinearAlgebra.BlasFloat}, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterface.lu_instance(A)
end
function init_cacheval(alg::GenericFactorization{typeof(lu!)},
    A::StridedMatrix{<:LinearAlgebra.BlasFloat}, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterface.lu_instance(A)
end
function init_cacheval(alg::GenericFactorization{typeof(lu)}, A::Diagonal, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    Diagonal(inv.(A.diag))
end
function init_cacheval(alg::GenericFactorization{typeof(lu)}, A::Tridiagonal, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.lu_instance(A)
end
function init_cacheval(alg::GenericFactorization{typeof(lu!)}, A::Diagonal, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    Diagonal(inv.(A.diag))
end
function init_cacheval(alg::GenericFactorization{typeof(lu!)}, A::Tridiagonal, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.lu_instance(A)
end

function init_cacheval(alg::GenericFactorization{typeof(qr)}, A, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterface.qr_instance(convert(AbstractMatrix, A))
end
function init_cacheval(alg::GenericFactorization{typeof(qr!)}, A, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterface.qr_instance(convert(AbstractMatrix, A))
end

function init_cacheval(alg::GenericFactorization{typeof(qr)},
    A::StridedMatrix{<:LinearAlgebra.BlasFloat}, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterface.qr_instance(A)
end
function init_cacheval(alg::GenericFactorization{typeof(qr!)},
    A::StridedMatrix{<:LinearAlgebra.BlasFloat}, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterface.qr_instance(A)
end
function init_cacheval(alg::GenericFactorization{typeof(qr)}, A::Diagonal, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    Diagonal(inv.(A.diag))
end
function init_cacheval(alg::GenericFactorization{typeof(qr)}, A::Tridiagonal, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.qr_instance(A)
end
function init_cacheval(alg::GenericFactorization{typeof(qr!)}, A::Diagonal, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    Diagonal(inv.(A.diag))
end
function init_cacheval(alg::GenericFactorization{typeof(qr!)}, A::Tridiagonal, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.qr_instance(A)
end

function init_cacheval(alg::GenericFactorization{typeof(svd)}, A, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterface.svd_instance(convert(AbstractMatrix, A))
end
function init_cacheval(alg::GenericFactorization{typeof(svd!)}, A, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterface.svd_instance(convert(AbstractMatrix, A))
end

function init_cacheval(alg::GenericFactorization{typeof(svd)},
    A::StridedMatrix{<:LinearAlgebra.BlasFloat}, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterface.svd_instance(A)
end
function init_cacheval(alg::GenericFactorization{typeof(svd!)},
    A::StridedMatrix{<:LinearAlgebra.BlasFloat}, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterface.svd_instance(A)
end
function init_cacheval(alg::GenericFactorization{typeof(svd)}, A::Diagonal, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    Diagonal(inv.(A.diag))
end
function init_cacheval(alg::GenericFactorization{typeof(svd)}, A::Tridiagonal, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.svd_instance(A)
end
function init_cacheval(alg::GenericFactorization{typeof(svd!)}, A::Diagonal, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    Diagonal(inv.(A.diag))
end
function init_cacheval(alg::GenericFactorization{typeof(svd!)}, A::Tridiagonal, b, u, Pl,
    Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.svd_instance(A)
end

function init_cacheval(alg::GenericFactorization, A::Diagonal, b, u, Pl, Pr, maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    Diagonal(inv.(A.diag))
end
function init_cacheval(alg::GenericFactorization, A::Tridiagonal, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterface.lu_instance(A)
end
function init_cacheval(alg::GenericFactorization, A::SymTridiagonal{T, V}, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions) where {T, V}
    LinearAlgebra.LDLt{T, SymTridiagonal{T, V}}(A)
end

function init_cacheval(alg::Union{GenericFactorization{typeof(bunchkaufman!)},
        GenericFactorization{typeof(bunchkaufman)}},
    A::Union{Hermitian, Symmetric}, b, u, Pl, Pr, maxiters::Int, abstol,
    reltol, verbose::Bool, assumptions::OperatorAssumptions)
    BunchKaufman(A.data, Array(1:size(A, 1)), A.uplo, true, false, 0)
end

function init_cacheval(alg::Union{GenericFactorization{typeof(bunchkaufman!)},
        GenericFactorization{typeof(bunchkaufman)}},
    A::StridedMatrix{<:LinearAlgebra.BlasFloat}, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    if eltype(A) <: Complex
        return bunchkaufman!(Hermitian(A))
    else
        return bunchkaufman!(Symmetric(A))
    end
end

# Fallback, tries to make nonsingular and just factorizes
# Try to never use it.

# Cholesky needs the posdef matrix, for GenericFactorization assume structure is needed
function init_cacheval(alg::Union{GenericFactorization{typeof(cholesky)},
        GenericFactorization{typeof(cholesky!)}}, A, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    newA = copy(convert(AbstractMatrix, A))
    do_factorization(alg, newA, b, u)
end

function init_cacheval(alg::Union{GenericFactorization},
    A::Union{Hermitian{T, <:SparseMatrixCSC},
        Symmetric{T, <:SparseMatrixCSC}}, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions) where {T}
    newA = copy(convert(AbstractMatrix, A))
    do_factorization(alg, newA, b, u)
end

# Ambiguity handling dispatch

################################## Factorizations which require solve! overloads

"""
`UMFPACKFactorization(;reuse_symbolic=true, check_pattern=true)`

A fast sparse multithreaded LU-factorization which specializes on sparsity 
patterns with “more structure”.

!!! note

    By default, the SuiteSparse.jl are implemented for efficiency by caching the
    symbolic factorization. I.e., if `set_A` is used, it is expected that the new
    `A` has the same sparsity pattern as the previous `A`. If this algorithm is to
    be used in a context where that assumption does not hold, set `reuse_symbolic=false`.
"""
Base.@kwdef struct UMFPACKFactorization <: AbstractFactorization
    reuse_symbolic::Bool = true
    check_pattern::Bool = true # Check factorization re-use
end

@static if VERSION < v"1.9.0-DEV.1622"
    const PREALLOCATED_UMFPACK = SuiteSparse.UMFPACK.UmfpackLU(C_NULL, C_NULL, 0, 0,
        [0], Int[], Float64[], 0)
    finalizer(SuiteSparse.UMFPACK.umfpack_free_symbolic, PREALLOCATED_UMFPACK)
else
    const PREALLOCATED_UMFPACK = SuiteSparse.UMFPACK.UmfpackLU(SparseMatrixCSC(0, 0, [1],
        Int[],
        Float64[]))
end

function init_cacheval(alg::UMFPACKFactorization,
    A, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol,
    verbose::Bool, assumptions::OperatorAssumptions)
    nothing
end

function init_cacheval(alg::UMFPACKFactorization, A::SparseMatrixCSC{Float64, Int}, b, u,
    Pl, Pr,
    maxiters::Int, abstol, reltol,
    verbose::Bool, assumptions::OperatorAssumptions)
    PREALLOCATED_UMFPACK
end

function init_cacheval(alg::UMFPACKFactorization, A::AbstractSparseArray, b, u, Pl, Pr,
    maxiters::Int, abstol,
    reltol,
    verbose::Bool, assumptions::OperatorAssumptions)
    A = convert(AbstractMatrix, A)
    zerobased = SparseArrays.getcolptr(A)[1] == 0
    @static if VERSION < v"1.9.0-DEV.1622"
        res = SuiteSparse.UMFPACK.UmfpackLU(C_NULL, C_NULL, size(A, 1), size(A, 2),
            zerobased ?
            copy(SparseArrays.getcolptr(A)) :
            SuiteSparse.decrement(SparseArrays.getcolptr(A)),
            zerobased ? copy(rowvals(A)) :
            SuiteSparse.decrement(rowvals(A)),
            copy(nonzeros(A)), 0)
        finalizer(SuiteSparse.UMFPACK.umfpack_free_symbolic, res)
        return res
    else
        return SuiteSparse.UMFPACK.UmfpackLU(SparseMatrixCSC(size(A)..., getcolptr(A),
            rowvals(A), nonzeros(A)))
    end
end

function SciMLBase.solve!(cache::LinearCache, alg::UMFPACKFactorization; kwargs...)
    A = cache.A
    A = convert(AbstractMatrix, A)
    if cache.isfresh
        cacheval = @get_cacheval(cache, :UMFPACKFactorization)
        if alg.reuse_symbolic
            # Caches the symbolic factorization: https://github.com/JuliaLang/julia/pull/33738
            if alg.check_pattern && !(SuiteSparse.decrement(SparseArrays.getcolptr(A)) ==
                 cacheval.colptr &&
                 SuiteSparse.decrement(SparseArrays.getrowval(A)) ==
                 cacheval.rowval)
                fact = lu(SparseMatrixCSC(size(A)..., getcolptr(A), rowvals(A),
                    nonzeros(A)))
            else
                fact = lu!(cacheval,
                    SparseMatrixCSC(size(A)..., getcolptr(A), rowvals(A),
                        nonzeros(A)))
            end
        else
            fact = lu(SparseMatrixCSC(size(A)..., getcolptr(A), rowvals(A), nonzeros(A)))
        end
        cache.cacheval = fact
        cache.isfresh = false
    end

    y = ldiv!(cache.u, @get_cacheval(cache, :UMFPACKFactorization), cache.b)
    SciMLBase.build_linear_solution(alg, y, nothing, cache)
end

"""
`KLUFactorization(;reuse_symbolic=true, check_pattern=true)`

A fast sparse LU-factorization which specializes on sparsity patterns with “less structure”.

!!! note

    By default, the SuiteSparse.jl are implemented for efficiency by caching the
    symbolic factorization. I.e., if `set_A` is used, it is expected that the new
    `A` has the same sparsity pattern as the previous `A`. If this algorithm is to
    be used in a context where that assumption does not hold, set `reuse_symbolic=false`.
"""
Base.@kwdef struct KLUFactorization <: AbstractFactorization
    reuse_symbolic::Bool = true
    check_pattern::Bool = true
end

const PREALLOCATED_KLU = KLU.KLUFactorization(SparseMatrixCSC(0, 0, [1], Int[],
    Float64[]))

function init_cacheval(alg::KLUFactorization,
    A, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol,
    verbose::Bool, assumptions::OperatorAssumptions)
    nothing
end

function init_cacheval(alg::KLUFactorization, A::SparseMatrixCSC{Float64, Int}, b, u, Pl,
    Pr,
    maxiters::Int, abstol, reltol,
    verbose::Bool, assumptions::OperatorAssumptions)
    PREALLOCATED_KLU
end

function init_cacheval(alg::KLUFactorization, A::AbstractSparseArray, b, u, Pl, Pr,
    maxiters::Int, abstol,
    reltol,
    verbose::Bool, assumptions::OperatorAssumptions)
    A = convert(AbstractMatrix, A)
    return KLU.KLUFactorization(SparseMatrixCSC(size(A)..., getcolptr(A), rowvals(A),
        nonzeros(A)))
end

function SciMLBase.solve!(cache::LinearCache, alg::KLUFactorization; kwargs...)
    A = cache.A
    A = convert(AbstractMatrix, A)

    if cache.isfresh
        cacheval = @get_cacheval(cache, :KLUFactorization)
        if cacheval !== nothing && alg.reuse_symbolic
            if alg.check_pattern && !(SuiteSparse.decrement(SparseArrays.getcolptr(A)) ==
                 cacheval.colptr &&
                 SuiteSparse.decrement(SparseArrays.getrowval(A)) == cacheval.rowval)
                fact = KLU.klu(SparseMatrixCSC(size(A)..., getcolptr(A), rowvals(A),
                    nonzeros(A)))
            else
                # If we have a cacheval already, run umfpack_symbolic to ensure the symbolic factorization exists
                # This won't recompute if it does.
                KLU.klu_analyze!(cacheval)
                copyto!(cacheval.nzval, nonzeros(A))
                if cacheval._numeric === C_NULL # We MUST have a numeric factorization for reuse, unlike UMFPACK.
                    KLU.klu_factor!(cacheval)
                end
                fact = KLU.klu!(cacheval,
                    SparseMatrixCSC(size(A)..., getcolptr(A), rowvals(A),
                        nonzeros(A)))
            end
        else
            # New fact each time since the sparsity pattern can change
            # and thus it needs to reallocate
            fact = KLU.klu(SparseMatrixCSC(size(A)..., getcolptr(A), rowvals(A),
                nonzeros(A)))
        end
        cache.cacheval = fact
        cache.isfresh = false
    end

    y = ldiv!(cache.u, @get_cacheval(cache, :KLUFactorization), cache.b)
    SciMLBase.build_linear_solution(alg, y, nothing, cache)
end

## CHOLMODFactorization

"""
`CHOLMODFactorization(; shift = 0.0, perm = nothing)`

A wrapper of CHOLMOD's polyalgorithm, mixing Cholesky factorization and ldlt.
Tries cholesky for performance and retries ldlt if conditioning causes Cholesky
to fail.

Only supports sparse matrices.

## Keyword Arguments

* shift: the shift argument in CHOLMOD. 
* perm: the perm argument in CHOLMOD
"""
Base.@kwdef struct CHOLMODFactorization{T} <: AbstractFactorization
    shift::Float64 = 0.0
    perm::T = nothing
end

const PREALLOCATED_CHOLMOD = cholesky(SparseMatrixCSC(0, 0, [1], Int[], Float64[]))

function init_cacheval(alg::CHOLMODFactorization,
    A, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol,
    verbose::Bool, assumptions::OperatorAssumptions)
    nothing
end

function init_cacheval(alg::CHOLMODFactorization,
    A::Union{SparseMatrixCSC{T, Int}, Symmetric{T, SparseMatrixCSC{T, Int}}}, b, u,
    Pl, Pr,
    maxiters::Int, abstol, reltol,
    verbose::Bool, assumptions::OperatorAssumptions) where {T <: Union{Float32, Float64}}
    PREALLOCATED_CHOLMOD
end

@static if VERSION > v"1.8-"
    function SciMLBase.solve!(cache::LinearCache, alg::CHOLMODFactorization; kwargs...)
        A = cache.A
        A = convert(AbstractMatrix, A)

        if cache.isfresh
            cacheval = @get_cacheval(cache, :CHOLMODFactorization)
            fact = cholesky(A; check = false)
            if !LinearAlgebra.issuccess(fact)
                ldlt!(fact, A; check = false)
            end
            cache.cacheval = fact
            cache.isfresh = false
        end

        cache.u .= @get_cacheval(cache, :CHOLMODFactorization) \ cache.b
        SciMLBase.build_linear_solution(alg, cache.u, nothing, cache)
    end
else
    function SciMLBase.solve!(cache::LinearCache, alg::CHOLMODFactorization; kwargs...)
        A = cache.A
        A = convert(AbstractMatrix, A)

        if cache.isfresh
            cacheval = @get_cacheval(cache, :CHOLMODFactorization)
            fact = cholesky(A)
            if !LinearAlgebra.issuccess(fact)
                ldlt!(fact, A)
            end
            cache.cacheval = fact
            cache.isfresh = false
        end

        cache.u .= @get_cacheval(cache, :CHOLMODFactorization) \ cache.b
        SciMLBase.build_linear_solution(alg, cache.u, nothing, cache)
    end
end

## RFLUFactorization

"""
`RFLUFactorization()` 

A fast pure Julia LU-factorization implementation
using RecursiveFactorization.jl. This is by far the fastest LU-factorization
implementation, usually outperforming OpenBLAS and MKL for smaller matrices
(<500x500), but currently optimized only for Base `Array` with `Float32` or `Float64`.  
Additional optimization for complex matrices is in the works.
"""
struct RFLUFactorization{P, T} <: AbstractFactorization
    RFLUFactorization(::Val{P}, ::Val{T}) where {P, T} = new{P, T}()
end

function RFLUFactorization(; pivot = Val(true), thread = Val(true))
    RFLUFactorization(pivot, thread)
end

function init_cacheval(alg::RFLUFactorization, A, b, u, Pl, Pr, maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ipiv = Vector{LinearAlgebra.BlasInt}(undef, min(size(A)...))
    ArrayInterface.lu_instance(convert(AbstractMatrix, A)), ipiv
end

function init_cacheval(alg::RFLUFactorization, A::Matrix{Float64}, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ipiv = Vector{LinearAlgebra.BlasInt}(undef, 0)
    PREALLOCATED_LU, ipiv
end

function init_cacheval(alg::RFLUFactorization,
    A::Union{AbstractSparseArray, AbstractSciMLOperator}, b, u, Pl, Pr,
    maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    nothing, nothing
end

@static if VERSION < v"1.9-"
    function init_cacheval(alg::RFLUFactorization,
        A::Union{Diagonal, SymTridiagonal, Tridiagonal}, b, u, Pl, Pr,
        maxiters::Int,
        abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
        nothing, nothing
    end
end

function SciMLBase.solve!(cache::LinearCache, alg::RFLUFactorization{P, T};
    kwargs...) where {P, T}
    A = cache.A
    A = convert(AbstractMatrix, A)
    fact, ipiv = @get_cacheval(cache, :RFLUFactorization)
    if cache.isfresh
        if length(ipiv) != min(size(A)...)
            ipiv = Vector{LinearAlgebra.BlasInt}(undef, min(size(A)...))
        end
        fact = RecursiveFactorization.lu!(A, ipiv, Val(P), Val(T))
        cache.cacheval = (fact, ipiv)
        cache.isfresh = false
    end
    y = ldiv!(cache.u, @get_cacheval(cache, :RFLUFactorization)[1], cache.b)
    SciMLBase.build_linear_solution(alg, y, nothing, cache)
end

## NormalCholeskyFactorization

"""
`NormalCholeskyFactorization(pivot = RowMaximum())`

A fast factorization which uses a Cholesky factorization on A * A'. Can be much
faster than LU factorization, but is not as numerically stable and thus should only
be applied to well-conditioned matrices.

## Positional Arguments

* pivot: Defaults to RowMaximum(), but can be NoPivot()
"""
struct NormalCholeskyFactorization{P} <: AbstractFactorization
    pivot::P
end

function NormalCholeskyFactorization(; pivot = nothing)
    if pivot === nothing
        pivot = @static if VERSION < v"1.8beta"
            Val(false)
        else
            NoPivot()
        end
    end
    NormalCholeskyFactorization(pivot)
end

default_alias_A(::NormalCholeskyFactorization, ::Any, ::Any) = true
default_alias_b(::NormalCholeskyFactorization, ::Any, ::Any) = true

@static if VERSION < v"1.8beta"
    normcholpivot = Val(false)
else
    normcholpivot = NoPivot()
end

const PREALLOCATED_NORMALCHOLESKY = ArrayInterface.cholesky_instance(rand(1, 1),
    normcholpivot)

function init_cacheval(alg::NormalCholeskyFactorization,
    A::Union{AbstractSparseArray,
        Symmetric{<:Number, <:AbstractSparseArray}}, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.cholesky_instance(convert(AbstractMatrix, A))
end

function init_cacheval(alg::NormalCholeskyFactorization, A, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.cholesky_instance(convert(AbstractMatrix, A), alg.pivot)
end

function init_cacheval(alg::NormalCholeskyFactorization,
    A::Union{Diagonal, AbstractSciMLOperator}, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    nothing
end

@static if VERSION < v"1.9-"
    function init_cacheval(alg::NormalCholeskyFactorization,
        A::Union{Tridiagonal, SymTridiagonal, Adjoint}, b, u, Pl, Pr,
        maxiters::Int, abstol, reltol, verbose::Bool,
        assumptions::OperatorAssumptions)
        nothing
    end
end

@static if VERSION > v"1.8-"
    function SciMLBase.solve!(cache::LinearCache, alg::NormalCholeskyFactorization;
        kwargs...)
        A = cache.A
        A = convert(AbstractMatrix, A)
        if cache.isfresh
            if A isa SparseMatrixCSC
                fact = cholesky(Symmetric((A)' * A, :L); check = false)
            else
                fact = cholesky(Symmetric((A)' * A, :L), alg.pivot; check = false)
            end
            cache.cacheval = fact
            cache.isfresh = false
        end
        if A isa SparseMatrixCSC
            cache.u .= @get_cacheval(cache, :NormalCholeskyFactorization) \ (A' * cache.b)
            y = cache.u
        else
            y = ldiv!(cache.u,
                @get_cacheval(cache, :NormalCholeskyFactorization),
                A' * cache.b)
        end
        SciMLBase.build_linear_solution(alg, y, nothing, cache)
    end
else
    function SciMLBase.solve!(cache::LinearCache, alg::NormalCholeskyFactorization;
        kwargs...)
        A = cache.A
        A = convert(AbstractMatrix, A)
        if cache.isfresh
            if A isa SparseMatrixCSC
                fact = cholesky(Symmetric((A)' * A, :L))
            else
                fact = cholesky(Symmetric((A)' * A, :L), alg.pivot)
            end
            cache.cacheval = fact
            cache.isfresh = false
        end
        if A isa SparseMatrixCSC
            cache.u .= @get_cacheval(cache, :NormalCholeskyFactorization) \ (A' * cache.b)
            y = cache.u
        else
            y = ldiv!(cache.u,
                @get_cacheval(cache, :NormalCholeskyFactorization),
                A' * cache.b)
        end
        SciMLBase.build_linear_solution(alg, y, nothing, cache)
    end
end

## NormalBunchKaufmanFactorization

"""
`NormalBunchKaufmanFactorization(rook = false)`

A fast factorization which uses a BunchKaufman factorization on A * A'. Can be much
faster than LU factorization, but is not as numerically stable and thus should only
be applied to well-conditioned matrices.

## Positional Arguments

* rook: whether to perform rook pivoting. Defaults to false.
"""
struct NormalBunchKaufmanFactorization <: AbstractFactorization
    rook::Bool
end

function NormalBunchKaufmanFactorization(; rook = false)
    NormalBunchKaufmanFactorization(rook)
end

default_alias_A(::NormalBunchKaufmanFactorization, ::Any, ::Any) = true
default_alias_b(::NormalBunchKaufmanFactorization, ::Any, ::Any) = true

function init_cacheval(alg::NormalBunchKaufmanFactorization, A, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.bunchkaufman_instance(convert(AbstractMatrix, A))
end

function SciMLBase.solve!(cache::LinearCache, alg::NormalBunchKaufmanFactorization;
    kwargs...)
    A = cache.A
    A = convert(AbstractMatrix, A)
    if cache.isfresh
        fact = bunchkaufman(Symmetric((A)' * A), alg.rook)
        cache.cacheval = fact
        cache.isfresh = false
    end
    y = ldiv!(cache.u, @get_cacheval(cache, :NormalBunchKaufmanFactorization), A' * cache.b)
    SciMLBase.build_linear_solution(alg, y, nothing, cache)
end

## DiagonalFactorization

"""
`DiagonalFactorization()`

A special implementation only for solving `Diagonal` matrices fast.
"""
struct DiagonalFactorization <: AbstractFactorization end

function init_cacheval(alg::DiagonalFactorization, A, b, u, Pl, Pr, maxiters::Int,
    abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    nothing
end

function SciMLBase.solve!(cache::LinearCache, alg::DiagonalFactorization;
    kwargs...)
    A = convert(AbstractMatrix, cache.A)
    if cache.u isa Vector && cache.b isa Vector
        @simd ivdep for i in eachindex(cache.u)
            cache.u[i] = A.diag[i] \ cache.b[i]
        end
    else
        cache.u .= A.diag .\ cache.b
    end
    SciMLBase.build_linear_solution(alg, cache.u, nothing, cache)
end

## FastLAPACKFactorizations

struct WorkspaceAndFactors{W, F}
    workspace::W
    factors::F
end

# There's no options like pivot here.
# But I'm not sure it makes sense as a GenericFactorization
# since it just uses `LAPACK.getrf!`.
"""
`FastLUFactorization()` 

The FastLapackInterface.jl version of the LU factorization. Notably,
this version does not allow for choice of pivoting method.
"""
struct FastLUFactorization <: AbstractFactorization end

function init_cacheval(::FastLUFactorization, A, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ws = LUWs(A)
    return WorkspaceAndFactors(ws, ArrayInterface.lu_instance(convert(AbstractMatrix, A)))
end

function SciMLBase.solve!(cache::LinearCache, alg::FastLUFactorization; kwargs...)
    A = cache.A
    A = convert(AbstractMatrix, A)
    ws_and_fact = @get_cacheval(cache, :FastLUFactorization)
    if cache.isfresh
        # we will fail here if A is a different *size* than in a previous version of the same cache.
        # it may instead be desirable to resize the workspace.
        @set! ws_and_fact.factors = LinearAlgebra.LU(LAPACK.getrf!(ws_and_fact.workspace,
            A)...)
        cache.cacheval = ws_and_fact
        cache.isfresh = false
    end
    y = ldiv!(cache.u, cache.cacheval.factors, cache.b)
    SciMLBase.build_linear_solution(alg, y, nothing, cache)
end

"""
`FastQRFactorization()` 

The FastLapackInterface.jl version of the QR factorization.
"""
struct FastQRFactorization{P} <: AbstractFactorization
    pivot::P
    blocksize::Int
end

function FastQRFactorization()
    if VERSION < v"1.7beta"
        FastQRFactorization(Val(false), 36)
    else
        FastQRFactorization(NoPivot(), 36)
    end
    # is 36 or 16 better here? LinearAlgebra and FastLapackInterface use 36,
    # but QRFactorization uses 16.
end

@static if VERSION < v"1.7beta"
    function init_cacheval(alg::FastQRFactorization{Val{false}}, A, b, u, Pl, Pr,
        maxiters::Int, abstol, reltol, verbose::Bool,
        assumptions::OperatorAssumptions)
        ws = QRWYWs(A; blocksize = alg.blocksize)
        return WorkspaceAndFactors(ws,
            ArrayInterface.qr_instance(convert(AbstractMatrix, A)))
    end

    function init_cacheval(::FastQRFactorization{Val{true}}, A, b, u, Pl, Pr,
        maxiters::Int, abstol, reltol, verbose::Bool,
        assumptions::OperatorAssumptions)
        ws = QRpWs(A)
        return WorkspaceAndFactors(ws,
            ArrayInterface.qr_instance(convert(AbstractMatrix, A)))
    end
else
    function init_cacheval(alg::FastQRFactorization{NoPivot}, A, b, u, Pl, Pr,
        maxiters::Int, abstol, reltol, verbose::Bool,
        assumptions::OperatorAssumptions)
        ws = QRWYWs(A; blocksize = alg.blocksize)
        return WorkspaceAndFactors(ws,
            ArrayInterface.qr_instance(convert(AbstractMatrix, A)))
    end
    function init_cacheval(::FastQRFactorization{ColumnNorm}, A, b, u, Pl, Pr,
        maxiters::Int, abstol, reltol, verbose::Bool,
        assumptions::OperatorAssumptions)
        ws = QRpWs(A)
        return WorkspaceAndFactors(ws,
            ArrayInterface.qr_instance(convert(AbstractMatrix, A)))
    end
end

function SciMLBase.solve!(cache::LinearCache, alg::FastQRFactorization{P};
    kwargs...) where {P}
    A = cache.A
    A = convert(AbstractMatrix, A)
    ws_and_fact = @get_cacheval(cache, :FastQRFactorization)
    if cache.isfresh
        # we will fail here if A is a different *size* than in a previous version of the same cache.
        # it may instead be desirable to resize the workspace.
        nopivot = @static if VERSION < v"1.7beta"
            Val{false}
        else
            NoPivot
        end
        if P === nopivot
            @set! ws_and_fact.factors = LinearAlgebra.QRCompactWY(LAPACK.geqrt!(ws_and_fact.workspace,
                A)...)
        else
            @set! ws_and_fact.factors = LinearAlgebra.QRPivoted(LAPACK.geqp3!(ws_and_fact.workspace,
                A)...)
        end
        cache.cacheval = ws_and_fact
        cache.isfresh = false
    end
    y = ldiv!(cache.u, cache.cacheval.factors, cache.b)
    SciMLBase.build_linear_solution(alg, y, nothing, cache)
end

## SparspakFactorization is here since it's MIT licensed, not GPL

"""
`SparspakFactorization(reuse_symbolic = true)`

This is the translation of the well-known sparse matrix software Sparspak
(Waterloo Sparse Matrix Package), solving
large sparse systems of linear algebraic equations. Sparspak is composed of the
subroutines from the book "Computer Solution of Large Sparse Positive Definite
Systems" by Alan George and Joseph Liu. Originally written in Fortran 77, later
rewritten in Fortran 90. Here is the software translated into Julia.

The Julia rewrite is released  under the MIT license with an express permission
from the authors of the Fortran package. The package uses multiple
dispatch to route around standard BLAS routines in the case e.g. of arbitrary-precision
floating point numbers or ForwardDiff.Dual.
This e.g. allows for Automatic Differentiation (AD) of a sparse-matrix solve.
"""
Base.@kwdef struct SparspakFactorization <: AbstractFactorization
    reuse_symbolic::Bool = true
end

const PREALLOCATED_SPARSEPAK = sparspaklu(SparseMatrixCSC(0, 0, [1], Int[], Float64[]),
    factorize = false)

function init_cacheval(alg::SparspakFactorization,
    A::Union{Matrix, Nothing, AbstractSciMLOperator}, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol,
    verbose::Bool, assumptions::OperatorAssumptions)
    nothing
end

function init_cacheval(::SparspakFactorization, A::SparseMatrixCSC{Float64, Int}, b, u, Pl,
    Pr, maxiters::Int, abstol,
    reltol,
    verbose::Bool, assumptions::OperatorAssumptions)
    PREALLOCATED_SPARSEPAK
end

function init_cacheval(::SparspakFactorization, A, b, u, Pl, Pr, maxiters::Int, abstol,
    reltol,
    verbose::Bool, assumptions::OperatorAssumptions)
    A = convert(AbstractMatrix, A)
    if typeof(A) <: SparseArrays.AbstractSparseArray
        return sparspaklu(SparseMatrixCSC(size(A)..., getcolptr(A), rowvals(A),
                nonzeros(A)),
            factorize = false)
    else
        return sparspaklu(SparseMatrixCSC(0, 0, [1], Int[], eltype(A)[]),
            factorize = false)
    end
end

function SciMLBase.solve!(cache::LinearCache, alg::SparspakFactorization; kwargs...)
    A = cache.A
    if cache.isfresh
        if cache.cacheval !== nothing && alg.reuse_symbolic
            fact = sparspaklu!(@get_cacheval(cache, :SparspakFactorization),
                SparseMatrixCSC(size(A)..., getcolptr(A), rowvals(A),
                    nonzeros(A)))
        else
            fact = sparspaklu(SparseMatrixCSC(size(A)..., getcolptr(A), rowvals(A),
                nonzeros(A)))
        end
        cache.cacheval = fact
        cache.isfresh = false
    end
    y = ldiv!(cache.u, @get_cacheval(cache, :SparspakFactorization), cache.b)
    SciMLBase.build_linear_solution(alg, y, nothing, cache)
end

for alg in InteractiveUtils.subtypes(AbstractFactorization)
    @eval function init_cacheval(alg::$alg, A::MatrixOperator, b, u, Pl, Pr,
        maxiters::Int, abstol, reltol, verbose::Bool,
        assumptions::OperatorAssumptions)
        init_cacheval(alg, A.A, b, u, Pl, Pr,
            maxiters::Int, abstol, reltol, verbose::Bool,
            assumptions::OperatorAssumptions)
    end
end
