#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "fireballshotgun"

ConVar g_hCVChancePerLevel;
ConVar g_hCVTimeIncrease;
ConVar g_hCVDamagePerLevel;
ConVar g_hCVFireEffectDamage;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Fireball Shotgun",
	author = "+SyntX",
	description = "Fireball effect from shotguns based on SM:RPG upgrade level.",
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
		SMRPG_RegisterUpgradeType("Fireball Shotgun", UPGRADE_SHORTNAME, "Chance to create fireball effect when shooting with a shotgun.", 0, true, 10, 20, 15);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVChancePerLevel = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_fireballshotgun_chance", "0.05", "Chance multiplier per level to create fireball effect (e.g. 0.05 = 5% per level)", 0, true, 0.0, true, 1.0);
		g_hCVTimeIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_fireballshotgun_time", "0.2", "How many seconds are players left burning multiplied by level?", 0, true, 0.0);
		g_hCVDamagePerLevel = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_fireballshotgun_damage", "1.0", "Additional damage per level", 0, true, 0.0);
		g_hCVFireEffectDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_fireballshotgun_fire_damage", "2.0", "Damage per second while burning", 0, true, 0.0);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
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

/**
 * Hook callbacks
 */
public void Hook_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || victim <= 0 || victim > MaxClients || !IsPlayerAlive(victim))
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	if(!SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME))
		return;
	
	if(SMRPG_IsClientBurning(victim))
		return;
	
	if(IsFakeClient(attacker) && SMRPG_IgnoreBots())
		return;
	
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	int iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	int iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = GetEntPropEnt(inflictor, Prop_Send, "m_hActiveWeapon");
	
	if(iWeapon == -1)
		return;
	
	if(iWeapon != GetPlayerWeaponSlot(attacker, 0))
		return;
	
	if(!IsShotgunWeapon(iWeapon))
		return;
	
	float fChance = float(iLevel) * g_hCVChancePerLevel.FloatValue;
	
	if(GetRandomFloat(0.0, 1.0) > fChance)
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
		return;

	float fTime = float(iLevel) * g_hCVTimeIncrease.FloatValue;
	float fDamage = g_hCVFireEffectDamage.FloatValue;
	
	SMRPG_IgniteClient(victim, fTime, UPGRADE_SHORTNAME, true, attacker);
	
	float fAdditionalDamage = float(iLevel) * g_hCVDamagePerLevel.FloatValue;
	if (fAdditionalDamage > 0.0)
	{
		SDKHooks_TakeDamage(victim, attacker, attacker, fAdditionalDamage, DMG_BURN);
	}
}

/**
 * Helper functions
 */
bool IsShotgunWeapon(int weapon)
{
	if(weapon <= 0 || !IsValidEntity(weapon))
		return false;
	
	char sWeapon[64];
	GetEntityClassname(weapon, sWeapon, sizeof(sWeapon));

	if(StrContains(sWeapon, "weapon_m3") != -1 ||
	   StrContains(sWeapon, "weapon_xm1014") != -1 ||
	   StrContains(sWeapon, "weapon_nova") != -1 ||
	   StrContains(sWeapon, "weapon_mag7") != -1)
	{
		return true;
	}
	
	return false;
}