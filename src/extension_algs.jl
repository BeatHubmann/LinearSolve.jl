# This file only include the algorithm struct to be exported by LinearSolve.jl. The main
# functionality is implemented as package extensions

"""
`HYPREAlgorithm(solver; Pl = nothing)`

[HYPRE.jl](https://github.com/fredrikekre/HYPRE.jl) is an interface to
[`hypre`](https://computing.llnl.gov/projects/hypre-scalable-linear-solvers-multigrid-methods)
and provide iterative solvers and preconditioners for sparse linear systems. It is mainly
developed for large multi-process distributed problems (using MPI), but can also be used for
single-process problems with Julias standard sparse matrices.

If you need more fine-grained control over the solver/preconditioner options you can
alternatively pass an already created solver to `HYPREAlgorithm` (and to the `Pl` keyword
argument). See HYPRE.jl docs for how to set up solvers with specific options.

!!! note
    
    Using HYPRE solvers requires Julia version 1.9 or higher, and that the package HYPRE.jl
    is installed.

## Positional Arguments

The single positional argument `solver` has the following choices:

- `HYPRE.BiCGSTAB`
- `HYPRE.BoomerAMG`
- `HYPRE.FlexGMRES`
- `HYPRE.GMRES`
- `HYPRE.Hybrid`
- `HYPRE.ILU`
- `HYPRE.ParaSails` (as preconditioner only)
- `HYPRE.PCG`

## Keyword Arguments

* `Pl`: A choice of left preconditioner.

## Example 

For example, to use `HYPRE.PCG` as the solver, with `HYPRE.BoomerAMG` as the preconditioner,
the algorithm should be defined as follows:

```julia
A, b = setup_system(...)
prob = LinearProblem(A, b)
alg = HYPREAlgorithm(HYPRE.PCG)
prec = HYPRE.BoomerAMG
sol = solve(prob, alg; Pl = prec)
```
"""
struct HYPREAlgorithm <: SciMLLinearSolveAlgorithm
    solver::Any

    @static if VERSION >= v"1.9-"
        function HYPREAlgorithm(solver)
            ext = Base.get_extension(@__MODULE__, :LinearSolveHYPREExt)
            if ext === nothing
                error("HYPREAlgorithm requires that HYPRE is loaded, i.e. `using HYPRE`")
            else
                return new{}(solver)
            end
        end
    end
end

"""
`CudaOffloadFactorization()`

An offloading technique used to GPU-accelerate CPU-based computations. 
Requires a sufficiently large `A` to overcome the data transfer costs.

!!! note
    
    Using this solver requires adding the package CUDA.jl, i.e. `using CUDA`
"""
struct CudaOffloadFactorization <: LinearSolve.AbstractFactorization
    @static if VERSION >= v"1.9-"
        function CudaOffloadFactorization()
            ext = Base.get_extension(@__MODULE__, :LinearSolveCUDAExt)
            if ext === nothing
                error("CudaOffloadFactorization requires that CUDA is loaded, i.e. `using CUDA`")
            else
                return new{}()
            end
        end
    end
end

"""
```julia
MKLPardisoFactorize(; nprocs::Union{Int, Nothing} = nothing,
                    matrix_type = nothing,
                    iparm::Union{Vector{Tuple{Int, Int}}, Nothing} = nothing,
                    dparm::Union{Vector{Tuple{Int, Int}}, Nothing} = nothing)
```

A sparse factorization method using MKL Pardiso.

!!! note
    
    Using this solver requires adding the package Pardiso.jl, i.e. `using Pardiso`

## Keyword Arguments

For the definition of the keyword arguments, see the Pardiso.jl documentation.
All values default to `nothing` and the solver internally determines the values
given the input types, and these keyword arguments are only for overriding the
default handling process. This should not be required by most users.
"""
MKLPardisoFactorize(; kwargs...) = PardisoJL(; solver_type = 0, kwargs...)

"""
```julia
MKLPardisoIterate(; nprocs::Union{Int, Nothing} = nothing,
                    matrix_type = nothing,
                    iparm::Union{Vector{Tuple{Int, Int}}, Nothing} = nothing,
                    dparm::Union{Vector{Tuple{Int, Int}}, Nothing} = nothing)
```

A mixed factorization+iterative method using MKL Pardiso.

!!! note
    
    Using this solver requires adding the package Pardiso.jl, i.e. `using Pardiso`

## Keyword Arguments

For the definition of the keyword arguments, see the Pardiso.jl documentation.
All values default to `nothing` and the solver internally determines the values
given the input types, and these keyword arguments are only for overriding the
default handling process. This should not be required by most users.
"""
MKLPardisoIterate(; kwargs...) = PardisoJL(; solver_type = 1, kwargs...)

@static if VERSION >= v"1.9-"
    """
    ```julia
    PardisoJL(; nprocs::Union{Int, Nothing} = nothing,
                solver_type = nothing,
                matrix_type = nothing,
                iparm::Union{Vector{Tuple{Int, Int}}, Nothing} = nothing,
                dparm::Union{Vector{Tuple{Int, Int}}, Nothing} = nothing)
    ```

    A generic method using MKL Pardiso. Specifying `solver_type` is required.

    !!! note

        Using this solver requires adding the package Pardiso.jl, i.e. `using Pardiso`

    ## Keyword Arguments

    For the definition of the keyword arguments, see the Pardiso.jl documentation.
    All values default to `nothing` and the solver internally determines the values
    given the input types, and these keyword arguments are only for overriding the
    default handling process. This should not be required by most users.
    """
    struct PardisoJL{T1, T2} <: LinearSolve.SciMLLinearSolveAlgorithm
        nprocs::Union{Int, Nothing}
        solver_type::T1
        matrix_type::T2
        iparm::Union{Vector{Tuple{Int, Int}}, Nothing}
        dparm::Union{Vector{Tuple{Int, Int}}, Nothing}

        function PardisoJL(; nprocs::Union{Int, Nothing} = nothing,
            solver_type = nothing,
            matrix_type = nothing,
            iparm::Union{Vector{Tuple{Int, Int}}, Nothing} = nothing,
            dparm::Union{Vector{Tuple{Int, Int}}, Nothing} = nothing)
            ext = Base.get_extension(@__MODULE__, :LinearSolvePardisoExt)
            if ext === nothing
                error("PardisoJL requires that Pardiso is loaded, i.e. `using Pardiso`")
            else
                T1 = typeof(solver_type)
                T2 = typeof(matrix_type)
                @assert T1 <: Union{Int, Nothing, ext.Pardiso.Solver}
                @assert T2 <: Union{Int, Nothing, ext.Pardiso.MatrixType}
                return new{T1, T2}(nprocs, solver_type, matrix_type, iparm, dparm)
            end
        end
    end
else
    """
    ```julia
    PardisoJL(; nprocs::Union{Int, Nothing} = nothing,
                solver_type = nothing,
                matrix_type = nothing,
                iparm::Union{Vector{Tuple{Int, Int}}, Nothing} = nothing,
                dparm::Union{Vector{Tuple{Int, Int}}, Nothing} = nothing)
    ```

    A generic method using MKL Pardiso. Specifying `solver_type` is required.

    !!! note

        Using this solver requires adding the package Pardiso.jl, i.e. `using Pardiso`

    ## Keyword Arguments

    For the definition of the keyword arguments, see the Pardiso.jl documentation.
    All values default to `nothing` and the solver internally determines the values
    given the input types, and these keyword arguments are only for overriding the
    default handling process. This should not be required by most users.
    """
    Base.@kwdef struct PardisoJL <: LinearSolve.SciMLLinearSolveAlgorithm
        nprocs::Union{Int, Nothing} = nothing
        solver_type::Any = nothing
        matrix_type::Any = nothing
        iparm::Union{Vector{Tuple{Int, Int}}, Nothing} = nothing
        dparm::Union{Vector{Tuple{Int, Int}}, Nothing} = nothing
    end
end

"""
```julia
KrylovKitJL(args...; KrylovAlg = Krylov.gmres!, kwargs...)
```

A generic iterative solver implementation allowing the choice of KrylovKit.jl
solvers.

!!! note
    
    Using this solver requires adding the package KrylovKit.jl, i.e. `using KrylovKit`
"""
struct KrylovKitJL{F, A, I, K} <: LinearSolve.AbstractKrylovSubspaceMethod
    KrylovAlg::F
    gmres_restart::I
    args::A
    kwargs::K
end

"""
```julia
KrylovKitJL_CG(args...; Pl = nothing, Pr = nothing, kwargs...)
```

A generic CG implementation for Hermitian and positive definite linear systems

!!! note
    
    Using this solver requires adding the package KrylovKit.jl, i.e. `using KrylovKit`    
"""
function KrylovKitJL_CG end

"""
```julia
KrylovKitJL_GMRES(args...; Pl = nothing, Pr = nothing, gmres_restart = 0, kwargs...)
```

A generic GMRES implementation.

!!! note
    
    Using this solver requires adding the package KrylovKit.jl, i.e. `using KrylovKit`
"""
function KrylovKitJL_GMRES end

"""
```julia
IterativeSolversJL(args...;
                   generate_iterator = IterativeSolvers.gmres_iterable!,
                   Pl = nothing, Pr = nothing,
                   gmres_restart = 0, kwargs...)
```

A generic wrapper over the IterativeSolvers.jl solvers.


!!! note
    
    Using this solver requires adding the package IterativeSolvers.jl, i.e. `using IterativeSolvers`

"""
struct IterativeSolversJL{F, I, A, K} <: LinearSolve.AbstractKrylovSubspaceMethod
    generate_iterator::F
    gmres_restart::I
    args::A
    kwargs::K
end

"""
```julia
IterativeSolversJL_CG(args...; Pl = nothing, Pr = nothing, kwargs...)
```

A wrapper over the IterativeSolvers.jl CG.

!!! note
    
    Using this solver requires adding the package IterativeSolvers.jl, i.e. `using IterativeSolvers`

"""
function IterativeSolversJL_CG end

"""
```julia
IterativeSolversJL_GMRES(args...; Pl = nothing, Pr = nothing, gmres_restart=0, kwargs...)
```

A wrapper over the IterativeSolvers.jl GMRES.


!!! note
    
    Using this solver requires adding the package IterativeSolvers.jl, i.e. `using IterativeSolvers`

"""
function IterativeSolversJL_GMRES end

"""
```julia
IterativeSolversJL_BICGSTAB(args...; Pl = nothing, Pr = nothing, kwargs...)
```

A wrapper over the IterativeSolvers.jl BICGSTAB.


!!! note
    
    Using this solver requires adding the package IterativeSolvers.jl, i.e. `using IterativeSolvers`

"""
function IterativeSolversJL_BICGSTAB end

"""
```julia
IterativeSolversJL_MINRES(args...; Pl = nothing, Pr = nothing, kwargs...)
```

A wrapper over the IterativeSolvers.jl MINRES.


!!! note
    
    Using this solver requires adding the package IterativeSolvers.jl, i.e. `using IterativeSolvers`

"""
function IterativeSolversJL_MINRES end

"""
```julia
MKLLUFactorization()
```

A wrapper over Intel's Math Kernel Library (MKL). Direct calls to MKL in a way that pre-allocates workspace
to avoid allocations and does not require libblastrampoline.
"""
struct MKLLUFactorization <: AbstractFactorization end

"""
```julia
MetalLUFactorization()
```

A wrapper over Apple's Metal GPU library. Direct calls to Metal in a way that pre-allocates workspace
to avoid allocations and automatically offloads to the GPU.
"""
struct MetalLUFactorization <: AbstractFactorization end