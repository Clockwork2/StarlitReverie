local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local remotes = shared:WaitForChild("Remotes")

local SendInput = remotes:WaitForChild("SendInput")
local ReceiveCorrection = remotes:WaitForChild("ReceiveCorrection")
local ReplicateState = remotes:WaitForChild("ReplicateState")

local CORRECTION_THRESHOLD = 12
local MAX_SPEED_THRESHOLD = 160

local validStates = {
	walking = true,
	running = true,
	sliding = true,
	ducking = true,
	rolling = true,
	wallrunning = true,
	grappling = true,
	airborne = true,
	gliding = true,
	dashing = true,
}

local playerData: { [Player]: { lastTimestamp: number, lastPosition: Vector3? } } = {}

Players.PlayerAdded:Connect(function(player)
	playerData[player] = { lastTimestamp = 0, lastPosition = nil }
end)

Players.PlayerRemoving:Connect(function(player)
	playerData[player] = nil
end)

SendInput.OnServerEvent:Connect(function(player: Player, state: string, clientPos: Vector3, timestamp: number)
	if not validStates[state] then
		return
	end
	if typeof(clientPos) ~= "Vector3" or typeof(timestamp) ~= "number" then
		return
	end

	local data = playerData[player]
	if not data or timestamp <= data.lastTimestamp then
		return
	end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local serverPos = hrp.Position
	if (clientPos - serverPos).Magnitude > CORRECTION_THRESHOLD then
		ReceiveCorrection:FireClient(player, serverPos)
	end

	local vel = hrp.AssemblyLinearVelocity
	if vel.Magnitude > MAX_SPEED_THRESHOLD then
		hrp.AssemblyLinearVelocity = vel.Unit * MAX_SPEED_THRESHOLD
		ReceiveCorrection:FireClient(player, hrp.Position)
	end

	data.lastTimestamp = timestamp
	data.lastPosition = serverPos

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			ReplicateState:FireClient(otherPlayer, player.UserId, state)
		end
	end
end)
