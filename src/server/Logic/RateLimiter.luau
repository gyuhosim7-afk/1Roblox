--!strict
-- Token bucket per key (player). Pure logic; caller supplies the clock.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
	{} :: { capacity: number, refill: number, buckets: { [any]: { tokens: number, at: number } } },
	RateLimiter
))

function RateLimiter.new(capacity: number, refillPerSecond: number): RateLimiter
	return setmetatable({ capacity = capacity, refill = refillPerSecond, buckets = {} }, RateLimiter)
end

-- Returns true if the action is allowed (and spends one token).
function RateLimiter.Allow(self: RateLimiter, key: any, now: number, cost: number?): boolean
	local bucket = self.buckets[key]
	if not bucket then
		bucket = { tokens = self.capacity, at = now }
		self.buckets[key] = bucket
	end
	local elapsed = math.max(0, now - bucket.at)
	bucket.tokens = math.min(self.capacity, bucket.tokens + elapsed * self.refill)
	bucket.at = now
	local price = cost or 1
	if bucket.tokens >= price then
		bucket.tokens -= price
		return true
	end
	return false
end

function RateLimiter.Remove(self: RateLimiter, key: any)
	self.buckets[key] = nil
end

return RateLimiter
