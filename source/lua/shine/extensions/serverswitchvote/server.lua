--[[
	Shine multi-server plugin.
]]

local Shine = Shine

local Notify = Shared.Message
local StringFormat = string.format
local StringMatch = string.match
local tonumber = tonumber

local Plugin = ...
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "ServerSwitchVote.json"

Plugin.DefaultConfig = {
	Servers = {
		{ Name = "My awesome server", IP = "127.0.0.1", Port = "27015", Password = "" }
	}
}

Plugin.CheckConfigTypes = true


do
	local Validator = Shine.Validator()

	local BitLShift = bit.lshift
	local select = select

	local function IPToInt( ... )
		if not ... then return nil end

		for i = 1, 4 do
			if tonumber( select( i, ... ), 10 ) > 255 then
				return -1
			end
		end

		local Byte1, Byte2, Byte3, Byte4 = ...

		-- Not using lshift for the first byte to avoid getting a signed int back.
		return tonumber( Byte1, 10 ) * 16777216 +
			BitLShift( tonumber( Byte2, 10 ), 16 ) +
			BitLShift( tonumber( Byte3, 10 ), 8 ) +
			tonumber( Byte4, 10 )
	end

	local function IsValidIPAddress( IP )
		if IP <= 0 then
			return false
		end

		-- 255.255.255.255 or higher.
		if IP >= 0xFFFFFFFF then
			return false
		end

		-- 127.x.x.x
		if IP >= 0x7F000000 and IP <= 0x7FFFFFFF then
			return false
		end

		-- 10.x.x.x
		if IP >= 0x0A000000 and IP <= 0x0AFFFFFF then
			return false
		end

		-- 172.16.0.0 - 172.31.255.255
		if IP >= 0xAC100000 and IP <= 0xAC1FFFFF then
			return false
		end

		-- 192.168.x.x
		if IP >= 0xC0A80000 and IP <= 0xC0A8FFFF then
			return false
		end

		return true
	end

	Validator:AddFieldRule( "Servers", Validator.AllValuesSatisfy(
		Validator.ValidateField( "Name", Validator.IsAnyType( { "string", "nil" } ) ),
		Validator.ValidateField( "IP", Validator.IsType( "string" ), { DeleteIfFieldInvalid = true } ),
		Validator.ValidateField( "IP", {
			Check = function( Address )
				local IP = IPToInt( StringMatch( Address, "^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$" ) )
				if IP then
					return not IsValidIPAddress( IP )
				end

				-- Hostname must contain at least 2 segments.
				if StringMatch( Address, "%." ) then
					return false
				end

				return true
			end,
			Fix = function() return nil end,
			Message = function()
				return "%s must have a valid IP address or hostname"
			end
		}, {
			DeleteIfFieldInvalid = true
		} ),
		Validator.ValidateField( "Port", Validator.IsAnyType( { "string", "number" } ), {
			DeleteIfFieldInvalid = true
		} ),
		Validator.ValidateField( "Port", Validator.IfType( "string", Validator.MatchesPattern( "^%d+$" ) ), {
			DeleteIfFieldInvalid = true
		} ),
		Validator.ValidateField( "Password", Validator.IsAnyType( { "string", "nil" } ) )
	) )

	Plugin.ConfigValidator = Validator
end

local function GetConnectIP(_index)
	local data = Plugin.Config.Servers[_index]
	return string.format("%s:%s",data.IP,data.Port)
end

function Plugin:Initialise()
	self.Enabled = true

	local function RedirClients(_serverIndex,_count,_onlySpectate)
		local clients = {}
		for Client in Shine.IterateClients() do
			
            local player = Client:GetControllingPlayer()
            if player then
                if _onlySpectate and not player:GetIsSpectator() then
                    goto continue
                end
                
                table.insert(clients,{client =Client,priority = player:GetPlayerSkill()})
                ::continue::
			end
		end

		table.sort(clients,function (a,b) return a.priority < b.priority end)
		local count = _count
		local targetIP =  GetConnectIP(_serverIndex)
		for index,data in ipairs(clients) do
			
			Server.SendNetworkMessage(data.client, "Redirect",{ ip = targetIP }, true)

			count = count - 1
			if count == 0 then
				break
			end
		end
	end
	
	
	local function RedirSpectateWithCount(_client,_serverIndex,_count)
	    RedirClients(_serverIndex,_count,1)
	end
	
    local redirSpectateWithCountCommand = self:BindCommand( "sh_redir_spec_count", "redir_spec_count", RedirSpectateWithCount )
    redirSpectateWithCountCommand:AddParam{ Type = "number", Round = true, Min = 1, Max = 6, Default=1 }
    redirSpectateWithCountCommand:AddParam{ Type = "number", Round = true, Min = 0, Max = 28, Optional = true, Default = 16 }
    redirSpectateWithCountCommand:Help( "示例: !redir_spec_count 1 20. 将20个观战(不包括场内玩家)迁移至服务器[1],排序为分数从下到上" )


	local function RedirPlayersWithCount(_client,_serverIndex,_count)
	    RedirClients(_serverIndex,_count,nil)
	end

    local redirPlayersCommand = self:BindCommand( "sh_redir_count", "redir_count", RedirPlayersWithCount )
    redirPlayersCommand:AddParam{ Type = "number", Round = true, Min = 1, Max = 6, Default=1 }
    redirPlayersCommand:AddParam{ Type = "number", Round = true, Min = 0, Max = 28, Optional = true, Default = 16 }
    redirPlayersCommand:Help( "示例: !redir_count 1 20. 将20个玩家(包括观战)迁移至服务器[1],排序为分数从下到上" )

	return true
end

function Plugin:OnNetworkingReady()
	for Client in Shine.IterateClients() do
		self:ProcessClient( Client )
	end
end

function Plugin:SendServerData( Client, ID, Data )
	self:SendNetworkMessage( Client, "ServerList", {
		Name = Data.Name and Data.Name:sub( 1, 15 ) or "No Name",
		IP = Data.IP,
		Port = tonumber( Data.Port ) or 27015,
		ID = ID
	}, true )
end

function Plugin:ProcessClient( Client )
	local Servers = self.Config.Servers
	local IsUser = Shine:GetUserData( Client )

	for i = 1, #Servers do
		local Data = Servers[ i ]
		
		if Data.UsersOnly then
			if IsUser then
				self:SendServerData( Client, i, Data )
			end
		else
			self:SendServerData( Client, i, Data )
		end
	end
end

function Plugin:ClientConnect( Client )
	if Client:GetIsVirtual() then return end
	
	self:ProcessClient( Client )
end

function Plugin:OnUserReload()
	for Client in Shine.IterateClients() do
		self:ProcessClient( Client )
	end
end