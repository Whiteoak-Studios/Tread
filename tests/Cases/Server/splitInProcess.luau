--[[
    With every turn in process no round is ever out, so with the split on
    nothing defers and the server sends what it does with it off, every
    message on the same Heartbeat, past the calm ticks the split needs
--]]

--!strict
local SplitSide = require("../../Fixtures/Server/SplitSide")

local TICKS: number = SplitSide.CALM + 4

type Driven = SplitSide.Driven

return function (): (boolean, string | nil)
	local off: Driven = SplitSide.new({ split = false, workers = false, checks = true })
	local on: Driven = SplitSide.new({ split = true, workers = false, checks = true })
	SplitSide.ticks(off, TICKS)
	SplitSide.ticks(on, TICKS)

	if not on.side.Tick.splitOn() or off.side.Tick.splitOn() then
		return false, "The server's start set the split other than relay.split gave it"
	end

	for beat: number, flags: number in on.flags do
		if flags ~= off.flags[beat] or bit32.band(flags, on.side.Tick.DEFERRED) ~= 0 then
			return false, `Heartbeat {beat} had the flags {flags} with the split and {off.flags[beat]} without`
		end
	end

	-- Every Owner message and block, in the order and on the Heartbeat it came
	local offArrivals: string = table.concat(off.side.arrivals, ", ")
	local onArrivals: string = table.concat(on.side.arrivals, ", ")
	if onArrivals ~= offArrivals then
		return false, `With the split in process the client heard {onArrivals}`
	elseif table.concat(on.side.blocks) ~= table.concat(off.side.blocks) then
		return false, "With the split in process the client's blocks differ"
	elseif table.concat(on.side.owners) ~= table.concat(off.side.owners) then
		return false, "With the split in process the client's Owner messages differ"
	elseif #on.side.blocks < TICKS then
		return false, `The client had {#on.side.blocks} blocks over {TICKS} ticks`
	end

	return true, nil
end
