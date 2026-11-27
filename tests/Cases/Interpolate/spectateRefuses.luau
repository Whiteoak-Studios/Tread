--[[
    Interpolate refuses a start with no client world, a restart, a withheld
    block or an occupant read before start, a restart at no u16 tick, a
    withheld block that isn't one, and an occupant of a slot outside the
    table
--]]

--!strict
local Environment = require("../../Environment")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local INTERPOLATE: string = "src/Client/Interpolate.luau"
local WIRE: number = 2 ^ 16

-- Whether a call errors
local function refuses(call: (...any) -> ...any, ...: any): boolean
	return not pcall(call, ...)
end

return function (): (boolean, string | nil)
	local fresh: any = Environment.load(INTERPOLATE)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate

	local early: { [string]: () -> () } = {
		restart = function ()
			fresh.restart(0)
		end,
		withheld = function ()
			fresh.withheld(buffer.create(8))
		end,
		occupant = function ()
			fresh.occupant(0)
		end,
	}

	for member: string, call: () -> () in early do
		if not refuses(call) then
			return false, `Interpolate.{member} ran before Interpolate.start`
		end
	end

	for _, world: any in { false, viewer.gravity, "world" } do
		if not refuses(fresh.start, viewer.settings, viewer.rates, viewer.limits, {}, world) then
			return false, `Interpolate.start took {world} as the client's world`
		end
	end

	for _, tick: any in { -1, WIRE, 1.5, 0 / 0 } do
		if not refuses(Interpolate.restart, tick) then
			return false, `Interpolate.restart took a tick of {tick}`
		end
	end

	-- 7 B, short of a header, and a block with a hide in it
	if not refuses(Interpolate.withheld, buffer.create(7)) then
		return false, "A 7 B withheld block was read"
	elseif not refuses(viewer.withhold, { tick = 1, hides = { { slot = 1, generation = 1 } } }) then
		return false, "A withheld block with a hide was read"
	end

	for _, slot: number in { -1, viewer.Constants.SLOTS, 2.5 } do
		if not refuses(Interpolate.occupant, slot) then
			return false, `Interpolate.occupant read slot {slot}`
		end
	end

	return true, nil
end
