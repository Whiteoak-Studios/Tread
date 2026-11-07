--[[
    While on, the walk, sprint and crouch speeds of the step settings the
    client's prediction steps with are multiplied by the kit's factor, and
    off puts back exactly what it found, every other speed left alone
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local mounted: Kit.Mounted = Kit.mount(rig)
	local factor: number = mounted.require(mounted.config).exploits.speedFactor
	local settings: any = rig.handle._world.settings

	if settings ~= rig.shared.step then
		return false, "The client's world steps with settings other than the shared table's step block"
	end

	local walk: number, sprint: number, crouch: number, swim: number =
		settings.walk, settings.sprint, settings.crouch, settings.swim

	local switch: (on: boolean) -> () =
		mounted.require(mounted.exploits.Speed).start({ client = rig.handle, shared = rig.shared })

	switch(true)
	if settings.walk ~= walk * factor or settings.sprint ~= sprint * factor or settings.crouch ~= crouch * factor then
		return false, `On, the speeds are {settings.walk}, {settings.sprint} and {settings.crouch}, not times {factor}`
	elseif settings.swim ~= swim then
		return false, "The speed changed the swim speed too"
	end

	switch(false)
	if settings.walk ~= walk or settings.sprint ~= sprint or settings.crouch ~= crouch then
		return false, `Off, the speeds are {settings.walk}, {settings.sprint} and {settings.crouch}, not as found`
	end

	-- Off again changes nothing, and on again multiplies what it finds then
	switch(false)
	switch(true)
	switch(false)
	if settings.walk ~= walk or settings.sprint ~= sprint or settings.crouch ~= crouch then
		return false, "A second round of the switch didn't end with the speeds as found"
	end

	return true, nil
end
