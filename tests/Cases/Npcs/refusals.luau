--[[
    Npcs refuses what it cannot run, naming it: a call before its start, a
    second start, a bad world or callback, a position, facing, command,
    awake flag, tick or visit of the wrong kind, and a destroyed NPC's calls
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local CONSTANTS: string = "src/Constants.luau"

type Refusal = {
	label: string,
	call: () -> (),
	refusal: string,
}

-- Why a call that should refuse ran, or failed with another message, or nil
local function refuses(refusal: Refusal): string?
	local ran: boolean, message: any = pcall(refusal.call)
	if ran then
		return `{refusal.label} was taken`
	elseif not string.find(`{message}`, refusal.refusal, 1, true) then
		return `{refusal.label} was refused with something other than "{refusal.refusal}": {message}`
	end

	return nil
end

-- Why the first of the refusals that failed to refuse did, or nil
local function refuseAll(refusals: { Refusal }): string?
	for _, refusal: Refusal in refusals do
		local failure: string? = refuses(refusal)
		if failure then
			return failure
		end
	end

	return nil
end

-- An NPC command with one key set to a value of the wrong kind
local function badOrder(stage: any, key: string, value: any): any
	local order: any = stage.order()
	order[key] = value

	return order
end

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	local bound: number = Environment.load(CONSTANTS).PLAY_BOUND
	local outside: string = `inside the {bound}-stud play bound`
	local Npcs: any = stage.Npcs
	local resting: number = stage.resting
	local at: vector = vector.create(-20, resting, 0)

	local early: string? = refuseAll({
		{
			label = "a create before the start",
			call = function ()
				Npcs.create(at, 0)
			end,
			refusal = "ran before Npcs.start",
		},
		{
			label = "a step before the start",
			call = function ()
				Npcs.step(1)
			end,
			refusal = "ran before Npcs.start",
		},
		{
			label = "a start with no world",
			call = function ()
				Npcs.start(nil, function () end)
			end,
			refusal = "takes the server's World",
		},
		{
			label = "a start with no landing callback",
			call = function ()
				Npcs.start(stage.world, "landed")
			end,
			refusal = "takes the landing callback as a function",
		},
	})
	if early then
		return false, early
	end

	stage.start()

	local npc: any = Npcs.create(at, 0)
	local doomed: any = Npcs.create(vector.create(-20, resting, 10), 0)
	doomed:destroy()

	local refused: string? = refuseAll({
		{
			label = "a second start",
			call = function ()
				Npcs.start(stage.world, function () end)
			end,
			refusal = "runs once",
		},
		{
			label = "a Vector3 position",
			call = function ()
				Npcs.create(roblox.Vector3.new(-20, resting, 0), 0)
			end,
			refusal = "takes its position as a vector",
		},
		{
			label = "a position whose x is not a number",
			call = function ()
				Npcs.create(vector.create(0 / 0, resting, 0), 0)
			end,
			refusal = outside,
		},
		{
			label = "a position past the play bound along x",
			call = function ()
				Npcs.create(vector.create(bound + 1, resting, 0), 0)
			end,
			refusal = outside,
		},
		{
			label = "a position past the play bound along z",
			call = function ()
				Npcs.create(vector.create(0, resting, -bound - 1), 0)
			end,
			refusal = outside,
		},
		{
			label = "an infinite height",
			call = function ()
				Npcs.create(vector.create(0, math.huge, 0), 0)
			end,
			refusal = outside,
		},
		{
			label = "a facing that is not a number",
			call = function ()
				Npcs.create(at, 0 / 0)
			end,
			refusal = "takes a finite facing",
		},
		{
			label = "a facing given as a string",
			call = function ()
				Npcs.create(at, "north" :: any)
			end,
			refusal = "takes a finite facing",
		},
		{
			label = "a command that is no table",
			call = function ()
				npc:command(1)
			end,
			refusal = "takes a command table",
		},
		{
			label = "a command whose forward is a string",
			call = function ()
				npc:command(badOrder(stage, "forward", "ahead"))
			end,
			refusal = "takes the move axes as numbers",
		},
		{
			label = "a command with no yaw",
			call = function ()
				npc:command(badOrder(stage, "yaw", nil))
			end,
			refusal = "takes the yaw, pitch and lean as numbers",
		},
		{
			label = "a command whose head pitch is a string",
			call = function ()
				npc:command(badOrder(stage, "headPitch", "up"))
			end,
			refusal = "takes the head offset's yaw and pitch as numbers",
		},
		{
			label = "a command whose jump is a number",
			call = function ()
				npc:command(badOrder(stage, "jump", 1))
			end,
			refusal = "takes the jump and crouch levels as booleans",
		},
		{
			label = "a command whose aim is a string",
			call = function ()
				npc:command(badOrder(stage, "aim", "yes"))
			end,
			refusal = "takes the sprint and aim levels as booleans",
		},
		{
			label = "a command with no fields",
			call = function ()
				npc:command(badOrder(stage, "fields", nil))
			end,
			refusal = "takes the game's declared fields as a table",
		},
		{
			label = "an awake flag given as a string",
			call = function ()
				npc:setAwake("yes")
			end,
			refusal = "takes a boolean",
		},
		{
			label = "a tick between two whole ticks",
			call = function ()
				Npcs.step(1.5)
			end,
			refusal = "takes the tick as a whole number of 0 or more",
		},
		{
			label = "a negative tick",
			call = function ()
				Npcs.step(-1)
			end,
			refusal = "takes the tick as a whole number of 0 or more",
		},
		{
			label = "a tick that is not a number",
			call = function ()
				Npcs.step(0 / 0)
			end,
			refusal = "takes the tick as a whole number of 0 or more",
		},
		{
			label = "a visit that is no function",
			call = function ()
				Npcs.each("visit")
			end,
			refusal = "takes a function",
		},
		{
			label = "a destroyed NPC's command",
			call = function ()
				doomed:command(stage.order())
			end,
			refusal = "npc:command ran on an NPC already destroyed",
		},
		{
			label = "a destroyed NPC woken",
			call = function ()
				doomed:setAwake(true)
			end,
			refusal = "npc:setAwake ran on an NPC already destroyed",
		},
		{
			label = "a second destroy",
			call = function ()
				doomed:destroy()
			end,
			refusal = "npc:destroy ran on an NPC already destroyed",
		},
	})
	if refused then
		return false, refused
	end

	-- No refused create held a slot, and no refused command changed the NPC's
	if stage.Slots.count("Npc") ~= 1 then
		return false, `The refused creates left {stage.Slots.count("Npc")} NPC slots taken, not the one made`
	end

	stage.Npcs.step(1)
	if npc:getState().tick ~= 1 or #stage.reports ~= 0 then
		return false, "The NPC whose commands were refused did not step cleanly on the command it was made with"
	end

	return true, nil
end
