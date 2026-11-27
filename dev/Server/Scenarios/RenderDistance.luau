--[[
    Checks a viewer's render distance on the running server: a viewer bot's
    client sends View, and the frames the viewer is observed with carry the
    target bot inside that distance and not the one past it
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Fleet = require(ServerScriptService.Server.Bots.Fleet)
local Game = require(ServerScriptService.Server.Game)
local Programs = require(ServerScriptService.Server.Bots.Programs)

local CENTER: Vector3 = require(ServerScriptService.Server.Config.RenderDistance).center
local FLOOR_SIZE: Vector3 = require(ServerScriptService.Server.Config.RenderDistance).floor
local LIFT: number = require(ServerScriptService.Server.Config.RenderDistance).lift
local NEAR: number = require(ServerScriptService.Server.Config.RenderDistance).near
local FAR: number = require(ServerScriptService.Server.Config.RenderDistance).far
local VIEW: number = require(ServerScriptService.Server.Config.RenderDistance).view
local WHOLE: number = require(ServerScriptService.Server.Config.RenderDistance).whole
local HOLD: number = require(ServerScriptService.Server.Config.RenderDistance).hold
local WAIT: number = require(ServerScriptService.Server.Config.RenderDistance).wait
local FOLDER: string = "RenderDistance" -- The folder the run lays its floor in
local GROUP: string = "render" -- What the fleet's entries call the run's bots
local SEED: number = 1 -- No bot has faults, so nothing any of them draws ever matters
local SEPARATOR: string = "; " -- Between the problems in one report

-- What the viewer's observed frames have shown it
type Seen = {
	sent: { [number]: boolean }, -- Each slot it is sent, from the reveals and hides its blocks carried
	records: { [number]: number }, -- The records of each slot its frames carried since the count was last cleared
	frames: number, -- The frames observed since then
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

-- Reads one observed frame into what the viewer has been shown, each block's hides before its reveals as it places them
local function read(seen: Seen, frame: buffer)
	local decoded: { [string]: any } = Tread.decode(Tread.CODEC_VERSION, "tap", frame)

	for _, block: { [string]: any } in decoded.blocks do
		for _, hide: { [string]: any } in block.hides do
			seen.sent[hide.slot] = nil
		end

		for _, reveal: { [string]: any } in block.reveals do
			seen.sent[reveal.slot] = true
		end

		for _, record: { [string]: any } in block.records do
			seen.records[record.slot] = (seen.records[record.slot] or 0) + 1
		end
	end

	seen.frames += 1
end

-- Sends a render distance from the viewer's client side, the bot's own copy of Tread's generated client module
local function send(network: any, distance: number)
	network.View.fire(distance)
	network.flush()
end

--[[
    The run on the floor laid: the viewer and both targets standing along
    X, the viewer observed from the start, then sent both targets at the
    server's whole radius, only the nearer once its client sends the
    shorter distance, and both again once it sends the whole radius
--]]

local function drive(made: Made, server: Tread.Server): (boolean, string)
	local from: Vector3 = CENTER + Vector3.new(-FAR / 2, LIFT, 0)

	-- Each faces -Z, as a CFrame with no turn does
	local viewer: Fleet.Entry = Fleet.add({
		name = "RenderViewer",
		group = GROUP,
		at = CFrame.new(from),
		steer = Programs.idle(),
		faults = nil,
		seed = SEED,
	})

	local near: Fleet.Entry = Fleet.add({
		name = "RenderNear",
		group = GROUP,
		at = CFrame.new(from + Vector3.new(NEAR, 0, 0)),
		steer = Programs.idle(),
		faults = nil,
		seed = SEED,
	})

	local far: Fleet.Entry = Fleet.add({
		name = "RenderFar",
		group = GROUP,
		at = CFrame.new(from + Vector3.new(FAR, 0, 0)),
		steer = Programs.idle(),
		faults = nil,
		seed = SEED,
	})

	local nearSlot: number = (near.character :: any)._slot
	local farSlot: number = (far.character :: any)._slot
	local seen: Seen = { sent = {}, records = {}, frames = 0 }

	made.stop = server:observe(viewer.volt, function (_: number, frame: buffer)
		read(seen, frame)
	end)

	local function both(): boolean
		return seen.sent[nearSlot] == true and seen.sent[farSlot] == true
	end

	-- 1) With no View heard, the viewer has the server's whole radius
	if not waitFor(both) then
		return false, `with no View heard the viewer was not sent both targets within {WAIT} s`
	end

	-- 2) At the shorter distance the farther target is hidden, and stays so with no record of it
	local network: any = (viewer.bot :: any)._network
	send(network, VIEW)

	local hidden: boolean = waitFor(function (): boolean
		return seen.sent[farSlot] == nil
	end)

	if not hidden then
		return false, `{WAIT} s after a View of {VIEW} the viewer was still sent the target at {FAR}`
	end

	table.clear(seen.records)
	seen.frames = 0

	local held: boolean = waitFor(function (): boolean
		return seen.frames >= HOLD
	end)

	if not held then
		return false, `the viewer was observed for {seen.frames} of {HOLD} frames within {WAIT} s`
	elseif seen.sent[farSlot] or seen.records[farSlot] ~= nil then
		return false, `at {VIEW} studs the viewer's frames carried the target at {FAR}`
	elseif not seen.sent[nearSlot] then
		return false, `at {VIEW} studs the viewer's frames did not carry the target at {NEAR}`
	end

	-- 3) Back at the whole radius both are sent again
	send(network, WHOLE)

	if not waitFor(both) then
		return false, `{WAIT} s after a View of {WHOLE} the viewer was not sent both targets again`
	end

	local line: string = `at {VIEW} studs the viewer was sent the target at {NEAR} and not the one at {FAR}`

	return true, `{line} for {HOLD} frames, and both at {WHOLE}`
end

return function (): (boolean, string | nil)
	local server: Tread.Server = Game.get()
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
	local ran: boolean, passed: any, line: any = pcall(drive, made, server)

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

	print(`RenderDistance: {ran and line or passed}`)

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, line
end
