#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "bloodritual"

ConVar g_hCVCooldown;
ConVar g_hCVHealthCost;
ConVar g_hCVRadius;
ConVar g_hCVDuration;
ConVar g_hCVDamagePerTick;
ConVar g_hCVHealPercentage;

Handle g_hBloodRitualTimer[MAXPLAYERS+1];
Handle g_hBloodPoolTimer[MAXPLAYERS+1];
bool g_bBloodPoolActive[MAXPLAYERS+1];
float g_fBloodPoolPosition[MAXPLAYERS+1][3];
int g_iBloodPoolOwner[MAXPLAYERS+1];

public Plugin myinfo = 
{
    name = "SM:RPG Upgrade > Blood Ritual",
    author = "+SyntX",
    description = "Sacrifice health to create a blood pool that damages enemies and heals you.",
    version = SMRPG_VERSION,
    url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
    LoadTranslations("smrpg_stock_upgrades.phrases");
    
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
    if(StrEqual(name, "smrpg"))
    {
        SMRPG_RegisterUpgradeType("Blood Ritual", UPGRADE_SHORTNAME, "Sacrifice health to create a damaging blood pool that heals you.", 8, true, 10, 20, 15);
        SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
        SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
        
        g_hCVCooldown = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_bloodritual_cooldown", "50.0", "Cooldown time in seconds", 0, true, 1.0);
        g_hCVHealthCost = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_bloodritual_healthcost", "30.0", "Health cost to activate blood ritual", 0, true, 1.0);
        g_hCVRadius = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_bloodritual_radius", "250.0", "Radius of blood pool", 0, true, 50.0);
        g_hCVDuration = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_bloodritual_duration", "8.0", "Duration of blood pool in seconds", 0, true, 1.0);
        g_hCVDamagePerTick = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_bloodritual_damage", "8.0", "Damage per tick to enemies", 0, true, 1.0);
        g_hCVHealPercentage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_bloodritual_heal", "0.50", "Percentage of damage dealt converted to healing (0.50 = 50%)", 0, true, 0.0, true, 1.0);
    }
}

public void OnClientPutInServer(int client)
{
    g_hBloodRitualTimer[client] = null;
    g_hBloodPoolTimer[client] = null;
    g_bBloodPoolActive[client] = false;
    g_iBloodPoolOwner[client] = 0;
}

public void OnClientDisconnect(int client)
{
    if(g_hBloodRitualTimer[client] != null)
    {
        KillTimer(g_hBloodRitualTimer[client]);
        g_hBloodRitualTimer[client] = null;
    }
    if(g_hBloodPoolTimer[client] != null)
    {
        KillTimer(g_hBloodPoolTimer[client]);
        g_hBloodPoolTimer[client] = null;
    }
    g_bBloodPoolActive[client] = false;
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

public void SMRPG_BuySell(int client, UpgradeQueryType type)
{
    if(type == UpgradeQueryType_Sell)
    {
        if(g_bBloodPoolActive[client])
        {
            g_bBloodPoolActive[client] = false;
        }
    }
}

public void SMRPG_UpgradeActivated(int client, const char[] shortname)
{
    if(!StrEqual(shortname, UPGRADE_SHORTNAME))
        return;
    
    if(g_hBloodRitualTimer[client] != null)
    {
        return;
    }
    
    if(!IsPlayerAlive(client))
    {
        return;
    }
    
    float healthCost = g_hCVHealthCost.FloatValue;
    int currentHealth = GetClientHealth(client);
    
    if(currentHealth <= healthCost)
    {
        return;
    }
    
    if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
        return;
    
    int newHealth = currentHealth - RoundToFloor(healthCost);
    SetEntityHealth(client, newHealth);
    
    CreateBloodPool(client);
    
    float cooldown = g_hCVCooldown.FloatValue;
    g_hBloodRitualTimer[client] = CreateTimer(cooldown, BloodRitualCooldown_Timer, client);
}

void CreateBloodPool(int client)
{
    int level = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
    float radius = g_hCVRadius.FloatValue + (level * 5.0);
    float duration = g_hCVDuration.FloatValue;
    
    g_bBloodPoolActive[client] = true;
    GetClientAbsOrigin(client, g_fBloodPoolPosition[client]);
    g_iBloodPoolOwner[client] = client;
    
    CreateBloodPoolVisuals(client, radius, duration);
    
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteFloat(radius);
    g_hBloodPoolTimer[client] = CreateTimer(1.0, BloodPoolDamage_Timer, pack, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
    
    CreateTimer(duration, EndBloodPool_Timer, GetClientUserId(client));
    
    EmitAmbientSound("player/heartbeat1.wav", g_fBloodPoolPosition[client], SOUND_FROM_WORLD, SNDLEVEL_NORMAL);
}

void CreateBloodPoolVisuals(int client, float radius, float duration)
{
    float pos[3];
    pos[0] = g_fBloodPoolPosition[client][0];
    pos[1] = g_fBloodPoolPosition[client][1];
    pos[2] = g_fBloodPoolPosition[client][2] + 5.0;
    
    int totalPulses = RoundToFloor(duration * 2);
    for(int i = 0; i < totalPulses; i++)
    {
        float delay = float(i) * 0.5;
        DataPack pack = new DataPack();
        pack.WriteFloat(pos[0]);
        pack.WriteFloat(pos[1]);
        pack.WriteFloat(pos[2]);
        pack.WriteFloat(radius);
        CreateTimer(delay, CreateBloodRing_Timer, pack);
    }
    
    int iEnt = CreateEntityByName("light_dynamic");
    if(iEnt != INVALID_ENT_REFERENCE)
    {
        char sBuffer[64];
        Format(sBuffer, sizeof(sBuffer), "bloodritual_%d", client);
        DispatchKeyValue(iEnt, "targetname", sBuffer);
        Format(sBuffer, sizeof(sBuffer), "%f %f %f", pos[0], pos[1], pos[2]);
        DispatchKeyValue(iEnt, "origin", sBuffer);
        DispatchKeyValue(iEnt, "angles", "0 0 0");
        DispatchKeyValue(iEnt, "_light", "255 0 0 200");
        DispatchKeyValue(iEnt, "pitch", "0");
        DispatchKeyValue(iEnt, "distance", "256");
        DispatchKeyValue(iEnt, "brightness", "5");
        DispatchKeyValue(iEnt, "style", "6");
        DispatchKeyValue(iEnt, "spawnflags", "1");
        DispatchSpawn(iEnt);
        AcceptEntityInput(iEnt, "DisableShadow");
        
        Format(sBuffer, sizeof(sBuffer), "OnUser1 !self:kill::%.1f:1", duration);
        SetVariantString(sBuffer);
        AcceptEntityInput(iEnt, "AddOutput");
        AcceptEntityInput(iEnt, "FireUser1");
    }
}

public Action CreateBloodRing_Timer(Handle timer, DataPack pack)
{
    pack.Reset();
    float pos[3];
    pos[0] = pack.ReadFloat();
    pos[1] = pack.ReadFloat();
    pos[2] = pack.ReadFloat();
    float radius = pack.ReadFloat();
    delete pack;
    
    int color[4] = {200, 0, 0, 200};
    TE_SetupBeamRingPoint(pos, 10.0, radius, PrecacheModel("sprites/laser.vmt"), PrecacheModel("sprites/halo01.vmt"), 0, 10, 0.5, 8.0, 0.5, color, 10, 0);
    TE_SendToAll();
    
    return Plugin_Stop;
}

public Action BloodPoolDamage_Timer(Handle timer, DataPack pack)
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    float radius = pack.ReadFloat();
    
    if(!client || !IsClientInGame(client) || !g_bBloodPoolActive[client])
    {
        delete pack;
        return Plugin_Stop;
    }
    
    float damagePerTick = g_hCVDamagePerTick.FloatValue;
    float healPercentage = g_hCVHealPercentage.FloatValue;
    int totalDamageDealt = 0;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientInGame(i) || !IsPlayerAlive(i) || i == client)
            continue;
        
        if(!SMRPG_IsFFAEnabled() && GetClientTeam(i) == GetClientTeam(client))
            continue;
        
        float targetPos[3];
        GetClientAbsOrigin(i, targetPos);
        
        float distance = GetVectorDistance(g_fBloodPoolPosition[client], targetPos);
        if(distance <= radius)
        {
            SDKHooks_TakeDamage(i, client, client, damagePerTick, DMG_GENERIC);
            totalDamageDealt += RoundToFloor(damagePerTick);
            
            float victimPos[3];
            GetClientAbsOrigin(i, victimPos);
            victimPos[2] += 50.0;
            
            int bloodColor[4] = {150, 0, 0, 255};
            TE_SetupBeamPoints(g_fBloodPoolPosition[client], victimPos, PrecacheModel("sprites/laser.vmt"), PrecacheModel("sprites/halo01.vmt"), 0, 1, 0.3, 2.0, 2.0, 1, 0.0, bloodColor, 0);
            TE_SendToAll();
        }
    }
    
    if(totalDamageDealt > 0 && IsPlayerAlive(client))
    {
        int healAmount = RoundToFloor(totalDamageDealt * healPercentage);
        if(healAmount > 0)
        {
            int currentHealth = GetClientHealth(client);
            int maxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
            int newHealth = currentHealth + healAmount;
            
            if(newHealth > maxHealth)
                newHealth = maxHealth;
            
            SetEntityHealth(client, newHealth);
            
            float clientPos[3];
            GetClientAbsOrigin(client, clientPos);
            clientPos[2] += 10.0;
            
            int healColor[4] = {0, 255, 0, 200};
            TE_SetupBeamRingPoint(clientPos, 0.0, 50.0, PrecacheModel("sprites/laser.vmt"), PrecacheModel("sprites/halo01.vmt"), 0, 10, 0.3, 5.0, 0.5, healColor, 10, 0);
            TE_SendToAll();
        }
    }
    
    pack.Reset();
    return Plugin_Continue;
}

public Action EndBloodPool_Timer(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if(client && IsClientInGame(client))
    {
        g_bBloodPoolActive[client] = false;
        if(g_hBloodPoolTimer[client] != null)
        {
            KillTimer(g_hBloodPoolTimer[client]);
            g_hBloodPoolTimer[client] = null;
        }
    }
    return Plugin_Stop;
}

public Action BloodRitualCooldown_Timer(Handle timer, any client)
{
    if(IsClientInGame(client))
    {
        g_hBloodRitualTimer[client] = null;
    }
    return Plugin_Stop;
}

public void OnMapStart()
{
    PrecacheSound("player/heartbeat1.wav", true);
    PrecacheModel("sprites/laser.vmt", true);
    PrecacheModel("sprites/halo01.vmt", true);
}