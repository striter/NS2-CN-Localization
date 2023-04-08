local Plugin = ...

Plugin.Version = "1.0"
Plugin.PrintName = "communityrank"
Plugin.HasConfig = true
Plugin.ConfigName = "CommunityRank.json"
Plugin.DefaultConfig = {
    EndRoundValidation = true,
    EndRoundValidationTime = 300,
    EndRoundValidationPlayerCount = 16,
    ["UserData"] = {
        ["55022511"] = {
            rank = -2000,
            fakeBot = true,
            emblem = 0,
            seedingDay = 0,
        }
    },
    SeedingDay = 1,
    SeedingActivePlayer = 12,
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

local kEloDefaultConstant = 20
local kEloTierConstant =
{
    [0] = 100,
    [1] = 75,
    [2] = 60,
    [3] = 50,
    [4] = 35,
    [5] = 20,
    [6] = 15,
    [7] = 10,
}

do
	local Validator = Shine.Validator()
	Validator:AddFieldRule( "UserData",  Validator.IsType( "table", {} ))
    Validator:AddFieldRule( "SeedingDay",  Validator.IsType( "number", -1 ))
    Validator:AddFieldRule( "SeedingActivePlayer",  Validator.IsType( "number", 12 ))
    Validator:AddFieldRule( "EndRoundValidation",  Validator.IsType( "boolean", true ))
    Validator:AddFieldRule( "EndRoundValidationTime",  Validator.IsType( "number", 300 ))
    Validator:AddFieldRule( "EndRoundValidationPlayerCount",  Validator.IsType( "number", 16 ))
	Plugin.ConfigValidator = Validator
end

function Plugin:Initialise()
    self.MemberInfos = { }
    self:CreateMessageCommands()
	return true
end

local function ReadPersistent(self)
    -- Shared.Message("[CNCR] Read Persistent:")
    for k,v in pairs(self.Config.UserData) do
        -- Shared.Message(k .. ":" .. tostring(v))
        self.MemberInfos[tonumber(k)] = v
    end
end

local function SavePersistent(self)
    -- Shared.Message("[CNCR] Save Persistent:")
    for k,v in pairs(self.MemberInfos) do
        self.Config.UserData[tostring(k)] = v
    end
    self:SaveConfig()
end

local function GetPlayerData(self,steamId)
    if not self.MemberInfos[steamId] then
        self.MemberInfos[steamId] = { }
    end
    
    return self.MemberInfos[steamId]
end

local function RankPlayerDelta(self,_steamId,_delta)
    local data = GetPlayerData(self,_steamId)
    local rank = data.rank or 0
    rank = rank + _delta
    data.rank = rank
    
    local target = Shine.GetClientByNS2ID(_steamId)
    if target then 
        local player = target:GetControllingPlayer()
        data.rank = math.max(rank, -player.skill)
        player:SetPlayerExtraData(data)
    end
end


local eloEnable = { "ns2","NS2.0","NS1.0","siege+++"  }
local function EndGameElo(self)
    local gameMode = Shine.GetGamemode()
    if not table.contains(eloEnable,gameMode) then return end

    if not self.Config.EndRoundValidation then return end

    local lastRoundData = CHUDGetLastRoundStats();
    if not lastRoundData then
        Shared.Message("[CNCR] ERROR Option 'savestats' not enabled ")
        return
    end

    local winningTeam = lastRoundData.RoundInfo.winningTeam
    local gameLength = lastRoundData.RoundInfo.roundLength
    local team1AverageSkill = 0
    local team2AverageSkill = 0

    local team1Table = {}
    local team2Table = {}
    local function PopTeamEntry(_teamTable,_steamId,_teamEntry,_playerSkill)
        if not _teamEntry.timePlayed or _teamEntry.timePlayed <=0 then
            return 0
        end
        local playTimeNormalized = _teamEntry.timePlayed / gameLength
        table.insert(_teamTable, {steamId = _steamId,playTimeNormalized = playTimeNormalized ,score = _teamEntry.score,hiveSkill = _playerSkill })
        return  _playerSkill * playTimeNormalized
        -- Shared.Message(string.format("%i %i %i",_steamId,_teamEntry.timePlayed,_teamEntry.score))
    end

    local playerCount = 0
    for steamId , playerStat in pairs( lastRoundData.PlayerStats ) do
        team1AverageSkill = team1AverageSkill + PopTeamEntry(team1Table,steamId,playerStat[1],playerStat.hiveSkill)
        team2AverageSkill = team2AverageSkill + PopTeamEntry(team2Table,steamId,playerStat[2],playerStat.hiveSkill)
        playerCount = playerCount + 1
    end

    if gameLength < self.Config.EndRoundValidationTime or playerCount < self.Config.EndRoundValidationPlayerCount then
        Shared.Message(string.format("[CNCR] End Game Result Restricted"))
        return
    end
    Shared.Message(string.format("[CNCR] End Game Resulting|Mode:%s Length:%i Players:%i WinTeam: %s|", gameMode , gameLength,playerCount , winningTeam))

    local function RankCompare(a,b) return a.score > b.score end
    table.sort(team1Table,RankCompare)
    table.sort(team2Table,RankCompare)

    local function ApplyRankTable(_rankTable, _teamTable, _delta)
        for _,data in ipairs(_teamTable) do
            local steamId = data.steamId

            if not _rankTable[steamId] then
                _rankTable[steamId] = 0
            end

            local tier,_ = GetPlayerSkillTier(data.hiveSkill)

            --its ELO dude
            local eloConstant = kEloTierConstant[tier] or kEloDefaultConstant
            local Edelta = eloConstant * _delta

            _rankTable[steamId] = _rankTable[steamId] + math.floor(Edelta * data.playTimeNormalized)
            --Shared.Message(string.format("ID:%s T%s K:%s ES-EA:%s", steamId,tier,eloConstant,_delta))
        end
    end

    local team1S, team2S
    if winningTeam == kMarineTeamType then
        team1S = 1; team2S = 0;
    elseif winningTeam == kAlienTeamType then
        team1S = 0; team2S = 1;
    else
        team1S = .5; team2S = .5;
    end

    local rankTable = {}
    ApplyRankTable(rankTable,team1Table,team1S - 1.0 / (1 + math.pow(10,(team2AverageSkill - team1AverageSkill)/400)))
    ApplyRankTable(rankTable,team2Table,team2S - 1.0 / (1 + math.pow(10,(team1AverageSkill - team2AverageSkill)/400)))

    -- Shared.Message("[CNCR] Result")

    for steamId, rankOffset in pairs(rankTable) do
        if rankOffset ~= 0 then
            RankPlayerDelta(self,steamId,rankOffset)
        end
         --Shared.Message(string.format("%i|%d",steamId, rankOffset))
    end

end

local kSeedingPrewarmColor = { 235, 152, 78 }
local function StartGameSeeding(self)
    local tmpDate = os.date("*t", Shared.GetSystemTime())
    if tmpDate.hour < 4 or self.Config.SeedingDay == tmpDate.day then return end
    
    for client in Shine.IterateClients() do
        Shine:NotifyDualColour( client,
                kSeedingPrewarmColor[1], kSeedingPrewarmColor[2], kSeedingPrewarmColor[3],"[战局预热]",
                255, 255, 255,string.format("当前为预热局,当游戏结束时[人数>%s]后,场内所有玩家将获得该服务器当天的预热特权.", self.Config.SeedingActivePlayer),true, data )
    end
end

local function EndGameSeeding(self)
    local tmpDate =  os.date("*t", Shared.GetSystemTime())
    local currentDay = tmpDate.day
    if tmpDate.hour < 4 or self.Config.SeedingDay == currentDay then return end
    
    if Shine.GetHumanPlayerCount() < self.Config.SeedingActivePlayer then return end
    
    self.Config.SeedingDay = currentDay
    for client in Shine.IterateClients() do
        data = GetPlayerData(self,client:GetUserId())
        data.seedingDay = currentDay
        client:GetControllingPlayer():SetPlayerExtraData(data)
        Shine:NotifyDualColour( client,
                kSeedingPrewarmColor[1], kSeedingPrewarmColor[2], kSeedingPrewarmColor[3],"[战局预热]",
                255, 255, 255,"以达到预热预期,现在您于该服务器当天享有预热徽章,感谢您的付出!",true, data )
    end
end

function Plugin:OnFirstThink()
    ReadPersistent(self)

    function Plugin:SetGameState( Gamerules, State, OldState )
        if State == kGameState.Countdown then
            StartGameSeeding(self)
        end
    end
    
    function Plugin:OnEndGame(_winningTeam)
        EndGameElo(self)
        EndGameSeeding(self)
        SavePersistent(self)
    end
    Shine.Hook.SetupClassHook("NS2Gamerules", "EndGame", "OnEndGame", "PassivePost")
end

function Plugin:ResetState()
    table.empty(self.MemberInfos)
    ReadPersistent(self)
end

function Plugin:Cleanup()
    table.empty(self.MemberInfos)
    return self.BaseClass.Cleanup( self )
end


function Plugin:CreateMessageCommands()
    local function AdminRankPlayer( _client, _id, _rank )
        local target = Shine.GetClientByNS2ID(_id)
        if not target then 
            return 
        end

        local player = target:GetControllingPlayer()
        local preRank = player.skill

        local rank = _rank - preRank
        data = GetPlayerData(self,_id)
        data.rank = rank
        target:GetControllingPlayer():SetPlayerExtraData(data)
    end

    local setCommand = self:BindCommand( "sh_rank_set", "rank_set", AdminRankPlayer )
    setCommand:AddParam{ Type = "steamid" }
    setCommand:AddParam{ Type = "number", Round = true, Min = 0, Max = 9999999, Optional = true, Default = 0 }
    setCommand:Help( "设置ID对应玩家的社区段位." )

    local function AdminRankReset( _client, _id )
        local target = Shine.GetClientByNS2ID(_id)
        if not target then 
            return 
        end

        local data = GetPlayerData(self,_id)
        data.rank = 0
        target:GetControllingPlayer():SetPlayerExtraData(data)
    end

    local resetCommand = self:BindCommand( "sh_rank_reset", "rank_reset", AdminRankReset )
    resetCommand:AddParam{ Type = "steamid" }
    resetCommand:Help( "重置玩家的段位(还原至NS2段位)." )

    local function AdminRankPlayerDelta( _client, _id, _offset )
        local target = Shine.GetClientByNS2ID(_id)
        if not target then 
            return 
        end

        RankPlayerDelta(self,_id,_offset)
    end
    local deltaCommand = self:BindCommand( "sh_rank_delta", "rank_delta", AdminRankPlayerDelta )
    deltaCommand:AddParam{ Type = "steamid" }
    deltaCommand:AddParam{ Type = "number", Round = true, Min = -5000, Max = 5000, Optional = true, Default = 0 }
    deltaCommand:Help( "增减ID对应玩家的社区段位." )

--BOT
    local function FakeBotSwitchID(_client,_id)
        local target = Shine.GetClientByNS2ID(_id)
        if not target then 
            return 
        end

        local data = GetPlayerData(self,target:GetUserId())
        data.fakeBot = not data.fakeBot
        target:GetControllingPlayer():SetPlayerExtraData(data)
    end
    local botCommand = self:BindCommand( "sh_fakebot_set", "fakebot_set", FakeBotSwitchID )
    botCommand:AddParam{ Type = "steamid" }
    botCommand:Help( "切换目标玩家的假BOT设置." )
    
    local function FakeBotSwitch(_client)
        FakeBotSwitchID(_client,_client:GetUserId())
    end

    local botSwitchCommand = self:BindCommand( "sh_fakebot", "fakebot", FakeBotSwitch )
    botSwitchCommand:Help( "假扮成BOT." )

--Emblem
    local function EmblemSetID(_client, _id, _emblem)
        local target = Shine.GetClientByNS2ID(_id)
        if not target then return  end

        local data = GetPlayerData(self,target:GetUserId())
        data.emblem = _emblem
        target:GetControllingPlayer():SetPlayerExtraData(data)
    end
    local function EmblemSet(_client, _emblem)
        EmblemSetID(_client,_client:GetUserId(),_emblem)
    end

    local function DynamicEmblemSet(_client, _emblem)
        EmblemSetID(_client,_client:GetUserId(),-_emblem)
    end

    local emblemSetCommand = self:BindCommand( "sh_emblem_set", "emblem_set", EmblemSetID)
    emblemSetCommand:AddParam{ Type = "steamid" }
    emblemSetCommand:AddParam{ Type = "number", Round = true, Min = -20, Max = 20, Optional = true, Default = 0 }
    emblemSetCommand:Help( "切换目标玩家的计分板底图(0为默认,正数为静态,负数为动态)." )

    local emblemCommand = self:BindCommand( "sh_emblem", "emblem", EmblemSet)
    emblemCommand:AddParam{ Type = "number", Round = true, Min = 0, Max = 20, Optional = true, Default = 0 }
    emblemCommand:Help( "切换自己的计分板底图(0为使用默认)." )
    
    local dynamicEmblemCommand = self:BindCommand( "sh_emblem_dynamic", "emblem_dynamic", DynamicEmblemSet)
    dynamicEmblemCommand:AddParam{ Type = "number", Round = true, Min = 0, Max = 20, Optional = true, Default = 0 }
    dynamicEmblemCommand:Help( "切换自己的动态计分板底图(0为使用默认)." )
end

function Plugin:GetUserGroup(Client)
	local userData = Shine:GetUserData(Client)

    local groupName = userData and userData.Group or nil
    local Group = groupName and Shine:GetGroupData(groupName) or Shine:GetDefaultGroup()
    
	return groupName and groupName or "RANK_DEFAULT" , Group
end

function Plugin:ClientConnect( _client )
    local clientID = _client:GetUserId()
    if clientID == 0 then return end
    
    --Jeez wtf
    local groupName,groupData = self:GetUserGroup(_client)

    local player = _client:GetControllingPlayer()
    player:SetGroup(groupName)
    player:SetPlayerExtraData(GetPlayerData(self,clientID))
    
    Shine.SendNetworkMessage(_client,"Shine_CommunityTier" ,{Tier = groupData.Tier or 0},true)
    --Shared.Message("[CNCR] Client Rank:" .. tostring(clientID))
end