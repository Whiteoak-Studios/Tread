--[[
    A frozen rider's place for the render distance is where its rig stands
    in the world, though its platform lost its copy before the hide and
    left the slot's drawn state in the platform's space
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Handle = require("../../Fixtures/Client/Handle")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"

local STAYS: number = 3 -- Stands inside the render distance, its place in its platform's space outside it
local ENDS: number = 4 -- Stands outside the render distance, its place in its platform's space inside it
local NEAR_LIFT: number = 6 -- The platform each rides
local FAR_LIFT: number = 7
local GENERATION: number = 1
local TICK: number = 50
local SETTLE: number = 6 -- Frames, a relay tick each, that take the render time past a block, with the delay
local REACH: number = 250 -- Studs the render distance is drawn in to once both are frozen

-- Each rider's platform's place, its own place in that platform's space, and so where its rig stands in the world
local NEAR_COPY: vector = vector.create(-300, 0, 0)
local NEAR_LOCAL: vector = vector.create(400, 0, 0)
local FAR_COPY: vector = vector.create(600, 0, 0)
local FAR_LOCAL: vector = vector.create(20, 0, 0)

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool

	-- Two platforms that never move, each a copy this client draws its rider on
	local function lift(id: number, at: vector): () -> ()
		return handle:addPlatform(Riders.lift(id, roblox.Vector3.new(at.x, at.y, at.z), 0, 0))
	end

	local removeNear: () -> () = lift(NEAR_LIFT, NEAR_COPY)
	local removeFar: () -> () = lift(FAR_LIFT, FAR_COPY)

	local now: number = TICK -- The relay tick the server writes its next block at

	-- Runs frames of a relay tick each, the server's tick moving on with them
	local function run(frames: number)
		rig.frames(frames)
		now += frames
	end

	rig.handshake()
	rig.slots({
		{ slot = STAYS, generation = GENERATION, rig = "A" },
		{ slot = ENDS, generation = GENERATION, rig = "A" },
	})
	rig.relay({
		tick = now,
		reveals = {
			{ slot = STAYS, generation = GENERATION, kind = "Player" },
			{ slot = ENDS, generation = GENERATION, kind = "Player" },
		},
		records = {
			{ slot = STAYS, generation = GENERATION, position = NEAR_LOCAL, platform = NEAR_LIFT },
			{ slot = ENDS, generation = GENERATION, position = FAR_LOCAL, platform = FAR_LIFT },
		},
	})
	run(SETTLE)

	-- Each rider was drawn on its platform's copy, where its rig stands from then on
	local drawn: { [number]: vector } = {}
	for _, pose: any in pool.of("pose") do
		drawn[pose.slot] = pose.position
	end

	if drawn[STAYS] ~= NEAR_COPY + NEAR_LOCAL or drawn[ENDS] ~= FAR_COPY + FAR_LOCAL then
		return false, `The riders were drawn at {drawn[STAYS]} and {drawn[ENDS]}, not on their platforms' copies`
	end

	-- Both platforms lose their copies, so no later frame poses a rider, and then anti-ESP's hides pass
	local poses: number = #pool.of("pose")
	rig.relay({
		tick = now,
		hides = {
			{ slot = STAYS, generation = GENERATION, culled = true },
			{ slot = ENDS, generation = GENERATION, culled = true },
		},
	})
	removeNear()
	removeFar()
	run(SETTLE)

	local states: any = handle._states
	if #pool.of("pose") ~= poses then
		return false, "A rider was posed after its platform lost its copy, so no unfinished state is tested"
	elseif states[STAYS].position ~= NEAR_LOCAL or states[ENDS].position ~= FAR_LOCAL then
		return false, "The riders' drawn states weren't left in their platforms' space before the hides"
	elseif #pool.of("freeze") ~= 2 or #pool.of("release") ~= 0 then
		return false, `The riders' hides anti-ESP made froze {#pool.of("freeze")} rigs, not both`
	end

	-- The render distance comes in between where each rig stands and where its state's place would put it
	handle:setRenderDistance(REACH)
	run(1)

	local releases: { any } = pool.of("release")
	if #releases ~= 1 then
		return false, `{#releases} frozen bodies ended once the render distance came in to {REACH} studs, not one`
	elseif releases[1].slot ~= ENDS then
		return false,
			`The frozen body {vector.magnitude(drawn[STAYS])} studs from the eye ended, measured from its state`
	end

	return true, nil
end
