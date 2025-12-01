#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>

#define UPGRADE_SHORTNAME "teleport"

ConVar g_hCVChance;
ConVar g_hCVMinDistance;
ConVar g_hCVMaxDistance;
ConVar g_hCVZOffset;

public Plugin myinfo = 
{
    name = "SM:RPG Upgrade > Teleport",
    author = "zombiesharp",
    description = "Teleports you away from enemies when taking damage.",
    version = SMRPG_VERSION,
    url = "https://www.wcfan.de/"
};

public void OnPluginStart()
{
    LoadTranslations("smrpg_stock_upgrades.phrases");
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
            OnClientPutInServer(i);
    }
}

public void OnPluginEnd()
{
    if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME))
        SMRPG_UnregisterUpgradeType(UPGRADE_SHORTNAME);
}

public void OnAllPluginsLoaded()
{
    OnLibraryAdded("smrpg");
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "smrpg"))
    {
        SMRPG_RegisterUpgradeType("Teleport", UPGRADE_SHORTNAME, "Teleports you away from enemies when taking damage.", 0, true, 5, 20, 15);
        SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
        
        g_hCVChance = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_teleport_chance", "0.1", "Base teleport chance per level.", _, true, 0.0, true, 1.0);
        g_hCVMinDistance = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_teleport_min_distance", "200.0", "Minimum teleport distance.", _, true, 50.0);
        g_hCVMaxDistance = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_teleport_max_distance", "800.0", "Maximum teleport distance.", _, true, 200.0);
        g_hCVZOffset = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_teleport_z_offset", "10.0", "Vertical offset when teleporting.", _, true, 0.0);
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public void SMRPG_TranslateUpgrade(int client, const char[] shortname, TranslationType type, char[] translation, int maxlen)
{
    if(type == TranslationType_Name)
        Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
    else if(type == TranslationType_Description)
    {
        char sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
        StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
        Format(translation, maxlen, "%T", sDescriptionKey, client);
    }
}

Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    if(attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || victim <= 0 || victim > MaxClients)
        return Plugin_Continue;

    if(!IsPlayerAlive(victim))
        return Plugin_Continue;

    if(!SMRPG_IsEnabled())
        return Plugin_Continue;
    
    if(!SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME))
        return Plugin_Continue;
    
    if(IsFakeClient(victim) && SMRPG_IgnoreBots())
        return Plugin_Continue;
    
    int iLevel = SMRPG_GetClientUpgradeLevel(victim, UPGRADE_SHORTNAME);
    if(iLevel <= 0)
        return Plugin_Continue;

    float chance = g_hCVChance.FloatValue * iLevel;
    if(GetRandomFloat(0.0, 1.0) > chance)
        return Plugin_Continue;
    
    if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
        return Plugin_Continue;

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(victim));
    pack.WriteCell(GetClientUserId(attacker));
    pack.WriteCell(iLevel);
    
    RequestFrame(DelayedTeleport, pack);
    
    return Plugin_Continue;
}

void DelayedTeleport(any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    
    int victim = GetClientOfUserId(pack.ReadCell());
    int attacker = GetClientOfUserId(pack.ReadCell());
    int level = pack.ReadCell();
    
    delete pack;
    
    if(!victim || !IsPlayerAlive(victim) || !attacker)
        return;
    
    float minDistance = g_hCVMinDistance.FloatValue;
    float maxDistance = g_hCVMaxDistance.FloatValue;
    float distance = minDistance + (maxDistance - minDistance) * (float(level) / 20.0);
    
    float victimPos[3], attackerPos[3], teleportPos[3];
    GetClientAbsOrigin(victim, victimPos);
    GetClientAbsOrigin(attacker, attackerPos);
    
    float awayDir[3];
    MakeVectorFromPoints(attackerPos, victimPos, awayDir);
    NormalizeVector(awayDir, awayDir);
    
    if(FindSafeTeleportPosition(victim, victimPos, awayDir, distance, teleportPos))
    {
        TeleportEntity(victim, teleportPos, NULL_VECTOR, NULL_VECTOR);
    }
}

bool FindSafeTeleportPosition(int client, float origin[3], float direction[3], float distance, float resultPos[3])
{
    for(int attempt = 0; attempt < 12; attempt++)
    {
        float randomAngle = GetRandomFloat(0.0, 360.0);
        float randomDistance = GetRandomFloat(distance * 0.7, distance * 1.3);
        
        float testDir[3];
        RotateYaw(direction, randomAngle, testDir);
        
        float testPos[3];
        testPos[0] = origin[0] + testDir[0] * randomDistance;
        testPos[1] = origin[1] + testDir[1] * randomDistance;
        testPos[2] = origin[2] + g_hCVZOffset.FloatValue;
        
        if(IsSafePosition(client, testPos))
        {
            resultPos = testPos;
            return true;
        }
    }
    
    return false;
}

bool IsSafePosition(int client, float pos[3])
{
    float clientEyePos[3];
    GetClientEyePosition(client, clientEyePos);
    
    float traceStart[3];
    traceStart[0] = clientEyePos[0];
    traceStart[1] = clientEyePos[1];
    traceStart[2] = clientEyePos[2] - 36.0;
    
    float traceEnd[3];
    traceEnd[0] = pos[0];
    traceEnd[1] = pos[1];
    traceEnd[2] = pos[2] + 72.0;
    
    TR_TraceRayFilter(traceStart, traceEnd, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter_NoPlayers, client);
    
    if(TR_DidHit())
        return false;
    
    float groundPos[3];
    if(!GetGroundPosition(pos, groundPos, 200.0))
        return false;
    
    groundPos[2] += 5.0;
    
    float mins[3] = {-16.0, -16.0, 0.0};
    float maxs[3] = {16.0, 16.0, 72.0};
    
    TR_TraceHullFilter(groundPos, groundPos, mins, maxs, MASK_PLAYERSOLID, TraceFilter_NoPlayers, client);
    
    if(TR_DidHit())
        return false;
    
    float upPos[3];
    upPos[0] = groundPos[0];
    upPos[1] = groundPos[1];
    upPos[2] = groundPos[2] + 72.0;
    
    TR_TraceHullFilter(groundPos, upPos, mins, maxs, MASK_PLAYERSOLID, TraceFilter_NoPlayers, client);
    
    return !TR_DidHit();
}

bool GetGroundPosition(float start[3], float result[3], float maxDistance)
{
    float end[3];
    end[0] = start[0];
    end[1] = start[1];
    end[2] = start[2] - maxDistance;
    
    TR_TraceRayFilter(start, end, MASK_SOLID, RayType_EndPoint, TraceFilter_World);
    
    if(TR_DidHit())
    {
        TR_GetEndPosition(result);
        return true;
    }
    
    return false;
}

void RotateYaw(float vec[3], float angle, float out[3])
{
    float radian = angle * 0.01745329251994329576923690768489;
    
    float cos = Cosine(radian);
    float sin = Sine(radian);
    
    out[0] = cos * vec[0] - sin * vec[1];
    out[1] = sin * vec[0] + cos * vec[1];
    out[2] = vec[2];
}

public bool TraceFilter_NoPlayers(int entity, int contentsMask, any data)
{
    if(entity == data)
        return false;
    
    return entity > MaxClients || entity == 0;
}

public bool TraceFilter_World(int entity, int contentsMask, any data)
{
    return entity == 0;
}