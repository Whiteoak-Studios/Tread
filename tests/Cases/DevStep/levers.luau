--[[
    A flip sets only that session's live levers, never a boot lever or
    another session's, restore puts each back, also when a half's run
    throws, and the levers' line names every lever with its state now
--]]

--!strict
local Step = require("../../Fixtures/DevStep/Step")

-- Session 1's live levers, in the list's order
local LIVE: { string } = { "lazyDecode", "ownerChecks" }

-- Every lever as the line names it with the stand-in server's settings and both live levers on
local LINE: string = table.concat({
	"lazyDecode (session 1, live) on",
	"ownerChecks (session 1, live) on",
	"relayWorkers (session 0, boot) on",
	"relayClocks (session 1, boot) on",
	"outOfView (session 0, boot) on",
	"changes (session 0, boot) on",
}, ", ")

-- A lever that keeps each state it is set to, in a list of its own
local function kept(name: string, session: number, live: boolean, sets: { string }): any
	local on: boolean = true

	return {
		name = name,
		session = session,
		live = live,
		get = function (): boolean
			return on
		end,
		set = function (state: boolean)
			on = state
			table.insert(sets, `{name} {state}`)
		end,
	}
end

return function (): (boolean, string | nil)
	-- Each half throws, so every flip must be put back by the half's own restore
	local mounted: Step.Mounted = Step.load(function (): (boolean, string, { [string]: number }?)
		error("a stand-in throw", 0)
	end)

	local Levers: any = mounted.Levers
	local Commands: any = mounted.Commands
	local Characters: any = mounted.Characters

	-- 1) The list: session 1's live levers are lazy decode and owner checks with their seams, the rest boot levers
	local names: { string } = {}
	for _, lever: any in Levers.list do
		table.insert(names, lever.name)

		local live: boolean = table.find(LIVE, lever.name) ~= nil
		if lever.live ~= live or (lever.set ~= nil) ~= live then
			return false, `{lever.name} is listed live {lever.live} with a setter {lever.set ~= nil}`
		elseif live and lever.session ~= 1 then
			return false, `{lever.name} is listed for session {lever.session}, not session 1`
		end
	end

	if table.concat(names, ",") ~= "lazyDecode,ownerChecks,relayWorkers,relayClocks,outOfView,changes" then
		return false, `The levers are {table.concat(names, ",")}`
	elseif Levers.line() ~= LINE then
		return false, `The levers' line read:\n{Levers.line()}\nnot:\n{LINE}`
	end

	-- 2) A flip of session 1 off sets both live levers off and gives each one's state before; restore puts both on
	local states: { [string]: boolean } = Levers.flip(1, false)
	if Commands.lazyOn() ~= false then
		return false, "Session 1's flip off left lazy decode on"
	elseif Characters.checksOn() ~= false then
		return false, "Session 1's flip off left owner checks on"
	end

	local found: { string } = {}
	for name: string, state: boolean in states do
		table.insert(found, `{name} {state}`)
	end

	table.sort(found)
	if table.concat(found, ",") ~= "lazyDecode true,ownerChecks true" then
		return false, `Session 1's flip found {table.concat(found, ",")}`
	end

	Levers.restore(states)
	if Commands.lazyOn() ~= true then
		return false, "Restore left lazy decode off"
	elseif Characters.checksOn() ~= true then
		return false, "Restore left owner checks off"
	end

	-- 3) Over a list of its own, a flip of session 1 never sets a boot lever of session 1 or a live one of session 2
	local real: { any } = Levers.list
	local sets: { string } = {}
	Levers.list = {
		kept("ownLive", 1, true, sets),
		kept("ownBoot", 1, false, sets),
		kept("otherLive", 2, true, sets),
	}

	local own: { [string]: boolean } = Levers.flip(1, false)
	Levers.restore(own)
	Levers.list = real

	if table.concat(sets, ",") ~= "ownLive false,ownLive true" then
		return false, `Session 1's flip and restore set {table.concat(sets, ",")}`
	end

	-- 4) Every half of the run throws: both live levers are still on afterward, and were off in each before half
	local passed: boolean = mounted.BenchStep()
	if passed then
		return false, "A run whose every half threw passed"
	elseif Commands.lazyOn() ~= true then
		return false, "Lazy decode was left off after the halves threw"
	elseif Characters.checksOn() ~= true then
		return false, "Owner checks were left off after the halves threw"
	end

	for _, asked: Step.Asked in mounted.asked do
		local after: boolean = asked.half == "after"
		if asked.lazy ~= after or asked.checks ~= after then
			local ran: string = `lazy decode {asked.lazy} and owner checks {asked.checks}`
			return false, `The {asked.scenario}/{asked.half} half ran with {ran}`
		end
	end

	-- 5) And with both off before the run, the after halves' throws put both back off too
	Commands.useLazy(false)
	Characters.useChecks(false)
	mounted.BenchStep()
	if Commands.lazyOn() ~= false then
		return false, "Lazy decode was left on after the after halves threw"
	elseif Characters.checksOn() ~= false then
		return false, "Owner checks were left on after the after halves threw"
	end

	return true, nil
end
