--[[
    Runs one live scenario by name on the dev place's server and hands back
    whether it passed with a report, printing both, and ending the test with
    both when the test was launched to run that scenario
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Scenarios = ServerScriptService.Server.Scenarios

local Runner = {}

--[[
    Prints the verdict for get_console_output, and in a test whose args
    name this scenario, as { scenario = name }, ends it with both, which
    the launcher's ExecuteMultiplayerTestAsync call returns
--]]

local function finish(name: string, success: boolean, report: string): (boolean, string)
	local verdict: string = success and "PASS" or "FAIL"
	print(`Runner {verdict} {report}`)

	-- A server outside Studio may have no StudioTestService, and the Runner still reports there
	local found: boolean, studioTestService: any = pcall(game.GetService, game, "StudioTestService")
	if not found then
		return success, report
	end

	-- A Play session, or a test Mike started, has no such args and keeps running
	local hasArgs: boolean, args: any = pcall(studioTestService.GetTestArgs, studioTestService)
	if hasArgs and type(args) == "table" and args.scenario == name then
		local ended: boolean, reason: any = pcall(studioTestService.EndTest, studioTestService, {
			success = success,
			report = report,
		})

		if not ended then
			warn(`Runner could not end the test with {name}'s verdict: {reason}`)
		end
	end

	return success, report
end

--[[
    Runs the scenario of that name and returns whether it passed and a
    report naming it. A missing scenario, one whose require fails or that
    is no function, one that throws and one that returns anything but true
    each come back false with the reason, so a caller never sees a throw
--]]

function Runner.run(name: string): (boolean, string)
	if type(name) ~= "string" then
		return finish(tostring(name), false, `{name}: a scenario is named by a string, not a {typeof(name)}`)
	end

	local module: Instance? = Scenarios:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return finish(name, false, `{name}: no scenario has that name`)
	end

	local loaded: boolean, scenario: any = pcall(require, module)
	if not loaded then
		return finish(name, false, `{name}: its require failed: {scenario}`)
	end

	if type(scenario) ~= "function" then
		return finish(name, false, `{name}: it returned a {type(scenario)}, not a function`)
	end

	local ran: boolean, passed: any, reason: any = pcall(scenario)
	if not ran then
		return finish(name, false, `{name}: it threw: {passed}`)
	end

	if passed ~= true then
		if reason == nil then
			return finish(name, false, `{name}: it returned {passed} with no reason`)
		end

		return finish(name, false, `{name}: {reason}`)
	end

	return finish(name, true, `{name}: passed`)
end

return Runner
