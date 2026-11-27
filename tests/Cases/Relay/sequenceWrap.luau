--[[
    A viewer's message sequences run 1 to 65,535 and wrap to 1, so no block
    is numbered 0, which an acknowledgment uses for none, and the block
    after 65,535 is acknowledged like any other
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local LAST: number = 2 ^ 16 - 1
local SWAY: vector = vector.create(0.5, 0, 0) -- The near character moves back and forth, so every tick has a record

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", vector.create(10, 0, 0))
	local state: any = harness.states[slot]

	local expected: number = 1
	for tick: number = 1, LAST do
		state.position = vector.create(10, 0, 0) + SWAY * (tick % 2)
		harness:run()

		local sequences: { number } = client.seen.sequences
		if #sequences ~= 1 or sequences[1] ~= expected then
			return false, `Tick {tick} sent sequences {table.concat(sequences, ", ")}, not the one block {expected}`
		end

		expected += 1
	end

	-- The block after 65,535 is 1, and its reveal is acknowledged as any block's is
	local late: number = harness:spawn("Player", vector.create(-10, 0, 0))
	harness:run()

	local sequences: { number } = client.seen.sequences
	if #sequences ~= 1 or sequences[1] ~= 1 then
		return false, `After 65,535 the viewer was sent sequences {table.concat(sequences, ", ")}, not 1`
	elseif Harness.count(client.seen.reveals, late) ~= 1 then
		return false, "The block after the wrap carried no reveal of the character spawned then"
	elseif client.viewer.acknowledged ~= 1 then
		return false, `The client acknowledged {client.viewer.acknowledged} after reading block 1`
	end

	state.position += SWAY
	harness:run()

	sequences = client.seen.sequences
	if sequences[1] ~= 2 then
		return false, `The block after 1 was numbered {sequences[1]}`
	elseif Harness.count(client.seen.reveals, late) ~= 0 then
		return false, "The reveal block 1 carried rode on after the viewer acknowledged block 1"
	end

	return true, nil
end
