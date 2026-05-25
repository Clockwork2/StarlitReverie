local CameraModule = {}

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Modules = script.Parent.Parent
local Camera = script.Parent
local parkour = Modules:WaitForChild("Parkour")
local SpringModule = require(Camera:WaitForChild("SpringModule"))
local StateModule = require(parkour:WaitForChild("StateModule"))

local camera = workspace.CurrentCamera

local character: Model
local hum: Humanoid
local hrp: BasePart

local isFirstPerson = false
local viewTransitioning = false
local cursorFree = false
local started = false
local inputConnection: RBXScriptConnection?
local inputBeganConnection: RBXScriptConnection?
local inputEndedConnection: RBXScriptConnection?
local accessoryConnection: RBXScriptConnection?

local TP_DISTANCE = 16
local TP_HEIGHT = 4.5
local TP_SIDE = 1.8
local TP_LERP = 10
local FP_FOV = 72
local TP_FOV = 68
local RUN_FOV = 78
local DASH_FOV = 88
local GLIDE_FOV = 82
local ROLL_FOV = 78
local FOV_LERP = 6

local HEAD_OFFSET = Vector3.new(0, 1.5, 0.1)

local BOB_SPEED_WALK = 6
local BOB_SPEED_RUN = 11
local BOB_AMT_WALK = 0.045
local BOB_AMT_RUN = 0.11
local BREATHE_SPEED = 0.85
local BREATHE_AMT = 0.006

local TILT_STRAFE = 0.07
local TILT_SLIDE = 0.22
local TILT_WALLRUN = 0.18
local LEAN_AMT = 0.055
local LAND_AMT = 0.35
local SWAY_AMT = 0.04
local SWAY_GRAPPLE = 0.13

local bobSpring = SpringModule.new(110, 9)
local tiltSpring = SpringModule.new(140, 11)
local leanSpring = SpringModule.new(120, 10)
local landSpring = SpringModule.new(170, 13)
local swaySpring = SpringModule.new(95, 9)
local bankSpring = SpringModule.new(90, 8)

local bobTime = 0
local lastVelocity = Vector3.zero
local justLanded = false

local mousePitch = 0
local mouseYaw = 0

local headAccessories: { BasePart } = {}

local function collectHeadParts()
	headAccessories = {}
	if not character then
		return
	end
	for _, acc in ipairs(character:GetChildren()) do
		if acc:IsA("Accessory") then
			local handle = acc:FindFirstChild("Handle")
			if handle then
				local att = handle:FindFirstChildOfClass("Attachment")
				if
					att
					and (
						string.find(att.Name:lower(), "hat")
						or string.find(att.Name:lower(), "hair")
						or string.find(att.Name:lower(), "face")
						or string.find(att.Name:lower(), "head")
					)
				then
					table.insert(headAccessories, handle :: BasePart)
				end
			end
		end
	end
	local head = character:FindFirstChild("Head")
	if head then
		for _, acc in ipairs(character:GetChildren()) do
			if acc:IsA("Accessory") then
				local handle = acc:FindFirstChild("Handle") :: BasePart?
				if handle then
					local weld = handle:FindFirstChildOfClass("Weld") or handle:FindFirstChildOfClass("Motor6D")
					if weld then
						local part0 = weld:IsA("Weld") and (weld :: Weld).Part0 or (weld :: Motor6D).Part0
						local part1 = weld:IsA("Weld") and (weld :: Weld).Part1 or (weld :: Motor6D).Part1
						if (part0 and part0.Name == "Head") or (part1 and part1.Name == "Head") then
							if not table.find(headAccessories, handle) then
								table.insert(headAccessories, handle)
							end
						end
					end
				end
			end
		end
	end
end

local function setHeadPartsVisible(visible: boolean)
	local transparency = visible and 0 or 1
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if head then
		head.LocalTransparencyModifier = visible and 0 or 1
		for _, d in ipairs(head:GetChildren()) do
			if d:IsA("Decal") then
				(d :: Decal).Transparency = transparency
			end
		end
	end
	for _, handle in ipairs(headAccessories) do
		if handle:IsA("BasePart") then
			handle.LocalTransparencyModifier = visible and 0 or 1
			for _, d in ipairs(handle:GetDescendants()) do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = visible and 0 or 1
				end
			end
		end
	end
end

function CameraModule:init(char: Model, humanoid: Humanoid, rootPart: BasePart)
	character = char
	hum = humanoid
	hrp = rootPart

	collectHeadParts()
	setHeadPartsVisible(not isFirstPerson)

	if accessoryConnection then
		accessoryConnection:Disconnect()
	end

	accessoryConnection = char.ChildAdded:Connect(function(child)
		if child:IsA("Accessory") then
			task.defer(function()
				collectHeadParts()
				setHeadPartsVisible(not isFirstPerson)
			end)
		end
	end)
end

function CameraModule:start()
	if started then
		return
	end
	started = true

	RunService:UnbindFromRenderStep("ParkourCamera")

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = TP_FOV

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	if inputConnection then
		inputConnection:Disconnect()
	end
	if inputBeganConnection then
		inputBeganConnection:Disconnect()
	end
	if inputEndedConnection then
		inputEndedConnection:Disconnect()
	end

	inputConnection = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement and not cursorFree then
			local sensitivity = 0.0026
			mouseYaw = mouseYaw - input.Delta.X * sensitivity
			mousePitch = mousePitch - input.Delta.Y * sensitivity
			mousePitch = math.clamp(mousePitch, -math.pi * 0.48, math.pi * 0.48)
		end
	end)

	inputBeganConnection = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
			cursorFree = true
		end
	end)

	inputEndedConnection = UserInputService.InputEnded:Connect(function(input, _gpe)
		if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
			cursorFree = false
		end
	end)

	RunService:BindToRenderStep("ParkourCamera", Enum.RenderPriority.Camera.Value, function(dt)
		if cursorFree then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		end

		bobTime += dt

		if isFirstPerson then
			self:_updateFP(dt)
		else
			self:_updateTP(dt)
		end

		self:_updateFOV(dt)
	end)
end

function CameraModule:_updateFOV(dt: number)
	local state = StateModule:getState()
	local targetFOV = isFirstPerson and FP_FOV or TP_FOV

	if state == "dashing" then
		targetFOV = (isFirstPerson and FP_FOV or TP_FOV) + (DASH_FOV - TP_FOV)
	end
	if state == "running" then
		targetFOV = RUN_FOV
	end
	if state == "gliding" then
		targetFOV = GLIDE_FOV
	end
	if state == "rolling" then
		targetFOV = ROLL_FOV
	end

	camera.FieldOfView = camera.FieldOfView + (targetFOV - camera.FieldOfView) * FOV_LERP * dt
end

function CameraModule:_updateTP(dt: number)
	local state = StateModule:getState()
	local rootPos = hrp.Position
	local rootCF = hrp.CFrame

	local dist = TP_DISTANCE
	local height = TP_HEIGHT
	local side = TP_SIDE

	if state == "sliding" then
		dist = TP_DISTANCE + 5
		height = TP_HEIGHT - 2.5
	elseif state == "running" then
		dist = TP_DISTANCE + 4
		height = TP_HEIGHT + 0.7
	elseif state == "gliding" then
		dist = TP_DISTANCE + 9
		height = TP_HEIGHT + 3
	elseif state == "grappling" then
		dist = TP_DISTANCE + 5
	elseif state == "wallrunning" then
		dist = TP_DISTANCE + 3
	end

	local yawCF = CFrame.Angles(0, mouseYaw, 0)
	local pitchCF = CFrame.Angles(mousePitch, 0, 0)
	local camRotCF = yawCF * pitchCF

	local vel = hrp.AssemblyLinearVelocity
	local hVel = Vector3.new(vel.X, 0, vel.Z)
	local bankTarget = 0
	if hVel.Magnitude > 1 then
		bankTarget = -rootCF.RightVector:Dot(hVel.Unit) * 0.12
	end
	local bank = bankSpring:Update(bankTarget, dt)

	local pivotCF = CFrame.new(rootPos + Vector3.new(0, height, 0)) * camRotCF
	local camOffset = pivotCF * CFrame.new(side, 0, dist)
	local camPos = camOffset.Position

	local occParams = RaycastParams.new()
	occParams.FilterType = Enum.RaycastFilterType.Exclude
	occParams.FilterDescendantsInstances = { character }

	local dir = camPos - rootPos
	local occHit = workspace:Raycast(rootPos, dir, occParams)
	if occHit then
		local safeT = math.max(0, occHit.Distance / dir.Magnitude - 0.05)
		camPos = rootPos + dir * safeT
	end

	local lookTarget = rootPos + Vector3.new(0, 1.5, 0) + camRotCF.LookVector * 4
	local finalCF = CFrame.lookAt(camPos, lookTarget) * CFrame.Angles(0, 0, bank)

	camera.CFrame = camera.CFrame:Lerp(finalCF, math.min(TP_LERP * dt, 1))
end

function CameraModule:_updateFP(dt: number)
	local state = StateModule:getState()
	local vel = hrp.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude

	local yawCF = CFrame.Angles(0, mouseYaw, 0)
	local pitchCF = CFrame.Angles(mousePitch, 0, 0)
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local headPos = head and head.Position or (hrp.Position + HEAD_OFFSET)
	local baseCF = CFrame.new(headPos) * yawCF * pitchCF

	if hum.AutoRotate and state ~= "gliding" then
		local flatLook = Vector3.new(baseCF.LookVector.X, 0, baseCF.LookVector.Z)
		if flatLook.Magnitude > 0.01 then
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flatLook.Unit)
		end
	end

	local bobTarget = 0
	if state == "running" then
		bobTarget = math.sin(bobTime * BOB_SPEED_RUN) * BOB_AMT_RUN
	elseif state == "walking" and speed > 0.5 then
		bobTarget = math.sin(bobTime * BOB_SPEED_WALK) * BOB_AMT_WALK
	else
		bobTarget = math.sin(bobTime * BREATHE_SPEED) * BREATHE_AMT
	end
	local bob = bobSpring:Update(bobTarget, dt)

	local tiltTarget = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		tiltTarget = TILT_STRAFE
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		tiltTarget = -TILT_STRAFE
	end

	if state == "sliding" then
		tiltTarget = TILT_SLIDE
	elseif state == "running" then
		tiltTarget *= 1.25
	elseif state == "wallrunning" then
		local MovementModule = require(parkour:WaitForChild("MovementModule"))
		local ws = MovementModule:getWallSide()
		tiltTarget = ws == "left" and TILT_WALLRUN or -TILT_WALLRUN
	end
	local tilt = tiltSpring:Update(tiltTarget, dt)

	local accel = (vel - lastVelocity) / math.max(dt, 0.001)
	local forwardDot = accel:Dot((CFrame.new(Vector3.zero) * yawCF * pitchCF).LookVector)
	local leanTarget = 0
	if forwardDot > 12 then
		leanTarget = -LEAN_AMT
	elseif forwardDot < -12 then
		leanTarget = LEAN_AMT
	end
	local lean = leanSpring:Update(leanTarget, dt)
	lastVelocity = vel

	local landTarget = 0
	if justLanded then
		landTarget = -LAND_AMT
		justLanded = false
	end
	local land = landSpring:Update(landTarget, dt)

	local swayTarget = 0
	if state == "grappling" then
		local right = baseCF.RightVector
		swayTarget = math.clamp(right:Dot(vel) * SWAY_GRAPPLE * 0.02, -0.3, 0.3)
	elseif state == "gliding" then
		swayTarget = math.noise(bobTime * 0.4, 42) * SWAY_AMT * 0.45
	end
	local sway = swaySpring:Update(swayTarget, dt)

	local finalCF = baseCF * CFrame.new(sway, bob + land, -0.05) * CFrame.Angles(lean, 0, tilt)

	camera.CFrame = finalCF
end

function CameraModule:toggleView()
	if viewTransitioning then
		return
	end
	viewTransitioning = true

	isFirstPerson = not isFirstPerson

	if isFirstPerson then
		setHeadPartsVisible(false)
		local CapeModule = require(parkour:WaitForChild("CapeModule"))
		CapeModule:hide()
	else
		setHeadPartsVisible(true)
		local CapeModule = require(parkour:WaitForChild("CapeModule"))
		CapeModule:show()
	end

	bobSpring:Reset()
	tiltSpring:Reset()
	leanSpring:Reset()
	landSpring:Reset()
	swaySpring:Reset()
	bankSpring:Reset()

	task.delay(0.3, function()
		viewTransitioning = false
	end)
end

function CameraModule:getIsFirstPerson(): boolean
	return isFirstPerson
end

local function onStateChanged(newState: string, prevState: string?)
	if not hum or not hrp then
		return
	end

	if prevState == "airborne" or prevState == "gliding" or prevState == "wallrunning" then
		if newState == "walking" or newState == "running" then
			justLanded = true
		end
	end

	if newState == "sliding" then
		tiltSpring:Reset()
	end
	if newState == "gliding" then
		bobSpring:Reset()
	end
	if newState == "dashing" then
		leanSpring:Reset()
	end
	if newState == "rolling" then
		bobSpring:Reset()
		tiltSpring:Reset()
	end
end

StateModule:AddSubscriber(onStateChanged)

return CameraModule
