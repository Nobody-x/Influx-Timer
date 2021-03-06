#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#include <influx/core>
#include <influx/zones>
#include <influx/zones_timer>

#include <msharedutil/arrayvec>


//#define DEBUG


enum
{
    TIMER_ZONE_ID = 0,
    TIMER_RUN_ID,
    
    TIMER_ZONE_TYPE,
    
    TIMER_ENTREF,
    
    TIMER_SIZE
};


ArrayList g_hTimer;


g_iBuildingRunId[INF_MAXPLAYERS];


public Plugin myinfo =
{
    author = INF_AUTHOR,
    url = INF_URL,
    name = INF_NAME..." - Zones | Timer",
    description = "",
    version = INF_VERSION
};

public APLRes AskPluginLoad2( Handle hPlugin, bool late, char[] szError, int error_len )
{
    RegPluginLibrary( INFLUX_LIB_ZONES_TIMER );
}

public void OnPluginStart()
{
    g_hTimer = new ArrayList( TIMER_SIZE );
}

public void OnClientPutInServer( int client )
{
    g_iBuildingRunId[client] = -1;
}

public Action Influx_OnSearchEnd( int runid, float pos[3] )
{
    int i = 0;
    while ( (i = FindByRunId( runid, i )) != -1 )
    {
        if ( g_hTimer.Get( i, TIMER_ZONE_TYPE ) == ZONETYPE_END )
        {
            float mins[3];
            float maxs[3];
            
            Influx_GetZoneMinsMaxs( g_hTimer.Get( i, TIMER_ZONE_ID ), mins, maxs );
            
            Inf_TelePosFromMinsMaxs( mins, maxs, pos );
            
            return Plugin_Stop;
        }
        
        ++i;
    }
    
    return Plugin_Continue;
}

public void Influx_OnPreRunLoad()
{
    g_hTimer.Clear();
}

public void Influx_OnPostZoneLoad()
{
    CheckRuns();
}

stock void CheckRuns()
{
    /*
    char szMap[64], char szPath[PLATFORM_MAX_PATH];
    GetLowerCurrentMap( szMap, sizeof( szMap ) );
    
    BuildPath( Path_SM, szPath, sizeof( szPath ), INFLUX_RUNDIR..."/%s.ini", szPath, szMap );
    
    if ( FileExists( szPath ) ) return;
    */
    
    int num = 0;
    
    int runid;
    
    int len = GetArrayLength_Safe( g_hTimer );
    for ( int i = 0; i < len; i++ )
    {
        if ( (runid = g_hTimer.Get( i, TIMER_RUN_ID )) < 1 )
            continue;
        
        // This run already exists.
        if ( Influx_FindRunById( runid ) != -1 ) continue;
        
        
        ZoneType_t myzonetype = view_as<ZoneType_t>( g_hTimer.Get( i, TIMER_ZONE_TYPE ) );
        
        // Find opposite type with same run id.
        int j = i;
        while ( (j = FindByRunId( runid, j + 1 )) != -1 )
        {
            if ( view_as<ZoneType_t>( g_hTimer.Get( j, TIMER_ZONE_TYPE ) ) == myzonetype ) continue;
            
            
#if defined DEBUG
            PrintToServer( INF_DEBUG_PRE..."Attempting to add run of an id %i!", runid );
#endif
            
            int istart, iend;
            if ( myzonetype == ZONETYPE_START )
            {
                istart = i;
                iend = j;
            }
            else
            {
                istart = j;
                iend = i;
            }
            
            
            float vec[3];
            float start_mins[3], start_maxs[3];
            float end_mins[3], end_maxs[3];
            
            Influx_GetZoneMinsMaxs( g_hTimer.Get( istart, TIMER_ZONE_ID ), start_mins, start_maxs );
            Influx_GetZoneMinsMaxs( g_hTimer.Get( iend, TIMER_ZONE_ID ), end_mins, end_maxs );
            
            
            float yaw;
            
            if ( !Inf_FindTelePos( start_mins, start_maxs, vec, yaw ) )
            {
                // No tele pos was found, make our own.
                Inf_TelePosFromMinsMaxs( start_mins, start_maxs, vec );
                
                yaw = Inf_MinsMaxsToYaw( start_mins, start_maxs, end_mins, end_maxs );
            }
            
            if ( Influx_AddRun( runid, _, vec, yaw ) )
            {
                ++num;
            }
            
            break;
        }
    }
    
    if ( num )
    {
        PrintToServer( INF_CON_PRE..."Added %i run(s) from zone file!", num );
    }
}

public Action Influx_OnZoneLoad( int zoneid, ZoneType_t zonetype, KeyValues kv )
{
    if ( !Inf_IsZoneTypeTimer( zonetype ) ) return Plugin_Continue;
    
    
    decl data[TIMER_SIZE];
    
    data[TIMER_RUN_ID] = kv.GetNum( "run_id", -1 );
    if ( data[TIMER_RUN_ID] < 1 )
    {
        LogError( INF_CON_PRE..."Invalid run id %i!", data[TIMER_RUN_ID] );
        return Plugin_Stop;
    }
    
    data[TIMER_ZONE_ID] = zoneid;
    
    data[TIMER_ZONE_TYPE] = view_as<int>( zonetype );
    data[TIMER_ENTREF] = INVALID_ENT_REFERENCE;
    
    
    g_hTimer.PushArray( data );
    
    return Plugin_Handled;
}

public Action Influx_OnZoneSave( int zoneid, ZoneType_t zonetype, KeyValues kv )
{
    if ( !Inf_IsZoneTypeTimer( zonetype ) ) return Plugin_Continue;
    
    
    int index = FindTimerById( zoneid );
    if ( index == -1 ) return Plugin_Stop;
    
    
    int runid = g_hTimer.Get( index, TIMER_RUN_ID );
    if ( runid < 1 ) return Plugin_Stop;
    
    
    kv.SetNum( "run_id", runid );
    
    return Plugin_Handled;
}

public void Influx_OnZoneSpawned( int zoneid, ZoneType_t zonetype, int ent )
{
    if ( !Inf_IsZoneTypeTimer( zonetype ) ) return;
    
    int index = FindTimerById( zoneid );
    if ( index == -1 ) return;
    
    
    // Cache our ent reference.
    g_hTimer.Set( index, EntIndexToEntRef( ent ), TIMER_ENTREF );
    
    
    Inf_SetZoneProp( ent, g_hTimer.Get( index, TIMER_RUN_ID ) );
    
    // We only store the run id because that's all we need.
    switch ( zonetype )
    {
        case ZONETYPE_START :
        {
            SDKHook( ent, SDKHook_StartTouchPost, E_StartTouchPost_Start );
            SDKHook( ent, SDKHook_EndTouchPost, E_EndTouchPost_Start );
        }
        case ZONETYPE_END :
        {
            SDKHook( ent, SDKHook_StartTouchPost, E_StartTouchPost_End );
        }
    }
}

stock void NameZone( int zoneid, ZoneType_t zonetype, int runid )
{
    char szRun[MAX_RUN_NAME];
    Influx_GetRunName( runid, szRun, sizeof( szRun ) );
    
    char szZone[MAX_ZONE_NAME];
    Inf_ZoneTypeToName( zonetype, szZone, sizeof( szZone ) );
    
    Format( szZone, sizeof( szZone ), "%s %s", szRun, szZone );
    
    Influx_SetZoneName( zoneid, szZone );
}

public void Influx_OnZoneCreated( int client, int zoneid, ZoneType_t zonetype )
{
    if ( !Inf_IsZoneTypeTimer( zonetype ) ) return;
    
    
    int runid = g_iBuildingRunId[client];
    
    decl data[TIMER_SIZE];
    data[TIMER_RUN_ID] = runid;
    data[TIMER_ZONE_ID] = zoneid;
    data[TIMER_ZONE_TYPE] = view_as<int>( zonetype );
    data[TIMER_ENTREF] = INVALID_ENT_REFERENCE;
    
    int ourindex = g_hTimer.PushArray( data );
    
    
    // We already have this run.
    if ( Influx_FindRunById( runid ) != -1 )
    {
        return;
    }
    
    // See if we have a run to add.
    // Loop through zones and find a matching opposite zone with same run id.
    
    int len = g_hTimer.Length;
    
    int other = -1;
    ZoneType_t otherzonetype;
    
    for ( int i = 0; i < len; i++ )
    {
        otherzonetype = g_hTimer.Get( i, TIMER_ZONE_TYPE );
        
        // Same run id but different zone type.
        if (i != ourindex
        &&  g_hTimer.Get( i, TIMER_RUN_ID ) == runid
        &&  otherzonetype != zonetype)
        {
            // Found our match!
            other = i;
            break;
        }
    }
    
    if ( other == -1 ) return;
    
    
    // Get tele position and yaw.
    float vec[3];
    float start_mins[3], start_maxs[3], end_mins[3], end_maxs[3];
    
    int istart, iend;
    if ( zonetype == ZONETYPE_START )
    {
        istart = ourindex;
        iend = other;
    }
    else
    {
        istart = other;
        iend = ourindex;
    }
    
    Influx_GetZoneMinsMaxs( g_hTimer.Get( istart, TIMER_ZONE_ID ), start_mins, start_maxs );
    Influx_GetZoneMinsMaxs( g_hTimer.Get( iend, TIMER_ZONE_ID ), end_mins, end_maxs );
    
    
    float yaw;
    
    if ( !Inf_FindTelePos( start_mins, start_maxs, vec, yaw ) )
    {
        // No tele pos was found, make our own.
        Inf_TelePosFromMinsMaxs( start_mins, start_maxs, vec );
        
        
        yaw = Inf_MinsMaxsToYaw( start_mins, start_maxs, end_mins, end_maxs );
    }
    
    
    int newrunid = Influx_AddRun( runid, "", vec, yaw );
    
    if ( newrunid < 1 )
    {
        LogError( INF_CON_PRE..."Couldn't add new run!" );
        return;
    }
    
    
    g_hTimer.Set( ourindex, newrunid, TIMER_RUN_ID );
    g_hTimer.Set( other, newrunid, TIMER_RUN_ID );
    
    
    // Update other zone's run id property.
    int ent;
    if ( (ent = EntRefToEntIndex( g_hTimer.Get( other, TIMER_ENTREF ) )) > 0 )
    {
        Inf_SetZoneProp( ent, newrunid );
    }
    
    
    // Update our zone names to reflect the change.
    NameZone( g_hTimer.Get( ourindex, TIMER_ZONE_ID ), zonetype, newrunid );
    NameZone( g_hTimer.Get( other, TIMER_ZONE_ID ), otherzonetype, newrunid );
}

public void Influx_OnZoneDeleted( int zoneid, ZoneType_t zonetype )
{
    if ( !Inf_IsZoneTypeTimer( zonetype ) ) return;
    
    
    int index = FindTimerById( zoneid );
    if ( index != -1 )
    {
        g_hTimer.Erase( index );
    }
    else
    {
        LogError( INF_CON_PRE..."Couldn't find timer zone with id %i to delete!", zoneid );
    }
}

public Action Influx_OnZoneBuildAsk( int client, ZoneType_t zonetype )
{
    if ( !Inf_IsZoneTypeTimer( zonetype ) ) return Plugin_Continue;
    
    
    g_iBuildingRunId[client] = -1;
    
    
    ArrayList runs = Influx_GetRunsArray();
    int len = GetArrayLength_Safe( runs );
    if ( len < 1 ) return Plugin_Continue;
    
    
    // Show a menu to clarify for which run do we want to build this zone for.
    
    char szZone[32];
    char szRun[MAX_RUN_NAME];
    char szDisplay[32], szInfo[32];
    
    Inf_ZoneTypeToName( zonetype, szZone, sizeof( szZone ) );
    
    
    Menu menu = new Menu( Hndlr_CreateZone_SelectRun );
    menu.SetTitle( "Which run do you want to create '%s' for?\n ", szZone );
    
    
    int timerchar = TimerToChar( zonetype );
    
    FormatEx( szInfo, sizeof( szInfo ), "%c-1", timerchar );
    menu.AddItem( szInfo, "New Run" );
    
    
    int runid;
    for ( int i = 0; i < len; i++ )
    {
        runs.GetString( i, szRun, sizeof( szRun ) );
        runid = runs.Get( i, RUN_ID );
        
        
        FormatEx( szInfo, sizeof( szInfo ), "%c%i", timerchar, runid );
        FormatEx( szDisplay, sizeof( szDisplay ), "%s (ID: %i)", szRun, runid );
        
        menu.AddItem( szInfo, szDisplay );
    }
    
    menu.Display( client, MENU_TIME_FOREVER );
    
    return Plugin_Stop;
}

public int Hndlr_CreateZone_SelectRun( Menu oldmenu, MenuAction action, int client, int index )
{
    MENU_HANDLE( oldmenu, action )
    
    
    char szInfo[32];
    if ( !GetMenuItem( oldmenu, index, szInfo, sizeof( szInfo ) ) ) return 0;
    
    
    ZoneType_t zonetype = TimerCharToType( szInfo[0] );
    int runid = StringToInt( szInfo[1] );
    
    if ( !Inf_IsZoneTypeTimer( zonetype ) ) return 0;
    
    
    // Go through all of our zones and see if our wanted type already exists.
    int izone = -1;
    
    if ( runid != -1 )
    {
        int len = g_hTimer.Length;
        for ( int i = 0; i < len; i++ )
        {
            if (g_hTimer.Get( i, TIMER_RUN_ID ) == runid
            &&  view_as<ZoneType_t>( g_hTimer.Get( i, TIMER_ZONE_TYPE ) ) == zonetype )
            {
                izone = i;
                break;
            }
        }
    }
    
    // If one already exists, show a warning menu.
    if ( izone != -1 )
    {
        char szZone[MAX_ZONE_NAME];
        
        char szType[32];
        Inf_ZoneTypeToName( zonetype, szType, sizeof( szType ) );
        
        int zoneid = g_hTimer.Get( izone, TIMER_ZONE_ID );
        
        Influx_GetZoneName( zoneid, szZone, sizeof( szZone ) );
        
        
        int timerchar = TimerToChar( zonetype );
        
        Menu menu = new Menu( Hndlr_CreateZone_SelectRun_Confirm );
        
        menu.SetTitle( "This zone already exists! %s (%s)\n ",
            szZone,
            szType );
        
        FormatEx( szInfo, sizeof( szInfo ), "%c%i", timerchar, runid );
        
        menu.AddItem( szInfo, "Create a new instance (keep both) (multiple starts/ends)" );
        menu.AddItem( szInfo, "Replace existing one(s)\n " );
        menu.AddItem( "", "Cancel" );
        
        menu.ExitButton = false;
        
        menu.Display( client, MENU_TIME_FOREVER );
    }
    else // Start to create otherwise.
    {
        StartToBuild( client, zonetype, runid );
    }
    
    return 0;
}

public int Hndlr_CreateZone_SelectRun_Confirm( Menu menu, MenuAction action, int client, int index )
{
    MENU_HANDLE( menu, action )
    
    
    char szInfo[32];
    if ( !GetMenuItem( menu, index, szInfo, sizeof( szInfo ) ) ) return 0;
    
    
    ZoneType_t zonetype = TimerCharToType( szInfo[0] );
    int runid = StringToInt( szInfo[1] );
    
    
    bool bValidInfo = ( runid != -1 && Inf_IsZoneTypeTimer( zonetype ) && Influx_FindRunById( runid ) != -1 );
    
    switch ( index )
    {
        case 0 : // New instance
        {
            if ( bValidInfo )
            {
                StartToBuild( client, zonetype, runid );
            }
        }
        case 1 : // Replace existing ones.
        {
            if ( bValidInfo )
            {
                int len = g_hTimer.Length;
                for ( int i = 0; i < len; i++ )
                {
                    if (g_hTimer.Get( i, TIMER_RUN_ID ) == runid
                    &&  g_hTimer.Get( i, TIMER_ZONE_TYPE ) == zonetype )
                    {
                        int zoneid = g_hTimer.Get( i, TIMER_ZONE_ID );
                        
                        // HACK - Will call OnZoneDeleted which in turn would delete our index anyway.
                        g_hTimer.Erase( i );
                        i = 0;
                        len = g_hTimer.Length;
                        
                        
                        Influx_DeleteZone( zoneid );
                    }
                }
                
                StartToBuild( client, zonetype, runid );
            }
        }
    }
    
    Inf_OpenZoneMenu( client );
    
    return 0;
}

stock void StartToBuild( int client, ZoneType_t zonetype, int runid = -1 )
{
    g_iBuildingRunId[client] = runid;
    
    
    char szName[MAX_ZONE_NAME];
    
    Inf_ZoneTypeToName( zonetype, szName, sizeof( szName ) );
    
    if ( Influx_FindRunById( runid ) != -1 )
    {
        char szRun[MAX_RUN_NAME];
        Influx_GetRunName( runid, szRun, sizeof( szRun ) );
        
        Format( szName, sizeof( szName ), "%s %s", szRun, szName );
    }
    
    
    Influx_BuildZone( client, zonetype, szName );
    
    Inf_OpenZoneMenu( client );
}

public void E_StartTouchPost_Start( int ent, int activator )
{
    if ( !IS_ENT_PLAYER( activator ) ) return;

    if ( !IsPlayerAlive( activator ) ) return;
    
    
    Influx_ResetTimer( activator, Inf_GetZoneProp( ent ) );
}

public void E_EndTouchPost_Start( int ent, int activator )
{
    if ( !IS_ENT_PLAYER( activator ) ) return;
    
    if ( !IsPlayerAlive( activator ) ) return;
    
    
    Influx_StartTimer( activator, Inf_GetZoneProp( ent ) );
}

public void E_StartTouchPost_End( int ent, int activator )
{
    if ( !IS_ENT_PLAYER( activator ) ) return;
    
    if ( !IsPlayerAlive( activator ) ) return;
    
    
    Influx_FinishTimer( activator, Inf_GetZoneProp( ent ) );
}

stock int FindTimerById( int id )
{
    int len = g_hTimer.Length;
    for ( int i = 0; i < len; i++ )
    {
        if ( g_hTimer.Get( i, TIMER_ZONE_ID ) == id )
        {
            return i;
        }
    }
    
    return -1;
}

stock int FindByRunId( int id, int startindex = 0 )
{
    int len = g_hTimer.Length;
    
    if ( startindex < 0 ) startindex = 0;
    
    for ( int i = startindex; i < len; i++ )
    {
        if ( g_hTimer.Get( i, TIMER_RUN_ID ) == id )
        {
            return i;
        }
    }
    
    return -1;
}

stock int TimerToChar( ZoneType_t zonetype )
{
    return ( zonetype == ZONETYPE_START ) ? 's' : 'e';
}

stock ZoneType_t TimerCharToType( int c )
{
    if ( c == 's' )
    {
        return ZONETYPE_START;
    }
    else if ( c == 'e' )
    {
        return ZONETYPE_END;
    }
    
    return ZONETYPE_INVALID;
}