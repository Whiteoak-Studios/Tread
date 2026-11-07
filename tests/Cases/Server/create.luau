--[[
    server:create builds a bot's character that getAll and near find and
    the tick steps onto the floor, and refuses what is no player or bot, a
    second character for one bot and a place outside the play bound
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 10 -- Long enough to land from the rig's lift
local OUTSIDE: number = 9000 -- Studs, past the 8,192-stud play bound
local RANGE: number = 5 -- Studs around the character a near query reaches

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local bot: any = rig.mock:addBot("Bot")

	local character: any = server:create(bot, rig:at(0, 0))
	if character.player ~= bot then
		return false, "The character names someone other than its bot"
	end

	local all: { any } = server:getAll()
	if #all ~= 1 or all[1] ~= character then
		return false, `getAll gave {#all} targets, not the one character`
	end

	rig:tick(TICKS)

	local state: any = character:getState()
	if not state.grounded or math.abs(state.root.Y - rig.floor) > 0.1 then
		return false, `After {TICKS} ticks the character stands at {state.root}, grounded {state.grounded}`
	end

	local names: { string } = server:near(roblox.Vector3.new(0, rig.floor, 0), RANGE)
	if #names ~= 1 or names[1] ~= bot.Name then
		return false, `near found {#names} names around the character, not its bot's`
	end

	local refusals: { { name: string, run: () -> () } } = {
		{
			name = "a number for the player",
			run = function ()
				server:create(5, rig:at(4, 0))
			end,
		},
		{
			name = "a second character for the same bot",
			run = function ()
				server:create(bot, rig:at(4, 0))
			end,
		},
		{
			name = "a place outside the play bound",
			run = function ()
				server:create(rig.mock:addBot("Far"), roblox.CFrame.new(OUTSIDE, rig.floor, 0))
			end,
		},
		{
			name = "a Vector3 for where to build",
			run = function ()
				server:create(rig.mock:addBot("Vector"), roblox.Vector3.zero)
			end,
		},
	}

	for _, refusal in refusals do
		if pcall(refusal.run) then
			return false, `server:create took {refusal.name}`
		end
	end

	if #server:getAll() ~= 1 then
		return false, `The refused creates left {#server:getAll()} targets, not the one character`
	end

	return true, nil
end
