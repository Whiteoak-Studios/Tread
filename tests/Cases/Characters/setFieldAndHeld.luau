--[[
    character:setField sets a server-set field and character:setHeld the
    held-item fields, each read by the rules function from the next step,
    the held item a copy of the game's table and nil emptying the hands;
    an unknown field, a value outside its declaration and a non-table held
    item are refused
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local ITEM: number = 7
local CHANGED: number = 9 -- What the game's own table is changed to after the call

return function (): (boolean, string | nil)
	local seen: { revived: boolean?, item: number? } = {}

	local rig: Rig.Rig = Rig.new(function (shared: any, _: any)
		shared.rules = function (step: any, _: any): number
			seen.revived = step.fields.beingRevived
			seen.item = step.held.item

			return math.huge
		end
	end)

	local server: any = rig:start()
	local character: any = server:create(rig.mock:addBot("Bot"), rig:at(0, 0))
	rig:tick(1)

	if seen.revived ~= false or seen.item ~= nil then
		return false, `A new character's rules read beingRevived {seen.revived} and item {seen.item}`
	end

	local held: { [string]: any } = { item = ITEM }
	character:setField("beingRevived", true)
	character:setHeld(held)
	held.item = CHANGED
	rig:tick(1)

	if seen.revived ~= true or seen.item ~= ITEM then
		return false, `After the calls the rules read beingRevived {seen.revived} and item {seen.item}`
	end

	character:setHeld(nil)
	rig:tick(1)

	if seen.item ~= nil then
		return false, `After setHeld(nil) the rules read item {seen.item}`
	end

	local refusals: { { name: string, run: () -> () } } = {
		{
			name = "an unknown field",
			run = function ()
				character:setField("health", 1)
			end,
		},
		{
			name = "a number for a boolean field",
			run = function ()
				character:setField("beingRevived", 1)
			end,
		},
		{
			name = "a held item outside its declaration",
			run = function ()
				character:setHeld({ item = -1 })
			end,
		},
		{
			name = "a held item that is no table",
			run = function ()
				character:setHeld(ITEM)
			end,
		},
	}

	for _, refusal in refusals do
		if pcall(refusal.run) then
			return false, `The character took {refusal.name}`
		end
	end

	return true, nil
end
