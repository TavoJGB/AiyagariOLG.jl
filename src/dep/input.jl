#===========================================================================
    HELPER FUNCTIONS
===========================================================================#

function get_object(pars, substr; typesubstr::String="Prefix")
    subset = subset_namedtuple(pars, substr; typesubstr)
    tipo = eval(subset.tipo)    # eval, in case tipo is a symbol
    req_pars = get_required_parameters(tipo)
    return _get_object(tipo; getindex(subset, req_pars)...)
end
function get_required_parameters(tipo::DataType)
    tiposhort = split(string(tipo),".")[end]
    return "get_$(tiposhort)_parameters()" |> Meta.parse |> eval
end

function _get_object(tipo::DataType; kwargs...)
    tiposhort = split(string(tipo),".")[end]
    return eval(Meta.parse("_$(tiposhort)"))(; kwargs...)
end
_get_object(tipo::SolverType; kwargs...) = Solver(tipo; kwargs...)
_get_object(tipo::AbstractGridType; kwargs...) = Grid(tipo; kwargs...)





#===========================================================================
    DEANNUALISE PARAMETERS
    I introduce annual values, but the model period may be different (if
    years_per_period != 1)
===========================================================================#

function deannualise(pars, years_per_period)
    years_per_period==1 && return pars  # if years_per_period == 1, do nothing
    # Newpars
    β = pars.β^years_per_period
    ρ_z = pars.ρ_z^years_per_period
    σ_z = pars.σ_z*sqrt( sum( pars.ρ_z .^ (2*((1:years_per_period).-1)) ) )
    δ = 1-(1-pars.δ)^years_per_period
    # Create struct
    newpars = (; β, ρ_z, σ_z, δ)
    return merge(pars, newpars)
end




#===========================================================================
    READ PARAMETERS OR RESULTS
===========================================================================#

function import_csv(filepath; comment='#', delim='=')
    raw = []
    open(filepath, "r") do io
        while !eof(io)
            line = readline(io)
            if line[1] == comment
                continue
            else
                push!(raw, split(line,delim))
            end
        end
    end
    return NamedTuple(Symbol.(getindex.(raw, 1)) .=> eval.(Meta.parse.(getindex.(raw, 2))))
end



#===========================================================================
    BUILD MAIN STRUCTURES FROM PARAMETERS
===========================================================================#

function prepare_household_builder(pars)
    # Grids and processes
    process_z = get_object(pars, "_z"; typesubstr="Suffix")
    # Life-cycle structures
    ages = get_ages(; getindex(pars, get_life_cycle_parameters())...)
    ζ_pars = subset_namedtuple(pars, "ζ_"; typesubstr="Prefix") |> collect
    ζ_f(age::Real)::Real = max(dot(age.^(0:(length(ζ_pars)-1))', ζ_pars), 0.0)
    # Kwargs for households
    pars_pref = getindex(pars, get_preference_parameters())
    tipo_pref = pars_pref.tipo_pref
    pref_kwargs = pars_pref[filter(key -> key != :tipo_pref, keys(pars_pref))]
    pars_a = subset_namedtuple(pars, "_a"; typesubstr="Suffix")
    tipo_a = pars_a.tipo
    grid_a_kwargs = pars_a[filter(key -> key != :tipo, keys(pars_a))]
    # Return
    return (; ages, process_z, tipo_pref, pref_kwargs, tipo_a, grid_a_kwargs, ζ_f)
end

function build_configuration(pars)
    # Configuration of solvers
    cfg_r = get_object(pars, "cfg_r_")
    cfg_graph = _GraphConfig(; subset_namedtuple(pars, "cfg_graph_")...)
    return Configuration(cfg_r, cfg_graph, pars.years_per_period)
end

# Main function
function build_model(
    filepath = BASE_FOLDER * "/Simulations/parameters/default_parameters.csv";
    save_pars::Bool=true,   # by default, save parameters in file
    outputpath = BASE_FOLDER * "/Simulations/parameters/latest_simulation.csv",
    fiscal::Bool=false,  # if true, build a government too
    kwargs...
)
    # println(pwd())
    # println(filepath)
    # Read parameters
    pars_file = import_csv(filepath)
    pars_code = NamedTuple(kwargs)
    annual_pars = merge(pars_file, pars_code)  # merge parameters, prioritising those introduced in the command line
    # Write parameters in file
    save_pars && export_csv(outputpath, annual_pars; delim='=')
    # Deannualise parameters
    pars = deannualise(annual_pars, annual_pars.years_per_period)
    # Build structures
    hh = build_households(pars)
    fm = Firms(; getindex(pars, get_firm_parameters())...)
    cfg = build_configuration(pars)
    # Return structures
    if fiscal
        @eval using .Fiscal
        gb = build_government(pars, hh.gens)
        return (; hh, fm, gb, cfg)
    else
        return (; hh, fm, cfg)
    end
end