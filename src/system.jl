"""
    PanelProperties

Panel specific properties calculated during the vortex lattice method analysis.

**Fields**
 - `gamma`: Vortex ring circulation strength, normalized by VINF
 - `velocity`: Local velocity at the panel's bound vortex center, normalized by VINF
 - `cfb`: Net force on the panel's bound vortex, as calculated using the
    Kutta-Joukowski theorem, normalized by `QINF*S`
 - `cfl`: Force on the left bound vortex from this panel's vortex ring, as
    calculated by the Kutta-Joukowski theorem, normalized by `QINF*S`
 - `cfr`: Force on the right bound vortex from this panel's vortex ring, as
    calculated by the Kutta-Joukowski theorem, normalized by `QINF*S`
"""
struct PanelProperties{TF}
    gamma::TF
    velocity::SVector{3, TF}
    cfb::SVector{3, TF}
    cfl::SVector{3, TF}
    cfr::SVector{3, TF}
end

# constructor
function PanelProperties(gamma, velocity, cfb, cfl, cfr)

    TF = promote_type(typeof(gamma), typeof(velocity), eltype(cfb), eltype(cfl),
        eltype(cfr))

    return PanelProperties{TF}(gamma, velocity, cfb, cfl, cfr)
end

Base.eltype(::Type{PanelProperties{TF}}) where TF = TF
Base.eltype(::PanelProperties{TF}) where TF = TF

"""
    System{TF}

Contains pre-allocated storage for internal system variables.

# Fields:
 - `AIC`: Aerodynamic influence coefficient matrix from the surface panels
 - `w`: Normal velocity at the control points from external sources and wakes
 - `Γ`: Circulation strength of the surface panels
 - `V`: Velocity at the wake vertices for each surface
 - `panels`: Surface panel properties for each surface
 - `wakes`: Wake panel properties for each surface
 - `trefftz`: Trefftz panels associated with each surface
 - `dw`: Derivatives of the R.H.S. with respect to the freestream variables
 - `dΓ`: Derivatives of the circulation strength with respect to the freestream variables
 - `dpanels`: Derivatives of the panel properties with respect to the freestream variables
 - `wake_shedding_locations`: Wake shedding locations for each surface
 - `dΓdt`: Derivative of the circulation strength with respect to non-dimensional time
"""
struct System{TF}
    AIC::Matrix{TF}
    w::Vector{TF}
    Γ::Vector{TF}
    V::Vector{Matrix{SVector{3,TF}}}
    panels::Vector{Matrix{PanelProperties{TF}}}
    wakes::Vector{Matrix{WakePanel{TF}}}
    trefftz::Vector{Vector{TrefftzPanel{TF}}}
    dw::NTuple{5, Vector{TF}}
    dΓ::NTuple{5, Vector{TF}}
    dpanels::NTuple{5, Vector{Matrix{PanelProperties{TF}}}}
    wake_shedding_locations::Vector{Vector{SVector{3,TF}}}
    dΓdt::Vector{TF}
end

@inline Base.eltype(::Type{System{TF}}) where TF = TF
@inline Base.eltype(::System{TF}) where TF = TF

"""
    System([TF], surface; kwargs...)

Return an object of type `System` with pre-allocated storage for internal
system variables

# Arguments:
 - `TF`: Floating point type, defaults to the floating point type used by `surface`
 - `surface`: Matrix of surface panels (see [`SurfacePanel`](@ref)) of shape
    (nc, ns) where `nc` is the number of chordwise panels and `ns` is the number
    of spanwise panels

# Keyword Arguments:
 - `nwake`: Number of chordwise wake panels to initialize. Defaults to zero wake panels.
"""
function System() end

System(surface::AbstractMatrix; kwargs...) = System(eltype(eltype(surface)), surface; kwargs...)

function System(TF::Type{<:AbstractFloat}, surface::AbstractMatrix; nwake=0)

    N = length(surface)
    nc, ns = size(surface)
    nw = nwake

    AIC = zeros(TF, N, N)
    w = zeros(TF, N)
    Γ = zeros(TF, N)
    V = [Matrix{SVector{3, TF}}(undef, nw+1, ns+1)]
    panels = [Matrix{PanelProperties{TF}}(undef, nc, ns)]
    wakes = [Matrix{WakePanel{TF}}(undef, nw, ns)]
    trefftz = [Vector{TrefftzPanel{TF}}(undef, ns)]
    dw = Tuple(zeros(TF, N) for id = 1:5)
    dΓ = Tuple(zeros(TF, N) for id = 1:5)
    dpanels = Tuple([Matrix{PanelProperties{TF}}(undef, nc, ns)] for id = 1:5)
    wake_shedding_locations = [Vector{SVector{3,TF}}(undef, ns+1)]
    dΓdt = zeros(TF, N)

    return System{TF}(AIC, w, Γ, V, panels, wakes, trefftz, dw, dΓ, dpanels,
        wake_shedding_locations, dΓdt)
end

"""
    System([TF], surfaces; kwargs...)

Return an object of type `System` with pre-allocated storage for internal
system variables

# Arguments:
 - `TF`: Floating point type, defaults to the floating point type used by `surfaces`
 - `surfaces`: Vector of surfaces, represented by matrices of surface panels
    (see [`SurfacePanel`](@ref) of shape (nc, ns) where `nc` is the number of
    chordwise panels and `ns` is the number of spanwise panels

# Keyword Arguments:
 - `nwake`: Number of chordwise wake panels to initialize for each surface. Defaults
    to zero wake panels for each surface.
"""
System(surfaces::AbstractVector{<:AbstractMatrix}; kwargs...) =
    System(eltype(eltype(eltype(surfaces))), surfaces; kwargs...)

function System(TF::Type{<:AbstractFloat}, surfaces::AbstractVector{<:AbstractMatrix};
    nwake = 0)

    # number of surfaces
    nsurf = length(surfaces)

    # number of surface panels
    N = sum(length.(surfaces))

    # number of chordwise panels in each surface
    nc = size.(surfaces, 1)

    # number of spanwise panels in each surface
    ns = size.(surfaces, 2)

    # number of wake panels for each surface
    if typeof(nwake) <: Number
        # use the same number of wake panels for each surface
        nw = fill(nwake, nsurf)
    else
        # use specified number of wake panels for each surface
        nw = nwake
    end

    AIC = zeros(TF, N, N)
    w = zeros(TF, N)
    Γ = zeros(TF, N)
    V = [Matrix{SVector{3, TF}}(undef, nw[i]+1, ns[i]+1) for i = 1:nsurf]
    panels = [Matrix{PanelProperties{TF}}(undef, nc[i], ns[i]) for i = 1:nsurf]
    wakes = [Matrix{WakePanel{TF}}(undef, nw[i], ns[i]) for i = 1:nsurf]
    trefftz = [Vector{TrefftzPanel{TF}}(undef, ns[i]) for i = 1:nsurf]
    dw = Tuple(zeros(TF, N) for i = 1:5)
    dΓ = Tuple(zeros(TF, N) for i = 1:5)
    dpanels = Tuple([Matrix{PanelProperties{TF}}(undef, nc[i], ns[i]) for i = 1:length(surfaces)] for j = 1:5)
    wake_shedding_locations = [Vector{SVector{3, TF}}(undef, ns[i]+1) for i = 1:nsurf]
    dΓdt = zeros(TF, N)

    return System{TF}(AIC, w, Γ, V, panels, wakes, trefftz, dw, dΓ, dpanels,
        wake_shedding_locations, dΓdt)
end

"""
    get_panel_properties(system, surface)

Return the panel properties stored in `system`
"""
get_panel_properties(system, surface::AbstractMatrix) = system.panels[1]

"""
    get_panel_properties(system, surfaces)

Return the panel properties stored in `system`
"""
get_panel_properties(system, surfaces::AbstractVector{<:AbstractMatrix}) = system.panels
