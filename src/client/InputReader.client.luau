local Players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Modules = replicatedStorage:WaitForChild("Shared"):WaitForChild("Modules")
local CameraModule = require(Modules:WaitForChild("CameraModule"))
local Remotes = replicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
local StateModule = require(Modules:WaitForChild("StateModule"))
local SendInput = Remotes:WaitForChild("SendInput")
local Player = Players.LocalPlayer

local lastWTime = 0
local char = Player.Character or Player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")
if not hrp then
	return
end

local function getVelocity()
	return hrp.AssemblyLinearVelocity.Magnitude
end

local function fireServer()
	SendInput:FireServer(StateModule:getState(), hrp.Position, tick())
end

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	local currentState = StateModule:getState()

	if input.KeyCode == Enum.KeyCode.W then
		if tick() - lastWTime < 0.3 then
			StateModule:setState("running")
			fireServer()
		else
			lastWTime = tick()
		end
	end

	if input.KeyCode == Enum.KeyCode.Space then
		if currentState == "airborne" then
			StateModule:setState("gliding")
			fireServer()
		else
			StateModule:setState("airborne")
			fireServer()
		end
	end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		if currentState == "running" then
			StateModule:setState("sliding")
			fireServer()
		else
			return
		end
	end

	if input.KeyCode == Enum.KeyCode.LeftControl then
		StateModule:setState("ducking")
		fireServer()
	end

	if input.KeyCode == Enum.KeyCode.Q then
		StateModule:setState("dashing")
		fireServer()
	end

	if input.KeyCode == Enum.KeyCode.F then
		StateModule:setState("rolling")
		fireServer()
	end

	if input.KeyCode == Enum.KeyCode.E then
		StateModule:setState("grappling")
		fireServer()
	end

	if input.KeyCode == Enum.KeyCode.C then
		CameraModule:toggleView()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	local currentState = StateModule:getState()

	if input.KeyCode == Enum.KeyCode.LeftShift then
		if getVelocity() > 2 then
			StateModule:setState("running")
		else
			StateModule:setState("walking")
		end
		fireServer()
	end

	if input.KeyCode == Enum.KeyCode.LeftControl then
		if getVelocity() > 2 then
			StateModule:setState("running")
		else
			StateModule:setState("walking")
		end
		fireServer()
	end

	if input.KeyCode == Enum.KeyCode.Space then
		if currentState == "gliding" then
			StateModule:setState("airborne")
			fireServer()
		end
	end

	if input.KeyCode == Enum.KeyCode.W then
		StateModule:setState("walking")
		fireServer()
	end
end)
