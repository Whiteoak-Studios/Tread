--[[
    A bot numbers each tick's command its lead past the server's tick, across
    the u16 wrap, sends each relay tick's Move with the new command and the
    two before it, newest first, and flushes it, and steers only once its
    first OwnerState says where its body stands
--]]

--!strict
local Harness = require("../../Fixtures/DevBot/Harness")

local WRAP: number = 2 ^ 16
local NEAR_WRAP: number = WRAP - 4 -- A tick a few short of the u16 wrap
local REPEATS: number = 2 -- The commands each Move repeats before its new one
local MILLISECONDS: number = 150 -- The delay the bot harness's config reports, 0.15 s
local SEED: number = 1
local FIRST_TICKS: number = 4 -- Ticks run before any OwnerState

return function (): (boolean, string | nil)
	local harness: Harness.Loaded = Harness.load()
	local side: Harness.Side = Harness.side()
	local context: any = harness.context
	local steered: number = 0

	local bot: any = harness.Bot.new(side.network, context, function (command: any, _: number, _: vector)
		steered += 1
		command.forward = 1
	end, nil, SEED)

	if side.flushes ~= 1 then
		return false, `A new bot flushed {side.flushes} times, not once for its handshake`
	elseif side.listeners.Owner == nil or side.listeners.Relay == nil or side.listeners.Slots == nil then
		return false, "A new bot did not hear its OwnerState, the relay and the slot table"
	end

	-- Before any OwnerState: numbered by the lead, sent at rest
	for tick: number = 1, FIRST_TICKS do
		bot:tick(tick)
	end

	local fourth: Harness.Fired = side.fired[FIRST_TICKS]
	if #side.fired ~= FIRST_TICKS or side.flushes ~= FIRST_TICKS + 1 then
		return false, `{FIRST_TICKS} ticks fired {#side.fired} Moves and flushed {side.flushes} times`
	elseif fourth.command ~= FIRST_TICKS + context.lead or #fourth.commands ~= 1 + REPEATS then
		return false, `The fourth Move's newest command is {fourth.command} with {#fourth.commands} in all`
	elseif #side.fired[1].commands ~= 1 or #side.fired[2].commands ~= 2 then
		return false, "The first Moves repeated commands the bot never made"
	elseif fourth.commands[2].number ~= 3 + context.lead or fourth.commands[3].number ~= 2 + context.lead then
		return false, "The fourth Move's commands are not newest first, each one below the one before"
	elseif steered ~= 0 or fourth.commands[1].moveZ ~= 0 then
		return false, "The bot steered before its first OwnerState said where its body stood"
	elseif fourth.delay ~= MILLISECONDS or fourth.acknowledged ~= 0 or fourth.received ~= 0 then
		return false, `The Move reported a delay of {fourth.delay} and acknowledgments before any relay block`
	end

	-- Once its body stands somewhere, every command is steered
	side.listeners.Owner(Harness.owner(harness, vector.create(0, 10, 0), vector.zero, FIRST_TICKS, FIRST_TICKS))
	bot:tick(FIRST_TICKS + 1)

	if steered ~= 1 or side.fired[FIRST_TICKS + 1].commands[1].moveZ == 0 then
		return false, "The bot did not steer once its OwnerState had arrived"
	elseif bot:measure().heard ~= 1 then
		return false, `The bot measured {bot:measure().heard} OwnerStates heard, not one`
	end

	-- Across the u16 wrap the numbers run on, and the Move still carries the run
	local wrapping: Harness.Side = Harness.side()
	local around: any = harness.Bot.new(wrapping.network, context, function () end, nil, SEED)

	for tick: number = NEAR_WRAP, NEAR_WRAP + 5 do
		around:tick(tick)
	end

	local last: Harness.Fired = wrapping.fired[#wrapping.fired]
	local newest: number = (NEAR_WRAP + 5 + context.lead) % WRAP
	if last.command ~= newest or #last.commands ~= 1 + REPEATS then
		return false, `Past the wrap the newest command is {last.command} with {#last.commands}, not {newest}`
	elseif last.commands[3].number ~= (newest - 2) % WRAP then
		return false, `Past the wrap the oldest repeat is {last.commands[3].number}`
	end

	bot:destroy()
	around:destroy()

	return true, nil
end
