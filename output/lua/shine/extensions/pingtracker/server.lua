--[[
	Shine ping tracking plugin.
]]

local Plugin = ...

local Abs = math.abs
local Ceil = math.ceil
local Floor = math.floor
local SharedGetTime = Shared.GetTime
local StringFormat = string.format
local TableAverage = table.Average

local UnorderedMap = Shine.UnorderedMap
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "PingTracker.json"

Plugin.DefaultConfig = {
	MaxPing = 200, -- Maximum allowed average ping.
	MaxJitter = 50, -- Maximum allowed average jitter.
	Warn = true, -- Should players be warned first?
	MeasureInterval = 1, -- Time in seconds between measurements.
	CheckInterval = 60 -- Interval to check averages and warn/kick.
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	self.Config.CheckInterval = Floor( self.Config.CheckInterval )

	self.Players = UnorderedMap()

	if self.Enabled ~= nil then
		local Clients, Count = Shine.GetAllClients()
		for i = 1, Count do
			local Client = Clients[ i ]
			self:ClientConnect( Client )
		end
	end

	self.Enabled = true

	return true
end

function Plugin:ClientConnect( Client )
	if not Client or Client:GetIsVirtual() then return end

	local Time = SharedGetTime()
	local FirstCheck = Time + 30
	local NextAverage = FirstCheck + self.Config.CheckInterval

	self.Players:Add( Client, {
		NextCheck = FirstCheck,
		NextAverage = NextAverage,
		TimesOver = 0,
		Pings = {},
		DeltaPings = {}
	} )
end

function Plugin:ClientDisconnect( Client )
	self.Players:Remove( Client )
end

function Plugin:WarnOrKickClient( Client, Data, AveragePing, AverageJitter, Reason, Message, Args )
	if Data.TimesOver == 0 and self.Config.Warn then
		self:SendTranslatedNotify( Client, Message, Args )
		self:NotifyTranslated( Client, "KICK_WARNING" )
		return true
	end

	Shine:LogString( StringFormat(
		"[PingTracker] Kicked client %s. Average ping: %.2f. Average jitter: %.2f.",
		Shine.GetClientInfo( Client ), AveragePing, AverageJitter ) )

	Client.DisconnectReason = Reason
	Server.DisconnectClient( Client, Reason )

	return false
end

function Plugin:CheckClient( Client, Data, Time )
	if Data.NextCheck > Time then return end
	if Shine:HasAccess( Client, "sh_pingimmune" ) then return end

	Data.NextCheck = Time + self.Config.MeasureInterval

	local Pings = Data.Pings
	local DeltaPings = Data.DeltaPings

	local Ping = Client:GetPing()
	local LastPing = Pings[ #Pings ]

	if LastPing then
		DeltaPings[ #DeltaPings + 1 ] = Abs( Ping - LastPing )
	end

	Pings[ #Pings + 1 ] = Ping

	if Data.NextAverage > Time then return end

	local AveragePing = TableAverage( Pings )
	local AverageJitter = TableAverage( DeltaPings )

	local ShouldIncrease

	if AveragePing > self.Config.MaxPing then
		ShouldIncrease = self:WarnOrKickClient( Client, Data, AveragePing, AverageJitter,
			"Ping too high", "PING_TOO_HIGH", {
				Amount = Ceil( AveragePing )
			} )

		if not ShouldIncrease then
			return
		end
	end

	if AverageJitter > self.Config.MaxJitter then
		ShouldIncrease = self:WarnOrKickClient( Client, Data, AveragePing, AverageJitter,
			"Ping jitter too high", "JITTER_TOO_HIGH", {
				Amount = Ceil( AverageJitter )
			} )

		if not ShouldIncrease then
			return
		end
	end

	if ShouldIncrease then
		Data.TimesOver = 1
	end

	Data.Pings = {}
	Data.DeltaPings = {}

	Data.NextAverage = Time + self.Config.CheckInterval
end

function Plugin:Think()
	local Time = SharedGetTime()

	for Client, Data in self.Players:Iterate() do
		self:CheckClient( Client, Data, Time )
	end
end

function Plugin:Cleanup()
	self.Players = nil
	self.BaseClass.Cleanup( self )
end
