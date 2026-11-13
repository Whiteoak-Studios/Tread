--[[
    What each staff scenario builds on: a floor of its own under the test
    content, its bots and the inputs that drive them, waits that each end on
    a deadline of their own, its teleports, and the clean-up of all of it
--]]

--!strict
local Testbed = {}
Testbed.__index = Testbed

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Promise: any = require(Packages.Promise)
local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Commands = require(Packages.Tread.Server.Commands)
local Connections = require(Packages.Tread.Server.Connections)

local Fleet = require(ServerScriptService.Server.Bots.Fleet)
local Game = require(ServerScriptService.Server.Game)
local Programs = require(ServerScriptService.Server.Bots.Programs)

local FLOOR: Vector3 = require(ServerScriptService.Server.Config.Staff).floor.size
local LIFT: number = require(ServerScriptService.Server.Config.Staff).floor.lift
local HEARTBEAT: number = require(ServerScriptService.Server.Config.Staff).waits.heartbeat
local HEARD: number = require(ServerScriptService.Server.Config.Staff).waits.heard
local SLACK: number = require(ServerScriptService.Server.Config.Staff).waits.slack
local SEED: number = 1 -- A driven bot has no faults, so nothing its generator draws ever matters

-- What a driven bot sends each tick, a table its scenario changes as it goes
export type Inputs = {
	forward: number, -- The move axes, each -1 to 1
	right: number,
	yaw: number, -- Radians, the step's: along -Z at 0 and -X at a quarter turn
	sprint: boolean,
	crouch: boolean,
}

-- What a character's state and intake held on one tick, copied out of the state's own table
export type Snapshot = {
	root: Vector3,
	facing: number,
	velocity: Vector3,
	epoch: number,
	platform: number,
	queued: number, -- Commands waiting in its intake for the ticks after the newest it stepped
}

-- One teleport's run, as testbed:teleport gives it back
export type Landing = {
	before: Snapshot, -- On the tick before the call
	at: CFrame, -- The last destination called, where it should land
	scheduled: number, -- The tick the call ran on, unwrapped
	after: Snapshot?, -- As the landing left it, before any step
	landed: number?, -- The tick it landed on
	heard: number, -- How many times onTeleported was called for it
}

type Rates = { simulation: number, relay: number }

type Fields = {
	_server: Tread.Server,
	_rates: Rates,
	_name: string,
	_center: Vector3,
	_folder: Folder,
	_targets: number, -- What getAll gave before the run
	_teardowns: { () -> () }, -- Each run by clean, newest first
	_ended: { [Tread.Character]: boolean }, -- The characters the run destroyed itself
}

--[[
    Lays a scenario's floor, its top at the center given, in a folder named
    for the scenario under Workspace.TestContent, whose parts the dev game's
    casts include. It errors when the place has no test content or another
    run's bots are still on the server, since the clean-up removes every bot
--]]

function Testbed.new(name: string, center: Vector3): Self
	local server: Tread.Server, shared: Tread.Shared = Game.get()

	Fleet.start()
	if #Fleet.entries() > 0 then
		error(`another run's {#Fleet.entries()} bots are still on the server`, 2)
	end

	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	if not testContent then
		error("Workspace.TestContent is missing, so the dev game's casts include nothing this could build in", 2)
	end

	local folder: Folder = Instance.new("Folder")
	folder.Name = name

	local self: Self = setmetatable({
		_server = server,
		_rates = shared.rates,
		_name = name,
		_center = center,
		_folder = folder,
		_targets = #server:getAll(),
		_teardowns = {} :: { () -> () },
		_ended = {} :: { [Tread.Character]: boolean },
	}, Testbed)

	self:part("Floor", FLOOR, CFrame.new(center - Vector3.new(0, FLOOR.Y / 2, 0)), true)
	folder.Parent = testContent

	return self
end

--[[
    An anchored part in the scenario's folder that touches nothing, which
    the bodies' casts meet when it collides
--]]

function Testbed.part(self: Self, name: string, size: Vector3, cframe: CFrame, canCollide: boolean): Part
	local made: Part = Instance.new("Part")
	made.Name = name
	made.Anchored = true
	made.CanCollide = canCollide
	made.CanQuery = true
	made.CanTouch = false
	made.Size = size
	made.CFrame = cframe
	made.Parent = self._folder

	return made
end

--[[
    Where a body is built or sent: the floor's center moved by an offset,
    lifted so the body settles onto what lies under it, and facing along a
    yaw of the step's
--]]

function Testbed.place(self: Self, offset: Vector3, yaw: number): CFrame
	return CFrame.new(self._center + offset + Vector3.new(0, LIFT, 0)) * CFrame.Angles(0, yaw, 0)
end

-- A program that sends whatever its inputs hold on each tick
local function drive(inputs: Inputs): Programs.Steer
	return function (command: Tread.Command, _: number, _: vector)
		command.forward = inputs.forward
		command.right = inputs.right
		command.yaw = inputs.yaw
		command.sprint = inputs.sprint
		command.crouch = inputs.crouch
	end
end

--[[
    A bot of the harness, which sends a Move every relay tick, driven by
    its inputs or standing at rest with none, and its character built at a
    CFrame. The clean-up removes it with every other bot
--]]

function Testbed.bot(self: Self, name: string, at: CFrame, inputs: Inputs?): Tread.Character
	local steer: Programs.Steer = Programs.idle()
	if inputs then
		steer = drive(inputs)
	end

	local entry: Fleet.Entry = Fleet.add({
		name = `{self._name}{name}`,
		group = self._name,
		at = at,
		steer = steer,
		faults = nil,
		seed = SEED,
	})

	return entry.character
end

-- One of Volt's bots with no client side and no character, which the clean-up removes
function Testbed.bare(self: Self, name: string): Volt.Bot
	local bot: Volt.Bot = Volt.addBot(`{self._name}{name}`)
	self:own(function ()
		Volt.removeBot(bot)
	end)

	return bot
end

--[[
    A bare bot's character built at a CFrame, which sends no Move and so
    stands in for every tick. The clean-up destroys it unless the run
    destroyed it itself through testbed:delete
--]]

function Testbed.plain(self: Self, name: string, at: CFrame): Tread.Character
	local bot: Volt.Bot = self:bare(name)
	local character: Tread.Character = self._server:create(bot, at)

	self:own(function ()
		if not self._ended[character] then
			character:destroy()
		end
	end)

	return character
end

-- Destroys a character the run made, which the clean-up then leaves alone
function Testbed.delete(self: Self, character: Tread.Character)
	self._ended[character] = true
	character:destroy()
end

-- Something the clean-up runs, newest first: a disconnect, a removal or a restore
function Testbed.own(self: Self, teardown: () -> ())
	table.insert(self._teardowns, teardown)
end

--[[
    The first real player who has a character, and that character, nil for
    none: an NPC has no player, and a bot's is no Instance
--]]

function Testbed.real(self: Self): (Player?, Tread.Character?)
	for _, target: Tread.Target in self._server:getAll() do
		local owner: any = (target :: any).player
		if typeof(owner) == "Instance" then
			return owner :: Player, target :: Tread.Character
		end
	end

	return nil, nil
end

-- A Promise of the next Heartbeat, which a scenario waits for after building its parts and before casting at them
function Testbed.heartbeat(self: Self): any
	return Promise.fromEvent(RunService.Heartbeat):timeout(HEARTBEAT, `waited {HEARTBEAT} s for a Heartbeat`)
end

-- The relay tick a simulation tick starts, nil for one that starts none
local function relayOf(rates: Rates, tick: number): number?
	local relayTick: number = math.floor(tick * rates.relay / rates.simulation)
	if relayTick == math.floor((tick - 1) * rates.relay / rates.simulation) then
		return nil
	end

	return relayTick
end

--[[
    A Promise run on every tick once the bots have sent, after the step,
    the history and the relay, handing each the tick and a resolve. A throw
    rejects it, and it stops listening once it settles or is cancelled
--]]

function Testbed._ticking(self: Self, each: (tick: number, resolve: (...any) -> ()) -> ()): any
	local stops: { () -> () } = {}
	local settled: boolean = false

	return Promise.new(function (resolve: (...any) -> (), reject: (...any) -> (), onCancel: (() -> ()) -> boolean)
		local function finish(...: any)
			settled = true
			resolve(...)
		end

		local stop: () -> () = Fleet.onTick(function (tick: number)
			if settled then
				return
			end

			local ran: boolean, failure: any = pcall(each, tick, finish)
			if not ran then
				settled = true
				reject(failure)
			end
		end)

		table.insert(stops, stop)
		self:own(stop)

		-- A timeout cancels it, and nothing it runs may act after that
		onCancel(function ()
			settled = true
			stop()
		end)
	end):finally(function ()
		for _, stop: () -> () in stops do
			stop()
		end
	end)
end

--[[
    A Promise of the first tick on which done holds, read once a tick after
    the step, the history and the relay, which rejects naming what it
    waited for once its seconds pass
--]]

function Testbed.waitFor(self: Self, what: string, done: (tick: number) -> boolean, seconds: number): any
	return self:_ticking(function (tick: number, resolve: (...any) -> ())
		if done(tick) then
			resolve(tick)
		end
	end):timeout(seconds, `waited {seconds} s for {what}`)
end

-- A Promise of a count of ticks from now, which rejects once they take past their length at the simulation rate
function Testbed.ticks(self: Self, count: number): any
	local seen: number = 0

	return self:waitFor(`{count} ticks`, function (_: number): boolean
		seen += 1

		return seen >= count
	end, count / self._rates.simulation + SLACK)
end

--[[
    Runs a check on each of the next count relay ticks, once the relay has
    sent, and resolves with nil when every one passed, or with how many
    failed and the first one's problem
--]]

function Testbed.sample(self: Self, count: number, check: (relayTick: number) -> string?): any
	local seconds: number = count / self._rates.relay + SLACK
	local seen: number = 0
	local failed: number = 0
	local first: string? = nil

	return self:_ticking(function (tick: number, resolve: (...any) -> ())
		local relayTick: number? = relayOf(self._rates, tick)
		if relayTick == nil then
			return
		end

		seen += 1

		local problem: string? = check(relayTick)
		if problem then
			failed += 1

			if first == nil then
				first = `relay tick {relayTick}: {problem}`
			end
		end

		if seen < count then
			return
		end

		local found: string? = first
		if found then
			resolve(`{failed} of {count} relay ticks failed, the first on {found}`)
		else
			resolve(nil)
		end
	end):timeout(seconds, `waited {seconds} s for {count} relay ticks`)
end

-- What a character's state and its intake hold now, copied out
local function snapshot(character: Tread.Character): Snapshot
	local state: Tread.State = character:getState()
	local connection: Connections.Connection? = Connections.get(character.player)

	local queued: number = 0
	if connection then
		queued = Commands.depth(connection)
	end

	return {
		root = state.root,
		facing = state.facing,
		velocity = state.velocity,
		epoch = state.epoch,
		platform = state.platform,
		queued = queued,
	}
end

--[[
    A Promise of one teleport's Landing: the character read on one tick,
    sent on the next to each CFrame destinations gives for that read, in
    turn, and read again inside onTeleported as it lands, then listened to
    for HEARD ticks more. getState refills once a step, so the read before
    and the landing's read never share a fill. It rejects once its seconds
    pass, and with a call that throws
--]]

function Testbed.teleport(
	self: Self,
	character: Tread.Character,
	destinations: (before: Snapshot) -> { CFrame },
	seconds: number
): any
	local before: Snapshot? = nil
	local landing: Landing? = nil
	local latest: number = 0 -- The newest tick the bots sent on, so a landing in the next decode is on the one after

	local stopHeard: () -> () = self._server:onTeleported(function (moved: Tread.Character)
		local made: Landing? = landing
		if moved ~= character or not made then
			return
		end

		made.heard += 1
		if made.heard == 1 then
			made.after = snapshot(character)
			made.landed = latest + 1
		end
	end)

	self:own(stopHeard)

	return self:_ticking(function (tick: number, resolve: (...any) -> ())
		latest = tick

		local from: Snapshot? = before
		local made: Landing? = landing
		if not from then
			before = snapshot(character)

			return
		elseif not made then
			local list: { CFrame } = destinations(from)
			if #list == 0 then
				error("testbed:teleport was given no destination")
			end

			for _, at: CFrame in list do
				character:teleport(at)
			end

			landing = { before = from, at = list[#list], scheduled = tick, after = nil, landed = nil, heard = 0 }

			return
		end

		local landed: number? = made.landed
		if landed and tick >= landed + HEARD then
			resolve(made)
		end
	end)
		:finally(stopHeard)
		:timeout(seconds, `waited {seconds} s for {character.player.Name}'s teleport to land`)
end

--[[
    Takes away everything the run made, whatever its checks found: each
    teardown it owns, newest first, then every bot, then its folder, and
    checks the handle lists the same targets it did before. Gives what
    failed, empty when nothing did
--]]

function Testbed.clean(self: Self): { string }
	local problems: { string } = {}
	local teardowns: { () -> () } = self._teardowns

	for index: number = #teardowns, 1, -1 do
		local ran: boolean, failure: any = pcall(teardowns[index])
		if not ran then
			table.insert(problems, `taking away what it made threw: {failure}`)
		end
	end

	table.clear(teardowns)

	for _, problem: string in Fleet.clear() do
		table.insert(problems, problem)
	end

	self._folder:Destroy()

	local left: number = #self._server:getAll()
	if left ~= self._targets then
		table.insert(problems, `after the clean-up getAll gave {left} targets, where it gave {self._targets} before`)
	end

	return problems
end

export type Testbed = Self
type Self = typeof(setmetatable({} :: Fields, Testbed))

return Testbed
