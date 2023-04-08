--[[
	Client side commands handling.
]]

local Notify = Shared.Message
local setmetatable = setmetatable
local StringFormat = string.format
local Traceback = debug.traceback
local type = type
local xpcall = xpcall

--[[
	Command object.
	Stores the console command and the function to run when these commands are used.
]]
local CommandMeta = Shine.Command

--[[
	Creates a command object.
	The object stores the console command and the function to run.
	It can also have parameters added to it to pass to its function.
]]
local function Command( ConCommand, Function )
	return setmetatable( {
		ConCmd = ConCommand,
		Func = Function,
		Arguments = {}
	}, CommandMeta )
end

local HookedCommands = {}

local ClientCommands = {}
Shine.ClientCommands = ClientCommands

--[[
	Registers a Shine client side command.
	Inputs: Console command to assign, function to run.
]]
function Shine:RegisterClientCommand( ConCommand, Function )
	self.TypeCheck( ConCommand, "string", 1, "RegisterClientCommand" )
	self.TypeCheck( Function, "function", 2, "RegisterClientCommand" )

	local CmdObj = Command( ConCommand, Function )

	ClientCommands[ ConCommand ] = CmdObj

	if not HookedCommands[ ConCommand ] then
		Event.Hook( "Console_"..ConCommand, function( ... )
			return Shine:RunClientCommand( ConCommand, ... )
		end )

		HookedCommands[ ConCommand ] = true
	end

	return CmdObj
end

function Shine:RemoveClientCommand( ConCommand )
	ClientCommands[ ConCommand ] = nil
end

function Shine.CommandUtil:OnFailedMatch( Client, ConCommand, ArgString, CurArg, Index )
	local ExpectedValue = self.GetExpectedValue( CurArg )
	Notify(
		Shine.Locale:GetInterpolatedPhrase( "Core", "COMMAND_DEFAULT_ERROR", {
			ArgNum = Index,
			CommandName = ConCommand,
			ExpectedType = ExpectedValue
		} )
	)
end

function Shine.CommandUtil:Validate( Client, ConCommand, Result, MatchedType, CurArg, Index )
	return true, Result
end

local OnError = Shine.BuildErrorHandler( "Client command error" )

--[[
	Executes a client side Shine command. Should not be called directly.
	Inputs: Console command to run, string arguments passed to the command.
]]
function Shine:RunClientCommand( ConCommand, ... )
	local Command = ClientCommands[ ConCommand ]
	if not Command or Command.Disabled then return end

	local Args = self.CommandUtil.AdjustArguments{ ... }

	local ParsedArgs = {}
	local ExpectedArgs = Command.Arguments
	local ExpectedCount = #ExpectedArgs

	for i = 1, ExpectedCount do
		local CurArg = ExpectedArgs[ i ]
		local ArgString = Args[ i ]
		local TakeRestOfLine = CurArg.TakeRestOfLine

		if TakeRestOfLine then
			if i < ExpectedCount then
				error( "Take rest of line called on function expecting more arguments!" )
			end

			ArgString = self.CommandUtil.BuildLineFromArgs( Args, i )
		end

		local Success, Result = self.CommandUtil:GetCommandArg( nil, ConCommand, ArgString, CurArg, i )
		if not Success then return end

		ParsedArgs[ i ] = Result
	end

	--Run the command with the parsed arguments we've gathered.
	local Success = xpcall( Command.Func, OnError, unpack( ParsedArgs, 1, ExpectedCount ) )

	if not Success then
		Shine:DebugPrint( "An error occurred when running the command: '%s'.", true, ConCommand )
	end
end
