--[[
    server:spectate starts a moderator on a target, switches it and ends it,
    each sending the moderator its Spectate with the target's id and the
    next relay tick; the target's feed reaches it while it watches, and the
    target's death ends the spectate
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 3

type Heard = { target: number?, tick: number }

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Record: any = rig:require(rig.tread.Codec.Record)
	local Spectate: any = rig:require(rig.tread.Server.Spectate)

	local client: any = rig:require(rig.tread.Network.Client)
	local moderatorKey: any = rig.mock.players[1]
	local heard: { Heard } = {}
	local feeds: number = 0

	client.Spectate.on(function (target: number?, tick: number)
		table.insert(heard, { target = target, tick = tick })
	end)

	client.Feed.on(function (_: buffer)
		feeds += 1
	end)

	client.flush()
	rig:deliver()

	server:create(moderatorKey, rig:at(0, 0))
	local first: any = server:create(rig.mock:addBot("First"), rig:at(6, 0))
	local second: any = server:create(rig.mock:addBot("Second"), rig:at(-6, 0))
	rig:tick(TICKS)

	server:spectate(moderatorKey, first)
	if Spectate.targetOf(moderatorKey) ~= first.player then
		return false, "The spectate's start left the moderator watching no one"
	end

	rig:tick(TICKS)
	rig:deliver()

	local start: Heard? = heard[1]
	if not start or start.target ~= Record.id(first._slot, first._generation) or start.tick ~= TICKS + 1 then
		return false, `The moderator heard {#heard} Spectates, the first not naming the target from tick {TICKS + 1}`
	elseif feeds == 0 then
		return false, "The moderator got no feed of the target it watched"
	end

	-- A switch names the new target, and the old one keeps no watcher
	server:spectate(moderatorKey, second)
	rig:tick(1)
	rig:deliver()

	local switch: Heard? = heard[2]
	if not switch or switch.target ~= Record.id(second._slot, second._generation) then
		return false, "The switch sent the moderator no Spectate naming the new target"
	elseif Spectate.watchers(first.player) ~= nil then
		return false, "The old target kept the moderator as a watcher after the switch"
	end

	-- The end names no target, and the feed stops
	server:spectate(moderatorKey, nil)
	rig:tick(1)
	rig:deliver()

	local ending: Heard? = heard[3]
	local feedsEnded: number = feeds
	rig:tick(TICKS)
	rig:deliver()

	if not ending or ending.target ~= nil or Spectate.targetOf(moderatorKey) ~= nil then
		return false, "The end sent the moderator no Spectate with no target, or left it watching"
	elseif feeds ~= feedsEnded then
		return false, `The moderator got {feeds - feedsEnded} feeds after its spectate ended`
	end

	-- The target's death ends a spectate of it
	server:spectate(moderatorKey, first)
	first:die(nil)
	rig:tick(1)
	rig:deliver()

	local last: Heard? = heard[#heard]
	if Spectate.targetOf(moderatorKey) ~= nil or not last or last.target ~= nil or #heard ~= 5 then
		return false, `The target's death left the moderator watching, or sent {#heard} Spectates, not 5`
	end

	return true, nil
end
