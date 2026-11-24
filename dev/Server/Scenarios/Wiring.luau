--[[
    Drives the server's members on the running dev game with Volt bots on a
    floor it builds: anti-ESP behind occluders it places, with verdict memory
    off and on, a sleeper, a body, a teleport, a spectate and a called platform
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local AntiEsp = require(Packages.Tread.Server.AntiEsp)
local Relay = require(Packages.Tread.Server.Relay)
local Spectate = require(Packages.Tread.Server.Spectate)

local Game = require(ServerScriptService.Server.Game)

local FLOOR_TOP: number = 1010 -- Studs: above the 1,000 no content reaches, and inside the record's 1,024-stud window
local FLOOR_SIZE: Vector3 = Vector3.new(120, 2, 80)
local LIFT: number = 0.5 -- Studs over the floor each bot's character is built at
local OCCLUDER_SIZE: Vector3 = Vector3.new(1, 30, 30) -- Across every ray between the viewer and its target
local SLEEPER_DROP: number = 10 -- Studs above the floor the sleeper is made, before it is moved down to it
local PLATFORM_ID: number = 127 -- The highest id, which the dev game's own platforms leave free
local PLATFORM_SIZE: Vector3 = Vector3.new(8, 1, 8)
local PLATFORM_RISE: number = 0.1 -- Studs a tick the platform rises once called
local PLATFORM_TOP: number = 40 -- Studs above the floor it stops at
local SECONDS: number = 10 -- The longest each wait runs before it fails
local SETTLE: number = 1 -- Seconds the bodies get to land and anti-ESP to test each pair
local CLOSE: number = 0.1 -- Studs a place may sit from where it should
local SEPARATOR: string = "; " -- Between the problems in one report
local PROBE_STAGE: string = "wiringProbe"
local ASIDE: Vector3 = Vector3.new(0, 0, 60) -- From the viewer's line to where the moved occluder waits, off every ray

-- The dev game's own anti-ESP hold and visible rate, which set how long an answer cast afresh takes to hide a visible
-- pair whose line is blocked
local HOLD: number = require(ServerScriptService.Server.Config.Tread).antiEsp.hold
local VISIBLE_RATE: number = require(ServerScriptService.Server.Config.Tread).antiEsp.visibleRate
local RECHECKS: number = 2 -- Visible rechecks past the hold: by the first a fresh answer has hidden the pair, then room

-- Seconds the target must stay sent once the moved occluder blocks its line, past when a fresh answer would have hidden
-- it, so only an answer served from memory keeps it sent
local SERVED: number = HOLD + RECHECKS / VISIBLE_RATE

-- The dev game's near-hidden rate and relay rate, which set how soon an answer cast afresh reveals a near hidden pair
-- whose line is clear: at its next near recheck, then the next relay run
local NEAR_RATE: number = require(ServerScriptService.Server.Config.Tread).antiEsp.nearRate
local RELAY_RATE: number = require(ReplicatedStorage.Shared.Dev.Config).rates.relay
local REVEALS: number = 3 -- Rechecks and relay ticks a fresh answer gets: in process, the workers' lead, then room

-- Seconds the target must stay unsent once nothing stands on its line, past when a fresh answer would have revealed
-- it, so only an answer or box served from memory keeps it hidden
local KEPT_HIDDEN: number = REVEALS * (1 / NEAR_RATE + 1 / RELAY_RATE)

-- Where each bot's character is built along the floor, the viewer's target behind the occluder from it
local VIEWER: Vector3 = Vector3.new(0, FLOOR_TOP + LIFT, 0)
local TARGET: Vector3 = Vector3.new(10, FLOOR_TOP + LIFT, 0)
local MODERATOR: Vector3 = Vector3.new(-10, FLOOR_TOP + LIFT, 0)
local VICTIM: Vector3 = Vector3.new(0, FLOOR_TOP + LIFT, 15)
local MOVER: Vector3 = Vector3.new(0, FLOOR_TOP + LIFT, -15)
local MOVED: Vector3 = Vector3.new(30, FLOOR_TOP + LIFT, -15)
local SLEEPER: Vector3 = Vector3.new(-30, FLOOR_TOP + SLEEPER_DROP, 15)
local PLATFORM: Vector3 = Vector3.new(-30, FLOOR_TOP + PLATFORM_SIZE.Y / 2, -20)

-- Everything one run made on the running handle, all of which it removes whatever its checks did
type Made = {
	targets: number,
	bots: { Volt.Bot },
	characters: { Tread.Character },
	sleeper: Tread.Sleeper?,
	body: Tread.Body?,
	stops: { () -> () }, -- Each callback's disconnect and the platform's removal
	parts: { Instance },
	memory: boolean?, -- Whether verdict memory ran as the run found it, nil until the run turns it on
}

-- The newest tick the history has written, which the probe stage keeps; added once a server, since stages stay
local Present: number = 0
local Probing: boolean = false

-- Waits a frame at a time until done says so or SECONDS pass, and gives whether it got there
local function waitFor(done: () -> boolean): boolean
	local deadline: number = os.clock() + SECONDS

	while not done() do
		if os.clock() >= deadline then
			return false
		end

		RunService.Heartbeat:Wait()
	end

	return true
end

--[[
    Waits until verdict memory has kept answers past where its count stood
    and SETTLE seconds have gone, long enough for every pair's recheck to
    keep its own, up to SECONDS, and gives whether it got there
--]]

local function keptPast(stood: number): boolean
	local settled: number = os.clock() + SETTLE

	return waitFor(function (): boolean
		local kept: number = AntiEsp.memory()

		return kept > stood and os.clock() >= settled
	end)
end

--[[
    Whether holds says so at every Heartbeat for seconds, the wait held to
    that deadline, giving false at the first Heartbeat it doesn't
--]]

local function heldFor(seconds: number, holds: () -> boolean): boolean
	local deadline: number = os.clock() + seconds

	while os.clock() < deadline do
		if not holds() then
			return false
		end

		RunService.Heartbeat:Wait()
	end

	return holds()
end

-- Anti-ESP's player pairs failed open on the server since start, a read that changes nothing
local function failOpens(): number
	local _, _, failed: number = AntiEsp.counts()

	return failed
end

-- A part that is anchored and touches nothing, colliding or not, in a parent
local function part(name: string, size: Vector3, at: Vector3, canCollide: boolean, parent: Instance): Part
	local made: Part = Instance.new("Part")
	made.Name = name
	made.Anchored = true
	made.CanCollide = canCollide
	made.CanQuery = true
	made.CanTouch = false
	made.Size = size
	made.CFrame = CFrame.new(at)
	made.Parent = parent

	return made
end

-- The city block's occluder folder, which the dev game's anti-ESP casts against, erroring when the place has none
local function occluders(): Instance
	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	local cityBlock: Instance? = testContent and testContent:FindFirstChild("CityBlock")
	local folder: Instance? = cityBlock and cityBlock:FindFirstChild("Occluders")
	if not folder then
		error("Workspace.TestContent.CityBlock.Occluders is missing, so no occluder this places would count")
	end

	return folder
end

-- A bot's character built at a point, the bot and the character kept for the clean-up
local function build(handle: Tread.Server, made: Made, name: string, at: Vector3): Tread.Character
	local bot: Volt.Bot = Volt.addBot(name)
	table.insert(made.bots, bot)

	local character: Tread.Character = handle:create(bot, CFrame.new(at))
	table.insert(made.characters, character)

	return character
end

-- The slot a handle stands in, which the relay is asked about
local function slotOf(target: any): number
	return target._slot
end

--[[
    Everything once the floor and the occluder stand: each member driven in
    turn and its answer checked, with the figures the report carries
--]]

local function drive(handle: Tread.Server, made: Made, problems: { string }, occluder: Part): string
	if not Probing then
		-- After the history, so its tick is the newest a sample reads at
		handle:addStage(PROBE_STAGE, "history", function (tick: number)
			Present = tick
		end)

		Probing = true
	end

	local viewer: Tread.Character = build(handle, made, "WiringViewer", VIEWER)
	local target: Tread.Character = build(handle, made, "WiringTarget", TARGET)
	local moderator: Tread.Character = build(handle, made, "WiringModerator", MODERATOR)
	local victim: Tread.Character = build(handle, made, "WiringVictim", VICTIM)
	local mover: Tread.Character = build(handle, made, "WiringMover", MOVER)
	local settled: number = os.clock() + SETTLE
	waitFor(function (): boolean
		return os.clock() >= settled
	end)

	-- 1) Anti-ESP: the target behind the occluder is not sent to the viewer, and is once the occluder goes
	local hidden: boolean = not Relay.isSent(viewer.player, slotOf(target))
	if not hidden then
		table.insert(problems, "the target behind the occluder was sent to the viewer")
	end

	occluder:Destroy()
	local shown: boolean = waitFor(function (): boolean
		return Relay.isSent(viewer.player, slotOf(target))
	end)

	if not shown then
		table.insert(problems, `with the occluder gone the target was not sent to the viewer within {SECONDS} s`)
	end

	-- And again with verdict memory on. A second occluder waits off the line, placed while memory is off so its
	-- arrival moves no epoch. Each change to the include list waits first for answers kept past where the count
	-- stood, so the pair's kept answer goes only through the listener that hears the change
	local line: Vector3 = (VIEWER + TARGET) / 2
	local moved: Part = part("WiringMovedOccluder", OCCLUDER_SIZE, line + ASIDE, false, occluders())
	table.insert(made.parts, moved)

	local remembered: boolean = AntiEsp.memoryOn()
	local remember: boolean = true
	made.memory = remembered
	AntiEsp.useMemory(remember)
	local startKept: number, startBoxRays: number = AntiEsp.memory()

	if not keptPast(startKept) then
		table.insert(
			problems,
			`with verdict memory on no answer was kept within {SECONDS} s, so DescendantAdded is unproven`
		)
	end

	-- Onto the line by CFrame, which no listener hears, so the target stays sent only while this pair's own answer
	-- is served from memory, as the listener's check below needs it to be. A fail-open would keep it sent too
	local failedBefore: number = failOpens()
	moved.CFrame = CFrame.new(line)
	local served: boolean = heldFor(SERVED, function (): boolean
		return Relay.isSent(viewer.player, slotOf(target))
	end)

	local failed: number = failOpens() - failedBefore
	if not served then
		local unproven: string = "so its answer was cast afresh and DescendantAdded is unproven"
		table.insert(problems, `the target was hidden within {SERVED} s of an occluder moved onto its line, {unproven}`)
	end

	if failed > 0 then
		local unproven: string = "so the target may have been sent without memory and DescendantAdded is unproven"
		table.insert(
			problems,
			`anti-ESP failed open {failed} times on the server while the target was held sent, {unproven}`
		)
	end

	local again: Part = part("WiringMemoryOccluder", OCCLUDER_SIZE, line, false, occluders())
	table.insert(made.parts, again)

	local rehidden: boolean = waitFor(function (): boolean
		return not Relay.isSent(viewer.player, slotOf(target))
	end)

	if not rehidden then
		table.insert(problems, `with verdict memory on the target was still sent behind an occluder after {SECONDS} s`)
	end

	local hiddenKept: number = AntiEsp.memory()
	if not keptPast(hiddenKept) then
		local unproven: string = "so DescendantRemoving is unproven"
		table.insert(problems, `with the target hidden no answer was kept within {SECONDS} s, {unproven}`)
	end

	-- Both off the line by CFrame, unheard, so the target stays unsent only while this pair's hidden answer or kept
	-- box is served from memory, as the listener's check below needs it to be
	moved.CFrame = CFrame.new(line + ASIDE)
	again.CFrame = CFrame.new(line + ASIDE)
	local stayed: boolean = heldFor(KEPT_HIDDEN, function (): boolean
		return not Relay.isSent(viewer.player, slotOf(target))
	end)

	if not stayed then
		local within: string = string.format("%.2f", KEPT_HIDDEN)
		local unproven: string = "so its answer was cast afresh and DescendantRemoving is unproven"
		table.insert(
			problems,
			`the target was sent within {within} s of both occluders moving off its line, {unproven}`
		)
	end

	-- Gone from the include list, which the listener hears, so the pair is cast afresh against a clear line
	again:Destroy()
	local reshown: boolean = waitFor(function (): boolean
		return Relay.isSent(viewer.player, slotOf(target))
	end)

	if not reshown then
		table.insert(
			problems,
			`with verdict memory on the target was not sent within {SECONDS} s of the occluder going`
		)
	end

	local endKept: number, endBoxRays: number = AntiEsp.memory()
	local kept: number, boxRays: number = endKept - startKept, endBoxRays - startBoxRays
	AntiEsp.useMemory(remembered)
	made.memory = nil

	local checks: string = `served {served}, hidden {rehidden}, kept hidden {stayed} and shown {reshown}`
	local memory: string = `with memory {checks}, {kept} kept answers and {boxRays} box rays`

	-- 2) A sleeper made in the air and moved down to the floor, its shapes following the fall
	local sleeper: Tread.Sleeper? = handle:createSleeper(CFrame.new(SLEEPER), {})
	made.sleeper = sleeper

	local fell: boolean = false
	if not sleeper then
		table.insert(problems, "createSleeper made no sleeper")
	else
		if not table.find(handle:getAll(), sleeper) then
			table.insert(problems, "getAll left out the sleeper")
		end

		local floor: Vector3 = Vector3.new(SLEEPER.X, FLOOR_TOP, SLEEPER.Z)
		sleeper:moveTo(CFrame.new(floor))

		fell = waitFor(function (): boolean
			local sample: Tread.Sample? = handle:sampleAt(sleeper, Present)

			return sample ~= nil and (sample.position - floor).Magnitude <= CLOSE
		end)

		if not fell then
			table.insert(problems, `the moved sleeper's shapes never reached the floor within {SECONDS} s`)
		end
	end

	-- 3) A death leaves a body in a slot of its own
	local body: Tread.Body = victim:die(Vector3.new(0, 0, 1))
	made.body = body
	victim:destroy()

	local index: number? = table.find(made.characters, victim)
	if index then
		table.remove(made.characters, index)
	end

	if slotOf(body) == slotOf(victim) then
		table.insert(problems, "the body took the dead character's slot")
	end

	-- 4) A teleport lands on a later tick and raises onTeleported
	local landed: Tread.Character? = nil
	table.insert(
		made.stops,
		handle:onTeleported(function (character: Tread.Character)
			if character == mover then
				landed = character
			end
		end)
	)

	mover:teleport(CFrame.new(MOVED))
	local teleported: boolean = waitFor(function (): boolean
		return landed ~= nil
	end)

	local root: Vector3 = mover:getState().root
	if not teleported then
		table.insert(problems, `onTeleported never heard the mover's landing within {SECONDS} s`)
	elseif math.abs(root.X - MOVED.X) > CLOSE or math.abs(root.Z - MOVED.Z) > CLOSE then
		table.insert(problems, `the mover landed at {root}, not {MOVED}`)
	end

	-- 5) A spectate starts and ends between two bots
	handle:spectate(moderator.player, target)
	local watching: boolean = Spectate.targetOf(moderator.player) == target.player
	handle:spectate(moderator.player, nil)

	if not watching or Spectate.targetOf(moderator.player) ~= nil then
		table.insert(problems, "the spectate between the moderator and the target did not start and end")
	end

	-- 6) A platform added, a rider on it, and once called it carries the rider up
	local top: number = PLATFORM_SIZE.Y / 2
	local platform: Tread.Platform = {
		id = PLATFORM_ID,
		boxes = { { center = Vector3.zero, size = PLATFORM_SIZE } },

		path = function (tick: number, calledAt: number?): Vector3
			local risen: number = 0
			if calledAt ~= nil then
				risen = math.min((tick - calledAt) * PLATFORM_RISE, PLATFORM_TOP)
			end

			return PLATFORM + Vector3.new(0, risen, 0)
		end,
	}

	table.insert(made.stops, handle:addPlatform(platform))

	local rider: Tread.Character = build(handle, made, "WiringRider", PLATFORM + Vector3.new(0, top + LIFT, 0))
	local boarded: boolean = waitFor(function (): boolean
		return rider:getState().platform == PLATFORM_ID
	end)

	local start: number = rider:getState().root.Y
	handle:callPlatform(PLATFORM_ID)

	local rode: boolean = waitFor(function (): boolean
		local state: Tread.State = rider:getState()

		return state.platform == PLATFORM_ID and state.root.Y > start + 1
	end)

	if not boarded or not rode then
		table.insert(problems, `the rider boarded the platform {boarded} and rode it up {rode}`)
	end

	local stats: { [string]: any } = handle:stats()
	local anti: string = `anti-ESP {stats.antiEspTests} tests and {stats.antiEspHidden} hidden this second`
	local rise: string = string.format("the rider rose %.2f studs", rider:getState().root.Y - start)

	return `hidden {hidden}, shown {shown}, {memory}, the sleeper fell {fell}, {rise}, {anti}`
end

--[[
    Takes away everything a run made on the running handle, so the dev
    game is left as the run found it, and checks the handle lists the same
    targets it did before
--]]

local function clean(handle: Tread.Server, made: Made, problems: { string })
	for _, stop: () -> () in made.stops do
		stop()
	end

	for _, character: Tread.Character in made.characters do
		character:destroy()
	end

	local sleeper: Tread.Sleeper? = made.sleeper
	if sleeper then
		sleeper:destroy()
	end

	local body: Tread.Body? = made.body
	if body then
		body:destroy()
	end

	for _, bot: Volt.Bot in made.bots do
		Volt.removeBot(bot)
	end

	for _, instance: Instance in made.parts do
		instance:Destroy()
	end

	-- Verdict memory as the run found it, when the checks threw while it was on
	local memory: boolean? = made.memory
	if memory ~= nil then
		AntiEsp.useMemory(memory)
	end

	local left: number = #handle:getAll()
	if left ~= made.targets then
		table.insert(problems, `after the clean-up getAll gave {left} targets, where it gave {made.targets} before`)
	end
end

return function (): (boolean, string | nil)
	local problems: { string } = {}
	local handle: Tread.Server = Game.get()

	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	if not testContent then
		return false, "Workspace.TestContent is missing, so the dev game's casts include nothing this could build in"
	end

	local folder: Folder = Instance.new("Folder")
	folder.Name = "Wiring"
	part("Floor", FLOOR_SIZE, Vector3.new(0, FLOOR_TOP - FLOOR_SIZE.Y / 2, 0), true, folder)
	folder.Parent = testContent

	local midpoint: Vector3 = (VIEWER + TARGET) / 2
	local occluder: Part = part("WiringOccluder", OCCLUDER_SIZE, midpoint, false, occluders())

	local made: Made = {
		targets = #handle:getAll(),
		bots = {},
		characters = {},
		sleeper = nil,
		body = nil,
		stops = {},
		parts = { occluder, folder },
		memory = nil,
	}

	local ran: boolean, result: any = pcall(drive, handle, made, problems, occluder)
	local line: string = ""
	if ran then
		line = result
	else
		table.insert(problems, `the checks threw: {result}`)
	end

	-- Everything it made goes, whatever the checks did
	local cleaned: boolean, failure: any = pcall(clean, handle, made, problems)
	if not cleaned then
		table.insert(problems, `taking away what it made threw: {failure}`)
	end

	print(`Wiring: {line}`)

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, line
end
