--[[
    The client parallel probes beside G5's bots: every real player on G5's
    team and set down beside its first bot, then P6's window over one run of
    the load and P8's over another, each client's line printed as it comes
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local ClientLines = require(ServerScriptService.Server.Bots.ClientLines)
local Config = require(ServerScriptService.Server.Bots.Config)
local Fleet = require(ServerScriptService.Server.Bots.Fleet)
local Game = require(ServerScriptService.Server.Game)
local Run = require(ServerScriptService.Server.Bots.Run)

local TIMING: Config.Timing = require(ServerScriptService.Server.Config.ClientParallel).timing
local CORES: string = require(ServerScriptService.Server.Config.ClientParallel).attributes.cores
local BEND: string = require(ServerScriptService.Server.Config.ClientParallel).attributes.bend
local RATE: { perSecond: number, burst: number } = require(ServerScriptService.Server.Config.ClientParallel).rate
local WAIT: number = require(ServerScriptService.Server.Config.ClientParallel).wait
local TEAM: number? = require(ServerScriptService.Server.Bots.Config).scenarios.G5.groups[1].team
local BESIDE: number = require(ServerScriptService.Server.Config.ClientCost).beside
local LIFT: number = require(ServerScriptService.Server.Config.ClientCost).lift
local LOAD: string = "G5" -- The bot harness's load each window is measured beside
local SEPARATOR: string = "; " -- Between the parts of one line

-- Sets every real player holding a character down beside the first bot built, each a further step along X
local function setDown(entries: { any })
	local first: Fleet.Entry? = entries[1]
	if not first then
		error(`{LOAD} built no bot to set the real players down beside`, 0)
	end

	local feet: Vector3 = first.character:getState().root
	for index: number, player: Player in Players:GetPlayers() do
		local character: Tread.Character? = Game.characterOf(player)
		if character then
			character:teleport(CFrame.new(feet + Vector3.new(BESIDE * index, LIFT, 0)))
		end
	end
end

--[[
    One probe's window on its attribute beside one run of the load, giving
    whether the run drove and cleaned up with every real player's line in
    and measured, and its line with every problem the window met
--]]

local function probed(attribute: string): (boolean, string)
	local window: ClientLines.Window = ClientLines.new(attribute, WAIT)
	local stop: () -> () = ClientLines.listen(window, RATE)
	local probe: Run.Probe = ClientLines.probe(window, setDown)
	local ran: boolean, passed: any, line: any = pcall(Run.run, LOAD, TIMING, probe, nil)

	-- Everything it set goes, whatever the run did
	stop()

	if not ran then
		return false, `{attribute}: it threw: {passed}`
	elseif #window.problems > 0 then
		return false, `{line}{SEPARATOR}{table.concat(window.problems, SEPARATOR)}`
	end

	return passed, line
end

return function (): (boolean, string | nil)
	if TEAM == nil then
		return false, `{LOAD}'s first group names no team for the real players to share`
	end

	local teamed: { Tread.Character } = {}
	for _, player: Player in Players:GetPlayers() do
		local character: Tread.Character? = Game.characterOf(player)
		if character then
			character:setTeam(TEAM)
			table.insert(teamed, character)
		end
	end

	if #teamed == 0 then
		return false, "no real player has a character to run the client parallel probes on"
	end

	-- Both probes run whatever the first did, so one window's failure still leaves the other's figures
	local ran: boolean, passed: any, line: any = pcall(function (): (boolean, string)
		local all: boolean = true
		local lines: { string } = {}
		for _, attribute: string in { CORES, BEND } do
			local ok: boolean, probedLine: string = probed(attribute)
			all = all and ok
			table.insert(lines, probedLine)
		end

		return all, table.concat(lines, SEPARATOR)
	end)

	for _, character: Tread.Character in teamed do
		-- A character destroyed during the run has no team left to take back
		pcall(character.setTeam, character, nil)
	end

	if not ran then
		return false, `it threw: {passed}`
	end

	return passed, line
end
