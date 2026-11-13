--[[
    A body falling in an empty scene steps each tick under that tick's
    gravity across a change, and a replay from before the change steps its
    ticks under the gravity each had and ends each where the first run did
--]]

--!strict
local Environment = require("../../Environment")

local STEP: string = "src/Step/init.luau"
local WORLD: string = "src/Step/World.luau"
local STATE: string = "src/Step/State.luau"
local MATH: string = "src/Step/Math.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"

local HIGH: number = 500 -- Studs up where the fall starts, clear of everything in an empty scene
local TOSS: number = 2 -- Studs/s up it starts at, under a tick of either gravity, so it falls from the first tick
local TICKS: number = 12 -- Ticks 1 on, which drop it about 9.4 studs to under 26 studs/s
local CHANGE_AT: number = 6
local CHANGED: number = 30 -- Studs/s², the gravity from CHANGE_AT on
local REPLAY_FROM: number = 4 -- The replay's first tick, run from the state the tick before it left
local REPLAY_TO: number = 8

-- A command with no input, numbered as the tick it runs on
local function newCommand(number: number): any
	return {
		number = number,
		forward = 0,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		pressed = { jump = false, crouch = false, sprint = false, aim = false },
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	}
end

return function (): (boolean, string | nil)
	local Step: any = Environment.load(STEP)
	local World: any = Environment.load(WORLD)
	local State: any = Environment.load(STATE)
	local Math: any = Environment.load(MATH)
	local Scene: any = Environment.load(SCENE)
	local Casts: any = Environment.load(CASTS)

	local world: any = Scene.world(Casts({}))
	local base: number = Scene.settings.gravity
	local body: any = Scene.state(vector.create(0, HIGH, 0), false)
	body.velocity = vector.create(0, TOSS, 0)

	-- The state each tick of the first run ended on, by tick
	local after: { any } = {}

	-- 1) The first run, the change made during the tick before it, as the server takes a call
	for tick: number = 1, TICKS do
		world.tick = tick
		world.clock = tick

		local last: number = body.velocity.y
		Step.advance(body, newCommand(tick), world)

		-- The air's update as the step makes it: a tick of gravity off its speed, held in a vector, on the quantum
		local gravity: number = tick < CHANGE_AT and base or CHANGED
		local speed: number = Math.quantizeVelocity(vector.create(0, last - gravity * world.delta, 0).y)
		if body.velocity.y ~= speed then
			return false,
				`Tick {tick} fell at {body.velocity.y}, where {speed} under a gravity of {gravity} was expected`
		end

		local kept: any = State.new()
		State.copy(body, kept)
		after[tick] = kept

		if tick == CHANGE_AT - 1 then
			World.setGravity(world, CHANGED, CHANGE_AT)
		end
	end

	-- 2) The replay, with the change already held, as the owner's prediction replays its held commands
	local replay: any = State.new()
	State.copy(after[REPLAY_FROM - 1], replay)

	for tick: number = REPLAY_FROM, REPLAY_TO do
		world.tick = tick
		world.clock = tick
		Step.advance(replay, newCommand(tick), world)

		local first: any = after[tick]
		if replay.position ~= first.position or replay.velocity ~= first.velocity then
			local replayed: string = `{replay.position} moving {replay.velocity}`
			local ran: string = `{first.position} moving {first.velocity}`

			return false, `The replay's tick {tick} ended at {replayed}, where the first run's ended at {ran}`
		end
	end

	return true, nil
end
