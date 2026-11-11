--[[
    Checks the out-of-view rate on the running server: a viewer bot's frames
    carry the targets behind and beside it at the lowered rate, the one in
    front and the near one at the full rate, and a record once it turns
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

-- Requiring them finds the modules the running server started, which keep each connection's newest look
local Commands = require(Packages.Tread.Server.Commands)
local Connections = require(Packages.Tread.Server.Connections)

local Fleet = require(ServerScriptService.Server.Bots.Fleet)
local Game = require(ServerScriptService.Server.Game)
local Programs = require(ServerScriptService.Server.Bots.Programs)

local CENTER: Vector3 = require(ServerScriptService.Server.Config.OutOfView).center
local FLOOR_SIZE: Vector3 = require(ServerScriptService.Server.Config.OutOfView).floor
local LIFT: number = require(ServerScriptService.Server.Config.OutOfView).lift
local FAR: number = require(ServerScriptService.Server.Config.OutOfView).far
local NEAR: number = require(ServerScriptService.Server.Config.OutOfView).near
local CIRCLE: number = require(ServerScriptService.Server.Config.OutOfView).circle
local LEAD: number = require(ServerScriptService.Server.Config.OutOfView).lead
local TURN: number = require(ServerScriptService.Server.Config.OutOfView).turn
local WINDOW: number = require(ServerScriptService.Server.Config.OutOfView).window
local SLACK: number = require(ServerScriptService.Server.Config.OutOfView).slack
local WAIT: number = require(ServerScriptService.Server.Config.OutOfView).wait
local HALF_TURN: number = math.pi -- Radians the viewer's look turns by
local FOLDER: string = "OutOfView" -- The folder the run lays its floor in
local GROUP: string = "outOfView" -- What the fleet's entries call the run's bots
local SEED: number = 1 -- No bot has faults, so nothing any of them draws ever matters
local SEPARATOR: string = "; " -- Between the problems in one report

-- The four targets, each by its spot from the viewer, which looks along -Z until it turns
local SPOTS: { { name: string, at: Vector3 } } = {
	{ name = "Front", at = Vector3.new(0, 0, -FAR) },
	{ name = "Behind", at = Vector3.new(0, 0, FAR) },
	{ name = "Side", at = Vector3.new(FAR, 0, 0) },
	{ name = "Close", at = Vector3.new(0, 0, NEAR) },
}

local FRONT: number = 1
local BEHIND: number = 2
local SIDE: number = 3
local CLOSE: number = 4

-- What the viewer's observed frames have shown it
type Seen = {
	sent: { [number]: boolean }, -- Each slot it is sent, from the reveals and hides its blocks carried
	counting: boolean, -- Whether every target was sent by the frame before
	records: { [number]: number }, -- Each slot's records in the frames counted, those before the turn
	frames: number, -- The frames counted
	hides: number, -- Hides of a target after counting began
	turned: boolean, -- Whether a frame from a run with the viewer's look turned has come
	answered: boolean, -- Whether that frame carried the record of the target that was behind
}

-- What one run made that its cleanup ends, whatever the run did
type Made = {
	stop: (() -> ())?,
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

local function toVector(value: Vector3): vector
	return vector.create(value.X, value.Y, value.Z)
end

--[[
    A target that walks a circle of CIRCLE studs about a point, each tick
    toward the point LEAD radians further round from where it stands
--]]

local function circle(center: vector): Programs.Steer
	return function (command: Tread.Command, _: number, position: vector)
		local angle: number = math.atan2(position.z - center.z, position.x - center.x) + LEAD
		local goal: vector = center + vector.create(math.cos(angle) * CIRCLE, 0, math.sin(angle) * CIRCLE)
		local offset: vector = goal - position

		-- The step's yaw 0 looks along -Z and a quarter turn along -X
		command.yaw = math.atan2(-offset.x, -offset.z)
		command.forward = 1
	end
end

-- A viewer that stands looking along -Z, then from its TURN-th tick along +Z
local function turning(): Programs.Steer
	local ticks: number = 0

	return function (command: Tread.Command, _: number, _: vector)
		ticks += 1
		if ticks >= TURN then
			command.yaw = HALF_TURN
		end
	end
end

--[[
    Reads one observed frame: each block's hides before its reveals, as the
    relay places them, the targets' records while counting, and on the first
    frame from a run whose look is turned, whether it carried the record of
    the target that was behind
--]]

local function read(seen: Seen, frame: buffer, slots: { number }, turned: boolean)
	local decoded: { [string]: any } = Tread.decode(Tread.CODEC_VERSION, "tap", frame)
	local records: { [number]: number } = {}

	for _, block: { [string]: any } in decoded.blocks do
		for _, hide: { [string]: any } in block.hides do
			seen.sent[hide.slot] = nil
			if seen.counting and table.find(slots, hide.slot) then
				seen.hides += 1
			end
		end

		for _, reveal: { [string]: any } in block.reveals do
			seen.sent[reveal.slot] = true
		end

		for _, record: { [string]: any } in block.records do
			records[record.slot] = (records[record.slot] or 0) + 1
		end
	end

	if seen.turned then
		return
	elseif turned then
		seen.turned = true
		seen.answered = records[slots[BEHIND]] ~= nil

		return
	end

	if seen.counting then
		seen.frames += 1
		for _, slot: number in slots do
			seen.records[slot] = (seen.records[slot] or 0) + (records[slot] or 0)
		end
	end

	local every: boolean = true
	for _, slot: number in slots do
		every = every and seen.sent[slot] == true
	end

	seen.counting = every
end

--[[
    The run on the floor laid: the viewer at its middle, the four targets
    walking their circles, the viewer observed from the start, and its
    frames counted from once every target is sent until its turned look
    reaches the relay, whose first run must send the target behind it
--]]

local function drive(
	made: Made,
	server: Tread.Server,
	shared: Tread.Shared,
	settings: Tread.ServerSettings
): (boolean, string)
	local outOfView: { rate: number, cone: number, radius: number }? = settings.tiers.outOfView
	if not outOfView then
		return false, "the dev server's settings give no tiers.outOfView"
	end

	local from: Vector3 = CENTER + Vector3.new(0, LIFT, 0)

	-- Built with no turn, so it faces -Z
	local viewer: Fleet.Entry = Fleet.add({
		name = "OutOfViewViewer",
		group = GROUP,
		at = CFrame.new(from),
		steer = turning(),
		faults = nil,
		seed = SEED,
	})

	-- Each target built on its circle, CIRCLE studs along +X from its spot
	local slots: { number } = {}
	for index: number, spot in SPOTS do
		local center: Vector3 = from + spot.at
		local target: Fleet.Entry = Fleet.add({
			name = `OutOfView{spot.name}`,
			group = GROUP,
			at = CFrame.new(center + Vector3.new(CIRCLE, 0, 0)),
			steer = circle(toVector(center)),
			faults = nil,
			seed = SEED,
		})

		slots[index] = (target.character :: any)._slot
	end

	local connection: Connections.Connection? = Connections.get(viewer.volt)
	if not connection then
		return false, "the viewer bot has no connection"
	end

	local seen: Seen = {
		sent = {},
		counting = false,
		records = {},
		frames = 0,
		hides = 0,
		turned = false,
		answered = false,
	}

	-- The look the frame's run read, since the relay reads it just before it runs and the taps right after
	made.stop = server:observe(viewer.volt, function (_: number, frame: buffer)
		local look: vector? = Commands.look(connection)
		read(seen, frame, slots, look ~= nil and look.z > 0)
	end)

	local function turned(): boolean
		return seen.turned
	end

	if not waitFor(turned) then
		return false, `the viewer's turned look reached no relay run within {WAIT} s`
	end

	local front: number = seen.records[slots[FRONT]] or 0
	local behind: number = seen.records[slots[BEHIND]] or 0
	local side: number = seen.records[slots[SIDE]] or 0
	local close: number = seen.records[slots[CLOSE]] or 0

	-- A lowered target's share of the front one's records, both held to the relay rate
	local relay: number = shared.rates.relay
	local share: number = math.min(outOfView.rate, relay) / math.min(settings.tiers.nearAim, relay)
	local lowered: number = front * share

	local counts: string = `front {front}, behind {behind}, side {side} and close {close} in {seen.frames} frames`
	local problems: { string } = {}

	if seen.frames < WINDOW then
		table.insert(problems, `only {seen.frames} frames, under {WINDOW}, came before the turn`)
	end

	if math.abs(behind - lowered) > SLACK or math.abs(side - lowered) > SLACK then
		table.insert(problems, `behind and side were not about {lowered}`)
	end

	if math.abs(close - front) > SLACK then
		table.insert(problems, "close was not about front")
	end

	if seen.hides > 0 then
		table.insert(problems, `a target was hidden {seen.hides} times`)
	end

	if not seen.answered then
		table.insert(problems, "the first run with the turned look sent no record of the target behind")
	end

	if #problems > 0 then
		return false, `{counts}: {table.concat(problems, SEPARATOR)}`
	end

	return true, `{counts}, and the target behind was sent on the first run after the turn`
end

return function (): (boolean, string | nil)
	local server: Tread.Server, shared: Tread.Shared, settings: Tread.ServerSettings = Game.get()
	Fleet.start()
	if #Fleet.entries() > 0 then
		return false, `another run's {#Fleet.entries()} bots are still on the server`
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

	local made: Made = { stop = nil }
	local ran: boolean, passed: any, line: any = pcall(drive, made, server, shared, settings)

	-- Everything it made goes, whatever the run did
	local stop: (() -> ())? = made.stop
	if stop then
		stop()
	end

	local problems: { string } = Fleet.clear()
	folder:Destroy()

	if not ran then
		table.insert(problems, `the run threw: {passed}`)
	elseif not passed then
		table.insert(problems, line)
	end

	print(`OutOfView: {ran and line or passed}`)

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, line
end
