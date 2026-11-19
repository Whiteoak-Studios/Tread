--[[
    client:showBody hands each of its four parts to the rig pool both ways,
    and refuses any other part and a shown flag that is no boolean, naming
    them, before the pool hears of it
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle

	-- The pool's stand-in writes down each show it is handed
	local shows: { { part: string, shown: boolean } } = {}
	handle._rigs.show = function (_: any, part: string, shown: boolean)
		table.insert(shows, { part = part, shown = shown })
	end

	local parts: { string } = { "arms", "chest", "copy", "rig" }
	for _, part: string in parts do
		for _, shown: boolean in { false, true } do
			local took: boolean, problem: any = pcall(handle.showBody, handle, part, shown)
			local last: { part: string, shown: boolean }? = shows[#shows]
			if not took then
				return false, `showBody("{part}", {shown}) threw: {problem}`
			elseif last == nil or last.part ~= part or last.shown ~= shown then
				return false, `showBody("{part}", {shown}) didn't reach the rig pool as it was given`
			end
		end
	end

	local count: number = #shows
	local refused: { any } = { "legs", "Rig", 4, nil :: any }
	for index: number = 1, 4 do
		local part: any = refused[index]
		local took: boolean, problem: any = pcall(handle.showBody, handle, part, true)
		if took then
			return false, `showBody took {part} as a part`
		elseif not string.find(tostring(problem), `client:showBody takes`, 1, true) then
			return false, `showBody refused {part} without naming itself: {problem}`
		elseif not string.find(tostring(problem), `not {part}`, 1, true) then
			return false, `showBody refused {part} without naming it: {problem}`
		end
	end

	local flagged: boolean, flagProblem: any = pcall(handle.showBody, handle, "arms", 1)
	if flagged then
		return false, "showBody took a number as shown"
	elseif not string.find(tostring(flagProblem), "boolean", 1, true) then
		return false, `showBody refused a number as shown without naming the boolean it takes: {flagProblem}`
	elseif #shows ~= count then
		return false, `{#shows - count} refused calls reached the rig pool`
	end

	return true, nil
end
