--[[
    A watch sends the moderator the target's id and tick and lists it under
    the target, a switch moves it with a fresh message, a repeat restarts
    it, and an unwatch sends the end and then answers false
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local SPECTATE: string = "src/Server/Spectate.luau"
local FIRST_ID: number = 1 + 1 * 4096 -- Slot 1, generation 1
local SECOND_ID: number = 4095 + 15 * 4096 -- The highest slot and generation, 65,535
local LAST_TICK: number = 65535 -- A u16 tick's top

return function (): (boolean, string | nil)
	local Spectate: any = Environment.load(SPECTATE)

	-- Each sendSpectate call as its key, target and tick
	local sent: { { any } } = {}
	Spectate.start({
		limits = Game.limits,
		sendFeed = function (_: { any }, _: buffer) end,
		sendSpectate = function (key: any, target: number?, tick: number)
			table.insert(sent, { key, target, tick })
		end,
	})

	-- Whether the message at index went to key with target and tick
	local function was(index: number, key: any, target: number?, tick: number): boolean
		local message: { any }? = sent[index]
		return message ~= nil and message[1] == key and message[2] == target and message[3] == tick
	end

	local moderator: any = roblox.Instance.new("Player")
	local other: any = roblox.Instance.new("Player")
	local first: any = roblox.Instance.new("Player")
	local second: { Name: string } = { Name = "Bot" }

	Spectate.watch(moderator, first, FIRST_ID, 0)
	local watchers: { any }? = Spectate.watchers(first)
	if #sent ~= 1 or not was(1, moderator, FIRST_ID, 0) then
		return false, "A watch did not send the moderator the target's id and tick once"
	elseif Spectate.targetOf(moderator) ~= first or not watchers or #watchers ~= 1 or watchers[1] ~= moderator then
		return false, "A watch did not list the moderator under its target"
	elseif Spectate.targetOf(first) ~= nil then
		return false, "The target became a moderator of its own"
	end

	-- A second moderator joins the same list
	Spectate.watch(other, first, FIRST_ID, 1)
	watchers = Spectate.watchers(first)
	if not was(2, other, FIRST_ID, 1) or not watchers or #watchers ~= 2 or watchers[2] ~= other then
		return false, "A second moderator did not join the target's watchers"
	end

	-- A switch leaves the first target's list and joins the second's, at the top of the id and tick
	Spectate.watch(moderator, second, SECOND_ID, LAST_TICK)
	watchers = Spectate.watchers(first)
	local switched: { any }? = Spectate.watchers(second)
	if #sent ~= 3 or not was(3, moderator, SECOND_ID, LAST_TICK) then
		return false, "A switch did not send the moderator the new target's id and tick"
	elseif Spectate.targetOf(moderator) ~= second or not switched or #switched ~= 1 or switched[1] ~= moderator then
		return false, "A switch did not list the moderator under its new target"
	elseif not watchers or #watchers ~= 1 or watchers[1] ~= other then
		return false, "A switch left the moderator under its old target, or took the other moderator out"
	end

	-- A repeat of the same target sends the start again with its new tick, and lists the moderator once
	Spectate.watch(moderator, second, SECOND_ID, 0)
	switched = Spectate.watchers(second)
	if not was(4, moderator, SECOND_ID, 0) or not switched or #switched ~= 1 then
		return false, "A repeated watch did not restart the view once"
	end

	-- An unwatch sends the end, and the last watcher leaving forgets the target
	if Spectate.unwatch(moderator, 7) ~= true or #sent ~= 5 or not was(5, moderator, nil, 7) then
		return false, "An unwatch did not answer true and send the moderator the end"
	elseif Spectate.targetOf(moderator) ~= nil or Spectate.watchers(second) ~= nil then
		return false, "An unwatch left the moderator watching or the target listed"
	end

	if Spectate.unwatch(moderator, 8) ~= false or #sent ~= 5 then
		return false, "Unwatching a moderator that watches no one answered other than false, or sent something"
	end

	if Spectate.unwatch(other, 9) ~= true or Spectate.watchers(first) ~= nil or not was(6, other, nil, 9) then
		return false, "The other moderator's unwatch did not end its spectate and forget the first target"
	end

	return true, nil
end
