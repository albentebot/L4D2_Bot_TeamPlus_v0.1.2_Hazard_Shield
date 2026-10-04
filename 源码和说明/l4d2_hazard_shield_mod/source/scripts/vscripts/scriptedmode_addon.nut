// SPDX-License-Identifier: GPL-3.0-or-later
// Use the supported addon entry, never replace coop.nut or scriptedmode.nut.
if (!("HazardShield" in getroottable()))
    IncludeScript("hazard_shield/core",getroottable());

// Chain mode initialization once. Scripted mode must be active for AllowTakeDamage.
// Initialization order follows Valve's ScriptMode_Init session lifecycle.
// API reference: smilz0/Left4Lib root/scripts/vscripts/scriptedmode_addon.nut.
if (!("HazardShieldInitInstalled" in this)) {
    HazardShieldInitInstalled <- true;
    local originalInit=ScriptMode_Init;
    ScriptMode_Init = function(modename,mapname) {
        local initialized=originalInit.call(this,modename,mapname);
        local supported=modename=="coop" || modename=="realism";
        ::HazardShield.Enabled=false;
        if(!supported) return initialized;
        if(!initialized) {
            // The stock function already created map/mode scopes and loaded
            // common helpers before returning false for a non-scripted mode.
            IncludeScript(mapname+"_"+modename,g_MapScript);
            MergeSessionSpawnTables();MergeSessionStateTables();
            SessionState.MapName <- mapname;SessionState.ModeName <- modename;
            if(!("StartActive" in SessionState)) SessionState.StartActive <- true;
            if(SessionState.StartActive) MergeSessionOptionTables();
            if("SanitizeTable" in this) SanitizeMap(SanitizeTable);
            if("SessionSpawns" in getroottable()) EntSpawn_DoIncludes(::SessionSpawns);
            IncludeScript("sm_stages",g_MapScript);
            foreach(scope in [getroottable(),g_MapScript,g_ModeScript]) AddToScriptHelp(scope);
            ScriptedPrecache();ScriptMode_SystemCall("Precache");
        }
        ::HazardShield.Enabled=true;
        ::HazardShield.Install(g_ModeScript);
        ::HazardShield.Register();
        printl("[HazardShield 0.1.0] loaded; chat: !hs; console: say !hs");
        return true;
    };
}
