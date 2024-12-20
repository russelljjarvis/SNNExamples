using DrWatson
using Revise
using SpikingNeuralNetworks
SNN.@load_units;
using SNNUtils
using Plots
using Statistics
using Distributions

## Define the network parameters

function run_model()
    # Number of neurons in the network
    NE = 1500
    NI = NE ÷ 4
    NI1 = round(Int,NI * 0.35)
    NI2 = round(Int,NI * 0.65)

    # Import models parameters
    I1_params = duarte2019.PV
    I2_params = duarte2019.SST
    @unpack connectivity, plasticity = quaresima2023
    @unpack dends, NMDA, param, soma_syn, dend_syn = quaresima2022

    # Define interneurons I1 and I2
    I1 = SNN.IF(; N = NI1, param = I1_params, name="I1_pv")
    I2 = SNN.IF(; N = NI2, param = I2_params, name="I2_sst")
    E = SNN.BallAndStickHet(N = NE, soma_syn = soma_syn, dend_syn = dend_syn, NMDA = NMDA, param = param, name="Exc")
    # background noise
    noise = Dict(
        # :noise_s   => SNN.PoissonStimulus(E,  :he_s,  param=1.0kHz, cells=:ALL, μ=0.f0, name="noise_s",),
        :d   => SNN.PoissonStimulus(E,  :he_d,  param=10.0kHz, cells=:ALL, μ=1.f0, name="noise_s",),
        :i1  => SNN.PoissonStimulus(I1, :ge,   param=1.5kHz, cells=:ALL, μ=1.f0,  name="noise_i1"),
        :i2  => SNN.PoissonStimulus(I2, :ge,   param=2.0kHz, cells=:ALL, μ=1.8f0, name="noise_i2")
    )
    syn= Dict(
    :I1_to_I1 => SNN.SpikingSynapse(I1, I1, :gi; connectivity.IfIf...),
    :I1_to_I2 => SNN.SpikingSynapse(I1, I2, :gi; connectivity.IfIs...),
    :I2_to_I2 => SNN.SpikingSynapse(I2, I2, :gi; connectivity.IsIs...),
    :I2_to_I1 => SNN.SpikingSynapse(I2, I1, :gi; connectivity.IsIf...),
    :I1_to_E  => SNN.SpikingSynapse(I1, E, :hi, :s; param = plasticity.iSTDP_rate, connectivity.EIf...),
    :I2_to_E  => SNN.SpikingSynapse(I2, E, :hi, :d; param = plasticity.iSTDP_potential, connectivity.EdIs...),
    :E_to_I1  => SNN.SpikingSynapse(E, I1, :ge; connectivity.IfE...),
    :E_to_I2  => SNN.SpikingSynapse(E, I2, :ge; connectivity.IsE...),
    :E_to_E   => SNN.SpikingSynapse(E, E, :he, :d ; connectivity.EdE...),
    )
    pop = dict2ntuple(@strdict I1 I2 E)

    # Return the network as a model
    network = merge_models(pop, noise=noise, syn)
    SNN.train!(model=network, duration= 5s, pbar=true, dt=0.125)
    SNN.monitor([network.pop...], [:fire, :v_d, :v_s, :v, (:g_d, [10,20,30,40,50]), (:ge_s, [10,20,30,40,50]), (:gi_s, [10,20,30,40,50])], sr=200Hz)
    mytime = SNN.Time()
    SNN.train!(model=network, duration= 10s, pbar=true, dt=0.125, time=mytime)
    return network
end

model = run_model()
plot_activity(model, 5s:2ms:10s)
vecplot(model.pop.E, :v_s, neurons =1, r=9s:10s,label="soma")
plot(histogram(getvariable(model.pop.E, :v_s)[:]), histogram(getvariable(model.pop.E, :v_d)[:]))
