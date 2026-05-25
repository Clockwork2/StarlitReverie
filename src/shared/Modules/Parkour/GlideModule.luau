local GlideModule = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local animator: Animator
local tracks: { [string]: AnimationTrack } = {}

local ANIMATION_NAMES = {
	"Dash",
	"Airborne",
	"Roll",
	"GlidePose",
	"Running",
	"Slide",
	"Crouch",
	"LeftWallrun",
	"RightWallrun",
}

local STATIC_POSES = {
	GlidePose = true,
	Slide = true,
}

local function getTrack(name: string): AnimationTrack?
	return tracks[name]
end

function GlideModule:init(_char: Model, humanoid: Humanoid)
	animator = humanoid:WaitForChild("Animator") :: Animator
	table.clear(tracks)

	local folder = ReplicatedStorage:WaitForChild("Animations")
	for _, name in ipairs(ANIMATION_NAMES) do
		local anim = folder:FindFirstChild(name)
		if anim and anim:IsA("Animation") then
			local track = animator:LoadAnimation(anim)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = name == "Running" or name == "Crouch" or STATIC_POSES[name] == true
			tracks[name] = track
		else
			warn("[GlideModule] Missing animation:", name)
		end
	end
end

function GlideModule:play(name: string, fadeTime: number?, speed: number?): AnimationTrack?
	local track = getTrack(name)
	if not track then
		return nil
	end

	if not track.IsPlaying then
		track:Play(fadeTime or 0.15)
	end

	track:AdjustSpeed(speed or 1)
	return track
end

function GlideModule:stopTrack(name: string, fadeTime: number?)
	local track = getTrack(name)
	if track and track.IsPlaying then
		track:Stop(fadeTime or 0.15)
	end
end

function GlideModule:stopMovement(exceptName: string?)
	for name, track in pairs(tracks) do
		if name ~= exceptName and track.IsPlaying then
			track:Stop(0.15)
		end
	end
end

function GlideModule:playStatic(name: string, fadeTime: number?): AnimationTrack?
	local track = GlideModule:play(name, fadeTime or 0.2, 1)
	if track then
		task.defer(function()
			if track.IsPlaying then
				track:AdjustSpeed(0)
			end
		end)
	end
	return track
end

function GlideModule:playDashWindup(onDash: () -> ())
	local track = GlideModule:play("Dash", 0.05, 1)
	if not track then
		onDash()
		return
	end

	task.delay(1, function()
		if not track.IsPlaying then
			onDash()
			return
		end
		track.TimePosition = math.min(1, math.max(track.Length - 0.03, 0))
		track:AdjustSpeed(0)
		onDash()
		task.delay(0.08, function()
			if track.IsPlaying then
				track:AdjustSpeed(1)
			end
		end)
	end)
end

function GlideModule:start()
	GlideModule:playStatic("GlidePose", 0.3)
end

function GlideModule:stop()
	GlideModule:stopTrack("GlidePose", 0.3)
end

return GlideModule
