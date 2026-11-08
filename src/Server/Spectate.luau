--[[
    Who spectates whom: each moderator's target and each target's watchers,
    the looks a watched target stepped since its last feed, and the feed
    that carries them beside its OwnerState once a relay tick
--]]

--!strict
--!native
local Command = require(script.Parent.Parent.Codec.Command)
local Constants = require(script.Parent.Parent.Constants)
local Feed = require(script.Parent.Parent.Codec.Feed)
local State = require(script.Parent.Parent.Step.State)
local Types = require(script.Parent.Parent.Types)

local MAX_COMMANDS: number = Constants.MAX_COMMANDS
local LOOK_BYTES: number = Constants.FEED_LOOK_BYTES
local COUNT_BYTES: number = 2 * Constants.PREFIX_BYTES -- The feed's OwnerState length and its count of looks
local MIN_OWNER_STATE: number = Constants.OWNER_STATE_BYTES + 2 * Constants.PREFIX_BYTES -- With both game blocks empty
local MAX_OWNER_STATE: number = Constants.MAX_OWNER_STATE
local WRAP: number = 2 ^ 16 -- The values a u16 wire number holds

type Bot = Types.Bot
type Key = Player | Bot
type Limits = Command.Limits
type StepCommand = State.Command

-- What the server handle starts spectate with: the limits the feed's head offsets step to, and what it sends through
export type Settings = {
	limits: Limits,
	sendFeed: (keys: { Key }, data: buffer) -> (), -- Fires one feed to every key, in one fireList
	sendSpectate: (key: Key, target: number?, tick: number) -> (), -- Fires a start, a switch or an end to a moderator
}

-- What a watched target keeps: who watches it, and the looks of the commands it stepped since its last feed
type Watched = {
	watchers: { Key },
	looks: { StepCommand }, -- Newest first and the first count current, every table made when its first watcher came
	count: number,
}

local Started: boolean = false
local Limits: Limits = { lean = 0, headCone = 0 }

-- Nothing is watched until start, so neither runs before it hands in the real ones
local SendFeed: (keys: { Key }, data: buffer) -> () = function (_: { Key }, _: buffer) end
local SendSpectate: (key: Key, target: number?, tick: number) -> () = function (_: Key, _: number?, _: number) end

local Targets: { [Key]: Key } = {} -- Each spectating moderator's target
local Watching: { [Key]: Watched } = {} -- Each watched target's watchers and looks

-- Volt sends a buffer field whole, so each feed goes in a buffer of its exact length, kept once per length
local Outgoing: { [number]: buffer } = {}

local Spectate = {}

-- Whether a value is a whole number a u16 wire field holds
local function wire(value: number): boolean
	return type(value) == "number" and value % 1 == 0 and value >= 0 and value < WRAP
end

-- Whether a value is a number above 0 and short of infinity, which NaN never is
local function positive(value: number): boolean
	return type(value) == "number" and value > 0 and value < math.huge
end

-- A target's record, made when its first watcher comes, with a table for each look a feed can carry
local function track(target: Key): Watched
	local watched: Watched? = Watching[target]
	if watched then
		return watched
	end

	local looks: { StepCommand } = {}
	for index: number = 1, MAX_COMMANDS do
		looks[index] = Command.new()
	end

	local made: Watched = { watchers = {}, looks = looks, count = 0 }
	Watching[target] = made

	return made
end

-- Takes a moderator out of its target's watchers, and forgets the target once nobody watches it
local function detach(moderator: Key, target: Key)
	local watchers: { Key } = Watching[target].watchers
	local index: number? = table.find(watchers, moderator)
	if index then
		table.remove(watchers, index)
	end

	Targets[moderator] = nil

	if #watchers == 0 then
		Watching[target] = nil
	end
end

-- Ends a moderator's spectate and sends it the end, or answers false for a moderator that watches no one
local function stop(moderator: Key, tick: number): boolean
	local target: Key? = Targets[moderator]
	if target == nil then
		return false
	end

	detach(moderator, target)
	SendSpectate(moderator, nil, tick)

	return true
end

--[[
    Starts spectate with the game's lean and cone limits and the two
    functions it sends through: sendFeed fires one feed to a target's
    watchers, and sendSpectate a start, a switch or an end to a moderator.
    It runs once
--]]

function Spectate.start(settings: Settings)
	if Started then
		error("Spectate.start runs once, and it has already run", 2)
	elseif type(settings.sendFeed) ~= "function" or type(settings.sendSpectate) ~= "function" then
		error("Spectate.start takes sendFeed and sendSpectate as functions", 2)
	end

	local limits: Limits = settings.limits
	if not (type(limits) == "table" and positive(limits.lean) and positive(limits.headCone)) then
		error("Spectate.start takes limits with lean and headCone in degrees above 0", 2)
	end

	Started = true
	Limits = { lean = limits.lean, headCone = limits.headCone }
	SendFeed = settings.sendFeed
	SendSpectate = settings.sendSpectate
end

--[[
    Starts a moderator spectating a target, or switches it from the one it
    watches, and sends the moderator the target's Record.id and the relay
    tick its new view starts at. It refuses a moderator spectating itself,
    a target who spectates and a moderator someone spectates
--]]

function Spectate.watch(moderator: Key, target: Key, id: number, tick: number)
	if not Started then
		error("Spectate.watch ran before Spectate.start", 2)
	elseif moderator == nil or target == nil then
		error("Spectate.watch takes a moderator and a target", 2)
	elseif moderator == target then
		error(`{moderator.Name} can't spectate itself`, 2)
	elseif Targets[target] ~= nil then
		error(`{moderator.Name} can't spectate {target.Name}, a moderator who spectates`, 2)
	elseif Watching[moderator] ~= nil then
		error(`{moderator.Name} can't start a spectate while being spectated`, 2)
	elseif not wire(id) or not wire(tick) then
		error(`Spectate.watch takes the target's id and the tick as u16 numbers, not {id} and {tick}`, 2)
	end

	local previous: Key? = Targets[moderator]
	if previous ~= target then
		if previous ~= nil then
			detach(moderator, previous)
		end

		table.insert(track(target).watchers, moderator)
		Targets[moderator] = target
	end

	SendSpectate(moderator, id, tick)
end

--[[
    Ends a moderator's spectate and sends it the end with the relay tick
    its own view starts again at. It answers false, and sends nothing, for
    a moderator that watches no one
--]]

function Spectate.unwatch(moderator: Key, tick: number): boolean
	if not wire(tick) then
		error(`Spectate.unwatch takes the tick as a u16 number, not {tick}`, 2)
	end

	return stop(moderator, tick)
end

--[[
    Ends every spectate of a key that dies, sleeps, is destroyed or leaves:
    each moderator watching it is sent the end, and so is the key itself
    when it was watching someone, each with the relay tick its own view
    starts again at
--]]

function Spectate.leave(key: Key, tick: number)
	if not wire(tick) then
		error(`Spectate.leave takes the tick as a u16 number, not {tick}`, 2)
	end

	local watched: Watched? = Watching[key]
	if watched then
		Watching[key] = nil

		-- Every spectate ends before the first send, so a send that throws leaves no moderator naming a lost target
		for _, moderator: Key in watched.watchers do
			Targets[moderator] = nil
		end

		for _, moderator: Key in watched.watchers do
			SendSpectate(moderator, nil, tick)
		end
	end

	stop(key, tick)
end

--[[
    The target a moderator spectates, or nil
--]]

function Spectate.targetOf(moderator: Key): Key?
	return Targets[moderator]
end

--[[
    The moderators watching a target in the module's own list, which the
    hot paths read and never change, or nil while nobody watches it
--]]

function Spectate.watchers(target: Key): { Key }?
	local watched: Watched? = Watching[target]
	if not watched then
		return nil
	end

	return watched.watchers
end

--[[
    The players spectating a target, in a new list each call, empty while
    nobody watches it. Bot moderators watch for the harness and stay out
--]]

function Spectate.spectatorsOf(target: Key): { Player }
	local players: { Player } = {}

	local watched: Watched? = Watching[target]
	if not watched then
		return players
	end

	for _, moderator: Key in watched.watchers do
		if typeof(moderator) == "Instance" then
			table.insert(players, moderator :: Player)
		end
	end

	return players
end

--[[
    Keeps the look of a command a watched target just stepped, newest
    first, dropping the oldest past a Move's worth. A target nobody watches
    keeps nothing
--]]

function Spectate.stepped(target: Key, command: StepCommand)
	local watched: Watched? = Watching[target]
	if not watched then
		return
	elseif type(command) ~= "table" then
		error(`Spectate.stepped takes the stepped command as a table, not a {typeof(command)}`, 2)
	end

	-- The oldest look past the cap, or the first spare, moves to the front and takes the newest
	local looks: { StepCommand } = watched.looks
	local last: number = math.min(watched.count + 1, MAX_COMMANDS)
	local newest: StepCommand = looks[last]

	table.move(looks, 1, last - 1, 2)
	looks[1] = newest

	newest.yaw = command.yaw
	newest.pitch = command.pitch
	newest.headYaw = command.headYaw
	newest.headPitch = command.headPitch
	watched.count = last
end

--[[
    Sends a watched target's watchers its feed: the length bytes of its
    OwnerState from owner's first byte, as the target was just sent them,
    then the looks it stepped since its last feed, which it forgets. A
    target nobody watches sends nothing
--]]

function Spectate.feed(target: Key, owner: buffer, length: number)
	local watched: Watched? = Watching[target]
	if not watched then
		return
	elseif
		not (
			type(owner) == "buffer"
			and type(length) == "number"
			and length % 1 == 0
			and length >= MIN_OWNER_STATE
			and length <= MAX_OWNER_STATE
			and length <= buffer.len(owner)
		)
	then
		error(
			`Spectate.feed takes OwnerState of {MIN_OWNER_STATE} to {MAX_OWNER_STATE} B in its buffer, not {length}`,
			2
		)
	end

	local count: number = watched.count
	local bytes: number = COUNT_BYTES + length + count * LOOK_BYTES

	local data: buffer = Outgoing[bytes] or buffer.create(bytes)
	Outgoing[bytes] = data

	Feed.write(data, owner, 0, length, watched.looks, count, Limits)
	watched.count = 0

	SendFeed(watched.watchers, data)
end

return Spectate
