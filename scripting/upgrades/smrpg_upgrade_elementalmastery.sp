#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "elementalmastery"

enum ElementType
{
    ELEMENT_FIRE,
    ELEMENT_ICE,
    ELEMENT_LIGHTNING,
    ELEMENT_EARTH
}

ElementType g_iCurrentElement[MAXPLAYERS+1];
ConVar g_hCVCooldown;
ConVar g_hCVDamageMultiplier;
ConVar g_hCVElementSwitchTime;

Handle g_hElementTimer[MAXPLAYERS+1];
Handle g_hAutoSwitchTimer[MAXPLAYERS+1];
bool g_bElementActive[MAXPLAYERS+1];
bool g_bUpgradeLoaded = false;

public Plugin myinfo = 
{
    name = "SM:RPG Upgrade > Elemental Mastery",
    author = "+SyntX",
    description = "Master different elemental powers to enhance your attacks.",
    version = SMRPG_VERSION,
    url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
    LoadTranslations("smrpg_stock_upgrades.phrases");
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            OnClientPutInServer(i);
        }
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
        SMRPG_RegisterUpgradeType("Elemental Mastery", UPGRADE_SHORTNAME, "Master different elemental powers to enhance your attacks.", 10, true, 10, 20, 15);
        SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
        SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
        
        g_hCVCooldown = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_elementalmastery_cooldown", "30.0", "Cooldown time in seconds between element switches", 0, true, 1.0);
        g_hCVDamageMultiplier = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_elementalmastery_damage", "1.5", "Damage multiplier for elemental attacks", 0, true, 1.0);
        g_hCVElementSwitchTime = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_elementalmastery_switchtime", "5.0", "Time between automatic element switches", 0, true, 1.0);
        
        g_bUpgradeLoaded = true;
        
        // Initialize auto-switch for any clients that already have the upgrade
        for(int i = 1; i <= MaxClients; i++)
        {
            if(IsClientInGame(i) && SMRPG_GetClientUpgradeLevel(i, UPGRADE_SHORTNAME) > 0)
            {
                StartAutoElementSwitch(i);
                g_bElementActive[i] = true;
            }
        }
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if(StrEqual(name, "smrpg"))
    {
        g_bUpgradeLoaded = false;
    }
}

public void OnClientPutInServer(int client)
{
    g_iCurrentElement[client] = ELEMENT_FIRE;
    g_hElementTimer[client] = null;
    g_hAutoSwitchTimer[client] = null;
    g_bElementActive[client] = false;
    
    // Hook for damage dealt
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    ClearClientTimers(client);
    g_bElementActive[client] = false;
}

void ClearClientTimers(int client)
{
    if(g_hElementTimer[client] != null)
    {
        KillTimer(g_hElementTimer[client]);
        g_hElementTimer[client] = null;
    }
    
    if(g_hAutoSwitchTimer[client] != null)
    {
        KillTimer(g_hAutoSwitchTimer[client]);
        g_hAutoSwitchTimer[client] = null;
    }
}

/**
 * SM:RPG Upgrade callbacks
 */
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
    if(type == UpgradeQueryType_Buy)
    {
        // Player bought the upgrade, start auto-switching
        if(!g_bElementActive[client])
        {
            StartAutoElementSwitch(client);
            g_bElementActive[client] = true;
        }
    }
    else if(type == UpgradeQueryType_Sell)
    {
        // Player sold the upgrade, stop all effects
        ClearClientTimers(client);
        g_bElementActive[client] = false;
    }
}

/**
 * Hook for damage dealt
 */
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    // Check if attacker has the upgrade
    if(attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
    {
        if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME) && SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME) > 0)
        {
            if(SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME) && SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
            {
                // Apply elemental damage multiplier
                if(g_hCVDamageMultiplier != null)
                {
                    damage *= g_hCVDamageMultiplier.FloatValue;
                }
                else
                {
                    damage *= 1.5; // Default multiplier
                }
                
                // Apply elemental effect based on current element
                ApplyElementalEffect(victim, attacker, g_iCurrentElement[attacker]);
                
                return Plugin_Changed;
            }
        }
    }
    
    return Plugin_Continue;
}

/**
 * Apply elemental effect based on element type
 */
void ApplyElementalEffect(int victim, int attacker, ElementType element)
{
    switch(element)
    {
        case ELEMENT_FIRE:
        {
            // Burn effect - DoT over time
            CreateTimer(1.0, FireDamage_Timer, GetClientUserId(victim), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
            // PrintToChat(attacker, "Fire damage applied to %N!", victim);
        }
        case ELEMENT_ICE:
        {
            // Slow effect
            if(IsPlayerAlive(victim))
            {
                SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 0.5);
                CreateTimer(3.0, ResetMovement_Timer, GetClientUserId(victim));
                // PrintToChat(attacker, "Ice slow applied to %N!", victim);
            }
        }
        case ELEMENT_LIGHTNING:
        {
            // Shock effect - extra damage
            float extraDamage = 10.0;
            if(IsPlayerAlive(victim))
            {
                SDKHooks_TakeDamage(victim, attacker, attacker, extraDamage, DMG_SHOCK);
                // PrintToChat(attacker, "Lightning shock applied to %N!", victim);
            }
        }
        case ELEMENT_EARTH:
        {
            // Stun effect - stop movement briefly
            if(IsPlayerAlive(victim) && GetEntityMoveType(victim) != MOVETYPE_NONE)
            {
                SetEntityMoveType(victim, MOVETYPE_NONE);
                CreateTimer(1.5, ResetMovementType_Timer, GetClientUserId(victim));
                //PrintToChat(attacker, "Earth stun applied to %N!", victim);
            }
        }
    }
}

/**
 * Switch to next element
 */
void SwitchToNextElement(int client)
{
    g_iCurrentElement[client] = view_as<ElementType>((g_iCurrentElement[client] + 1) % 4);
    
    char elementName[32];
    switch(g_iCurrentElement[client])
    {
        case ELEMENT_FIRE: elementName = "Fire";
        case ELEMENT_ICE: elementName = "Ice";
        case ELEMENT_LIGHTNING: elementName = "Lightning";
        case ELEMENT_EARTH: elementName = "Earth";
    }
    
    // PrintToChat(client, "Element switched to %s!", elementName);
}

/**
 * Manual element switching function
 */
public Action Command_SwitchElement(int client, int args)
{
    if(!g_bUpgradeLoaded)
        return Plugin_Handled;
        
    if(g_hElementTimer[client] != null)
    {
        //PrintToChat(client, "Element switch is on cooldown!");
        return Plugin_Handled;
    }
    
    if(!IsPlayerAlive(client))
    {
        //PrintToChat(client, "You must be alive to switch elements!");
        return Plugin_Handled;
    }
    
    if(SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) == 0)
    {
        //PrintToChat(client, "You don't have the Elemental Mastery upgrade!");
        return Plugin_Handled;
    }
    
    if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
        return Plugin_Handled;
    
    // Start auto element switching if not already active
    if(!g_bElementActive[client])
    {
        StartAutoElementSwitch(client);
        g_bElementActive[client] = true;
    }
    
    // Switch to next element
    SwitchToNextElement(client);
    
    // Set cooldown for manual switch
    float cooldown = g_hCVCooldown != null ? g_hCVCooldown.FloatValue : 30.0;
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    g_hElementTimer[client] = CreateTimer(cooldown, ElementCooldown_Timer, pack);
    
    return Plugin_Handled;
}

void StartAutoElementSwitch(int client)
{
    // Clear any existing auto switch timer
    if(g_hAutoSwitchTimer[client] != null)
    {
        KillTimer(g_hAutoSwitchTimer[client]);
        g_hAutoSwitchTimer[client] = null;
    }
    
    // Start new auto switch timer
    float switchTime = g_hCVElementSwitchTime != null ? g_hCVElementSwitchTime.FloatValue : 5.0;
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    g_hAutoSwitchTimer[client] = CreateTimer(switchTime, AutoSwitchElement_Timer, pack, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Timer callbacks
 */
public Action AutoSwitchElement_Timer(Handle timer, DataPack pack)
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    
    if(client > 0 && IsClientInGame(client) && IsPlayerAlive(client) && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0)
    {
        // Automatically switch elements
        SwitchToNextElement(client);
        return Plugin_Continue;
    }
    
    // Client disconnected or no longer has upgrade
    delete pack;
    g_hAutoSwitchTimer[client] = null;
    return Plugin_Stop;
}

public Action FireDamage_Timer(Handle timer, any userid)
{
    int victim = GetClientOfUserId(userid);
    
    if(victim > 0 && IsClientInGame(victim) && IsPlayerAlive(victim))
    {
        // Deal damage over time
        SDKHooks_TakeDamage(victim, 0, 0, 5.0, DMG_BURN);
        return Plugin_Continue;
    }
    
    return Plugin_Stop;
}

public Action ResetMovement_Timer(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if(client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
    {
        SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
    }
    return Plugin_Stop;
}

public Action ResetMovementType_Timer(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if(client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
    {
        SetEntityMoveType(client, MOVETYPE_WALK);
    }
    return Plugin_Stop;
}

public Action ElementCooldown_Timer(Handle timer, DataPack pack)
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    delete pack;
    
    if(client > 0 && IsClientInGame(client))
    {
        g_hElementTimer[client] = null;
        //PrintToChat(client, "Element switch is ready!");
    }
    return Plugin_Stop;
}