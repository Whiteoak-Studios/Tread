--[[
    The codec's fixture game: declarations of every kind of field in each of
    the five lists, each list again filling exactly its bound, the limits
    lean and the head offset step to, and values at every field's edges
--]]

--!strict
local WIDEST: number = 2 ^ 32 - 1 -- A 32-bit uint's top
local HALF: number = 2 ^ 31 -- A 32-bit int's values either side of 0

-- One of every kind of field, with each list's indices counted depth first from 1
local FIELDS: { [string]: { { [string]: any } } } = {
	command = {
		{ name = "slot", type = "uint", bits = 3, kind = "held" }, -- 1
		{ name = "reload", type = "bool", kind = "carried" }, -- 2
		{ name = "uses", type = "uint", bits = 4, max = 9, kind = "carried" }, -- 3
		{
			name = "shots", -- 4, a list of groups: sequence 5, fraction 6, yaw 7, class 8
			type = "group",
			count = 2,
			kind = "dropped",
			fields = {
				{ name = "sequence", type = "uint", bits = 8 },
				{ name = "fraction", type = "int", bits = 8, min = -100, max = 100 },
				{ name = "yaw", type = "uint", bits = 16 },
				{ name = "class", type = "uint", bits = 2, max = 2 },
			},
		},
		{ name = "seed", type = "uint", bits = 32, kind = "held" }, -- 9
		{ name = "offset", type = "int", bits = 32, kind = "held" }, -- 10
		{ name = "fixed", type = "uint", bits = 5, min = 7, max = 7, kind = "held" }, -- 11, packed in 0 bits
	},

	rules = {
		{ name = "sinceJump", type = "uint", bits = 8, start = 0 },
		{ name = "sprintLock", type = "int", bits = 6, min = -20, max = 20, start = -20 },
		{ name = "flags", type = "bool", count = 3 },
	},

	server = {
		{ name = "beingRevived", type = "bool", start = false },
		{ name = "reviver", type = "uint", bits = 12, start = 0 },
	},

	slot = {
		{ name = "head", type = "uint", bits = 10, optional = true },
		{ name = "chest", type = "uint", bits = 10 },
		{ name = "colors", type = "uint", bits = 8, count = 4 },
		{
			name = "badge",
			type = "group",
			optional = true,
			fields = {
				{ name = "id", type = "uint", bits = 16 },
				{ name = "shiny", type = "bool" },
			},
		},
	},

	held = {
		{ name = "item", type = "uint", bits = 16 },
		{ name = "skin", type = "uint", bits = 16, optional = true },
	},
}

-- Each list's bytes at its largest packing, from FIELDS
local BYTES: { [string]: number } = { command = 18, rules = 3, server = 2, slot = 10, held = 5 }

-- That many 32-bit uints, each filling 4 B, for a list that fills its bound exactly
local function words(count: number, kind: string?): { { [string]: any } }
	local made: { { [string]: any } } = {}

	for index: number = 1, count do
		table.insert(made, { name = `word{index}`, type = "uint", bits = 32, kind = kind })
	end

	return made
end

-- Values at each field's lowest, its lists empty and its optionals absent
local LOW: { [string]: { [string]: any } } = {
	command = { slot = 0, reload = false, uses = 0, shots = {}, seed = 0, offset = -HALF, fixed = 7 },
	rules = { sinceJump = 0, sprintLock = -20, flags = {} },
	server = { beingRevived = false, reviver = 0 },
	slot = { chest = 0, colors = {} },
	held = { item = 0 },
}

-- Values at each field's highest, its lists full and its optionals present
local HIGH: { [string]: { [string]: any } } = {
	command = {
		slot = 7,
		reload = true,
		uses = 9,
		shots = {
			{ sequence = 255, fraction = 100, yaw = 65535, class = 2 },
			{ sequence = 0, fraction = -100, yaw = 0, class = 0 },
		},
		seed = WIDEST,
		offset = HALF - 1,
		fixed = 7,
	},
	rules = { sinceJump = 255, sprintLock = 20, flags = { true, false, true } },
	server = { beingRevived = true, reviver = 4095 },
	slot = { head = 1023, chest = 1023, colors = { 255, 0, 128, 255 }, badge = { id = 65535, shiny = true } },
	held = { item = 65535, skin = 65535 },
}

return {
	fields = FIELDS,
	bytes = BYTES,
	low = LOW,
	high = HIGH,

	-- Each list at exactly its bound: 64 B a command, 32 B rule state, 16 B server-set, 64 B look, 16 B held item
	largest = {
		command = words(16, "held"),
		rules = words(8),
		server = words(4),
		slot = words(16),
		held = words(4),
	},

	-- Frontier Zero's lean limit and head cone, in degrees
	limits = { lean = 20, headCone = 75 },
}
