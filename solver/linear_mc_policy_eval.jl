using POMDPSimulators
using Parameters
using LinearAlgebra
using Test
using POMDPs

# Linear model that retains matrices for online fitting
# NOTE: Probably not good to use when the number of paramters is large
@with_kw mutable struct LinearModel
    θ::Array{Float64} = []
    XTX::Array{Float64,2} = []
    XTy::Array{Float64} = []
end

#  Constructors for the linear models
LinearModel(n_dim::Int) = LinearModel(zeros(n_dim), zeros(n_dim, n_dim), zeros(n_dim))
LinearModel(θ::Array{Float64}) = LinearModel(θ, zeros(length(θ), length(θ)), zeros(length(θ)))

# Fit the linear model using new data X, and y added to other data already used to fit the model
function fit!(model::LinearModel, X, y)
    d = length(model.θ)
    # add the new data to the existing data
    model.XTX = model.XTX .+ (X' * X)
    model.XTy = model.XTy .+ (X' * y)

    all(model.XTy .== 0) && return zeros(length(model.θ))

    A = model.XTX + 1e-6*Matrix{Float64}(I,d,d)
    model.θ = pinv(A)*model.XTy
end

# Evaluate the model on some data
forward(model::LinearModel, X) = X * model.θ

# Test the linear model
X = rand(100,2)
X2 = rand(100, 2)
θt = [1., 2.]
y = X * θt
y2 = rand(100)

model = LinearModel(length(θt))
@test model.θ == [0,0]
fit!(model, X, y)
@test all(isapprox.(model.θ, θt, rtol=1e-5, atol=1e-5))
model.θ = θt
@test all(forward(LinearModel([1., 2.]), X) .== y)

two_part_model = LinearModel(length(θt))
fit!(two_part_model, X, y)
fit!(two_part_model, X2, y2)

full_model = LinearModel(length(θt))
fit!(full_model, vcat(X,X2), vcat(y,y2))

@test all(isapprox.(two_part_model.θ, full_model.θ))

mse(est, truth) = sum((est .- truth).^2)/length(truth)

# Definea special type of policy that uses a model, and has a probability of failure
# estimator defined by the user. This estimator will be filled in by the subproblems
mutable struct ISPolicy <: Policy
    mdp # The mdp this problem is associated with
    corrective_model # Model that corrects for deviations from the observed probabilty of failure
    estimate # Estimate of the failure probability. Function of the form estimate(mdp, s)
end

# Computes the estimated probability of failure at the provided state
# The probability is bounded between 0 and 1, and is
function POMDPs.value(p::ISPolicy, s)
    est = p.estimate(p.mdp, s)
    cor = forward(p.corrective_model, convert_s(AbstractArray, s, p.mdp)')
    min(1, max(0, cor + est))
end

# Selects an action to take according to the probability of failure
function POMDPs.action(p::ISPolicy, s, rng = Random.GLOBAL_RNG)
    # TODO: We probably need a way to sample actions instead of enumerating
    as = actions(p.mdp, s)
    Na = length(as)
    pf = Array{Float64}(undef, Na)
    for i=1:Na
        a = as[i]
        sp, r = gen(DDNOut((:sp,:r)), p.mdp, s, a, rng)
        pf[i] = action_probability(p.mdp, s, a)*value(p, sp)
    end
    sum_pf = sum(pf)
    pf = (sum_pf == 0) ? ones(Na)/Na : pf/sum_pf
    ai = rand(Categorical(pf))
    as[ai], pf[ai]
end

# Convert an array of states into a state matrix
# NOTE: For some reason using vcat is very slow so we do it this way
function to_mat(S)
    X = Array{Float64, 2}(undef, length(S),length(S[1]))
    for i=1:size(X,1)
        X[i,:] = S[i]
    end
    X
end


# Simulate the mdp through Neps episodes.
# Requires ISPolicy because it stores the failure probability estimates at each timestep
function sim(policy::ISPolicy, Neps; verbose = true, max_steps = 1000)
    mdp = policy.mdp
    # ρ is the importance sampling weight of the associated action
    # W is the weight of the trajectory from that state (cumulative)
    S, A, R, G, ρ, W, pf_est = [], [], [], [], [], [], []
    for i=1:Neps
        verbose && println("   Rolling out episode ", i)
        s = initialstate(mdp)
        Si, Ai, Ri, ρi, pfi = [convert_s(AbstractArray, s, mdp)], [], [], [], []
        steps = 0
        while !isterminal(mdp, s)
            push!(pfi, policy.estimate(mdp, s))
            a, prob = action(policy, s)
            push!(Ai, a)
            push!(ρi, action_probability(mdp, s, a) / prob)
            s, r = gen(DDNOut((:sp, :r)), mdp, s, a)
            push!(Si, convert_s(AbstractArray, s, mdp))
            push!(Ri, r)
            steps += 1
            steps >= max_steps && break
        end
        steps >= max_steps && println("Episode timeout at ", max_steps, " steps")
        Gi = reverse(cumsum(reverse(Ri)))
        Wi = reverse(cumprod(reverse(ρi)))
        push!(S, Si[1:end-1]...)
        push!(A, Ai...)
        push!(R, Ri...)
        push!(G, Gi...)
        push!(ρ, ρi...)
        push!(W, Wi...)
        push!(pf_est, pfi...)
    end
    to_mat(S), A, R, G, ρ, W, pf_est
end

# Fits the correct model based on rollouts
function mc_policy_eval(policy::ISPolicy, max_iterations, Neps; verbose = true)
    for iter in 1:max_iterations
        verbose && println("iteration: ", iter)
        X, _, _, G, _, W, pf_est = sim(policy, Neps, verbose = verbose)
        y = W .* G .- pf_est

        fit!(policy.corrective_model, X, y)
    end
    model
end
