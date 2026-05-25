local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local shared = ReplicatedStorage:WaitForChild("Shared")
local modules = shared:WaitForChild("Modules")
local parkour = modules:WaitForChild("Parkour")
local cameraModules = modules:WaitForChild("Camera")
local remotes = shared:WaitForChild("Remotes")

local StateModule = require(parkour:WaitForChild("StateModule"))
local MovementModule = require(parkour:WaitForChild("MovementModule"))
local GlideModule = require(parkour:WaitForChild("GlideModule"))
local CameraModule = require(cameraModules:WaitForChild("CameraModule"))
local CapeModule = require(parkour:WaitForChild("CapeModule"))

local SendInput = remotes:WaitForChild("SendInput")
local ReceiveCorrection = remotes:WaitForChild("ReceiveCorrection")

local player = Players.LocalPlayer
local char: Model
local hum: Humanoid
local hrp: BasePart

local RUN_SPEED = 30
local WALK_SPEED = 16

local lastWTap = 0
local wHeld = false
local spaceHeld = false
local correcting = false
local correctTarget: Vector3?

local function fireServer()
	if hrp then
		SendInput:FireServer(StateModule:getState(), hrp.Position, os.clock())
	end
end

local function tryState(newState: string): boolean
	local before = StateModule:getState()
	StateModule:setState(newState)
	if StateModule:getState() ~= before then
		fireServer()
		return true
	end
	return false
end

local function setupCharacter(newChar: Model)
	char = newChar
	hum = char:WaitForChild("Humanoid") :: Humanoid
	hrp = char:WaitForChild("HumanoidRootPart") :: BasePart

	CapeModule:destroy()
	MovementModule:init(char, hum, hrp)
	GlideModule:init(char, hum)
	CameraModule:init(char, hum, hrp)
	CapeModule:init(char, hrp)
	CameraModule:start()
	StateModule:forceState("walking")
end

setupCharacter(player.Character or player.CharacterAdded:Wait())
player.CharacterAdded:Connect(setupCharacter)

ReceiveCorrection.OnClientEvent:Connect(function(correctedPos: Vector3)
	correcting = true
	correctTarget = correctedPos
end)

RunService.Heartbeat:Connect(function(dt)
	if correcting and correctTarget then
		local dist = (hrp.Position - correctTarget).Magnitude
		if dist < 0.1 then
			correcting = false
			correctTarget = nil
		else
			hrp.CFrame =
				hrp.CFrame:Lerp(CFrame.new(correctTarget) * (hrp.CFrame - hrp.CFrame.Position), math.min(10 * dt, 1))
		end
	end

	if not hum or not hrp then
		return
	end

	local humanoidState = hum:GetState()
	local currentState = StateModule:getState()
	if currentState == "running" and not wHeld then
		tryState("walking")
		return
	end

	if currentState == "gliding" and hum.FloorMaterial ~= Enum.Material.Air then
		MovementModule:forceStopGlide()
		tryState("walking")
		return
	end

	if
		(currentState == "walking" or currentState == "running")
		and (humanoidState == Enum.HumanoidStateType.Freefall or humanoidState == Enum.HumanoidStateType.Jumping)
	then
		tryState("airborne")
	elseif spaceHeld and currentState == "airborne" and hrp.AssemblyLinearVelocity.Y < 2 then
		tryState("gliding")
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gpe: boolean)
	if gpe then
		return
	end

	local state = StateModule:getState()
	local kc = input.KeyCode

	if kc == Enum.KeyCode.W then
		wHeld = true
		local now = os.clock()
		if now - lastWTap < 0.3 and (state == "walking" or state == "running") then
			tryState("running")
		end
		lastWTap = now
	end

	if kc == Enum.KeyCode.Space then
		spaceHeld = true
		if state == "airborne" then
			tryState("gliding")
		elseif state == "walking" or state == "running" then
			hrp.AssemblyLinearVelocity = Vector3.new(
				hrp.AssemblyLinearVelocity.X,
				math.max(hrp.AssemblyLinearVelocity.Y, 30),
				hrp.AssemblyLinearVelocity.Z
			)
			tryState("airborne")
		end
	end

	if kc == Enum.KeyCode.LeftShift then
		local speed = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
		local wantsSlide = speed > 2 or hum.MoveDirection.Magnitude > 0.1
		if (state == "running" or state == "walking") and wantsSlide then
			tryState("sliding")
		end
	end

	if kc == Enum.KeyCode.LeftControl then
		if state == "walking" or state == "running" then
			tryState("ducking")
		end
	end

	if kc == Enum.KeyCode.Q then
		if state ~= "ducking" and state ~= "sliding" then
			tryState("dashing")
		end
	end

	if kc == Enum.KeyCode.F then
		if state ~= "ducking" and state ~= "sliding" then
			tryState("rolling")
		end
	end

	if kc == Enum.KeyCode.E then
		if state ~= "ducking" and state ~= "sliding" then
			tryState("grappling")
		end
	end

	if kc == Enum.KeyCode.C then
		CameraModule:toggleView()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject, gpe: boolean)
	if gpe then
		return
	end

	local state = StateModule:getState()
	local kc = input.KeyCode

	if kc == Enum.KeyCode.W then
		wHeld = false
		if state == "running" then
			tryState("walking")
		end
	end

	if kc == Enum.KeyCode.Space then
		spaceHeld = false
		if state == "gliding" then
			tryState("airborne")
		end
	end

	if kc == Enum.KeyCode.LeftShift then
		if state == "sliding" then
			local speed = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
			tryState(speed > RUN_SPEED * 0.5 and "running" or "walking")
		end
	end

	if kc == Enum.KeyCode.LeftControl then
		if state == "ducking" then
			local speed = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
			tryState(speed > WALK_SPEED * 0.7 and "running" or "walking")
		end
	end
end)
