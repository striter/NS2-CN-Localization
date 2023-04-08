--[[
	Shine pregame plugin shared.
]]

local Plugin = Shine.Plugin( ... )
Plugin.NotifyPrefixColour = {
	100, 100, 255
}
Plugin.EnabledGamemodes = {
	[ "ns2" ] = true,
	[ "mvm" ] = true
}

Plugin.ScreenTextID = 2

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "StartDelay", { StartTime = "integer" }, "Client" )

	local MessageTypes = {
		Empty = {},
		Team = {
			Team = "integer (0 to 3)"
		},
		CommanderAdd = {
			Team = "integer (0 to 3)",
			TimeLeft = "integer"
		},
		Duration = {
			Duration = "integer"
		},
		MinPlayers = {
			MinPlayers = "integer"
		}
	}

	self:AddNetworkMessages( "AddTranslatedNotify", {
		[ MessageTypes.Empty ] = {
			"WaitingForBoth", "ROUND_START_ABORTED_MAP_VOTE_STARTED"
		},
		[ MessageTypes.Team ] = {
			"EmptyTeamAbort", "WaitingForTeam"
		},
		[ MessageTypes.Duration ] = {
			"EXCEEDED_TIME", "GameStartsSoon", "GameStarting"
		},
		[ MessageTypes.CommanderAdd ] = {
			"TeamHasCommander"
		},
		[ MessageTypes.MinPlayers ] = {
			"WaitingForMinPlayers"
		}
	} )
end

return Plugin
