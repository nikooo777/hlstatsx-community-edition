#include <sourcemod>
#include <hlxce-sm-api>

public Plugin:myinfo = 
{
	name = "HLXCE SM API TEST PLUGIN",
	author = "psychoinc",
	description = "",
	version = "0.1",
	url = "http://www.hlxcommunity.com"
};


public OnPluginStart()
{
	RegServerCmd("hlxapi_test", callback);
}

public Action:callback(args)
{
	decl String:arrrrg[10];
	GetCmdArg(1, arrrrg, sizeof(arrrrg));
	new client = StringToInt(arrrrg);
	
	if (HLXCE_IsClientReady(client))
	{
		HLXCE_GetPlayerData(client);
	}
	else
	{
		LogToGame("[SAMPLE] Client %d is not hlx-ready yet", client);
	}
	
	return Plugin_Handled;
}

public HLXCE_OnClientReady(client)
{
	LogToGame("[SAMPLE] Received OnClientReady for %N", client);
}


public HLXCE_OnGotPlayerData(client, const PData[HLXCE_PlayerData])
{
	LogToGame("[SAMPLE] RECEIVING GOT CLIENT DATA FWD");
	LogToGame("[SAMPLE] %N is on rank %d with %d points and %d kills (%.3f%%)!", client, PData[PData_Rank], PData[PData_Skill], PData[PData_Kills], FloatDiv(Float:(PData[PData_Kills]),Float:((PData[PData_Deaths]==0)?1:PData[PData_Deaths])));
}