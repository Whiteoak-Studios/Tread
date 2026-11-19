--[[
    Every other end of a slide starts its cooldown too: going down, Noclip,
    Parked, entering water, mounting a ladder and starting a mantle, each
    of which takes a sliding body as it takes one on the ground
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local SPEED: number = 18
local SURFACE: number = 4 -- Studs of water over the floor ahead, past the swim depth
local WATER_FROM: number = 96 -- Z the water starts at, toward -Z
local LADDER: vector = vector.create(2, 6, 0.5) -- A ladder box across the lane, thin along Z
local LIMIT: number = 20 -- Ticks a slide is stepped at most before its end

-- A sliding body moving along -Z at feet, and its command with forward and crouch held
local function sliding(Slides: any, feet: vector): (any, any)
	local state: any = Slides.state(feet, true)
	state.mode = "Slide"
	state.posture = "Crouch"
	state.velocity = vector.create(0, 0, -SPEED)

	local order: any = Slides.command()
	order.forward = 1
	order.crouch = true

	return state, order
end

-- Steps until the mode leaves Slide, and gives why that end was not the one wanted, or nil
local function ends(Slides: any, label: string, state: any, world: any, order: any, mode: string): string?
	local cooldown: number = math.round(world.settings.slide.cooldown / world.delta)

	for _ = 1, LIMIT do
		Slides.advance(state, world, order, 1)
		if state.mode ~= "Slide" then
			return Slides.is(`the mode {label}`, state.mode, mode)
				or Slides.is(`the cooldown {label}`, state.slideCooldown, cooldown)
		end
	end

	return `It still slid {LIMIT} ticks on, {label}`
end

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)

	-- Going down, Noclip and Parked
	local changes: { { label: string, mode: string, change: (state: any) -> () } } = {
		{
			label = "once downed",
			mode = "Ground",
			change = function (state: any)
				state.posture = "Downed"
			end,
		},
		{
			label = "in Noclip",
			mode = "Air",
			change = function (state: any)
				state.moveMode = "Noclip"
			end,
		},
		{
			label = "Parked",
			mode = "Ground",
			change = function (state: any)
				state.moveMode = "Parked"
			end,
		},
	}

	for _, row in changes do
		local world: any = Slides.world()
		local state: any, order: any = sliding(Slides, vector.create(0, Slides.resting, 100))
		Slides.advance(state, world, order, 1)
		row.change(state)

		local problem: string? = ends(Slides, row.label, state, world, order, row.mode)
		if problem then
			return false, problem
		end
	end

	-- Into water deep enough to swim, ahead of where it starts
	local wet: any = Slides.world()
	wet.water = function (_: number, z: number): number?
		if z < WATER_FROM then
			return Slides.floor + SURFACE
		end

		return nil
	end

	local swimmer: any, swimOrder: any = sliding(Slides, vector.create(0, Slides.resting, WATER_FROM + 1))
	local swam: string? = ends(Slides, "into the water", swimmer, wet, swimOrder, "Swim")
	if swam then
		return false, swam
	end

	-- Onto a ladder across the lane ahead
	local climbing: any = Slides.world()
	Slides.ladder(climbing, vector.create(20, Slides.floor + LADDER.y / 2, 94), LADDER)
	local climber: any, climbOrder: any = sliding(Slides, vector.create(20, Slides.resting, 100))
	local climbed: string? = ends(Slides, "onto the ladder", climber, climbing, climbOrder, "Ladder")
	if climbed then
		return false, climbed
	end

	-- Into a mantle, a jump pressed facing the shelf within reach
	local shelf: any = Slides.shelf
	local face: number = shelf.center.z + shelf.size.z / 2
	local world: any = Slides.world()
	local mantler: any, mantleOrder: any = sliding(Slides, vector.create(shelf.center.x, Slides.resting, face + 6))

	for _ = 1, LIMIT do
		local gap: number = mantler.position.z - Slides.settings().radius - face
		if gap <= world.settings.mantleReach then
			break
		end

		Slides.advance(mantler, world, mantleOrder, 1)
	end

	mantleOrder.jump, mantleOrder.pressed.jump = true, true

	return Slides.verdict(ends(Slides, "into a mantle", mantler, world, mantleOrder, "Mantle"))
end
