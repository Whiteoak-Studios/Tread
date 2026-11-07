--[[
    A replay of the owner's prediction reaches the client's correction
    callback with the size and flag prediction gives its own callbacks
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local OWN: number = 9
local TICK: number = 100
local FRAMES: number = 4
local REPLAYED: number = 2 -- The command the server's state answers for, which the client predicted
local OFFSET: vector = vector.create(5, 0, 0) -- Where the server's state sits from the spawn, past every tolerance

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle

	local corrections: { { size: number, flagged: boolean } } = {}
	local predicted: { { size: number, flagged: boolean } } = {}
	handle:onCorrected(function (size: number, flagged: boolean)
		table.insert(corrections, { size = size, flagged = flagged })
	end)
	rig.Predict.onCorrected(function (size: number, flagged: boolean)
		table.insert(predicted, { size = size, flagged = flagged })
	end)

	local at: vector = vector.create(0, 50, 0)
	rig.handshake()
	rig.own(OWN, 1)
	rig.owner(rig.body(at, 0, TICK))
	rig.frames(FRAMES)

	rig.owner(rig.body(at + OFFSET, REPLAYED, TICK + REPLAYED))

	if #predicted ~= 1 then
		return false, `The server's state past the tolerance made {#predicted} replays, not 1`
	elseif #corrections ~= 1 then
		return false, `The replay reached the client's callback {#corrections} times, not once`
	elseif corrections[1].size ~= predicted[1].size or corrections[1].flagged ~= predicted[1].flagged then
		local got: string = `{corrections[1].size} and {corrections[1].flagged}`
		return false, `The client's callback heard {got}, where prediction gave {predicted[1].size}`
	elseif not (corrections[1].size > 0) then
		return false, `A replay 5 studs off told a size of {corrections[1].size}`
	end

	return true, nil
end
