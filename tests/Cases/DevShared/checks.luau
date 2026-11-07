--[[
    The dev game's shared table passes both entry points' checks beside the
    approved example's server and client settings, and two loads of it, as
    the server and a client each make, hash alike
--]]

--!strict
local Harness = require("../../Fixtures/DevShared/Harness")

return function (): (boolean, string | nil)
	local first: Harness.Loaded = Harness.load()
	local Config: any = first.Config
	local Example: any = first.Example

	local served: boolean, serverFailure: any = pcall(Config.server, first.shared, Example.server())
	if not served then
		return false, `Config.server refused the dev table: {serverFailure}`
	end

	local started: boolean, clientFailure: any = pcall(Config.client, first.shared, Example.client())
	if not started then
		return false, `Config.client refused the dev table: {clientFailure}`
	end

	local second: Harness.Loaded = Harness.load()
	if second.shared == first.shared then
		return false, "The second load handed back the first's table, so it proves nothing"
	end

	local hash: number = Config.hash(first.shared)
	local again: number = second.Config.hash(second.shared)
	if hash ~= again then
		return false, `Two loads hashed {hash} and {again}`
	end

	return true, nil
end
