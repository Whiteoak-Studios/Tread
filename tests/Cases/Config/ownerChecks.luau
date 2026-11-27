--[[
    The server's check takes owner.checks and bots.agree left out, true or
    false, and refuses by its path either one that is neither true nor
    false, and any key beside checks in owner
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local CHECKS: string = "server.owner.checks"
local AGREE: string = "server.bots.agree"
local OTHER: string = "server.owner.every"
local BOT_RTT: number = 0.1 -- Seconds, the round trip the bots table needs beside agree

-- Each value taken for either key, the first left out
local TAKEN: { { value: boolean? } } = { {}, { value = true }, { value = false } }

-- Each value refused for either key
local REFUSED: { any } = { 1, 0, "true", {}, 0 / 0 }

-- The example's server settings with an owner table of checks and a bots table of agree, either nil for left out
local function settings(Example: any, checks: any, agree: any): any
	local server = Example.server()
	server.owner = { checks = checks }
	server.bots = { rtt = BOT_RTT, agree = agree }

	return server
end

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	-- Left out whole, as every game before them
	local plain: boolean, plainFailure: any = pcall(Config.server, Example.shared(), Example.server())
	if not plain then
		return false, `Config.server refused settings with no owner and no bots: {plainFailure}`
	end

	for _, checks: { value: boolean? } in TAKEN do
		for _, agree: { value: boolean? } in TAKEN do
			local server: any = settings(Example, checks.value, agree.value)
			local served: boolean, failure: any = pcall(Config.server, Example.shared(), server)
			if not served then
				return false,
					`Config.server refused owner.checks {checks.value} with bots.agree {agree.value}: {failure}`
			end
		end
	end

	for _, value: any in REFUSED do
		local problem: string? = Example.refusal(Config.server, CHECKS, Example.shared(), settings(Example, value, nil))
			or Example.refusal(Config.server, AGREE, Example.shared(), settings(Example, nil, value))
		if problem then
			return false, `With {value}: {problem}`
		end
	end

	local server: any = settings(Example, true, nil)
	server.owner.every = 1
	local problem: string? = Example.refusal(Config.server, OTHER, Example.shared(), server)
	if problem then
		return false, `With a key beside owner.checks: {problem}`
	end

	return true, nil
end
