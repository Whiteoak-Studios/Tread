--[[
    A walking body that moved never ends a step with its rounded hull inside
    a part or reported stuck, along a wall, in a pocket beside a hull, grazing
    a wall and along a wall turned by a yaw, all faces off the quantum
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local STEP: string = "src/Step/init.luau"
local CONSTANTS: string = "src/Constants.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"

local MODULUS: number = 2147483647 -- The Lehmer generator's prime, so a seed always draws the same walks
local MULTIPLIER: number = 48271
local SHORT: number = 0.03 -- The least a walker starts short of the wall ahead of it, its skin and a little more
local NEAREST: number = 0.0005 -- The least and most a grazing walker starts from its wall
local FARTHEST: number = 0.03
local SLACK: number = 0.004 -- The most past a skin a walker along a turned wall starts from it
local SLIVER: number = 0.08 -- The most a pressed walker's yaw leans into its wall, radians
local GRAZE: number = 0.004 -- The most a grazing walker's yaw leans into its wall, radians, about half under 1/512
local SPRINTING: number = 0.3 -- The share of walkers that sprint, and of grazing ones
local GRAZING_SPRINTING: number = 0.5
local CROWDED: number = 0.01 -- How much less than a hull width the pocket's hull overlaps the walker's x at most
local PHASES: number = 10 -- The every-tenth exact check's phases, one drawn a walk
local TURN_EDGE: number = 0.03 -- How far inside a quarter turn's ends a turned wall's yaw is drawn

local Y_AXIS: vector = vector.create(0, 1, 0)
local WORLD_AXES: { vector } = { vector.create(1, 0, 0), Y_AXIS, vector.create(0, 0, 1) }

-- A part turned by a yaw about Y: its center, its half size and its three unit axes
type Part = {
	center: vector,
	half: vector,
	axes: { vector },
}

-- One layout's walks, each drawn from the layout's seed
type Layout = {
	name: string,
	seed: number,
	walks: number,
	ticks: number,
}

-- One walker: its state, and its command's yaw and sprint for the whole walk
type Walker = {
	state: any,
	yaw: number,
	sprint: boolean,
}

-- Each seed's walks end a moving step inside a wall under a step that leaves the rounding unchecked
local LAYOUTS: { Layout } = {
	{ name = "along", seed = 28, walks = 200, ticks = 20 },
	{ name = "pocket", seed = 7, walks = 200, ticks = 20 },
	{ name = "graze", seed = 19, walks = 100, ticks = 40 },
	{ name = "turned", seed = 2, walks = 40, ticks = 60 },
}

local function dot(a: vector, b: vector): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

local function turned(center: vector, half: vector, yaw: number): Part
	local across: vector = vector.create(math.cos(yaw), 0, -math.sin(yaw))
	local along: vector = vector.create(math.sin(yaw), 0, math.cos(yaw))

	return { center = center, half = half, axes = { across, Y_AXIS, along } }
end

local function block(low: vector, high: vector): Part
	return turned((low + high) / 2, (high - low) / 2, 0)
end

local FLOOR: Part = block(vector.create(-100, -2, -100), vector.create(100, 0, 100))

-- How far a box of half size half and a part reach along a unit axis together
local function reach(part: Part, half: vector, axis: vector): number
	local axes: { vector } = part.axes
	local own: number = part.half.x * math.abs(dot(axis, axes[1]))
		+ part.half.y * math.abs(dot(axis, axes[2]))
		+ part.half.z * math.abs(dot(axis, axes[3]))

	return half.x * math.abs(axis.x) + half.y * math.abs(axis.y) + half.z * math.abs(axis.z) + own
end

-- How deep a box sits inside a part, its least overlap over the separating axes, 0 when apart or touching
local function depth(part: Part, center: vector, half: vector): number
	local gap: vector = part.center - center
	local least: number = math.huge

	for _, axes: { vector } in { WORLD_AXES, part.axes } do
		for _, axis: vector in axes do
			local overlap: number = reach(part, half, axis) - math.abs(dot(gap, axis))
			if overlap <= 0 then
				return 0
			end

			least = math.min(least, overlap)
		end
	end

	return least
end

-- The shares of a move at which it enters and leaves a slab of half width extent whose center lies gap away
local function slab(gap: number, extent: number, move: number): (number, number)
	if move == 0 then
		if math.abs(gap) < extent then
			return -math.huge, math.huge
		end

		return math.huge, -math.huge
	end

	local near: number = (gap - extent) / move
	local far: number = (gap + extent) / move
	if near > far then
		return far, near
	end

	return near, far
end

--[[
    The step's casts over a list of parts the walks refill: exact sweeps by
    the separating axes, each skipping a part it starts inside as the
    engine's do, and the exact overlap query, counting each time it finds one
--]]

local function casts(parts: { Part }, skins: number, found: { number }): { [string]: any }
	local hit: { [string]: any } = {
		distance = 0,
		position = vector.zero,
		normal = vector.zero,
		material = roblox.Enum.Material.Plastic,
		instance = nil,
	}

	local function cast(center: vector, half: vector, direction: vector): { [string]: any }?
		local best: number, bestNormal: vector = math.huge, vector.zero

		for _, part: Part in parts do
			local gap: vector = part.center - center
			local enter: number, exit: number, normal: vector = -math.huge, math.huge, vector.zero

			for _, axes: { vector } in { WORLD_AXES, part.axes } do
				for _, axis: vector in axes do
					local move: number = dot(direction, axis)
					local near: number, far: number = slab(dot(gap, axis), reach(part, half, axis), move)
					if near > enter then
						enter = near
						normal = axis * -math.sign(move)
					end

					exit = math.min(exit, far)
				end
			end

			if enter >= 0 and enter < exit and enter <= 1 and enter < best then
				best = enter
				bestNormal = normal
			end
		end

		if best > 1 then
			return nil
		end

		hit.distance = best * math.sqrt(dot(direction, direction))
		hit.position = center + direction * best
		hit.normal = bestNormal

		return hit
	end

	return {
		ray = function (origin: vector, direction: vector): { [string]: any }?
			return cast(origin, vector.zero, direction)
		end,

		sweep = function (center: vector, size: vector, direction: vector): { [string]: any }?
			return cast(center, size / 2, direction)
		end,

		rest = function (center: vector, size: vector): number?
			local top: number = center.y + size.y / 2
			local plate: vector = vector.create(size.x / 2, 0, size.z / 2)
			local below: { [string]: any }? =
				cast(vector.create(center.x, top, center.z), plate, vector.create(0, -(size.y + skins), 0))
			if not below then
				return nil
			end

			return top - below.distance
		end,

		sphere = function (center: vector, radius: number, direction: vector): { [string]: any }?
			return cast(center, vector.one * radius, direction)
		end,

		overlap = function (center: vector, size: vector): boolean
			for _, part: Part in parts do
				if depth(part, center, size / 2) > 0 then
					found[1] += 1

					return true
				end
			end

			return false
		end,

		destroy = function () end,
	}
end

-- A walk ahead at a yaw, its presses all off
local function command(number: number, yaw: number, sprint: boolean): { [string]: any }
	return {
		number = number,
		forward = 1,
		right = 0,
		jump = false,
		crouch = false,
		sprint = sprint,
		aim = false,
		pressed = { jump = false, crouch = false, sprint = false, aim = false },
		yaw = yaw,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	}
end

return function (): (boolean, string | nil)
	local Step: any = Environment.load(STEP)
	local Constants: any = Environment.load(CONSTANTS)
	local Scene: any = Environment.load(SCENE)

	local quantum: number = Constants.POSITION_QUANTUM
	local skin: number = Constants.SKIN
	local radius: number = Scene.settings.radius
	local width: number = radius + radius
	local hull: vector = vector.create(radius, Scene.settings.standing / 2, radius)
	local resting: number = math.round(skin / quantum) * quantum -- Feet a skin over the floor's top at 0

	local parts: { Part } = {}
	local bodies: { any } = {}
	local found: { number } = { 0 }
	local world: any = Scene.world(casts(parts, skin + skin, found), bodies)

	local function quantized(value: number): number
		return math.round(value / quantum) * quantum
	end

	-- A standing body at feet among the bodies the hulls test against
	local function body(feet: vector): any
		local state: any = Scene.state(feet, true)
		table.insert(bodies, state)

		return state
	end

	-- Why one layout's walks broke the rule, or nil
	local function run(layout: Layout): string?
		local drawn: number = layout.seed
		local function random(low: number, high: number): number
			drawn = drawn * MULTIPLIER % MODULUS
			return low + (high - low) * (drawn - 1) / (MODULUS - 1)
		end

		-- The layout's parts and walker for one walk, its walls' faces off the quantum as a part's face anywhere is
		local function build(): Walker
			table.clear(parts)
			table.clear(bodies)
			table.insert(parts, FLOOR)

			local wallX: number = 10 + random(0, 1)
			local wallZ: number = 10 + random(0, 1)
			local sprint: boolean = random(0, 1) < SPRINTING
			local pressedX: number = quantized(wallX - radius - skin)

			if layout.name == "turned" then
				-- One wall turned by a yaw, the walker a skin from its face near an end, walking along it with a sliver in
				local yaw: number = random(TURN_EDGE, math.pi / 2 - TURN_EDGE)
				local wall: Part = turned(vector.zero, vector.create(2, 5, 32), yaw)
				local across: vector, along: vector = wall.axes[1], wall.axes[3]
				local foot: vector = vector.create(wallX, 0, wallZ - 10)
				wall.center = foot + across * 2 + along * -18 + vector.create(0, 5, 0)
				table.insert(parts, wall)

				local spread: number = radius * (math.abs(across.x) + math.abs(across.z))
				local spot: vector = foot + across * -(spread + skin + random(0, SLACK)) + along * (-45 + random(0, 2))
				local state: any = body(vector.create(quantized(spot.x), resting, quantized(spot.z)))

				return { state = state, yaw = yaw + math.pi + random(0, SLIVER), sprint = sprint }
			elseif layout.name == "graze" then
				-- A long wall past wallX, the walker a hair from it rounded away, walking +Z at a hair's angle into it
				table.insert(parts, block(vector.create(wallX, 0, -60), vector.create(wallX + 4, 10, 200)))
				local x: number = math.floor((wallX - radius - random(NEAREST, FARTHEST)) / quantum) * quantum
				local state: any = body(vector.create(x, resting, quantized(random(-40, -30))))

				return { state = state, yaw = math.pi + random(0, GRAZE), sprint = random(0, 1) < GRAZING_SPRINTING }
			end

			-- Pressed a skin from a wall past wallX, walking +Z with a sliver into it
			table.insert(parts, block(vector.create(wallX, 0, -60), vector.create(wallX + 4, 10, wallZ + 4)))
			local yaw: number = math.pi + random(0, SLIVER)

			if layout.name == "along" then
				-- Into the corner a second wall past wallZ makes with the first
				table.insert(parts, block(vector.create(-60, 0, wallZ), vector.create(wallX + 4, 10, wallZ + 4)))
				local z: number = quantized(random(wallZ - 8, wallZ - radius - SHORT))

				return { state = body(vector.create(pressedX, resting, z)), yaw = yaw, sprint = sprint }
			end

			-- Pocket: a standing hull ahead along +Z beside the wall, overlapping the walker's x by up to its width
			local otherX: number = quantized(wallX - radius - skin - random(0, width - CROWDED))
			local otherZ: number = quantized(wallZ)
			body(vector.create(otherX, resting, otherZ))
			local z: number = quantized(otherZ - width - skin - random(0, 6))

			return { state = body(vector.create(pressedX, resting, z)), yaw = yaw, sprint = sprint }
		end

		found[1] = 0

		for walk: number = 1, layout.walks do
			local walker: Walker = build()
			local state: any = walker.state
			local phase: number = math.floor(random(0, PHASES))

			for tick: number = 1, layout.ticks do
				local start: vector = state.position
				local _: number, stuck: number? =
					Step.advance(state, command(phase + tick, walker.yaw, walker.sprint), world)
				if stuck ~= nil then
					return `The {layout.name} walk {walk} was reported stuck {stuck} deep on tick {tick}`
				end

				local feet: vector = state.position
				if feet ~= start then
					local center: vector = vector.create(feet.x, feet.y + hull.y, feet.z)
					for _, part: Part in parts do
						local sunk: number = depth(part, center, hull)
						if sunk > 0 then
							return `The {layout.name} walk {walk} moved to {feet} on tick {tick}, its hull {sunk} inside a part`
						end
					end
				end
			end
		end

		if found[1] == 0 then
			return `The exact query never found a part in the {layout.name} walks, so they test nothing`
		end

		return nil
	end

	for _, layout: Layout in LAYOUTS do
		local failed: string? = run(layout)
		if failed then
			return false, failed
		end
	end

	return true, nil
end
