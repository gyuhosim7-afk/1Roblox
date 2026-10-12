--!strict
-- Minimal signal used for in-process events. Handlers run in connection order.

export type Connection = { Disconnect: (self: Connection) -> (), Connected: boolean }

type Entry = { connection: Connection, handler: (...any) -> () }

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable({} :: { _entries: { Entry } }, Signal))

function Signal.new(): Signal
	return setmetatable({ _entries = {} }, Signal)
end

function Signal.Connect(self: Signal, handler: (...any) -> ()): Connection
	local entries = self._entries
	local connection = { Connected = true } :: any
	local entry: Entry = { connection = connection, handler = handler }
	function connection.Disconnect(conn: Connection)
		conn.Connected = false
		local index = table.find(entries, entry)
		if index then
			table.remove(entries, index)
		end
	end
	table.insert(entries, entry)
	return connection
end

function Signal.Fire(self: Signal, ...: any)
	for _, entry in table.clone(self._entries) do
		if entry.connection.Connected then
			task.spawn(entry.handler, ...)
		end
	end
end

function Signal.DisconnectAll(self: Signal)
	for _, entry in self._entries do
		entry.connection.Connected = false
	end
	table.clear(self._entries)
end

return Signal
