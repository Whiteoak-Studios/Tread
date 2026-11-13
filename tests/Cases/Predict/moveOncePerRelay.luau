--[[
    A Move goes out once a relay tick, newest first, with the commands made
    since the last and the two before them, the stub's acknowledgments and
    the delay in milliseconds, and no repeat ever differs from its first copy
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

-- Why a Move's numbers are not the ones listed, or nil
local function numbered(move: any, want: { number }, label: string): string?
	if #move.numbers ~= #want then
		return `{label} carried {#move.numbers} commands, not {#want}`
	end

	for index: number, number: number in want do
		if move.numbers[index] ~= number then
			return `{label}'s command {index} was {move.numbers[index]}, not {number}`
		end
	end

	if move.command ~= want[1] then
		return `{label} named {move.command} as its newest, not {want[1]}`
	end

	return nil
end

return function (): (boolean, string | nil)
	-- At a relay rate equal to the simulation rate, every tick sends one Move
	local rig: any = Harness.new()
	rig.spawn()
	rig.frames(5)

	local each: { { number } } = { { 1 }, { 2, 1 }, { 3, 2, 1 }, { 4, 3, 2 }, { 5, 4, 3 } }
	if #rig.moves ~= #each then
		return false, `Five ticks sent {#rig.moves} Moves, not 5`
	end

	for index: number, want: { number } in each do
		local move: any = rig.moves[index]
		local wrong: string? = numbered(move, want, `Move {index}`)
		if wrong then
			return false, wrong
		elseif move.acknowledged ~= 7 or move.received ~= 3 then
			return false, `Move {index} acknowledged {move.acknowledged} and {move.received}, not the stub's 7 and 3`
		elseif move.delay ~= 150 then
			return false, `Move {index} reported a delay of {move.delay} ms, not the stub's 150`
		end
	end

	-- At half the simulation rate, every second tick sends one with its two commands and the two before them
	local half: any = Harness.new({ relay = 10 })
	half.spawn()
	half.frames(6)

	local halves: { { number } } = { { 2, 1 }, { 4, 3, 2, 1 }, { 6, 5, 4, 3 } }
	if #half.moves ~= #halves then
		return false, `Six ticks at half the relay rate sent {#half.moves} Moves, not 3`
	end

	for index: number, want: { number } in halves do
		local wrong: string? = numbered(half.moves[index], want, `The half rate's Move {index}`)
		if wrong then
			return false, wrong
		end
	end

	-- A frame that owes three ticks sends a Move for each
	local burst: any = Harness.new()
	burst.spawn()
	burst.frames(1, burst.delta * 3.5)
	if #burst.moves ~= 3 or burst.samples ~= 3 then
		return false, `A frame of 3.5 ticks sent {#burst.moves} Moves from {burst.samples} samples, not 3 from 3`
	end

	if rig.tampered or half.tampered or burst.tampered then
		return false, "A repeated command differed from its first copy, which the server reports as tampering"
	end

	return true, nil
end
