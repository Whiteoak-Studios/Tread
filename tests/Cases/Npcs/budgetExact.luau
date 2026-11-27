--[[
    Under a budget that locks two groups onto alternate ticks, a still NPC
    on odd ticks is freed from a part moved into it on the step after its
    tenth-tick wait; once the overload ends it owes nothing, a tenth frees it
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local GEOMETRY: string = "tests/Fixtures/Step/Geometry.luau"
local STEP: number = 1 -- Seconds the stand-in clock moves on at each read
local BUDGET: number = 0 -- Spent at the first read, so every NPC not forced waits
local ROOMY: number = 1e6 -- A budget no walk of two NPCs spends on the stand-in clock, once the overload ends
local SPACING: number = 20 -- Studs between the two NPCs along Z
local POST_SIZE: vector = vector.create(1, 8, 1) -- Narrower than the hull and taller, so only the exact check finds it
local SETTLED: number = 11 -- The tick after which the odd NPC stands still and the first part moves into it
local WAITED_TENTH: number = 20 -- The tenth tick the odd NPC waits on after the first part moves in
local ROOMY_TENTH: number = 30 -- The tenth tick that frees it from the second part, every NPC stepping each tick

-- Casts over the fixture's parts with one post standing at a spot
local function posted(Casts: any, Geometry: any, at: vector): any
	local parts: { any } = table.clone(Geometry.parts)
	table.insert(parts, {
		name = "Post",
		center = vector.create(at.x, Geometry.floor + POST_SIZE.y / 2, at.z),
		size = POST_SIZE,
		tilt = 0,
	})

	return Casts(parts)
end

--[[
    Steps one tick and gives why the walk broke its shape on it, or nil:
    locked, the even NPC steps on even ticks and the odd on odd, and
    otherwise both step every tick
--]]

local function run(stage: any, even: any, odd: any, tick: number, locked: boolean): string?
	stage.Npcs.step(tick)

	local evenStepped: boolean = even:getState().tick == tick
	local oddStepped: boolean = odd:getState().tick == tick
	if locked and (evenStepped ~= (tick % 2 == 0) or oddStepped ~= (tick % 2 == 1)) then
		return `On tick {tick} the even NPC stepped {evenStepped} and the odd {oddStepped}, so the lock broke`
	elseif not locked and not (evenStepped and oddStepped) then
		return `On tick {tick} the even NPC stepped {evenStepped} and the odd {oddStepped}, under a roomy budget`
	end

	return nil
end

--[[
    Moves a post into the odd NPC where it stands, then runs the ticks after
    from to freedOn, and gives why it left the part before freedOn or stayed
    in it after, or nil
--]]

local function freed(
	stage: any,
	even: any,
	odd: any,
	casts: any,
	from: number,
	freedOn: number,
	locked: boolean
): string?
	local still: vector = odd:getState().position
	stage.world.collision = casts

	for tick: number = from + 1, freedOn do
		local broke: string? = run(stage, even, odd, tick, locked)
		if broke then
			return broke
		end

		local moved: boolean = odd:getState().position ~= still
		if moved ~= (tick == freedOn) then
			return `The odd NPC moved {moved} on tick {tick}, where the part frees it on tick {freedOn}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	local Casts: any = Environment.load(CASTS)
	local Geometry: any = Environment.load(GEOMETRY)
	stage.start(stage.clock(STEP).read)

	-- The even NPC waits on tick 1 alone, so the odd one, made after it, falls a tick behind
	local even: any = stage.Npcs.create(vector.create(-20, stage.resting, SPACING / 2), 0)
	stage.Npcs.setBudget(BUDGET)
	stage.Npcs.step(1)

	local odd: any = stage.Npcs.create(vector.create(-20, stage.resting, -SPACING / 2), 0)
	for tick: number = 2, SETTLED do
		local broke: string? = run(stage, even, odd, tick, true)
		if broke then
			return false, broke
		end
	end

	-- Its every tenth tick is a wait, so only the check that wait leaves owed frees it, on its next step
	local casts: any = posted(Casts, Geometry, odd:getState().position)
	local failure: string? = freed(stage, even, odd, casts, SETTLED, WAITED_TENTH + 1, true)
	if failure then
		return false, `Locked: {failure}`
	end

	-- The overload ends, so it steps every tick, and a check still owed would free it on its first
	stage.Npcs.setBudget(ROOMY)
	casts = posted(Casts, Geometry, odd:getState().position)
	failure = freed(stage, even, odd, casts, WAITED_TENTH + 1, ROOMY_TENTH, false)
	if failure then
		return false, `Once the overload ends: {failure}`
	end

	local report: any = stage.reports[1]
	if report then
		return false, `The stage reported {report.kind} {report.measurement}, where every NPC was freed`
	end

	return true, nil
end
