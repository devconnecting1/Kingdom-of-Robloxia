--!strict
-- Values that move between server pushes: resources ticking up, stamina, timers. The server sends rates and
-- timestamps once; the client extrapolates them every frame instead of being sent new numbers every second.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Rules.Balance)

local Live = {}

function Live.resources(view: any, now: number): { [string]: number }
	local out = {}
	local dt = math.max(0, now - view.now)
	for _, res in Balance.RESOURCES do
		local have = view.resources[res] or 0
		if have < view.cap then
			have = math.min(view.cap, have + (view.rates[res] or 0) * dt / 3600)
		end
		out[res] = math.floor(have)
	end
	return out
end

function Live.stamina(view: any, now: number): number
	if view.stamina >= Balance.STAMINA_MAX then
		return Balance.STAMINA_MAX
	end
	local gained = math.floor((now - view.staminaAt) / view.staminaSeconds)
	return math.min(Balance.STAMINA_MAX, view.stamina + math.max(0, gained))
end

function Live.left(job: any, now: number): number
	return math.max(0, job.endAt - now)
end

function Live.fraction(job: any, now: number): number
	local span = job.endAt - job.startAt
	if span <= 0 then
		return 1
	end
	return math.clamp((now - job.startAt) / span, 0, 1)
end

function Live.legPosition(leg: any, now: number): (number, number)
	local span = leg.t1 - leg.t0
	local t = if span > 0 then math.clamp((now - leg.t0) / span, 0, 1) else 1
	return leg.ax + (leg.bx - leg.ax) * t, leg.ay + (leg.by - leg.ay) * t
end

function Live.buildingJob(view: any, building: string): any
	for _, job in view.builds do
		if job.building == building then
			return job
		end
	end
	return nil
end

return Live
