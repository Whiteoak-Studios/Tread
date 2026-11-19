--[[
    The tick runs decode, simulate, npcs, history, antiEsp and relay in that
    order, a game's stage added after simulate runs straight after it, one
    naming no stage is refused, and a game stage that throws is reported as
    stage with its name while the tick and every later stage go on
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local ORDER: { string } = { "decode", "simulate", "zones", "npcs", "history", "antiEsp", "relay" }
local TICKS: number = 3

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Tick: any = rig:require(rig.tread.Server.Tick)
	local character: any = server:create(rig.mock:addBot("Bot"), rig:at(0, 0))

	local seen: { number } = {}
	server:addStage("zones", "simulate", function (tick: number)
		table.insert(seen, tick)
		error("This game stage throws on purpose, to show the tick goes on")
	end)

	if pcall(server.addStage, server, "late", "ballistics", function (_: number) end) then
		return false, "addStage took a stage after ballistics, which the tick does not run"
	elseif pcall(server.addStage, server, "zones", "relay", function (_: number) end) then
		return false, "addStage took a second stage named zones"
	end

	local names: { string } = {}
	for _, stage: any in Tick.stages() do
		table.insert(names, stage.name)
	end

	if table.concat(names, ",") ~= table.concat(ORDER, ",") then
		return false, `The tick runs {table.concat(names, ", ")}, not {table.concat(ORDER, ", ")}`
	end

	rig:tick(TICKS)

	if #seen ~= TICKS or seen[TICKS] ~= TICKS then
		return false, `The zones stage ran on {#seen} ticks, not each of the {TICKS}`
	end

	local reported: { number | string } = rig:reported("stage")
	if #reported ~= TICKS or reported[1] ~= "zones" then
		return false, `The throwing stage gave {#reported} stage reports, not one a tick naming zones`
	end

	-- The character still fell from where it was built, and its history, a later stage, still took the last tick
	local built: number = rig:at(0, 0).Position.Y
	if not (character:getState().root.Y < built) or not server:sampleAt(character, TICKS) then
		return false, "The stages after the throwing one stopped running"
	end

	return true, nil
end
