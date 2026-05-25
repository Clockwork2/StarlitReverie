local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")

local remotesFolder = sharedFolder:FindFirstChild("Remotes")

if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = sharedFolder
end

local remotes = {
	"ReceiveCorrection",
	"ApplyTimeEffect",
	"ReplicateTimeEffect",
	"ReplicateState",
	"SendInput",
}

for _, remoteName in ipairs(remotes) do
	if not remotesFolder:FindFirstChild(remoteName) then
		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = remotesFolder
	end
end
