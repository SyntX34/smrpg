#pragma semicolon 1
#include <sourcemod>
#include <smrpg>

#undef REQUIRE_PLUGIN
#include <ccc>

//#define USE_SIMPLE_PROCESSOR 1

#if defined USE_SIMPLE_PROCESSOR
#include <scp>
#include <colorvariables>
#define PROCESSOR_TYPE "(Simple Chat Processor)"
#else
#include <chat-processor>
#define PROCESSOR_TYPE "(Chat Processor)"
#endif

#pragma newdecls required

enum ChatSystemMode
{
	Mode_Auto = 0,
	Mode_CCC = 1,    
	Mode_Standalone = 2
}

ConVar g_hCVMaxChatRank;
ConVar g_hCVShowLevel;
ConVar g_hCVChatMode;

bool g_bCCCAvailable = false;
ChatSystemMode g_iCurrentMode = Mode_Auto;
char g_sOriginalCCCTag[MAXPLAYERS + 1][128];
bool g_bHasOriginalTag[MAXPLAYERS + 1] = {false, ...};
char g_sColorPalette[][] = {
	"FF1493", "00BFFF", "FF4500", "9400D3", "00FF7F", "FFD700", "FF69B4", "4169E1", "FF6347", "40E0D0",
	"DA70D6", "00CED1", "FF00FF", "ADFF2F", "BA55D3", "FFA500", "7B68EE", "00FA9A", "F08080", "87CEEB",
	"FF1744", "00E676", "FFEA00", "E040FB", "00E5FF", "FF6E40", "76FF03", "F50057", "651FFF", "FFD600",
	"00B0FF", "FF3D00", "C6FF00", "D500F9", "00BFA5", "FF9100", "AA00FF", "FFC400", "18FFFF", "FF5252",
	"69F0AE", "FFFF00", "E91E63", "2196F3", "FF5722", "9C27B0", "00BCD4", "FF9800", "3F51B5", "009688",
	"FF5733", "33FF57", "5733FF", "FF33F5", "33FFF5", "F533FF", "FFF533", "33F5FF", "F5FF33", "33FFF5",
	"FF0080", "0080FF", "80FF00", "FF8000", "00FF80", "8000FF", "FF0040", "40FF00", "0040FF", "FF4000",
	"FF007F", "7FFF00", "007FFF", "FF7F00", "00FF7F", "7F00FF", "FF00BF", "BFFF00", "00BFFF", "FFBF00",
	"FF1A8C", "1AFF8C", "8C1AFF", "FF8C1A", "1AFF1A", "8CFF1A", "FF1AFF", "1AFFFF", "FFFF1A", "1A8CFF",
	"FF33CC", "33FFCC", "CC33FF", "FFCC33", "33FF33", "CCFF33", "FF33FF", "33FFFF", "FFFF33", "33CCFF",
	"FF66AA", "66FFAA", "AA66FF", "FFAA66", "66FF66", "AAFF66", "FF66FF", "66FFFF", "FFFF66", "66AAFF"
};

public Plugin myinfo =
{
	name = "SM:RPG > Chat Tags " ... PROCESSOR_TYPE,
	author = "Peace-Maker, +SyntX",
	description = "Add RPG level in front of chat messages with CCC integration.",
	version = SMRPG_VERSION,
	url = "https://www.wcfan.de/"
};

public void OnPluginStart()
{
	LoadTranslations("smrpg_chattags.phrases");
	
	g_hCVMaxChatRank = CreateConVar("smrpg_chattags_maxrank", "10", "Show the rank of the player up until this value in front of his name in chat. -1 to disable, 0 to show for everyone.", _, true, -1.0);
	g_hCVShowLevel = CreateConVar("smrpg_chattags_showlevel", "1", "Show the level of the player in front of his name in chat?", _, true, 0.0, true, 1.0);
	g_hCVChatMode = CreateConVar("smrpg_chattags_mode", "0", "Chat system mode: 0 = Auto-detect, 1 = Force CCC integration, 2 = Force standalone mode", _, true, 0.0, true, 2.0);
	g_hCVChatMode.AddChangeHook(OnModeChanged);
	HookEvent("player_say", Event_PlayerSay, EventHookMode_Pre);
	
	AutoExecConfig(true, "smrpg_chattags");
	UpdateChatMode();
}

public void OnAllPluginsLoaded()
{
	g_bCCCAvailable = LibraryExists("ccc");
	UpdateChatMode();
	PrintModeStatus();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "ccc"))
	{
		g_bCCCAvailable = true;
		UpdateChatMode();
		PrintModeStatus();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "ccc"))
	{
		g_bCCCAvailable = false;
		UpdateChatMode();
		PrintModeStatus();
	}
}

public void OnClientPostAdminCheck(int client)
{
	g_sOriginalCCCTag[client][0] = '\0';
	g_bHasOriginalTag[client] = false;
	
	if (g_bCCCAvailable && g_iCurrentMode == Mode_CCC)
	{
		RequestFrame(Frame_StoreOriginalTag, GetClientUserId(client));
	}
}

public void OnClientDisconnect(int client)
{
	g_sOriginalCCCTag[client][0] = '\0';
	g_bHasOriginalTag[client] = false;
}

public void Frame_StoreOriginalTag(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client))
	{
		StoreOriginalCCCTag(client);
	}
}

public void CCC_OnUserConfigLoaded(int client)
{
	if (g_iCurrentMode == Mode_CCC)
	{
		StoreOriginalCCCTag(client);
	}
}

void StoreOriginalCCCTag(int client)
{
	char tempTag[128];
	CCC_GetTag(client, tempTag, sizeof(tempTag));
	RemoveSMRPGTags(tempTag, sizeof(tempTag));
	strcopy(g_sOriginalCCCTag[client], sizeof(g_sOriginalCCCTag[]), tempTag);
	g_bHasOriginalTag[client] = true;
}
public Action Event_PlayerSay(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (client > 0 && IsClientInGame(client) && !IsFakeClient(client))
	{
		if (g_iCurrentMode == Mode_CCC && g_bCCCAvailable)
		{
			if (!g_bHasOriginalTag[client])
			{
				StoreOriginalCCCTag(client);
			}
			UpdateClientTagWithRandomColors(client);
		}
	}
	
	return Plugin_Continue;
}

void RemoveSMRPGTags(char[] text, int maxlen)
{
	char output[256];
	int writePos = 0;
	int len = strlen(text);
	int i = 0;
	
	while (i < len)
	{
		while (i < len && (text[i] == 0x07 || text[i] == 0x08 || text[i] == 0x01 || 
			   text[i] == 0x02 || text[i] == 0x03 || text[i] == 0x04 || 
			   text[i] == 0x05 || text[i] == 0x06))
		{
			if (text[i] == 0x07)
				i += 7;
			else if (text[i] == 0x08)
				i += 9;
			else
				i++;
		}
		if (i < len && text[i] == '[')
		{
			bool isRPGTag = false;
			if (i + 6 < len && StrContains(text[i], "[Rank ", false) == 0)
			{
				isRPGTag = true;
			}
			else if (i + 5 < len && StrContains(text[i], "[LVL ", false) == 0)
			{
				isRPGTag = true;
			}
			
			if (isRPGTag)
			{
				int endPos = i + 1;
				while (endPos < len && text[endPos] != ']')
					endPos++;
				
				if (endPos < len)
				{
					endPos++;
					while (endPos < len && (text[endPos] == 0x01 || text[endPos] == ' '))
						endPos++;
					i = endPos;
					continue;
				}
			}
		}
		if (i < len)
		{
			output[writePos++] = text[i];
			i++;
		}
	}
	
	output[writePos] = '\0';
	strcopy(text, maxlen, output);
	TrimString(text);
}

void StripColorCodes(char[] text, int maxlen)
{
	char output[256];
	int len = strlen(text);
	int outPos = 0;
	int i = 0;
	
	while (i < len)
	{
		if (text[i] == '{')
		{
			int closePos = i + 1;
			while (closePos < len && text[closePos] != '}')
				closePos++;
			
			if (closePos < len && text[closePos] == '}')
			{
				i = closePos + 1;
				continue;
			}
		}
		if (text[i] == 0x07)
		{
			i += 7;
			continue;
		}
		if (text[i] == 0x08)
		{
			i += 9;
			continue;
		}
		if (text[i] == 0x01 || text[i] == 0x02 || text[i] == 0x03 || 
			text[i] == 0x04 || text[i] == 0x05 || text[i] == 0x06)
		{
			i++;
			continue;
		}
		
		output[outPos++] = text[i++];
	}
	output[outPos] = '\0';
	strcopy(text, maxlen, output);
}

void GetRandomColor(char[] buffer, int maxlen)
{
	int randomIndex = GetRandomInt(0, sizeof(g_sColorPalette) - 1);
	strcopy(buffer, maxlen, g_sColorPalette[randomIndex]);
}

void UpdateClientTagWithRandomColors(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
		return;
	bool alpha;
	int cccTagColorInt = CCC_GetColor(client, CCC_TagColor, alpha);
	char cccTagColorHex[8] = "";
	if (cccTagColorInt != COLOR_NONE && cccTagColorInt != COLOR_NULL && cccTagColorInt >= 0)
	{
		Format(cccTagColorHex, sizeof(cccTagColorHex), "%06X", cccTagColorInt);
	}
	char sRankTag[128], sRankTagClean[64], rankColor[8];
	sRankTag[0] = '\0';
	rankColor[0] = '\0';
	
	int iMaxRank = g_hCVMaxChatRank.IntValue;
	if (iMaxRank > -1)
	{
		int iRank = SMRPG_GetClientRank(client);
		if (iRank > 0 && (iMaxRank == 0 || iRank <= iMaxRank))
		{
			Format(sRankTagClean, sizeof(sRankTagClean), "%T", "Rank Chat Tag", client, iRank);
			StripColorCodes(sRankTagClean, sizeof(sRankTagClean));
			
			GetRandomColor(rankColor, sizeof(rankColor));
			Format(sRankTag, sizeof(sRankTag), "\x07%s%s\x01", rankColor, sRankTagClean);
		}
	}
	char sLevelTag[128], sLevelTagClean[64]; 
	sLevelTag[0] = '\0';
	if (g_hCVShowLevel.BoolValue)
	{
		int iLevel = SMRPG_GetClientLevel(client);
		Format(sLevelTagClean, sizeof(sLevelTagClean), "%T", "Level Chat Tag", client, iLevel);
		StripColorCodes(sLevelTagClean, sizeof(sLevelTagClean));
		
		char levelColor[8];
		GetRandomColor(levelColor, sizeof(levelColor));
		int attempts = 0;
		while (StrEqual(levelColor, rankColor) && attempts < 10)
		{
			GetRandomColor(levelColor, sizeof(levelColor));
			attempts++;
		}
		
		Format(sLevelTag, sizeof(sLevelTag), "\x07%s%s\x01", levelColor, sLevelTagClean);
	}
	char sNewTag[256];
	
	if (strlen(cccTagColorHex) > 0)
	{
		Format(sNewTag, sizeof(sNewTag), "%s%s\x01\x07%s%s", 
			sRankTag, sLevelTag, cccTagColorHex, g_sOriginalCCCTag[client]);
	}
	else
	{
		Format(sNewTag, sizeof(sNewTag), "%s%s%s", 
			sRankTag, sLevelTag, g_sOriginalCCCTag[client]);
	}
	CCC_SetTag(client, sNewTag);
	CCC_ResetColor(client, CCC_NameColor);
	CCC_ResetColor(client, CCC_ChatColor);
}

void OnModeChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	UpdateChatMode();
	PrintModeStatus();
}

void UpdateChatMode()
{
	int iModeValue = g_hCVChatMode.IntValue;
	
	switch (iModeValue)
	{
		case 0:
		{
			g_iCurrentMode = g_bCCCAvailable ? Mode_CCC : Mode_Standalone;
		}
		case 1:
		{
			if (g_bCCCAvailable)
				g_iCurrentMode = Mode_CCC;
			else
			{
				LogError("[SMRPG-ChatTags] Cannot force CCC mode - Custom Chat Colors plugin not found! Falling back to standalone mode.");
				g_iCurrentMode = Mode_Standalone;
			}
		}
		case 2:
		{
			g_iCurrentMode = Mode_Standalone;
		}
		default:
		{
			LogError("[SMRPG-ChatTags] Invalid mode value '%d', using auto-detect.", iModeValue);
			g_iCurrentMode = g_bCCCAvailable ? Mode_CCC : Mode_Standalone;
		}
	}
	if (g_iCurrentMode == Mode_CCC)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				StoreOriginalCCCTag(i);
			}
		}
	}
}

void PrintModeStatus()
{
	char sModeName[32];
	char sConfigMode[32];
	
	switch (g_hCVChatMode.IntValue)
	{
		case 0: sConfigMode = "Auto-detect";
		case 1: sConfigMode = "Force CCC";
		case 2: sConfigMode = "Force Standalone";
		default: sConfigMode = "Unknown";
	}
	
	switch (g_iCurrentMode)
	{
		case Mode_CCC: sModeName = "CCC Integration";
		case Mode_Standalone: sModeName = "Standalone";
		default: sModeName = "Unknown";
	}
	
	LogMessage("[SMRPG-ChatTags] Mode: %s | Config: %s | CCC Available: %s", 
		sModeName, sConfigMode, g_bCCCAvailable ? "Yes" : "No");
}

#if defined USE_SIMPLE_PROCESSOR
public Action OnChatMessage(int& author, Handle recipients, char[] name, char[] message)
#else
public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
#endif
{
	if (g_iCurrentMode == Mode_Standalone)
	{
		char sRankTag[128];
		char sRankTagClean[64];
		sRankTag[0] = '\0';
		
		int iMaxRank = g_hCVMaxChatRank.IntValue;
		if (iMaxRank > -1)
		{
			int iRank = SMRPG_GetClientRank(author);
			if (iRank > 0 && (iMaxRank == 0 || iRank <= iMaxRank))
			{
				Format(sRankTagClean, sizeof(sRankTagClean), "%T", "Rank Chat Tag", author, iRank);
				StripColorCodes(sRankTagClean, sizeof(sRankTagClean));
				
				char rankColor[8];
				GetRandomColor(rankColor, sizeof(rankColor));
				Format(sRankTag, sizeof(sRankTag), "\x07%s%s\x01", rankColor, sRankTagClean);
			}
		}

		char sLevelTag[128];
		char sLevelTagClean[64];
		sLevelTag[0] = '\0';
		
		if (g_hCVShowLevel.BoolValue)
		{
			int iLevel = SMRPG_GetClientLevel(author);
			Format(sLevelTagClean, sizeof(sLevelTagClean), "%T", "Level Chat Tag", author, iLevel);
			StripColorCodes(sLevelTagClean, sizeof(sLevelTagClean));
			
			char levelColor[8];
			GetRandomColor(levelColor, sizeof(levelColor));
			Format(sLevelTag, sizeof(sLevelTag), "\x07%s%s\x01", levelColor, sLevelTagClean);
		}
		Format(name, MAXLENGTH_NAME, "%s%s\x03%s", sRankTag, sLevelTag, name);
		
#if defined USE_SIMPLE_PROCESSOR
		CProcessVariables(name, MAXLENGTH_NAME, false);
#endif
		return Plugin_Changed;
	}
	return Plugin_Continue;
}