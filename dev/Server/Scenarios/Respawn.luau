--[[
    Respawns each real player's character through the dev game, and passes
    when every new body's commands met the server's fresh intake, with none
    ahead, late or stood in for over a window, and the body at its spawn
--]]

--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Game = require(ServerScriptService.Server.Game)
local Spawns = require(ServerScriptService.Server.Spawns)

local SETTLE: number = require(ServerScriptService.Server.Config.Respawn).settle
local WINDOW: number = require(ServerScriptService.Server.Config.Respawn).window
local DISTANCE: number = require(ServerScriptService.Server.Config.Respawn).distance
local REFUSED: { string } = { "ahead", "late", "standIn" } -- The kinds a respawned player raises none of in the window
local SEPARATOR: string = "; " -- Between the problems in one report

type Counts = { [string]: number }

-- One respawned player's run: their reports by kind, the new character and the spawn point it was built at
type Run = {
	player: Player,
	before: Counts, -- From just before the respawn until the window opens
	window: Counts,
	character: Tread.Character?, -- nil when the respawn was refused
	spawn: Vector3,
	refusal: string?,
}

-- The real players who have a character now: an NPC has no player, and a bot's is no Instance
local function owners(server: Tread.Server): { [Player]: boolean }
	local found: { [Player]: boolean } = {}

	for _, target: Tread.Target in server:getAll() do
		local owner: any = (target :: any).player
		if typeof(owner) == "Instance" then
			found[owner] = true
		end
	end

	return found
end

-- Respawns one player's character and keeps the point it was built at, read before anything yields
local function respawn(run: Run)
	local respawned: boolean, result: any = pcall(Game.respawn, run.player)
	if not respawned then
		run.refusal = tostring(result)

		return
	end

	run.character = result

	-- The point the respawn took for them, which take hands its holder back unchanged
	local at: CFrame? = Spawns.take(run.player)
	if at then
		run.spawn = at.Position
	else
		run.refusal = "they hold no spawn point after the respawn"
	end
end

--[[
    Prints a run's line, its reports by kind in the window and before it
    and where the body stands, and adds each way it failed to the problems
--]]

local function judge(run: Run, problems: { string })
	local name: string = run.player.Name
	local window: string = HttpService:JSONEncode(run.window)
	local before: string = HttpService:JSONEncode(run.before)
	local counts: string = `in the window {window}, before it {before}`
	local character: Tread.Character? = run.character
	local refusal: string? = run.refusal

	if refusal or not character then
		print(`Respawn {name}: not checked, {refusal}, {counts}`)
		table.insert(problems, `{name} was not checked: {refusal}`)

		return
	end

	local read: boolean, state: any = pcall(character.getState, character)
	if not read then
		print(`Respawn {name}: {counts}, and its state could not be read: {state}`)
		table.insert(problems, `{name}'s new character could not be read at the window's end: {state}`)

		return
	end

	local root: Vector3 = state.root
	local distance: number = (root - run.spawn).Magnitude
	local apart: string = string.format("%.3f", distance)
	print(`Respawn {name}: {counts}, standing at {root}, {apart} studs from its spawn point {run.spawn}`)

	for _, kind: string in REFUSED do
		if run.window[kind] > 0 then
			table.insert(problems, `{name} raised {run.window[kind]} {kind} reports in the window`)
		end
	end

	if distance > DISTANCE then
		table.insert(problems, `{name}'s new body stands {apart} studs from its spawn point, past {DISTANCE}`)
	end
end

return function (): (boolean, string | nil)
	local real: { Player } = Players:GetPlayers()
	if #real == 0 then
		return false, "no real player is in the server to respawn"
	end

	local server: Tread.Server = Game.get()
	local having: { [Player]: boolean } = owners(server)
	local runs: { [Player]: Run } = {}
	local order: { Run } = {}

	for _, player: Player in real do
		if having[player] then
			local run: Run = {
				player = player,
				before = {},
				window = { ahead = 0, late = 0, standIn = 0, gap = 0 }, -- The kinds the check counts, shown at none
				character = nil,
				spawn = Vector3.zero,
				refusal = nil,
			}

			runs[player] = run
			table.insert(order, run)
		else
			print(`Respawn {player.Name}: skipped, since they have no character yet`)
		end
	end

	if #order == 0 then
		return false, "no real player in the server has a character to respawn"
	end

	local counting: boolean = false -- Whether the window has opened

	-- From before the first respawn, so a report the respawn itself raises is counted; disconnected below
	local stop: () -> () = server:onReport(function (player: (Player | Tread.Bot)?, kind: string, _: number | string)
		if typeof(player) ~= "Instance" then
			return
		end

		local run: Run? = runs[player :: Player] -- A bot is a table, so an Instance here is a Player
		if not run then
			return
		end

		local counts: Counts = run.before
		if counting then
			counts = run.window
		end

		counts[kind] = (counts[kind] or 0) + 1
	end)

	for _, run: Run in order do
		respawn(run)
	end

	task.wait(SETTLE)
	counting = true
	task.wait(WINDOW)
	stop()

	local problems: { string } = {}
	for _, run: Run in order do
		judge(run, problems)
	end

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, nil
end
