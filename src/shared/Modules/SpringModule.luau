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
		spring.velocity -= (spring.velocity * spring.damping * dt)
		spring.position += (spring.velocity * dt)
		return spring.position
	end

	return spring
end

return SpringModule
