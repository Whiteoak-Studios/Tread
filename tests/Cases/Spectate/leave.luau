--[[
    A watched target that leaves ends every spectate of it, each watcher
    sent the end with the tick, a moderator that leaves ends its own, and a
    key in neither role sends nothing, while other spectates go on
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local SPECTATE: string = "src/Server/Spectate.luau"
local TARGET_ID: number = 4097
local OTHER_ID: number = 4098
local LEFT_AT: number = 20
local MODERATOR_LEFT_AT: number = 21

return function (): (boolean, string | nil)
	local Spectate: any = Environment.load(SPECTATE)

	local sent: { { any } } = {}
	Spectate.start({
		limits = Game.limits,
		sendFeed = function (_: { any }, _: buffer) end,
		sendSpectate = function (key: any, target: number?, tick: number)
			table.insert(sent, { key, target, tick })
		end,
	})

	local function was(index: number, key: any, target: number?, tick: number): boolean
		local message: { any }? = sent[index]
		return message ~= nil and message[1] == key and message[2] == target and message[3] == tick
	end

	local player: any = roblox.Instance.new("Player")
	local bot: { Name: string } = { Name = "Bot" }
	local third: any = roblox.Instance.new("Player")
	local target: any = roblox.Instance.new("Player")
	local other: any = roblox.Instance.new("Player")

	Spectate.watch(player, target, TARGET_ID, 1)
	Spectate.watch(bot, target, TARGET_ID, 1)
	Spectate.watch(third, other, OTHER_ID, 1)

	-- The target leaves: both of its watchers get the end, in the order they came
	Spectate.leave(target, LEFT_AT)
	if #sent ~= 5 or not was(4, player, nil, LEFT_AT) or not was(5, bot, nil, LEFT_AT) then
		return false, "A target that left did not send each of its watchers the end once"
	elseif Spectate.targetOf(player) ~= nil or Spectate.targetOf(bot) ~= nil or Spectate.watchers(target) ~= nil then
		return false, "A target that left is still watched"
	end

	local watchers: { any }? = Spectate.watchers(other)
	if Spectate.targetOf(third) ~= other or not watchers or #watchers ~= 1 then
		return false, "A target leaving ended another target's spectate"
	end

	-- A moderator leaves: its own spectate ends, and it is sent the end too
	Spectate.leave(third, MODERATOR_LEFT_AT)
	if #sent ~= 6 or not was(6, third, nil, MODERATOR_LEFT_AT) then
		return false, "A moderator that left was not sent the end of its spectate"
	elseif Spectate.targetOf(third) ~= nil or Spectate.watchers(other) ~= nil then
		return false, "A moderator that left is still watching"
	end

	-- Neither a target nor a moderator: nothing to end
	Spectate.leave(player, MODERATOR_LEFT_AT)
	if #sent ~= 6 then
		return false, "A key that watched nobody and nobody watched sent something on leaving"
	end

	-- Once it has left, the target may spectate, and be spectated, again
	Spectate.watch(target, other, OTHER_ID, LEFT_AT)
	if Spectate.targetOf(target) ~= other or not was(7, target, OTHER_ID, LEFT_AT) then
		return false, "A target that left could not start a spectate of its own"
	end

	return true, nil
end
