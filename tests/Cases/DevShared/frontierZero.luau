--[[
    The dev game's shared table holds the approved example's values: its
    collision is engine casts over the place's test content and terrain, and
    with the fixture's collision in a copy the two hash alike
--]]

--!strict
local Harness = require("../../Fixtures/DevShared/Harness")

-- Every key either table holds, sorted
local function keys(a: { [string]: any }, b: { [string]: any }): { string }
	local names: { string } = {}

	for name: string in a do
		table.insert(names, name)
	end

	for name: string in b do
		if a[name] == nil then
			table.insert(names, name)
		end
	end

	table.sort(names)

	return names
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local Config: any = loaded.Config
	local shared: { [string]: any } = loaded.shared
	local example: { [string]: any } = loaded.Example.shared()

	-- The one part that differs by design: an include list where the fixture passes four functions
	local collision: { [string]: any } = shared.collision
	local include: { any }? = collision.include
	if not include or #include ~= 2 or include[1] ~= loaded.content or include[2] ~= loaded.terrain then
		return false, "collision.include is not Workspace.TestContent and Workspace.Terrain"
	end

	for name: string in collision do
		if name ~= "include" then
			return false, `collision gives {name} beside its include list`
		end
	end

	-- The hash names each instance of the include list, which the fixture's functions don't give
	if Config.hash(shared) == Config.hash(example) then
		return false, "The two hashed alike with different collision tables, so the hash read neither"
	end

	local copy: { [string]: any } = table.clone(shared)
	copy.collision = example.collision

	if Config.hash(copy) == Config.hash(example) then
		return true, nil
	end

	-- Each top-level key that hashes differently, for the report
	local differ: { string } = {}
	for _, name: string in keys(copy, example) do
		if Config.hash({ [name] = copy[name] }) ~= Config.hash({ [name] = example[name] }) then
			table.insert(differ, name)
		end
	end

	return false, `The dev table differs from the approved example's in {table.concat(differ, ", ")}`
end
