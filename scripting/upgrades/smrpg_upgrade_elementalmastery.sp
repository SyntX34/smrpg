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
bool g_bElementActive[MAXPLAYERS+1];

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
        SMRPG_RegisterUpgradeType("Elemental Mastery", UPGRADE_SHORTNAME, "Master different elemental powers to enhance your attacks.", 10, true, 10, 20, 15);
        SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
        SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
        
        g_hCVCooldown = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_elementalmastery_cooldown", "30.0", "Cooldown time in seconds between element switches", 0, true, 1.0);
        g_hCVDamageMultiplier = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_elementalmastery_damage", "1.5", "Damage multiplier for elemental attacks", 0, true, 1.0);
        g_hCVElementSwitchTime = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_elementalmastery_switchtime", "5.0", "Time between automatic element switches", 0, true, 1.0);
    }
}

public void OnClientPutInServer(int client)
{
    g_iCurrentElement[client] = ELEMENT_FIRE;
    g_hElementTimer[client] = null;
    g_bElementActive[client] = false;
    
    // Start automatic element switching
    CreateTimer(g_hCVElementSwitchTime.FloatValue, SwitchElement_Timer, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
    
    // Hook for damage dealt
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    if(g_hElementTimer[client] != null)
    {
        KillTimer(g_hElementTimer[client]);
        g_hElementTimer[client] = null;
    }
    g_bElementActive[client] = false;
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
    // Reset any active effects when upgrade is sold
    if(type == UpgradeQueryType_Sell)
    {
        if(g_bElementActive[client])
        {
            g_bElementActive[client] = false;
        }
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
                damage *= g_hCVDamageMultiplier.FloatValue;
                
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
            CreateTimer(1.0, FireDamage_Timer, victim, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
            // PrintToChat(attacker, "Fire damage applied to %N!", victim);
        }
        case ELEMENT_ICE:
        {
            // Slow effect
            SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 0.5);
            CreateTimer(3.0, ResetMovement_Timer, victim);
            // PrintToChat(attacker, "Ice slow applied to %N!", victim);
        }
        case ELEMENT_LIGHTNING:
        {
            // Shock effect - extra damage
            float extraDamage = 10.0;
            SDKHooks_TakeDamage(victim, attacker, attacker, extraDamage, DMG_SHOCK);
            // PrintToChat(attacker, "Lightning shock applied to %N!", victim);
        }
        case ELEMENT_EARTH:
        {
            // Stun effect - stop movement briefly
            SetEntityMoveType(victim, MOVETYPE_NONE);
            CreateTimer(1.5, ResetMovementType_Timer, victim);
            //PrintToChat(attacker, "Earth stun applied to %N!", victim);
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
 * Activate specific element
 */
public void SMRPG_UpgradeActivated(int client, const char[] shortname)
{
    if(!StrEqual(shortname, UPGRADE_SHORTNAME))
        return;
    
    if(g_hElementTimer[client] != null)
    {
        //PrintToChat(client, "Element switch is on cooldown!");
        return;
    }
    
    if(!IsPlayerAlive(client))
    {
        //PrintToChat(client, "You must be alive to switch elements!");
        return;
    }
    
    if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
        return;
    
    // Switch to next element
    SwitchToNextElement(client);
    
    // Set cooldown
    float cooldown = g_hCVCooldown.FloatValue;
    g_hElementTimer[client] = CreateTimer(cooldown, ElementCooldown_Timer, client);
}

/**
 * Timer callbacks
 */
public Action SwitchElement_Timer(Handle timer, any client)
{
    if(IsClientInGame(client) && IsPlayerAlive(client))
    {
        // Automatically switch elements
        SwitchToNextElement(client);
    }
    return Plugin_Continue;
}

public Action FireDamage_Timer(Handle timer, any victim)
{
    static int fireTicks[MAXPLAYERS+1] = {0};
    
    if(!IsClientInGame(victim) || !IsPlayerAlive(victim))
    {
        fireTicks[victim] = 0;
        return Plugin_Stop;
    }
    
    // Deal damage over time
    SDKHooks_TakeDamage(victim, 0, 0, 5.0, DMG_BURN);
    fireTicks[victim]++;
    
    // Stop after 5 ticks (5 seconds)
    if(fireTicks[victim] >= 5)
    {
        fireTicks[victim] = 0;
        return Plugin_Stop;
    }
    
    return Plugin_Continue;
}

public Action ResetMovement_Timer(Handle timer, any client)
{
    if(IsClientInGame(client) && IsPlayerAlive(client))
    {
        SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
    }
    return Plugin_Stop;
}

public Action ResetMovementType_Timer(Handle timer, any client)
{
    if(IsClientInGame(client) && IsPlayerAlive(client))
    {
        SetEntityMoveType(client, MOVETYPE_WALK);
    }
    return Plugin_Stop;
}

public Action ElementCooldown_Timer(Handle timer, any client)
{
    if(IsClientInGame(client))
    {
        g_hElementTimer[client] = null;
        //PrintToChat(client, "Element switch is ready!");
    }
    return Plugin_Stop;
}