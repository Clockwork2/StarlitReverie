local MovementModule = {}

local RunService = game:GetService("RunService")
local workspace = game:GetService("Workspace")

local Modules = script.Parent
local StateModule = require(Modules:WaitForChild("StateModule"))
local GlideModule = require(Modules:WaitForChild("GlideModule"))

local character, hum, hrp

local glideConnection
local glideForce
local glideatt
local slideConnection
local airborneConnection
local wallrunConnection
local wallrunNormal
local grappleConnection
local grappleAnchor

local WALK_SPEED = 16
local RUN_SPEED = 24
local SLIDE_FORCE = 80
local SLIDE_DECEL = 15
local DASH_FORCE = 120
local CAN_DASH = true
local DASH_COOLDOWN = 0.8
local DASH_DURATION = 0.2
local CAN_ROLL = true
local WALLRUN_SPEED = 28
local WALLRUN_GRAVITY_SCALE = 0.1
local GRAPPLE_FORCE = 60
local GLIDE_THRUST = 40
local GRAPPLE_MAX_DIST = 50
local GLIDE_GRAVITY_SCALE = 0.15
local GLIDE_BANK_FORCE = 20

function MovementModule:init(char, humanoid, rootPart)
	character = char
	hum = humanoid
	hrp = rootPart
end
function MovementModule:checkWall()
	local origin = hrp.Position
	local right = hrp.CFrame.RightVector
	local left = -hrp.CFrame.RightVector

	local rightDirection = right * 5
	local leftDirection = left * 5

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local leftResult = workspace:Raycast(origin, leftDirection, params)
	local rightResult = workspace:Raycast(origin, rightDirection, params)

	return leftResult, rightResult
end

local function checkGround(downwardsRay)
	local origin = hrp.Position
	local direction = Vector3.new(0, -downwardsRay, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local result = workspace:Raycast(origin, direction, params)

	return result
end

function MovementModule:endSlide()
	if slideConnection then
		slideConnection:Disconnect()
	end
	hum.WalkSpeed = WALK_SPEED
end

function MovementModule:endDuck()
	hum.HipHeight = 0
	hum.WalkSpeed = WALK_SPEED
end

function MovementModule:endAirborne()
	airborneConnection:Disconnect()
end

function MovementModule:endWallRun()
	if wallrunConnection then
		wallrunConnection:Disconnect()
		hum.AutoRotate = true
		wallrunNormal = nil
	end
end

function MovementModule:endGrapple()
	grappleConnection:Disconnect()
	grappleAnchor = nil
	hum.AutoRotate = true
end

function MovementModule:endGlide()
	glideConnection:Disconnect()
	glideForce:Destroy()
	glideatt:Destroy()
	GlideModule:stop()
end

function MovementModule:startWalking()
	hum.WalkSpeed = WALK_SPEED
end

function MovementModule:startRunning()
	hum.WalkSpeed = RUN_SPEED
end

function MovementModule:startSlide()
	local dir = hrp.AssemblyLinearVelocity.Unit
	hrp.AssemblyLinearVelocity = dir * SLIDE_FORCE
	hum.WalkSpeed = 0

	slideConnection = RunService.Heartbeat:Connect(function(dt)
		local vel = hrp.AssemblyLinearVelocity
		local newVel = vel * (1 - SLIDE_DECEL * dt)
		hrp.AssemblyLinearVelocity = newVel
		if newVel.Magnitude <= 2 then
			slideConnection:Disconnect()
			StateModule:setState("walking")
		end
	end)
end

function MovementModule:startDuck()
	hum.WalkSpeed = WALK_SPEED / 2
	hum.HipHeight = -1
end

function MovementModule:startDash()
	if not CAN_DASH then
		return
	end
	CAN_DASH = false
	local direction = hrp.CFrame.LookVector
	hum.AutoRotate = false
	hrp.AssemblyLinearVelocity =
		Vector3.new(direction.X * DASH_FORCE, hrp.AssemblyLinearVelocity.Y, direction.Z * DASH_FORCE)

	task.delay(DASH_COOLDOWN, function()
		CAN_DASH = true
	end)

	task.delay(DASH_DURATION, function()
		local floor = hum.FloorMaterial
		if floor == Enum.Material.Air then
			StateModule:setState("airborne")
		else
			StateModule:setState("walking")
		end
		hum.AutoRotate = true
	end)
end

function MovementModule:startRoll()
	if not CAN_ROLL then
		return
	end
	CAN_ROLL = false
	hum.AutoRotate = false
	local direction = hrp.CFrame.LookVector
	hum.HipHeight = -0.5
	hrp.AssemblyLinearVelocity = Vector3.new(direction.X * 60, hrp.AssemblyLinearVelocity.Y, direction.Z * 60)
	task.delay(0.2, function()
		local floor = hum.FloorMaterial
		if floor == Enum.Material.Air then
			StateModule:setState("airborne")
		else
			StateModule:setState("walking")
		end
		hum.HipHeight = 0
		hum.AutoRotate = true
		CAN_ROLL = true
	end)
end

function MovementModule:startWallRun()
	local leftResult, rightResult = MovementModule:checkWall()

	if rightResult then
		wallrunNormal = rightResult.Normal
	elseif leftResult then
		wallrunNormal = leftResult.Normal
	else
		print("No runnable wall")
		return
	end

	hum.WalkSpeed = WALLRUN_SPEED
	hum.AutoRotate = false

	wallrunConnection = RunService.Heartbeat:Connect(function(dt)
		local velocity = hrp.AssemblyLinearVelocity
		local newY = math.max(velocity.Y * WALLRUN_GRAVITY_SCALE, -5)
		local newVelocity = Vector3.new(velocity.X, newY, velocity.Z)
		hrp.AssemblyLinearVelocity = newVelocity

		local leftResult, rightResult = MovementModule:checkWall()

		if rightResult then
			wallrunNormal = rightResult.Normal
		elseif leftResult then
			wallrunNormal = leftResult.Normal
		else
			StateModule:setState("airborne")
			return
		end

		local result = checkGround(3)
		if result then
			StateModule:setState("walking")
			return
		end
	end)
end

function MovementModule:startGrapple()
	local origin = hrp.Position
	local direction = hrp.CFrame.LookVector * GRAPPLE_MAX_DIST
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local result = workspace:Raycast(origin, direction, params)
	if not result then
		return
	end

	grappleAnchor = result.Position
	hum.AutoRotate = false

	grappleConnection = RunService.Heartbeat:Connect(function(dt)
		local grappleMomentum
		local currentVelocity = hrp.AssemblyLinearVelocity
		local dampenedVelocity = currentVelocity * 0.98
		local directionToAnchor = (grappleAnchor - hrp.Position).Unit
		local distanceToAnchor = (grappleAnchor - hrp.Position).Magnitude

		local scaledForce = directionToAnchor * (distanceToAnchor * 2)

		local grounded = checkGround(3)
		if grounded then
			grappleMomentum = Vector3.new(scaledForce.X, 0, scaledForce.Z)
			hrp.AssemblyLinearVelocity =
				Vector3.new(dampenedVelocity.X + grappleMomentum.X, 0, dampenedVelocity.Z + grappleMomentum.Z)
		else
			grappleMomentum = Vector3.new(scaledForce.X, scaledForce.Y, scaledForce.Z)
			hrp.AssemblyLinearVelocity = Vector3.new(
				dampenedVelocity.X + grappleMomentum.X,
				dampenedVelocity.Y + grappleMomentum.Y,
				dampenedVelocity.Z + grappleMomentum.Z
			)
		end

		if distanceToAnchor < 5 then
			StateModule:setState("airborne")
			return
		end
	end)
end

function MovementModule:startGlide()
	local att = Instance.new("Attachment")
	att.Parent = hrp
	att.Name = "GlideAttachment"

	local vf = Instance.new("VectorForce")
	vf.Parent = hrp
	vf.Name = "GlideVF"
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Attachment0 = att

	glideForce = vf
	glideatt = att

	local mass = hrp.AssemblyMass
	local gravity = workspace.Gravity

	glideConnection = RunService.Heartbeat:Connect(function()
		local raw = workspace.CurrentCamera.CFrame.LookVector
		local camera = Vector3.new(raw.X, 0, raw.Z).Unit
		local pitch = raw.Y

		if pitch >= 0.8 then
			StateModule:setState("airborne")
			return
		end

		local rightVec = hrp.CFrame.RightVector
		local bankAmount = rightVec:Dot(hrp.AssemblyLinearVelocity.Unit)
		local bankForce = rightVec * bankAmount * GLIDE_BANK_FORCE
		local thrust_scalar = math.clamp(1 - pitch, 0, 2)

		vf.Force = Vector3.new(
			(camera.X * GLIDE_THRUST * thrust_scalar) + bankForce.X,
			mass * gravity * (1 - GLIDE_GRAVITY_SCALE),
			(camera.Z * GLIDE_THRUST * thrust_scalar) + bankForce.Z
		)
	end)

	GlideModule:start()
end

function MovementModule:startAirborne()
	airborneConnection = RunService.Heartbeat:Connect(function(dt)
		local result = checkGround(3)
		if result ~= nil then
			StateModule:setState("walking")
		end
	end)
end

local function onStateChanged(new, prev)
	if prev == "sliding" then
		MovementModule:endSlide()
	end
	if prev == "wallrunning" then
		MovementModule:endWallRun()
	end
	if prev == "grappling" then
		MovementModule:endGrapple()
	end
	if prev == "gliding" then
		MovementModule:endGlide()
	end
	if prev == "ducking" then
		MovementModule:endDuck()
	end
	if prev == "airborne" then
		MovementModule:endAirborne()
	end

	if new == "walking" then
		MovementModule:startWalking()
	end
	if new == "running" then
		MovementModule:startRunning()
	end
	if new == "sliding" then
		MovementModule:startSlide()
	end
	if new == "ducking" then
		MovementModule:startDuck()
	end
	if new == "dashing" then
		MovementModule:startDash()
	end
	if new == "rolling" then
		MovementModule:startRoll()
	end
	if new == "wallrunning" then
		MovementModule:startWallRun()
	end
	if new == "grappling" then
		MovementModule:startGrapple()
	end
	if new == "gliding" then
		MovementModule:startGlide()
	end
	if new == "airborne" then
		MovementModule:startAirborne()
	end
end

StateModule:AddSubscriber(onStateChanged)

return MovementModule
