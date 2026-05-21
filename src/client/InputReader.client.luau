local Players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local shared = replicatedStorage:WaitForChild("Shared")
local modules = shared:WaitForChild("Modules")
local remotes = shared:WaitForChild("Remotes")

local StateModule = require(modules:WaitForChild("StateModule"))
local MovementModule = require(modules:WaitForChild("MovementModule"))
local GlideModule = require(modules:WaitForChild("GlideModule"))
local CameraModule = require(modules:WaitForChild("CameraModule"))
local CapeModule = require(modules:WaitForChild("CapeModule"))

local SendInput = remotes:WaitForChild("SendInput")

local Player = Players.LocalPlayer
local char = Player.Character or Player.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
local hrp = char:WaitForChild("HumanoidRootPart")

print("InputReader: character ready, calling inits")

MovementModule:init(char, hum, hrp)
GlideModule:init(char, hum)
CameraModule:init(char, hum, hrp)
CapeModule:init(char, hrp)
CameraModule:start()

print("InputReader: all inits done, state:", StateModule:getState())

local lastWTime = 0

local function getVelocity()
	return hrp.AssemblyLinearVelocity.Magnitude
end

local function fireServer()
	local state = StateModule:getState()
	print("fireServer: state =", state, "pos =", hrp.Position)
	SendInput:FireServer(state, hrp.Position, tick())
end

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	local currentState = StateModule:getState()
	print("InputBegan:", input.KeyCode, "| currentState:", currentState)

	if input.KeyCode == Enum.KeyCode.W then
		if tick() - lastWTime < 0.3 then
			print("Double tap W → running")
			StateModule:setState("running")
			fireServer()
		else
			lastWTime = tick()
		end
	end

	if input.KeyCode == Enum.KeyCode.Space then
		if currentState == "airborne" then
			print("Space in airborne → gliding")
			StateModule:setState("gliding")
			fireServer()
		else
			print("Space → airborne")
			StateModule:setState("airborne")
			fireServer()
		end
	end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		if currentState == "running" then
			print("Shift in running → sliding")
			StateModule:setState("sliding")
			fireServer()
		end
	end

	if input.KeyCode == Enum.KeyCode.LeftControl then
		print("Ctrl → ducking")
		StateModule:setState("ducking")
		fireServer()
	end

	if input.KeyCode == Enum.KeyCode.Q then
		print("Q → dashing")
		StateModule:setState("dashing")
		fireServer()
	end

	if input.KeyCode == Enum.KeyCode.F then
		print("F → rolling")
		StateModule:setState("rolling")
		fireServer()
	end

	if input.KeyCode == Enum.KeyCode.E then
		print("E → grappling")
		StateModule:setState("grappling")
		fireServer()
	end

	if input.KeyCode == Enum.KeyCode.C then
		print("C → toggleView")
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
			print("Shift released, velocity > 2 → running")
			StateModule:setState("running")
		else
			print("Shift released, velocity <= 2 → walking")
			StateModule:setState("walking")
		end
		fireServer()
	end

	if input.KeyCode == Enum.KeyCode.LeftControl then
		if getVelocity() > 2 then
			print("Ctrl released, velocity > 2 → running")
			StateModule:setState("running")
		else
			print("Ctrl released, velocity <= 2 → walking")
			StateModule:setState("walking")
		end
		fireServer()
	end

	if input.KeyCode == Enum.KeyCode.Space then
		if currentState == "gliding" then
			print("Space released in gliding → airborne")
			StateModule:setState("airborne")
			fireServer()
		end
	end

	if input.KeyCode == Enum.KeyCode.W then
		print("W released → walking")
		StateModule:setState("walking")
		fireServer()
	end
end)

print("InputReader: fully loaded")
