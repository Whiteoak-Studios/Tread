--[[
    Fires one fixture shot from a bot at another on a floor it lays: the
    Bow's bullet leaves the shooter's cleared eye, flies its ticks on the
    shooter's timeline and must strike the target bot
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Constants = require(Packages.Tread.Constants)

local Fleet = require(ServerScriptService.Server.Bots.Fleet)
local Game = require(ServerScriptService.Server.Game)
local Shots = require(ServerScriptService.Server.Fixtures.Shots)

local DELAY: number = require(ServerScriptService.Server.Bots.Config).delay
local CENTER: Vector3 = require(ServerScriptService.Server.Config.Fixtures).scenario.center
local FLOOR_SIZE: Vector3 = require(ServerScriptService.Server.Config.Fixtures).scenario.floor
local LIFT: number = require(ServerScriptService.Server.Config.Fixtures).scenario.lift
local APART: number = require(ServerScriptService.Server.Config.Fixtures).scenario.apart
local SLOT: number = require(ServerScriptService.Server.Config.Fixtures).scenario.slot
local SETTLE: number = require(ServerScriptService.Server.Config.Fixtures).scenario.settle
local WAIT: number = require(ServerScriptService.Server.Config.Fixtures).scenario.wait
local ANGLE_STEPS: number = Constants.ANGLE_STEPS -- A shot's packed yaw and pitch step through a turn in these
local RENDER_TICKS: number = 2 ^ 16 -- A shot's renderTick holds the low 16 bits of its render tick
local TURN: number = 2 * math.pi
local SEED: number = 1 -- Neither bot has faults, so nothing either draws ever matters
local SEPARATOR: string = "; " -- Between the problems in one report

-- The two bots one run built, which the shooter's program reads once both stand
type Made = {
	shooter: Fleet.Entry?,
	target: Fleet.Entry?,
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

-- The resolved shot the shooter fired, or nil before it resolves
local function resultOf(shooter: Tread.Character): Shots.Result?
	for _, result: Shots.Result in Shots.results() do
		if result.shooter == shooter then
			return result
		end
	end

	return nil
end

--[[
    Both bots built facing each other along Z, the shooter firing once
    the settle has passed: its one command carries the Bow and a shot from
    its eye at the target's chest, claiming the render time its round trip
    and reported delay give, and every command before and after carries none
--]]

local function drive(made: Made, shared: Tread.Shared, settings: Tread.ServerSettings): (boolean, string)
	local bots: { rtt: number }? = settings.bots
	if not bots then
		return false, "the dev game's server settings give its bots no round trip"
	end

	local behind: number = math.round((bots.rtt + DELAY) * shared.rates.relay)
	local chest: Tread.Shape = shared.hitShapes.Stand.zones.chest
	local center: Vector3 = (chest.from + chest.to) / 2
	local fireAt: number = os.clock() + SETTLE
	local fired: boolean = false

	local function steer(command: Tread.Command, _: number, _: vector)
		local shooter: Fleet.Entry? = made.shooter
		local target: Fleet.Entry? = made.target
		if fired or not shooter or not target or os.clock() < fireAt then
			return
		end

		fired = true

		local eye: Vector3 = shooter.character:getState().eye
		local direction: Vector3 = (target.character:getState().root + center - eye).Unit
		local yaw: number = math.atan2(-direction.X, -direction.Z)
		local pitch: number = math.asin(direction.Y)

		command.fields = {
			slot = SLOT,
			shots = {
				{
					sequence = 0,
					class = 0,
					renderTick = (command.number - behind) % RENDER_TICKS,
					fraction = 0,
					yaw = math.round(yaw / TURN * ANGLE_STEPS) % ANGLE_STEPS,
					pitch = math.round(pitch / TURN * ANGLE_STEPS),
				},
			},
		}
	end

	-- The shooter faces -Z, toward the target, as a CFrame with no turn does
	local raised: Vector3 = CENTER + Vector3.new(0, LIFT, 0)
	local targetAt: CFrame = CFrame.new(raised - Vector3.new(0, 0, APART / 2))
	local shooterAt: CFrame = CFrame.new(raised + Vector3.new(0, 0, APART / 2))

	made.target =
		Fleet.add({ name = "FixtureTarget", group = "fixture", at = targetAt, steer = nil, faults = nil, seed = SEED })
	made.shooter = Fleet.add({
		name = "FixtureShooter",
		group = "fixture",
		at = shooterAt,
		steer = steer,
		faults = nil,
		seed = SEED,
	})

	local shooter: Tread.Character = (made.shooter :: Fleet.Entry).character
	local target: Tread.Character = (made.target :: Fleet.Entry).character

	local resolved: boolean = waitFor(function (): boolean
		return resultOf(shooter) ~= nil
	end)

	local result: Shots.Result? = resultOf(shooter)
	if not resolved or not result then
		local sent: string = fired and "made" or "never made"
		return false, `the shooter's shot had not resolved {WAIT} s after the bots were built, its command {sent}`
	end

	local struck: Shots.Strike? = result.strike
	local line: string =
		`fired on tick {result.fired}, {result.offset} relay ticks behind, inside the band {result.inside}`
	if not struck then
		return false, `the shot {line} missed on tick {result.tick} for {result.reason}`
	elseif struck.target ~= target then
		return false, `the shot {line} struck something other than the target on tick {result.tick}`
	end

	return true, `the Bow's shot {line}, struck the target's {struck.zone} on tick {result.tick}`
end

return function (): (boolean, string | nil)
	local _, shared: Tread.Shared, settings: Tread.ServerSettings = Game.get()
	Fleet.start()
	if #Fleet.entries() > 0 then
		return false, `another run's {#Fleet.entries()} bots are still on the server`
	end

	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	if not testContent then
		return false, "Workspace.TestContent is missing, so the dev game's casts include nothing this could build in"
	end

	local folder: Folder = Instance.new("Folder")
	folder.Name = "FixtureShot"

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

	local made: Made = { shooter = nil, target = nil }
	local ran: boolean, passed: any, line: any = pcall(drive, made, shared, settings)

	-- Everything it made goes, whatever the checks did
	local problems: { string } = Fleet.clear()
	folder:Destroy()
	Shots.clear()

	if not ran then
		table.insert(problems, `the run threw: {passed}`)
	elseif not passed then
		table.insert(problems, line)
	end

	print(`FixtureShot: {ran and line or passed}`)

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, line
end
