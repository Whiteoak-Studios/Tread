--[[
    Holds a bot to the dev client's player: built beside the player's
    character, it sends every command the player's client sends, and each
    tick both bodies must stand in the same state but for the offset
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Move = require(Packages.Tread.Codec.Move)

local Bot = require(ServerScriptService.Server.Bots.Bot)
local Fleet = require(ServerScriptService.Server.Bots.Fleet)
local Game = require(ServerScriptService.Server.Game)

local OFFSET: number = require(ServerScriptService.Server.Bots.Config).mirror.offset
local FIND: number = require(ServerScriptService.Server.Bots.Config).mirror.find
local SETTLE: number = require(ServerScriptService.Server.Bots.Config).mirror.settle
local COMPARE: number = require(ServerScriptService.Server.Bots.Config).mirror.compare
local SEED: number = 1 -- The mirror bot has no faults, so nothing it draws ever matters
local NAME: string = "Mirror"
local SEPARATOR: string = "; " -- Between the parts of the report

-- A Move the player's client sent, kept until the bot sends it on
type Pending = {
	command: number,
	delay: number,
	wires: { any },
}

-- A real player's character standing still on the ground, or nil for none
local function stillPlayer(server: Tread.Server): (Player?, Tread.Character?)
	for _, target: Tread.Target in server:getAll() do
		-- An NPC has no player, and a bot's is no Instance
		local owner: any = (target :: any).player
		if typeof(owner) == "Instance" then
			local character: Tread.Character = target :: Tread.Character
			local state: Tread.State = character:getState()

			if state.grounded and state.velocity == Vector3.zero then
				return owner :: Player, character
			end
		end
	end

	return nil, nil
end

-- Waits a frame at a time, up to FIND seconds, for a real player's character standing still
local function waitForStill(server: Tread.Server): (Player?, Tread.Character?)
	local deadline: number = os.clock() + FIND

	while os.clock() < deadline do
		local player: Player?, character: Tread.Character? = stillPlayer(server)
		if character then
			return player, character
		end

		RunService.Heartbeat:Wait()
	end

	return nil, nil
end

-- The first way the bot's state differs from the player's, the offset taken off its place, or nil when none does
local function differs(mine: Tread.State, theirs: Tread.State, offset: Vector3): string?
	local moved: Vector3 = theirs.root - offset

	if moved ~= mine.root then
		return `the player's root is {mine.root} and the bot's less the offset {moved}`
	elseif theirs.velocity ~= mine.velocity then
		return `the player's velocity is {mine.velocity} and the bot's {theirs.velocity}`
	elseif theirs.facing ~= mine.facing then
		return `the player faces {mine.facing} and the bot {theirs.facing}`
	elseif theirs.apex - offset.Y ~= mine.apex then
		return `the player's apex is {mine.apex} and the bot's less the offset {theirs.apex - offset.Y}`
	elseif theirs.grounded ~= mine.grounded or theirs.mode ~= mine.mode or theirs.posture ~= mine.posture then
		return `the player is {mine.mode} and {mine.posture} and the bot {theirs.mode} and {theirs.posture}`
	elseif theirs.moveMode ~= mine.moveMode then
		return `the player's move mode is {mine.moveMode} and the bot's {theirs.moveMode}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local server: Tread.Server = Game.get()
	local context: Bot.Context = Fleet.start()
	if #Fleet.entries() > 0 then
		return false, `another run's {#Fleet.entries()} bots are still on the server`
	end

	-- 1) A real player's character standing still, which the bot is built beside
	local player: Player?, character: Tread.Character? = waitForStill(server)
	if not player or not character then
		return false, `no real player's character stood still on the ground within {FIND} s`
	end

	local mirrored: Player = player
	local body: Tread.Character = character
	local start: Tread.State = body:getState()
	local at: CFrame = CFrame.new(start.root + Vector3.new(OFFSET, 0, 0)) * CFrame.Angles(0, start.facing, 0)
	local entry: Fleet.Entry = Fleet.add({ name = NAME, group = NAME, at = at, steer = nil, faults = nil, seed = SEED })

	local guide: string = `hold still for {SETTLE} s, then move about the open plaza, away from +X, for {COMPARE} s`
	print(`BotsMirror: built {NAME} {OFFSET} studs along X from {mirrored.Name}'s character; {guide}`)

	-- 2) Every Move the player's client sends, sent on as the bot's in the same frame, before the next tick's decode
	local Network = require(Packages.Tread.Network.Server) -- Tread's own scope, whose Moves the hook hears
	local incoming: Move.Incoming = Move.incoming()
	local pending: { Pending } = {}
	local mirroring: boolean = true
	local scheduled: boolean = false
	local forwarded: number, refused: number = 0, 0

	local function forward()
		scheduled = false

		for _, move: Pending in pending do
			if not mirroring then
				break
			end

			local failed: number? =
				Move.decode(move.command, 0, 0, move.delay, move.wires, context.layout, context.limits, incoming)
			if failed ~= nil then
				refused += 1
			elseif incoming.count > 0 then
				entry.bot:send(incoming.commands, incoming.count)
				forwarded += 1
			end
		end

		table.clear(pending)
	end

	-- Cleared below, once the comparison ends
	Network.hooks.afterReceive(
		"Move",
		function (from: any, command: number, _: number, _: number, delay: number, wires: { any }): boolean
			if mirroring and from == mirrored then
				table.insert(pending, { command = command, delay = delay, wires = wires })

				if not scheduled then
					scheduled = true
					task.defer(forward)
				end
			end

			return true
		end
	)

	-- 3) Each tick after the settle, both bodies held to each other, with which of them stood in for a missing command
	local playerStood: boolean, botStood: boolean = false, false
	local late: number = 0

	local stopReports: () -> () = server:onReport(function (key: (Player | Tread.Bot)?, kind: string, _: number | string)
		if kind == "standIn" and key == mirrored then
			playerStood = true
		elseif kind == "standIn" and key == entry.volt then
			botStood = true
		elseif kind == "late" and key == entry.volt then
			late += 1
		end
	end)

	local settleTicks: number = math.ceil(SETTLE * context.simulation)
	local ticks: number, compared: number, mismatched: number = 0, 0, 0
	local playerStandIns: number, botStandIns: number, oneSided: number = 0, 0, 0
	local offset: Vector3? = nil
	local first: string? = nil
	local left: boolean = false

	local stopTick: () -> () = Fleet.onTick(function (tick: number)
		local stoodPlayer: boolean, stoodBot: boolean = playerStood, botStood
		playerStood, botStood = false, false
		ticks += 1

		if ticks <= settleTicks or left then
			return
		elseif mirrored.Parent == nil then
			left = true

			return
		end

		local mine: Tread.State = body:getState()
		local theirs: Tread.State = entry.character:getState()

		-- The first tick compared fixes the offset, so the check is that both moved alike from there
		local held: Vector3 = offset or theirs.root - mine.root
		offset = held
		compared += 1

		if stoodPlayer then
			playerStandIns += 1
		end

		if stoodBot then
			botStandIns += 1
		end

		if stoodPlayer ~= stoodBot then
			oneSided += 1
		end

		local difference: string? = differs(mine, theirs, held)
		if difference then
			mismatched += 1
			first = first or `tick {tick}: {difference}`
		end
	end)

	task.wait(SETTLE + COMPARE)

	-- Everything it made goes: the hook, both listeners and the bot
	mirroring = false
	Network.hooks.afterReceive("Move", nil)
	stopTick()
	stopReports()

	local problems: { string } = Fleet.clear()
	local standIns: string = `the player stood in on {playerStandIns} and the bot on {botStandIns}`
	local copies: string = `{forwarded} Moves sent on, {refused} refused, {late} of the bot's commands late`
	local line: string =
		`{compared} ticks compared, {mismatched} differing; {standIns}, one alone on {oneSided}; {copies}`

	if left then
		table.insert(problems, `{mirrored.Name} left before the comparison ended`)
	elseif compared == 0 then
		table.insert(problems, "no tick was compared")
	elseif first then
		table.insert(problems, `the first differing {first}`)
	end

	-- The Runner prints only a verdict on a pass, so the counts print here
	print(`BotsMirror: {line}`)

	if #problems > 0 then
		return false, `{line}{SEPARATOR}{table.concat(problems, SEPARATOR)}`
	end

	return true, line
end
