local SpringModule = {}

local Spring = {}
Spring.__index = Spring

function Spring:Update(target: number, dt: number): number
	dt = math.min(dt, 1 / 30)

	local force = (target - self.position) * self.stiffness
	self.velocity = (self.velocity + force * dt) * math.exp(-self.damping * dt)
	self.position += self.velocity * dt

	return self.position
end

function Spring:Reset(value: number?)
	self.position = value or 0
	self.velocity = 0
end

function SpringModule.new(stiffness: number, damping: number)
	return setmetatable({
		position = 0,
		velocity = 0,
		stiffness = stiffness,
		damping = damping,
	}, Spring)
end

return SpringModule
