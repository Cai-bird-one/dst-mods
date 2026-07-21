local team_state = require("src/team/lobby_team_state")
local function IsDST()
	return TheSim:GetGameID() == "DST"
end

local function IsClient()
	return IsDST() and not TheWorld.ismastersim
end

local function DYCGetPlayer()
	if IsDST() then
		return ThePlayer
	else
		return GetPlayer()
	end
end

local function IsDistOK (other)
	-- if IsDST() then
		-- return true
	-- end
	local player=DYCGetPlayer()
	if player==other then
		return true
	end
	if not player or not player:IsValid() or not other:IsValid() then
		return false
	end
	local dis = player:GetPosition():Dist(other:GetPosition())
	return dis<=TUNING.DYC_HEALTHBAR_MAXDIST
end

local DYC_ENT_SIZE_LIST = {
	{prefab="krampus",width=1,height=3.75,},
	{prefab="nightmarebeak",width=1,height=4.5,},
	{prefab="terrorbeak",width=1,height=4.5,},
	{prefab="spiderqueen",width=2,height=4.5,},
	{prefab="warg",width=1.7,height=5,},
	{prefab="pumpkin_lantern",width=0.7,height=1.5,},
	{prefab="jellyfish_planted",width=0.7,height=1.5,},
	{prefab="babybeefalo",width=1,height=2.2,},
	{prefab="beeguard",width=0.65,height=2,},
	{prefab="shadow_rook",width=1.8,height=3.5,},
	{prefab="shadow_bishop",width=0.9,height=3.2,},
	{prefab="walrus",width=1.1,height=3.2,},
	{prefab="teenbird",width=1.0,height=3.6,},
	
	{tag="koalefant",width=1.7,height=4,},
	{tag="spat",width=1.5,height=3.5,},
	{tag="lavae",width=0.8,height=1.5,},
	{tag="glommer",width=0.9,height=2.9,},
	{tag="deer",width=1,height=3.1,},
	{tag="snake",width=0.9,height=1.7,},
	{tag="eyeturret",width=1,height=4.5,},
	{tag="primeape",width=0.85,height=1.5,},
	{tag="monkey",width=0.85,height=1.5,},
	{tag="ox",width=1.5,height=3.75,},
	{tag="beefalo",width=1.5,height=3.75,},
	{tag="kraken",width=2,height=5.5,},
	{tag="nightmarecreature",width=1.25,height=3.5,},
	{tag="bishop",width=1,height=4,},
	{tag="rook",width=1.25,height=4,},
	{tag="knight",width=1,height=3,},
	{tag="bat",width=0.85,height=3,},
	{tag="minotaur",width=1.75,height=4.5,},
	{tag="packim",width=0.9,height=3.75,},
	{tag="stungray",width=0.9,height=3.75,},
	{tag="ghost",width=0.9,height=3.75,},
	{tag="tallbird",width=1.25,height=5,},
	{tag="chester",width=0.85,height=1.5,},
	{tag="hutch",width=0.85,height=1.5,},
	{tag="wall",width=0.5,height=1.5,},
	{tag="largecreature",width=2,height=7,},
	{tag="insect",width=0.5,height=1.6,},
	{tag="smallcreature",width=0.85,height=1.5,},
}


local assets=
{
	
}

local prefabs =
{
	
}

local function Clamp01 (num)
	if num<0 then
		num=0
	elseif num>1 then
		num=1
	end
	return num
end

local function GetHpText(hpCurrent,hpMax)
	local c1=TUNING.DYC_HEALTHBAR_C1
	local c2=TUNING.DYC_HEALTHBAR_C2
	local cnum=TUNING.DYC_HEALTHBAR_CNUM
	local str=""
	if TUNING.DYC_HEALTHBAR_POSITION==0 then
		str="  \n  \n  \n  \n"
	end
	local hpp=hpCurrent/hpMax
	for i=1,cnum do
		if hpp==0 or (i~=1 and i*1.0/cnum>hpp) then
			str=str..c1
		else
			str=str..c2
		end
	end
	return str
end

local function GetEntHBSize(ent)
	if not ent then 
		return 1
	end
	for k,v in pairs(DYC_ENT_SIZE_LIST) do
		if v.width and (ent.prefab==v.prefab or (v.tag and ent:HasTag(v.tag))) then
			return v.width
		end
	end
	return 1
end

local function GetEntHBHeight(ent)
	if not ent then 
		return 2.2
	end
	for k,v in pairs(DYC_ENT_SIZE_LIST) do
		if v.height and (ent.prefab==v.prefab or (v.tag and ent:HasTag(v.tag))) then
			return v.height
		end
	end
	return 2.2
end





local function InitHB (inst)
	if not inst.dychbowner then
		inst.dychbowner=inst.entity:GetParent()
		if not inst.dychbowner then
			inst:Remove()
			return
		end
		inst.dychbowner.dychealthbar=inst
	end
	
	if IsDST() or TUNING.DYC_HEALTHBAR_POSITION==0 then
		inst.dychbtext=inst.dychbowner:SpawnChild("dyc_healthbarchild") 
	else
		inst.dychbtext=inst:SpawnChild("dyc_healthbarchild") 
	end
	inst.Label:Enable(false)
	inst.dychbtext.Label:Enable(false)
	
	inst.SetHBHeight=function (inst,height)
		if TUNING.DYC_HEALTHBAR_POSITION==0 then
			height=0
		end
		if IsDST() then
			inst.Label:SetWorldOffset(0, height, 0)
			inst.dychbtext.Label:SetWorldOffset(0, height, 0)
		else
			inst.dychbheight=height*1.5
		end
	end
	inst.dychbheightconst=GetEntHBHeight(inst.dychbowner)
	inst:SetHBHeight(inst.dychbheightconst)
	
	inst.SetHBSize=function (inst,size)
		local hbsize=math.max(1,(13-TUNING.DYC_HEALTHBAR_CNUM)/5)*15*size
		inst.Label:SetFontSize(hbsize)
		inst.dychbtext.Label:SetFontSize(28*size)
	end
	inst:SetHBSize(GetEntHBSize(inst.dychbowner))
	inst.dycHbStarted=true
end

local function fn()
	local inst = CreateEntity()
	inst.entity:AddTransform()
	-- inst.entity:AddAnimState()
	-- inst.AnimState:SetLightOverride(1)
	
	inst:AddTag("FX")
	
	local label = inst.entity:AddLabel()
	label:SetFont(NUMBERFONT)
	-- label:SetFont(TALKINGFONT)
	label:SetFontSize(28)
	-- if IsDST() then
		-- label:SetWorldOffset(0, 2.2, 0)
	-- end
	label:SetColour(1, 1, 1)
	-- label:SetText("dyc_healthbar")
	label:SetText(" ")
	label:Enable(true)

	inst.persists = false
	
	inst.InitHB=InitHB

	return inst
end

local mycolour = {
	[1] = {1,0,0},
	[2] = {0,0,1},
	[3] = {1,1,1},
}

local function dychbfn()
	local inst = fn()
	
	
	
	if IsDST() then
		inst.entity:AddNetwork()
	end

	inst.Label:SetFontSize(15)
	
	if IsDST() then
		-- inst.dychpold=-1
		inst.dychpini=-1
		inst.dychp=0
		inst.dychp_net = net_float(inst.GUID, "dyc_healthbar.hp", "dychpdirty")
		inst.dycol_net = net_tinybyte(inst.GUID, "dyc_healthbar.col", "dyccoldirty")

		inst:ListenForEvent("dyccoldirty", function(inst)
			if inst.dycol_net:value() and mycolour[inst.dycol_net:value()] then
				inst.Label:SetColour(unpack(mycolour[inst.dycol_net:value()]))
			end
		end)
		inst:ListenForEvent("dychpdirty", function(inst)
			local hpnew=inst.dychp_net:value()
			if inst.dychpini==-1 then
				inst.dychpini=hpnew
				if not TUNING.DYC_HEALTHBAR_DDON then
					inst.dychpini=-2
				end
			end
			if TUNING.DYC_HEALTHBAR_DDON then
				
				if inst.dychbowner and IsDistOK(inst.dychbowner) then
					local dd=SpawnPrefab("dyc_damagedisplay")
					if inst.dychpini>0 then
						dd:DamageDisplay(inst.dychbowner,{hpOld=inst.dychpini, hpNewDefault=hpnew})
						inst.dychpini=-2
					else
						dd:DamageDisplay(inst.dychbowner,{hpNewDefault=hpnew})
					end
				end
			end
			inst.dychp=hpnew
			
		end)
		
		inst.dychpmax=0
		inst.dychpmax_net = net_float(inst.GUID, "dyc_healthbar.hpmax", "dychpmaxdirty")
		inst:ListenForEvent("dychpmaxdirty", function(inst)
			inst.dychpmax=inst.dychpmax_net:value()
		end)
		
		-- inst.dychbowner=nil
		-- inst.dychbowner_net=net_entity(inst.GUID, "dyc_healthbar.owner", "dychbownerdirty")
		-- inst:ListenForEvent("dychbownerdirty", function(inst)
			-- inst.dychbowner=inst.dychbowner_net:value()
		-- end)
		
		-- inst.dychbattacker=nil
		-- inst.dychbattacker_net=net_entity(inst.GUID, "dyc_healthbar.owner", "dychbattackerdirty")
		-- inst:ListenForEvent("dychbattackerdirty", function(inst)
			-- inst.dychbattacker=inst.dychbattacker_net:value()
		-- end)
	end
	
	local hpCurrent=-1
	local hpMax=-1
	local timer=0
	inst.dycHbStarted=false
	
	inst.OnRemoveEntity=function(inst)
		if IsDST() and inst.dychbowner and TUNING.DYC_HEALTHBAR_DDON and IsDistOK(inst.dychbowner) then
			local dd=SpawnPrefab("dyc_damagedisplay")
			dd:DamageDisplay(inst.dychbowner,{hpNewDefault=inst.dychp})
		end
		inst.Label:SetText(" ")
		if inst.dychbowner then
			inst.dychbowner.dychealthbar=nil
		end
		if inst.dychbtext then
			inst.dychbtext:Remove()
		end
		if inst.dychbtask then
			inst.dychbtask:Cancel()
		end
	end
	
	function inst:DYCHBSetTimer(t)
		timer=t
	end
	
	inst.dychbtask=inst:DoPeriodicTask(FRAMES, function()
	
		if not inst.dycHbStarted then return end
		local owner=inst.dychbowner
		if not owner then return end
		
		local attacker=inst.dychbattacker
		local health=nil
		
		if not IsClient() then
			health=owner.components.health
		else
			health=owner.replica.health
		end
		
		
		
		
		if not owner:IsValid() or (not IsDST() and not IsDistOK(owner)) or (IsClient() and not owner:HasTag("player")) or health==nil or health:IsDead() or timer>=TUNING.DYC_HEALTHBAR_DURATION then
			if not IsClient() then
				inst:Remove()
				return
			end
		end
		
		if owner.dychealthbar~=inst then
			inst:Remove()
			return
		end
		
		if not owner:IsValid() then
			return
		end
		
		
		
		
		local hpCurrentNew=0
		local hpMaxNew=0
		if not IsDST() then
			hpCurrentNew=health.currenthealth
			hpMaxNew=health.maxhealth
		else
			hpCurrentNew=inst.dychp
			hpMaxNew=inst.dychpmax
		end
		
		
		if health~=nil and (TUNING.DYC_HEALTHBAR_FORCEUPDATE==true or hpCurrent ~= hpCurrentNew or hpMax ~= hpMaxNew) then
			hpCurrent = hpCurrentNew
			hpMax = hpMaxNew
			inst.Label:Enable(true)
			inst.Label:SetText(GetHpText(hpCurrent,hpMax))
			inst.dychbtext.Label:Enable(true)
			if TUNING.DYC_HEALTHBAR_VALUE then
				if TUNING.DYC_HEALTHBAR_POSITION~=0 then
					inst.dychbtext.Label:SetText(string.format("%d/%d\n   ",hpCurrent,hpMax))
				else
					inst.dychbtext.Label:SetText(string.format("  \n  \n%d/%d\n   ",hpCurrent,hpMax))
				end
			else
				inst.dychbtext.Label:SetText("")
			end
			if inst.SetHBHeight and inst.dychbheightconst then
				inst:SetHBHeight(inst.dychbheightconst)
			end
			local hpp=hpCurrent/hpMax
			local team_id = team_state.get_player_team(owner)
			if team_id == team_state.TEAM_RED then
				inst.dycol_net:set(1)
			elseif team_id == team_state.TEAM_BLUE then
				inst.dycol_net:set(2)
			else
				inst.dycol_net:set(3)
			end
			--[[if TUNING.DYC_HEALTHBAR_COLOR==nil then
				inst.Label:SetColour(Clamp01((1-hpp)*2),Clamp01(hpp*2),0)
			elseif type(TUNING.DYC_HEALTHBAR_COLOR)=="table" then
				inst.Label:SetColour(TUNING.DYC_HEALTHBAR_COLOR:Get())
			else
				--其他类型颜色方案？
			end]]
		end
		
		local shouldFade=true
		local combat=nil
		if not IsClient() then
			combat=owner.components.combat
		else
			combat=owner.replica.combat
		end
		
		if combat and combat.target then
			shouldFade=false
		else
			if attacker and attacker:IsValid() then
				
				local attackerHealth=nil
				local attackerCombat=nil
				if not IsClient() then
					attackerHealth=attacker.components.health
					attackerCombat=attacker.components.combat
				else
					attackerHealth=attacker.replica.health
					attackerCombat=attacker.replica.combat
				end
				if attackerHealth and not attackerHealth:IsDead() and attackerCombat and attackerCombat.target==owner then
					shouldFade=false
				end
			end
		end
		
		
		
		if shouldFade then
			timer = timer + FRAMES
		else
			timer = 0
		end
		
		if IsDST() or TUNING.DYC_HEALTHBAR_POSITION==0 then
		else
			local pos=owner:GetPosition()
			pos.y = inst.dychbheight or 0
			inst.Transform:SetPosition(pos:Get())
		end
	end)
	
	if IsClient() then
		inst:DoTaskInTime(0,function() 
			inst:InitHB()
		end)
	end
	
	return inst
end


local function DamageDisplay (inst,target,passedData)
	
	if not inst:IsValid() or not target:IsValid() or target.dycddcd==true then
		inst:Remove()
		return
	end
	target.dycddcd=true
	
	local health=nil
	if not IsClient() then
		health=target.components.health
	else
		health=target.replica.health
	end
	
	inst.Transform:SetPosition( ( target:GetPosition() + Vector3(0,GetEntHBHeight(target)*0.65,0) ):Get() )
	local oldhealth=(passedData and passedData.hpOld) or (not IsDST() and target.components.health.currenthealth) or (target.dychealthbar and target.dychealthbar.dychp) or (health and health:IsDead() and 0) or (passedData and passedData.hpOldDefault) or 0
	local ison=false
	local angle=math.random()*360
	local t=TUNING.DYC_HEALTHBAR_DDDURATION/2
	local d=1
	local h=2
	local g=2*h/t/t
	local timer=0
	local vh=d/t
	local vv=math.sqrt(2*g*h)
	local duration=t*2
	local changecolor=false
	local delay=TUNING.DYC_HEALTHBAR_DDDELAY
	local timer2=0
	-- if IsDST() then
		-- inst.Label:SetWorldOffset(0, GetEntHBHeight(target)*0.65, 0)
	-- end
	
	inst.dycddtask=inst:DoPeriodicTask(FRAMES,function()
		if not inst:IsValid() or not target:IsValid()then
			inst.dycddtask:Cancel()
			inst:Remove()
			return
		end
		
		timer2=timer2+FRAMES
		timer=timer2-delay
		
		if timer2>delay then
		
			if ison==false then
				target.dycddcd=false
				local newhealth=(passedData and passedData.hpNew) or (not IsDST() and target.components.health.currenthealth) or (target.dychealthbar and target.dychealthbar.dychp) or (health and health:IsDead() and 0) or (passedData and passedData.hpNewDefault) or 0
				local amount=newhealth-oldhealth
				local absamount=math.abs(amount)
				if absamount<TUNING.DYC_HEALTHBAR_DDTHRESHOLD then
					inst.dycddtask:Cancel()
					inst:Remove()
					return
				else
					ison=true
					inst.Label:Enable(true)
					local sign=""
					if amount>0 then
						inst.Label:SetColour(0, 1, 0)
						sign="+"
					else
						inst.Label:SetColour(1, 0, 0)
						changecolor=true
					end
					
					if absamount<1 then
						inst.Label:SetText(sign..string.format("%.2f",amount))
					elseif absamount<100 then
						inst.Label:SetText(sign..string.format("%.1f",amount))
					else
						inst.Label:SetText(sign..string.format("%d",amount))
					end
				end
			end
			
			local pos=inst:GetPosition()
			local move=Vector3(vh*FRAMES*math.cos(angle),vv*FRAMES,vh*FRAMES*math.sin(angle))
			inst.Transform:SetPosition(pos.x+move.x, pos.y+move.y, pos.z+move.z)
			vv=vv-g*FRAMES
			local fontsize=(1-math.abs(timer/t-1))*(TUNING.DYC_HEALTHBAR_DDSIZE2-TUNING.DYC_HEALTHBAR_DDSIZE1)+TUNING.DYC_HEALTHBAR_DDSIZE1
			inst.Label:SetFontSize(fontsize)
			if changecolor then
				local greenandblue=1-Clamp01(timer/t-0.5)
				inst.Label:SetColour(1, greenandblue, greenandblue)
			end
			if timer>=duration then
				inst.dycddtask:Cancel()
				inst:Remove()
			end
		
		end
		
		
	end)
end

local function dycddfn ()
	local inst =  fn()
	inst.Label:SetFontSize(TUNING.DYC_HEALTHBAR_DDSIZE1)
	inst.Label:Enable(false)
	inst.InitHB=nil
	inst.DamageDisplay=DamageDisplay
	return inst
end


return 
Prefab( "common/dyc_damagedisplay", dycddfn, assets, prefabs),
Prefab( "common/dyc_healthbarchild", fn, assets, prefabs),
Prefab( "common/dyc_healthbar", dychbfn, assets, prefabs)


