--[[
    character:destroy and npc:destroy release all each holds: the slot, the
    range query's entry, the history, the connection record and the place
    in a viewer's view, and leave as many callbacks connected to the slot
    table and the reports as before they were built; a destroyed handle
    refuses every call, and its bot can build a new character
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Rig = require("../../Fixtures/Server/Rig")

local REPORTS: string = "src/Server/Reports.luau"
local SLOTS: string = "src/Server/Slots.luau"
local TICKS: number = 4
local DROP: number = 6 -- Studs above the floor the NPC is built at, so it lands while the case watches
local FALL_TICKS: number = 20

-- A module's table with one function counting the callbacks it connects and has not yet disconnected
local function counting(module: any, member: string, counts: { [string]: number }): any
	local wrapped: any = table.clone(module)
	counts[member] = 0

	wrapped[member] = function (callback: any): () -> ()
		counts[member] += 1
		local disconnect: () -> () = module[member](callback)
		local connected: boolean = true

		return function ()
			if connected then
				connected = false
				counts[member] -= 1
			end

			disconnect()
		end
	end

	return wrapped
end

return function (): (boolean, string | nil)
	local counts: { [string]: number } = {}
	local rig: Rig.Rig = Rig.new(nil, {
		["ReplicatedStorage.Packages.Tread.Server.Reports"] = counting(Environment.load(REPORTS), "connect", counts),
		["ReplicatedStorage.Packages.Tread.Server.Slots"] = counting(Environment.load(SLOTS), "onChange", counts),
	})

	local server: any = rig:start()
	local Connections: any = rig:require(rig.tread.Server.Connections)
	local Relay: any = rig:require(rig.tread.Server.Relay)
	local Slots: any = rig:require(rig.tread.Server.Slots)

	local reportsBefore: number, slotsBefore: number = counts.connect, counts.onChange

	local bot: any = rig.mock:addBot("Bot")
	local watcherBot: any = rig.mock:addBot("Watcher")
	server:create(watcherBot, rig:at(0, 0))
	local character: any = server:create(bot, rig:at(6, 0))
	local npc: any = server:createNpc(roblox.CFrame.new(-6, rig.floor + DROP, 0))

	-- A game's callbacks, connected and disconnected again, hear nothing more
	local landings: number = 0
	local stopLanded: () -> () = server:onLanded(function ()
		landings += 1
	end)
	local stopReports: () -> () = server:onReport(function () end)
	stopLanded()
	stopReports()

	rig:tick(FALL_TICKS)

	local slot: number = character._slot
	local npcSlot: number = npc._slot
	if landings ~= 0 then
		return false, `A disconnected landing callback heard {landings} landings`
	elseif not Relay.isSent(watcherBot, slot) then
		return false, "The watcher was never sent the character beside it"
	end

	character:destroy()
	npc:destroy()
	rig:tick(TICKS)

	local _, entry: any = Slots.get(slot)
	local _, npcEntry: any = Slots.get(npcSlot)
	local around: { string } = server:near(roblox.Vector3.new(6, rig.floor, 0), 1)

	if entry ~= nil or npcEntry ~= nil then
		return false, "A destroyed handle's slot is still taken"
	elseif #around ~= 0 or #server:npcsNear(roblox.Vector3.new(-6, rig.floor, 0), 1) ~= 0 then
		return false, "A destroyed handle is still in the range query"
	elseif server:sampleAt(character, FALL_TICKS) ~= nil or server:sampleAt(npc, FALL_TICKS) ~= nil then
		return false, "A destroyed handle still answers from the history"
	elseif Connections.get(bot) ~= nil then
		return false, "A destroyed character's bot still has a connection record"
	elseif Relay.isSent(watcherBot, slot) then
		return false, "The watcher is still sent the destroyed character"
	elseif #server:getAll() ~= 1 then
		return false, `After both destroys getAll gave {#server:getAll()} targets, not the watcher`
	end

	if counts.connect ~= reportsBefore or counts.onChange ~= slotsBefore then
		local now: string = `{counts.connect} report and {counts.onChange} slot table callbacks`
		return false, `{now} are connected, where {reportsBefore} and {slotsBefore} were before the handles`
	end

	local calls: { string } = { "getState", "destroy", "setInvisible" }
	for _, name: string in calls do
		if pcall(character[name], character, false) then
			return false, `A destroyed character took {name}`
		end
	end

	if pcall(npc.command, npc, {}) then
		return false, "A destroyed NPC took a command"
	end

	local again: any = server:create(bot, rig:at(6, 0))
	again:destroy()

	return true, nil
end
