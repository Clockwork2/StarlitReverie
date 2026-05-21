local CapeModule = {}

local RunService = game:GetService("RunService")

local Modules = script.Parent
local StateModule = require(Modules:WaitForChild("StateModule"))

local particles = {}
local visuals = {}

local CAPE_COLS = 4
local CAPE_ROWS = 8
local CAPE_SPACING = 0.4
local GRAVITY = Vector3.new(0, -196, 0)
local CONSTRAINT_ITERATIONS = 5
local AIRFLOW_STRENGTH = 8
local CAPE_COLOR = BrickColor.new("Bright red")
local CAPE_SIZE = Vector3.new(0.35, 0.45, 0.08)

local character
local hrp
local torso

local currentState = "walking"
local heartbeatConnection

function CapeModule:createParticles()
	for row = 1, CAPE_ROWS do
		for col = 1, CAPE_COLS do
			local xoffset = (col - (CAPE_COLS + 1) / 2) * CAPE_SPACING
			local yoffset = -(row - 1) * CAPE_SPACING
			local zoffset = 0.5

			local spawnPosition = torso.Position
				+ torso.CFrame.RightVector * xoffset
				+ Vector3.new(0, yoffset, 0)
				- torso.CFrame.LookVector * zoffset
			local particle = {
				position = spawnPosition,
				previousPosition = spawnPosition,
				anchored = (row == 1),
			}

			particles[row] = particles[row] or {}
			particles[row][col] = particle
		end
	end
end

function CapeModule:createVisuals()
	for row = 1, CAPE_ROWS do
		for col = 1, CAPE_COLS do
			local part = Instance.new("Part")

			part.Size = CAPE_SIZE
			part.BrickColor = CAPE_COLOR
			part.CanCollide = false
			part.Anchored = true
			part.CastShadow = false
			part.Parent = workspace

			visuals[row] = visuals[row] or {}
			visuals[row][col] = part
		end
	end
end

local function updateAnchors()
	for col = 1, CAPE_COLS do
		local xoffset = (col - (CAPE_COLS + 1) / 2) * CAPE_SPACING
		local anchorPos = torso.CFrame.Position + torso.CFrame.RightVector * xoffset - torso.CFrame.LookVector * 0.5
		local particle = particles[1][col]
		particle.position = anchorPos
		particle.previousPosition = anchorPos
	end
end

local function verlet(dt)
	for row = 1, CAPE_ROWS do
		for col = 1, CAPE_COLS do
			local particle = particles[row][col]
			if particle.anchored then
				continue
			end

			local velocity = particle.position - particle.previousPosition
			local oldPos = particle.position

			particle.position = particle.position + velocity + GRAVITY * dt * dt

			if currentState == "gliding" then
				particle.position += Vector3.new(0, AIRFLOW_STRENGTH * dt, 0)
			end

			particle.previousPosition = oldPos
		end
	end
end

local function solveConstraints()
	for i = 1, CONSTRAINT_ITERATIONS do
		for row = 1, CAPE_ROWS do
			for col = 1, CAPE_COLS do
				local downNeighbour
				local rightNeighbour

				if col < CAPE_COLS then
					rightNeighbour = particles[row][col + 1]
				end

				if row < CAPE_ROWS then
					downNeighbour = particles[row + 1][col]
				end

				local delta = downNeighbour.position - rightNeighbour.position
				local dist = delta.Magnitude
				local error = dist - CAPE_SPACING
				local correction = delta.Unit * error * 0.5

				if not rightNeighbour.anchored then
					rightNeighbour.position += correction
				end
				if not downNeighbour.anchored then
					downNeighbour.position -= correction
				end
			end
		end
	end
end

local function updateVisuals() end

local function onStateChanged(new, prev)
	currentState = new
end

function CapeModule:show() end

function CapeModule:hide() end

function CapeModule:init(char, rootPart)
	character = char
	hrp = rootPart
	torso = char:WaitForChild("Torso")

	CapeModule:createParticles()
	CapeModule:createVisuals()

	StateModule:AddSubscriber(onStateChanged)

	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		updateAnchors()
		verlet(dt)
		solveConstraints()
		updateVisuals()
	end)
end

return CapeModule
