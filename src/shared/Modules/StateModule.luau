local StateModule = {}

StateModule.States = {
	IDLE = "idle",
	RUNNING = "running",
	SLIDING = "sliding",
	DUCKING = "ducking",
	ROLLING = "rolling",
	WALLRUNNING = "wallrunning",
	GRAPPLING = "grappling",
	AIRBORNE = "airborne",
	GLIDING = "gliding",
	WALKING = "walking",
}

StateModule.ValidTransitions = {
	walking = { "running", "airborne", "ducking" },
	running = { "walking", "sliding", "rolling", "airborne", "wallrunning", "ducking" },
	airborne = { "walking", "running", "wallrunning", "grappling", "gliding" },
	gliding = { "airborne", "wallrunning", "grappling", "walking" },
	wallrunning = { "airborne", "walking" },
	grappling = { "airborne", "walking" },
	sliding = { "walking", "running", "airborne" },
	ducking = { "walking", "running" },
	rolling = { "airborne", "walking", "running" },
}

local subscribers = {}

local currentState = "idle"
local previousState = nil

function StateModule:AddSubscriber(subscriberFunction)
	table.insert(subscribers, subscriberFunction)
end

function StateModule:setState(stateToSet)
	local currentStateTable = StateModule.ValidTransitions[currentState]
	if not currentStateTable then
		return
	end

	local allowed = false
	for _, viableState in ipairs(currentStateTable) do
		if viableState == stateToSet then
			allowed = true
			break
		end
	end

	if not allowed then
		print("Not a viable transition")
		return
	end

	previousState = currentState
	currentState = stateToSet

	for _, Function in ipairs(subscribers) do
		Function(currentState, previousState)
	end
end

function StateModule:getState()
	return currentState
end

function StateModule:getPrevious()
	return previousState
end

return StateModule
