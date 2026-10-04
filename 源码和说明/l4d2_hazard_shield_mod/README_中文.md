# Survivor Hazard Shield 0.1.0

独立的求生之路2 VScript Mod。适用于单机或本地房主的战役/写实：真人和 Bot 幸存者免疫 Spitter 酸液及火焰伤害，包括倒地时的这两类伤害。没有 SourceMod 或其他脚本库依赖。

**这是测试版：通过语法、模拟行为和VPK校验，尚未游戏实测。**

## 安装与状态

关闭游戏，将 `survivor_hazard_shield.vpk` 放进 `left4dead2/addons`，在附加内容中启用后开启本地战役。聊天输入 `!hs`，控制台输入 `say !hs`。状态会显示接口状态、收到的伤害回调数量和拦截次数。

“接口已安装”只说明脚本已设置回调；踩酸液/火焰后拦截次数上升、且生命值不下降，才验证游戏中生效。初始化时控制台应出现 `[HazardShield 0.1.0] loaded`。没有状态响应请保留控制台脚本报错。

可单独安装。与 Bot TeamPlus 0.1.2 同装时，后者默认取消自己的酸火避让。卸载本包需要退出游戏、移除VPK、再启动；需要恢复Bot避让时，聊天输入 `!btpset avoid_spit 1`。`!btpoff` 只关闭Bot增强，不关闭本免伤包。

## 伤害范围

- 只保护幸存者，不保护普通感染者、特感、Tank、Witch或其他实体；燃烧瓶仍可烧敌人。
- 在 `AllowTakeDamage` 回调中把匹配伤害归零并拒绝此次伤害，不使用受伤后补血，因此不转换临时血量，也不需要修改最大生命值。
- 识别 `insect_swarm` / `spitter_projectile` 的酸液，以及 `DMG_ACID`、`DMG_BURN`、`DMG_SLOWBURN`。不把所有辐射类型一概视为酸液。
- 保留枪伤、近战、摔伤、碰撞、爆炸。混合了子弹/爆炸与火焰标志的瞬间伤害整体保留；后续单独燃烧伤害屏蔽。
- 火焰和酸液特效仍显示。不删除危险实体，不熄灭地图机关，不更改感染者生命值。
- 第三方地图若用通用伤害、脚本直接改血或直接杀死玩家来模拟熔岩/毒池，不在识别范围内。

## 模式与兼容

仅对普通 `coop` 和 `realism` 启用。必须由运行服务器的一方安装；客户端加入官方/他人服务器时不会获得免伤。

使用游戏支持的 `scriptedmode_addon.nut` 入口，先调用原有 `ScriptMode_Init`。普通战役没有脚本模式时，完成会话状态、地图选项、生成及预缓存初始化，再启用伤害回调；不会覆盖 `coop.nut` 或整份 `scriptedmode.nut`。

安装伤害回调时串联原有模式回调，保留其执行上下文、伤害修改和拒绝结果。如果其他Mod后来覆盖同一回调，本包会在回合开始或查看状态时提示，而不会持续互相重装制造回调循环。任意第三方Mod组合仍需实测，尤其是修改游戏模式和伤害规则的Mod。

## 本次验证

- Squirrel 3.2编译语法检查。L4D2的Squirrel及引擎扩展不同，此检查不等同游戏内加载。
- 模拟验证真人/Bot/倒地免伤、Spitter辐射伤害来源识别、普通辐射保留、感染者火伤保留、枪/摔/爆炸与混合伤害保留、原回调调用/上下文/拒绝保留、重复安装和覆盖提示。
- 模拟验证普通战役初始化补全、已初始化写实模式不重复初始化、其他模式返回值保留、多次初始化不重复触发；使用已公布的游戏事件分发代码测试 `!hs`。
- 独立VPK读取器校验逐文件CRC和源码字节一致性。
- 未执行真实L4D2实战：需要确认具体客户端上的伤害回调捕获、换图、救援动作和其他Mod兼容。

## 游戏验收

先只启用本包和Bot TeamPlus新版，在单机战役分别测试：真人/Bot正常状态与倒地状态踩痰、踩火；低血量时进入火区；感染者仍受火伤；普通受击/坠落/爆炸仍掉血。每次比较 `!hs` 的拦截计数。继续检查酸火区域扶人是否中断，再测试换图和第三方地图。

源码位于 `source`，运行 `python build_vpk.py` 重打包；Python3即可，不需要第三方包。源码采用GPL-3.0-or-later，许可证随附。

接口核对参考：[Valve VScript](https://developer.valvesoftware.com/wiki/Left_4_Dead_2/Scripting/Script_Functions)、[Left4Lib初始化入口](https://github.com/smilz0/Left4Lib/blob/main/root/scripts/vscripts/scriptedmode_addon.nut)、[Left4Lib伤害回调用法](https://github.com/smilz0/Left4Lib/blob/main/root/scripts/vscripts/left4lib_hooks.nut)。不内置Left4Lib，不需要订阅它。
