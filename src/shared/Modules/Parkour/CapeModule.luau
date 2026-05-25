local CapeModule = {}

local RunService = game:GetService("RunService")

local Modules = script.Parent
local StateModule = require(Modules:WaitForChild("StateModule"))

local COLS = 4
local ROWS = 8
local SPACING = 0.38
local GRAVITY = -58
local DAMPING = 0.975
local ITERATIONS = 8
local ANCHOR_Z_OFFSET = 0.55
local ANCHOR_Y_OFFSET = 0.9

local AIRFLOW_GLIDE = 18
local AIRFLOW_WALLRUN = 9
local AIRFLOW_GRAPPLE = 14
local AIRFLOW_DUCK_FOLD = -10
local AIRFLOW_RUN = 5

local PART_WIDTH = 0.34
local PART_DEPTH = 0.025

local CAPE_COLOR = Color3.fromRGB(180, 20, 20)
local CAPE_TRIM = Color3.fromRGB(220, 200, 80)

type Particle = {
	pos: Vector3,
	prev: Vector3,
	anchor: boolean,
}

local particles: { { Particle } } = {}
local visuals: { { BasePart } } = {}

local torso: BasePart
local character: Model
local hrp: BasePart

local currentState: string = "walking"
local heartbeat: RBXScriptConnection?
local unsubscribeState: (() -> ())?
local hidden = false

local function makeAnchorPos(col: number): Vector3
	local x = (col - (COLS + 1) / 2) * SPACING
	return (torso.CFrame * CFrame.new(x, ANCHOR_Y_OFFSET, ANCHOR_Z_OFFSET)).Position
end

local function buildParticles()
	particles = {}
	for row = 1, ROWS do
		particles[row] = {}
		for col = 1, COLS do
			local base: Vector3
			if row == 1 then
				base = makeAnchorPos(col)
			else
				local above = particles[row - 1][col]
				base = above.pos - Vector3.new(0, SPACING, 0)
			end
			particles[row][col] = {
				pos = base,
				prev = base,
				anchor = (row == 1),
			}
		end
	end
end

local function buildVisuals()
	visuals = {}
	for row = 1, ROWS - 1 do
		visuals[row] = {}
		for col = 1, COLS do
			local isTrim = (row == 1 or row == ROWS - 1 or col == 1 or col == COLS)
			local p = Instance.new("Part")
			p.Size = Vector3.new(PART_WIDTH, SPACING, PART_DEPTH)
			p.Color = isTrim and CAPE_TRIM or CAPE_COLOR
			p.Material = Enum.Material.Fabric
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.CastShadow = false
			p.Anchored = true
			p.Massless = true
			p.Name = "CapeSegment_" .. row .. "_" .. col
			p.Parent = workspace
			visuals[row][col] = p
		end
	end
end

local function updateAnchors()
	for col = 1, COLS do
		local p = particles[1][col]
		local pos = makeAnchorPos(col)
		p.pos = pos
		p.prev = pos
	end
end

local function stepVerlet(dt: number)
	local state = currentState
	local vel = hrp.AssemblyLinearVelocity
	local speed = vel.Magnitude
	local charBack = -torso.CFrame.LookVector
	local velocityWind = speed > 0.1 and -vel.Unit * math.min(speed * 0.08, 9) or Vector3.zero

	local airflow = Vector3.zero

	if state == "gliding" then
		airflow = Vector3.new(0, AIRFLOW_GLIDE * dt, 0) + charBack * 4 * dt + velocityWind * dt
	elseif state == "wallrunning" then
		airflow = Vector3.new(0, AIRFLOW_WALLRUN * dt, 0) + velocityWind * dt
	elseif state == "grappling" then
		local dir = vel.Magnitude > 0.1 and vel.Unit or Vector3.zero
		airflow = -dir * AIRFLOW_GRAPPLE * dt + Vector3.new(0, 4 * dt, 0)
	elseif state == "ducking" then
		airflow = Vector3.new(0, AIRFLOW_DUCK_FOLD * dt, 0) + torso.CFrame.LookVector * 3 * dt
	elseif state == "running" then
		airflow = charBack * AIRFLOW_RUN * dt + velocityWind * dt
	elseif state == "airborne" then
		local hSpd = Vector3.new(vel.X, 0, vel.Z).Magnitude
		airflow = charBack * math.min(hSpd * 0.15, 4) * dt + velocityWind * dt
	end

	for row = 1, ROWS do
		for col = 1, COLS do
			local p = particles[row][col]
			if p.anchor then
				continue
			end

			local rowFrac = (row - 1) / (ROWS - 1)
			local v = (p.pos - p.prev) * DAMPING
			local oldPos = p.pos

			p.pos = p.pos + v + Vector3.new(0, GRAVITY * dt * dt, 0) + airflow * rowFrac
			p.prev = oldPos
		end
	end
end

local function solveConstraints()
	for _ = 1, ITERATIONS do
		for row = 1, ROWS do
			for col = 1, COLS do
				local A = particles[row][col]

				if col < COLS then
					local B = particles[row][col + 1]
					local delta = B.pos - A.pos
					local dist = delta.Magnitude
					if dist > 0.001 then
						local err = delta.Unit * (dist - SPACING) * 0.5
						if not A.anchor then
							A.pos += err
						end
						if not B.anchor then
							B.pos -= err
						end
					end
				end

				if row < ROWS then
					local B = particles[row + 1][col]
					local delta = B.pos - A.pos
					local dist = delta.Magnitude
					if dist > 0.001 then
						local err = delta.Unit * (dist - SPACING) * 0.5
						if not A.anchor then
							A.pos += err
						end
						if not B.anchor then
							B.pos -= err
						end
					end
				end
			end
		end
	end
end

local function updateVisuals()
	if hidden then
		return
	end
	local torsoRight = torso.CFrame.RightVector
	for row = 1, ROWS - 1 do
		for col = 1, COLS do
			local part = visuals[row][col]
			local pA = particles[row][col]
			local pB = particles[row + 1][col]
			local down = (pB.pos - pA.pos)

			if down.Magnitude < 0.001 then
				continue
			end

			local mid = (pA.pos + pB.pos) * 0.5
			local up = down.Unit
			local right = torsoRight
			if col < COLS then
				local side = particles[row][col + 1].pos - pA.pos
				if side.Magnitude > 0.001 then
					right = side.Unit
				end
			elseif col > 1 then
				local side = pA.pos - particles[row][col - 1].pos
				if side.Magnitude > 0.001 then
					right = side.Unit
				end
			end
			local back = right:Cross(up)
			if back.Magnitude < 0.001 then
				back = torso.CFrame.LookVector
			end
			if math.abs(back.Unit:Dot(up)) > 0.98 then
				back = torso.CFrame.UpVector
			end
			right = up:Cross(back).Unit
			back = right:Cross(up).Unit
			part.Size = Vector3.new(PART_WIDTH, down.Magnitude, PART_DEPTH)
			part.CFrame = CFrame.fromMatrix(mid, right, up, back)
		end
	end
end

function CapeModule:init(char: Model, rootPart: BasePart)
	character = char
	hrp = rootPart
	torso = char:WaitForChild("Torso") :: BasePart

	buildParticles()
	buildVisuals()
	if hidden then
		CapeModule:hide()
	end

	if unsubscribeState then
		unsubscribeState()
	end
	unsubscribeState = StateModule:AddSubscriber(function(new, _)
		currentState = new
	end)

	heartbeat = RunService.Heartbeat:Connect(function(dt)
		updateAnchors()
		stepVerlet(dt)
		solveConstraints()
		updateVisuals()
	end)
end

function CapeModule:show()
	hidden = false
	for row = 1, ROWS - 1 do
		for col = 1, COLS do
			visuals[row][col].Transparency = 0
		end
	end
end

function CapeModule:hide()
	hidden = true
	for row = 1, ROWS - 1 do
		for col = 1, COLS do
			visuals[row][col].Transparency = 1
		end
	end
end

function CapeModule:destroy()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	if unsubscribeState then
		unsubscribeState()
		unsubscribeState = nil
	end
	for row = 1, ROWS - 1 do
		for col = 1, COLS do
			if visuals[row] and visuals[row][col] then
				visuals[row][col]:Destroy()
			end
		end
	end
	particles = {}
	visuals = {}
end

return CapeModule
