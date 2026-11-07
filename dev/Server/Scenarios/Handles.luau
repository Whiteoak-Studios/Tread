--[[
    Drives the server handle the dev game started: an NPC and a Volt bot's
    character on a floor it builds under Workspace.TestContent, the members'
    answers checked against what was there before, and everything removed
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Game = require(ServerScriptService.Server.Game)

local FLOOR_TOP: number = 1010 -- Studs: above the 1,000 no content reaches, and inside the record's 1,024-stud window
local FLOOR_SIZE: Vector3 = Vector3.new(80, 2, 60)
local LIFT: number = 0.5 -- Studs over the floor the character is built at
local DROP: number = 6 -- Studs over the floor the NPC is built at, past the landing airtime
local NPC_X: number = -10 -- Where along X the NPC is built, the character at 0
local STAND_INS: number = 10 -- The bot's stand-in reports to see before the checks, half a second at 20 Hz
local SECONDS: number = 10 -- The longest each wait runs before it fails
local RANGE: number = 5 -- Studs the range queries reach around each body
local BOX: Vector3 = Vector3.new(1, 4, 1) -- The overlap query's box
local AWAY: number = 20 -- Studs off the character the second overlap box sits
local HEIGHT_STEP: number = 1 / 32 -- Studs, the history's height precision
local MILLISECONDS: number = 1000 -- A second's, which the report gives stage times in
local SEPARATOR: string = "; " -- Between the problems in one report
local PROBE_STAGE: string = "handlesProbe"
local BOT_NAME: string = "HandlesBot"

type Landing = { target: Tread.Target, speed: number, material: Enum.Material, apex: number }

-- What one run made on the running handle, all of which it removes whatever its checks did, and the targets before it
type Made = {
	targets: number,
	bot: Volt.Bot?,
	npc: Tread.Npc?,
	character: Tread.Character?,
	stops: { () -> () }, -- Each callback's disconnect
}

-- The newest tick the history has written, which the probe stage keeps; added once a server, since stages stay
local Present: number = 0
local Probing: boolean = false

-- The first value in a stats read that is no number, with its path, or nil when every value is one
local function stray(value: any, path: string): string?
	if type(value) == "table" then
		for key: any, inner: any in value do
			local found: string? = stray(inner, `{path}.{tostring(key)}`)
			if found then
				return found
			end
		end

		return nil
	elseif type(value) ~= "number" then
		return `{path} holds a {typeof(value)}`
	end

	return nil
end

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

-- Builds the floor, anchored and collidable, in a folder under TestContent, which the dev game's casts include
local function build(): Folder
	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	if not testContent then
		error("Workspace.TestContent is missing, so the dev game's casts include nothing this could build in")
	end

	local folder: Folder = Instance.new("Folder")
	folder.Name = "Handles"

	local floor: Part = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.CanCollide = true
	floor.CanQuery = true
	floor.CanTouch = false
	floor.Size = FLOOR_SIZE
	floor.CFrame = CFrame.new(0, FLOOR_TOP - FLOOR_SIZE.Y / 2, 0)
	floor.Parent = folder
	folder.Parent = testContent

	return folder
end

--[[
    Everything once the floor stands: the bodies built, the tick run until
    the NPC has landed and the bot's stand-ins are reported, and every
    member's answer checked against the stats read first. Gives the stats
    line the report carries
--]]

local function drive(handle: Tread.Server, made: Made, problems: { string }): string
	if not Probing then
		-- After the history, so its tick is the newest a sample reads at
		handle:addStage(PROBE_STAGE, "history", function (tick: number)
			Present = tick
		end)

		Probing = true
	end

	local before: { [string]: any } = handle:stats()
	local landings: { Landing } = {}
	local standIns: number = 0

	local bot: Volt.Bot = Volt.addBot(BOT_NAME)
	made.bot = bot

	local npc: Tread.Npc = handle:createNpc(CFrame.new(NPC_X, FLOOR_TOP + DROP, 0))
	made.npc = npc

	local character: Tread.Character = handle:create(bot, CFrame.new(0, FLOOR_TOP + LIFT, 0))
	made.character = character

	-- Only the NPC's landings, since a player's own character may land on the plaza meanwhile
	local stopLanded: () -> () = handle:onLanded(
		function (target: Tread.Target, speed: number, material: Enum.Material, apex: number)
			if target == npc then
				table.insert(landings, { target = target, speed = speed, material = material, apex = apex })
			end
		end
	)

	local stopReports: () -> () = handle:onReport(
		function (player: (Player | Tread.Bot)?, kind: string, _: number | string)
			if player == bot and kind == "standIn" then
				standIns += 1
			end
		end
	)

	table.insert(made.stops, stopLanded)
	table.insert(made.stops, stopReports)

	local settled: boolean = waitFor(function (): boolean
		return #landings > 0 and npc:getState().grounded and character:getState().grounded and standIns >= STAND_INS
	end)

	if not settled then
		local states: string =
			`NPC grounded {npc:getState().grounded}, character grounded {character:getState().grounded}`
		table.insert(problems, `after {SECONDS} s: {#landings} landings, {standIns} stand-ins, {states}`)
	end

	local landing: Landing? = landings[1]
	if not landing or not (landing.speed > 0) then
		table.insert(problems, "onLanded gave no landing of the NPC's with a speed")
	elseif landing.material ~= Enum.Material.Plastic or math.abs(landing.apex - (FLOOR_TOP + DROP)) > HEIGHT_STEP then
		table.insert(problems, `the NPC's landing reported {landing.material} at an apex of {landing.apex}`)
	end

	local state: Tread.State = character:getState()
	if character:getState() ~= state or math.abs(state.root.Y - FLOOR_TOP) > HEIGHT_STEP then
		table.insert(problems, `getState read {state.root}, or a second read gave another table`)
	end

	local names: { string } = handle:near(state.root, RANGE)
	if #names ~= 1 or names[1] ~= bot.Name then
		table.insert(problems, `near found {#names} names around the character, not the bot's`)
	end

	local npcs: { Tread.Npc } = handle:npcsNear(npc:getState().root, RANGE)
	if #npcs ~= 1 or npcs[1] ~= npc then
		table.insert(problems, `npcsNear found {#npcs} NPCs around the NPC`)
	end

	local over: CFrame = CFrame.new(state.root + Vector3.new(0, BOX.Y / 2, 0))
	if not handle:overlaps(over, BOX) or handle:overlaps(over + Vector3.new(AWAY, 0, 0), BOX) then
		table.insert(problems, "overlaps missed the character's hull, or found one where none stands")
	end

	local sample: Tread.Sample? = handle:sampleAt(character, Present)
	if not sample or (sample.position - state.root).Magnitude > HEIGHT_STEP then
		table.insert(problems, `sampleAt at tick {Present} gave no sample where the character stands`)
	end

	local stats: { [string]: any } = handle:stats()
	local found: string? = stray(stats, "stats")
	local players: number = stats.players - before.players
	local awake: number = stats.npcs - before.npcs
	if found then
		table.insert(problems, `stats is aggregate numbers only, and {found}`)
	elseif players ~= 1 or awake ~= 1 or not (stats.standIns > 0) or not (stats.ticks > 0) then
		table.insert(problems, `stats gave {players} players, {awake} NPCs and {stats.standIns} stand-ins more`)
	end

	local simulate: any = stats.stages.simulate
	local last: number = simulate.last * MILLISECONDS
	local p95: number = simulate.p95 * MILLISECONDS
	local times: string = string.format("simulate last %.3f ms, p95 %.3f ms", last, p95)

	return `{stats.ticks} ticks, {stats.standIns} stand-ins, {stats.bytesOut} B out, {times}`
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

	local character: Tread.Character? = made.character
	if character then
		character:destroy()
	end

	local npc: Tread.Npc? = made.npc
	if npc then
		npc:destroy()
	end

	local bot: Volt.Bot? = made.bot
	if bot then
		Volt.removeBot(bot)
	end

	local left: number = #handle:getAll()
	if left ~= made.targets then
		table.insert(problems, `after both destroys getAll gave {left} targets, where it gave {made.targets} before`)
	end
end

return function (): (boolean, string | nil)
	local problems: { string } = {}
	local handle: Tread.Server = Game.get()
	local folder: Folder = build()
	local made: Made = { targets = #handle:getAll(), bot = nil, npc = nil, character = nil, stops = {} }

	local ran: boolean, result: any = pcall(drive, handle, made, problems)
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

	folder:Destroy()

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, line
end
