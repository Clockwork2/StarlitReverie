local CameraModule = {}

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Modules = script.Parent
local SpringModule = require(Modules:WaitForChild("SpringModule"))
local StateModule = require(Modules:WaitForChild("StateModule"))
local MovementModule = require(Modules:WaitForChild("MovementModule"))

local camera = workspace.CurrentCamera

local character
local hum
local hrp

local isFP = false
local lastVelocity = Vector3.zero
local justLanded = false
local TP_DISTANCE = 18
local TP_HEIGHT = 4
local TP_OFFSET_SIDE = 2
local TRANSITION_SPEED = 10
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
local SPRING_BOB = { 120, 10 }
local SPRING_TILT = { 150, 12 }
local SPRING_LEAN = { 130, 11 }
local SPRING_LAND = { 180, 14 }
local SPRING_SWAY = { 100, 10 }
local HEAD_OFFSET = Vector3.new(0, 2.5, 0)

local bobSpring = SpringModule.new(SPRING_BOB[1], SPRING_BOB[2])
local tiltSpring = SpringModule.new(SPRING_TILT[1], SPRING_TILT[2])
local leanSpring = SpringModule.new(SPRING_LEAN[1], SPRING_LEAN[2])
local landSpring = SpringModule.new(SPRING_LAND[1], SPRING_LAND[2])
local swaySpring = SpringModule.new(SPRING_SWAY[1], SPRING_SWAY[2])

local currentState = StateModule:getState()

function CameraModule:init(char, humanoid, rootPart)
	character = char
	hum = humanoid
	hrp = rootPart
end

function CameraModule:start()
	camera.CameraType = Enum.CameraType.Scriptable

	RunService:BindToRenderStep("CameraUpdate", Enum.RenderPriority.Camera.Value, function(dt)
		if not isFP then
			local distance = TP_DISTANCE
			local height = TP_HEIGHT

			if currentState == "sliding" then
				distance = TP_DISTANCE + 4
				height = TP_HEIGHT - 2
			elseif currentState == "gliding" then
				distance = TP_DISTANCE + 8
				height = TP_HEIGHT + 2
			elseif currentState == "grappling" then
				distance = TP_DISTANCE + 6
			elseif currentState == "wallrunning" then
				distance = TP_DISTANCE + 2
			end

			local current = camera.CFrame
			local rootCF = hrp.CFrame
			local playerPos = rootCF.Position

			local cameraPos = (playerPos - rootCF.LookVector * distance)
				+ Vector3.new(0, height, 0)
				+ rootCF.RightVector * TP_OFFSET_SIDE

			local lookTarget = rootCF.Position + Vector3.new(0, 3, 0)

			local targetCf = CFrame.lookAt(cameraPos, lookTarget)

			camera.CFrame = current:Lerp(targetCf, dt * TRANSITION_SPEED)
		else
			local bobTarget
			local tiltTarget
			local leanTarget
			local landTarget
			local swayTarget

			local velocity = hrp.AssemblyLinearVelocity
			local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
			local speed = horizontalVelocity.Magnitude

			local headPosition = hrp.Position + HEAD_OFFSET

			local baseCF = CFrame.new(headPosition) * camera.CFrame.Rotation

			if currentState == "running" then
				bobTarget = math.sin(tick() * BOB_SPEED_RUN) * BOB_AMOUNT_RUN
			elseif currentState == "walking" and speed > 0.5 then
				bobTarget = math.sin(tick() * BOB_SPEED_WALK) * BOB_AMOUNT_WALK
			elseif currentState == "walking" and speed < 0.5 then
				bobTarget = math.sin(tick() * BREATHE_SPEED) * BREATHE_AMOUNT
			else
				bobTarget = 0
			end

			local bob = bobSpring:Update(bobTarget, dt)

			local left = UserInputService:IsKeyDown(Enum.KeyCode.A)
			local right = UserInputService:IsKeyDown(Enum.KeyCode.D)

			if left and not right then
				tiltTarget = TILT_STRAFE
			elseif right and not left then
				tiltTarget = -TILT_STRAFE
			else
				tiltTarget = 0
			end

			if currentState == "sliding" then
				tiltTarget = TILT_SLIDE
			elseif currentState == "wallrunning" then
				local leftResult, rightResult = MovementModule:checkWall()

				if leftResult then
					tiltTarget = TILT_WALLRUN
				elseif rightResult then
					tiltTarget = -TILT_WALLRUN
				end
			end

			local tilt = tiltSpring:Update(tiltTarget, dt)

			local acceleration = (hrp.AssemblyLinearVelocity - lastVelocity) / dt
			local dot = acceleration:Dot(camera.CFrame.LookVector)

			if dot > 0 then
				leanTarget = -LEAN_AMOUNT
			elseif dot < 0 then
				leanTarget = LEAN_AMOUNT
			else
				leanTarget = 0
			end

			local lean = leanSpring:Update(leanTarget, dt)
			lastVelocity = hrp.AssemblyLinearVelocity

			if justLanded then
				landTarget = -LAND_AMOUNT
				justLanded = false
			else
				landTarget = 0
			end

			local land = landSpring:Update(landTarget, dt)

			if currentState == "grappling" then
				local swayVelocity = hrp.AssemblyLinearVelocity
				local swayLookVector = camera.CFrame.LookVector
				local forwardVelocity = swayLookVector * swayVelocity:Dot(swayLookVector)
				local perpendicularVelocity = swayVelocity - forwardVelocity

				swayTarget = perpendicularVelocity.X * SWAY_GRAPPLE
			elseif currentState == "gliding" then
				swayTarget = math.noise(tick() * 0.5) * SWAY_AMOUNT
			else
				swayTarget = 0
			end

			local sway = swaySpring:Update(swayTarget, dt)

			local finalCF = baseCF * CFrame.new(sway, bob + land, 0) * CFrame.Angles(lean, 0, tilt)
			camera.CFrame = finalCF
		end
	end)
end

function CameraModule:toggleView()
	isFP = not isFP
end

local function onStateChanged(newState, previousState)
	currentState = newState

	if previousState == "airborne" and newState == "walking" then
		justLanded = true
	end

	if newState == "rolling" or newState == "dashing" then
		justLanded = true
	end
end

StateModule:AddSubscriber(onStateChanged)

return CameraModule
