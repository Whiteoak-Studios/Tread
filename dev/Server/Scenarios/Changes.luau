--[[
    Checks records as changes on the running server: the real player set
    down among 20 walking bots, its Tread bytes a second from Volt over a
    window, and the frames it is observed with holding whole records alone
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Fleet = require(ServerScriptService.Server.Bots.Fleet)
local Game = require(ServerScriptService.Server.Game)
local Programs = require(ServerScriptService.Server.Bots.Programs)
local Seeded = require(ServerScriptService.Server.Bots.Seeded)

local CENTER: Vector3 = require(ServerScriptService.Server.Config.Changes).center
local FLOOR_SIZE: Vector3 = require(ServerScriptService.Server.Config.Changes).floor
local AREA: Vector2 = require(ServerScriptService.Server.Config.Changes).area
local LIFT: number = require(ServerScriptService.Server.Config.Changes).lift
local BOTS: number = require(ServerScriptService.Server.Config.Changes).bots
local SEED: number = require(ServerScriptService.Server.Config.Changes).seed
local LANDED: number = require(ServerScriptService.Server.Config.Changes).landed
local WARMUP: number = require(ServerScriptService.Server.Config.Changes).warmup
local WINDOW: number = require(ServerScriptService.Server.Config.Changes).window
local INTERVAL: number = require(ServerScriptService.Server.Config.Changes).interval
local WAIT: number = require(ServerScriptService.Server.Config.Changes).wait
local SEED_BOUND: number = 2 ^ 31 - 2 -- The largest seed a bot's own generator is drawn
local TURN: number = 2 * math.pi
local FOLDER: string = "Changes" -- The folder the run lays its floor in
local GROUP: string = "changes" -- What the fleet's entries call the run's bots
local SEPARATOR: string = "; " -- Between the problems in one report

-- What the player's observed frames have shown
type Seen = {
	frames: number,
	blocks: number,
	records: number, -- Whole records, every change expanded to one
	changes: number, -- Change records a frame's block still held, which expansion leaves none of
}

-- What one run made that its cleanup ends, whatever the run did
type Made = {
	stop: (() -> ())?,
	moved: boolean, -- Whether the player was set down, so it is respawned after
}

-- Waits a frame at a time until done says so or WAIT seconds pass, and gives whether it got there
local function waitFor(done: () -> boolean): boolean
	local deadline: number = os.clock() + WAIT
	while not done() do
		if os.clock() >= deadline then
			return false
		end

		RunService.Heartbeat:Wait()
	end

	return true
end

-- The first real player holding a character, with it, or nil
local function playerOf(): (Player?, Tread.Character?)
	for _, player: Player in Players:GetPlayers() do
		local character: Tread.Character? = Game.characterOf(player)
		if character then
			return player, character
		end
	end

	return nil, nil
end

-- Reads one observed frame's blocks into what the player has been shown
local function read(seen: Seen, frame: buffer)
	local decoded: { [string]: any } = Tread.decode(Tread.CODEC_VERSION, "tap", frame)
	seen.frames += 1

	for _, block: { [string]: any } in decoded.blocks do
		seen.blocks += 1
		seen.records += #block.records
		seen.changes += #block.changes
	end
end

--[[
    The run on the floor laid: the player set down at its middle, the bots
    built round it from the run's seeded generator, each roaming the area,
    the player observed through a warm-up and a window of its traffic read
    once an interval, each read printed as it comes
--]]

local function drive(
	made: Made,
	server: Tread.Server,
	shared: Tread.Shared,
	player: Player,
	character: Tread.Character
): (boolean, string)
	made.moved = true
	character:teleport(CFrame.new(CENTER + Vector3.new(0, LIFT, 0)))

	local landed: boolean = waitFor(function (): boolean
		local offset: Vector3 = character:getState().root - CENTER

		return Vector2.new(offset.X, offset.Z).Magnitude <= LANDED
	end)

	if not landed then
		return false, `{player.Name}'s teleport to the floor did not land within {WAIT} s`
	end

	local seeded: Seeded.Seeded = Seeded.new(SEED)
	local area: { center: Vector3, size: Vector2 } = { center = CENTER, size = AREA }
	local gait: Programs.Gait = {
		speed = shared.step.walk,
		rate = shared.rates.simulation,
		sprint = false,
		crouch = false,
		long = false,
	}

	for index: number = 1, BOTS do
		local own: Seeded.Seeded = Seeded.new(seeded:integer(1, SEED_BOUND))
		local x: number = CENTER.X + own:number(-AREA.X / 2, AREA.X / 2)
		local z: number = CENTER.Z + own:number(-AREA.Y / 2, AREA.Y / 2)

		Fleet.add({
			name = `Changes{index}`,
			group = GROUP,
			at = CFrame.new(x, CENTER.Y + LIFT, z) * CFrame.Angles(0, own:number(0, TURN), 0),
			steer = Programs.roam(area, own, gait),
			faults = nil,
			seed = own:integer(1, SEED_BOUND),
		})
	end

	local seen: Seen = { frames = 0, blocks = 0, records = 0, changes = 0 }
	made.stop = server:observe(player, function (_: number, frame: buffer)
		read(seen, frame)
	end)

	task.wait(WARMUP)

	-- Tread's own scope, which the player's bytes are counted on
	local Network = require(Packages.Tread.Network.Server)
	local samples: { number } = {}
	local deadline: number = os.clock() + WINDOW

	while os.clock() < deadline do
		task.wait(INTERVAL)

		local sent: number = Network.traffic(player)
		table.insert(samples, sent)
		print(`Changes second {#samples}: {sent} B of Tread's traffic to {player.Name} over the last second`)
	end

	local total: number = 0
	for _, sent: number in samples do
		total += sent
	end

	local mean: number = total / math.max(#samples, 1)
	local most: number = math.max(0, table.unpack(samples))
	local least: number = math.min(most, table.unpack(samples))
	local bytes: string = `{math.round(mean)} B/s on average to {player.Name}, {least} to {most}, over {#samples} s`
	local frames: string = `{seen.records} records in {seen.blocks} tap blocks of {seen.frames} frames`
	local line: string = `{BOTS} bots walking round them: {bytes}; {frames}`

	if #samples == 0 then
		return false, `{line}: no second of traffic was read`
	elseif seen.records == 0 then
		return false, `{line}: the frames carried no record`
	elseif seen.changes > 0 then
		return false, `{line}: the frames still held {seen.changes} change records`
	end

	return true, `{line}, every one whole`
end

return function (): (boolean, string | nil)
	local server: Tread.Server, shared: Tread.Shared, settings: Tread.ServerSettings = Game.get()
	local relay: { read changes: boolean? }? = settings.relay
	if not (relay and relay.changes) then
		return false, "the dev server's settings give no relay.changes"
	end

	Fleet.start()
	if #Fleet.entries() > 0 then
		return false, `another run's {#Fleet.entries()} bots are still on the server`
	end

	local player: Player?, character: Tread.Character? = playerOf()
	if not player or not character then
		return false, "no real player has a character to set down among the bots"
	end

	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	if not testContent then
		return false, "Workspace.TestContent is missing, so the dev game's casts take no floor laid"
	end

	local folder: Folder = Instance.new("Folder")
	folder.Name = FOLDER

	local floor: Part = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.CanCollide = true
	floor.CanQuery = true
	floor.CanTouch = false
	floor.Size = FLOOR_SIZE
	floor.CFrame = CFrame.new(CENTER - Vector3.new(0, FLOOR_SIZE.Y / 2, 0))
	floor.Parent = folder
	folder.Parent = testContent

	local made: Made = { stop = nil, moved = false }
	local ran: boolean, passed: any, line: any = pcall(drive, made, server, shared, player, character)

	-- Everything it made goes, whatever the run did
	local stop: (() -> ())? = made.stop
	if stop then
		stop()
	end

	local problems: { string } = Fleet.clear()
	folder:Destroy()

	if made.moved then
		local respawned: boolean, failure: any = pcall(Game.respawn, player)
		if not respawned then
			table.insert(problems, `{player.Name} was not respawned: {failure}`)
		end
	end

	if not ran then
		table.insert(problems, `the run threw: {passed}`)
	elseif not passed then
		table.insert(problems, line)
	end

	print(`Changes: {ran and line or passed}`)

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, line
end
