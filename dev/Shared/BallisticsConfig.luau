--[[
    The fixture ballistics' numbers, which both realms read: the weapon a
    shot fires by its held hotbar slot, and what a shot's render fraction
    counts its tick in
--]]

--!strict
return {
	-- Frontier Zero's AKM and Bow from its firing table, by the hotbar slot the shot's command holds
	weapons = {
		{ speed = 3003, range = 750 }, -- Slot 1, the AKM: studs a second its bullet flies, and studs before it falls short
		{ speed = 521, range = 450 }, -- Slot 2, the Bow, whose flight to its range takes 0.86 s
	},

	fractionSteps = 256, -- What a shot's 8-bit render fraction counts its tick in
}
