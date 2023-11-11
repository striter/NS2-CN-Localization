--[[
	Basic table streams.

	Provides a way to interact with array structures with simple functional methods.
	Note that streams will modify the table passed in directly.
]]

local setmetatable = setmetatable
local TableConcat = table.concat
local TableMergeSort = table.MergeSort
local TableQuickCopy = table.QuickCopy
local TableSort = table.sort
local tostring = tostring

local Stream = Shine.TypeDef()

-- Expose some useful predicate functions.
Predicates = {
	Equals = function( Value )
		return function( Entry )
			return Entry == Value
		end
	end,
	Has = function( Set )
		return function( Entry )
			return Set[ Entry ]
		end
	end,
	Not = function( Predicate )
		return function( Entry )
			return not Predicate( Entry )
		end
	end,
	And = function( Left, Right )
		return function( Value )
			return Left( Value ) and Right( Value )
		end
	end,
	Or = function( Left, Right )
		return function( Value )
			return Left( Value ) or Right( Value )
		end
	end
}

--[[
	Creates a stream containing the given values, but not referencing the original table.
]]
function Stream.Of( Table )
	return Stream( TableQuickCopy( Table ) )
end

function Stream:Init( Table )
	self.Data = Table

	return self
end

--[[
	Filters the stream based on the given predicate function.

	Any value for which the predicate returns false will be removed.
]]
function Stream:Filter( Predicate, Context )
	local Size = #self.Data
	local Offset = 0

	for i = 1, Size do
		self.Data[ i - Offset ] = self.Data[ i ]
		if not Predicate( self.Data[ i ], i, Context ) then
			self.Data[ i ] = nil
			Offset = Offset + 1
		end
	end

	for i = Size, Size - Offset + 1, -1 do
		self.Data[ i ] = nil
	end

	return self
end

--[[
	Performs an action on all values in the stream, without changing the stream.
]]
function Stream:ForEach( Function, Context )
	for i = 1, #self.Data do
		Function( self.Data[ i ], i, Context )
	end

	return self
end

--[[
	Maps the values of the stream using the given Mapper function.

	All values in the stream are replaced with what the mapper function returns for them.
]]
function Stream:Map( Mapper, Context )
	for i = 1, #self.Data do
		self.Data[ i ] = Mapper( self.Data[ i ], i, Context )
	end

	return self
end

--[[
	Returns a new stream that holds the distinct values of the current stream.
	This cannot contain nil values.
]]
function Stream:Distinct()
	local Seen = {}
	local Out = {}

	for i = 1, #self.Data do
		local Entry = self.Data[ i ]
		if Entry ~= nil and not Seen[ Entry ] then
			Seen[ Entry ] = true
			Out[ #Out + 1 ] = Entry
		end
	end

	return Stream( Out )
end

--[[
	Returns a single value built from all values in the stream.

	Consumer should be a function which takes the following parameters:
		1. Current reducing value, starts at StartValue if provided.
		2. Value at the current step in the stream.
		3. The current step.
	It should return the new reducing value which will be passed into the next step.

	If no start value is provided, then the first step will be at index 2 in the stream,
	with the current reducing value equal to the first value in the stream.
]]
function Stream:Reduce( Consumer, StartValue, Context )
	local ReducingValue = StartValue or self.Data[ 1 ]
	local StartIndex = StartValue and 1 or 2

	for i = StartIndex, #self.Data do
		ReducingValue = Consumer( ReducingValue, self.Data[ i ], i, Context )
	end

	return ReducingValue
end

--[[
	Returns true if any value in the stream matches the given predicate.
]]
function Stream:AnyMatch( Predicate, Context )
	for i = 1, #self.Data do
		if Predicate( self.Data[ i ], i, Context ) then
			return true
		end
	end
	return false
end

--[[
	Sorts the values in the stream with the given comparator, or nil for natural order.
]]
function Stream:Sort( Comparator )
	TableSort( self.Data, Comparator )

	return self
end

--[[
	Sorts the values in the stream with the given comparator using a stable merge sort.
]]
function Stream:StableSort( Comparator )
	TableMergeSort( self.Data, Comparator )

	return self
end

--[[
	Imposes a limit on the number of results.
]]
function Stream:Limit( Limit )
	for i = Limit + 1, #self.Data do
		self.Data[ i ] = nil
	end

	return self
end

--[[
	Concatenates the values in the stream into a single string based
	on the string value returned by the transformation function.
]]
function Stream:Concat( Separator, ToStringFunc )
	ToStringFunc = ToStringFunc or tostring

	local Values = {}

	for i = 1, #self.Data do
		Values[ i ] = ToStringFunc( self.Data[ i ] )
	end

	return TableConcat( Values, Separator )
end

--[[
	Returns the current table of data for the stream.
]]
function Stream:AsTable()
	return self.Data
end

function Stream:GetCount()
	return #self.Data
end

Shine.Stream = Stream
