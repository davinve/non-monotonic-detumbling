using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
import SatelliteDynamics
using Random
Random.seed!(0)
using Colors
using PGFPlotsX
using LaTeXStrings
using LinearAlgebra
using Formatting

include("../src/satellite_simulator.jl")
include("../src/detumble_controller.jl")
include("../src/satellite_models.jl")

detumble_color_list = distinguishable_colors(6, [RGB(1, 1, 1), RGB(0, 0, 0)], dropseed=true)

color_mode = "_dark_mode"
# color_mode = "" # normal

function color_to_pgf_string(c::Colors.Colorant)
    rgb = convert(Colors.RGB{Float64}, c)
    str = format("rgb,1:red,{:.4f};green,{:.4f};blue,{:.4f}", Colors.red(rgb), Colors.green(rgb), Colors.blue(rgb))
    return raw"{" * str * raw"}"
end

if color_mode == "_dark_mode"
    const color_grid = RGBA(([148, 148, 148, 255] ./ 255)...)
    const color_text = RGBA(([205, 209, 209, 255] ./ 255)...)
    const color_axis = color_text
    const color_bg = RGBA(([0x00, 0x22, 0x39, 0xFF] ./ 255)...)
else
    const color_grid = RGBA(([191, 191, 191, 255] ./ 255)...)
    const color_text = RGBA(([0, 0, 0, 255] ./ 255)...)
    const color_axis = color_text
    const color_bg = RGBA(([255, 255, 255, 255] ./ 255)...)
end

color_grid_pgf = color_to_pgf_string(color_grid)
color_text_pgf = color_to_pgf_string(color_text)
color_axis_pgf = color_to_pgf_string(color_axis)
color_bg_pgf = color_to_pgf_string(color_bg)


params = OrbitDynamicsParameters(py4_model_no_noise_diagonal;
    distance_scale=1.0,
    time_scale=1.0,
    angular_rate_scale=1.0,
    control_scale=1,
    control_type=:dipole,
    magnetic_model=:IGRF13,
    add_solar_radiation_pressure=true,
    add_sun_thirdbody=true,
    add_moon_thirdbody=true)

x0 = [
    6.77710395701087e6
    -118294.78959490504
    0.0
    86.02735177981981
    4928.503682661721
    5874.456678131549
    0.15508705047693072
    0.3746535184890531
    0.9141021539511538
    -0.0
    0.0
    0.0
    0.8726646259971648
]

tspan = (0.0, 5 * 60 * 60.0)

x_osc_0 = SatelliteDynamics.sCARTtoOSC(x0[1:6])

k_bcross = bcross_gain(x_osc_0, params)
xhist_bcross, uhist_bcross, thist_bcross = simulate_satellite_orbit_attitude_rk4(x0, params, tspan; integrator_dt=0.1, controller=(x, t, m) -> bcross_control(x, t, m; k=k_bcross, saturate=true), controller_dt=0.0)

k_bcross_stuck = 100 * k_bcross
xhist_bcross_stuck, uhist_bcross_stuck, thist_bcross_stuck = simulate_satellite_orbit_attitude_rk4(x0, params, tspan; integrator_dt=0.1, controller=(x, t, m) -> bcross_control(x, t, m; k=k_bcross_stuck, saturate=true), controller_dt=0.0)

J = params.satellite_model.inertia
downsample = get_downsample(length(thist_bcross), 100)

ω_bcross = xhist_bcross[11:13, downsample]
h_bcross = J * ω_bcross
h̄_bcross = dropdims(sqrt.(sum(h_bcross .* h_bcross, dims=1)); dims=1)
t_plot_bcross = thist_bcross[downsample] / (60 * 60)

ω_bcross_stuck = xhist_bcross_stuck[11:13, downsample]
h_bcross_stuck = J * ω_bcross_stuck
h̄_bcross_stuck = dropdims(sqrt.(sum(h_bcross_stuck .* h_bcross_stuck, dims=1)); dims=1)
t_plot_bcross_stuck = thist_bcross_stuck[downsample] / (60 * 60)

lineopts1 = @pgf {no_marks, "very thick", style = "solid", color = detumble_color_list[2], opacity = 1.0}
lineopts2 = @pgf {no_marks, "very thick", style = "solid", color = detumble_color_list[4], opacity = 1.0}

pin_bcross = "[text=" * color_text_pgf * ", fill=" * color_bg_pgf * ", draw=" * color_text_pgf * "]right:" * format("k = {:.2e}", k_bcross)
pin_bcross_stuck = "[text=" * color_text_pgf * ", fill=" * color_bg_pgf * ", draw=" * color_text_pgf * "]above:" * format("k = {:.2e}", k_bcross_stuck)

p = @pgf Axis(
    {
        "grid style" = {"color" = color_grid},
        "label style" = {"color" = color_text},
        "tick label style" = {"color" = color_text},
        "axis line style" = {"color" = color_axis},
        xmajorgrids,
        ymajorgrids,
        height = "2.5in",
        width = "3.5in",
        xlabel = "Time (hours)",
        ylabel = L"$\|h\|$ (Nms)",
        legend_pos = "north east",
        title = raw"{\rule{0pt}{1pt}}",
    },
    PlotInc(lineopts1, Coordinates(t_plot_bcross, h̄_bcross)),
    PlotInc(lineopts2, Coordinates(t_plot_bcross_stuck, h̄_bcross_stuck)),
    [raw"\node ",
        {
            pin = pin_bcross
        },
        " at ",
        Coordinate(t_plot_bcross[10], h̄_bcross[10]),
        "{};"],
    [raw"\node ",
        {
            pin = pin_bcross_stuck
        },
        " at ",
        Coordinate(t_plot_bcross[70], h̄_bcross_stuck[70]),
        "{};"],
)

pgfsave(joinpath(@__DIR__, "..", "figs", "pdf", "bcross_stuck" * color_mode * ".pdf"), p)
pgfsave(joinpath(@__DIR__, "..", "figs", "bcross_stuck" * color_mode * ".tikz"), p, include_preamble=false)