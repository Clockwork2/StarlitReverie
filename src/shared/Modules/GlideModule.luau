local GlideModule = {}

local Animations = script.Parent.Parent:WaitForChild("Animations")
local character
local hum
local animator
local glideTrack

function GlideModule:init(char, humanoid)
	character = char
	hum = humanoid

    animator = hum:WaitForChild("Animator")
    glideTrack = animator:LoadAnimation(Animations:WaitForChild("GlidePose"))
end

function GlideModule:start()
    glideTrack:Play(0.3)
end

function GlideModule:stop()
    glideTrack:Stop(0.3)
end

return GlideModule