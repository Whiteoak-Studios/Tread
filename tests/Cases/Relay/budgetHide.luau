--[[
    A player hidden from a viewer in the run the relay budget leaves it gets
    its hide to that viewer exactly one run late, on its next turn, with no
    record of it in between, where a viewer never left gets the hide on time
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local HIDE_RUN: number = 5 -- A run the budget leaves the viewer, the third in the list, as on runs 1, 5 and 9
local STRIDE: number = 0.1 -- Studs the player moves a run, back and forth, so it always has a change to send
local PLAYER_AT: vector = vector.create(0, 0, -60)
local AWAY: vector = vector.create(3000, 0, 0)
local MODERATOR_AT: vector = vector.create(3000, 0, 3000)

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()

	for index: number = 1, 2 do
		harness:viewer(`Other{index}`).viewer.position = AWAY + vector.create(index, 0, 0)
	end

	-- The viewer the budget leaves, and one a moderator watches, so it is never left
	local viewer: any = harness:viewer("Viewer")
	local steady: any = harness:viewer("Steady")
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = MODERATOR_AT
	harness:watch(moderator, steady)

	local player: number = harness:spawn("Player", PLAYER_AT)
	Harness.Relay.setBudget(0)

	for run: number = 1, HIDE_RUN + 1 do
		harness.states[player].position += vector.create(run % 2 == 0 and -STRIDE or STRIDE, 0, 0)
		if run == HIDE_RUN then
			harness:hide(viewer, player, true)
			harness:hide(steady, player, true)
		end

		harness:run()

		local waited: boolean = false
		for _, call: any in harness.passed do
			waited = waited or call.key == viewer.viewer.key
		end

		local seen: any = viewer.seen
		if run == HIDE_RUN then
			if not waited then
				return false, `The budget did not leave the viewer on run {run}, as its order would`
			elseif #seen.sizes ~= 0 then
				return false, `The viewer left on run {run} got {#seen.sizes} blocks`
			elseif Harness.count(steady.seen.hides, player) ~= 1 then
				return false, "The viewer never left got no hide on the run the player was hidden"
			end
		elseif run == HIDE_RUN + 1 then
			if waited then
				return false, "The budget left the viewer two runs running"
			elseif Harness.count(seen.hides, player) ~= 1 then
				return false, "The viewer back from its wait got no hide of the player hidden on the run it waited"
			elseif Harness.count(seen.records, player) ~= 0 or Harness.count(steady.seen.records, player) ~= 0 then
				return false, "A record of the hidden player reached a viewer after its hide was due"
			end
		elseif run > 1 and not waited and Harness.count(seen.records, player) ~= 1 then
			return false, `The viewer got no record of the player on run {run}, before it was hidden`
		end
	end

	return true, nil
end
