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

public Plugin myinfo = 
{
    name = "SM:RPG Upgrade > Teleport",
    author = "+SyntX",
    description = "Teleports you away from enemies when taking damage.",
    version = SMRPG_VERSION,
    url = "https://www.wcfan.de/"
};

public void OnPluginStart()
{
    LoadTranslations("smrpg_stock_upgrades.phrases");
    
    // Account for late loading
    for(int i=1;i<=MaxClients;i++)
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
    // Register this upgrade in SM:RPG
    if(StrEqual(name, "smrpg"))
    {
        // Register the upgrade type.
        SMRPG_RegisterUpgradeType("Teleport", UPGRADE_SHORTNAME, "Teleports you away from enemies when taking damage.", 0, true, 5, 20, 15);

        // Register translation callback
        SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
        
        // Create convars
        g_hCVChance = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_teleport_chance", "0.1", "The chance that the player teleports when taking damage (multiplied by level).", _, true, 0.0, true, 1.0);
        g_hCVMinDistance = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_teleport_min_distance", "200.0", "Minimum teleport distance from enemies.", _, true, 50.0);
        g_hCVMaxDistance = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_teleport_max_distance", "800.0", "Maximum teleport distance from enemies (at max level).", _, true, 200.0);
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

/**
 * SM:RPG Upgrade callbacks
 */

// The core wants to display your upgrade somewhere. Translate it into the clients language!
public void SMRPG_TranslateUpgrade(int client, const char[] shortname, TranslationType type, char[] translation, int maxlen)
{
    // Easy pattern is to use the shortname of your upgrade in the translation file
    if(type == TranslationType_Name)
        Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
    // And "shortname description" as phrase in the translation file for the description.
    else if(type == TranslationType_Description)
    {
        char sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
        StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
        Format(translation, maxlen, "%T", sDescriptionKey, client);
    }
}

void Hook_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom)
{
    // Validate attacker and victim
    if(attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || victim <= 0 || victim > MaxClients)
        return;

    if(!IsPlayerAlive(victim))
        return;

    // SM:RPG is disabled?
    if(!SMRPG_IsEnabled())
        return;
    
    // The upgrade is disabled completely?
    if(!SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME))
        return;
    
    // Are bots allowed to use this upgrade?
    if(IsFakeClient(victim) && SMRPG_IgnoreBots())
        return;
    
    // Player didn't buy this upgrade yet.
    int iLevel = SMRPG_GetClientUpgradeLevel(victim, UPGRADE_SHORTNAME);
    if(iLevel <= 0)
        return;

    // Check if this attack allows the victim to teleport
    float chance = g_hCVChance.FloatValue * iLevel;
    if(GetRandomFloat(0.0, 1.0) > chance)
        return;
    
    if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
        return;

    // Calculate teleport distance based on level
    float minDistance = g_hCVMinDistance.FloatValue;
    float maxDistance = g_hCVMaxDistance.FloatValue;
    float distance = minDistance + (maxDistance - minDistance) * (float(iLevel) / 20.0);
    
    // Find a safe position away from the attacker
    float victimPos[3], attackerPos[3], teleportPos[3];
    GetClientAbsOrigin(victim, victimPos);
    GetClientAbsOrigin(attacker, attackerPos);
    
    // Calculate direction away from attacker
    MakeVectorFromPoints(attackerPos, victimPos, teleportPos);
    NormalizeVector(teleportPos, teleportPos);
    
    // Scale by distance
    ScaleVector(teleportPos, distance);
    
    // Add to victim position
    AddVectors(victimPos, teleportPos, teleportPos);
    
    // Try to find a valid position on the ground
    if(!FindValidPosition(teleportPos))
    {
        // If we can't find a valid position, try a simpler approach
        teleportPos[2] += 20.0; // Lift slightly off ground
    }
    
    // Teleport the player
    TeleportEntity(victim, teleportPos, NULL_VECTOR, NULL_VECTOR);
}

bool FindValidPosition(float pos[3])
{
    float endPos[3];
    endPos[0] = pos[0];
    endPos[1] = pos[1];
    endPos[2] = pos[2] - 100.0;
    
    Handle trace = TR_TraceRayFilterEx(pos, endPos, MASK_PLAYERSOLID_BRUSHONLY, RayType_EndPoint, TraceFilter);
    if(TR_DidHit(trace))
    {
        TR_GetEndPosition(endPos, trace);
        CloseHandle(trace);
        
        endPos[2] += 20.0;
        pos[0] = endPos[0];
        pos[1] = endPos[1];
        pos[2] = endPos[2];
        return true;
    }
    
    CloseHandle(trace);
    return false;
}

public bool TraceFilter(int entity, int contentsMask)
{
    return entity > MaxClients || entity == 0;
}