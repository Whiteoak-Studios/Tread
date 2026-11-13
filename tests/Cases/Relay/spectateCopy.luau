--[[
    A spectated target's blocks go to it and each moderator watching it in
    one send, the same bytes to every one, while a watcher gets no blocks of
    its own and counts as sent nothing of its own view until it stops
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local NEAR_TARGET: vector = vector.create(20, 0, 0)
local AWAY: vector = vector.create(4000, 0, 0) -- Past the target's relevancy, where the moderators stand
local NEAR_AWAY: vector = vector.create(4010, 0, 0)
local STRIDE: vector = vector.create(0, 0, 0.5)
local TICKS: number = 5
local RECIPIENTS: number = 3 -- The target and its two watchers

-- The list's numbers in order, as one string to compare
local function joined(list: { number }): string
	return table.concat(list, ",")
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(true)
	local target: any = harness:viewer("Target")
	local first: any = harness:viewer("First")
	local second: any = harness:viewer("Second")
	first.viewer.position = AWAY
	second.viewer.position = AWAY

	local seen: number = harness:spawn("Player", NEAR_TARGET)
	local unseen: number = harness:spawn("Player", NEAR_AWAY)

	harness:run()
	if target.drawn[seen] == nil or first.drawn[unseen] == nil then
		return false, "The viewers were not each revealed the character beside them"
	end

	harness:watch(first, target)
	harness:watch(second, target)
	Harness.Relay.revealAll(target.viewer.key)

	for tick: number = 1, TICKS do
		harness.states[seen].position += STRIDE
		harness.states[unseen].position += STRIDE
		harness:run()

		if #harness.sends == 0 then
			return false, `Tick {tick} sent the target nothing`
		end

		for _, keys: { any } in harness.sends do
			if
				#keys ~= RECIPIENTS
				or keys[1] ~= target.viewer.key
				or not table.find(keys, first.viewer.key)
				or not table.find(keys, second.viewer.key)
			then
				return false, `Tick {tick} sent a block to {#keys} keys, not to the target and its watchers at once`
			end
		end

		for _, watcher: any in { first, second } do
			local copy: any = watcher.seen
			local name: string = watcher.viewer.key.Name

			if joined(copy.sizes) ~= joined(target.seen.sizes) then
				return false, `Tick {tick}'s copy to {name} was {joined(copy.sizes)} B, not the target's blocks`
			elseif joined(copy.sequences) ~= joined(target.seen.sequences) then
				return false, `Tick {tick}'s copy to {name} carried other sequences than the target's`
			elseif Harness.count(copy.records, unseen) + Harness.count(copy.reveals, unseen) ~= 0 then
				return false, `Tick {tick} sent {name} the character of its own view while it watched`
			elseif watcher.drawn[seen] == nil then
				return false, `{name} was never revealed the character the target is sent`
			end
		end

		if Harness.Relay.isSent(first.viewer.key, unseen) then
			return false, "A watcher counted as sent a character of its own view"
		elseif table.find(Harness.Relay.viewersOf(unseen), first.viewer.key) then
			return false, "A watcher was one of the viewers of a character of its own view"
		end
	end

	-- Its spectate over, its own view runs again and the target's blocks go to the other watcher alone
	harness:watch(first, nil)
	Harness.Relay.revealAll(first.viewer.key)
	harness:run()

	if Harness.count(first.seen.reveals, unseen) ~= 1 then
		return false, "The moderator's own view did not reveal its character again once the spectate ended"
	elseif not Harness.Relay.isSent(first.viewer.key, unseen) then
		return false, "The moderator did not count as sent its own view's character again"
	end

	for _, keys: { any } in harness.sends do
		if table.find(keys, first.viewer.key) and table.find(keys, target.viewer.key) then
			return false, "A block of the target's still went to the moderator once its spectate ended"
		end
	end

	return true, nil
end
