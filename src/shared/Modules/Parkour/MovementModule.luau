local MovementModule = {}

local RunService  = game:GetService("RunService")
local Workspace   = game:GetService("Workspace")

local Modules      = script.Parent
local StateModule  = require(Modules:WaitForChild("StateModule"))
local GlideModule  = require(Modules:WaitForChild("GlideModule"))

local character: Model
local hum: Humanoid
local hrp: BasePart

local activeConnections: { [string]: RBXScriptConnection } = {}

local WALK_SPEED          = 16
local RUN_SPEED           = 30
local SLIDE_FORCE         = 60
local SLIDE_DECEL         = 7
local SLIDE_MIN_DURATION  = 0.3
local SLIDE_MAX_DURATION  = 1.2

local DASH_FORCE          = 100
local DASH_WINDUP         = 1
local DASH_DURATION       = 0.18
local DASH_COOLDOWN       = 0.8

local ROLL_FORCE          = 50
local ROLL_DURATION       = 0.25
local ROLL_COOLDOWN       = 0.6

local WALLRUN_SPEED       = 26
local WALLRUN_GRAVITY     = -12
local WALLRUN_LAUNCH_UP   = 18
local WALLRUN_MIN_SPEED   = 8
local WALLRUN_SCAN        = 2.2

local GRAPPLE_FORCE       = 95
local GRAPPLE_MAX_DIST    = 90
local GRAPPLE_MAX_DUR     = 4
local GRAPPLE_ARRIVE_DIST = 5

local GLIDE_GRAVITY_FRAC  = 0.18
local GLIDE_THRUST        = 42
local GLIDE_MAX_FALL      = -14
local GLIDE_BANK          = 18

local GROUND_RAY          = 3.2
local WALL_RAY            = WALLRUN_SCAN
local AIRBORNE_GROUND_GRACE = 0.18
local GLIDE_GROUND_RAY    = 4.2

local canDash  = true
local canRoll  = true

local glideAttachment: Attachment?
local glideForce: VectorForce?
local glideTouchConnections: { RBXScriptConnection } = {}

local slideAttachment: Attachment?
local slideVelocity: LinearVelocity?

local dashFreezeAttachment: Attachment?
local dashFreezeVelocity: LinearVelocity?
local savedJumpPower = 50
local savedJumpHeight = 7.2

local grappleAttachment: Attachment?
local grappleVelocity: LinearVelocity?

local wallSide: string = "none"
local airborneStarted = 0
local defaultHipHeight = 0
local dashSequence = 0

local function disconnect(name: string)
	if activeConnections[name] then
		activeConnections[name]:Disconnect()
		activeConnections[name] = nil
	end
end

local function makeRayParams(): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = { character }
	return p
end

function MovementModule:checkGround(dist: number): RaycastResult?
	return Workspace:Raycast(hrp.Position, Vector3.new(0, -dist, 0), makeRayParams())
end

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

function MovementModule:isGrounded(dist: number?, grace: number?): boolean
	local velY = hrp.AssemblyLinearVelocity.Y
	if velY > 2 then
		return false
	end
	if grace and os.clock() - airborneStarted < grace then
		return false
	end
	return MovementModule:checkGround(dist or GROUND_RAY) ~= nil
end

function MovementModule:checkWall(dist: number): (RaycastResult?, RaycastResult?)
	local params = makeRayParams()
	local l = Workspace:Raycast(hrp.Position, -hrp.CFrame.RightVector * dist, params)
	local r = Workspace:Raycast(hrp.Position,  hrp.CFrame.RightVector * dist, params)
	return l, r
end

function MovementModule:getWallSide(): string
	return wallSide
end

function MovementModule:init(char: Model, humanoid: Humanoid, rootPart: BasePart)
	character = char
	hum       = humanoid
	hrp       = rootPart
	defaultHipHeight = hum.HipHeight
	savedJumpPower = hum.JumpPower
	savedJumpHeight = hum.JumpHeight
end

local function resetHumanoid()
	hum.AutoRotate = true
	hum.PlatformStand = false
	hum.HipHeight = defaultHipHeight
	hum.JumpPower = savedJumpPower
	hum.JumpHeight = savedJumpHeight
end

local function clearSlideMover()
	if slideVelocity then
		slideVelocity:Destroy()
		slideVelocity = nil
	end
	if slideAttachment then
		slideAttachment:Destroy()
		slideAttachment = nil
	end
end

local function clearDashFreeze()
	if dashFreezeVelocity then
		dashFreezeVelocity:Destroy()
		dashFreezeVelocity = nil
	end
	if dashFreezeAttachment then
		dashFreezeAttachment:Destroy()
		dashFreezeAttachment = nil
	end
end

local function freezeDashWindup()
	clearDashFreeze()

	local att = Instance.new("Attachment")
	att.Name = "DashFreezeAttachment"
	att.Parent = hrp

	local lv = Instance.new("LinearVelocity")
	lv.Name = "DashFreezeVelocity"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = hrp.AssemblyMass * 20000
	lv.VectorVelocity = Vector3.zero
	lv.Parent = hrp

	dashFreezeAttachment = att
	dashFreezeVelocity = lv
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

local function clearGrappleMover()
	if grappleVelocity then
		grappleVelocity:Destroy()
		grappleVelocity = nil
	end
	if grappleAttachment then
		grappleAttachment:Destroy()
		grappleAttachment = nil
	end
end

local function clearGlideForce()
	disconnectAll(glideTouchConnections)
	if glideForce then
		glideForce.Force = Vector3.zero
		glideForce:Destroy()
		glideForce = nil
	end
	if glideAttachment then
		glideAttachment:Destroy()
		glideAttachment = nil
	end
end

local function killGlideToWalking()
	disconnect("glide")
	clearGlideForce()
	GlideModule:stop()

	local v = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = Vector3.new(v.X * 0.05, math.min(v.Y, -2), v.Z * 0.05)
	hrp.AssemblyAngularVelocity = Vector3.zero
	hum:ChangeState(Enum.HumanoidStateType.Running)
	StateModule:setState("walking")
end

function MovementModule:startWalking()
	hum.WalkSpeed  = WALK_SPEED
	resetHumanoid()
	GlideModule:stopMovement()
end

function MovementModule:startRunning()
	hum.WalkSpeed  = RUN_SPEED
	resetHumanoid()
	GlideModule:stopMovement("Running")
	GlideModule:play("Running", 0.18, 1.08)
end

function MovementModule:startSlide()
	local startTime = os.clock()
	local flatVel   = hrp.AssemblyLinearVelocity
	local dir       = Vector3.new(flatVel.X, 0, flatVel.Z)

	if dir.Magnitude < 0.5 then
		dir = hum.MoveDirection
	end
	if dir.Magnitude < 0.5 then
		local cam = Workspace.CurrentCamera
		local look = cam and cam.CFrame.LookVector or hrp.CFrame.LookVector
		dir = Vector3.new(look.X, 0, look.Z)
	end

	dir = dir.Unit
	clearSlideMover()
	GlideModule:stopMovement("Slide")
	GlideModule:playStatic("Slide", 0.12)

	local att = Instance.new("Attachment")
	att.Name = "SlideAttachment"
	att.Parent = hrp

	local lv = Instance.new("LinearVelocity")
	lv.Name = "SlideVelocity"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = hrp.AssemblyMass * 20000
	lv.VectorVelocity = Vector3.new(dir.X * SLIDE_FORCE, math.min(hrp.AssemblyLinearVelocity.Y, -2), dir.Z * SLIDE_FORCE)
	lv.Parent = hrp

	slideAttachment = att
	slideVelocity = lv

	hrp.AssemblyLinearVelocity = Vector3.new(dir.X * SLIDE_FORCE, hrp.AssemblyLinearVelocity.Y, dir.Z * SLIDE_FORCE)
	hum.WalkSpeed  = 0
	hum.AutoRotate = false

	activeConnections.slide = RunService.Heartbeat:Connect(function(dt)
		local vel    = hrp.AssemblyLinearVelocity
		local hSpd   = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local elapsed = os.clock() - startTime
		local slideSpeed = math.max(SLIDE_FORCE - SLIDE_DECEL * elapsed, 0)
		if slideVelocity then
			slideVelocity.VectorVelocity = Vector3.new(dir.X * slideSpeed, math.min(vel.Y, -2), dir.Z * slideSpeed)
		end

		if elapsed < SLIDE_MIN_DURATION then return end

		if not MovementModule:isGrounded(GROUND_RAY) then
			disconnect("slide")
			clearSlideMover()
			StateModule:setState("airborne")
			return
		end

		if hSpd <= 4 or elapsed >= SLIDE_MAX_DURATION then
			disconnect("slide")
			clearSlideMover()
			StateModule:setState("walking")
		end
	end)
end

function MovementModule:startDuck()
	GlideModule:stopMovement("Crouch")
	GlideModule:play("Crouch", 0.15, 1)
	hum.WalkSpeed   = WALK_SPEED * 0.5
	hum.HipHeight   = defaultHipHeight - 1
	hum.AutoRotate  = true
end

function MovementModule:startDash()
	if not canDash then
		StateModule:setState(MovementModule:isGrounded(GROUND_RAY) and "walking" or "airborne")
		return
	end
	canDash = false
	dashSequence += 1
	local sequence = dashSequence

	local cam = Workspace.CurrentCamera
	local look = cam and cam.CFrame.LookVector or hrp.CFrame.LookVector
	local dir = Vector3.new(look.X, 0, look.Z)
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	end
	dir = dir.Unit
	hum.AutoRotate = false
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
	freezeDashWindup()
	GlideModule:stopMovement("Dash")

	GlideModule:playDashWindup(function()
		if StateModule:getState() ~= "dashing" or sequence ~= dashSequence then
			return
		end
		clearDashFreeze()
		hrp.AssemblyLinearVelocity = Vector3.new(dir.X * DASH_FORCE, hrp.AssemblyLinearVelocity.Y, dir.Z * DASH_FORCE)
		hrp:ApplyImpulse(Vector3.new(dir.X, 0, dir.Z) * hrp.AssemblyMass * 45)
	end)

	task.delay(DASH_WINDUP + DASH_DURATION, function()
		if StateModule:getState() ~= "dashing" or sequence ~= dashSequence then
			return
		end
		disconnect("dash")
		clearDashFreeze()
		hum.AutoRotate = true
		hum.JumpPower = savedJumpPower
		hum.JumpHeight = savedJumpHeight
		if MovementModule:isGrounded(GROUND_RAY) then
			StateModule:setState("walking")
		else
			StateModule:setState("airborne")
		end
	end)

	task.delay(DASH_COOLDOWN, function()
		canDash = true
	end)
end

function MovementModule:startRoll()
	if not canRoll then
		StateModule:setState(MovementModule:isGrounded(GROUND_RAY) and "walking" or "airborne")
		return
	end
	canRoll = false

	GlideModule:stopMovement("Roll")
	GlideModule:play("Roll", 0.08, 1)
	hum.AutoRotate = false
	local dir = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
	hrp.AssemblyLinearVelocity = Vector3.new(dir.X * ROLL_FORCE, hrp.AssemblyLinearVelocity.Y, dir.Z * ROLL_FORCE)

	task.delay(ROLL_DURATION, function()
		if StateModule:getState() ~= "rolling" then
			return
		end
		disconnect("roll")
		hum.HipHeight  = defaultHipHeight
		hum.AutoRotate = true
		if MovementModule:isGrounded(GROUND_RAY) then
			StateModule:setState("walking")
		else
			StateModule:setState("airborne")
		end
	end)

	task.delay(ROLL_COOLDOWN, function()
		canRoll = true
	end)
end

function MovementModule:startWallRun()
	local leftHit, rightHit = MovementModule:checkWall(WALL_RAY)

	if not leftHit and not rightHit then
		StateModule:setState("airborne")
		return
	end

	local isRight   = rightHit ~= nil
	wallSide        = isRight and "right" or "left"
	GlideModule:stopMovement(isRight and "RightWallrun" or "LeftWallrun")
	GlideModule:play(isRight and "RightWallrun" or "LeftWallrun", 0.12, 1)
	local wallNormal = isRight and rightHit.Normal or leftHit.Normal
	local wallDir    = Vector3.new(-wallNormal.Z, 0, wallNormal.X).Unit

	if isRight then
		wallDir = -wallDir
	end

	local flatVel = hrp.AssemblyLinearVelocity
	if wallDir:Dot(Vector3.new(flatVel.X, 0, flatVel.Z)) < 0 then
		wallDir = -wallDir
	end

	hrp.AssemblyLinearVelocity = Vector3.new(wallDir.X * WALLRUN_SPEED, WALLRUN_LAUNCH_UP, wallDir.Z * WALLRUN_SPEED)
	hum.AutoRotate    = false
	hum.PlatformStand = false

	local startTime = os.clock()

	activeConnections.wallrun = RunService.Heartbeat:Connect(function(dt)
		local lh, rh = MovementModule:checkWall(WALL_RAY + 0.5)

		if (wallSide == "left" and not lh) or (wallSide == "right" and not rh) then
			disconnect("wallrun")
			StateModule:setState("airborne")
			return
		end

		if MovementModule:isGrounded(GROUND_RAY) then
			disconnect("wallrun")
			StateModule:setState("walking")
			return
		end

		local vel  = hrp.AssemblyLinearVelocity
		local hSpd = Vector3.new(vel.X, 0, vel.Z).Magnitude
		if hSpd < WALLRUN_MIN_SPEED and os.clock() - startTime > 0.4 then
			disconnect("wallrun")
			StateModule:setState("airborne")
			return
		end

		local newY = math.max(vel.Y + WALLRUN_GRAVITY * dt, WALLRUN_GRAVITY)
		hrp.AssemblyLinearVelocity = Vector3.new(wallDir.X * WALLRUN_SPEED, newY, wallDir.Z * WALLRUN_SPEED)

		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + wallDir) * CFrame.new(0, 0, 0)
	end)
end

function MovementModule:startGrapple()
	local origin    = hrp.Position
	local cam = Workspace.CurrentCamera
	local look = cam and cam.CFrame.LookVector or hrp.CFrame.LookVector
	local direction = look.Unit * GRAPPLE_MAX_DIST

	local result = Workspace:Raycast(origin, direction, makeRayParams())
	if not result then
		StateModule:setState(MovementModule:isGrounded(GROUND_RAY) and "walking" or "airborne")
		return
	end

	local anchor    = result.Position
	local startTime = os.clock()
	hum.AutoRotate  = false
	GlideModule:stopMovement()
	clearGrappleMover()

	local att = Instance.new("Attachment")
	att.Name = "GrappleAttachment"
	att.Parent = hrp

	local lv = Instance.new("LinearVelocity")
	lv.Name = "GrappleVelocity"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = hrp.AssemblyMass * 12000
	lv.Parent = hrp

	grappleAttachment = att
	grappleVelocity = lv

	local initialPull = (anchor - hrp.Position)
	if initialPull.Magnitude > 0.01 then
		hrp:ApplyImpulse(initialPull.Unit * hrp.AssemblyMass * 80)
	end

	activeConnections.grapple = RunService.Heartbeat:Connect(function(dt)
		local toAnchor = anchor - hrp.Position
		local dist     = toAnchor.Magnitude

		if dist < GRAPPLE_ARRIVE_DIST or os.clock() - startTime > GRAPPLE_MAX_DUR then
			disconnect("grapple")
			clearGrappleMover()
			StateModule:setState("airborne")
			return
		end

		local pullStrength = math.clamp(dist * 2.6, 45, GRAPPLE_FORCE)
		local desired = toAnchor.Unit * pullStrength + Vector3.new(0, 14, 0)
		if grappleVelocity then
			grappleVelocity.VectorVelocity = desired
		end
		hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity:Lerp(desired, math.min(12 * dt, 1))
	end)
end

function MovementModule:startGlide()
	local att = Instance.new("Attachment")
	att.Name  = "GlideAtt"
	att.Parent = hrp

	local vf            = Instance.new("VectorForce")
	vf.Name             = "GlideForce"
	vf.RelativeTo       = Enum.ActuatorRelativeTo.World
	vf.Attachment0      = att
	vf.Parent           = hrp

	glideAttachment = att
	glideForce      = vf
	disconnectAll(glideTouchConnections)

	local function onTouched(hit: BasePart)
		if not hit or hit:IsDescendantOf(character) then
			return
		end
		if StateModule:getState() == "gliding" then
			killGlideToWalking()
		end
	end

	table.insert(glideTouchConnections, hrp.Touched:Connect(onTouched))
	local torso = character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		table.insert(glideTouchConnections, torso.Touched:Connect(onTouched))
	end
	for _, limbName in ipairs({ "Left Leg", "Right Leg" }) do
		local limb = character:FindFirstChild(limbName)
		if limb and limb:IsA("BasePart") then
			table.insert(glideTouchConnections, limb.Touched:Connect(onTouched))
		end
	end

	local mass    = hrp.AssemblyMass
	local gravity = Workspace.Gravity

	local glideStartVel = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = Vector3.new(glideStartVel.X, math.min(glideStartVel.Y, 0), glideStartVel.Z)

	activeConnections.glide = RunService.Heartbeat:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		local camLook = cam and cam.CFrame.LookVector or hrp.CFrame.LookVector
		local pitch     = camLook.Y

		if pitch > 0.75 then
			disconnect("glide")
			StateModule:setState("airborne")
			return
		end

		local grounded = MovementModule:checkGround(GLIDE_GROUND_RAY) ~= nil or hum.FloorMaterial ~= Enum.Material.Air
		if grounded then
			killGlideToWalking()
			return
		end

		local vel    = hrp.AssemblyLinearVelocity
		local clampedY = math.max(vel.Y, GLIDE_MAX_FALL)
		if vel.Y < clampedY then
			hrp.AssemblyLinearVelocity = Vector3.new(vel.X, clampedY, vel.Z)
		end

		local forward     = Vector3.new(camLook.X, 0, camLook.Z)
		if forward.Magnitude < 0.01 then
			forward = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		end
		forward = forward.Unit
		local thrustScale = math.clamp(1 - pitch, 0.1, 1.8)
		local right       = hrp.CFrame.RightVector
		local velDir = vel.Magnitude > 0.1 and vel.Unit or forward
		local bank        = right:Dot(velDir) * GLIDE_BANK

		vf.Force = Vector3.new(
			(forward.X * GLIDE_THRUST * thrustScale + bank) * mass,
			mass * gravity * (1 - GLIDE_GRAVITY_FRAC),
			forward.Z * GLIDE_THRUST * thrustScale * mass
		)
	end)

	GlideModule:start()
end

function MovementModule:startAirborne()
	airborneStarted = os.clock()
	GlideModule:stopMovement("Airborne")
	GlideModule:play("Airborne", 0.15, 1)
	activeConnections.airborne = RunService.Heartbeat:Connect(function(dt)
		if MovementModule:isGrounded(GROUND_RAY, AIRBORNE_GROUND_GRACE) then
			disconnect("airborne")
			local vel = hrp.AssemblyLinearVelocity
			local hSpd = Vector3.new(vel.X, 0, vel.Z).Magnitude
			if hSpd > RUN_SPEED * 0.6 then
				StateModule:setState("running")
			else
				StateModule:setState("walking")
			end
		end

		local lh, rh = MovementModule:checkWall(WALL_RAY)
		if lh or rh then
			local vel    = hrp.AssemblyLinearVelocity
			local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			if hSpeed > WALLRUN_MIN_SPEED and vel.Y < 5 then
				disconnect("airborne")
				StateModule:setState("wallrunning")
			end
		end
	end)
end

function MovementModule:forceStopGlide()
	if StateModule:getState() == "gliding" then
		killGlideToWalking()
	end
end

local function onStateChanged(newState: string, prevState: string?)
	if not hum or not hrp then
		return
	end

	if prevState == "sliding"    then disconnect("slide") ; clearSlideMover() ; GlideModule:stopTrack("Slide", 0.12) ; hum.AutoRotate = true end
	if prevState == "wallrunning" then disconnect("wallrun") ; hum.AutoRotate = true ; hum.PlatformStand = false ; wallSide = "none" end
	if prevState == "grappling"  then disconnect("grapple") ; clearGrappleMover() ; hum.AutoRotate = true end
	if prevState == "airborne"   then disconnect("airborne") end
	if prevState == "dashing"    then disconnect("dash") ; dashSequence += 1 ; clearDashFreeze() ; GlideModule:stopTrack("Dash", 0.12) ; hum.AutoRotate = true ; hum.JumpPower = savedJumpPower ; hum.JumpHeight = savedJumpHeight end
	if prevState == "rolling"    then disconnect("roll") ; GlideModule:stopTrack("Roll", 0.12) ; hum.HipHeight = defaultHipHeight ; hum.AutoRotate = true end
	if prevState == "ducking"    then GlideModule:stopTrack("Crouch", 0.12) ; hum.HipHeight = defaultHipHeight end
	if prevState == "running"    then GlideModule:stopTrack("Running", 0.12) end
	if prevState == "wallrunning" then GlideModule:stopTrack("LeftWallrun", 0.12) ; GlideModule:stopTrack("RightWallrun", 0.12) end
	if prevState == "airborne"   then GlideModule:stopTrack("Airborne", 0.12) end

	if prevState == "gliding" then
		disconnect("glide")
		clearGlideForce()
		GlideModule:stop()
	end

	if newState == "walking"     then MovementModule:startWalking()    end
	if newState == "running"     then MovementModule:startRunning()    end
	if newState == "sliding"     then MovementModule:startSlide()      end
	if newState == "ducking"     then MovementModule:startDuck()       end
	if newState == "dashing"     then MovementModule:startDash()       end
	if newState == "rolling"     then MovementModule:startRoll()       end
	if newState == "wallrunning" then MovementModule:startWallRun()    end
	if newState == "grappling"   then MovementModule:startGrapple()    end
	if newState == "gliding"     then MovementModule:startGlide()      end
	if newState == "airborne"    then MovementModule:startAirborne()   end
end

StateModule:AddSubscriber(onStateChanged)

return MovementModule
