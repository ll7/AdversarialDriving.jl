# Decomposes a scene into smaller scenes made up of pairwise agents
function decompose_scene(scene::Scene, egoid::Int)
    scenes = Dict{Int, Scene}()
    ego = set_veh_id(get_by_id(scene, egoid), 2)
    for i=1:egoid-1
        if has_veh(i, scene)
            veh = set_veh_id(get_by_id(scene, i), 1)
            scenes[i] = Scene([veh, ego])
        end
    end
    scenes
end

# Functions for constructing vehicles


ez_Tint_vehicle(id, s, v, lane) = BlinkerVehicle(roadway = Tint_roadway,
                                              lane=lane, s=s, v = v,
                                              id = id, goals = Tint_goals[lane],
                                              blinker = Tint_should_blink[lane])
up_left(id; s::Float64 = 40., v::Float64 = 20.) = ez_Tint_vehicle(id, s, v, 5)
left_straight(id; s::Float64 = 15., v::Float64 = 19.) = ez_Tint_vehicle(id, s, v, 2)
left_turnright(id; s::Float64 = 15., v::Float64 = 19.) = ez_Tint_vehicle(id, s, v, 1)
right_straight(id; s::Float64 = 30., v::Float64 = 20.) = ez_Tint_vehicle(id, s, v, 3)
right_turnleft(id; s::Float64 = 40., v::Float64 = 14.) = ez_Tint_vehicle(id, s, v, 4)

ez_ped_vehicle(id, s, v) = BlinkerVehicle(roadway = ped_roadway,
                                              lane=1, s=s, v = v,
                                              id = id, goals = ped_goals[1],
                                              blinker = ped_should_blink[1])
ez_pedestrian(id, s, v) = NoisyPedestrian(roadway = ped_roadway, lane = 2, s=s, v=v, id=id)



# Create a random IntelligentDriverModel
function random_IDM()
    headway_t = max(0.5, rand(rng, Normal(1.5, 0.5))) # desired time headway [s]
    v_des = max(15.0, rand(rng, Normal(20.0, 5.0))) # desired speed [m/s]
    s_min = max(1.0, rand(rng, Normal(5.0, 1.0))) # minimum acceptable gap [m]
    a_max = max(2.0, rand(rng, Normal(3.0, 1.0))) # maximum acceleration ability [m/s²]
    IntelligentDriverModel(T = headway_t, v_des = v_des, s_min = s_min, a_max = a_max)
end

