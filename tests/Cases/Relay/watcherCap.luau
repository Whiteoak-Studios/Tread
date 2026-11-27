--[[
    A target takes 31 watchers, each copied its blocks; a 32nd is refused
    with an error naming the target, raised once every viewer has had its
    turn, and gets nothing, while the 31 keep theirs
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local MOST: number = 31
local NEAR: vector = vector.create(20, 0, 0)
local AWAY: vector = vector.create(4000, 0, 0) -- Past the target's relevancy, where the moderators stand
local STRIDE: vector = vector.create(0, 0, 0.5)

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local target: any = harness:viewer("Spectated")
	local slot: number = harness:spawn("Player", NEAR)

	local watchers: { any } = {}
	for index: number = 1, MOST do
		local watcher: any = harness:viewer(`Moderator {index}`)
		watcher.viewer.position = AWAY
		harness:watch(watcher, target)
		table.insert(watchers, watcher)
	end

	harness:run()
	for _, watcher: any in watchers do
		if watcher.drawn[slot] == nil then
			return false, `{watcher.viewer.key.Name} of {MOST} watchers was not copied the target's reveal`
		end
	end

	-- A latecomer last in the viewers' list, one past what a target takes
	local extra: any = harness:viewer("Extra")
	extra.viewer.position = AWAY
	harness:watch(extra, target)
	harness.states[slot].position += STRIDE

	local passed: boolean, message: any = pcall(harness.run, harness)
	if passed then
		return false, "A 32nd watcher of one target was taken"
	elseif not string.find(tostring(message), target.viewer.key.Name, 1, true) then
		return false, `The refusal of a 32nd watcher did not name the target: {message}`
	elseif #extra.seen.sizes ~= 0 then
		return false, "The refused watcher was copied the target's blocks"
	end

	for _, watcher: any in watchers do
		if Harness.count(watcher.seen.records, slot) ~= 1 then
			return false, `{watcher.viewer.key.Name} lost its copy when a 32nd watcher was refused`
		end
	end

	return true, nil
end
