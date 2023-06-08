--[[
	Represents a stream of adverts that may be started/stopped,
	each may have its own delay and each may be filtered by game state.
]]

local IsType = Shine.IsType
local next = next
local StringFormat = string.format
local TableQuickShuffle = table.QuickShuffle

local AdvertStream = Shine.TypeDef()

--[[
	Constructs a new advert stream.

	Inputs:
		1. The plugin that provides message display functionality.
		2. The list of adverts to cycle through.
		3. Extra options:
			* InitialDelayInSeconds - how long to delay the first
			advert displayed after starting (overrides the advert's delay).
			* RequiresGameStateFiltering - indicates whether the
			advert list depends on game state.
			* RandomiseOrder - whether to randomise the order
			in which adverts are displayed.
			* Loop - whether to loop the adverts.
			* StartingTriggers - a lookup of trigger names that will
			start this stream.
			* StoppingTriggers - a lookup of trigger names that will
			stop this stream.
]]
function AdvertStream:Init( Plugin, AdvertsList, Options )
	Shine.TypeCheck( Plugin, "table", 1, "AdvertStream" )
	Shine.TypeCheck( AdvertsList, "table", 2, "AdvertStream" )
	Shine.TypeCheck( Options, "table", 3, "AdvertStream" )

	self.Plugin = Plugin
	self.Logger = Plugin.Logger
	self.AdvertsList = AdvertsList
	self.InitialDelayInSeconds = Options.InitialDelayInSeconds
	self.RequiresGameStateFiltering = Options.RequiresGameStateFiltering
	self.RandomiseOrder = Options.RandomiseOrder
	self.Loop = Options.Loop
	self.MinPlayers = Options.MinPlayers
	self.MaxPlayers = Options.MaxPlayers
	self.PlayerCount = 0

	self.StartingTriggers = Options.StartingTriggers or {}
	self.StoppingTriggers = Options.StoppingTriggers or {}

	self.CurrentMessageIndex = 1

	self.Started = false

	return self
end

--[[
	Restarts the stream, resetting the stream back to the first advert.
]]
function AdvertStream:Restart()
	self:Stop()
	self:Start()

	self.Logger:Debug( "%s restarted.", self )
end

--[[
	Stops the advert stream, if it is not already stopped.
]]
function AdvertStream:Stop()
	if not self.Started then return end

	self.Started = false

	-- Cancel any pending adverts.
	self:StopTimer()

	self.Logger:Debug( "%s stopped.", self )
end

--[[
	Starts the advert stream if it is not already started.

	This will prepare the filtered advert list, and start from
	the first advert, randomising the order if necessary.
]]
function AdvertStream:Start()
	if self.Started then return end

	self.Started = true

	self.Logger:Debug( "%s started.", self )

	if #self.AdvertsList == 0 then return end

	self.CurrentMessageIndex = 1
	if self.RequiresGameStateFiltering then
		local Gamerules = GetGamerules()
		local GameState = Gamerules and Gamerules:GetGameState() or kGameState.NotStarted
		-- Make sure to filter down to the right list of adverts now.
		self.CurrentAdvertsList = self.FilterAdvertListForState( self.AdvertsList,
			self.AdvertsList, GameState )
	else
		self.CurrentAdvertsList = self.AdvertsList
	end

	self:StartAdverts( self.InitialDelayInSeconds )
end

function AdvertStream:StopTimer()
	if not self.Timer then return end

	self.Timer:Destroy()
	self.Timer = nil
end

function AdvertStream:StartAdverts( DelayOverride )
	self:StopTimer()

	if #self.CurrentAdvertsList == 0 then return end

	if self.RandomiseOrder then
		TableQuickShuffle( self.CurrentAdvertsList )
	end

	self:QueueNextAdvert( DelayOverride )
end

function AdvertStream:IsStartedByTrigger()
	return next( self.StartingTriggers ) ~= nil
end

function AdvertStream:WillStartOnTrigger( TriggerName )
	return self.StartingTriggers[ TriggerName ] ~= nil
end

function AdvertStream:OnTrigger( TriggerName )
	if self.StartingTriggers[ TriggerName ] and self:CanStart( self.PlayerCount ) then
		self:Start()
	end
	if self.StoppingTriggers[ TriggerName ] then
		self:Stop()
	end
end

function AdvertStream:OnGameStateChanged( NewState )
	if not self.RequiresGameStateFiltering then return end

	local NewAdverts, HasListChanged = self.FilterAdvertListForState( self.AdvertsList,
		self.CurrentAdvertsList or self.AdvertsList, NewState )
	if HasListChanged then
		self.Logger:Debug( "%s has changed adverts due to a game state change to %s.", self, NewState )
		-- Reset the advert list to the newly filtered version.
		self.CurrentMessageIndex = 1
		self.CurrentAdvertsList = NewAdverts
		self:StartAdverts()
	end
end

function AdvertStream:CanStart( PlayerCount )
	if self.MinPlayers and PlayerCount < self.MinPlayers then
		return false
	end

	if self.MaxPlayers and PlayerCount > self.MaxPlayers then
		return false
	end

	return true
end

function AdvertStream:OnPlayerCountChanged( PlayerCount )
	self.PlayerCount = PlayerCount

	if not self:CanStart( PlayerCount ) then
		self:Stop()
	elseif not self:IsStartedByTrigger() and ( self.MinPlayers or self.MaxPlayers ) then
		self:Start()
	end
end

function AdvertStream:QueueNextAdvert( DelayOverride )
	self:StopTimer()

	local Advert = self.CurrentAdvertsList[ self.CurrentMessageIndex ]
	local Delay = DelayOverride or Advert.DelayInSeconds

	self.Logger:Debug( "Queueing next advert for %s in %d seconds.", self, Delay )

	if Delay <= 0 then
		self:DisplayAndAdvance()
	else
		self.Timer = self.Plugin:SimpleTimer( Delay, function()
			self:DisplayAndAdvance()
		end )
	end
end

local function GetNextMessageIndex( self, MessageIndex )
	return ( MessageIndex % #self.CurrentAdvertsList ) + 1
end

function AdvertStream:GetNextAdvert()
	local MessageIndex = self.CurrentMessageIndex
	-- Back to the start, randomise the order again.
	if MessageIndex == 1 and self.RandomiseOrder then
		TableQuickShuffle( self.CurrentAdvertsList )
	end

	-- Infinite looping should be detected by the config validation, but just in case, make sure to stop checking
	-- adverts if all of them fail the player count check.
	local NumAdverts = #self.CurrentAdvertsList
	local Attempts = 1
	local Advert = self.CurrentAdvertsList[ MessageIndex ]
	while not self.IsValidForPlayerCount( Advert, self.PlayerCount ) and Attempts < NumAdverts do
		MessageIndex = GetNextMessageIndex( self, MessageIndex )
		Advert = self.CurrentAdvertsList[ MessageIndex ]
		Attempts = Attempts + 1
	end

	if self.IsValidForPlayerCount( Advert, self.PlayerCount ) then
		return Advert, MessageIndex
	end

	return nil, MessageIndex
end

function AdvertStream:DisplayAndAdvance()
	local Advert, MessageIndex = self:GetNextAdvert()
	if Advert then
		self.Plugin:DisplayAdvert( Advert )
	end

	self.CurrentMessageIndex = GetNextMessageIndex( self, MessageIndex )

	if self.CurrentMessageIndex == 1 and not self.Loop then
		self.Logger:Debug( "%s is stopping due to completing a cycle.", self )
		-- Stop after one iteration if not set to loop.
		self:Stop()
		return
	end

	self:QueueNextAdvert()
end

-- Enums error when accessing a field that is not present...
local SafeGameStateLookup = {}
for i = 1, #kGameState do
	SafeGameStateLookup[ kGameState[ i ] ] = i
end

local function IsGameState( GameStateName, GameState )
	return SafeGameStateLookup[ GameStateName ] == GameState
end

function AdvertStream.IsValidForGameState( Advert, GameState )
	if not Advert.GameState then return true end

	if IsType( Advert.GameState, "table" ) then
		for i = 1, #Advert.GameState do
			if IsGameState( Advert.GameState[ i ], GameState ) then
				return true
			end
		end
	end

	return IsGameState( Advert.GameState, GameState )
end

local IsValidForGameState = AdvertStream.IsValidForGameState
--[[
	Filters the current advert list to those that are valid for the given
	game state.

	Returns the filtered list, and a boolean to indicate if any have been filtered
	out.
]]
function AdvertStream.FilterAdvertListForState( Adverts, CurrentAdverts, GameState )
	local OutputAdverts = {}
	local HasChanged = false
	for i = 1, #Adverts do
		if IsValidForGameState( Adverts[ i ], GameState ) then
			local Index = #OutputAdverts + 1
			OutputAdverts[ Index ] = Adverts[ i ]
			if OutputAdverts[ Index ] ~= CurrentAdverts[ Index ] then
				HasChanged = true
			end
		end
	end

	if #OutputAdverts ~= #CurrentAdverts then
		HasChanged = true
	end

	return OutputAdverts, HasChanged
end

function AdvertStream.IsValidForPlayerCount( Advert, PlayerCount )
	if Advert.MinPlayers and PlayerCount < Advert.MinPlayers then
		return false
	end

	if Advert.MaxPlayers and PlayerCount > Advert.MaxPlayers then
		return false
	end

	return true
end

function AdvertStream:__tostring()
	return StringFormat(
		"AdvertStream[ %s | CurrentMessageIndex = %d | %d adverts | RequiresGameStateFiltering = %s | RandomiseOrder = %s ]",
		self.Started and "STARTED" or "STOPPED",
		self.CurrentMessageIndex,
		#self.AdvertsList,
		self.RequiresGameStateFiltering,
		self.RandomiseOrder
	)
end

return AdvertStream
