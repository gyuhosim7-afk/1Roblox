--!strict
-- Minimal signal used for in-process events (no Roblox instances needed).

export type Connection = { Disconnect: (self: Connection) -> (), Connected: boolean }

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable({} :: { _handlers: { [Connection]: (...any) -> () } }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal.Connect(self: Signal, handler: (...any) -> ()): Connection
	local handlers = self._handlers
	local connection = { Connected = true } :: any
	function connection.Disconnect(conn: Connection)
		conn.Connected = false
		handlers[conn] = nil
	end
	handlers[connection] = handler
	return connection
end

function Signal.Fire(self: Signal, ...: any)
	for _, handler in self._handlers do
		task.spawn(handler, ...)
	end
end

function Signal.DisconnectAll(self: Signal)
	table.clear(self._handlers)
end

return Signal
