--[[
    A crouch press starts no slide at a walk's 10 studs/s, below the start,
    inside the cooldown, with allow.slide or allow.crouch cleared by the
    rules, downed, in Noclip or Parked, or with no slide in the step block
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local SPRINT: number = 18
local WALK: number = 10

-- One refusal: the world's rules and settings, what the body is before the press, and what the press must leave
type Row = {
	label: string,
	speed: number,
	clear: string?, -- The permit the rules clear
	before: ((state: any) -> ())?,
	plain: boolean?, -- The step block with no slide
}

local ROWS: { Row } = {
	{ label = "at a walk", speed = WALK },
	{
		label = "inside the cooldown",
		speed = SPRINT,
		before = function (state: any)
			state.slideCooldown = 2
		end,
	},
	{ label = "with allow.slide cleared", speed = SPRINT, clear = "slide" },
	{ label = "with allow.crouch cleared", speed = SPRINT, clear = "crouch" },
	{
		label = "downed",
		speed = SPRINT,
		before = function (state: any)
			state.posture = "Downed"
		end,
	},
	{
		label = "in Noclip",
		speed = SPRINT,
		before = function (state: any)
			state.moveMode = "Noclip"
		end,
	},
	{
		label = "Parked",
		speed = SPRINT,
		before = function (state: any)
			state.moveMode = "Parked"
		end,
	},
	{ label = "with no slide in the step block", speed = SPRINT, plain = true },
}

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local Scene: any = Environment.load(SCENE)

	for _, row: Row in ROWS do
		local permits: { boolean } = {}
		local settings: any = Slides.settings()
		if row.plain then
			settings = Scene.settings
		end

		local world: any = Slides.world(settings, function (_: any, allow: any): number
			table.insert(permits, allow.slide)
			if row.clear then
				allow[row.clear] = false
			end

			return math.huge
		end)

		-- A body on the floor moving ahead at the row's speed, as a walk or a sprint leaves it
		local state: any = Slides.state(vector.create(0, Slides.resting, 100), true)
		state.velocity = vector.create(0, 0, -row.speed)
		state.groundTicks = 10
		local before: ((state: any) -> ())? = row.before
		if before then
			before(state)
		end

		local order: any = Slides.command()
		order.forward = 1
		order.sprint = row.speed == SPRINT
		Slides.crouch(state, world, order)

		if state.mode == "Slide" then
			return false, `A crouch press {row.label} started a slide`
		elseif row.plain and permits[1] ~= false then
			return false, `allow.slide was {permits[1]} with no slide in the step block`
		end
	end

	-- The cooldown counts down a tick at a time, and a press once it has run out starts one
	local world: any = Slides.world()
	local state: any = Slides.state(vector.create(0, Slides.resting, 100), true)
	state.velocity = vector.create(0, 0, -SPRINT)
	state.groundTicks = 10
	state.slideCooldown = 2

	local order: any = Slides.command()
	order.forward = 1
	order.sprint = true
	Slides.advance(state, world, order, 1)
	if state.slideCooldown ~= 1 then
		return false, `A tick took the cooldown from 2 to {state.slideCooldown}, not 1`
	end

	Slides.crouch(state, world, order)

	return Slides.verdict(Slides.is("the mode once the cooldown ran out", state.mode, "Slide"))
end
