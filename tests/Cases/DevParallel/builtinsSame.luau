--[[
    Two calls of the B2 battery in one VM, writing one part, start from the
    same state: every section's hash, the stream and the timing loop's end
    value agree, and differences finds nothing between them
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")

return function (): (boolean, string | nil)
	local loaded: any = Harness.load()
	local Builtins: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Parallel.Builtins)
	local part: any = roblox.Instance.new("Part")

	local first: any = Builtins.run(part)
	local second: any = Builtins.run(part)

	-- 1) Section by section, then the whole stream and the loop
	if #second.sections ~= #first.sections then
		return false, `The second call gave {#second.sections} sections, the first {#first.sections}`
	end

	for index: number, entry: any in first.sections do
		local again: any = second.sections[index]
		if again.name ~= entry.name or again.hash ~= entry.hash then
			local was: string = `{entry.name} with hash {entry.hash}`
			return false, `Section {index} was {was} in the first call and {again.name} with {again.hash} in the second`
		end
	end

	if second.values ~= first.values or second.hash ~= first.hash then
		local was: string = `{first.values} values hashing {first.hash}`
		return false, `The first call wrote {was} and the second {second.values} hashing {second.hash}`
	elseif second.loopValue ~= first.loopValue then
		return false, `The timing loop ended at {first.loopValue} and then at {second.loopValue}`
	end

	-- 2) The comparison step-probe makes finds no difference
	local lines: { string } = Builtins.differences(first, second)
	if #lines > 0 then
		return false, `Two calls differed: {table.concat(lines, "; ")}`
	end

	return true, nil
end
