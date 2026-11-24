--!strict
-- Token bucket per player. Each Roblox player is an account, so the limit can never punish a whole household or a
-- school that shares one address.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type Limiter = typeof(setmetatable(
	{} :: { rate: number, burst: number, buckets: { [number]: { tokens: number, at: number } } },
	RateLimiter
))

function RateLimiter.new(rate: number, burst: number): Limiter
	return setmetatable({ rate = rate, burst = burst, buckets = {} }, RateLimiter)
end

function RateLimiter.allow(self: Limiter, userId: number, now: number): boolean
	local bucket = self.buckets[userId]
	if not bucket then
		bucket = { tokens = self.burst, at = now }
		self.buckets[userId] = bucket
	end
	bucket.tokens = math.min(self.burst, bucket.tokens + (now - bucket.at) * self.rate)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function RateLimiter.forget(self: Limiter, userId: number)
	self.buckets[userId] = nil
end

return RateLimiter
