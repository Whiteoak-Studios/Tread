--[[
    A dress hook that throws gives its rig back: over many checkouts whose
    dress throws, for the world rig and for the first-person copy, the pool
    builds no more rigs, and one whose undress throws too is dropped
--]]

--!strict
local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local SLOT: number = 4
local OWN: number = 9
local TRIES: number = 10 -- Checkouts in a row, as a frame each of the owner's spawn retried
local BROKEN_TRIES: number = 3 -- Fewer where both hooks throw, since each warns its stack
local THROWN: string = "This dress hook throws on purpose, to show its rig goes back"

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	-- 1) The world rig's dress throws on every checkout, and checkout still raises it
	local calls: { any } = {}
	local settings: any = Rig.settings(calls)
	settings.dress = function (_: Model, _: any, _: boolean)
		error(THROWN)
	end

	local rigs: any = Rigs.new(settings, Rig.drawDistance, Rig.collision())
	for try: number = 1, TRIES do
		local checked: boolean, problem: any = pcall(rigs.checkout, rigs, SLOT, {})
		if checked then
			return false, "A checkout whose dress hook threw handed back a rig"
		elseif not string.find(tostring(problem), THROWN, 1, true) then
			return false, `A checkout whose dress hook threw raised "{problem}", not the hook's own error`
		elseif #rigs._rigs ~= 1 or #rigs._pool ~= 1 then
			return false,
				`After {try} checkouts whose dress threw the pool held {#rigs._rigs} rigs, {#rigs._pool} pooled`
		end
	end

	local undressed: number = 0
	for _, call: any in calls do
		if call.hook == "undress" then
			undressed += 1
		end
	end

	if undressed ~= TRIES then
		return false, `{TRIES} rigs whose dress threw were undressed {undressed} times before going back`
	end

	-- The slot was never taken, so a checkout with a dress that works takes the same rig
	local first: any = rigs._rigs[1].rig
	settings.dress = function (_: Model, _: any, _: boolean) end
	if rigs:checkout(SLOT, {}) ~= first then
		return false, "A checkout after the throwing ones built a new rig instead of taking the one given back"
	end

	rigs:destroy()

	-- 2) The copy's dress throws on every own checkout, which still hands back the world rig
	local copyCalls: { any } = {}
	local copySettings: any = Rig.settings(copyCalls)
	local dress: (Model, any, boolean) -> () = copySettings.dress
	copySettings.dress = function (rig: Model, outfit: any, copy: boolean)
		dress(rig, outfit, copy)
		if copy then
			error(THROWN)
		end
	end

	local own: any = Rigs.new(copySettings, Rig.drawDistance, Rig.collision())
	for try: number = 1, TRIES do
		local checked: boolean, problem: any = pcall(own.checkout, own, OWN, {}, true)
		if not checked then
			return false, `An own checkout threw when its copy's dress did: {problem}`
		end

		own:release(OWN)
		if #own._rigs ~= 2 or #own._pool ~= 2 then
			return false, `After {try} own checkouts whose copy's dress threw the pool held {#own._rigs} rigs`
		end
	end

	own:destroy()

	-- 3) The undress throws too, so each rig is destroyed and dropped from the pool's rigs, which destroy then skips
	local brokenSettings: any = Rig.settings({})
	brokenSettings.dress = function (_: Model, _: any, _: boolean)
		error(THROWN)
	end
	brokenSettings.undress = function (_: Model)
		error("This undress hook throws on purpose, to show its rig is destroyed")
	end

	local broken: any = Rigs.new(brokenSettings, Rig.drawDistance, Rig.collision())
	for try: number = 1, BROKEN_TRIES do
		local checked: boolean, problem: any = pcall(broken.checkout, broken, SLOT, {})
		if checked or not string.find(tostring(problem), THROWN, 1, true) then
			return false, `A checkout whose dress and undress threw raised "{problem}", not the dress hook's error`
		elseif #broken._rigs ~= 0 or #broken._pool ~= 0 then
			return false, `After {try} rigs whose undress threw the pool kept {#broken._rigs} rigs`
		end
	end

	local ended: boolean, failure: any = pcall(broken.destroy, broken)
	if not ended then
		return false, `Destroying the pool threw after its rigs were dropped: {failure}`
	end

	return true, nil
end
