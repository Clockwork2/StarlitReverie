local rs = game:GetService("ReplicatedStorage")
local shared = rs:WaitForChild("Shared")
local modules = shared:WaitForChild("Modules")
local remotes = shared:WaitForChild("Remotes")

local MovementModule = require(modules:WaitForChild("MovementModule"))
local StateModule = require(modules:WaitForChild("StateModule"))

local SendInput = remotes:WaitForChild("SendInput")
local ReceiveCorrection = remotes:WaitForChild("ReceiveCorrection")
local ReplicateState = remotes:WaitForChild("ReplicateState")

SendInput.OnServerEvent:Connect(function(player, state, clientPosition, timestamp)
	local char = player.Character
	local hrp = char:WaitForChild("HumanoidRootPart")

	local delta = (clientPosition - hrp.Position).Magnitude

	if delta > 10 then
		ReceiveCorrection:FireClient(player, hrp.Position)
	end

	ReplicateState:FireAllClients(state)
end)
