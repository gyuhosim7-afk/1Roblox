-- Virtual-time scheduler that stands in for Roblox's task library inside tests.
-- Time only moves when a test calls Scheduler:Advance(seconds).

local Scheduler = {}
Scheduler.__index = Scheduler

export type Scheduler = typeof(setmetatable(
	{} :: {
		now: number,
		epoch: number,
		queue: { { at: number, seq: number, thread: thread, args: { any }, cancelled: boolean? } },
		deferred: { { thread: thread, args: { any } } },
		seq: number,
		errors: { string },
		onStep: ((dt: number) -> ())?,
	},
	Scheduler
))

function Scheduler.new(epoch: number?)
	local self = setmetatable({
		now = 0,
		epoch = epoch or 1_790_000_000,
		queue = {},
		deferred = {},
		seq = 0,
		errors = {},
		onStep = nil,
	}, Scheduler)
	return self
end

function Scheduler:_resume(thread: thread, ...: any)
	if coroutine.status(thread) ~= "suspended" then
		return
	end
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		local message = tostring(err) .. "\n" .. debug.traceback(thread)
		table.insert(self.errors, message)
	end
end

function Scheduler:_schedule(at: number, thread: thread, args: { any })
	self.seq += 1
	local entry = { at = at, seq = self.seq, thread = thread, args = args }
	table.insert(self.queue, entry)
	return entry
end

-- Runs deferred threads and every thread due at or before the current time.
function Scheduler:RunDue()
	local guard = 0
	while true do
		guard += 1
		if guard > 100000 then
			error("Scheduler: too many iterations (infinite loop?)")
		end
		if #self.deferred > 0 then
			local list = self.deferred
			self.deferred = {}
			for _, item in list do
				self:_resume(item.thread, table.unpack(item.args))
			end
			continue
		end
		local bestIndex, best = nil, nil
		for index, entry in self.queue do
			if
				entry.at <= self.now + 1e-9
				and (best == nil or entry.at < best.at or (entry.at == best.at and entry.seq < best.seq))
			then
				bestIndex, best = index, entry
			end
		end
		if not bestIndex then
			break
		end
		table.remove(self.queue, bestIndex)
		if not best.cancelled then
			self:_resume(best.thread, table.unpack(best.args))
		end
	end
end

-- Moves virtual time forward in small steps, firing onStep (Heartbeat) each step.
function Scheduler:Advance(seconds: number, step: number?)
	local dt = step or (1 / 20)
	local target = self.now + seconds
	self:RunDue()
	while self.now < target - 1e-9 do
		local delta = math.min(dt, target - self.now)
		self.now += delta
		if self.onStep then
			self.onStep(delta)
		end
		self:RunDue()
	end
end

function Scheduler:ThrowIfErrors()
	if #self.errors > 0 then
		local message = table.concat(self.errors, "\n----\n")
		self.errors = {}
		error("Errors in scheduled threads:\n" .. message, 2)
	end
end

-- Builds the `task` library bound to this scheduler.
function Scheduler:TaskLibrary()
	local scheduler = self
	local lib = {}

	function lib.spawn(fnOrThread: any, ...: any): thread
		local thread = if type(fnOrThread) == "thread" then fnOrThread else coroutine.create(fnOrThread)
		scheduler:_resume(thread, ...)
		return thread
	end

	function lib.defer(fnOrThread: any, ...: any): thread
		local thread = if type(fnOrThread) == "thread" then fnOrThread else coroutine.create(fnOrThread)
		table.insert(scheduler.deferred, { thread = thread, args = { ... } })
		return thread
	end

	function lib.delay(seconds: number?, fnOrThread: any, ...: any): thread
		local thread = if type(fnOrThread) == "thread" then fnOrThread else coroutine.create(fnOrThread)
		scheduler:_schedule(scheduler.now + (seconds or 0), thread, { ... })
		return thread
	end

	function lib.wait(seconds: number?): number
		local thread = coroutine.running()
		local isMain = coroutine.isyieldable() == false
		if isMain then
			error("task.wait called outside a coroutine in tests")
		end
		local start = scheduler.now
		scheduler:_schedule(scheduler.now + math.max(seconds or 0, 1 / 60), thread, {})
		coroutine.yield()
		return scheduler.now - start
	end

	function lib.cancel(thread: thread)
		for _, entry in scheduler.queue do
			if entry.thread == thread then
				entry.cancelled = true
			end
		end
		for index = #scheduler.deferred, 1, -1 do
			if scheduler.deferred[index].thread == thread then
				table.remove(scheduler.deferred, index)
			end
		end
		pcall(coroutine.close, thread)
	end

	function lib.synchronize() end
	function lib.desynchronize() end

	return lib
end

function Scheduler:Time(): number
	return self.epoch + self.now
end

return Scheduler
