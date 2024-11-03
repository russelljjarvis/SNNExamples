using DrWatson
using Revise
using SpikingNeuralNetworks
SNN.@load_units;
using SNNUtils
using Plots
using Statistics
using Distributions

## Define the network parameters
NE = 1000
NI = 1000 ÷ 4
NI1 = round(Int,NI * 0.35)
NI2 = round(Int,NI * 0.65)

# Import models parameters
I1_params = duarte2019.PV
I2_params = duarte2019.SST
E_params = quaresima2022
@unpack connectivity, plasticity = quaresima2023


network = let
    # Number of neurons in the network
    # Define neurons and synapses in the network
	# proximal_distal = [(150um, 400um), (150um, 400um)], defines the dendrite dimensions later used in create_dendrite
    @unpack dends, NMDA, param, soma_syn, dend_syn = E_params
    E = SNN.Tripod(dends...;
        N = NE,
        soma_syn = soma_syn,
        dend_syn = dend_syn,
        NMDA = NMDA,
        param = param
    )

    # Define interneurons I1 and I2
    I1 = SNN.IF(; N = NI1, param = I1_params)
    I2 = SNN.IF(; N = NI2, param = I2_params)
    # Define synaptic interactions between neurons and interneurons

    E_to_I1 = SNN.SpikingSynapse(E, I1, :ge; connectivity.IfE...)
    E_to_I2 = SNN.SpikingSynapse(E, I2, :ge; connectivity.IsE...,)

    I1_to_E = SNN.CompartmentSynapse(
        I1,
        E,
        :s,
        :hi;
        param = plasticity.iSTDP_rate,
        connectivity.EIf...,
    )

    I2_to_E_d1 = SNN.CompartmentSynapse( # what learning rate should I use?
        I2,
        E,
        :d1,
        :hi;
        param = plasticity.iSTDP_potential,
        connectivity.EdIs...,
    )

    I2_to_E_d2 = SNN.CompartmentSynapse( # what learning rate should I use?
        I2,
        E,
        :d2,
        :hi;
        param = plasticity.iSTDP_potential,
        connectivity.EdIs...,
    )

    # Define recurrent connections in the network
    I1_to_I1 = SNN.SpikingSynapse(I1, I1, :gi; connectivity.IfIf...)
    I2_to_I2 = SNN.SpikingSynapse(I1, I2, :gi; connectivity.IsIs...)
    I1_to_I2 = SNN.SpikingSynapse(I1, I2, :gi; connectivity.IfIs...)
    I2_to_I1 = SNN.SpikingSynapse(I2, I1, :gi; connectivity.IsIf...)

    E_to_E1_d1 = SNN.CompartmentSynapse(
        E,
        E,
        :d1,
        :he;
        # param = plasticity.vstdp,
        connectivity.EdE...,
    )

    E_to_E2_d2 = SNN.CompartmentSynapse(
        E,
        E,
        :d2,
        :he;
        param = plasticity.vstdp,
        connectivity.EdE...,
    )

    # Define normalization
    recurrent_norm =
    [
        SNN.SynapseNormalization(NE, [E_to_E1_d1], param = SNN.MultiplicativeNorm(τ = 20ms)),
        SNN.SynapseNormalization(NE, [E_to_E2_d2], param = SNN.MultiplicativeNorm(τ = 20ms))
    ]

    # Store neurons and synapses into a dictionary
    pop = dict2ntuple(@strdict E I1 I2)
    syn = dict2ntuple(@strdict E_to_I1 E_to_I2 I1_to_E I2_to_E_d1 I2_to_E_d2 I1_to_I1 I2_to_I2 I1_to_I2 I2_to_I1 E_to_E1_d1 E_to_E2_d2 norm1=recurrent_norm[1] norm2=recurrent_norm[2])
    
	# Return the network as a tuple
    (pop = pop, syn = syn)
end

# Stimulus
# Background noise
stimuli = Dict(
    :noise_s   => SNN.PoissonStimulus(network.pop.E,  :he_s,  param=4.0kHz, cells=:ALL, μ=5.f0,),
    :noise_i1  => SNN.PoissonStimulus(network.pop.I1, :ge,   param=2.0kHz, cells=:ALL, μ=1.f0),
    :noise_i2  => SNN.PoissonStimulus(network.pop.I2, :ge,   param=2.5kHz, cells=:ALL, μ=1.5f0),
    
)
baseline = merge_models(stimuli, network)
baseline = merge_models(stimuli, network)


# Sequence input
dictionary = Dict(:AB=>[:A, :B], :BA=>[:B, :A])
duration = Dict(:A=>40, :B=>60, :_=>100)

config_lexicon = ( ph_duration=duration, dictionary=dictionary)
lexicon = generate_lexicon(config_lexicon)

config_sequence = (init_silence=1s, seq_length=200, silence=1,)
seq = generate_sequence(lexicon, config_sequence, 1234)

function step_input(x, param::PSParam) 
    intervals::Vector{Vector{Float32}} = param.variables[:intervals]
    if time_in_interval(x, intervals)
        my_interval = start_interval(x, intervals)
        return 3kHz * 3kHz*(1-exp(-(x-my_interval)/10))
        # return 0kHz
    else
        return 0kHz
    end
end

stim_d1 = Dict{Symbol,Any}()
stim_d2 = Dict{Symbol,Any}()
for w in seq.symbols.words
    param = PSParam(rate=step_input, 
                    variables=Dict(:intervals=>sign_intervals(w, seq)))
    push!(stim_d1,w  => SNN.PoissonStimulus(network.pop.E, :he, :d1, μ=4.f0, param=param))
    push!(stim_d2,w  => SNN.PoissonStimulus(network.pop.E, :he, :d2, μ=4.f0, param=param))
    push!(stim_d2,w  => SNN.PoissonStimulus(network.pop.E, :he, :d2, μ=4.f0, param=param))
end
for p in seq.symbols.phonemes
    param = PSParam(rate=step_input, 
                    variables=Dict(:intervals=>sign_intervals(p, seq)))
    push!(stim_d1,p  => SNN.PoissonStimulus(network.pop.E, :he, :d1, μ=4.f0, param=param))
    push!(stim_d2,p  => SNN.PoissonStimulus(network.pop.E, :he, :d2, μ=4.f0, param=param))
end

stim_d1 = dict2ntuple(stim_d1)
stim_d2 = dict2ntuple(stim_d2)
model = merge_models(baseline, d1=stim_d1, d2=stim_d2)

# %%
SNN.monitor(model.pop.E, [:fire, :v_d1,])
#  :v_s, :v_d1, :v_d2, :h_s, :h_d1, :h_d2, :g_d1, :g_d2])
# SNN.monitor(model.pop.I1, [:fire, :v, :ge, :gi])
# SNN.monitor(model.pop.I2, [:fire, :v, :ge, :gi])
SNN.monitor([network.pop...], [:fire])
duration = sequence_end(seq)
# @profview 
mytime = SNN.Time()
SNN.train!(model=model, duration= duration, pbar=true, dt=0.125, time=mytime)
SNN.raster([network.pop...], (13s,16s))
## Target activation with stimuli
p=plot()
cells = collect(intersect(Set(stim_d1.A.cells)))
SNN.vecplot!(p,model.pop.E, :v_d1, r=9.5s:10.5s, neurons=cells, dt=0.125, pop_average=true)
myintervals = sign_intervals(:A, seq)
vline!(myintervals, c=:red)
##
SNN.average_firing_rate(model.pop.E)

model.syn.I1_to_E.W