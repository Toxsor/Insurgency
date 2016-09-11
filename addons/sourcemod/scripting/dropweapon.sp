//(C) 2014 Jared Ballou <sourcemod@jballou.com>
//Released under GPLv3

#pragma semicolon 1
#pragma unused cvarVersion
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <insurgency>
#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL    "http://ins.jballou.com/sourcemod/update-dropweapon.txt"

#define PLUGIN_AUTHOR "Jared Ballou (jballou)"
#define PLUGIN_DESCRIPTION "Adds a drop command"
#define PLUGIN_NAME "[INS] Drop Weapon"
#define PLUGIN_VERSION "0.0.2"
#define PLUGIN_URL "http://jballou.com/"
#define PLUGIN_WORKING "0"

public Plugin:myinfo = {
	name		= PLUGIN_NAME,
	author		= PLUGIN_AUTHOR,
	description	= PLUGIN_DESCRIPTION,
	version		= PLUGIN_VERSION,
	url		= PLUGIN_URL
};

#define EF_NODRAW 32

new Handle:cvarVersion = INVALID_HANDLE; // version cvar!
new Handle:cvarEnabled = INVALID_HANDLE; // are we enabled?

public OnPluginStart()
{
	cvarVersion = CreateConVar("sm_dropweapon_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_NOTIFY | FCVAR_PLUGIN | FCVAR_DONTRECORD);
	cvarEnabled = CreateConVar("sm_dropweapon_enabled", PLUGIN_WORKING, "sets whether weapon dropping is enabled", FCVAR_NOTIFY | FCVAR_PLUGIN);
	RegConsoleCmd("drop_weapon", Command_Drop_Weapon);
	AddCommandListener(CmdLstnr_Drop, "drop");
	//HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	PrintToServer("[DROPWEAPON] Started!");
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public Action:CmdLstnr_Drop(client, const String:command[], argc)
{
	if(!client)
		return Plugin_Continue;
	return Drop_Weapon(client);
}

public OnLibraryAdded(const String:name[]) {
	if (StrEqual(name, "updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}
}

public Action:Command_Drop_Weapon(client, args) {
	return Drop_Weapon(client);
}
public Action:Drop_Weapon(client) {
	//PrintToServer("[DROPWEAPON] Check_Ammo!");
	// If disabled, return
	if (!GetConVarBool(cvarEnabled)) {
		return Plugin_Continue;
	}
	// If no active weapon, return
	new m_hActiveWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
	if (m_hActiveWeapon < 0) {
		return Plugin_Continue;
	}
	// Do not drop knives
	decl String:strBuf[32];
	GetEdictClassname(m_hActiveWeapon, strBuf, sizeof(strBuf));
	if(StrEqual("weapon_knife", strBuf) || StrEqual("weapon_kabar", strBuf) || StrEqual("weapon_gurkha", strBuf) || StrEqual("weapon_kukri", strBuf)) {
		return Plugin_Continue;
	}
	// Drop weapon
	// Create weapon entity
	CreateWorldWeapon(client,m_hActiveWeapon);

	//SDKHooks_DropWeapon(client,m_hActiveWeapon);
	return Plugin_Continue;
}
CreateWorldWeapon(client,weapon) {
	decl String:strBuf[32];
	GetEdictClassname(weapon, strBuf, sizeof(strBuf));
	new ent = CreateEntityByName(strBuf);
	new Float:cllocation[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", cllocation);
	cllocation[2]+=20;
	PrintToServer("[DROPWEAPON] dropping %s from %N ent %d loc %f %f %f",strBuf,client,ent,cllocation[0],cllocation[1],cllocation[2]);
	char sModel[PLATFORM_MAX_PATH];
	int m_iWorldModelIndex = GetEntProp(weapon, Prop_Send, "m_iWorldModelIndex");
	int m_fEffects = GetEntProp(weapon, Prop_Send, "m_fEffects");
	int m_iState = GetEntProp(weapon, Prop_Send, "m_iState");
//	ModelIndexToString(m_iWorldModelIndex, sModel, sizeof(sModel));

	//SetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex", StringToInt(index));

	// Not owned
	SetEntProp(ent, Prop_Send, "m_iState", 0);

	m_fEffects = GetEntProp(ent, Prop_Send, "m_fEffects");
	m_fEffects |= EF_NODRAW;
	SetEntProp(ent, Prop_Send, "m_fEffects", m_fEffects);

	TeleportEntity(ent,cllocation, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(ent);
	ActivateEntity(ent);
	PrintToServer("[DROP] m_iWorldModelIndex %d m_fEffects %d m_iState %d",m_iWorldModelIndex,m_fEffects,m_iState);
	//SetEntProp(ent, Prop_Send, "m_iExtraPrimaryAmmo", ammo);
	//SetEntProp(ent, Prop_Send, "m_iClip1", clip);
}
		
