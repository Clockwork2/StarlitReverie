--// CameraModule.lua \\--
local CameraModule = {}

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Modules = script.Parent
local SpringModule = require(Modules:WaitForChild("SpringModule"))
local StateModule = require(Modules:WaitForChild("StateModule"))

local camera = workspace.CurrentCamera

local character, hum, hrp
local isFirstPerson = false
local viewTransitioning = false

-- Camera offsets
local TP_DISTANCE = 18
local TP_HEIGHT = 4
local TP_OFFSET_SIDE = 2
local TRANSITION_SPEED = 8
local FP_FOV = 70
local TP_FOV = 70

-- FP procedural motion settings
local BOB_SPEED_WALK = 6
local BOB_SPEED_RUN = 10
local BOB_AMOUNT_WALK = 0.05
local BOB_AMOUNT_RUN = 0.12

local TILT_STRAFE = 0.08
local TILT_SLIDE = 0.2
local TILT_WALLRUN = 0.15
local LEAN_AMOUNT = 0.06
local LAND_AMOUNT = 0.4
local SWAY_AMOUNT = 0.05
local SWAY_GRAPPLE = 0.15
local BREATHE_SPEED = 1.2
local BREATHE_AMOUNT = 0.02

local DASH_FOV = 90
local GLIDE_FOV = 85
local ROLL_FOV = 80
local FOV_TRANSITION_SPEED = 5

local HEAD_OFFSET = Vector3.new(0, 2.5, 0)

-- Springs
local bobSpring = SpringModule.new(120, 10)
local tiltSpring = SpringModule.new(150, 12)
local leanSpring = SpringModule.new(130, 11)
local landSpring = SpringModule.new(180, 14)
local swaySpring = SpringModule.new(100, 10)
local rollSpring = SpringModule.new(200, 15)

local lastVelocity = Vector3.zero
local justLanded = false
local currentBank = 0

-- Time accumulator for bob (replaces blocking task.wait)
local bobTime = 0

function CameraModule:init(char, humanoid, rootPart)
	character = char
	hum = humanoid
	hrp = rootPart
end

function CameraModule:start()
	camera.CameraType = Enum.CameraType.Scriptable

	-- Initialize FOV
	camera.FieldOfView = TP_FOV

	RunService:BindToRenderStep("CameraUpdate", Enum.RenderPriority.Camera.Value, function(dt)
		bobTime += dt

		if not isFirstPerson then
			self:updateThirdPerson(dt)
		else
			self:updateFirstPerson(dt)
		end

		self:updateFOV(dt)
	end)
end

function CameraModule:updateFOV(dt)
	local state = StateModule:getState()
	local targetFOV = TP_FOV

	if state == StateModule.States.DASHING then
		targetFOV = DASH_FOV
	elseif state == StateModule.States.GLIDING then
		targetFOV = GLIDE_FOV
	elseif state == StateModule.States.ROLLING then
		targetFOV = ROLL_FOV
	end

	local currentFOV = camera.FieldOfView
	local newFOV = currentFOV + (targetFOV - currentFOV) * FOV_TRANSITION_SPEED * dt
	camera.FieldOfView = newFOV
end

function CameraModule:updateThirdPerson(dt)
	local state = StateModule:getState()

	-- Dynamic configuration based on state
	local distance = TP_DISTANCE
	local height = TP_HEIGHT
	local sideOffset = TP_OFFSET_SIDE

	if state == StateModule.States.SLIDING then
		distance = TP_DISTANCE + 4
		height = TP_HEIGHT - 2
	elseif state == StateModule.States.GLIDING then
		distance = TP_DISTANCE + 8
		height = TP_HEIGHT + 2
	elseif state == StateModule.States.GRAPPLING then
		distance = TP_DISTANCE + 6
	elseif state == StateModule.States.WALLRUNNING then
		distance = TP_DISTANCE + 2
	end

	local rootCF = hrp.CFrame
	local playerPos = rootCF.Position

	-- Calculate bank based on velocity
	local velocity = hrp.AssemblyLinearVelocity
	local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)

	if horizontalVel.Magnitude > 1 then
		local velRight = rootCF.RightVector:Dot(horizontalVel.Unit)
		currentBank = rollSpring:Update(-velRight * 0.1, dt)
	else
		currentBank = rollSpring:Update(0, dt)
	end

	-- Camera position with state-based offsets
	local cameraPos = (playerPos - rootCF.LookVector * distance)
		+ Vector3.new(0, height, 0)
		+ rootCF.RightVector * sideOffset

	local lookTarget = rootCF.Position + Vector3.new(0, 3, 0)

	-- Apply bank rotation
	local targetCF = CFrame.lookAt(cameraPos, lookTarget) * CFrame.Angles(0, 0, currentBank)

	camera.CFrame = camera.CFrame:Lerp(targetCF, dt * TRANSITION_SPEED)
end

function CameraModule:updateFirstPerson(dt)
	local state = StateModule:getState()
	local velocity = hrp.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	local headPos = hrp.Position + HEAD_OFFSET
	local baseCF = CFrame.new(headPos) * camera.CFrame.Rotation

	-- Head bob - using time accumulator instead of task.wait
	local bobTarget = 0
	if state == StateModule.States.RUNNING then
		bobTarget = math.sin(bobTime * BOB_SPEED_RUN) * BOB_AMOUNT_RUN
	elseif state == StateModule.States.WALKING and speed > 0.5 then
		bobTarget = math.sin(bobTime * BOB_SPEED_WALK) * BOB_AMOUNT_WALK
	elseif speed <= 0.5 then
		bobTarget = math.sin(bobTime * BREATHE_SPEED) * BREATHE_AMOUNT
	end
	local bob = bobSpring:Update(bobTarget, dt)

	-- Strafe/slide tilt
	local tiltTarget = 0
	local left = UserInputService:IsKeyDown(Enum.KeyCode.A)
	local right = UserInputService:IsKeyDown(Enum.KeyCode.D)

	if left and not right then
		tiltTarget = TILT_STRAFE
	elseif right and not left then
		tiltTarget = -TILT_STRAFE
	end

	if state == StateModule.States.SLIDING then
		tiltTarget = TILT_SLIDE
	elseif state == StateModule.States.WALLRUNNING then
		-- Use MovementModule to check which wall
		local Modules = script.Parent
		local MovementModule = Modules:FindFirstChild("MovementModule")
		if MovementModule then
			MovementModule = require(MovementModule)
			local leftWall, rightWall = MovementModule:checkWall(5)
			if leftWall then
				tiltTarget = TILT_WALLRUN
			elseif rightWall then
				tiltTarget = -TILT_WALLRUN
			end
		end
	end

	local tilt = tiltSpring:Update(tiltTarget, dt)

	-- Speed lean based on acceleration
	local leanTarget = 0
	local accel = (velocity - lastVelocity) / dt
	local dot = accel:Dot(camera.CFrame.LookVector)

	if dot > 10 then
		leanTarget = -LEAN_AMOUNT
	elseif dot < -10 then
		leanTarget = LEAN_AMOUNT
	end

	local lean = leanSpring:Update(leanTarget, dt)
	lastVelocity = velocity

	-- Landing dip
	local landTarget = 0
	if justLanded then
		landTarget = -LAND_AMOUNT
		justLanded = false
	end
	local land = landSpring:Update(landTarget, dt)

	-- Grapple/glide sway
	local swayTarget = 0
	if state == StateModule.States.GRAPPLING then
		local perp = velocity - camera.CFrame.LookVector * velocity:Dot(camera.CFrame.LookVector)
		swayTarget = perp.X * SWAY_GRAPPLE
	elseif state == StateModule.States.GLIDING then
		-- Wind sway using Perlin noise
		swayTarget = math.noise(bobTime * 0.5, 0) * SWAY_AMOUNT
	end

	local sway = swaySpring:Update(swayTarget, dt)

	-- Combine all procedural motion
	local finalCF = baseCF * CFrame.new(sway, bob + land, 0) * CFrame.Angles(lean, 0, tilt)

	camera.CFrame = finalCF
end

function CameraModule:toggleView()
	if viewTransitioning then
		return
	end

	viewTransitioning = true

	local targetPosition
	local targetFOV
	local duration = 0.5

	if isFirstPerson then
		-- Currently FP, going to TP
		targetPosition = hrp.Position + (-hrp.CFrame.LookVector * TP_DISTANCE) + Vector3.new(0, TP_HEIGHT, 0)
		targetFOV = TP_FOV
		isFirstPerson = false

		-- Show cape
		task.spawn(function()
			local CapeModule = require(Modules:WaitForChild("CapeModule"))
			CapeModule:show()
		end)
	else
		-- Currently TP, going to FP
		targetPosition = hrp.Position + HEAD_OFFSET
		targetFOV = FP_FOV
		isFirstPerson = true

		-- Hide cape
		task.spawn(function()
			local CapeModule = require(Modules:WaitForChild("CapeModule"))
			CapeModule:hide()
		end)
	end

	-- Smooth FOV transition
	local fovTween = TweenService:Create(camera, TweenInfo.new(duration, Enum.EasingStyle.Quad), {
		FieldOfView = targetFOV,
	})
	fovTween:Play()

	-- Lerp to new view position
	local startCF = camera.CFrame
	local startTime = os.clock()

	task.spawn(function()
		while viewTransitioning and os.clock() - startTime < duration do
			local t = (os.clock() - startTime) / duration
			t = math.clamp(t, 0, 1)
			t = 1 - (1 - t) * (1 - t) -- Ease out quad

			task.wait()
		end
		viewTransitioning = false
	end)
end

-- State change handler - subscribe to StateModule
local function onStateChanged(newState, prevState)
	-- Landing detection
	if
		prevState == StateModule.States.AIRBORNE
		or prevState == StateModule.States.GLIDING
		or prevState == StateModule.States.WALLRUNNING
	then
		if newState == StateModule.States.WALKING or newState == StateModule.States.RUNNING then
			justLanded = true
		end
	end

	-- Reset springs on state change to avoid snapping
	if newState == StateModule.States.SLIDING then
		tiltSpring:Reset()
	end
	if newState == StateModule.States.GLIDING then
		bobSpring:Reset()
	end
end

-- Subscribe to state changes
StateModule:AddSubscriber(onStateChanged)

return CameraModule
