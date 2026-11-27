--[[
    The ESP is the kit's tool named ESP on the One key: its start draws
    nothing, even with characters sent, a second start is refused, and its
    switch refuses anything but a boolean and takes a repeat as no change
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Rig = require("../../Fixtures/Esp/Rig")

local TICK: number = 50
local FRAMES: number = 3
local DRAWN: string = "Esp"

return function (): (boolean, string | nil)
	local rig: any = Rig.new()
	local esp: any = rig.esp

	if esp.name ~= "ESP" or esp.key ~= roblox.Enum.KeyCode.One or type(esp.start) ~= "function" then
		return false, `The ESP is {esp.name} on {esp.key}, not ESP on One with a start`
	end

	local switch: any = rig.startEsp()
	if type(switch) ~= "function" then
		return false, `The ESP's start gave a {type(switch)}, not its switch`
	end

	rig.slots({ { slot = 3, generation = 1, rig = "A" } })
	rig.relay({
		tick = TICK,
		reveals = { { slot = 3, generation = 1, kind = "Npc" } },
		records = { { slot = 3, generation = 1, position = vector.create(1, 0, 1), word = rig.word({}) } },
	})
	rig.frames(FRAMES)

	if rig.drawn() or rig.count() then
		return false, "The ESP drew before its switch was turned on"
	end

	local again: boolean, reason: any = pcall(esp.start, { client = rig.handle, shared = rig.shared })
	if again then
		return false, "A second start was taken"
	elseif not string.find(tostring(reason), "starts once", 1, true) then
		return false, `A second start was refused as "{reason}"`
	end

	local took: boolean, why: any = pcall(switch, 1)
	if took or not string.find(tostring(why), "takes a boolean", 1, true) then
		return false, `The switch took a number, or refused it as "{why}"`
	end

	-- A repeated on draws one folder, and a repeated off leaves none
	switch(true)
	switch(true)
	rig.frames(FRAMES)

	local folders: number = 0
	for _, child: any in rig.workspace:GetChildren() do
		if child.Name == DRAWN then
			folders += 1
		end
	end

	if folders ~= 1 or not rig.slot(3) then
		return false, `Two ons drew {folders} folders, not one with slot 3's box`
	end

	switch(false)
	switch(false)

	if rig.drawn() or rig.count() then
		return false, "Two offs left something drawn"
	end

	return true, nil
end
