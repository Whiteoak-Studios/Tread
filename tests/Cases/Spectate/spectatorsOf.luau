--[[
    A bot may spectate, and the watchers list holds it, while spectatorsOf
    gives only the players in a new list each call, which a caller may
    change, and an empty one for a target nobody watches
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local SPECTATE: string = "src/Server/Spectate.luau"
local ID: number = 4097

return function (): (boolean, string | nil)
	local Spectate: any = Environment.load(SPECTATE)
	Spectate.start({
		limits = Game.limits,
		sendFeed = function (_: { any }, _: buffer) end,
		sendSpectate = function (_: any, _: number?, _: number) end,
	})

	local first: any = roblox.Instance.new("Player")
	local bot: { Name: string } = { Name = "Bot" }
	local second: any = roblox.Instance.new("Player")
	local target: any = roblox.Instance.new("Player")

	local empty: { any } = Spectate.spectatorsOf(target)
	if type(empty) ~= "table" or #empty ~= 0 then
		return false, "A target nobody watches had spectators, or no list"
	end

	Spectate.watch(first, target, ID, 0)
	Spectate.watch(bot, target, ID, 0)
	Spectate.watch(second, target, ID, 0)

	local watchers: { any }? = Spectate.watchers(target)
	if not watchers or #watchers ~= 3 or watchers[2] ~= bot then
		return false, "The bot moderator is not among the target's watchers"
	end

	local spectators: { any } = Spectate.spectatorsOf(target)
	if #spectators ~= 2 or spectators[1] ~= first or spectators[2] ~= second then
		return false, `spectatorsOf gave {#spectators} keys, not the two players in the order they came`
	elseif spectators == watchers then
		return false, "spectatorsOf handed out the module's own list"
	end

	-- A caller's change to its list reaches neither the module nor the next call
	table.clear(spectators)
	local again: { any } = Spectate.spectatorsOf(target)
	if again == spectators or #again ~= 2 or #(Spectate.watchers(target) :: { any }) ~= 3 then
		return false, "Clearing one call's list changed the watchers or the next call's list"
	end

	return true, nil
end
