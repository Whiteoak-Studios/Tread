--[[
    character:setInvisible on a bot a few studs from the real player's body,
    both on a floor of the scenario's own: viewersOf holds the player before,
    on no relay tick while Invisible, and again after, a teammate's view too
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Relay = require(Packages.Tread.Server.Relay)

local Game = require(ServerScriptService.Server.Game)
local Testbed = require(ServerScriptService.Server.Scenarios.Staff.Testbed)

local CENTER: Vector3 = require(ServerScriptService.Server.Config.Staff).invisible.center
local APART: number = require(ServerScriptService.Server.Config.Staff).invisible.apart
local TEAM: number = require(ServerScriptService.Server.Config.Staff).invisible.team
local REVEAL: number = require(ServerScriptService.Server.Config.Staff).invisible.reveal
local WINDOW: number = require(ServerScriptService.Server.Config.Staff).invisible.window
local LANDING: number = require(ServerScriptService.Server.Config.Staff).waits.landing
local NAME: string = "Invisible"
local TOWARD_X: number = -math.pi / 2 -- The step's yaw that looks along +X, toward the bot
local SEPARATOR: string = "; " -- Between the parts of a report

--[[
    Everything once the floor stands: the bot and its teammate built, the
    real player brought beside them, each phase read over its relay ticks,
    and the real player sent back where it stood
--]]

local function drive(testbed: Testbed.Testbed, problems: { string }, figures: { string })
	local server: Tread.Server, _: Tread.Shared, settings: Tread.ServerSettings = Game.get()
	local seconds: number = settings.teleport.timeout + LANDING

	local player: Player?, character: Tread.Character? = testbed:real()
	if not player or not character then
		table.insert(problems, "no real player in the server has a character to stand beside the bot")

		return
	end

	local viewer: Player = player
	local body: Tread.Character = character
	local found: Tread.State = body:getState()
	local home: CFrame = CFrame.new(found.root) * CFrame.Angles(0, found.facing, 0)

	-- Sent back where it stood unless the run brought it back itself
	local returned: boolean = true
	testbed:own(function ()
		if not returned then
			body:teleport(home)
		end
	end)

	local beat: boolean, beatFailure: any = testbed:heartbeat():await()
	if not beat then
		table.insert(problems, tostring(beatFailure))

		return
	end

	-- 1) The bot a few studs along X from where the real player will stand, and a teammate of the bot's beside it
	local target: Tread.Character = testbed:plain("Target", testbed:place(Vector3.new(APART, 0, 0), 0))
	local teammate: Tread.Character = testbed:plain("Teammate", testbed:place(Vector3.new(APART, 0, APART), 0))
	local slot: number = (target :: any)._slot

	target:setTeam(TEAM)
	teammate:setTeam(TEAM)

	-- Whether the real player is sent the bot, and whether its teammate is
	local function shown(): boolean
		return table.find(server:viewersOf(target), viewer) ~= nil
	end

	local function teamed(): boolean
		return Relay.isSent(teammate.player, slot)
	end

	-- A relay tick's problem while the bot should reach both views, or nil
	local function bothSent(_: number): string?
		if not shown() then
			return "viewersOf left the real player out"
		elseif not teamed() then
			return "the bot's teammate was not sent it"
		end

		return nil
	end

	returned = false
	local went: boolean, wentFailure: any = testbed
		:teleport(body, function (_: Testbed.Snapshot): { CFrame }
			return { testbed:place(Vector3.zero, TOWARD_X) }
		end, seconds)
		:await()

	if not went then
		table.insert(problems, `the real player was not brought beside the bot: {wentFailure}`)

		return
	end

	-- 2) The bot reaches both views, anti-ESP's first test of the real player's pair included, and stays in them
	local revealedAt: number = os.clock()
	local revealed: boolean, revealFailure: any = testbed
		:waitFor("the bot to reach the real player's view and its teammate's", function (_: number): boolean
			return shown() and teamed()
		end, REVEAL)
		:await()

	if not revealed then
		table.insert(problems, tostring(revealFailure))

		return
	end

	table.insert(figures, string.format("the bot reached both views in %.2f s", os.clock() - revealedAt))

	local sampled: boolean, before: any = testbed:sample(WINDOW, bothSent):await()
	if not sampled or before then
		table.insert(problems, `before Invisible: {before}`)
	end

	-- 3) Invisible: neither view gets it, from the first relay tick on
	target:setInvisible(true)

	local hidden: boolean, during: any = testbed
		:sample(WINDOW, function (_: number): string?
			if shown() then
				return "viewersOf still held the real player"
			elseif teamed() then
				return "the bot's teammate was still sent it"
			end

			return nil
		end)
		:await()

	if not hidden or during then
		table.insert(problems, `while Invisible: {during}`)
	end

	-- 4) Visible again: back in both views once anti-ESP has tested the pair afresh, and staying there
	target:setInvisible(false)

	local backAt: number = os.clock()
	local back: boolean, backFailure: any = testbed
		:waitFor("the bot to reach both views again", function (_: number): boolean
			return shown() and teamed()
		end, REVEAL)
		:await()

	if not back then
		table.insert(problems, tostring(backFailure))
	else
		table.insert(figures, string.format("back in both views %.2f s after Invisible ended", os.clock() - backAt))

		local kept: boolean, after: any = testbed:sample(WINDOW, bothSent):await()
		if not kept or after then
			table.insert(problems, `after Invisible: {after}`)
		end
	end

	table.insert(figures, `each phase read over {WINDOW} relay ticks`)

	-- 5) The real player goes back where it stood
	local wentHome: boolean, homeFailure: any = testbed
		:teleport(body, function (_: Testbed.Snapshot): { CFrame }
			return { home }
		end, seconds)
		:await()

	if wentHome then
		returned = true
	else
		table.insert(problems, `the real player was not sent back where it stood: {homeFailure}`)
	end
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
