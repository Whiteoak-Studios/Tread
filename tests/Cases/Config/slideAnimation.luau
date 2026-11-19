--[[
    The client's check requires animations.slide only where the shared
    table gives the crouch slide, naming client.animations.slide, and
    refuses one that is no Animation
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PATH: string = "client.animations.slide"

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	-- With no slide in the step block, none is needed
	local ran: boolean, failure: any = pcall(Config.client, Example.shared(), Example.client())
	if not ran then
		return false, `With no slide, a client with no slide animation was refused: {failure}`
	end

	local shared = Example.shared()
	shared.step.slide =
		{ start = 15, boost = 0, friction = 6, slope = 0.5, max = 27, stop = 6, steer = 60, cooldown = 2 }

	-- With one, the client's check needs it, and the server's never asks
	local problem: string? = Example.refusal(Config.client, PATH, shared, Example.client())
	if problem then
		return false, `With a slide, a client with no slide animation: {problem}`
	end

	local served: boolean, serverFailure: any = pcall(Config.server, shared, Example.server())
	if not served then
		return false, `The server's check refused the slide: {serverFailure}`
	end

	local wrong = Example.client()
	wrong.animations.slide = "rbxassetid://1" :: any
	local wrongProblem: string? = Example.refusal(Config.client, PATH, shared, wrong)
	if wrongProblem then
		return false, `With a slide, a slide animation that is a string: {wrongProblem}`
	end

	local given = Example.client()
	given.animations.slide = given.animations.crouchWalk
	local started: boolean, startFailure: any = pcall(Config.client, shared, given)
	if not started then
		return false, `With a slide, a client with a slide animation was refused: {startFailure}`
	end

	return true, nil
end
