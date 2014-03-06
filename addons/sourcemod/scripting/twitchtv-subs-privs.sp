#include <sourcemod>
#include <steamtools>
#include <smjansson>

#define PRESSURE_API_URL_FORMAT "http://pressure.fwdcp.net/api/twitchtv/channel/%s/subscriptions/steamids"
#define PRESSURE_API_QUERY_KEY "apikey"

#define VERSION "0.2.0"

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

public OnRebuildAdminCache(AdminCachePart:part)
{
	if (part == AdminCache_Admins) {
		decl String:sChannel[64];
		GetConVarString(hChannel, sChannel, sizeof(sChannel));
		
		decl String:sAPIURL[256];
		Format(sAPIURL, sizeof(sAPIURL), PRESSURE_API_URL_FORMAT, sChannel);
		
		new HTTPRequestHandle:httprhRequest = Steam_CreateHTTPRequest(HTTPMethod_GET, sAPIURL);
		
		decl String:sAPIKey[64];
		GetConVarString(hAPIKey, sAPIKey, sizeof(sAPIKey));
		
		Steam_SetHTTPRequestGetOrPostParameter(httprhRequest, PRESSURE_API_QUERY_KEY, sAPIKey);
		
		Steam_SendHTTPRequest(httprhRequest, OnRetrieveAPIResult);
	}
}

public OnRetrieveAPIResult(HTTPRequestHandle:HTTPRequest, bool:requestSuccessful, HTTPStatusCode:statusCode)
{
	if (statusCode != HTTPStatusCode_OK) {
		LogError("Unable to load admins.");
		return;
	}
		
	decl String:sAdminGroup[32];
	GetConVarString(hAdminGroup, sAdminGroup, sizeof(sAdminGroup));
	
	if (FindAdmGroup(sAdminGroup) == INVALID_GROUP_ID) {
		LogError("Unable to find subscriber group.");
		return;
	}
	new GroupId:adminGroup = FindAdmGroup(sAdminGroup);
	
	new bodySize = Steam_GetHTTPResponseBodySize(HTTPRequest);
	
	decl String:sAPIResponse[bodySize + 1];
	
	Steam_GetHTTPResponseBodyData(HTTPRequest, sAPIResponse, bodySize + 1);
	
	new Handle:hAPIResponse = json_load(sAPIResponse);
	
	decl String:sServerChannel[32];
	GetConVarString(hChannel, sServerChannel, sizeof(sServerChannel));
	
	decl String:sResponseChannel[32];
	json_object_get_string(hAPIResponse, "channel", sResponseChannel, sizeof(sResponseChannel));
	
	if (!StrEqual(sServerChannel, sResponseChannel)) {
		LogError("Response returned not for channel.");
		return;
	}
	
	new Handle:hSteamIDList = json_object_get(hAPIResponse, "users");
	
	for (new iElement = 0; iElement < json_array_size(hSteamIDList); iElement++) {
		new Handle:hSubscriber = json_array_get(hSteamIDList, iElement);
		
		decl String:sSubscriberSteamID[32];
		json_object_get_string(hSubscriber, "steamid", sSubscriberSteamID, sizeof(sSubscriberSteamID));
		
		new AdminId:subscriber;
		
		if (FindAdminByIdentity(AUTHMETHOD_STEAM, sSubscriberSteamID) != INVALID_ADMIN_ID) {
			subscriber = FindAdminByIdentity(AUTHMETHOD_STEAM, sSubscriberSteamID);
		}
		else {
			decl String:sSubscriberName[32];
			json_object_get_string(hSubscriber, "name", sSubscriberName, sizeof(sSubscriberName));
			
			subscriber = CreateAdmin(sSubscriberName);
			BindAdminIdentity(subscriber, AUTHMETHOD_STEAM, sSubscriberSteamID);
		}
		
		AdminInheritGroup(subscriber, adminGroup);
	}
}