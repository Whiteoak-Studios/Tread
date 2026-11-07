--[[
    A stand-in for the client's rig pool with the Rigs module's members,
    which writes down every call and lets a case raise a marker, since Lune
    can load no animation and ragdoll no rig
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

-- One call the pool was made, by its member, with what it was handed
export type Call = { [string]: any }

export type Pool = { [string]: any }

local Pool = {}

--[[
    A fresh pool. Its module answers the handle's require of Rigs, and new
    hands back the pool's rigs, refusing what the real pool refuses: a
    second checkout for a slot, and any other call for a slot with no rig
--]]

function Pool.new(): Pool
	local pool: Pool = {
		calls = {} :: { Call },
		made = 0, -- How many times new ran
	}

	local slots: { [number]: any } = {}
	local listeners: { [{ nil }]: (slot: number, marker: string, value: string) -> () } = {}

	local function record(call: Call)
		table.insert(pool.calls, call)
	end

	local function entry(slot: number, member: string): any
		local rig: any = slots[slot]
		if not rig then
			error(`Rigs.{member} takes a slot with a rig checked out, not {slot}`)
		end

		return rig
	end

	local rigs: { [string]: any } = {}

	function rigs.checkout(_: any, slot: number, outfit: { [string]: any }): any
		if slots[slot] then
			error(`Slot {slot} already has a rig checked out`)
		end

		local rig: any = roblox.Instance.new("Model")
		rig.Name = `Rig{slot}`
		slots[slot] = rig
		record({ member = "checkout", slot = slot, outfit = outfit, rig = rig })

		return rig
	end

	function rigs.release(_: any, slot: number)
		local rig: any = entry(slot, "release")
		slots[slot] = nil
		record({ member = "release", slot = slot, rig = rig })
	end

	function rigs.pose(_: any, slot: number, state: any, distance: number, pitch: number)
		local rig: any = entry(slot, "pose")
		record({
			member = "pose",
			slot = slot,
			rig = rig,
			position = state.position,
			distance = distance,
			pitch = pitch,
		})
	end

	function rigs.ragdoll(_: any, slot: number, body: number, push: vector?)
		local rig: any = entry(slot, "ragdoll")
		if body ~= slot and slots[body] then
			error(`Slot {body} already has a rig, so slot {slot}'s body can't take its rig`)
		end

		slots[slot] = nil
		slots[body] = rig
		record({ member = "ragdoll", slot = slot, body = body, push = push, rig = rig })
	end

	function rigs.dress(_: any, slot: number, outfit: { [string]: any })
		record({ member = "dress", slot = slot, outfit = outfit, rig = entry(slot, "dress") })
	end

	function rigs.hold(_: any, slot: number, held: { [string]: any }?)
		record({ member = "hold", slot = slot, held = held, rig = entry(slot, "hold") })
	end

	function rigs.onMarker(_: any, callback: (slot: number, marker: string, value: string) -> ()): () -> ()
		local token: { nil } = {}
		listeners[token] = callback

		return function ()
			listeners[token] = nil
		end
	end

	function rigs.destroy(_: any)
		record({ member = "destroy" })
	end

	-- Raises a marker on a slot's rig, each callback under its own pcall as the real pool's xpcall runs it
	function pool.marker(slot: number, marker: string, value: string)
		entry(slot, "marker")

		for _, callback: (slot: number, marker: string, value: string) -> () in table.clone(listeners) do
			pcall(callback, slot, marker, value)
		end
	end

	-- The calls of one member, in the order they came
	function pool.of(member: string): { Call }
		local found: { Call } = {}
		for _, call: Call in pool.calls do
			if call.member == member then
				table.insert(found, call)
			end
		end

		return found
	end

	pool.module = {
		new = function (settings: any, drawDistance: number, collision: any): any
			pool.made += 1
			pool.settings = settings
			pool.drawDistance = drawDistance
			pool.collision = collision

			return rigs
		end,
	}

	return pool
end

return Pool
