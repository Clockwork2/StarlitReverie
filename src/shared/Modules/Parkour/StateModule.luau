local StateModule = {}

StateModule.States = {
	WALKING = "walking",
	RUNNING = "running",
	SLIDING = "sliding",
	DUCKING = "ducking",
	ROLLING = "rolling",
	WALLRUNNING = "wallrunning",
	GRAPPLING = "grappling",
	AIRBORNE = "airborne",
	GLIDING = "gliding",
	DASHING = "dashing",
}

StateModule.ValidTransitions = {
	walking = { "running", "sliding", "airborne", "ducking", "dashing", "rolling", "grappling" },
	running = { "walking", "sliding", "rolling", "airborne", "wallrunning", "ducking", "dashing", "grappling" },
	airborne = { "walking", "running", "wallrunning", "grappling", "gliding", "dashing", "rolling" },
	gliding = { "airborne", "wallrunning", "grappling", "walking", "running", "dashing", "rolling" },
	wallrunning = { "airborne", "walking", "running", "dashing", "rolling" },
	grappling = { "airborne", "walking", "running", "gliding", "dashing", "rolling" },
	sliding = { "walking", "running", "airborne" },
	ducking = { "walking", "running" },
	rolling = { "airborne", "walking", "running" },
	dashing = { "walking", "running", "airborne" },
}

local subscribers: { (string, string?) -> () } = {}
local currentState: string = "walking"
local previousState: string? = nil

local function notifySubscribers(newState: string, oldState: string?)
	for _, fn in ipairs(subscribers) do
		local ok, err = pcall(fn, newState, oldState)
		if not ok then
			warn("[StateModule] subscriber failed:", err)
		end
	end
end

function StateModule:AddSubscriber(fn: (string, string?) -> ())
	table.insert(subscribers, fn)
	return function()
		local index = table.find(subscribers, fn)
		if index then
			table.remove(subscribers, index)
		end
	end
end

function StateModule:setState(newState: string)
	if newState == currentState then
		return
	end

	local allowed = false
	local transitions = StateModule.ValidTransitions[currentState]
	if transitions then
		for _, v in ipairs(transitions) do
			if v == newState then
				allowed = true
				break
			end
		end
	end

	if not allowed then
		return
	end

	previousState = currentState
	currentState = newState

	notifySubscribers(currentState, previousState)
end

function StateModule:forceState(newState: string)
	if newState == currentState then
		return
	end
	previousState = currentState
	currentState = newState
	notifySubscribers(currentState, previousState)
end

function StateModule:getState(): string
	return currentState
end

function StateModule:getPrevious(): string?
	return previousState
end

return StateModule
