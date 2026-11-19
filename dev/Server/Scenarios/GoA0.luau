--[[
    Sends every real player to a fresh reserved server of the A0 arm's
    place, whose program starts once a player arrives, trying each teleport
    again as Roblox's teleport guide does when it fails
--]]

--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local PLACE_ID: number = require(ServerScriptService.Server.Config.GoA0).placeId
local ATTEMPTS: number = require(ServerScriptService.Server.Config.GoA0).attempts
local RETRY_DELAY: number = require(ServerScriptService.Server.Config.GoA0).retryDelay
local FLOOD_DELAY: number = require(ServerScriptService.Server.Config.GoA0).floodDelay
local CALL_WAIT: number = require(ServerScriptService.Server.Config.GoA0).callWait
local SETTLE: number = require(ServerScriptService.Server.Config.GoA0).settle
local SEPARATOR: string = "; " -- Between the parts of one line
local LIST: string = ", " -- Between the players one part names

-- What TeleportInitFailed told of a player's teleport after its call was taken
type Failure = {
	result: Enum.TeleportResult,
	message: string,
}

-- Each player's name, in one part of a line
local function names(players: { Player }): string
	local listed: { string } = {}
	for _, player: Player in players do
		table.insert(listed, player.Name)
	end

	return table.concat(listed, LIST)
end

--[[
    Calls TeleportAsync on a thread of its own, so a call that never
    answers ends its try at its own deadline, and gives why the call
    failed, nil once it was taken
--]]

local function call(players: { Player }, options: TeleportOptions): string?
	local answered: boolean = false
	local failure: string? = nil

	-- Writes only these two locals, so a call answering after the deadline changes nothing the run reads
	task.spawn(function ()
		local taken: boolean, problem: any =
			pcall(TeleportService.TeleportAsync, TeleportService, PLACE_ID, players, options)
		if not taken then
			failure = `TeleportAsync threw: {problem}`
		end

		answered = true
	end)

	local deadline: number = os.clock() + CALL_WAIT
	while not answered and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end

	if not answered then
		return `TeleportAsync gave no answer within {CALL_WAIT} s`
	end

	return failure
end

-- Whether each player given has left this server or been told their teleport failed
local function settled(players: { Player }, failures: { [Player]: Failure }): boolean
	for _, player: Player in players do
		if player.Parent ~= nil and not failures[player] then
			return false
		end
	end

	return true
end

--[[
    Tries the teleport up to the configured attempts. A call that fails is
    tried again after the retry delay. Once one is taken, the run waits for
    each player to leave or hear of a failure: Failure and Flooded are tried
    again after the retry or flood delay, as Roblox's teleport guide does,
    and any other result ends the run. A player who left before a call for
    them is named as gone
--]]

local function send(players: { Player }, options: TeleportOptions, failures: { [Player]: Failure }): (boolean, string)
	local pending: { Player } = players
	local started: { Player } = {}
	local gone: { Player } = {}
	local tries: { string } = {}
	local made: number = 0

	-- The run's line: its head, then the players gone and each try that went wrong
	local function line(head: string): string
		local parts: { string } = { head }
		if #gone > 0 then
			table.insert(parts, `{names(gone)} left before a teleport started for them`)
		end

		for _, try: string in tries do
			table.insert(parts, try)
		end

		return table.concat(parts, SEPARATOR)
	end

	for attempt: number = 1, ATTEMPTS do
		local going: { Player } = {}
		for _, player: Player in pending do
			table.insert(player.Parent ~= nil and going or gone, player)
		end

		pending = {}
		if #going == 0 then
			break
		end

		made = attempt
		table.clear(failures)

		local delay: number = RETRY_DELAY
		local problem: string? = call(going, options)
		if problem then
			table.insert(tries, `try {attempt}: {problem}`)
			pending = going
		else
			local deadline: number = os.clock() + SETTLE
			while not settled(going, failures) and os.clock() < deadline do
				RunService.Heartbeat:Wait()
			end

			for _, player: Player in going do
				local failure: Failure? = failures[player]
				if not failure then
					table.insert(started, player)
					continue
				end

				local told: string = `{player.Name}'s teleport failed with {failure.result.Name}: {failure.message}`
				if failure.result ~= Enum.TeleportResult.Failure and failure.result ~= Enum.TeleportResult.Flooded then
					return false, line(`try {attempt}: {told}, a result no try is made again for`)
				end

				table.insert(tries, `try {attempt}: {told}`)
				table.insert(pending, player)

				if failure.result == Enum.TeleportResult.Flooded then
					delay = math.max(delay, FLOOD_DELAY)
				end
			end
		end

		if #pending > 0 and attempt < ATTEMPTS then
			task.wait(delay)
		end
	end

	if #pending > 0 then
		return false, line(`no teleport started for {names(pending)} in {ATTEMPTS} tries`)
	elseif #started == 0 then
		return false, line("no teleport started, since every player left first")
	end

	local head: string = `a teleport started for {names(started)} to reserved server {options.ReservedServerId}`
	return true, line(`{head} of place {PLACE_ID} on try {made}`)
end

return function (): (boolean, string | nil)
	if RunService:IsStudio() then
		return false,
			"it sends players to a live server of the A0 place, so it runs on a live server of the dev place only"
	end

	local players: { Player } = Players:GetPlayers()
	if #players == 0 then
		return false, "no real player is in to send to the A0 place"
	end

	-- Whiteoak TODO: TeleportAsync takes at most 50 players a call, so a server with more real players fails its
	-- every try. Calls of 50 each, all with these options, lift it
	local options: TeleportOptions = Instance.new("TeleportOptions")
	options.ReservedServerId = HttpService:GenerateGUID(false)

	-- Disconnected below, whatever the tries did
	local failures: { [Player]: Failure } = {}
	local connection: RBXScriptConnection = TeleportService.TeleportInitFailed:Connect(
		function (player: Player, result: Enum.TeleportResult, message: string)
			failures[player] = { result = result, message = message }
		end
	)

	local ran: boolean, passed: any, line: any = pcall(send, players, options, failures)

	connection:Disconnect()
	options:Destroy()

	if not ran then
		return false, `it threw: {passed}`
	elseif passed then
		print(`GoA0: {line}`)
	end

	return passed, line
end
