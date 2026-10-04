// Bot TeamPlus MOD 0.1.2 -- GPL-3.0-or-later.
// Standalone implementation. No SourceMod, Left4DHooks or third-party script library.
::BTPMod <- {
    Version = "0.1.2", Active = false, Thinker = null, States = {}, Players = [], Commons = [], Hazards = [],
    Rules = [], Buttons = {}, Failures = {}, Trades = [], HumanButtons = {}, Cooldowns = {},
    SavedCvars = {}, NextScan = 0.0, ThrowAfter = 0.0, TradeAfter = 0.0, Sequence = 0, Errors = 0,
    NextEventCheck = 0.0, AnnounceAt = 0.0, Announced = false,
    Settings = {
        combat = 1, rescue = 1, revive_seconds = 2.0, defib = 1, upgrade = 1,
        throw_mask = 3, throw_count = 8, share = 1, share_health = 100,
        avoid_spit = 0, planb = 2, gas = 1, task_range = 1600, debug = 0
    },
    Limits = {
        combat = [0,1], rescue = [0,1], revive_seconds = [0,10], defib = [0,1], upgrade = [0,1],
        throw_mask = [0,7], throw_count = [3,100], share = [0,1], share_health = [1,100],
        avoid_spit = [0,1], planb = [0,2], gas = [0,1], task_range = [200,5000], debug = [0,1]
    }
};

::BTPMod.Valid <- function(e) { return e != null && e.IsValid(); };
::BTPMod.Prop <- function(e, n, fallback = 0) { return Valid(e) && NetProps.HasProp(e,n) ? NetProps.GetPropInt(e,n) : fallback; };
::BTPMod.Handle <- function(e,n) { return Valid(e) && NetProps.HasProp(e,n) ? NetProps.GetPropEntity(e,n) : null; };
::BTPMod.Survivor <- function(p, alive = true) { return Valid(p) && p.GetClassname() == "player" && p.IsSurvivor() && (!alive || (!p.IsDead() && !p.IsDying())); };
::BTPMod.Able <- function(p) { return Survivor(p) && !p.IsIncapacitated() && !p.IsHangingFromLedge() && !p.IsDominatedBySpecialInfected(); };
::BTPMod.Bot <- function(p) { return Survivor(p) && IsPlayerABot(p); };
::BTPMod.Item <- function(p, slot) { local t={}; GetInvTable(p,t); local k="slot"+slot; return k in t && Valid(t[k]) ? t[k] : null; };
::BTPMod.Class <- function(e,n) { return Valid(e) && e.GetClassname() == n; };
::BTPMod.Distance <- function(a,b) { return (a.GetOrigin()-b.GetOrigin()).Length(); };
::BTPMod.Health <- function(p) { return p.GetHealth()+p.GetHealthBuffer(); };
::BTPMod.Owned <- function(e) { return Valid(Handle(e,"m_hOwnerEntity")) || Valid(Handle(e,"m_hOwner")) || Valid(e.GetMoveParent()); };
::BTPMod.Busy <- function(p) {
    return Valid(Handle(p,"m_reviveTarget")) || Valid(Handle(p,"m_useActionTarget")) || Prop(p,"m_usingMountedWeapon") || Prop(p,"m_usingMountedGun");
};
::BTPMod.Note <- function(p,text) { ClientPrint(p,3,"\x04[TeamPlus]\x01 "+text); };
::BTPMod.Status <- function(player=null) {
    Note(player,"MOD "+Version+" / "+(Active ? "运行中" : "已停用")+" / 地图规则 "+Rules.len()+" / 酸火避让 "+(Settings.avoid_spit?"开":"关"));
};
::BTPMod.FindSpeaker <- function(userid) {
    local id=0;try {id=userid.tointeger();} catch(err) {return null;}
    if(id<=0) return null;
    // Do not rely on GetPlayerFromUserID being available in the root script scope.
    local p=null;while((p=Entities.FindByClassname(p,"player"))!=null)
        if(Valid(p) && p.GetPlayerUserId()==id) return p;
    return null;
};
::BTPMod.EnsureEvents <- function() {
    // Other map/addon initialization can clear the callback table after our entry runs.
    // The engine collector deduplicates this scope; it does not replace other listeners.
    __CollectEventCallbacks(::BTPMod,"OnGameEvent_","GameEventCallbacks",RegisterScriptGameEventListener);
};
::BTPMod.Log <- function(text) { if (Settings.debug) printl("[TeamPlus] "+text); };
::BTPMod.Input <- function(s, force=0, disable=0) {
    // Only remove bits introduced by this addon, including after a human takes over.
    if (!Valid(s.bot)) return;
    local f=Prop(s.bot,"m_afButtonForced"), d=Prop(s.bot,"m_afButtonDisabled");
    f=f & ~s.forced; d=d & ~s.disabled;
    s.forced=force & ~f; s.disabled=disable & ~d;
    NetProps.SetPropInt(s.bot,"m_afButtonForced",f|force);
    NetProps.SetPropInt(s.bot,"m_afButtonDisabled",d|disable);
};
::BTPMod.State <- function(bot) {
    local id=bot.GetPlayerUserId();
    if (!(id in States) || States[id].bot != bot) {
        States[id] <- {bot=bot, job=null, forced=0, disabled=0, move=false, nextMove=0.0,
            nextWork=0.0, nextShare=0.0, nextThrow=0.0, revive=null, reviveAt=0.0, locked=[]};
    }
    return States[id];
};
::BTPMod.Aim <- function(bot,point,pitch=0.0) {
    local d=point-bot.EyePosition();
    bot.SnapEyeAngles(QAngle(-atan2(d.z,sqrt(d.x*d.x+d.y*d.y))*57.2957795+pitch,atan2(d.y,d.x)*57.2957795,0));
};
::BTPMod.Trace <- function(start,finish,ignore=null) {
    local tr={start=start,end=finish,ignore=ignore,mask=1174421507}; TraceLine(tr); return tr;
};
::BTPMod.Visible <- function(p,e,point=null) {
    if (!Valid(e)) return false;
    local tr=Trace(p.EyePosition(),point==null ? e.GetCenter() : point,p);
    return !("hit" in tr) || !tr.hit || ("enthit" in tr && tr.enthit==e) || ("fraction" in tr && tr.fraction>0.98);
};
::BTPMod.Reach <- function(bot,point) {
    if ((bot.GetOrigin()-point).Length()>Settings.task_range || Danger(point)) return false;
    local a=bot.GetLastKnownArea(), b=NavMesh.GetNearestNavArea(point,180.0,true,true);
    return a!=null && b!=null && NavMesh.NavAreaBuildPath(a,b,point,Settings.task_range*1.6,2,false);
};
::BTPMod.LockWeapons <- function(s) {
    if(s.locked.len()>0) return;
    // The stock AI otherwise switches to a gun and drops the carried can.
    foreach(slot in [0,1]) {
        local w=Item(s.bot,slot);
        if(w!=null && NetProps.HasProp(w,"m_hOwner") && Handle(w,"m_hOwner")==s.bot) {
            s.locked.append({weapon=w,slot=slot,owner=s.bot});
            NetProps.SetPropEntity(w,"m_hOwner",null);
        }
    }
};
::BTPMod.UnlockWeapons <- function(s) {
    foreach(entry in s.locked) {
        // Never reassign a weapon that was dropped or acquired by another player.
        if(Valid(entry.weapon) && Valid(s.bot) && Item(s.bot,entry.slot)==entry.weapon && Handle(entry.weapon,"m_hOwner")==null)
            NetProps.SetPropEntity(entry.weapon,"m_hOwner",s.bot);
    }
    s.locked.clear();
};
::BTPMod.Cancel <- function(s, failed=false, keepCarry=false) {
    local j=s.job;
    Input(s);
    UnlockWeapons(s);
    if (Valid(s.bot) && IsPlayerABot(s.bot)) {
        if (s.move) CommandABot({cmd=3,bot=s.bot});
        if (j!=null && (j.kind=="gas" || j.kind=="deliver") && !keepCarry && Class(Item(s.bot,5),"weapon_gascan")) s.bot.DropItem("weapon_gascan");
        if (j!=null && (j.kind=="throw" || j.kind=="defib" || j.kind=="upgrade")) {
            local gun=Item(s.bot,0); if (gun==null) gun=Item(s.bot,1);
            if (gun!=null) s.bot.SwitchToItem(gun.GetClassname());
        }
    }
    if (failed && j!=null && Valid(j.target)) Failures[j.target.GetEntityIndex()] <- {ent=j.target,until=Time()+25.0};
    s.job=null; s.move=false; s.nextWork=Time()+(failed ? 3.0 : 0.6);
};
::BTPMod.Begin <- function(s,kind,target,seconds=22.0,stand=null,rule=null,item=null) {
    Cancel(s,false,kind=="deliver");
    s.job={kind=kind,target=target,until=Time()+seconds,at=0.0,best=999999.0,progress=Time(),stand=stand,rule=rule,item=item,phase=0};
    if(kind=="deliver") LockWeapons(s);
    s.nextMove=0.0; Log(s.bot.GetPlayerName()+" -> "+kind);
};
::BTPMod.Move <- function(s,point) {
    if (Time()<s.nextMove) return;
    CommandABot({cmd=1,bot=s.bot,pos=point}); s.move=true; s.nextMove=Time()+0.6;
};
::BTPMod.Free <- function(e,s=null) {
    if (!Valid(e)) return false;
    local idx=e.GetEntityIndex();
    if (idx in Failures && Failures[idx].ent==e && Failures[idx].until>Time()) return false;
    foreach (other in States) if (other!=s && other.job!=null && other.job.target==e) return false;
    foreach (t in Trades) if (t.a==e || t.b==e) return false;
    return true;
};
::BTPMod.Scan <- function() {
    Players.clear(); Commons.clear(); Hazards.clear();
    local e=null;
    while ((e=Entities.FindByClassname(e,"player"))!=null) Players.append(e);
    e=null; while ((e=Entities.FindByClassname(e,"infected"))!=null && Commons.len()<256) if (e.GetHealth()>0) Commons.append(e);
    foreach (cls in ["insect_swarm","inferno"]) {
        e=null; while ((e=Entities.FindByClassname(e,cls))!=null && Hazards.len()<64) Hazards.append(e);
    }
    local remove=[];
    foreach(id,s in States) if (!Bot(s.bot)) { Cancel(s); remove.append(id); }
    foreach(id in remove) delete States[id];
    remove=[]; foreach(id,f in Failures) if (!Valid(f.ent) || f.until<=Time()) remove.append(id);
    foreach(id in remove) delete Failures[id];
};
::BTPMod.Danger <- function(point) {
    if (!Settings.avoid_spit) return false;
    foreach(e in Hazards) {
        if (!Valid(e)) continue;
        local origin=e.GetOrigin(), count=Prop(e,"m_fireCount");
        if (count>0 && NetProps.HasProp(e,"m_fireXDelta") && NetProps.HasProp(e,"m_fireYDelta") && NetProps.HasProp(e,"m_fireZDelta")) {
            local size=NetProps.GetPropArraySize(e,"m_fireXDelta"); if(count>size) count=size;
            for(local i=0;i<count;i++) {
                if (NetProps.HasProp(e,"m_bFireIsBurning") && !NetProps.GetPropIntArray(e,"m_bFireIsBurning",i)) continue;
                local p=origin+Vector(NetProps.GetPropIntArray(e,"m_fireXDelta",i),NetProps.GetPropIntArray(e,"m_fireYDelta",i),NetProps.GetPropIntArray(e,"m_fireZDelta",i));
                if (fabs(point.z-p.z)<70.0 && (point-p).Length()<100.0) return true;
            }
        } else if (fabs(point.z-origin.z)<80.0 && (point-origin).Length()<230.0) return true;
    }
    return false;
};
::BTPMod.Enemy <- function(s) {
    local best=-999999.0,target=null,bot=s.bot;
    foreach(e in Players) {
        if (!Valid(e) || e.IsSurvivor() || e.IsDead() || e.IsDying() || e.IsGhost()) continue;
        local d=Distance(bot,e); if (d>2000.0 || !Visible(bot,e)) continue;
        local score=1800.0-d;
        foreach(p in Players) if(Survivor(p) && p.GetSpecialInfectedDominatingMe()==e) { score+=5000.0; break; }
        if(e.GetZombieType()==1 || e.GetZombieType()==4) score+=500.0;
        if(e.GetZombieType()==8) score-=400.0;
        if(d<140.0) score+=1000.0;
        if(score>best) { best=score;target=e; }
    }
    foreach(e in Commons) {
        if(!Valid(e) || e.GetHealth()<=0) continue;
        local d=Distance(bot,e); if(d>750.0) continue;
        local score=650.0-d+(d<100.0 ? 1900.0 : 0.0);
        if(score>best && Visible(bot,e)) { best=score; target=e; }
    }
    return target;
};
::BTPMod.Threats <- function(bot,radius) {
    local n=0;
    foreach(e in Commons) if(Valid(e) && e.GetHealth()>0 && Distance(bot,e)<radius && Visible(bot,e)) n++;
    foreach(e in Players) if(Valid(e) && !e.IsSurvivor() && !e.IsDead() && !e.IsDying() && !e.IsGhost() && Distance(bot,e)<radius && Visible(bot,e)) n+=3;
    return n;
};
::BTPMod.Combat <- function(s,target) {
    if(!Settings.combat || !Valid(target) || Busy(s.bot)) return;
    local w=s.bot.GetActiveWeapon(); if(!Valid(w) || (w!=Item(s.bot,0) && w!=Item(s.bot,1))) return;
    if(!Visible(s.bot,target)) return;
    local d=Distance(s.bot,target),cls=w.GetClassname(),type=target.GetClassname()=="player" ? target.GetZombieType() : 0;
    Aim(s.bot,target.GetCenter());
    if(d<95.0 && type!=6 && type!=8) { Input(s,2048); return; }
    if((cls=="weapon_melee" || cls=="weapon_chainsaw") && d>95.0) return;
    if(cls=="weapon_grenade_launcher" && (d<350.0 || NearSurvivor(target.GetOrigin(),270.0))) return;
    Input(s,Prop(w,"m_iClip1",-1)==0 ? 8192 : 1);
};
::BTPMod.FastRevive <- function(s) {
    local t=Handle(s.bot,"m_reviveTarget");
    if(!Survivor(t) || Handle(t,"m_reviveOwner")!=s.bot || t.IsDominatedBySpecialInfected()) { s.revive=null;return; }
    if(Danger(t.GetOrigin())) {
        // Release USE and temporarily disable it; let the engine stop its own action.
        Input(s,0,32); s.revive=null; return;
    }
    if(s.revive!=t) { s.revive=t; s.reviveAt=Time(); }
    if(Settings.rescue && Settings.revive_seconds>0 && Time()-s.reviveAt>=Settings.revive_seconds && Distance(s.bot,t)<110.0) {
        t.ReviveFromIncap(); s.revive=null; Cancel(s);
    }
};
::BTPMod.Escape <- function(s) {
    local areas={}; NavMesh.GetNavAreasInRadius(s.bot.GetOrigin(),500.0,areas);
    local best=null,dist=999999.0;
    foreach(a in areas) {
        local p=a.GetCenter(),d=(p-s.bot.GetOrigin()).Length();
        if(d<dist && d>80.0 && fabs(p.z-s.bot.GetOrigin().z)<60.0 && !Danger(p) && Reach(s.bot,p)) { best=p;dist=d; }
    }
    if(best!=null) { Begin(s,"evade",null,4.0,best); return true; }
    return false;
};
::BTPMod.FindRescue <- function(s) {
    local best=null,distance=Settings.task_range.tofloat();
    foreach(p in Players) {
        if(p==s.bot || !Survivor(p) || (!p.IsIncapacitated() && !p.IsHangingFromLedge()) || p.IsDominatedBySpecialInfected() || !Free(p,s)) continue;
        if(Valid(Handle(p,"m_reviveOwner"))) continue;
        local d=Distance(s.bot,p); if(d<distance && Reach(s.bot,p.GetOrigin())) { best=p;distance=d; }
    }
    if(best==null) return false; Begin(s,"rescue",best);return true;
};
::BTPMod.FindDefib <- function(s) {
    if(!Class(Item(s.bot,3),"weapon_defibrillator")) return false;
    local dead=false; foreach(p in Players) if(Survivor(p,false) && p.IsDead()) {dead=true;break;}
    if(!dead) return false;
    local e=null,best=null,dist=Settings.task_range.tofloat();
    while((e=Entities.FindByClassname(e,"survivor_death_model"))!=null) {
        local d=Distance(s.bot,e); if(d<dist && Free(e,s) && Reach(s.bot,e.GetOrigin())) {best=e;dist=d;}
    }
    if(best==null) return false;Begin(s,"defib",best,24.0,null,null,Item(s.bot,3));return true;
};
::BTPMod.FindUpgrade <- function(s) {
    local pack=Item(s.bot,3); if(!Class(pack,"weapon_upgradepack_incendiary") && !Class(pack,"weapon_upgradepack_explosive")) return false;
    if(Threats(s.bot,500.0)>0) return false;
    local near=0;foreach(p in Players) if(Survivor(p) && Distance(p,s.bot)<320.0) near++;
    if(near<2) return false;Begin(s,"upgrade",s.bot,8.0,s.bot.GetOrigin(),null,pack);return true;
};
::BTPMod.Slot <- function(cls) {
    if(cls=="weapon_pipe_bomb" || cls=="weapon_molotov" || cls=="weapon_vomitjar") return 2;
    if(cls=="weapon_first_aid_kit" || cls=="weapon_defibrillator" || cls=="weapon_upgradepack_incendiary" || cls=="weapon_upgradepack_explosive") return 3;
    if(cls=="weapon_pain_pills" || cls=="weapon_adrenaline") return 4;
    return -1;
};
::BTPMod.FindPickup <- function(s) {
    local e=null,best=null,dist=450.0;
    while((e=Entities.FindInSphere(e,s.bot.GetOrigin(),450.0))!=null) {
        if(Owned(e) || !Free(e,s)) continue;
        local cls=e.GetClassname(),suffix=cls.find("_spawn"); if(suffix!=null) cls=cls.slice(0,suffix);
        local slot=Slot(cls);if(slot<0 || Item(s.bot,slot)!=null || Prop(e,"m_itemCount",1)==0) continue;
        local d=Distance(s.bot,e);if(d<dist && Reach(s.bot,e.GetOrigin())) {best=e;dist=d;}
    }
    if(best==null) return false;Begin(s,"pickup",best,12.0);return true;
};
::BTPMod.NearSurvivor <- function(point,radius) { foreach(p in Players) if(Survivor(p) && (p.GetOrigin()-point).Length()<radius) return true;return false; };
::BTPMod.TryThrow <- function(s) {
    if(!Settings.throw_mask || Time()<ThrowAfter || Time()<s.nextThrow || Busy(s.bot)) return false;
    s.nextThrow=Time()+1.0;
    local w=Item(s.bot,2);if(w==null) return false;
    local kind=Class(w,"weapon_pipe_bomb") ? 1 : (Class(w,"weapon_vomitjar") ? 2 : (Class(w,"weapon_molotov") ? 4 : 0));
    if(!(Settings.throw_mask.tointeger() & kind)) return false;
    local target=null;
    if(kind==4) {
        foreach(e in Players) if(Valid(e) && !e.IsSurvivor() && !e.IsDead() && !e.IsGhost() && e.GetZombieType()==8 && Distance(s.bot,e)>500 && Distance(s.bot,e)<950 && Visible(s.bot,e)) {target=e;break;}
    } else {
        local best=0;
        foreach(e in Commons) {
            if(!Valid(e) || e.GetHealth()<=0) continue;
            local d=Distance(s.bot,e);if(d<350 || d>800 || !Visible(s.bot,e)) continue;
            local count=0;foreach(other in Commons) if(Valid(other) && other.GetHealth()>0 && Distance(e,other)<250.0) count++;
            if(count>=Settings.throw_count && count>best) {best=count;target=e;}
        }
    }
    if(target==null || NearSurvivor(target.GetOrigin(),kind==4 ? 400.0 : 250.0)) return false;
    // Normal engine throw. Check a raised route to avoid an obvious low ceiling or wall.
    local start=s.bot.EyePosition(),end=target.GetCenter(),mid=(start+end)*0.5+Vector(0,0,150);
    local tr=Trace(start,mid,s.bot),tr2=Trace(mid,end,s.bot);
    if(("hit" in tr && tr.hit) || ("hit" in tr2 && tr2.hit && (!("enthit" in tr2) || tr2.enthit!=target))) return false;
    Begin(s,"throw",target,4.0,null,null,w);s.job.stand=end;
    ThrowAfter=Time()+8.0;s.nextThrow=Time()+20.0;return true;
};

::BTPMod.Trade <- function(from,to,slot,swap=false) {
    if(Time()<TradeAfter || !Able(from) || !Able(to) || Busy(from) || Busy(to) || Distance(from,to)>160 || !Visible(from,to)) return false;
    local a=Item(from,slot),b=Item(to,slot);
    if(a==null || (b!=null && !swap)) return false;
    if(Slot(a.GetClassname())!=slot || (b!=null && Slot(b.GetClassname())!=slot)) return false;
    if(IsPlayerABot(from) && State(from).job!=null) return false;
    if(IsPlayerABot(to) && State(to).job!=null) return false;
    // Drop existing entities, then Use those same entities after the engine settles.
    // No GiveItem and no Kill: failed transfers leave the original resources recoverable.
    from.DropItem(a.GetClassname()); if(b!=null) to.DropItem(b.GetClassname());
    Trades.append({from=from,to=to,a=a,b=b,slot=slot,at=Time()+0.3,until=Time()+1.8,attempted=false});
    TradeAfter=Time()+2.0;
    foreach(p in [from,to]) if(IsPlayerABot(p)) {local s=State(p);s.nextShare=Time()+8.0;s.nextThrow=Time()+4.0;}
    return true;
};
::BTPMod.TradeBusy <- function(p) { foreach(t in Trades) if(t.from==p || t.to==p) return true;return false; };
::BTPMod.FinishTrades <- function() {
    for(local i=Trades.len()-1;i>=0;i--) {
        local t=Trades[i];if(Time()<t.at) continue;
        if(!t.attempted) {
            if(Able(t.to) && Item(t.to,t.slot)==null && Valid(t.a) && !Owned(t.a) && Distance(t.to,t.a)<180 && Visible(t.to,t.a)) DoEntFire("!self","Use","",0,t.to,t.a);
            if(t.b!=null && Able(t.from) && Item(t.from,t.slot)==null && Valid(t.b) && !Owned(t.b) && Distance(t.from,t.b)<180 && Visible(t.from,t.b)) DoEntFire("!self","Use","",0,t.from,t.b);
            t.attempted=true;t.at=Time()+0.3;continue;
        }
        local done=Survivor(t.to) && Item(t.to,t.slot)==t.a && (t.b==null || (Survivor(t.from) && Item(t.from,t.slot)==t.b));
        if(done) {if(!IsPlayerABot(t.to)) Note(t.to,"补给已交接。");if(t.b!=null && !IsPlayerABot(t.from)) Note(t.from,"投掷物已交换。");Trades.remove(i);}
        else if(Time()>=t.until) {
            // Best effort return to original owner. Never delete items that remain on the ground.
            foreach(pair in [[t.from,t.a],[t.to,t.b]]) {
                if(Able(pair[0]) && Valid(pair[1]) && !Owned(pair[1]) && Item(pair[0],t.slot)==null && Distance(pair[0],pair[1])<180 && Visible(pair[0],pair[1])) DoEntFire("!self","Use","",0,pair[0],pair[1]);
            }
            if(Survivor(t.from) && !IsPlayerABot(t.from)) Note(t.from,"交接未完成，原物品保留在持有者或附近地面。");
            Trades.remove(i);
        }
    }
};
::BTPMod.Share <- function(s,recipient=null,requested=false) {
    s.nextShare=Time()+3.0;
    foreach(p in Players) {
        if((recipient!=null && p!=recipient) || !Able(p) || IsPlayerABot(p) || Distance(s.bot,p)>160 || Busy(p)) continue;
        foreach(slot in [4,3,2]) {
            local w=Item(s.bot,slot);if(w==null || Item(p,slot)!=null) continue;
            if(slot==3 && !Class(w,"weapon_first_aid_kit")) continue;
            if(!requested && slot!=2 && (Health(p)>Settings.share_health || Health(s.bot)<35.0)) continue;
            if(Trade(s.bot,p,slot)) {s.nextShare=Time()+8.0;return true;}
        }
    }
    return false;
};
::BTPMod.HumanSwap <- function(p) {
    local id=p.GetPlayerUserId(),buttons=p.GetButtonMask(),prev=id in HumanButtons ? HumanButtons[id] : 0;
    HumanButtons[id] <- buttons;
    if(!(buttons&2048) || (prev&2048) || !Able(p) || (id in Cooldowns && Cooldowns[id]>Time())) return;
    local w=Item(p,2);if(w==null || p.GetActiveWeapon()!=w) return;
    local tr=Trace(p.EyePosition(),p.EyePosition()+p.EyeAngles().Forward()*150.0,p);
    if(!("enthit" in tr) || !Bot(tr.enthit) || !Able(tr.enthit)) return;
    if(Trade(p,tr.enthit,2,true)) Cooldowns[id] <- Time()+2.0;
};

::BTPMod.RuleTarget <- function(r) {
    if(r.target.len()>1 && r.target.slice(0,1)=="#") {
        local wanted=r.target.slice(1).tointeger(),e=Entities.First();
        while(e!=null) {if(Prop(e,"m_iHammerID",-1)==wanted) return e;e=Entities.Next(e);}
        return null;
    }
    return Entities.FindByName(null,r.target);
};
::BTPMod.ButtonAllowed <- function(e) {
    return (Class(e,"func_button") || Class(e,"func_rot_button") || Class(e,"func_button_timed")) && !Prop(e,"m_bLocked") && !Prop(e,"m_bDisabled");
};
::BTPMod.ObserveButton <- function(e) {
    local idx=e.GetEntityIndex();if(idx in Buttons && Buttons[idx].ent==e) return Buttons[idx];
    local token=++Sequence,output=Class(e,"func_button_timed") ? "OnTimeUp" : "OnPressed";
    local code="BTPMod.ButtonDone("+token+")";
    Buttons[idx] <- {ent=e,token=token,done=false,output=output,code=code};
    EntityOutputs.AddOutput(e,output,Thinker.GetName(),"RunScriptCode",code,0.0,-1);
    return Buttons[idx];
};
::BTPMod.ButtonDone <- function(token) {
    foreach(record in Buttons) if(record.token==token) {record.done=true;return;}
};
::BTPMod.PlanB <- function() {
    local dead=false;
    foreach(p in Players) if(Survivor(p,false)) {
        if(!IsPlayerABot(p)) {if(!p.IsDead() && !p.IsDying()) return false;dead=true;}
        if(Bot(p) && Class(Item(p,3),"weapon_defibrillator") && Able(p)) {
            local e=null;while((e=Entities.FindByClassname(e,"survivor_death_model"))!=null) if(Free(e,State(p)) && Reach(p,e.GetOrigin())) return false;
        }
    }
    return dead;
};
::BTPMod.FindButton <- function(s) {
    foreach(r in Rules) {
        if(r.kind!="button") continue;
        local e=RuleTarget(r);if(!Valid(e)) return false;
        local record=ObserveButton(e);if(record.done) continue;
        if(!ButtonAllowed(e) || !Free(e,s) || !Reach(s.bot,r.stand)) return false;
        Begin(s,"button",e,25.0,r.stand,r);return true;
    }
    if(Settings.planb<2) return false;
    local e=null;while((e=Entities.FindByClassname(e,"func_button"))!=null) {
        if(!ButtonAllowed(e) || !(Prop(e,"m_spawnflags")&1024) || !Free(e,s) || (s.bot.GetOrigin()-e.GetCenter()).Length()>250) continue;
        if(ObserveButton(e).done || !Visible(s.bot,e) || !Reach(s.bot,e.GetCenter())) continue;
        Begin(s,"button",e,8.0);return true;
    }
    return false;
};
::BTPMod.Nozzle <- function(s) {
    foreach(r in Rules) if(r.kind=="gas") {local e=RuleTarget(r);if(Valid(e) && Reach(s.bot,r.stand)) return {ent=e,stand=r.stand};}
    local map=Director.GetMapName();if(map!="c1m4_atrium" && map!="c6m3_port") return null;
    local e=null;while((e=Entities.FindByClassname(e,"point_prop_use_target"))!=null) if(!Prop(e,"m_bDisabled") && Reach(s.bot,e.GetOrigin())) return {ent=e,stand=e.GetOrigin()};
    return null;
};
::BTPMod.FindGas <- function(s) {
    foreach(other in States) if(other!=s && other.job!=null && (other.job.kind=="gas" || other.job.kind=="deliver")) return false;
    local nozzle=Nozzle(s);if(nozzle==null) return false;
    local carried=Item(s.bot,5);
    if(Class(carried,"weapon_gascan")) {Begin(s,"deliver",nozzle.ent,35.0,nozzle.stand,null,carried);return true;}
    if(carried!=null) return false;
    local e=null,best=null,dist=Settings.task_range.tofloat();
    while((e=Entities.FindByClassname(e,"weapon_gascan"))!=null) {
        if(Owned(e) || !Free(e,s) || (e.GetOrigin()-nozzle.stand).Length()<180.0) continue;
        local d=Distance(s.bot,e);if(d<dist && Reach(s.bot,e.GetOrigin())) {best=e;dist=d;}
    }
    if(best==null) return false;Begin(s,"gas",best,35.0);return true;
};

::BTPMod.UpdateJob <- function(s) {
    local j=s.job,bot=s.bot,now=Time();
    if(now>j.until) {Cancel(s,true);return;}
    if(j.kind!="evade" && !Valid(j.target)) {Cancel(s);return;}
    if(j.kind=="throw") {
        if(Item(bot,2)!=j.item) {Cancel(s);return;}
        if(Danger(bot.GetOrigin()) || NearSurvivor(j.stand,Class(j.item,"weapon_molotov") ? 400.0 : 240.0)) {Cancel(s);return;}
        Aim(bot,j.stand,-9.0);
        LockWeapons(s);
        if(bot.GetActiveWeapon()!=j.item) {bot.SwitchToItem(j.item.GetClassname());return;}
        if(j.at==0.0) {
            if(NetProps.GetPropFloat(j.item,"m_flNextPrimaryAttack")>now) return;
            j.at=now;
        }
        if(now-j.at<0.3) Input(s,1,2048); else Input(s,0,1|2048);
        return;
    }
    if(j.kind=="rescue") {
        if(!Survivor(j.target) || (!j.target.IsIncapacitated() && !j.target.IsHangingFromLedge()) || j.target.IsDominatedBySpecialInfected()) {Cancel(s);return;}
        local owner=Handle(j.target,"m_reviveOwner");if(Valid(owner) && owner!=bot) {Cancel(s);return;}
        if(Threats(bot,140.0)>=6) {Cancel(s,true);return;}
    }
    if(j.kind=="defib" || j.kind=="upgrade") if(Item(bot,3)!=j.item) {Cancel(s);return;}
    if(j.kind=="pickup") {
        local cls=j.target.GetClassname(),suffix=cls.find("_spawn");if(suffix!=null) cls=cls.slice(0,suffix);
        local slot=Slot(cls);if(Owned(j.target) || (slot>=0 && Item(bot,slot)!=null)) {Cancel(s);return;}
    }
    if(j.kind=="gas") {
        if(Item(bot,5)==j.target) {local nozzle=Nozzle(s);if(nozzle!=null) Begin(s,"deliver",nozzle.ent,35.0,nozzle.stand,null,j.target);else Cancel(s,true);return;}
        if(Owned(j.target)) {Cancel(s);return;}
    }
    if(j.kind=="deliver" && Item(bot,5)!=j.item) {Cancel(s);return;}
    if(j.kind=="button" && ObserveButton(j.target).done) {Cancel(s);return;}
    if(j.kind!="evade" && j.kind!="rescue" && Threats(bot,180.0)>=3) {Cancel(s,true);return;}
    if(j.kind=="deliver") Input(s,0,1|2048);
    local point=j.stand!=null ? j.stand : j.target.GetOrigin();
    if(j.kind=="button" && j.stand==null) point=j.target.GetCenter();
    if(j.kind!="evade" && Danger(point)) {Cancel(s,true);return;}
    local d=(bot.GetOrigin()-point).Length(),range=j.kind=="deliver" ? 105.0 : 65.0;
    if(j.rule!=null || j.kind=="evade") range=35.0;
    if(d<j.best-20.0) {j.best=d;j.progress=now;}
    if(d>range) {
        j.at=0.0;
        if(now-j.progress>7.0) {Cancel(s,true);return;}
        Move(s,point);Combat(s,Enemy(s));return;
    }
    if(j.kind=="evade") {Cancel(s);return;}
    if(j.kind=="deliver") {bot.DropItem("weapon_gascan");Cancel(s);return;}
    if(j.kind!="upgrade" && !Visible(bot,j.target)) {Cancel(s,true);return;}
    if(j.kind!="rescue" && Threats(bot,180.0)>=3) {Cancel(s,true);return;}
    // Hold position using normal Bot navigation; no FL_FROZEN changes survive an interruption.
    Move(s,bot.GetOrigin());
    if(j.at==0.0) j.at=now;
    Aim(bot,j.kind=="upgrade" ? bot.GetOrigin() : j.target.GetCenter());
    if(j.kind=="defib" || j.kind=="upgrade") {
        LockWeapons(s);
        if(bot.GetActiveWeapon()!=j.item) bot.SwitchToItem(j.item.GetClassname());
        else if(NetProps.GetPropFloat(j.item,"m_flNextPrimaryAttack")<=now) Input(s,1,32|2048);
    } else if(j.kind=="pickup" || j.kind=="gas") {
        Input(s,0,1|2048);
        if(j.kind=="gas") LockWeapons(s);
        if(j.phase==0) {DoEntFire("!self","Use","",0,bot,j.target);j.phase=1;}
        if(now-j.at>2.0) Cancel(s,true);
    } else {
        Input(s,32,1|2048);
        if(j.kind=="button" && now-j.at>(j.rule==null ? 2.0 : j.rule.hold+2.0)) Cancel(s,true);
    }
};
::BTPMod.BotThink <- function(s) {
    Input(s);
    if(!Able(s.bot)) {Cancel(s);s.revive=null;return;}
    if(TradeBusy(s.bot)) return;
    FastRevive(s);
    if(Danger(s.bot.GetOrigin())) {
        if(s.job==null || s.job.kind!="evade") Escape(s);
        if(s.job!=null && s.job.kind=="evade") {UpdateJob(s);Input(s,s.forced,32);}
        else Input(s,0,32);
        return;
    }
    if(s.job!=null && s.job.kind=="evade") Cancel(s);
    local enemy=Settings.combat ? Enemy(s) : null,urgent=false;
    foreach(p in Players) if(Survivor(p) && Valid(enemy) && p.GetSpecialInfectedDominatingMe()==enemy) {urgent=true;break;}
    if(urgent) {if(s.job!=null) Cancel(s);Combat(s,enemy);return;}
    if(s.job!=null) {UpdateJob(s);return;}
    if(Busy(s.bot)) return;
    Combat(s,enemy);
    if(TryThrow(s)) return;
    if(Settings.share && Time()>=s.nextShare && Share(s)) return;
    if(Time()<s.nextWork) return;s.nextWork=Time()+0.8;
    if(Settings.rescue && FindRescue(s)) return;
    if(Threats(s.bot,250.0)>0) return;
    if(Settings.defib && FindDefib(s)) return;
    if(Settings.upgrade && FindUpgrade(s)) return;
    if(FindPickup(s)) return;
    if(Settings.gas && FindGas(s)) return;
    if(Settings.planb && PlanB()) FindButton(s);
};
::BTPMod.Think <- function() {
    if(!Active) return 0.1;
    try {
        if(Time()>=NextEventCheck) {EnsureEvents();NextEventCheck=Time()+2.0;}
        if(Time()>=NextScan) {Scan();NextScan=Time()+0.25;}
        if(!Announced && Time()>=AnnounceAt) {
            foreach(p in Players) if(Survivor(p) && !IsPlayerABot(p)) {
                Note(null,"MOD "+Version+" 已加载。聊天输入 !btp；控制台输入 say !btp。");Announced=true;break;
            }
        }
        FinishTrades();
        foreach(p in Players) {
            if(!Survivor(p)) continue;
            if(IsPlayerABot(p)) {
                local s=State(p);
                try {BotThink(s);} catch(err) {Cancel(s);throw err;}
            } else HumanSwap(p);
        }
    } catch(err) {
        printl("[TeamPlus ERROR] "+err);Errors++;
        if(Errors>=3) {Note(null,"脚本累计出错3次，已停用增强。请查看控制台错误。");Stop();}
    }
    return 0.05;
};

::BTPMod.SaveSettings <- function() {
    local text="# Bot TeamPlus MOD. key=value; use !btpreload after editing.\n";
    foreach(k,v in Settings) text+=k+"="+v+"\n";
    StringToFile("bot_teamplus/settings.txt",text);
};
::BTPMod.LoadSettings <- function() {
    local text=FileToString("bot_teamplus/settings.txt");if(text==null) text="";
    foreach(line in split(text,"\n")) {
        line=strip(line);if(line.len()==0 || line.slice(0,1)=="#") continue;
        local p=split(line,"=");if(p.len()!=2) continue;
        local k=strip(p[0]);if(!(k in Settings)) continue;
        try {
            local v=strip(p[1]).tofloat(),limit=Limits[k];
            if(v<limit[0] || v>limit[1]) continue;
            Settings[k]=k=="revive_seconds" ? v : v.tointeger();
        } catch(err) {printl("[TeamPlus] Invalid setting: "+line);}
    }
    // One-time migration: old installs saved avoid_spit=1. Do not reset other settings.
    // After migration the host may opt back into avoidance with !btpset avoid_spit 1.
    if(FileToString("bot_teamplus/hazard_walk_012.txt")!="done") {
        Settings.avoid_spit=0;SaveSettings();
        StringToFile("bot_teamplus/hazard_walk_012.txt","done");
        printl("[TeamPlus] 0.1.2: acid/fire avoidance disabled; use with Hazard Shield.");
    }
};
::BTPMod.MapPath <- function() {return "bot_teamplus/maps/"+Director.GetMapName()+".txt";};
::BTPMod.LoadRules <- function() {
    Rules.clear();local text=FileToString(MapPath());if(text==null) return;
    foreach(line in split(text,"\n")) {
        line=strip(line);if(line.len()==0 || line.slice(0,1)=="#") continue;
        local p=split(line,"|");if(p.len()!=6 || (p[0]!="button" && p[0]!="gas")) continue;
        try {
            local hold=p[5].tofloat();if(hold<0.2) hold=0.2;if(hold>20.0) hold=20.0;
            Rules.append({kind=p[0],target=p[1],stand=Vector(p[2].tofloat(),p[3].tofloat(),p[4].tofloat()),hold=hold});
        } catch(err) {printl("[TeamPlus] Invalid map rule: "+line);}
        if(Rules.len()>=64) break;
    }
};
::BTPMod.SaveRules <- function() {
    local text="# type|targetname or #hammerid|stand_x|stand_y|stand_z|hold_seconds\n";
    foreach(r in Rules) text+=format("%s|%s|%.2f|%.2f|%.2f|%.2f\n",r.kind,r.target,r.stand.x,r.stand.y,r.stand.z,r.hold);
    StringToFile(MapPath(),text);
};
::BTPMod.SetCvar <- function(name,value) {
    local old=Convars.GetStr(name);if(old==null) return;
    SavedCvars[name] <- {old=old,value=value.tostring()};Convars.SetValue(name,value);
};
::BTPMod.Stop <- function() {
    Active=false;
    foreach(s in States) Cancel(s);
    foreach(record in Buttons) if(Valid(record.ent) && Valid(Thinker)) EntityOutputs.RemoveOutput(record.ent,record.output,Thinker.GetName(),"RunScriptCode",record.code);
    Buttons.clear();
    foreach(name,entry in SavedCvars) if(Convars.GetStr(name)==entry.value) Convars.SetValue(name,entry.old);
    SavedCvars.clear();
    if(Valid(Thinker)) {AddThinkToEnt(Thinker,null);Thinker.Kill();}
    Thinker=null;States.clear();Trades.clear();HumanButtons.clear();Cooldowns.clear();
};
::BTPMod.Start <- function() {
    Stop();Errors=0;Failures.clear();ThrowAfter=0.0;TradeAfter=0.0;NextScan=0.0;
    NextEventCheck=0.0;Announced=false;AnnounceAt=Time()+1.0;EnsureEvents();
    local mode=Director.GetGameMode();if(mode!="coop" && mode!="realism") {printl("[TeamPlus] Inactive mode: "+mode);return;}
    LoadSettings();LoadRules();Scan();
    Thinker=SpawnEntityFromTable("info_target",{targetname=DoUniqueString("btp_mod_thinker")});
    if(!Valid(Thinker)) {printl("[TeamPlus ERROR] Unable to create thinker");return;}
    Thinker.ValidateScriptScope();Thinker.GetScriptScope().BTPThink <- function() {return ::BTPMod.Think();};
    SetCvar("sb_all_bot_game",1);SetCvar("allow_all_bot_survivor_team",1);
    Active=true;AddThinkToEnt(Thinker,"BTPThink");
    // Observe configured buttons immediately, including presses made by humans.
    foreach(r in Rules) if(r.kind=="button") {local e=RuleTarget(r);if(Valid(e)) ObserveButton(e);}
    printl("[TeamPlus MOD "+Version+"] loaded: "+Director.GetMapName()+" ("+Rules.len()+" map rules)");
};
::BTPMod.OnGameEvent_round_start <- function(params) {Start();};
::BTPMod.OnGameEvent_round_end <- function(params) {Stop();};
::BTPMod.OnGameEvent_map_transition <- function(params) {Stop();};
::BTPMod.OnGameEvent_player_disconnect <- function(params) {
    if("userid" in params && params.userid in States) {Cancel(States[params.userid]);delete States[params.userid];}
};
::BTPMod.OnGameEvent_player_say <- function(params) {
    if(!("text" in params) || typeof params.text!="string") return;
    local text=strip(params.text);
    if(text.len()<4 || text.slice(0,4).tolower()!="!btp") return;
    local player=null;
    try {
        if("userid" in params) player=FindSpeaker(params.userid);
        if(!Valid(player)) {printl("[TeamPlus CHAT] Cannot resolve speaker userid; command ignored.");return;}
        Command(player,text);
    } catch(err) {
        printl("[TeamPlus CHAT ERROR] "+err);
        if(Valid(player)) Note(player,"命令处理出错，请查看控制台 [TeamPlus CHAT ERROR]。");
    }
};
::BTPMod.Command <- function(player,text) {
    local words=split(strip(text)," \t\r\n");if(words.len()==0) return;
    local cmd=words[0].tolower();
    if(cmd=="!btp") {Status(player);return;}
    if(cmd=="!btpgive" && Active && Able(player)) {foreach(s in States) if(Bot(s.bot) && Share(s,player,true)) return;Note(player,"附近没有可交付的补给。");return;}
    if(cmd!="!btpon" && cmd!="!btpoff" && cmd!="!btpreload" && cmd!="!btpmark" && cmd!="!btpset") return;
    if(player!=GetListenServerHost()) {Note(player,"该命令仅限本地房主。");return;}
    if(cmd=="!btpoff") {Stop();Note(player,"已停用并释放Bot控制。");return;}
    if(cmd=="!btpon" || cmd=="!btpreload") {Start();Note(player,Active ? "已启动/重载。" : "当前模式不支持。");return;}
    if(cmd=="!btpset") {
        if(words.len()!=3 || !(words[1] in Settings)) {Note(player,"用法：!btpset 配置名 数值");return;}
        try {local k=words[1],v=words[2].tofloat();if(v<Limits[k][0] || v>Limits[k][1]) throw "range";Settings[k]=k=="revive_seconds" ? v : v.tointeger();SaveSettings();Start();Note(player,"配置已保存并重载。");}
        catch(err) {Note(player,"数值不合法或超出范围。");}return;
    }
    if(!Active || !Able(player) || words.len()<2 || (words[1]!="button" && words[1]!="gas")) {Note(player,"用法：!btpmark button [持续秒数] 或 !btpmark gas");return;}
    local tr=Trace(player.EyePosition(),player.EyePosition()+player.EyeAngles().Forward()*250.0,player);
    local e="enthit" in tr ? tr.enthit : null;
    if(!Valid(e) || (words[1]=="button" && !ButtonAllowed(e))) {Note(player,"请瞄准可用按钮实体，或灌油机实体。");return;}
    local hammer=Prop(e,"m_iHammerID"),name=hammer>0 ? "#"+hammer : e.GetName();
    if(name==null || name.len()==0 || name.find("|")!=null || name.find("\n")!=null) {Note(player,"实体缺少可保存的地图标识。");return;}
    local hold=5.0;try {if(words.len()>2) hold=words[2].tofloat();} catch(err) {Note(player,"持续时间应为数值。");return;}
    if(hold<0.2 || hold>20.0) {Note(player,"持续时间范围0.2到20秒。");return;}
    local rule={kind=words[1],target=name,stand=player.GetOrigin(),hold=hold},found=false;
    for(local i=0;i<Rules.len();i++) if(Rules[i].kind==rule.kind && Rules[i].target==name) {Rules[i]=rule;found=true;break;}
    if(!found && Rules.len()<64) Rules.append(rule);
    SaveRules();Start();Note(player,"当前地图的 "+words[1]+" 位置已登记。");
};

::BTPMod.EnsureEvents();
