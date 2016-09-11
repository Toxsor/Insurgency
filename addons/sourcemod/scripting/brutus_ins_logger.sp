/**
 * Brutus Insurgency2 Logger/LogFixer
 * Based on SuperLogs by psychonic (https://forums.alliedmods.net/showthread.php?t=99231?t=99231)
 * Author: FZFalzar of Brutus.SG Modded Servers (http://brutus.sg)
 * Version: 1.0.7
 */

#include <sourcemod>
#include <regex>
#define MAX_DEFINABLE_WEAPONS 100
#define MAX_WEAPON_LEN 32
#define PREFIX_LEN 7

#define INS

new g_weapon_stats[MAXPLAYERS+1][MAX_DEFINABLE_WEAPONS][15];
new Handle:g_weap_array = INVALID_HANDLE;
new NumWeaponsDefined = 0;
new const String:g_weapon_list[MAX_DEFINABLE_WEAPONS][MAX_WEAPON_LEN] = {
	"grenade_anm14",
	"grenade_c4",
	"grenade_f1",
	"grenade_molotov",
	"grenade_m67",
	"grenade_m84",
	"obj_weapon_cache",
	"rocket_at4",
	"rocket_rpg7",
	"weapon_akm",
	"weapon_aks74u",
	"weapon_fal",
	"weapon_garand",
	"weapon_kabar",
	"weapon_k98",
	"weapon_makarov",
	"weapon_mini14",
	"weapon_mk18",
	"weapon_mosin",
	"weapon_mp40",
	"weapon_mp5",
	"weapon_m249",
	"weapon_m1a1",
	"weapon_m14",
	"weapon_m16a4",
	"weapon_m40a1",
	"weapon_m590",
	"weapon_m9",
	"weapon_rpk",
	"weapon_sks",
	"weapon_toz",
	"weapon_ump45"
};

new g_client_last_weapon[MAXPLAYERS+1] = {-1, ...};
new String:g_client_last_weaponstring[MAXPLAYERS+1][64];
//============================================================================================================
#include <loghelper>
#include <wstatshelper>

#define KILL_REGEX_PATTERN "^\"(.+(?:<[^>]*>))\" killed \"(.+(?:<[^>]*>))\" with \"([^\"]*)\" at (.*)"
#define SUICIDE_REGEX_PATTERN "^\"(.+(?:<[^>]*>))\" committed suicide with \"([^\"]*)\""

new Handle:kill_regex = INVALID_HANDLE;
new Handle:suicide_regex = INVALID_HANDLE;
//============================================================================================================

public Plugin:myinfo =
{
	name = "Brutus Insurgency2 Logger",
	author = "FZFalzar",
	version = "1.1.0",
	description = "Intercepts and fixes events logged for Insurgency2",
	url = "http://brutus.sg"
};

public OnPluginStart()
{
	g_weap_array = LoadValues();
	
	if(g_weap_array == INVALID_HANDLE)
	{
		SetFailState("[LOGGER] Failed to load weapon configuration into array!");
	}

	CreatePopulateWeaponTrie();

	kill_regex = CompileRegex(KILL_REGEX_PATTERN);
	suicide_regex = CompileRegex(SUICIDE_REGEX_PATTERN);
	
	//Begin HookEvents
	hook_wstats();
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("weapon_fire", Event_WeaponFired);
	
	HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
	HookEvent("player_death", Event_PlayerDeath);
	
	HookEvent("object_destroyed", Event_CPDestroyed);
	HookEvent("controlpoint_captured", Event_CPCapped);
	
	//Begin Engine LogHooks
	AddGameLogHook(LogEvent);
	
	GetTeams(false);
}

public OnMapStart()
{
	GetTeams(false);
	RepopulateWeaponTrie();
	PrintToServer("[LOGGER] Weapon Trie Reset!");
}

public Handle:LoadValues()
{
	new numWeapons = 0;
	g_weap_array = CreateArray(32);
	decl String:strBuf[32];
	
	if (!FileExists("cfg/sourcemod/brutus_ins_logger_weapons.cfg"))
	{
		SetFailState("[LOGGER] Couldn't load Brutus Insurgency2 Logger. brutus_ins_logger_weapons.cfg could not be found.");
	}
	
	new Handle:g_weaponfile_handle = OpenFile("cfg/sourcemod/brutus_ins_logger_weapons.cfg", "r");
	
	if (g_weaponfile_handle == INVALID_HANDLE)
	{
		SetFailState("[LOGGER] An error occured while trying to load the configuration!");
	}
	
	do
	{
		ReadFileLine(g_weaponfile_handle, strBuf, sizeof(strBuf));
		TrimString(strBuf);
		if(FindCharInString(strBuf, '+') == 0)
		{
			ReplaceString(strBuf, sizeof(strBuf), "+", "", false);
			PushArrayString(g_weap_array, strBuf);
			numWeapons++;
		}
	}
	while(!IsEndOfFile(g_weaponfile_handle));
	
	CloseHandle(g_weaponfile_handle);
	
	//PrintToServer("Weapons Loaded: %d", numWeapons);
	NumWeaponsDefined = numWeapons;
	for(new i = 0; i < NumWeaponsDefined; i++)
	{
		decl String:strNewBuf[32];
		GetArrayString(g_weap_array, i, strNewBuf, sizeof(strNewBuf));
		PrintToServer("[LOGGER] Loaded Weapon (%d): \t%s", i, strNewBuf);
	}
	
	return g_weap_array;
}

//=====================================================================================================
hook_wstats()
{
	HookEvent("player_first_spawn", Event_PlayerSpawn);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
}

unhook_wstats()
{
	UnhookEvent("player_first_spawn", Event_PlayerSpawn);
	UnhookEvent("player_spawn", Event_PlayerSpawn);
	UnhookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
}
//=====================================================================================================

public RepopulateWeaponTrie()
{
	ClearTrie(g_weapon_trie);
	CreatePopulateWeaponTrie();
}

public Action:Event_CPCapped(Handle:event, const String:name[], bool:dontBroadcast)
{
	new cap_team_index = GetEventInt(event, "team");
	new player_team_index;
	//"cp" "byte" - for naming, currently not needed
	for (new i=1; i<=MaxClients; i++)
	{
		//player_team_index = GetClientTeam(i);
	
		if(IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i))
		{
			player_team_index = GetClientTeam(i);
			if(player_team_index == cap_team_index)
			{
				decl String: player_authid[64];
				if (!GetClientAuthString(i, player_authid, sizeof(player_authid)))
				{
					strcopy(player_authid, sizeof(player_authid), "UNKNOWN");
				}
				new player_userid = GetClientUserId(i);
				
				LogToGame("\"%N<%d><%s><%s>\" triggered \"ins_cp_captured\"", i, player_userid, player_authid, g_team_list[player_team_index]);
			}
		}
	}
}

public Action:Event_CPDestroyed(Handle:event, const String:name[], bool:dontBroadcast)
{
	new cap_team_index = GetEventInt(event, "attackerteam");
	new player_team_index;
	//"cp" "byte" - for naming, currently not needed
	for (new i=1; i<=MaxClients; i++)
	{
		//player_team_index = GetClientTeam(i);
	
		if(IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i))
		{
			player_team_index = GetClientTeam(i);
			if(player_team_index == cap_team_index)
			{
				decl String: player_authid[64];
				if (!GetClientAuthString(i, player_authid, sizeof(player_authid)))
				{
					strcopy(player_authid, sizeof(player_authid), "UNKNOWN");
				}
				new player_userid = GetClientUserId(i);
				
				LogToGame("\"%N<%d><%s><%s>\" triggered \"ins_cp_destroyed\"", i, player_userid, player_authid, g_team_list[player_team_index]);
			}
		}
	}
}

public Action:Event_WeaponFired(Handle:event, const String:name[], bool:dontBroadcast)
{
	//"weaponid" "short"
	//"userid" "short"
	//"shots" "byte"
	new plrid = GetClientOfUserId(GetEventInt(event, "userid"));
	new String:shotWeapName[32];
	GetClientWeapon(plrid, shotWeapName, sizeof(shotWeapName));
	//PrintToChatAll("WeapFire: %s", shotWeapName);
	//WORKAROUND! THIS IS VERY BAD BUT I DONT WANT ANOTHER STAT WIPE TO AFFECT ANYONE
	//THROWABLES
	if(StrContains(shotWeapName, "c4") > -1 ||		//c4 expl	(weapon_c4_clicker) OR (weapon_c4_cell) OR (weapon_c4)
	StrContains(shotWeapName, "anm14") > -1 || 		//anm14 incendiary (weapon_anm14)
	StrContains(shotWeapName, "m18") > -1 ||		//smoke grenade (weapon_m18)
	StrContains(shotWeapName, "molotov") > -1 ||	//molotov (weapon_molotov)
	StrContains(shotWeapName, "f1") > -1 ||			//f1 frag (weapon_f1)
	StrContains(shotWeapName, "m67") > -1 ||		//m67 frag (weapon_m67)
	StrContains(shotWeapName, "m84") > -1)			//m84 flashbang (weapon_m84)
	{
		if(StrContains(shotWeapName, "c4") > -1)
		{
			shotWeapName = "grenade_c4";
		}
		else
		{
			ReplaceString(shotWeapName, sizeof(shotWeapName), "weapon", "grenade", false);
		}
	}
	//LAUNCHERS
	else if(StrContains(shotWeapName, "at4") > -1 ||	//at4 launcher (weapon_at4)
	StrContains(shotWeapName, "rpg7") > -1)	//rpg7 launcher (weapon_rpg7)
	{
		ReplaceString(shotWeapName, sizeof(shotWeapName), "weapon", "rocket", false);
	}
	//PrintToChatAll("WeapFire Replaced: %s", shotWeapName);
	//new weapon_index = get_weapon_index(shotWeapName, GetEventInt(event, "weaponid"));
	
	//Game WeaponId is not consistent with our list, we cannot assume it to be the same, thus the requirement for iteration. it's slow but it'll do
	new weapon_index = GetWeaponArrayIndex(shotWeapName);
	//PrintToChatAll("WeapFired: %s", shotWeapName);
	//PrintToServer("WeaponIndex: %d - %s", weapon_index, shotWeapName);
	
	if (weapon_index > -1)
	{
		g_weapon_stats[plrid][weapon_index][LOG_HIT_SHOTS]++;
		g_client_last_weapon[plrid] = weapon_index;
		g_client_last_weaponstring[plrid] = shotWeapName;
	}
}

public GetWeaponArrayIndex(String:key[])
{
	decl String:strBuf[32];
	
	for(new i = 0; i < NumWeaponsDefined; i++)
	{
		GetArrayString(g_weap_array, i, strBuf, sizeof(strBuf));
		if(StrEqual(key, strBuf)) return i;
	}
	
	return -1;
}

public Action:Event_PlayerDisconnect(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	OnPlayerDisconnect(client);
	return Plugin_Continue;
}

public Action:Event_PlayerDeathPre(Handle:event, const String:name[], bool:dontBroadcast)
{
	LogKillLoc(GetClientOfUserId(GetEventInt(event, "attacker")), GetClientOfUserId(GetEventInt(event, "userid")));
	
	return Plugin_Continue;
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	// "userid"        "short"         // user ID on server          

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client > 0)
	{
		reset_player_stats(client);
	}
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	//"deathflags" "short"
	//"attacker" "short"
	//"customkill" "short"
	//"lives" "short"
	//"attackerteam" "short"
	//"damagebits" "short"
	//"weapon" "string"
	//"weaponid" "short"
	//"userid" "short"
	//"priority" "short"
	//"team" "short"
	//"y" "float"
	//"x" "float"
	//"z" "float"
	//"assister" "short"

	new victim   = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if (attacker == 0 || victim == 0 || attacker == victim)
	{
		return;
	}
	
	new weapon_index = g_client_last_weapon[attacker];
	//decl String:weap[32];
	//GetEventString(event, "weapon", weap, sizeof(weap));
	//PrintToChatAll("WeapID: %d -> %s", weapon_index, weap);
	//new weapon_index2 = GetEventInt(event, "weaponid");
	/*
	PrintToChatAll("======WEAPON (%s)======", g_client_last_weaponstring[attacker]);
	PrintToChatAll("Shots: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_SHOTS]);
	PrintToChatAll("Hits: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_HITS]);
	PrintToChatAll("Kills: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_KILLS]);
	PrintToChatAll("HS: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_HEADSHOTS]);
	PrintToChatAll("TK: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_TEAMKILLS]);
	PrintToChatAll("Dmg: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_DAMAGE]);
	PrintToChatAll("Deaths: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_DEATHS]);
	PrintToChatAll("-------HIT STATS-------");
	PrintToChatAll("General: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_GENERIC]);
	PrintToChatAll("Head: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_HEAD]);
	PrintToChatAll("UTorso: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_CHEST]);
	PrintToChatAll("LTorso: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_STOMACH]);
	PrintToChatAll("LArm: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_LEFTARM]);
	PrintToChatAll("RArm: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_RIGHTARM]);
	PrintToChatAll("LLeg: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_LEFTLEG]);
	PrintToChatAll("RLeg: \t%d", g_weapon_stats[attacker][weapon_index][LOG_HIT_RIGHTLEG]);
	*/
	
	if (weapon_index > -1)
	{
		g_weapon_stats[attacker][weapon_index][LOG_HIT_KILLS]++;
		g_weapon_stats[victim][weapon_index][LOG_HIT_DEATHS]++;
		if (GetClientTeam(attacker) == GetClientTeam(victim))
		{
			g_weapon_stats[attacker][weapon_index][LOG_HIT_TEAMKILLS]++;
		}
	
		//PrintToChat(attacker, "Kills: %d", g_weapon_stats[attacker][weapon_index][LOG_HIT_KILLS]);		
		
		dump_player_stats(victim);
	}
}

public Action:Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	//"userid" "short"
	//"weapon" "string"
	//"hitgroup" "short"
	//"priority" "short"
	//"attacker" "short"
	//"dmg_health" "short"
	//"health" "byte"
	decl String:weapon[MAX_WEAPON_LEN];
	new attacker  = GetClientOfUserId(GetEventInt(event, "attacker"));
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	GetEventString(event, "weapon", weapon, sizeof(weapon));
	
	if (attacker > 0 && attacker != victim)
	{
		new hitgroup  = GetEventInt(event, "hitgroup");
		if (hitgroup < 8)
		{
			hitgroup += LOG_HIT_OFFSET;
		}
		
		
		decl String:clientname[64];
		GetClientName(attacker, clientname, sizeof(clientname));
		

		//new weapon_index = get_weapon_index(weapon, -1 ,false);
		//PrintToChatAll("idx: %d - weapon: %s", weapon_index, weapon);
		new weapon_index = get_weapon_index(weapon);

		if (weapon_index > -1)  {
			g_weapon_stats[attacker][weapon_index][LOG_HIT_HITS]++;
			g_weapon_stats[attacker][weapon_index][LOG_HIT_DAMAGE]  += GetEventInt(event, "dmg_health");
			g_weapon_stats[attacker][weapon_index][hitgroup]++;
			
			if (hitgroup == (HITGROUP_HEAD+LOG_HIT_OFFSET))
			{
				g_weapon_stats[attacker][weapon_index][LOG_HIT_HEADSHOTS]++;
			}
			g_client_last_weapon[attacker] = weapon_index;
			g_client_last_weaponstring[attacker] = weapon;
		}
		
		if (hitgroup == (HITGROUP_HEAD+LOG_HIT_OFFSET))
		{
			LogPlayerEvent(attacker, "triggered", "headshot");
		}
	}
}

public Action:LogEvent(const String:message[])
{
	if(StrContains(message, "killed") > -1 &&
	StrContains(message, "with") > -1 &&
	StrContains(message, "at") > -1)
	{
		new bool:found_weap = false;
		new String:strReassembledKillMsg[512];
		new String:strBuffer[256];
		
		//strings to hold various info
		new String:strWeapName[64];
		new String:strRegexKillerNameFull[64];
		new String:strRegexVictimNameFull[64];
		new String:strRegexKillParameters[256];
		
		//perform dissection of message
		if(kill_regex != INVALID_HANDLE)
		{
			//Get Number of SubStrings
			new numSubStr = MatchRegex(kill_regex, message);
			//PrintToChatAll("[REGEX] Substrings: %d", numSubStr);
			
			if(numSubStr != 5)
			{					
				return Plugin_Continue;
			}

			//Regex SHOULD have 1+4 substrings, but first we need to check that victims/killers are appropriately placed
			
			//SUBSTRING 1: KILLER
			GetRegexSubString(kill_regex, 1, strBuffer, sizeof(strBuffer));
			Format(strRegexKillerNameFull, sizeof(strRegexKillerNameFull), "%s", strBuffer);
			//PrintToChatAll("[REGEX] SubStr1: %s", strRegexKillerNameFull);
			//RETRIEVE KILLER'S WEAPON HERE!
			for (new k=1; k<=MaxClients; k++)
			{
				if(IsClientInGame(k) && IsClientConnected(k))
				{
					GetClientName(k, strBuffer, sizeof(strBuffer));
					if(StrContains(strRegexKillerNameFull, strBuffer) > -1)
					{
						strWeapName = g_client_last_weaponstring[k];
						found_weap = true;
						break;
					}
				}
			}
			
			//SUBSTRING 2: VICTIM
			GetRegexSubString(kill_regex, 2, strBuffer, sizeof(strBuffer));
			Format(strRegexVictimNameFull, sizeof(strRegexVictimNameFull), "%s", strBuffer);
			
			//SUBSTRING 3: WEAPON NAME
			//No need to do anything with weapon name, we are going to replace it
			
			//SUBSTRING 4: PARAMETERS
			GetRegexSubString(kill_regex, 4, strBuffer, sizeof(strBuffer));
			Format(strRegexKillParameters, sizeof(strRegexKillParameters), "%s", strBuffer);
			
			//ASSEMBLE MESSAGE
			if(found_weap)
			{
				Format(strReassembledKillMsg, sizeof(strReassembledKillMsg), "\"%s\" killed \"%s\" with \"%s\" at %s", strRegexKillerNameFull, strRegexVictimNameFull, strWeapName, strRegexKillParameters);
			}
			else
			{
				/*
				GetRegexSubString(kill_regex, 3, strBuffer, sizeof(strBuffer));
				Format(strReassembledKillMsg, sizeof(strReassembledKillMsg), "\"%s\" killed \"%s\" with \"%s\" at %s", strRegexKillerNameFull, strRegexVictimNameFull, strBuffer, strRegexKillParameters);
				*/
				return Plugin_Continue;
			}
			//PrintToChatAll("[REGEX] Reassembled: %s", strReassembledKillMsg);
			LogToGame("%s", strReassembledKillMsg);
			
			return Plugin_Handled;
		}
		else
		{
			PrintToChatAll("[LOGGER] Regex Pattern Failure!");
		}
	}
	else if(StrContains(message, "committed suicide") > -1)
	{
		//perform dissection of message
		if(suicide_regex != INVALID_HANDLE)
		{
			new String:strBuffer[256];
			new String:strWeapName[64];
			new String:strReassembledMsg[512];
			new String:strRegexSuiciderNameFull[64];		
			new bool:found_weap = false;
			//Get Number of SubStrings
			new numSubStr = MatchRegex(suicide_regex, message);
			
			if(numSubStr != 3)
			{		
				return Plugin_Continue;
			}
			
			//SUBSTR 1: Name of the stupid guy who shot himself
			GetRegexSubString(suicide_regex, 1, strBuffer, sizeof(strBuffer));
			Format(strRegexSuiciderNameFull, sizeof(strRegexSuiciderNameFull), "%s", strBuffer);
			
			for (new k=1; k<=MaxClients; k++)
			{
				if(IsClientInGame(k) && IsClientConnected(k))
				{
					GetClientName(k, strBuffer, sizeof(strBuffer));
					if(StrContains(strRegexSuiciderNameFull, strBuffer) > -1)
					{
						strWeapName = g_client_last_weaponstring[k];
						found_weap = true;
						break;
					}
				}
			}
			
			//SUBSTR 2: WEAPON (WE NEED TO REPLACE THIS!);
			if(found_weap)
			{
				Format(strReassembledMsg, sizeof(strReassembledMsg), "\"%s\" commited suicide with \"%s\"", strRegexSuiciderNameFull, strWeapName);
			}
			else
			{
				return Plugin_Continue;
			}
			
			LogToGame("%s", strReassembledMsg);
			
			return Plugin_Handled;
		}
		else
		{
			PrintToChatAll("[LOGGER] Regex Pattern Failure");
		}
	}
	else if(StrContains(message, "obj_captured") > -1) return Plugin_Handled;
	else if(StrContains(message, "obj_destroyed") > -1) return Plugin_Handled;
	
	return Plugin_Continue;
}