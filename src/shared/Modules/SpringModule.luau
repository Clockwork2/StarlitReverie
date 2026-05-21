local SpringModule = {}

function SpringModule.new(stiffness, damping)
	local spring = {}
	spring.position = 0
	spring.velocity = 0
	spring.stiffness = stiffness
	spring.damping = damping

	function spring:Update(target, dt)
		local distance = target - spring.position
		spring.velocity += (distance * spring.stiffness)

		local dampenValue = spring.velocity * spring.damping
		spring.velocity -= dampenValue

		spring.position += (spring.velocity * dt)

		return self.position
	end

	return spring
end

return SpringModule
