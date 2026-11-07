--[[
    A viewer's client for the interpolation cases: Interpolate started in a
    fresh game with Frontier Zero's settings, logs of what its signals tell,
    and the server's part, announcing slots and sending relay blocks
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../Codec/Game")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local WIRE: number = 2 ^ 16 -- The values a block's u16 sequence and tick hold

-- Frontier Zero's interpolation block and rates, from game-integration
local SETTINGS: { [string]: number } = { delay = 0.15, delayMax = 0.25, scaleMin = 0.95, scaleMax = 1.05 }
local RATES: { [string]: number } = { simulation = 20, relay = 20 }

export type Viewer = { [string]: any }

-- A copy all the way down, since Interpolate refills its own tables
local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local made: { [any]: any } = {}
	for key: any, inner: any in value do
		made[key] = copy(inner)
	end

	return made
end

local Viewer = {}

--[[
    A started viewer. Each override answers a require at its dotted path,
    as Environment.load takes them
--]]

function Viewer.new(overrides: { [string]: any }?): Viewer
	local globals: any = Environment.load(GLOBALS, overrides)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread

	local Interpolate: any = globals.require(tread.Client.Interpolate)
	local Block: any = globals.require(tread.Codec.Block)
	local Constants: any = globals.require(tread.Constants)
	local Fields: any = globals.require(tread.Codec.Fields)
	local Record: any = globals.require(tread.Codec.Record)
	local Reliable: any = globals.require(tread.Codec.Reliable)
	local Sequence: any = globals.require(tread.Codec.Sequence)
	local State: any = globals.require(tread.Step.State)
	local StateWord: any = globals.require(tread.Codec.StateWord)
	local layout: any = Fields.compile(Game.fields)

	local viewer: Viewer = {
		Interpolate = Interpolate,
		Constants = Constants,
		Record = Record,
		Sequence = Sequence,
		State = State,
		StateWord = StateWord,
		settings = SETTINGS,
		rates = RATES,
		limits = Game.limits,
		reveals = {},
		hides = {},
		dresses = {},
		holds = {},
		footsteps = {},
		sequence = 0,
	}

	Interpolate.start(SETTINGS, RATES, Game.limits, layout)

	Interpolate.onReveal(function (slot: number, kind: string, player: any, outfit: any, held: any)
		table.insert(
			viewer.reveals,
			{ slot = slot, kind = kind, player = player, outfit = copy(outfit), held = copy(held) }
		)
	end)

	Interpolate.onHide(function (slot: number)
		table.insert(viewer.hides, slot)
	end)

	Interpolate.onDress(function (slot: number, outfit: any)
		table.insert(viewer.dresses, { slot = slot, outfit = copy(outfit) })
	end)

	Interpolate.onHold(function (slot: number, held: any)
		table.insert(viewer.holds, { slot = slot, held = copy(held) })
	end)

	Interpolate.onFootstep(function (step: any)
		table.insert(viewer.footsteps, copy(step))
	end)

	-- One slot table entry as Volt's Slots sends it, a rig of nil freeing the slot
	function viewer.announce(slot: number, generation: number, rig: string?, player: any)
		local entry: { [string]: any } = { slot = 0, taken = nil }
		Reliable.write(entry, slot, generation, rig, player)
		Interpolate.slots({ entry })
	end

	--[[
	    Sends one relay block. Its tick is required and its sequence counts
	    up from 1 unless given. Reveals and hides are { slot, generation,
	    kind }; looks are { slot, generation, outfit?, held?, empty? }, empty
	    a held part of length 0; records are Record fields by name, every
	    one but slot, generation and position optional; footsteps are Block's
	--]]

	function viewer.send(spec: { [string]: any })
		local block: any = Block.new()
		local sequence: number? = spec.sequence

		if sequence == nil then
			viewer.sequence += 1
			sequence = viewer.sequence
		end

		block.sequence = (sequence :: number) % WIRE
		block.tick = spec.tick % WIRE

		local reveals: { any } = spec.reveals or {}
		local hides: { any } = spec.hides or {}
		block.reveals, block.revealCount = reveals, #reveals
		block.hides, block.hideCount = hides, #hides

		local looks: { any } = spec.looks or {}
		local partBytes: number = Constants.MAX_LOOK + Constants.MAX_HELD
		local parts: buffer = buffer.create(math.max(#looks, 1) * partBytes)

		for index: number, look: { [string]: any } in looks do
			local at: number = (index - 1) * partBytes
			local entry: { [string]: any } = {
				slot = look.slot,
				generation = look.generation,
				look = false,
				lookData = parts,
				lookAt = at,
				lookLength = 0,
				held = look.empty == true,
				heldData = parts,
				heldAt = at + Constants.MAX_LOOK,
				heldLength = 0,
			}

			if look.outfit then
				entry.look = true
				entry.lookLength = Fields.write(layout.slot, look.outfit, parts, at)
			end

			if look.held then
				entry.held = true
				entry.heldLength = Fields.write(layout.held, look.held, parts, at + Constants.MAX_LOOK)
			end

			block.looks[index] = entry
		end

		block.lookCount = #looks

		local records: { any } = spec.records or {}
		local recordData: buffer = buffer.create(math.max(#records, 1) * Constants.RECORD_BYTES)

		for index: number, fields: { [string]: any } in records do
			local record: { [string]: any } = Record.new()
			for name: string, value: any in fields do
				record[name] = value
			end

			Record.write(record, recordData, (index - 1) * Constants.RECORD_BYTES, Game.limits)
			block.records[index] = (index - 1) * Constants.RECORD_BYTES
		end

		block.recordData, block.recordCount = recordData, #records

		local steps: { any } = spec.footsteps or {}
		local stepData: buffer = buffer.create(math.max(#steps, 1) * Constants.FOOTSTEP_BYTES)

		for index: number, step: any in steps do
			Block.writeFootstep(step, stepData, (index - 1) * Constants.FOOTSTEP_BYTES)
			block.footsteps[index] = (index - 1) * Constants.FOOTSTEP_BYTES
		end

		block.footstepData, block.footstepCount = stepData, #steps

		local data: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
		local bytes: number = Block.write(block, data)
		local exact: buffer = buffer.create(bytes)
		buffer.copy(exact, 0, data, 0, bytes)

		Interpolate.receive(exact)
	end

	-- A slot's drawn state at the render time, in a fresh state, with whether it has one and its pitch
	function viewer.pose(slot: number): (boolean, any, number)
		local state: any = State.new()
		local drawn: boolean, pitch: number = Interpolate.pose(slot, state)

		return drawn, state, pitch
	end

	-- A state word for a record, every field at rest but those given
	function viewer.word(fields: { [string]: any }): number
		local word: { [string]: any } = {
			mode = "Ground",
			posture = "Stand",
			sprint = false,
			aim = false,
			waterLevel = "Dry",
			jumps = 0,
			lands = 0,
			heavy = false,
			epoch = 0,
		}

		for name: string, value: any in fields do
			word[name] = value
		end

		return StateWord.pack(word)
	end

	return viewer
end

return Viewer
