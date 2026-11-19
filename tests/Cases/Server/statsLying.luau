--[[
    server:stats gives antiEspLyingTests and antiEspLyingWaiting as
    AntiEsp.lying gives them at the read: the sleepers' pairs waiting after
    a slice with no time, then their tests once the ticks' slices have the
    time, and none on a read straight after
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 4
local HEAD: number = 12 -- An item index the example's head slot holds
local SLEEPERS: { number } = { 6, -6 } -- Studs along X each sleeper lies from the viewer, in its sight

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local AntiEsp: any = rig:require(rig.tread.Server.AntiEsp)

	server:create(rig.mock:addBot("Viewer"), rig:at(0, 0))

	local sleepers: { any } = {}
	for _, x: number in SLEEPERS do
		table.insert(sleepers, server:createSleeper(rig:at(x, 0), { head = HEAD }))
	end

	rig:tick(TICKS)
	server:stats()

	-- Every sleeper pair due again, and a slice with no time, as one past a starved budget leaves them
	for _, sleeper: any in sleepers do
		AntiEsp.moved(sleeper._slot)
	end

	AntiEsp.run(0, os.clock())

	local starved: any = server:stats()
	local tests: number, waiting: number = AntiEsp.lying()
	if starved.antiEspLyingTests ~= 0 or starved.antiEspLyingWaiting ~= #SLEEPERS then
		local counts: string = `{starved.antiEspLyingTests} lying tests and {starved.antiEspLyingWaiting} waiting`
		return false, `The read after a slice with no time gave {counts}, not 0 and {#SLEEPERS}`
	elseif tests ~= 0 or waiting ~= starved.antiEspLyingWaiting then
		return false, `AntiEsp.lying gave {tests} tests and {waiting} waiting straight after the read`
	end

	rig:tick(TICKS)

	local tested: any = server:stats()
	if tested.antiEspLyingTests ~= #SLEEPERS or tested.antiEspLyingWaiting ~= 0 then
		local counts: string = `{tested.antiEspLyingTests} lying tests and {tested.antiEspLyingWaiting} waiting`
		return false, `Once the slices had time the read gave {counts}, not {#SLEEPERS} and 0`
	elseif tested.antiEspTests < tested.antiEspLyingTests then
		return false, `The read gave {tested.antiEspTests} tests in all, fewer than its lying ones`
	end

	local again: any = server:stats()
	if again.antiEspLyingTests ~= 0 or again.antiEspLyingWaiting ~= 0 then
		return false, "A read straight after another gave lying tests or waiting pairs above 0"
	end

	return true, nil
end
