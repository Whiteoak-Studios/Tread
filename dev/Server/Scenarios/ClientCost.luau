--[[
    G5's client cost: every real player on G5's team and set down beside its
    first bot, each seed's window measured on every real client, and each
    client's line of Tread's remote-character work a frame printed
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

local FULL: Config.Timing = require(ServerScriptService.Server.Bots.Config).full
local TEAM: number? = require(ServerScriptService.Server.Bots.Config).scenarios.G5.groups[1].team
local ATTRIBUTE: string = require(ServerScriptService.Server.Config.ClientCost).attribute
local RATE: { perSecond: number, burst: number } = require(ServerScriptService.Server.Config.ClientCost).rate
local WAIT: number = require(ServerScriptService.Server.Config.ClientCost).wait
local BESIDE: number = require(ServerScriptService.Server.Config.ClientCost).beside
local LIFT: number = require(ServerScriptService.Server.Config.ClientCost).lift
local LOAD: string = "G5" -- The bot harness's load each window is measured in
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
		return false, "no real player has a character to measure the client cost on"
	end

	local window: ClientLines.Window = ClientLines.new(ATTRIBUTE, WAIT)
	local stop: () -> () = ClientLines.listen(window, RATE)
	local probe: Run.Probe = ClientLines.probe(window, setDown)
	local ran: boolean, passed: any, line: any = pcall(Run.run, LOAD, FULL, probe, nil)

	-- Everything it set goes, whatever the run did
	stop()

	for _, character: Tread.Character in teamed do
		-- A character destroyed during the run has no team left to take back
		pcall(character.setTeam, character, nil)
	end

	if not ran then
		return false, `it threw: {passed}`
	elseif #window.problems > 0 then
		return false, `{line}{SEPARATOR}{table.concat(window.problems, SEPARATOR)}`
	end

	return passed, line
end
