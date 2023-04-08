--[[
	Shine surrender vote plugin.
]]

local Shine = Shine

local GetClientForPlayer = Shine.GetClientForPlayer
local SharedTime = Shared.GetTime
local StringFormat = string.format

local Ceil = math.ceil
local Clamp = math.Clamp
local Floor = math.floor
local Max = math.max
local Random = math.random

local Plugin = ...
Plugin.Version = "1.6"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteSurrender.json"

Plugin.DefaultConfig = {
	-- Fraction of the team needing to vote in order to surrender.
	FractionOfPlayersNeeded = 0.75,
	-- Fraction of the team needing to vote in the early game to surrender (during VoteDelayInMinutes time).
	FractionOfPlayersNeededInEarlyGame = 0,
	-- Time after round start before surrender vote is available/uses normal percentage (in minutes)
	VoteDelayInMinutes = 10,
	-- Min players needed for voting to be enabled.
	MinPlayers = 6,
	-- How long after no votes before the vote should reset?
	VoteTimeoutInSeconds = 120,
	-- Is a team allowed to surrender with multiple bases
	AllowVoteWithMultipleBases = true,
	-- Skip the in-game surrender sequence?
	SkipSequence = false,
	-- How much health [0, 1] the final command structure must have greater-equal to allow a vote.
	LastCommandStructureMinHealthFraction = 0
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.VoteApplicableToSpectators = false

Shine.LoadPluginModule( "vote.lua", Plugin )

Plugin.ConfigMigrationSteps = {
	{
		VersionTo = "1.5",
		Apply = Shine.Migrator()
			:RemoveField( { "VoteSettings", "ConsiderSpectatorsInVotes" } )
	},
	{
		VersionTo = "1.6",
		Apply = Shine.Migrator()
			:RenameField( "PercentNeeded", "FractionOfPlayersNeeded" )
			:RenameField( "PercentNeededInEarlyGame", "FractionOfPlayersNeededInEarlyGame" )
			:RenameField( "VoteDelay", "VoteDelayInMinutes" )
			:RenameField( "VoteTimeout", "VoteTimeoutInSeconds" )
			:RenameField( "LastCommandStructureMinHealthPercent", "LastCommandStructureMinHealthFraction" )
	}
}

do
	local Validator = Shine.Validator()

	Validator:AddFieldRule( "FractionOfPlayersNeeded", Validator.Clamp( 0, 1 ) )
	Validator:AddFieldRule( "FractionOfPlayersNeededInEarlyGame", Validator.Clamp( 0, 1 ) )
	Validator:AddFieldRule( "LastCommandStructureMinHealthFraction", Validator.Clamp( 0, 1 ) )

	Plugin.ConfigValidator = Validator
end

function Plugin:Initialise()
	self.Votes = {
		Shine:CreateVote( function() return self:GetVotesNeeded( 1 ) end,
			self:WrapCallback( function() self:Surrender( 1 ) end ) ),

		Shine:CreateVote( function() return self:GetVotesNeeded( 2 ) end,
			self:WrapCallback( function() self:Surrender( 2 ) end ) )
	}
	for i = 1, 2 do
		self:SetupVoteTimeout( self.Votes[ i ], self.Config.VoteTimeoutInSeconds, "VoteTimeout"..i )
	end

	self.NextVote = 0
	self.dt.ConcedeTime = self.Config.VoteDelayInMinutes

	self:CreateCommands()

	self.Enabled = true

	return true
end

--[[
	Runs when the game state is set.
	If a round has started, we set the next vote time to current time + delay.
]]
function Plugin:SetGameState( Gamerules, State, OldState )
	if State >= kGameState.Started then
		-- Game has started/ended, reset the votes.
		for i = 1, 2 do
			self.Votes[ i ]:Reset()
		end
	end

	if State == kGameState.Started then
		self.NextVote = SharedTime() + ( self.Config.VoteDelayInMinutes * 60 )
	end
end

function Plugin:GetTeamPlayerCount( Team )
	local Gamerules = GetGamerules()
	local TeamData = Gamerules[ Team == 1 and "team1" or "team2" ]

	local Count = 0
	local function CountPlayers( Player )
		local Client = GetClientForPlayer( Player )
		if Shine:IsValidClient( Client ) and self:IsValidVoter( Client ) then
			Count = Count + 1
		end
	end
	TeamData:ForEachPlayer( CountPlayers )

	return Count
end

function Plugin:GetVotesNeeded( Team )
	local TeamCount = self:GetTeamPlayerCount( Team )
	local IsEarlyGame = self.NextVote > SharedTime()
	local FractionOfPlayersNeeded = IsEarlyGame and self.Config.FractionOfPlayersNeededInEarlyGame
		or self.Config.FractionOfPlayersNeeded

	return Max( 1, Ceil( TeamCount * FractionOfPlayersNeeded ) )
end

--[[
	Checks whether the given team has more than one command structure when the vote is set
	to not allow surrendering with more than one.
]]
function Plugin:HasTooManyTechPoints( Gamerules, Team )
	return not self.Config.AllowVoteWithMultipleBases and Gamerules:GetTeam( Team ):GetNumCapturedTechPoints() > 1
end

--[[
	Checks whether the given team has a single command structure whose health is below the
	minimum percentage permitted to surrender.
]]
function Plugin:HasCommandStructureAtTooLowHP( Team )
	local CommandStructures = GetEntitiesForTeam( "CommandStructure", Team )
	if #CommandStructures ~= 1 then return false end

	local MinFraction = self.Config.LastCommandStructureMinHealthFraction
	local CommandStructure = CommandStructures[ 1 ]

	return CommandStructure:GetHealthFraction() < MinFraction
end

--[[
	Make sure we only vote when a round has started and
	the team data pass the config params
]]
function Plugin:CanStartVote( Team )
	local Gamerules = GetGamerules()
	if not Gamerules then return false end

	local State = Gamerules:GetGameState()
	if State ~= kGameState.Started then return false end

	if self:HasTooManyTechPoints( Gamerules, Team ) then return false end
	if self:HasCommandStructureAtTooLowHP( Team ) then return false end

	return self:GetTeamPlayerCount( Team ) >= self.Config.MinPlayers
		and ( self.NextVote <= SharedTime() or self.Config.FractionOfPlayersNeededInEarlyGame > 0 )
end

function Plugin:AddVote( Client, Team )
	if not Client then return end

	-- Would be a fun bug...
	if Team ~= 1 and Team ~= 2 then return false, "spectators can't surrender!" end

	if not self:CanStartVote( Team ) then return false, "can't start" end
	local Success, Err = self.Votes[ Team ]:AddVote( Client )

	if not Success then return false, Err end

	return true
end

--[[
	Remove a client's vote if they disconnect!
]]
function Plugin:ClientDisconnect( Client )
	for i = 1, 2 do
		self.Votes[ i ]:ClientDisconnect( Client )
	end
end

--[[
	Remove a client's vote if they leave the team!
]]
function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
	if not Player then return end

	local Client = GetClientForPlayer( Player )
	if not Client then return end

	local Vote = self.Votes[ OldTeam ]
	if Vote then
		Vote:RemoveVote( Client )
	end
end

--[[
	Makes the given team surrender.
]]
function Plugin:Surrender( Team )
	local Gamerules = GetGamerules()
	if not Gamerules or Gamerules:GetGameState() ~= kGameState.Started then return end

	for i = 1, 2 do
		self.Votes[ i ]:Reset()
	end

	Shine.SendNetworkMessage( "TeamConceded", { teamNumber = Team } )

	local WinningTeam = Gamerules:GetTeam( Team == 1 and 2 or 1 )
	local SurrenderingTeam = Gamerules:GetTeam( Team )

	-- For the surrender sequence we have to set this flag
	if not self.Config.SkipSequence then
		SurrenderingTeam.conceded = true
	end

	Gamerules:EndGame( WinningTeam )

	self.Surrendered = true
	self:SimpleTimer( 0, function()
		self.Surrendered = false
	end )
end

--[[
	Overrides the concede vote button in the NS2 request menu.
]]
function Plugin:CastVoteByPlayer( Gamerules, ID, Player )
	if not Player then return end
	if ID ~= kTechId.VoteConcedeRound then return end

	local Client = Player:GetClient()
	if not Client then return true end

	local Team = Player:GetTeam():GetTeamNumber()
	if not self.Votes[ Team ] then return true end

	local Votes = self.Votes[ Team ]:GetVotes()
	local Success, Err = self:AddVote( Client, Team )

	-- We failed to add the vote, but we should still stop it going through NS2's system...
	if not Success then return true end
	-- We've surrendered, no need to say another player's voted.
	if self.Surrendered then return true end

	local VotesNeeded = self.Votes[ Team ]:GetVotesNeeded()

	self:AnnounceVote( Player, Team, VotesNeeded )

	return true
end

function Plugin:AnnounceVote( Player, Team, VotesNeeded )
	local Players = GetEntitiesForTeam( "Player", Team )

	local NWMessage = {
		voterName = Player:GetName(),
		votesMoreNeeded = VotesNeeded
	}

	for i = 1, #Players do
		local Ply = Players[ i ]

		if Ply then
			-- Use NS2's built in concede, it's localised.
			Shine.SendNetworkMessage( Ply, "VoteConcedeCast", NWMessage, true )
		end
	end
end

function Plugin:CreateCommands()
	local function VoteSurrender( Client )
		if not Client then return end

		local Player = Client:GetControllingPlayer()
		if not Player then return end

		local Team = Player:GetTeamNumber()

		if not self.Votes[ Team ] then
			self:NotifyTranslatedError( Player, "ERROR_WRONG_TEAM" )

			return
		end

		local Success, Err = self:AddVote( Client, Team )

		if Success then
			if self.Surrendered then return end

			local VotesNeeded = self.Votes[ Team ]:GetVotesNeeded()

			return self:AnnounceVote( Player, Team, VotesNeeded )
		end

		if Err == "already voted" then
			self:NotifyTranslatedError( Player, "ERROR_ALREADY_VOTED" )
		else
			self:NotifyTranslatedError( Player, "ERROR_ROUND_TIME" )
		end
	end
	local VoteSurrenderCommand = self:BindCommand( "sh_votesurrender",
		{ "surrender", "votesurrender", "surrendervote" }, VoteSurrender, true )
	VoteSurrenderCommand:Help( "Votes to surrender the round." )
end
