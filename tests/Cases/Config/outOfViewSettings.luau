--[[
    The server's check takes tiers.outOfView left out or whole, and refuses
    by its path a table that isn't one, a key missing or not Tread's, a
    rate not above 0, a cone not above 0 or past 180 and a negative radius
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PATH: string = "tiers.outOfView"

local NOT_FINITE: { number } = { 0 / 0, math.huge, -math.huge }

-- Each key's values refused, beside NaN and both infinities, and taken
local KEYS: { { key: string, refused: { number }, taken: { number } } } = {
	{ key = "rate", refused = { 0, -1 }, taken = { 1 / 8, 5, 20 } },
	{ key = "cone", refused = { 0, -60, 180.001, 360 }, taken = { 1 / 8, 60, 90, 120, 180 } },
	{ key = "radius", refused = { -1 / 512, -15 }, taken = { 0, 15, 1000 } },
}

-- A fresh out-of-view table, the dev game's values
local function lever(): { [string]: any }
	return { rate = 5, cone = 70, radius = 40 }
end

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	-- Left out, and given whole
	local server = Example.server()
	Example.set(server, PATH, nil)
	local served: boolean, failure: any = pcall(Config.server, Example.shared(), server)
	if not served then
		return false, `Config.server refused settings with no {PATH}: {failure}`
	end

	server = Example.server()
	Example.set(server, PATH, lever())
	served, failure = pcall(Config.server, Example.shared(), server)
	if not served then
		return false, `Config.server refused {PATH} at its dev values: {failure}`
	end

	-- Not a table
	server = Example.server()
	Example.set(server, PATH, 5)
	local problem: string? = Example.refusal(Config.server, `server.{PATH}`, Example.shared(), server)
	if problem then
		return false, `With {PATH} a number: {problem}`
	end

	-- A key Tread doesn't read
	server = Example.server()
	Example.set(server, PATH, lever())
	Example.set(server, `{PATH}.width`, 30)
	problem = Example.refusal(Config.server, `server.{PATH}.width`, Example.shared(), server)
	if problem then
		return false, `With {PATH}.width given: {problem}`
	end

	for _, entry in KEYS do
		local path: string = `{PATH}.{entry.key}`

		server = Example.server()
		Example.set(server, PATH, lever())
		Example.set(server, path, nil)
		problem = Example.refusal(Config.server, `server.{path}`, Example.shared(), server)
		if problem then
			return false, `With {path} missing: {problem}`
		end

		local refused: { number } = table.clone(entry.refused)
		table.move(NOT_FINITE, 1, #NOT_FINITE, #refused + 1, refused)

		for _, value: number in refused do
			server = Example.server()
			Example.set(server, PATH, lever())
			Example.set(server, path, value)
			problem = Example.refusal(Config.server, `server.{path}`, Example.shared(), server)
			if problem then
				return false, `With {path} at {value}: {problem}`
			end
		end

		for _, value: number in entry.taken do
			server = Example.server()
			Example.set(server, PATH, lever())
			Example.set(server, path, value)
			served, failure = pcall(Config.server, Example.shared(), server)
			if not served then
				return false, `Config.server refused {path} at {value}: {failure}`
			end
		end
	end

	return true, nil
end
