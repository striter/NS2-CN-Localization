--[[
	Shine's logging system.
]]

local Shine = Shine

local Ceil = math.ceil
local Date = os.date
local Floor = math.floor
local Notify = Shared.Message
local StringFormat = string.format
local TableConcat = table.concat
local TableEmpty = table.Empty
local type = type

--Geez what was I thinking with that old method...
local function GetDate( Logging )
	local DateFormat = Shine.Config.DateFormat
	local FormatString = DateFormat:gsub( "(d+)", "%%d" ):gsub( "(m+)", "%%m" )

	if FormatString:find( "yyyy" ) then
		FormatString = FormatString:gsub( "(y+)", "%%Y" )
	else
		FormatString = FormatString:gsub( "(y+)", "%%y" )
	end

	return Date( FormatString )
end
Shine.GetDate = GetDate

local function GetTimeString()
	return Date( "[%H:%M:%S]" )
end
Shine.GetTimeString = GetTimeString

Shared.OldMessage = Shared.OldMessage or Shared.Message

--[[
	Fun fact for anyone reading, this thread started Shine:

	http://forums.unknownworlds.com/discussion/126283/time-in-log-files

	and this function was its first feature.
]]
function Shared.Message( String )
	return Notify( GetTimeString()..String )
end

do
	local CurrentLogFileHandle
	local CurrentLogFileName
	local LogMessages = {}

	-- Limit logs to 10MiB max to avoid reading too much data into memory in one go.
	local MAX_LOG_SIZE = 1024 * 1024 * 10

	local LogFileIndex
	local function GetCurrentLogFile()
		return StringFormat(
			"%s%s%s.txt",
			Shine.Config.LogDir,
			GetDate(),
			LogFileIndex and ( "-"..LogFileIndex ) or ""
		)
	end

	function Shine:LogString( String )
		if not self.Config.EnableLogging then return end

		LogMessages[ #LogMessages + 1 ] = GetTimeString()..String
	end

	function Shine:SaveLog( ForceFlush )
		if not self.Config.EnableLogging then return false end

		local LogFileName = GetCurrentLogFile()
		if LogFileName ~= CurrentLogFileName then
			-- Make sure the new log file name starts at the first file of the day.
			LogFileIndex = nil
			LogFileName = GetCurrentLogFile()

			if CurrentLogFileHandle then
				CurrentLogFileHandle:flush()
				CurrentLogFileHandle:close()
				CurrentLogFileHandle = nil
			end

			-- This is dumb, but append mode appears to be broken.
			local File, Err = io.open( LogFileName, "r" )
			local ExistingContents
			while File do
				local Size = File:seek( "end" )
				if Size > MAX_LOG_SIZE then
					-- File has grown too large, move on to another file to avoid massive logs.
					LogFileIndex = ( LogFileIndex or 1 ) + 1
					LogFileName = GetCurrentLogFile()
					File, Err = io.open( LogFileName, "r" )
				else
					File:seek( "set", 0 )
					ExistingContents = File:read( "*all" )
					File:close()
					break
				end
			end

			Shared.Message( StringFormat( "[Shine] Opening new log file for writing: %s", LogFileName ) )

			File, Err = io.open( LogFileName, "w+" )
			if not File then
				-- Assume that if it's failed now it's going to fail next time and thus clear the messages to avoid
				-- forever increasing memory usage.
				TableEmpty( LogMessages )
				Shared.Message( StringFormat( "Error opening new log file: %s", Err  ) )
				return false
			end

			if ExistingContents then
				File:write( ExistingContents )
				File:flush()
			end

			CurrentLogFileHandle = File
			CurrentLogFileName = LogFileName
		end

		CurrentLogFileHandle:write( TableConcat( LogMessages, "\n" ), "\n" )

		if ForceFlush then
			CurrentLogFileHandle:flush()
		end

		TableEmpty( LogMessages )

		return true
	end

	-- Periodically save the log file.
	Shine.Hook.Add( "EndGame", "SaveLog", function()
		Shine:SaveLog()
	end, Shine.Hook.MAX_PRIORITY )

	Shine.Hook.Add( "MapChange", "SaveLog", function()
		Shine:SaveLog()

		if CurrentLogFileHandle then
			CurrentLogFileHandle:flush()
			CurrentLogFileHandle:close()
			CurrentLogFileHandle = nil
			CurrentLogFileName = nil
		end
	end, Shine.Hook.MIN_PRIORITY )

	Shine.Timer.Create( "LogSave", 300, -1, function()
		Shine:SaveLog()
	end )

	Shine:RegisterCommand( "sh_flushlog", nil, function( Client )
		if Shine:SaveLog( true ) then
			Shine:AdminPrint( Client, "Log flushed successfully." )
		else
			Shine:AdminPrint( Client, "Failed to flush log. Either logging is disabled, or an error occurred." )
		end
	end ):Help( "Flushes Shine's current log file to disk." )
end

function Shine:Print( String, Format, ... )
	String = Format and StringFormat( String, ... ) or String

	Shared.Message( String )

	self:LogString( String )
end

local IsType = Shine.IsType

--[[
	Sends a chat message to the given player(s).
]]
function Shine:Notify( Player, Prefix, Name, String, Format, ... )
	local Message = Format and StringFormat( String, ... ) or String

	if Prefix == "" and Name == "" then
		return self:NotifyColour( Player, 255, 255, 255, String, Format, ... )
	end

	if Player == "Console" then
		Shared.Message( Message )

		return
	end

	local MessageLength = Message:UTF8Length()
	if MessageLength > kMaxChatLength then
		local Iterations = Ceil( MessageLength / kMaxChatLength )

		for i = 1, Iterations do
			self:Notify( Player, Prefix, Name, Message:UTF8Sub( 1 + kMaxChatLength * ( i - 1 ),
				kMaxChatLength * i ) )
		end

		return
	end

	local MessageTable = self.BuildChatMessage( Prefix, Name, kTeamReadyRoom,
		kNeutralTeamType, Message )

	self:ApplyNetworkMessage( Player, "Shine_Chat", MessageTable, true )

	Server.AddChatToHistory( Message, Name, 0, kTeamReadyRoom, false )
end

--[[
	Sends a coloured notification to the given player(s).
]]
function Shine:NotifyColour( Player, R, G, B, String, Format, ... )
	self:NotifyDualColour( Player, 0, 0, 0, "", R, G, B, String, Format, ... )
end

--[[
	Sends a coloured notification to the given player(s), supporting a coloured prefix.
]]
function Shine:NotifyDualColour( Player, RP, GP, BP, Prefix, R, G, B, String, Format, ... )
	local Message = Format and StringFormat( String, ... ) or String

	-- Use the maximum amount of the allowed byte length.
	local MaxBytes = kMaxChatLength * 4
	if #Message > MaxBytes then
		local Chars = Message:UTF8Encode()
		local NumBytes = 0
		local StopIndex = 1

		for i = 1, #Chars do
			NumBytes = NumBytes + #Chars[ i ]
			if NumBytes > MaxBytes then
				StopIndex = i - 1
				break
			end
		end

		Message = TableConcat( Chars, "", 1, StopIndex )
	end

	local MessageTable = {
		R = R,
		G = G,
		B = B,
		Message = Message,
		RP = RP,
		GP = GP,
		BP = BP,
		Prefix = Prefix
	}

	self:ApplyNetworkMessage( Player, "Shine_ChatCol", MessageTable, true )
end

--[[
	Similar to NotifyColour, except the message is a translation key which is
	resolved client-side.
]]

function Shine:TranslatedNotifyColour( Player, R, G, B, String, Source )
	self:TranslatedNotifyDualColour( Player, 0, 0, 0, "", R, G, B, String, Source )
end

--[[
	Similar to NotifyDualColour, except the prefix and message are translation keys which
	are resolved client-side.
]]
function Shine:TranslatedNotifyDualColour( Player, RP, GP, BP, Prefix, R, G, B, String, Source )
	self:ApplyNetworkMessage( Player, "Shine_TranslatedChatCol", {
		R = R,
		G = G,
		B = B,
		Message = String,
		RP = RP,
		GP = GP,
		BP = BP,
		Prefix = Prefix,
		Source = Source or ""
	}, true )
end

--[[
	An easy error message function.
]]
function Shine:NotifyError( Player, Message, Format, ... )
	if Player == "Console" then
		Shared.Message( Format and StringFormat( Message, ... ) or Message )
		return
	end

	self:ApplyNetworkMessage( Player, "Shine_ChatErrorMessage", {
		Message = Format and StringFormat( Message, ... ) or Message,
		Source = ""
	}, true )
end

--[[
	Sends a translation key which the client will resolve to an error message.
]]
function Shine:TranslatedNotifyError( Player, Message, Source )
	if Player == "Console" then return end

	self:ApplyNetworkMessage( Player, "Shine_ChatErrorMessage", {
		Message = Message,
		Source = Source
	}, true )
end

do
	local SharedTime = Shared.GetTime

	local NextNotification = {}
	function Shine:CanNotify( Client )
		if not Client then return false end

		local NextTime = NextNotification[ Client ] or 0
		local Time = SharedTime()

		if Time < NextTime then return false end

		NextNotification[ Client ] = Time + 5

		return true
	end

	Shine.Hook.Add( "ClientDisconnect", "NextNotification", function( Client )
		NextNotification[ Client ] = nil
	end )
end

function Shine:DoCommandNotify( Client, Message, Sender, ... )
	local IsConsole = not Client
	local Name

	if IsConsole then
		Name = self.Config.ConsoleName
	else
		local Player = Client:GetControllingPlayer()
		if Player then
			Name = Player:GetName()
		else
			Name = self.Config.ChatName
		end
	end

	if not self.Config.NotifyOnCommand then
		-- Console can see the success already.
		if IsConsole then return end

		-- Always notify the client that performed the action to confirm
		-- that their command was a success.
		Sender( self, Client, Name, Message, ... )

		return
	end

	local Clients = self.GameIDs
	local Immunity = self:GetUserImmunity( Client )

	local NotifyAnonymous = self.Config.NotifyAnonymous
	local NotifyAdminAnonymous = self.Config.NotifyAdminAnonymous

	for Target in Clients:Iterate() do
		--Console should always notify with its special name.
		if IsConsole then
			Sender( self, Target, Name, Message, ... )
		else
			--If admins can't see it, no one can.
			if NotifyAdminAnonymous then
				Sender( self, Target, self.Config.ChatName, Message, ... )
			else
				local TargetImmunity = self:GetUserImmunity( Target )
				local IsGreaterEqual = TargetImmunity >= Immunity

				--They're greater equal in rank, so show the name.
				if IsGreaterEqual then
					Sender( self, Target, Name, Message, ... )
				else
					--If we're set to be anonymous to lower ranks, use the set generic admin name.
					if NotifyAnonymous then
						Sender( self, Target, self.Config.ChatName, Message, ... )
					else --Otherwise use the admin's name.
						Sender( self, Target, Name, Message, ... )
					end
				end
			end
		end
	end
end

do
	local function SendNonTranslatedMessage( self, Target, Name, Message )
		self:NotifyDualColour( Target, 255, 255, 0, Name, 255, 255, 255, Message )
	end

	--[[
		Notifies players of a command, obeying the settings for who can see names,
		and how the console should be displayed.
	]]
	function Shine:CommandNotify( Client, Message, Format, ... )
		Message = Format and StringFormat( Message, ... ) or Message

		self:DoCommandNotify( Client, Message, SendNonTranslatedMessage )
	end
end

Shine.Hook.Add( "OnFirstThink", "OverrideServerAdminPrint", function( Deltatime )
	local Min = math.min
	local StringExplode = string.Explode
	local StringUTF8Encode = string.UTF8Encode
	local TableConcat = table.concat

	local function WrapText( Lines, Chars, StartIndex, MaxLength )
		local NumBytes = 0
		local LastEndIndex = StartIndex

		for i = StartIndex, #Chars do
			local CharByteLength = #Chars[ i ]

			NumBytes = NumBytes + CharByteLength

			if NumBytes > MaxLength then
				Lines[ #Lines + 1 ] = TableConcat( Chars, "", LastEndIndex, i - 1 )
				LastEndIndex = i
				NumBytes = CharByteLength
			end
		end

		if LastEndIndex <= #Chars then
			Lines[ #Lines + 1 ] = TableConcat( Chars, "", LastEndIndex )
		end
	end

	local function WrapWords( Lines, Chars, MaxLength )
		local StartIndex = 1
		local CurrentLength = 0
		local NumWordsInLine = 0
		local LastWordIndex = 1
		local NumChars = #Chars

		for i = 1, NumChars do
			local Char = Chars[ i ]

			if Char == " " then
				NumWordsInLine = NumWordsInLine + 1

				if CurrentLength > MaxLength then
					-- If it's a single word, need to keep cutting it until the remainder is less than the max length.
					while CurrentLength > MaxLength do
						if NumWordsInLine == 1 then
							-- Overflow comes from a single word, so cut it in half.
							Lines[ #Lines + 1 ] = TableConcat(
								Chars, "", StartIndex, Min( StartIndex + MaxLength - 1, NumChars )
							)
							StartIndex = StartIndex + MaxLength
						else
							-- Overflow comes from multiple words, take all of the words seen on this line except
							-- the one that triggered the overflow.
							Lines[ #Lines + 1 ] = TableConcat( Chars, "", StartIndex, LastWordIndex )
							StartIndex = LastWordIndex + 2
						end

						CurrentLength = CurrentLength - MaxLength
						NumWordsInLine = 1
					end
				else
					-- Only count whitespace length in the middle of a line, not the end of it.
					CurrentLength = CurrentLength + #Char
				end

				LastWordIndex = i - 1
			else
				CurrentLength = CurrentLength + #Char
			end
		end

		-- Make sure any remaining text is included (can't be more than one word).
		if StartIndex <= #Chars then
			WrapText( Lines, Chars, StartIndex, MaxLength )
		end
	end

	local function WrapTextOrWords( Lines, TextToWrap, MaxLength, WrapEntireTextOnly )
		if #TextToWrap <= MaxLength then
			Lines[ #Lines + 1 ] = TextToWrap
			return
		end

		local Chars = StringUTF8Encode( TextToWrap )

		if WrapEntireTextOnly then
			return WrapText( Lines, Chars, 1, MaxLength )
		end

		return WrapWords( Lines, Chars, MaxLength )
	end
	Shine.WrapTextByLength = WrapTextOrWords

	local MaxPrintLength = 127

	--[[
		Rewrite ServerAdminPrint to not print to the server console when used,
		otherwise we'll get spammed with repeat prints when sending to lots of people at once.

		Also make it word-wrap overflowing text.
	]]
	function ServerAdminPrint( Client, Message, WrapEntireTextOnly )
		if not Client then return end

		if #Message <= MaxPrintLength then
			Shine.SendNetworkMessage( Client, "ServerAdminPrint",
				{ message = Message }, true )
			return
		end

		-- Preserve the lines of the original message, and only wrap based on those.
		local ProvidedLines = StringExplode( Message, "\n", true )
		local WrappedLines = {}

		for i = 1, #ProvidedLines do
			WrapTextOrWords( WrappedLines, ProvidedLines[ i ], MaxPrintLength, WrapEntireTextOnly )
		end

		-- Then, consolidate each wrapped line into the smallest number of network messages (some
		-- of the provided lines may be far smaller than the size limit).
		local CurrentLength = 0
		local StartIndex = 1

		for i = 1, #WrappedLines do
			local Line = WrappedLines[ i ]
			local LineLength = #Line
			CurrentLength = CurrentLength + LineLength

			if CurrentLength > MaxPrintLength then
				Shine.SendNetworkMessage( Client, "ServerAdminPrint", {
					message = TableConcat( WrappedLines, "\n", StartIndex, i - 1 )
				}, true )

				StartIndex = i
				CurrentLength = LineLength
			end
		end

		Shine.SendNetworkMessage( Client, "ServerAdminPrint", {
			message = TableConcat( WrappedLines, "\n", StartIndex )
		}, true )
	end
end )

--[[
	Prints a translated value to the given target(s) console.
]]
function Shine:TranslatedConsolePrint( Client, MessageKey, Source )
	self:ApplyNetworkMessage( Client, "Shine_TranslatedConsoleMessage", {
		Source = Source,
		MessageKey = MessageKey
	}, true )
end

do
	local DEFAULT_DURATION = 5
	function Shine:SendNotification( Client, Type, Message, OnlyIfAdminMenuOpen, Duration )
		self:ApplyNetworkMessage( Client, "Shine_Notification", {
			Type = Type,
			Message = Message,
			Duration = Duration or DEFAULT_DURATION,
			OnlyIfAdminMenuOpen = OnlyIfAdminMenuOpen or false
		}, true )
	end

	function Shine:SendTranslatedNotification( Client, Type, MessageKey, Source, OnlyIfAdminMenuOpen, Duration )
		self:ApplyNetworkMessage( Client, "Shine_TranslatedNotification", {
			Type = Type,
			MessageKey = MessageKey,
			Source = Source or "",
			Duration = Duration or DEFAULT_DURATION,
			OnlyIfAdminMenuOpen = OnlyIfAdminMenuOpen or false
		}, true )
	end

	--[[
		Prints the given message to the console of all online admins, and also sends a notification
		to the given client to display if they are currently in the admin menu.
	]]
	function Shine:SendAdminNotification( Client, Type, Message, Duration )
		self:AdminPrint( Client, Message )
		if Client then
			self:SendNotification( Client, Type, Message, true, Duration )
		end
	end
end

function Shine:AdminPrint( Client, String, Format, ... )
	self:Print( String, Format, ... )

	local Message = Format and StringFormat( String, ... ) or String
	local Admins = self:GetClientsForLog()

	for i = 1, #Admins do
		local Admin = Admins[ i ]
		if Admin ~= Client then
			ServerAdminPrint( Admin, Message )
		end
	end

	if not Client then return end

	return ServerAdminPrint( Client, Message )
end

do
	local Max = math.max
	local StringRep = string.rep
	local StringUTF8Length = string.UTF8Length
	local TableEmpty = table.Empty
	local TableNew = require "table.new"

	local function PrintToConsole( Client, Message )
		if not Client then
			Notify( Message )
			return
		end

		ServerAdminPrint( Client, Message )
	end

	Shine.PrintToConsole = PrintToConsole

	--[[
		Prints a formatted table to the given client's console.

		This assumes the console is using a monospace font (which, unless modded, it does).

		Inputs:
			1. Client to print the table to. If nil, will be printed to the server console.
			2. A list of column definitions of the form:
			{
				-- The name to print for the column.
				Name = "Name of Column",

				-- Optional getter. If omitted, Row[ Name ] will be used for the column value.
				Getter = function( Row ) return Row.Field end
			}
			3. The data to be printed. Should be an array of values that will be printed based on the columns.
	]]
	function Shine.PrintTableToConsole( Client, Columns, Data )
		local NumRows = #Data
		local NumColumns = #Columns

		local RowDataByColumn = TableNew( NumColumns, 0 )
		local TotalLength = 0
		local ColumnSpacing = StringRep( " ", Columns.SpacingAmount or 4 )
		local CellLengths = TableNew( NumRows, 0 )

		for i = 1, NumColumns do
			local Column = Columns[ i ]
			local FieldName = Column.Name

			local Name = Column.Name..ColumnSpacing
			local Getter = Column.Getter
			local NameLength = StringUTF8Length( Name )
			local MaxLength = NameLength
			local CellsByRowIndex = TableNew( NumRows + 1, 0 )

			TableEmpty( CellLengths )

			-- First build the cell values and find the maximum length.
			for j = 1, NumRows do
				local Entry = Data[ j ]

				local String = ( Getter and Getter( Entry ) or Entry[ FieldName ] )..ColumnSpacing
				local Length = StringUTF8Length( String )

				CellLengths[ j ] = Length
				CellsByRowIndex[ j ] = String
				MaxLength = Max( MaxLength, Length )
			end

			-- For each cell, add whitespace if the cell's length is less than the maximum.
			for j = 1, NumRows do
				local Entry = CellsByRowIndex[ j ]
				local Diff = MaxLength - CellLengths[ j ]
				if Diff > 0 then
					CellsByRowIndex[ j ] = Entry..StringRep( " ", Diff )
				end
			end

			TotalLength = TotalLength + MaxLength

			-- Make sure the header lines up with the content width.
			local NameDiff = MaxLength - NameLength
			if NameDiff > 0 then
				Name = Name..StringRep( " ", Floor( NameDiff ) )
			end

			CellsByRowIndex[ 0 ] = Name

			RowDataByColumn[ i ] = CellsByRowIndex
		end

		-- Finally, print all rows, starting with the header.
		local Row = TableNew( NumColumns, 0 )
		for i = 1, NumColumns do
			Row[ i ] = RowDataByColumn[ i ][ 0 ]
		end

		PrintToConsole( Client, TableConcat( Row, "" ) )
		PrintToConsole( Client, StringRep( "=", TotalLength ) )

		for i = 1, NumRows do
			TableEmpty( Row )

			for j = 1, NumColumns do
				Row[ j ] = RowDataByColumn[ j ][ i ]
			end

			PrintToConsole( Client, TableConcat( Row, "" ) )
		end
	end
end
