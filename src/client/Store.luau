--!strict
-- Client state and the actions the interface calls. Orders go to the server; the server's answer (and its pushes)
-- update the state. Nothing here decides a rule: it only shows them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Rules.Balance)
local Locale = require(Shared.Locale)

local Store = {}

export type State = { [string]: any }

function Store.initialState(): State
	return {
		view = nil,
		marches = {},
		castles = {},
		chunks = {},
		tileIndex = {},
		chunksVersion = 0,
		now = 0,
		screen = "city",
		modal = nil,
		selected = {
			troop = "inf1",
			count = 50,
			hero = "aldric",
			report = nil,
			tile = nil,
			guildName = { adj = 1, noun = 1 },
		},
		map = { x = 48, y = 48, zoom = 1 },
		toasts = {},
	}
end

function Store.setChunk(state: State, chunk: number, list: { any })
	local old = state.chunks[chunk]
	if old then
		for _, ent in old do
			local key = ent.x .. "_" .. ent.y
			if state.tileIndex[key] == ent then
				state.tileIndex[key] = nil
			end
		end
	end
	state.chunks[chunk] = list
	for _, ent in list do
		state.tileIndex[ent.x .. "_" .. ent.y] = ent
	end
	state.chunksVersion += 1
end

-- `send(name, payload)` calls the server and returns its reply table; `changed()` asks for a re-render.
function Store.actions(state: State, send: (string, any) -> any, changed: () -> ()): { [string]: any }
	local actions = {}

	local function toast(text: string, kind: string?)
		table.insert(state.toasts, { text = text, kind = kind or "info", at = os.clock() })
		while #state.toasts > 4 do
			table.remove(state.toasts, 1)
		end
		changed()
	end
	actions.toast = toast

	local function order(name: string, payload: any?, onOk: ((any) -> ())?)
		task.spawn(function()
			local reply = send(name, payload or {})
			if reply and reply.ok then
				if onOk then
					onOk(reply.result)
				end
			else
				toast(Locale.t(if reply and reply.err then reply.err else "err.unknown"), "error")
			end
			changed()
		end)
	end
	actions.order = order

	function actions.navigate(screen: string)
		state.screen = screen
		state.modal = nil
		if screen == "reports" and state.view and state.view.reports[1] then
			state.selected.report = state.selected.report or state.view.reports[1].id
		end
		changed()
	end

	function actions.closeModal()
		state.modal = nil
		changed()
	end

	function actions.openBuilding(id: string)
		state.modal = { kind = "building", id = id }
		changed()
	end

	function actions.openRanking()
		state.modal = { kind = "ranking" }
		changed()
	end

	function actions.upgrade(id: string)
		state.modal = nil
		order("upgrade", { building = id })
	end

	function actions.finish(job: number)
		order("finish", { job = job })
	end

	function actions.claimQuest()
		order("claimQuest")
	end

	function actions.selectTroop(id: string)
		state.selected.troop = id
		changed()
	end

	function actions.setCount(n: number)
		state.selected.count = math.max(1, math.floor(n))
		changed()
	end

	function actions.train(id: string, count: number)
		order("train", { troop = id, count = count })
	end

	function actions.heal()
		order("heal")
	end

	function actions.research(id: string)
		order("research", { tech = id })
	end

	function actions.selectHero(id: string)
		state.selected.hero = id
		changed()
	end

	function actions.recruit(id: string)
		order("recruit", { hero = id })
	end

	function actions.openReport(id: number)
		state.selected.report = id
		changed()
	end

	function actions.readReports()
		order("readReports")
	end

	-- Map ---------------------------------------------------------------------------------------------------------

	function actions.selectTile(x: number, y: number)
		if state.dragMoved then
			return
		end
		local sel = state.selected.tile
		if sel and sel.x == x and sel.y == y then
			state.selected.tile = nil
		else
			state.selected.tile = { x = x, y = y }
		end
		changed()
	end

	function actions.mapHome()
		if state.view then
			state.map.x, state.map.y = state.view.castle.x, state.view.castle.y
			state.selected.tile = { x = state.view.castle.x, y = state.view.castle.y }
		end
		changed()
	end

	function actions.mapZoom(delta: number)
		state.map.zoom = math.clamp(state.map.zoom + delta * 0.25, 0.5, 1.5)
		changed()
	end

	function actions.mapPan(dxTiles: number, dyTiles: number)
		local max = Balance.MAP_SIZE - 1
		state.map.x = math.clamp(state.map.x + dxTiles, 0, max)
		state.map.y = math.clamp(state.map.y + dyTiles, 0, max)
		changed()
	end

	function actions.openMarch(kind: string, x: number, y: number)
		local view = state.view
		local troops = {}
		if kind ~= "scout" then
			-- Start from half of every troop type, within the march size.
			local room = view.marchSize
			for _, id in Balance.TROOP_ORDER do
				local n = math.min(math.floor((view.troops[id] or 0) / 2), room)
				if n > 0 then
					troops[id] = n
					room -= n
				end
			end
		end
		local hero = nil
		for _, id in Balance.HERO_ORDER do
			if view.heroes[id] then
				local busy = false
				for _, m in view.marches do
					if m.hero == id then
						busy = true
					end
				end
				if not busy then
					hero = id
					break
				end
			end
		end
		state.modal = { kind = "march", march = kind, x = x, y = y, troops = troops, hero = if kind == "scout" then nil else hero }
		changed()
	end

	function actions.setMarchTroop(id: string, n: number)
		if state.modal and state.modal.kind == "march" then
			state.modal.troops[id] = if n > 0 then n else nil
			changed()
		end
	end

	function actions.setMarchHero(id: string?)
		if state.modal and state.modal.kind == "march" then
			state.modal.hero = id
			changed()
		end
	end

	function actions.sendMarch()
		local m = state.modal
		if not m or m.kind ~= "march" then
			return
		end
		state.modal = nil
		state.selected.tile = nil
		order("march", {
			kind = m.march,
			x = m.x,
			y = m.y,
			troops = if m.march == "scout" then nil else m.troops,
			hero = m.hero,
		})
	end

	function actions.recall(id: number)
		order("recall", { march = id })
	end

	function actions.relocate(x: number, y: number)
		state.selected.tile = nil
		order("relocate", { x = x, y = y })
	end

	-- Guild -------------------------------------------------------------------------------------------------------

	function actions.guildJoin(id: number)
		order("guildJoin", { guild = id })
	end

	function actions.guildLeave()
		order("guildLeave")
	end

	function actions.guildHelp()
		order("guildHelp", {}, function(n)
			if type(n) == "number" then
				toast(Locale.t("toast.helped", { n = n }))
			end
		end)
	end

	function actions.cycleGuildName(part: string, delta: number)
		local list = if part == "adj" then Balance.GUILD_ADJECTIVES else Balance.GUILD_NOUNS
		local pick = state.selected.guildName
		pick[part] = (pick[part] - 1 + delta) % #list + 1
		changed()
	end

	function actions.guildCreate()
		local pick = state.selected.guildName
		order("guildCreate", { adj = pick.adj, noun = pick.noun })
	end

	return actions
end

return Store
