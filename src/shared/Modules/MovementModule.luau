--// MovementModule.lua \\--
local MovementModule = {}

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = script.Parent
local StateModule = require(Modules:WaitForChild("StateModule"))
local GlideModule = require(Modules:WaitForChild("GlideModule"))

local character, hum, hrp

-- Active state connections
local activeConnections = {}

-- Constants
local WALK_SPEED = 16
local RUN_SPEED = 24
local SLIDE_FORCE = 80
local SLIDE_DECEL = 15
local SLIDE_MIN_DURATION = 0.3

local DASH_FORCE = 120
local DASH_DURATION = 0.2
local DASH_COOLDOWN = 0.8
local CAN_DASH = true

local ROLL_FORCE = 60
local ROLL_DURATION = 0.25
local ROLL_COOLDOWN = 0.6
local CAN_ROLL = true

local WALLRUN_SPEED = 28
local WALLRUN_GRAVITY_SCALE = 0.1
local WALLRUN_MIN_DURATION = 0.4

local GRAPPLE_FORCE = 60
local GRAPPLE_MAX_DIST = 50
local GRAPPLE_MAX_DURATION = 4

local GLIDE_GRAVITY_SCALE = 0.15
local GLIDE_THRUST = 40
local GLIDE_BANK_FORCE = 20

-- Cape/force instances
local glideAttachment, glideVectorForce

function MovementModule:init(char, humanoid, rootPart)
	character = char
	hum = humanoid
	hrp = rootPart
end

-- Ground check
function MovementModule:checkGround(distance: number)
	local origin = hrp.Position
	local direction = Vector3.new(0, -distance, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local result = workspace:Raycast(origin, direction, params)
	return result
end

-- Wall detection
function MovementModule:checkWall(scanDistance: number)
	local origin = hrp.Position
	local leftDir = -hrp.CFrame.RightVector * scanDistance
	local rightDir = hrp.CFrame.RightVector * scanDistance

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local leftHit = workspace:Raycast(origin, leftDir, params)
	local rightHit = workspace:Raycast(origin, rightDir, params)

	return leftHit, rightHit
end

-- Cleanup helper
local function disconnect(name: string)
	if activeConnections[name] then
		activeConnections[name]:Disconnect()
		activeConnections[name] = nil
	end
end

local function cleanupAll()
	for name, conn in pairs(activeConnections) do
		conn:Disconnect()
	end
	table.clear(activeConnections)
end

-- State entry/exit handlers
function MovementModule:startWalking()
	hum.WalkSpeed = WALK_SPEED
	hum.AutoRotate = true
end

function MovementModule:startRunning()
	hum.WalkSpeed = RUN_SPEED
	hum.AutoRotate = true
end

--// MovementModule.lua (continued) \\--

function MovementModule:startSlide()
	local startTime = os.clock()
	local direction = hrp.AssemblyLinearVelocity.Unit

	-- Apply slide impulse
	if direction.Magnitude > 0.1 then
		hrp.AssemblyLinearVelocity = direction * SLIDE_FORCE
	else
		hrp.AssemblyLinearVelocity = hrp.CFrame.LookVector * SLIDE_FORCE
	end

	hum.WalkSpeed = 0
	hum.AutoRotate = false

	-- Slide physics loop
	activeConnections.slide = RunService.Heartbeat:Connect(function(dt)
		local vel = hrp.AssemblyLinearVelocity
		local newVel = vel * (1 - SLIDE_DECEL * dt)
		hrp.AssemblyLinearVelocity = newVel

		-- Minimum duration check
		if os.clock() - startTime < SLIDE_MIN_DURATION then
			return
		end

		-- Stop if slow enough
		if newVel.Magnitude <= 2 then
			disconnect("slide")
			StateModule:setState(StateModule.States.WALKING)
		end

		-- Fall off edge
		if not MovementModule:checkGround(3) then
			disconnect("slide")
			StateModule:setState(StateModule.States.AIRBORNE)
		end
	end)
end

function MovementModule:startDuck()
	hum.WalkSpeed = WALK_SPEED * 0.5
	hum.HipHeight = -1
end

function MovementModule:startDash()
	if not CAN_DASH then
		return
	end
	CAN_DASH = false

	local direction = hrp.CFrame.LookVector
	hrp.AssemblyLinearVelocity =
		Vector3.new(direction.X * DASH_FORCE, hrp.AssemblyLinearVelocity.Y, direction.Z * DASH_FORCE)
	hum.AutoRotate = false

	activeConnections.dash = RunService.Heartbeat:Connect(function(dt)
		if not MovementModule:checkGround(3) then
			StateModule:setState(StateModule.States.AIRBORNE)
			disconnect("dash")
		end
	end)

	-- Cooldown
	task.delay(DASH_COOLDOWN, function()
		CAN_DASH = true
	end)

	-- End dash
	task.delay(DASH_DURATION, function()
		disconnect("dash")
		hum.AutoRotate = true

		if MovementModule:checkGround(3) then
			StateModule:setState(StateModule.States.WALKING)
		else
			StateModule:setState(StateModule.States.AIRBORNE)
		end
	end)
end

function MovementModule:startRoll()
	if not CAN_ROLL or hum.HipHeight < 0 then
		return
	end
	CAN_ROLL = false

	hum.AutoRotate = false
	hum.HipHeight = -0.5
	hrp.AssemblyLinearVelocity = hrp.CFrame.LookVector * ROLL_FORCE

	activeConnections.roll = RunService.Heartbeat:Connect(function(dt)
		if not MovementModule:checkGround(3) then
			StateModule:setState(StateModule.States.AIRBORNE)
			disconnect("roll")
		end
	end)

	task.delay(ROLL_COOLDOWN, function()
		CAN_ROLL = true
	end)

	task.delay(ROLL_DURATION, function()
		disconnect("roll")
		hum.HipHeight = 0
		hum.AutoRotate = true

		if MovementModule:checkGround(3) then
			StateModule:setState(StateModule.States.WALKING)
		else
			StateModule:setState(StateModule.States.AIRBORNE)
		end
	end)
end

function MovementModule:startWallRun()
	local leftHit, rightHit = MovementModule:checkWall(5)

	if not leftHit and not rightHit then
		warn("[MovementModule] No wall found for wallrun")
		return
	end

	local wallNormal = rightHit and rightHit.Normal or leftHit.Normal
	hum.WalkSpeed = WALLRUN_SPEED
	hum.AutoRotate = false
	hum.Rotation = CFrame.Angles(0, 0, 0)

	local startTime = os.clock()

	activeConnections.wallrun = RunService.Heartbeat:Connect(function(dt)
		-- Reduced gravity
		local vel = hrp.AssemblyLinearVelocity
		local newY = math.max(vel.Y * WALLRUN_GRAVITY_SCALE, -5)
		hrp.AssemblyLinearVelocity = Vector3.new(vel.X, newY, vel.Z)

		-- Wall still there?
		local leftHit, rightHit = MovementModule:checkWall(5)
		if not leftHit and not rightHit then
			StateModule:setState(StateModule.States.AIRBORNE)
			disconnect("wallrun")
			return
		end

		-- Minimum duration
		if os.clock() - startTime < WALLRUN_MIN_DURATION then
			return
		end

		-- Hit ground?
		if MovementModule:checkGround(3) then
			StateModule:setState(StateModule.States.WALKING)
			disconnect("wallrun")
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
		warn("[MovementModule] No grapple point found")
		return
	end

	local anchor = result.Position
	local startTime = os.clock()
	hum.AutoRotate = false

	activeConnections.grapple = RunService.Heartbeat:Connect(function(dt)
		local toAnchor = (anchor - hrp.Position)
		local distance = toAnchor.Magnitude
		local dir = toAnchor.Unit

		-- Apply force toward anchor
		local scaledForce = dir * (distance * 2)
		local vel = hrp.AssemblyLinearVelocity * 0.98

		hrp.AssemblyLinearVelocity = Vector3.new(vel.X + scaledForce.X, vel.Y + scaledForce.Y, vel.Z + scaledForce.Z)

		-- Max duration or close enough
		if distance < 5 or os.clock() - startTime > GRAPPLE_MAX_DURATION then
			StateModule:setState(StateModule.States.AIRBORNE)
			disconnect("grapple")
		end
	end)
end

function MovementModule:startGlide()
	-- Create force attachment
	local att = Instance.new("Attachment")
	att.Name = "GlideAttachment"
	att.Parent = hrp

	local vf = Instance.new("VectorForce")
	vf.Name = "GlideVectorForce"
	vf.Parent = hrp
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Attachment0 = att

	glideAttachment = att
	glideVectorForce = vf

	local mass = hrp.AssemblyMass
	local gravity = workspace.Gravity

	activeConnections.glide = RunService.Heartbeat:Connect(function(dt)
		local camLook = workspace.CurrentCamera.CFrame.LookVector
		local forward = Vector3.new(camLook.X, 0, camLook.Z).Unit
		local pitch = camLook.Y

		-- Too steep?
		if pitch >= 0.8 then
			StateModule:setState(StateModule.States.AIRBORNE)
			disconnect("glide")
			return
		end

		-- Bank into velocity
		local right = hrp.CFrame.RightVector
		local velDir = hrp.AssemblyLinearVelocity.Unit
		local bank = right:Dot(velDir) * GLIDE_BANK_FORCE

		local thrustScale = math.clamp(1 - pitch, 0, 2)

		vf.Force = Vector3.new(
			forward.X * GLIDE_THRUST * thrustScale + bank,
			mass * gravity * (1 - GLIDE_GRAVITY_SCALE),
			forward.Z * GLIDE_THRUST * thrustScale
		)

		-- Landed?
		if MovementModule:checkGround(3) then
			StateModule:setState(StateModule.States.WALKING)
			disconnect("glide")
		end
	end)

	GlideModule:start()
end

function MovementModule:startAirborne()
	activeConnections.airborne = RunService.Heartbeat:Connect(function(dt)
		if MovementModule:checkGround(3) then
			StateModule:setState(StateModule.States.WALKING)
			disconnect("airborne")
		end
	end)
end

-- FSM state change handler
local function onStateChanged(newState, prevState)
	-- Cleanup previous state
	if prevState == StateModule.States.SLIDING then
		disconnect("slide")
	end
	if prevState == StateModule.States.DASHING then
		disconnect("dash")
	end
	if prevState == StateModule.States.ROLLING then
		disconnect("roll")
	end
	if prevState == StateModule.States.WALLRUNNING then
		disconnect("wallrun")
	end
	if prevState == StateModule.States.GRAPPLING then
		disconnect("grapple")
	end
	if prevState == StateModule.States.GLIDING then
		disconnect("glide")
		-- Cleanup force instances
		if glideVectorForce then
			glideVectorForce:Destroy()
			glideVectorForce = nil
		end
		if glideAttachment then
			glideAttachment:Destroy()
			glideAttachment = nil
		end
		GlideModule:stop()
	end
	if prevState == StateModule.States.AIRBORNE then
		disconnect("airborne")
	end
	if prevState == StateModule.States.DUCKING then
		hum.HipHeight = 0
	end

	-- Enter new state
	if newState == StateModule.States.WALKING then
		MovementModule:startWalking()
	end
	if newState == StateModule.States.RUNNING then
		MovementModule:startRunning()
	end
	if newState == StateModule.States.SLIDING then
		MovementModule:startSlide()
	end
	if newState == StateModule.States.DUCKING then
		MovementModule:startDuck()
	end
	if newState == StateModule.States.DASHING then
		MovementModule:startDash()
	end
	if newState == StateModule.States.ROLLING then
		MovementModule:startRoll()
	end
	if newState == StateModule.States.WALLRUNNING then
		MovementModule:startWallRun()
	end
	if newState == StateModule.States.GRAPPLING then
		MovementModule:startGrapple()
	end
	if newState == StateModule.States.GLIDING then
		MovementModule:startGlide()
	end
	if newState == StateModule.States.AIRBORNE then
		MovementModule:startAirborne()
	end
end

StateModule:AddSubscriber(onStateChanged)

return MovementModule
