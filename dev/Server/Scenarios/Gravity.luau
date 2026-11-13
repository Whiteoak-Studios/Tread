--[[
    Changes Tread's gravity under a falling Volt bot and a moved sleeper:
    Workspace.Gravity set to match, the bot's ticks held to the step's own
    update and the sleeper's to Math.fall under each tick's gravity, then
    the shared table's gravity put back
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Math = require(Packages.Tread.Step.Math)

local Game = require(ServerScriptService.Server.Game)

local AT: Vector3 = require(ServerScriptService.Server.Config.Gravity).at
local CHANGED: number = require(ServerScriptService.Server.Config.Gravity).changed
local AIRBORNE: number = require(ServerScriptService.Server.Config.Gravity).airborne
local CHECKED: number = require(ServerScriptService.Server.Config.Gravity).checked
local CLOSE: number = require(ServerScriptService.Server.Config.Gravity).close
local READ: number = require(ServerScriptService.Server.Config.Gravity).read
local AIRBORNE_WAIT: number = require(ServerScriptService.Server.Config.Gravity).waits.airborne
local CHECKED_WAIT: number = require(ServerScriptService.Server.Config.Gravity).waits.checked
local SLEEPER_AT: Vector3 = require(ServerScriptService.Server.Config.Gravity).sleeper.at
local SLEEPER_DROP: number = require(ServerScriptService.Server.Config.Gravity).sleeper.drop
local SLEEPER_CHANGE: number = require(ServerScriptService.Server.Config.Gravity).sleeper.changeAfter
local SLEEPER_AFTER: number = require(ServerScriptService.Server.Config.Gravity).sleeper.after
local SLEEPER_CLOSE: number = require(ServerScriptService.Server.Config.Gravity).sleeper.close
local SLEEPER_WAIT: number = require(ServerScriptService.Server.Config.Gravity).waits.sleeper
local PROBE_STAGE: string = "gravityProbe"
local BOT_NAME: string = "GravityBot"
local AIR: string = "Air"
local SEPARATOR: string = "; " -- Between the parts of a report

-- One tick of the bot's fall, as the probe read it right after the step
type Fall = {
	velocity: number, -- Studs/s, up positive
	mode: string,
}

-- What one run made or changed, all of which it puts back whatever its checks did
type Made = {
	bot: Volt.Bot?,
	character: Tread.Character?,
	sleeper: Tread.Sleeper?,
	changed: boolean, -- Whether the run's own call changed the gravity, which the clean-up then sets back
}

-- The bot's fall by tick while one is watched, and the newest tick the probe has seen; added once a server
local Watched: Tread.Character? = nil
local Falls: { [number]: Fall } = {}
local Airborne: number = 0 -- The ticks the watched bot has ended in the air
local Present: number = 0
local Probing: boolean = false

-- The probe stage, right after every character's step: keeps the tick, and the watched bot's fall on it
local function probe(tick: number)
	Present = tick

	local character: Tread.Character? = Watched
	if not character then
		return
	end

	local state: Tread.State = character:getState()
	Falls[tick] = { velocity = state.velocity.Y, mode = state.mode }

	if state.mode == AIR then
		Airborne += 1
	end
end

-- Waits a frame at a time until done says so or the seconds pass, and gives whether it got there
local function waitFor(seconds: number, done: () -> boolean): boolean
	local deadline: number = os.clock() + seconds

	while not done() do
		if os.clock() >= deadline then
			return false
		end

		RunService.Heartbeat:Wait()
	end

	return true
end

--[[
    The bot built in open air and falling, the change on the tick after the
    newest the server ran, each tick from it through CHECKED after held to
    the step's update under the new gravity, then the shared gravity back.
    Gives the first failure, or nil and the line the report carries
--]]

local function drive(handle: Tread.Server, shared: Tread.Shared, made: Made): (string?, string)
	local rate: number = shared.rates.simulation
	local terminal: number = shared.step.terminal
	local base: number = shared.step.gravity

	local bot: Volt.Bot = Volt.addBot(BOT_NAME)
	made.bot = bot

	table.clear(Falls)
	Airborne = 0

	local character: Tread.Character = handle:create(bot, CFrame.new(AT))
	made.character = character
	Watched = character

	local fell: boolean = waitFor(AIRBORNE_WAIT, function (): boolean
		return Airborne >= AIRBORNE
	end)

	if not fell then
		return `the bot fell {Airborne} of its {AIRBORNE} ticks before the change within {AIRBORNE_WAIT} s`, ""
	end

	-- A call lands on the tick after the newest the server ran, which the probe saw last
	local changeAt: number = Present + 1
	local last: number = changeAt + CHECKED
	local before: number = Airborne
	made.changed = true
	handle:setGravity(CHANGED)

	local set: number = Workspace.Gravity
	if math.abs(set - CHANGED) > READ then
		return `Workspace.Gravity read {set} after the change, not {CHANGED}`, ""
	end

	local ran: boolean = waitFor(CHECKED_WAIT, function (): boolean
		return Present >= last
	end)

	Watched = nil

	if not ran then
		return `the server ran to tick {Present} of the checks' {last} within {CHECKED_WAIT} s`, ""
	end

	-- Each tick from the change's is the step's own update of the tick before it under the new gravity
	local worst: number = 0
	for tick: number = changeAt, last do
		local now: Fall?, earlier: Fall? = Falls[tick], Falls[tick - 1]
		if not now or not earlier then
			return `the probe read no fall on tick {tick - 1} or {tick}`, ""
		elseif now.mode ~= AIR or earlier.mode ~= AIR then
			return `the bot left the air by tick {tick}, {tick - changeAt} ticks after the change`, ""
		end

		local expected: number = math.max(earlier.velocity - CHANGED / rate, -terminal)
		local off: number = math.abs(now.velocity - expected)
		worst = math.max(worst, off)

		if off > CLOSE then
			return `on tick {tick} the bot fell at {now.velocity} studs/s, not the step's {expected} under {CHANGED}`,
				""
		end
	end

	handle:setGravity(base)
	made.changed = false

	local back: number = Workspace.Gravity
	if math.abs(back - base) > READ then
		return `Workspace.Gravity read {back} after the shared gravity was put back, not {base}`, ""
	end

	local fall: string = string.format(
		"fell %d ticks under %.1f, then %d under %.1f each within %.6f studs/s of the step",
		before,
		base,
		CHECKED + 1,
		CHANGED,
		worst
	)

	return nil, string.format("%s; Workspace.Gravity read %.4f, then %.4f", fall, set, back)
end

--[[
    A sleeper moved straight down through open air, the change landing a
    few relay ticks into its fall, then every relay tick from the move's
    through the fall's end under the change read with sampleAt and held to
    Math.fall under that tick's gravity, before the shared gravity goes
    back, since the world keeps only the value before its latest change.
    Gives the first failure, or nil and the line the report carries
--]]

local function sleep(handle: Tread.Server, shared: Tread.Shared, made: Made): (string?, string)
	local rate: number = shared.rates.simulation
	local relay: number = shared.rates.relay
	local base: number = shared.step.gravity
	local low: Vector3 = SLEEPER_AT - Vector3.new(0, SLEEPER_DROP, 0)
	local from: vector = vector.create(SLEEPER_AT.X, SLEEPER_AT.Y, SLEEPER_AT.Z)
	local to: vector = vector.create(low.X, low.Y, low.Z)

	local sleeper: Tread.Sleeper? = handle:createSleeper(CFrame.new(SLEEPER_AT), {})
	made.sleeper = sleeper
	if not sleeper then
		return "createSleeper made no sleeper", ""
	end

	-- The move rides the relay tick after the newest the server ran, which the probe saw last
	local moved: number = math.floor(Present * relay / rate) + 1
	sleeper:moveTo(CFrame.new(low))

	-- A call lands on the tick after the newest the server ran, so it goes in once that tick is the one wanted
	local wanted: number = (moved + SLEEPER_CHANGE) * rate / relay
	local reached: boolean = waitFor(SLEEPER_WAIT, function (): boolean
		return Present + 1 >= wanted
	end)

	if not reached then
		return `the server ran to tick {Present}, short of the sleeper's change on {wanted}, within {SLEEPER_WAIT} s`,
			""
	end

	local changeAt: number = Present + 1
	made.changed = true
	handle:setGravity(CHANGED)

	local last: number = moved + math.ceil(math.sqrt(2 * SLEEPER_DROP / CHANGED) * relay) + SLEEPER_AFTER
	local ran: boolean = waitFor(SLEEPER_WAIT, function (): boolean
		return Present * relay / rate >= last
	end)

	if not ran then
		return `the server ran to tick {Present}, short of the sleeper's relay tick {last}, within {SLEEPER_WAIT} s`, ""
	end

	-- Each relay tick from the move's lies where Math.fall puts it under the gravity the world gives that tick
	local worst: number = 0
	local before: number, after: number = 0, 0
	local rest: number? = nil
	for tick: number = moved, last do
		local under: number = base
		if tick * rate / relay >= changeAt then
			under = CHANGED
		end

		local expected: vector, fraction: number = Math.fall(from, to, under, (tick - moved) / relay)
		local sample: Tread.Sample? = handle:sampleAt(sleeper, tick)
		if not sample then
			return `sampleAt gave the sleeper nothing at relay tick {tick}`, ""
		end

		local off: number = (sample.position - Vector3.new(expected.x, expected.y, expected.z)).Magnitude
		worst = math.max(worst, off)

		if off > SLEEPER_CLOSE then
			return `{tick - moved} ticks after its move the sleeper lay at {sample.position}, not {expected} under {under}`,
				""
		end

		if fraction >= 1 then
			if rest == nil then
				rest = tick - moved
			end
		elseif under == base then
			before += 1
		else
			after += 1
		end
	end

	handle:setGravity(base)
	made.changed = false

	if rest == nil then
		return `the sleeper was still falling {last - moved} ticks after its move`, ""
	end

	local fell: string = string.format(
		"the sleeper fell %d ticks under %.1f, then %d under %.1f from %d ticks after its move",
		before,
		base,
		after,
		CHANGED,
		math.round(changeAt * relay / rate - moved)
	)

	local landed: string =
		string.format("at rest from tick %d (%.2f s), each within %.6f studs of Math.fall", rest, rest / relay, worst)

	return nil, `{fell}, {landed}`
end

return function (): (boolean, string | nil)
	local handle: Tread.Server, shared: Tread.Shared = Game.get()

	if not Probing then
		handle:addStage(PROBE_STAGE, "simulate", probe)
		Probing = true
	end

	local made: Made = { bot = nil, character = nil, sleeper = nil, changed = false }
	local ran: boolean, failure: any, line: any = pcall(drive, handle, shared, made)

	-- The sleeper's part starts from the shared gravity, so it runs only once the bot's has put it back
	local slept: boolean, sleeperFailure: any, sleeperLine: any = true, nil, ""
	if ran and failure == nil then
		slept, sleeperFailure, sleeperLine = pcall(sleep, handle, shared, made)
	end

	-- Everything it made or changed goes back, whatever the checks did
	Watched = nil

	local restored: boolean, problem: any = true, nil
	if made.changed then
		restored, problem = pcall(handle.setGravity, handle, shared.step.gravity)
	end

	local character: Tread.Character? = made.character
	if character then
		character:destroy()
	end

	local sleeper: Tread.Sleeper? = made.sleeper
	if sleeper then
		sleeper:destroy()
	end

	local bot: Volt.Bot? = made.bot
	if bot then
		Volt.removeBot(bot)
	end

	local problems: { string } = {}
	if not ran then
		table.insert(problems, `the gravity's checks threw: {failure}`)
	elseif failure ~= nil then
		table.insert(problems, failure)
	end

	if not slept then
		table.insert(problems, `the sleeper's checks threw: {sleeperFailure}`)
	elseif sleeperFailure ~= nil then
		table.insert(problems, sleeperFailure)
	end

	if not restored then
		table.insert(problems, `the shared gravity could not be put back: {problem}`)
	end

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	local report: string = `{line}{SEPARATOR}{sleeperLine}`
	print(`Gravity: {report}`)

	return true, report
end
