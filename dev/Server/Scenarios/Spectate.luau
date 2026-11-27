--[[
    server:spectate with the real player, parked, as the moderator and bots
    on a floor of the scenario's own as targets: its start, switch and end,
    its ends on a death, a sleep and a destroy, its refusals, the focus part
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Constants = require(Packages.Tread.Constants)
local Spectate = require(Packages.Tread.Server.Spectate)

local Game = require(ServerScriptService.Server.Game)
local Testbed = require(ServerScriptService.Server.Scenarios.Staff.Testbed)

local MAX_WATCHERS: number = Constants.MAX_WATCHERS
local CENTER: Vector3 = require(ServerScriptService.Server.Config.Staff).spectate.center
local SPACING: number = require(ServerScriptService.Server.Config.Staff).spectate.spacing
local COLUMNS: number = require(ServerScriptService.Server.Config.Staff).spectate.columns
local FOCUS: number = require(ServerScriptService.Server.Config.Staff).spectate.focus
local WINDOW: number = require(ServerScriptService.Server.Config.Staff).spectate.window
local SETTLE: number = require(ServerScriptService.Server.Config.Staff).waits.settle
local CLOSE: number = require(ServerScriptService.Server.Config.Staff).close
local NAME: string = "Spectate"
local TARGETS: number = 6 -- The spots the targets and the bot moderator take, before the watchers'
local SEPARATOR: string = "; " -- Between the parts of a report

-- Where the bot of a spot index stands on the floor's grid, row after row
local function spot(testbed: Testbed.Testbed, index: number): CFrame
	local column: number = (index - 1) % COLUMNS
	local row: number = (index - 1) // COLUMNS

	return testbed:place(Vector3.new((column - COLUMNS / 2) * SPACING, 0, row * SPACING), 0)
end

-- Whether a player's focus part, its ReplicationFocus, sits at a point
local function focusedOn(player: Player, point: Vector3): boolean
	local part: Instance? = player.ReplicationFocus
	if not part or not part:IsA("BasePart") then
		return false
	end

	return ((part :: BasePart).Position - point).Magnitude <= CLOSE
end

--[[
    Everything once the floor stands: the moderator parked, the bots built
    and landed, the spectate started, switched and ended with the focus part
    followed, its ends of its own, and each refusal
--]]

local function drive(testbed: Testbed.Testbed, problems: { string }, figures: { string })
	local server: Tread.Server = Game.get()

	local player: Player?, character: Tread.Character? = testbed:real()
	if not player or not character then
		table.insert(problems, "no real player in the server has a character to spectate from")

		return
	end

	local moderator: Player = player
	local own: Tread.Character = character
	local found: Tread.MoveMode = own:getState().moveMode

	-- 1) Parked, as the game parks a moderator, and given back its mode and its own view whatever happens
	own:setMode("Parked")
	testbed:own(function ()
		own:setMode(found)
	end)

	testbed:own(function ()
		server:spectate(moderator, nil)
	end)

	local beat: boolean, beatFailure: any = testbed:heartbeat():await()
	if not beat then
		table.insert(problems, tostring(beatFailure))

		return
	end

	local first: Tread.Character = testbed:plain("First", spot(testbed, 1))
	local second: Tread.Character = testbed:plain("Second", spot(testbed, 2))
	local dying: Tread.Character = testbed:plain("Dying", spot(testbed, 3))
	local sleeping: Tread.Character = testbed:plain("Sleeping", spot(testbed, 4))
	local destroyed: Tread.Character = testbed:plain("Destroyed", spot(testbed, 5))
	local chained: Tread.Character = testbed:plain("Chained", spot(testbed, TARGETS))
	local nobody: Volt.Bot = testbed:bare("Nobody")

	local watchers: { Tread.Character } = {}
	for index: number = 1, MAX_WATCHERS do
		table.insert(watchers, testbed:plain(`Watcher{index}`, spot(testbed, TARGETS + index)))
	end

	local bodies: { Tread.Character } = { first, second, dying, sleeping, destroyed, chained }
	table.move(watchers, 1, #watchers, #bodies + 1, bodies)

	local landed: boolean, landFailure: any = testbed
		:waitFor("every bot to land on the floor", function (_: number): boolean
			for _, body: Tread.Character in bodies do
				if not body:getState().grounded then
					return false
				end
			end

			return true
		end, SETTLE)
		:await()

	if not landed then
		table.insert(problems, tostring(landFailure))

		return
	end

	-- Whether spectatorsOf lists the moderator for a target
	local function listed(target: Tread.Character): boolean
		return table.find(server:spectatorsOf(target.player), moderator) ~= nil
	end

	-- Waits for the focus part to sit at a body, and gives the seconds it took, nil when it never did
	local function follow(what: string, body: Tread.Character): number?
		local from: number = os.clock()
		local followed: boolean, failure: any = testbed
			:waitFor(what, function (_: number): boolean
				return focusedOn(moderator, body:getState().root)
			end, FOCUS)
			:await()

		if not followed then
			table.insert(problems, tostring(failure))

			return nil
		end

		return os.clock() - from
	end

	if not follow("the moderator's focus part to sit at its own parked body", own) then
		return
	end

	-- 2) A start lists the moderator at once and on every relay tick after, and its focus part follows the target
	server:spectate(moderator, first)
	if not listed(first) then
		table.insert(problems, "spectatorsOf left the moderator out as its spectate started")
	end

	local toFirst: number? = follow("the focus part to follow the first target", first)

	local sampled: boolean, during: any = testbed
		:sample(WINDOW, function (_: number): string?
			if not listed(first) then
				return "spectatorsOf left the moderator out while it spectated"
			end

			return nil
		end)
		:await()

	if not sampled or during then
		table.insert(problems, `while it spectated: {during}`)
	else
		table.insert(figures, `the moderator listed on each of {WINDOW} relay ticks of its spectate`)
	end

	-- 3) A switch moves the listing and the focus part to the new target
	server:spectate(moderator, second)
	if listed(first) or not listed(second) then
		table.insert(problems, "after the switch spectatorsOf did not list the moderator for the new target alone")
	end

	local toSecond: number? = follow("the focus part to follow the second target", second)

	-- 4) The end lists it nowhere and gives the focus part back to its own body
	server:spectate(moderator, nil)
	if listed(second) or Spectate.targetOf(moderator) ~= nil then
		table.insert(problems, "after the end spectatorsOf still listed the moderator, or it still watched")
	end

	local toOwn: number? = follow("the focus part to come back to the moderator's own body", own)

	if toFirst and toSecond and toOwn then
		table.insert(
			figures,
			string.format("the focus part followed in %.2f, %.2f and %.2f s", toFirst, toSecond, toOwn)
		)
	end

	-- 5) A spectate ends on its own when its target dies, sleeps or is destroyed
	local endings: number = 0
	local ends: number = 0

	-- Starts a spectate of a target, ends the target, and checks the spectate ended with it
	local function endsWith(how: string, target: Tread.Character, ending: () -> ())
		ends += 1
		server:spectate(moderator, target)
		if not listed(target) then
			table.insert(problems, `spectatorsOf left the moderator out before the target {how}`)
		end

		ending()

		if listed(target) or Spectate.targetOf(moderator) ~= nil then
			table.insert(problems, `the spectate went on after its target {how}`)
		else
			endings += 1
		end
	end

	endsWith("died", dying, function ()
		local body: Tread.Body = dying:die(nil)
		testbed:own(function ()
			body:destroy()
		end)
	end)

	endsWith("slept", sleeping, function ()
		local sleeper: Tread.Sleeper? = sleeping:sleep()
		if not sleeper then
			table.insert(problems, "the sleeping target made no sleeper")

			return
		end

		local made: Tread.Sleeper = sleeper
		testbed:own(function ()
			made:destroy()
		end)
	end)

	endsWith("was destroyed", destroyed, function ()
		testbed:delete(destroyed)
	end)

	table.insert(figures, `the spectate ended with its target on {endings} of {ends}`)

	-- 6) The refusals, each of which leaves the moderator watching no one
	local refusals: number = 0
	local asked: number = 0

	local function refuse(what: string, key: Player | Tread.Bot, target: Tread.Character)
		asked += 1

		if pcall(server.spectate, server, key, target) then
			table.insert(problems, `server:spectate took {what}`)
		else
			refusals += 1
		end

		if Spectate.targetOf(moderator) ~= nil then
			table.insert(problems, `refusing {what} left the moderator watching`)
			server:spectate(moderator, nil)
		end
	end

	refuse("a moderator with no character", nobody, first)
	refuse("a moderator spectating itself", moderator, own)
	refuse("a target that died", moderator, dying)

	server:spectate(chained.player, second)
	refuse("a target who spectates", moderator, chained)
	server:spectate(chained.player, nil)

	server:spectate(chained.player, own)
	refuse("a start while being spectated", moderator, first)
	server:spectate(chained.player, nil)

	-- The first target full of bot watchers, which spectatorsOf never lists, and the real player one past them
	for _, watcher: Tread.Character in watchers do
		server:spectate(watcher.player, first)
	end

	local listedBots: number = #server:spectatorsOf(first.player)
	if listedBots > 0 then
		table.insert(problems, `spectatorsOf listed {listedBots} of the {MAX_WATCHERS} bot moderators`)
	end

	refuse(`a watcher past the {MAX_WATCHERS} a target takes`, moderator, first)

	for _, watcher: Tread.Character in watchers do
		server:spectate(watcher.player, nil)
	end

	table.insert(figures, `refused {refusals} of {asked}`)

	-- 7) Its own view back, the focus part on its own body
	follow("the focus part to sit at the moderator's own body at the end", own)
end

return function (): (boolean, string | nil)
	local built: boolean, made: any = pcall(Testbed.new, NAME, CENTER)
	if not built then
		return false, `its floor could not be laid: {made}`
	end

	local testbed: Testbed.Testbed = made
	local problems: { string } = {}
	local figures: { string } = {}

	local ran: boolean, failure: any = pcall(drive, testbed, problems, figures)
	if not ran then
		table.insert(problems, `the checks threw: {failure}`)
	end

	-- Everything it made goes, whatever the checks found
	for _, problem: string in testbed:clean() do
		table.insert(problems, problem)
	end

	local line: string = table.concat(figures, SEPARATOR)
	print(`{NAME}: {line}`)

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, line
end
