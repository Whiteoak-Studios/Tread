--[[
    The server's check takes the example's anti-ESP table, which holds no
    near rate, and refuses antiEsp.nearRate, a key Tread doesn't read, with
    its whole message, whatever value it holds
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PATH: string = "antiEsp.nearRate"
local VALUES: { any } = { 30, 60, "30" }

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	local plain: boolean, failure: any = pcall(Config.server, Example.shared(), Example.server())
	if not plain then
		return false, `The example's tables with no near rate were refused: {failure}`
	end

	for _, value: any in VALUES do
		local server: any = Example.server()
		Example.set(server, PATH, value)

		local shown: string = type(value) == "string" and `"{value}"` or tostring(value)
		local message: string = `server.{PATH} expected no value, since Tread reads no such key, and got {shown}`
		local taken: boolean, why: any = pcall(Config.server, Example.shared(), server)
		if taken then
			return false, `Config.server took {PATH} at {shown}`
		elseif tostring(why) ~= message then
			return false, `Config.server refused {PATH} at {shown} as "{why}", not "{message}"`
		end
	end

	return true, nil
end
