--[[
    Spectate refuses a watch before start, a second start or one without
    its functions or limits, a moderator spectating itself, a target who
    spectates, a moderator someone spectates, ids and ticks past a u16, and
    a watched target's bad feed or stepped command, each changing nothing
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")

local SPECTATE: string = "src/Server/Spectate.luau"
local ID: number = 4097
local OWNER_BYTES: number = 44 -- OwnerState with both game blocks empty, the shortest a feed carries
local LONGEST_OWNER: number = 92

-- Ids and ticks a u16 doesn't hold, each with what it gets wrong
local BAD_WIRE: { [string]: any } = {
	["past the top"] = 65536,
	["below 0"] = -1,
	["a fraction"] = 1.5,
	["NaN"] = 0 / 0,
	["infinite"] = math.huge,
	["no number"] = "1",
}

-- Limits start refuses, each with what it gets wrong
local BAD_LIMITS: { [string]: any } = {
	["a cone of 0"] = { lean = 20, headCone = 0 },
	["a NaN lean"] = { lean = 0 / 0, headCone = 75 },
	["an infinite cone"] = { lean = 20, headCone = math.huge },
	["no table"] = 75,
}

return function (): (boolean, string | nil)
	local sent: number = 0
	local function sendSpectate(_: any, _: number?, _: number)
		sent += 1
	end

	local function sendFeed(_: { any }, _: buffer) end

	local moderator: any = roblox.Instance.new("Player")
	local target: any = roblox.Instance.new("Player")
	local watcher: { Name: string } = { Name = "Watcher" }

	local Spectate: any = Environment.load(SPECTATE)
	local refused: boolean, why: string = Refuses("before Spectate.start", Spectate.watch, moderator, target, ID, 0)
	if not refused then
		return false, `A watch ran before start: {why}`
	end

	refused, why = Refuses("as functions", Spectate.start, { limits = Game.limits, sendSpectate = sendSpectate })
	if not refused then
		return false, `Spectate started with no sendFeed: {why}`
	end

	for problem: string, limits: any in BAD_LIMITS do
		local start: any = { limits = limits, sendFeed = sendFeed, sendSpectate = sendSpectate }
		refused, why = Refuses("in degrees above 0", Environment.load(SPECTATE).start, start)
		if not refused then
			return false, `Spectate started with {problem}: {why}`
		end
	end

	Spectate.start({ limits = Game.limits, sendFeed = sendFeed, sendSpectate = sendSpectate })
	refused, why =
		Refuses("runs once", Spectate.start, { limits = Game.limits, sendFeed = sendFeed, sendSpectate = sendSpectate })
	if not refused then
		return false, `Spectate started twice: {why}`
	end

	refused, why = Refuses("a moderator and a target", Spectate.watch, nil, target, ID, 0)
	if not refused then
		return false, `A watch with no moderator ran: {why}`
	end

	refused, why = Refuses("can't spectate itself", Spectate.watch, moderator, moderator, ID, 0)
	if not refused then
		return false, `A moderator spectated itself: {why}`
	end

	for problem: string, value: any in BAD_WIRE do
		refused, why = Refuses("as u16 numbers", Spectate.watch, moderator, target, value, 0)
		if not refused then
			return false, `A watch took an id {problem}: {why}`
		end

		refused, why = Refuses("as u16 numbers", Spectate.watch, moderator, target, ID, value)
		if not refused then
			return false, `A watch took a tick {problem}: {why}`
		end

		refused, why = Refuses("as a u16 number", Spectate.unwatch, moderator, value)
		if not refused then
			return false, `An unwatch took a tick {problem}: {why}`
		end

		refused, why = Refuses("as a u16 number", Spectate.leave, target, value)
		if not refused then
			return false, `A leave took a tick {problem}: {why}`
		end
	end

	if sent ~= 0 or Spectate.targetOf(moderator) ~= nil or Spectate.watchers(target) ~= nil then
		return false, "A refused watch sent a message or left a spectate behind"
	end

	-- The moderator watches the target, so neither may take part in a chain
	Spectate.watch(moderator, target, ID, 0)

	refused, why = Refuses("a moderator who spectates", Spectate.watch, watcher, moderator, ID, 1)
	if not refused then
		return false, `A moderator spectated a moderator who spectates: {why}`
	end

	refused, why = Refuses("while being spectated", Spectate.watch, target, watcher, ID, 1)
	if not refused then
		return false, `A spectated target started a spectate: {why}`
	end

	local watchers: { any }? = Spectate.watchers(target)
	if sent ~= 1 or Spectate.targetOf(watcher) ~= nil or Spectate.targetOf(target) ~= nil then
		return false, "A refused chain sent a message or started a spectate"
	elseif Spectate.watchers(moderator) ~= nil or Spectate.watchers(watcher) ~= nil then
		return false, "A refused chain listed a watcher"
	elseif not watchers or #watchers ~= 1 or watchers[1] ~= moderator then
		return false, "A refused chain changed the target's watchers"
	end

	-- A watched target's feed and stepped command are checked
	local owner: buffer = buffer.create(LONGEST_OWNER)
	local feedRefusals: { [string]: { any } } = {
		["shorter than OwnerState"] = { owner, OWNER_BYTES - 1 },
		["longer than OwnerState"] = { buffer.create(LONGEST_OWNER + 1), LONGEST_OWNER + 1 },
		["past its buffer"] = { buffer.create(OWNER_BYTES), OWNER_BYTES + 1 },
		["a fraction long"] = { owner, OWNER_BYTES + 0.5 },
		["no buffer"] = { "owner", OWNER_BYTES },
	}

	for problem: string, arguments: { any } in feedRefusals do
		refused, why = Refuses("Spectate.feed takes OwnerState", Spectate.feed, target, arguments[1], arguments[2])
		if not refused then
			return false, `A feed {problem} was sent: {why}`
		end
	end

	refused, why = Refuses("as a table", Spectate.stepped, target, 42)
	if not refused then
		return false, `A watched target stepped a command that is no table: {why}`
	end

	return true, nil
end
