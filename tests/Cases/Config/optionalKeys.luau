--[[
    The other shapes a game may give pass: engine casts with only an include
    list, its own functions with one beside them, no water or prestream, a
    server that creates bots, a silent footstep kind and an extra Animation
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local BOT_RTT: number = 0.1 -- Seconds, a bot harness's configured round trip

type Variant = { label: string, table: "shared" | "server" | "client", path: string, value: any }

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	local folder: any = roblox.Instance.new("Folder")
	local reload: any = roblox.Instance.new("Animation")

	local variants: { Variant } = {
		{
			label = "engine casts with an include list",
			table = "shared",
			path = "collision",
			value = { include = { folder } },
		},
		{
			label = "its own functions with an include list",
			table = "shared",
			path = "collision.include",
			value = { folder },
		},
		{ label = "no water", table = "shared", path = "water", value = nil },
		{ label = "no prestream", table = "server", path = "prestream", value = nil },
		{ label = "a server that creates bots", table = "server", path = "bots", value = { rtt = BOT_RTT } },
		{
			label = "silent jumps and landings",
			table = "server",
			path = "footsteps.range",
			value = { walk = 40, sprint = 60 },
		},
		{ label = "every footstep kind silent", table = "server", path = "footsteps.range", value = {} },
		{ label = "an Animation beside the states'", table = "client", path = "animations.reload", value = reload },
	}

	for _, variant: Variant in variants do
		local tables: { [string]: any } =
			{ shared = Example.shared(), server = Example.server(), client = Example.client() }
		Example.set(tables[variant.table], variant.path, variant.value)

		local served: boolean, serverFailure: any = pcall(Config.server, tables.shared, tables.server)
		if not served then
			return false, `Config.server refused {variant.label}: {serverFailure}`
		end

		local started: boolean, clientFailure: any = pcall(Config.client, tables.shared, tables.client)
		if not started then
			return false, `Config.client refused {variant.label}: {clientFailure}`
		end
	end

	return true, nil
end
