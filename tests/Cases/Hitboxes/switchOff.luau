--[[
    A slot's rig put away takes its drawing with it, switching off removes
    the folder and every drawing and draws nothing on the frames after, and
    switching on again draws each character still drawn, those spawned while
    the hitboxes were off included
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local DRAWN: string = "Hitboxes" -- The Workspace folder the hitboxes draw in
local OWNER: string = "-1" -- The owner's body's drawing
local OWN: number = 9
local FIRST: number = 30 -- Freed while the hitboxes are on
local KEPT: number = 31 -- Drawn throughout
local LATER: number = 32 -- Spawned while the hitboxes are off
local GENERATION: number = 1
local TICK: number = 50
local FRAMES: number = 6
local AT: vector = vector.create(5, 0, -5)

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local mounted: Kit.Mounted = Kit.mount(rig)
	local workspace: any = rig.globals.game:GetService("Workspace")

	local switch: (on: boolean) -> () =
		mounted.require(mounted.exploits.Hitboxes).start({ client = rig.handle, shared = rig.shared })

	-- Records for each slot at every tick from one to the next, each frame between, then the frames to reach them
	local function heard(slots: { number }, from: number, to: number)
		for tick: number = from, to do
			local reveals: { any } = {}
			local records: { any } = {}

			for _, slot: number in slots do
				if tick == from then
					table.insert(reveals, { slot = slot, generation = GENERATION, kind = "Npc" })
				end

				table.insert(records, { slot = slot, generation = GENERATION, position = AT, word = rig.word({}) })
			end

			rig.relay({ tick = tick, reveals = reveals, records = records })
			rig.frames(1)
		end

		rig.frames(FRAMES)
	end

	local function drawing(key: string): any
		local drawn: any = workspace:FindFirstChild(DRAWN)

		return drawn and drawn:FindFirstChild(key)
	end

	rig.handshake()
	rig.own(OWN, GENERATION)
	rig.owner(rig.body(AT, 0, TICK))
	rig.slots({
		{ slot = FIRST, generation = GENERATION, rig = "A" },
		{ slot = KEPT, generation = GENERATION, rig = "A" },
		{ slot = LATER, generation = GENERATION, rig = "A" },
	})

	switch(true)
	heard({ FIRST, KEPT }, TICK, TICK + FRAMES)

	if not drawing(OWNER) or not drawing(`{FIRST}`) or not drawing(`{KEPT}`) then
		return false, "Switched on, the hitboxes didn't draw the owner and both NPCs"
	end

	-- 1) The slot table frees one: its rig goes back to the pool, and its drawing with it
	local first: any = drawing(`{FIRST}`)
	rig.slots({ { slot = FIRST, generation = GENERATION } })
	rig.frames(1)

	if drawing(`{FIRST}`) or first.Parent ~= nil then
		return false, "A freed slot's drawing stayed in the game"
	elseif not drawing(`{KEPT}`) then
		return false, "Freeing one slot took another's drawing"
	end

	-- 2) Off: the folder and every drawing go, and no frame after draws one again
	local kept: any = drawing(`{KEPT}`)
	switch(false)

	if workspace:FindFirstChild(DRAWN) or kept.Parent ~= nil then
		return false, "Switching off left the hitboxes' folder or a drawing in the game"
	end

	heard({ LATER }, TICK + FRAMES + 1, TICK + 2 * FRAMES)

	if workspace:FindFirstChild(DRAWN) then
		return false, "A frame after the switch went off drew the hitboxes again"
	end

	-- 3) On again: the owner, the NPC drawn throughout and the one spawned while off are all drawn
	switch(true)
	rig.frames(1)

	for _, key: string in { OWNER, `{KEPT}`, `{LATER}` } do
		local anchor: any = drawing(key)
		if not anchor or not anchor:FindFirstChild("Hull") or not anchor.Hull.Visible then
			return false, `Switching on again drew no hull for {key}`
		end
	end

	if drawing(`{FIRST}`) then
		return false, "Switching on again drew the slot freed earlier"
	end

	switch(false)

	if workspace:FindFirstChild(DRAWN) then
		return false, "The second switch off left the hitboxes' folder"
	end

	return true, nil
end
