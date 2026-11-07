--[[
    server:stats gives aggregate numbers only, with no position, name or
    other value but a number anywhere in it, and each figure a second as its
    counter's change since the last read: here the ticks and the stand-ins
    of a bot that never sends a Move, one a tick, and the OwnerStates sent
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local FIRST: number = 7 -- Ticks before the first read
local SECOND: number = 4 -- Ticks between it and the second
local STAGES: { string } = { "decode", "simulate", "npcs", "history", "relay" }

-- The first value in a read that is no number, with its path, or nil when every value is one
local function stray(value: any, path: string): string?
	if type(value) == "table" then
		for key: any, inner: any in value do
			local found: string? = stray(inner, `{path}.{tostring(key)}`)
			if found then
				return found
			end
		end

		return nil
	elseif type(value) ~= "number" then
		return `{path} holds a {typeof(value)}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	server:create(rig.mock:addBot("Bot"), rig:at(0, 0))
	server:createNpc(rig:at(8, 0))

	rig:tick(FIRST)
	local first: any = server:stats()

	local found: string? = stray(first, "stats")
	if found then
		return false, `A stats read is aggregate numbers only, and {found}`
	end

	if first.ticks ~= FIRST or first.standIns ~= FIRST or first.players ~= 1 or first.npcs ~= 1 then
		local bodies: string = `{first.players} players and {first.npcs} NPCs`
		return false, `The first read gave {first.ticks} ticks, {first.standIns} stand-ins, {bodies}`
	elseif first.reports.standIn ~= FIRST or first.bytesOut <= 0 or first.historyBytes <= 0 then
		local bytes: string = `{first.bytesOut} B out and {first.historyBytes} history bytes`
		return false, `The first read gave {first.reports.standIn} standIn reports, {bytes}`
	end

	for _, name: string in STAGES do
		local times: any = first.stages[name]
		if not times or not (times.p95 >= 0) or not (times.last >= 0) or times.p95 > 1 then
			return false, `The read gave the {name} stage no last time and p95`
		end
	end

	rig:tick(SECOND)
	local second: any = server:stats()

	if second.ticks ~= SECOND or second.standIns ~= SECOND or second.reports.standIn ~= SECOND then
		local counts: string = `{second.ticks} ticks and {second.standIns} stand-ins`
		return false, `The second read gave {counts}, not the {SECOND} since the first`
	elseif second.dropped ~= 0 or second.late ~= 0 or second.recordsCut ~= 0 then
		local counts: string = `{second.dropped} dropped ticks, {second.late} late commands`
		return false, `The second read gave {counts} and {second.recordsCut} records cut`
	end

	-- Read again at once, every count since the last read is 0
	local third: any = server:stats()
	if third.ticks ~= 0 or third.standIns ~= 0 or third.bytesOut ~= 0 or third.reports.standIn ~= 0 then
		return false, "A read straight after another gave counts above 0"
	end

	return true, nil
end
