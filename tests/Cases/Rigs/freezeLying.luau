--[[
    A freeze changes nothing about whether a root is written: a rig lying
    Downed at rest joins no frame's move while frozen or at a thaw in place,
    a standing one keeps its nudge, and one frozen mid-settle still settles
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local LYING: number = 1 -- Posed Downed from the first frame, so at rest when it freezes
local STANDING: number = 2 -- Posed standing, and frozen beside it
local SETTLING: number = 3 -- Lies down while its root stands raised, and freezes before the move that brings it down
local TWIN: number = 4 -- Posed as the settling rig is, at the same place, and never frozen
local DISTANCE: number = 4 -- Studs from the eye, inside every detail range
local LAY: vector = vector.create(-40, 7.5, 120) -- Where the lying rig lies
local MOVED: vector = vector.create(-38, 7.5, 121) -- Where its second thaw puts it
local STOOD: vector = vector.create(10, 2, -5) -- Where the standing rig stands
local SETTLED: vector = vector.create(25, 0, 30) -- Where the settling rig and its twin lie down
local NUDGE: number = 0.001 -- Studs a still rig's root rises on alternate frames, as the pool's constant gives it
local TOLERANCE: number = 1e-4 -- Studs, a tenth of the nudge, since a CFrame holds 32-bit floats
local FROZEN_FRAMES: number = 6 -- Frames run with the three rigs frozen

return function (): (boolean, string | nil)
	-- Lune's RunService has no PreSimulation and its Workspace no BulkMoveTo, which a drawn rig needs. Lune takes one
	-- registration of each a run, so a case that ran first may have made it
	pcall(roblox.implementProperty, "RunService", "PreSimulation", function (_: any): any
		return {
			Connect = function (_: any, _: () -> ()): any
				return { Disconnect = function (_: any) end }
			end,
		}
	end)
	pcall(roblox.implementMethod, "Workspace", "BulkMoveTo", function (_: any, parts: { any }, cframes: { any }, _: any)
		for index: number, part: any in parts do
			part.CFrame = cframes[index]
		end
	end)

	-- Lune loads no animation, so Animate's stand-in plays nothing
	local function nothing(_: any) end
	local Animate: { [string]: any } = {
		check = nothing,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, _: any): any
			return { rig = rig, tracks = {} }
		end,
		speed = nothing,
		stop = nothing,
		detail = nothing,
		pose = nothing,
		aim = nothing,
		plant = nothing,
		layer = nothing,
		watch = nothing,
		release = nothing,
		markers = function (_: any): { string }
			return {}
		end,
	}

	local Rigs = Environment.load(RIGS, { [ANIMATE] = Animate })
	local Rig = Environment.load(RIG)
	local State = Environment.load(STATE)

	local rigs: any = Rigs.new(Rig.settings({}), Rig.drawDistance, Rig.collision())

	-- Each frame's move writes down the rigs whose roots it takes, by their slot
	local moves: { [number]: number } = { [LYING] = 0, [STANDING] = 0, [SETTLING] = 0, [TWIN] = 0 }
	local slotOf: { [any]: number } = {}
	local move: any = rigs._move
	rigs._move = function (self: any)
		for _, entry: any in self._queued do
			moves[slotOf[entry.rig]] += 1
		end

		move(self)
	end

	local models: { [number]: any } = {}
	for _, slot: number in { LYING, STANDING, SETTLING, TWIN } do
		models[slot] = rigs:checkout(slot, {})
		slotOf[models[slot]] = slot
	end

	local function state(posture: string, place: vector): any
		local made = State.new()
		made.mode = "Ground"
		made.posture = posture
		made.position = place

		return made
	end

	local lying = state("Downed", LAY)
	local standing = state("Stand", STOOD)
	local settling = state("Stand", SETTLED)

	-- How far a slot's root stands above the place given, less the root's own height above the soles
	local height: number = models[LYING].PrimaryPart.CFrame.Position.Y
	local function above(slot: number, place: vector): number
		return models[slot].PrimaryPart.CFrame.Position.Y - place.y - height
	end

	-- Two frames of poses: the lying rig is on its target and out of the second move, and the others stand raised
	for _ = 1, 2 do
		rigs:pose(LYING, lying, DISTANCE, 0)
		rigs:pose(STANDING, standing, DISTANCE, 0)
		rigs:pose(SETTLING, settling, DISTANCE, 0)
		rigs:pose(TWIN, settling, DISTANCE, 0)
		rigs:frame()
	end

	if moves[LYING] ~= 1 or math.abs(above(LYING, LAY)) > TOLERANCE then
		return false, `Before any freeze the lying rig was in {moves[LYING]} moves, not the one that placed it`
	elseif math.abs(above(SETTLING, SETTLED) - NUDGE) > TOLERANCE then
		return false, "The settling rig's root didn't stand raised before it lay down, so no settle is tested"
	end

	-- The settling rig and its twin lie down with their roots raised, and three rigs freeze before the frame's end
	settling.posture = "Downed"
	rigs:pose(LYING, lying, DISTANCE, 0)
	rigs:pose(STANDING, standing, DISTANCE, 0)
	rigs:pose(SETTLING, settling, DISTANCE, 0)
	rigs:pose(TWIN, settling, DISTANCE, 0)

	for _, slot: number in { LYING, STANDING, SETTLING } do
		if rigs:freeze(slot) ~= true then
			return false, `Rigs.freeze refused slot {slot}'s drawn rig`
		end
	end
	rigs:frame()

	-- 1) Frozen: the lying rig is in no move, the standing one in every move, and the settling one settled as its twin
	local stood: number = moves[STANDING]
	local settled: number = moves[SETTLING]
	for frame: number = 1, FROZEN_FRAMES do
		rigs:pose(TWIN, settling, DISTANCE, 0)
		rigs:frame()

		local wanted: number = frame % 2 == 1 and NUDGE or 0
		if moves[LYING] ~= 1 or math.abs(above(LYING, LAY)) > TOLERANCE then
			return false, `Frozen frame {frame} wrote the root of a rig frozen lying at rest`
		elseif moves[STANDING] ~= stood + frame or math.abs(above(STANDING, STOOD) - wanted) > TOLERANCE then
			return false, `Frozen frame {frame} left the standing rig {above(STANDING, STOOD)} studs up, not {wanted}`
		elseif moves[SETTLING] ~= settled or moves[SETTLING] ~= moves[TWIN] then
			return false, `The rig frozen mid-settle was in {moves[SETTLING]} moves, and its twin in {moves[TWIN]}`
		elseif math.abs(above(SETTLING, SETTLED)) > TOLERANCE or math.abs(above(TWIN, SETTLED)) > TOLERANCE then
			return false, `Frozen frame {frame} left the rig frozen mid-settle off the target its twin lies on`
		end
	end

	-- 2) A thaw pose at the same lying place writes nothing
	rigs:pose(LYING, lying, DISTANCE, 0)
	rigs:pose(TWIN, settling, DISTANCE, 0)
	rigs:frame()
	if rigs._slots[LYING].frozen or moves[LYING] ~= 1 then
		return false, `A thaw pose where the rig already lay put its root in a move, {moves[LYING]} in all`
	end

	-- 3) Frozen again and thawed at a new place, it moves there once and lies still again
	lying.position = MOVED
	if rigs:freeze(LYING) ~= true then
		return false, "Rigs.freeze refused the lying rig a second time"
	end

	rigs:frame()
	rigs:pose(LYING, lying, DISTANCE, 0)
	rigs:frame()
	if moves[LYING] ~= 2 or math.abs(above(LYING, MOVED)) > TOLERANCE then
		return false, `A thaw pose at a new place left the rig in {moves[LYING]} moves, {above(LYING, MOVED)} studs up`
	end

	rigs:pose(LYING, lying, DISTANCE, 0)
	rigs:frame()
	if moves[LYING] ~= 2 then
		return false, "A lying rig thawed at a new place was written again once it lay there"
	end

	rigs:destroy()

	return true, nil
end
