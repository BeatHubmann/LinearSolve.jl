module LinearSolveMKLExt

using MKL_jll
using LinearAlgebra: BlasInt, LU
using LinearAlgebra.LAPACK: require_one_based_indexing, chkfinite, chkstride1, 
                            @blasfunc, chkargsok
using LinearAlgebra
const usemkl = MKL_jll.is_available()

using LinearSolve
using LinearSolve: ArrayInterface, MKLLUFactorization, @get_cacheval, LinearCache, SciMLBase

function getrf!(A::AbstractMatrix{<:Float64}; ipiv = similar(A, BlasInt, min(size(A,1),size(A,2))), info = Ref{BlasInt}(), check = false)
    require_one_based_indexing(A)
    check && chkfinite(A)
    chkstride1(A)
    m, n = size(A)
    lda  = max(1,stride(A, 2))
    if isempty(ipiv)
        ipiv = similar(A, BlasInt, min(size(A,1),size(A,2)))
    end
    ccall((@blasfunc(dgetrf_), MKL_jll.libmkl_rt), Cvoid,
            (Ref{BlasInt}, Ref{BlasInt}, Ptr{Float64},
            Ref{BlasInt}, Ptr{BlasInt}, Ptr{BlasInt}),
            m, n, A, lda, ipiv, info)
    chkargsok(info[])
    A, ipiv, info[], info #Error code is stored in LU factorization type
end

function getrf!(A::AbstractMatrix{<:Float32}; ipiv = similar(A, BlasInt, min(size(A,1),size(A,2))), info = Ref{BlasInt}(), check = false)
    require_one_based_indexing(A)
    check && chkfinite(A)
    chkstride1(A)
    m, n = size(A)
    lda  = max(1,stride(A, 2))
    if isempty(ipiv)
        ipiv = similar(A, BlasInt, min(size(A,1),size(A,2)))
    end
    ccall((@blasfunc(sgetrf_), MKL_jll.libmkl_rt), Cvoid,
            (Ref{BlasInt}, Ref{BlasInt}, Ptr{Float32},
            Ref{BlasInt}, Ptr{BlasInt}, Ptr{BlasInt}),
            m, n, A, lda, ipiv, info)
    chkargsok(info[])
    A, ipiv, info[], info #Error code is stored in LU factorization type
end

function getrs!(trans::AbstractChar, A::AbstractMatrix{<:Float64}, ipiv::AbstractVector{BlasInt}, B::AbstractVecOrMat{<:Float64}; info = Ref{BlasInt}())
    require_one_based_indexing(A, ipiv, B)
    LinearAlgebra.LAPACK.chktrans(trans)
    chkstride1(A, B, ipiv)
    n = LinearAlgebra.checksquare(A)
    if n != size(B, 1)
        throw(DimensionMismatch("B has leading dimension $(size(B,1)), but needs $n"))
    end
    if n != length(ipiv)
        throw(DimensionMismatch("ipiv has length $(length(ipiv)), but needs to be $n"))
    end
    nrhs = size(B, 2)
    ccall(("dgetrs_", MKL_jll.libmkl_rt), Cvoid,
          (Ref{UInt8}, Ref{BlasInt}, Ref{BlasInt}, Ptr{Float64}, Ref{BlasInt},
           Ptr{BlasInt}, Ptr{Float64}, Ref{BlasInt}, Ptr{BlasInt}, Clong),
          trans, n, size(B,2), A, max(1,stride(A,2)), ipiv, B, max(1,stride(B,2)), info, 1)
    LinearAlgebra.LAPACK.chklapackerror(BlasInt(info[]))
    B
end

function getrs!(trans::AbstractChar, A::AbstractMatrix{<:Float32}, ipiv::AbstractVector{BlasInt}, B::AbstractVecOrMat{<:Float32}; info = Ref{BlasInt}())
    require_one_based_indexing(A, ipiv, B)
    LinearAlgebra.LAPACK.chktrans(trans)
    chkstride1(A, B, ipiv)
    n = LinearAlgebra.checksquare(A)
    if n != size(B, 1)
        throw(DimensionMismatch("B has leading dimension $(size(B,1)), but needs $n"))
    end
    if n != length(ipiv)
        throw(DimensionMismatch("ipiv has length $(length(ipiv)), but needs to be $n"))
    end
    nrhs = size(B, 2)
    ccall(("sgetrs_", MKL_jll.libmkl_rt), Cvoid,
          (Ref{UInt8}, Ref{BlasInt}, Ref{BlasInt}, Ptr{Float32}, Ref{BlasInt},
           Ptr{BlasInt}, Ptr{Float32}, Ref{BlasInt}, Ptr{BlasInt}, Clong),
          trans, n, size(B,2), A, max(1,stride(A,2)), ipiv, B, max(1,stride(B,2)), info, 1)
    LinearAlgebra.LAPACK.chklapackerror(BlasInt(info[]))
    B
end

default_alias_A(::MKLLUFactorization, ::Any, ::Any) = false
default_alias_b(::MKLLUFactorization, ::Any, ::Any) = false

function LinearSolve.init_cacheval(alg::MKLLUFactorization, A, b, u, Pl, Pr,
    maxiters::Int, abstol, reltol, verbose::Bool,
    assumptions::OperatorAssumptions)
    ArrayInterface.lu_instance(convert(AbstractMatrix, A)), Ref{BlasInt}()
end

function SciMLBase.solve!(cache::LinearCache, alg::MKLLUFactorization;
    kwargs...)
    A = cache.A
    A = convert(AbstractMatrix, A)
    if cache.isfresh
        cacheval = @get_cacheval(cache, :MKLLUFactorization)
        res = getrf!(A; ipiv = cacheval[1].ipiv, info = cacheval[2])
        fact = LU(res[1:3]...), res[4]
        cache.cacheval = fact
        cache.isfresh = false
    end

    y = ldiv!(cache.u, @get_cacheval(cache, :MKLLUFactorization)[1], cache.b)
    SciMLBase.build_linear_solution(alg, y, nothing, cache)

    #=
    A, info = @get_cacheval(cache, :MKLLUFactorization)
    LinearAlgebra.require_one_based_indexing(cache.u, cache.b)
    m, n = size(A, 1), size(A, 2)
    if m > n
        Bc = copy(cache.b)
        getrs!('N', A.factors, A.ipiv, Bc; info)
        return copyto!(cache.u, 1, Bc, 1, n)
    else
        copyto!(cache.u, cache.b)
        getrs!('N', A.factors, A.ipiv, cache.u; info)
    end

    SciMLBase.build_linear_solution(alg, cache.u, nothing, cache)
    =#
end

end