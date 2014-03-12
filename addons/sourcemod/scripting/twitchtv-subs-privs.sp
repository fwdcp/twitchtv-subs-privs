#include <sourcemod>
#include <steamtools>
#include <smjansson>

#define PRESSURE_API_URL_FORMAT "http://pressure.fwdcp.net/api/twitchtv/channel/%s/subscription/steam/%s"
#define PRESSURE_API_QUERY_KEY "apikey"

#define VERSION "0.3.0"

new Handle:hChannel = INVALID_HANDLE;
new Handle:hAPIKey = INVALID_HANDLE;
new Handle:hAdminGroup = INVALID_HANDLE;

public Plugin:myinfo = 
{
	name = "TwitchTV Subscribers Privileges from Pressure",
	author = "thesupremecommander",
	description = "Pulls info from Pressure about the subscribers of a certain Twitch channel and their Steam accounts in order to grant them admin privileges (e.g. reserved slots/other donator stuff) on a server.",
	version = VERSION,
	url = "http://pressure.fwdcp.net/"
};

public OnPluginStart()
{
	CreateConVar("twitchtv_subs_privs_version", VERSION, "TwitchTV Subscribers Privileges version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_CHEAT|FCVAR_DONTRECORD);
	hChannel = CreateConVar("twitchtv_subs_privs_channel", "", "the channel from which subscribers are pulled (requires streamer to register on Pressure)", FCVAR_PLUGIN);
	hAPIKey = CreateConVar("twitchtv_subs_privs_pressure_apikey", "", "the Pressure API key required to retrieve subscriber information from Pressure", FCVAR_PLUGIN|FCVAR_PROTECTED);
	hAdminGroup = CreateConVar("twitchtv_subs_privs_admin_group", "Subscribers", "the name of the admin group that subscribers will be put into", FCVAR_PLUGIN|FCVAR_PROTECTED);
	
	AutoExecConfig();
}

public Action:OnClientPreAdminCheck(client)
{
	RunAdminCacheChecks(client);
	
	decl String:sChannel[64];
	GetConVarString(hChannel, sChannel, sizeof(sChannel));
	
	decl String:sCSteamID[64];
	Steam_GetCSteamIDForClient(client, sCSteamID, sizeof(sCSteamID));
	
	decl String:sAPIURL[256];
	Format(sAPIURL, sizeof(sAPIURL), PRESSURE_API_URL_FORMAT, sChannel, sCSteamID);
	
	new HTTPRequestHandle:httprhRequest = Steam_CreateHTTPRequest(HTTPMethod_GET, sAPIURL);
	
	decl String:sAPIKey[64];
	GetConVarString(hAPIKey, sAPIKey, sizeof(sAPIKey));
	
	Steam_SetHTTPRequestGetOrPostParameter(httprhRequest, PRESSURE_API_QUERY_KEY, sAPIKey);
	
	Steam_SendHTTPRequest(httprhRequest, OnRetrieveAPIResult, GetClientUserId(client));
}

public OnRetrieveAPIResult(HTTPRequestHandle:HTTPRequest, bool:requestSuccessful, HTTPStatusCode:statusCode, any:userid)
{
	new client = GetClientOfUserId(userid);
	
	if (statusCode != HTTPStatusCode_OK && statusCode != HTTPStatusCode_NotFound)
	{
		LogError("API returned error.");
		NotifyPostAdminCheck(client);
		return;
	}
	
	new bodySize = Steam_GetHTTPResponseBodySize(HTTPRequest);
	decl String:sAPIResponse[bodySize + 1];
	Steam_GetHTTPResponseBodyData(HTTPRequest, sAPIResponse, bodySize + 1);
	new Handle:hAPIResponse = json_load(sAPIResponse);
	
	decl String:sServerChannel[32];
	GetConVarString(hChannel, sServerChannel, sizeof(sServerChannel));
	decl String:sResponseChannel[32];
	json_object_get_string(hAPIResponse, "channel", sResponseChannel, sizeof(sResponseChannel));
	if (!StrEqual(sServerChannel, sResponseChannel))
	{
		LogError("Response returned not for channel.");
		NotifyPostAdminCheck(client);
		return;
	}
	
	decl String:sClientCSteamID[64];
	Steam_GetCSteamIDForClient(client, sClientCSteamID, sizeof(sClientCSteamID));
	decl String:sResponseCSteamID[64];
	json_object_get_string(hAPIResponse, "steam", sResponseCSteamID, sizeof(sResponseCSteamID));
	if (!StrEqual(sClientCSteamID, sResponseCSteamID))
	{
		LogError("Response returned not for client.");
		NotifyPostAdminCheck(client);
		return;
	}
	
	if (!json_object_get_bool(hAPIResponse, "subscribed"))
	{
		NotifyPostAdminCheck(client);
		return;
	}
	
	decl String:sAdminGroup[32];
	GetConVarString(hAdminGroup, sAdminGroup, sizeof(sAdminGroup));
	
	if (FindAdmGroup(sAdminGroup) == INVALID_GROUP_ID)
	{
		LogError("Unable to find subscriber group.");
		NotifyPostAdminCheck(client);
		return;
	}
	new GroupId:adminGroup = FindAdmGroup(sAdminGroup);
	
	new AdminId:admin;	
	if (GetUserAdmin(client) != INVALID_ADMIN_ID)
	{
		admin = GetUserAdmin(client);
	}
	else
	{
		admin = CreateAdmin();
		SetUserAdmin(client, admin, true);
	}
	
	AdminInheritGroup(admin, adminGroup);
	NotifyPostAdminCheck(client);
}