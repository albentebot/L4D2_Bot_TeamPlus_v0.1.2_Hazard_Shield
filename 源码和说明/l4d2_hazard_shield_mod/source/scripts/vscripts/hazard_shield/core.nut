// SPDX-License-Identifier: GPL-3.0-or-later
// Pre-damage protection, not player_hurt health refunds.
::HazardShield <- {
    Version="0.1.0", Enabled=false, Calls=0, Blocked=0, Scope=null, Wrapper=null,
    Conflict=false
};
::HazardShield.Class <- function(e) {
    try {if(e!=null && e.IsValid()) return e.GetClassname();} catch(err) {}
    return "";
};
::HazardShield.Protected <- function(d) {
    if(!Enabled || !("Victim" in d) || Class(d.Victim)!="player") return false;
    try {if(!d.Victim.IsSurvivor()) return false;} catch(err) {return false;}
    if(!("DamageType" in d) || d.DamageType<0) return false;
    local bits=d.DamageType;
    // Keep impact damage, including mixed blast+burn and incendiary bullet impacts.
    local impact=1|2|4|16|32|64|128; // crush, bullet, slash, vehicle, fall, blast, club
    if((bits & impact)!=0) return false;
    local inflictor=("Inflictor" in d)?Class(d.Inflictor):"";
    // L4D2 spit can carry DMG_RADIATION. Identify its entity rather than block
    // every radiation event, which third-party maps may use for other hazards.
    if(inflictor=="insect_swarm" || inflictor=="spitter_projectile") return true;
    return (bits & (8|1048576|2097152))!=0; // DMG_BURN | DMG_ACID | DMG_SLOWBURN
};
::HazardShield.Filter <- function(d) {
    Calls++;
    if(!Protected(d)) return true;
    d.DamageDone=0;Blocked++;return false;
};
::HazardShield.Install <- function(scope) {
    if(scope==Scope) {
        // Never repeatedly wrap another addon that may itself wrap us.
        Conflict=!("AllowTakeDamage" in scope) || scope.AllowTakeDamage!=Wrapper;
        if(Conflict) printl("[HazardShield WARNING] Damage hook changed by another script; protection may be unavailable.");
        return;
    }
    local previous=("AllowTakeDamage" in scope)?scope.AllowTakeDamage:null;
    local capturedScope=scope;
    Wrapper=function(d) {
        // Preserve the existing callback's receiver, edits, and rejection.
        local result=true;
        if(previous!=null) result=previous.call(capturedScope,d);
        local allow=::HazardShield.Filter(d);
        return result==false ? false : allow;
    };
    Scope=scope;scope.AllowTakeDamage <- Wrapper;Conflict=false;
};
::HazardShield.Status <- function(player=null) {
    if(Enabled && Scope!=null) Conflict=!("AllowTakeDamage" in Scope) || Scope.AllowTakeDamage!=Wrapper;
    local state=!Enabled?"当前模式未启用":(Conflict?"伤害接口被覆盖，请检查其他Mod":"伤害接口已安装");
    local msg="[HazardShield] "+Version+" / "+state+" / 已拦截 "+Blocked+" 次 / 已收到 "+Calls+" 次伤害回调";
    printl(msg);ClientPrint(player,3,msg);
};
::HazardShield.OnGameEvent_player_say <- function(p) {
    if(!("text" in p) || strip(p.text)!="!hs") return;
    local speaker=null;
    while((speaker=Entities.FindByClassname(speaker,"player"))!=null)
        if("userid" in p && speaker.GetPlayerUserId()==p.userid) {Status(speaker);return;}
};
::HazardShield.OnGameEvent_round_start <- function(p) {
    if(Enabled && Scope!=null) Install(Scope);
    if(Enabled) Status();
};
::HazardShield.Register <- function() {
    __CollectEventCallbacks(this,"OnGameEvent_","GameEventCallbacks",RegisterScriptGameEventListener);
};
