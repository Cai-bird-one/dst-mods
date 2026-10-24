name = "【月落繁星】饥荒pvp专用mod（测试版）"
description =
    "为饥荒联机版红蓝团队对抗准备的PVP整合模组。" ..
    "\n\n【选队与准备】" ..
    "\n- 进入选人界面后，点击顶部的“队伍”按钮选择等待、OB、红队或蓝队" ..
    "\n- 点击“Roll骰子”可投出1至100点，结果会显示在聊天栏" ..
    "\n- 管理员可点击“自动分队”分配等待玩家或重新分配全部参赛玩家" ..
    "\n- 管理员可使用“锁定队伍”禁止玩家自行换队" ..
    "\n- 比赛开始后新加入且尚未参赛的玩家会进入OB" ..
    "\n\n【比赛功能】" ..
    "\n- 红蓝双方使用独立队伍聊天，上下洞后仍可与队友交流" ..
    "\n- 地图显示自己和队友的位置，红蓝玩家脚下显示队伍颜色圈" ..
    "\n- 按Tab打开玩家列表，可查看红队、蓝队、OB和等待玩家" ..
    "\n- 红蓝队员可在暂停菜单发起投降投票；存活计1票、死亡计0.5票，赞成票须严格大于反对票的两倍" ..
    "\n- 支持队内快捷宣告，科技书效果仅与队友共享" ..
    "\n\n【OB使用】" ..
    "\n- 选择OB后不会参与战斗，可自由观察比赛" ..
    "\n- 点击左下角按钮，可切换大视野和夜视" ..
    "\n- 打开地图后右键点击目标位置即可传送" ..
    "\n- OB拥有全图、快速移动和上下洞能力，并可查看玩家与生物血量" ..
    "\n- 按J键可隐藏或显示队伍信息面板" ..
    "\n\n【比赛规则】" ..
    "\n- 第一天玩家互相攻击时，仅空手拳击可造成正常伤害与受击动作" ..
    "\n- 第一天提供防催眠、冰冻、燃烧和旋风杖保护" ..
    "\n- 包含Boss掉落、季节Boss和泰拉瑞亚之眼规则调整" ..
    "\n\n【连接提示】" ..
    "\n- 当前为测试版本；更新后请完整重启游戏和服务器"
author = "乔尔,冷泠,蔡鸟bird"
version = "1.0beta.27"
priority = 9007199254740991

forumthread = ""

dst_compatible = true
all_clients_require_mod = true

api_version = 10  

icon_atlas = "modicon.xml"
icon = "modicon.tex"




configuration_options =
{
	{
		name = "extra_loot",
		label = "boss三倍掉落",
		hover = "",
		options =	{
			{description = "开启", data = true, hover = ""},
			{description = "关闭", data = false, hover = ""},
					},
		default = true,
	},
	{
		name = "quick_announce",
		label = "队内快捷宣告",
		hover = "",
		options =	{
			{description = "开启", data = true, hover = ""},
			{description = "关闭", data = false, hover = ""},
					},
		default = true,
	},
	{
		name = "better_show_teammate",
		label = "队友显示优化",
		hover = "",
		options =	{
			{description = "开启", data = true, hover = ""},
			{description = "关闭", data = false, hover = ""},
					},
		default = true,
	},
	{
		name = "hbstyle",
		label = "Style样式",
		hover = "",
		options =	{
						{description = "Hidden隐藏", data = "hidden", hover = "Hide healthbar 隐藏血条"},
						{description = "♥♥♥♡♡", data = "heart", hover = "Heart. 心形血格"},
						{description = "●●●○○", data = "circle", hover = "Circle. 圆形血格"},
						{description = "■■■□□", data = "square", hover = "Square. 方块形血格"},
						{description = "◆◆◆◇◇", data = "diamond", hover = "Diamond. 菱形血格"},
						{description = "★★★☆☆", data = "star", hover = "Star. 星形血格"},
					},
		default = "heart",
	},
	
	{
		name = "value",
		label = "Value数值",
		hover = "Show health value?是否显示生命值",
		options =	{
						{description = "Shown显示", data = true, hover = ""},
						{description = "Hidden隐藏", data = false, hover = ""},
					},
		default = true,
	},
	
	{
		name = "hblength",
		label = "Length长度",
		hover = "",
		options =	{
						{description = "5", data = 5, hover = ""},
						{description = "6", data = 6, hover = ""},
						{description = "8", data = 8, hover = ""},
						{description = "10", data = 10, hover = ""},
					},
		default = 10,
	},
	
	{
		name = "hbpos",
		label = "Pos位置",
		hover = "",
		options =	{
						{description = "Bottom脚下", data = 0, hover = ""},
						{description = "OverHead头顶", data = 1, hover = ""},
					},
		default = 1,
	},
	
	{
		name = "hbcolor",
		label = "Color颜色",
		hover = "",
		options =	{
						{description = "Dynamic动态", data = "dynamic", hover = ""},
						{description = "White白", data = "white", hover = ""},
						{description = "Black黑", data = "black", hover = ""},
						{description = "Red红", data = "red", hover = ""},
						{description = "Green绿", data = "green", hover = ""},
						{description = "Blue蓝", data = "blue", hover = ""},
						{description = "Yellow黄", data = "yellow", hover = ""},
						{description = "Cyan青", data = "cyan", hover = ""},
						{description = "Magenta品红", data = "magenta", hover = ""},
						{description = "Gray灰", data = "gray", hover = ""},
						{description = "Orange橙", data = "orange", hover = ""},
						{description = "Purple紫", data = "purple", hover = ""},
					},
		default = "dynamic",
	},
	
	{
		name = "ddon",
		label = "DD显伤",
		hover = "Damage display. 伤害显示",
		options =	{
						{description = "On开启", data = true, hover = ""},
						{description = "Off关闭", data = false, hover = ""},
					},
		default = true,
	},

    {
        name = "preselect_lobby",
        label = "预选角色界面",
        hover = "在初始选人流程中插入一个预选确认界面。",
        options = {
            {description = "开启", data = true, hover = ""},
            {description = "关闭", data = false, hover = ""},
        },
        default = true,
    },
    {
        name = "LATE_JOIN",
        label = "允许中途加入",
        hover = "游戏开始后是否允许新玩家继续连接。",
        options = {
            {description = "是", data = true, hover = ""},
            {description = "否", data = false, hover = ""},
        },
        default = true,
    },
    {
        name = "START_PAUSE_DURATION",
        label = "开局等待时间",
        hover = "首个玩家生成后暂停指定时间再自动开始；管理员可以提前开始游戏。",
        options = {
            {description = "无开局暂停", data = 0, hover = ""},
            {description = "10 秒", data = 10, hover = ""},
            {description = "20 秒", data = 20, hover = ""},
            {description = "30 秒", data = 30, hover = ""},
            {description = "40 秒", data = 40, hover = ""},
            {description = "50 秒", data = 50, hover = ""},
            {description = "60 秒", data = 60, hover = ""},
			{description = "90 秒", data = 90, hover = ""},
			{description = "120 秒", data = 120, hover = ""},
        },
        default = 30,
    },
    {
        name = "ADMIN_CLIENT_MODS",
        label = "允许管理员启用本地 MOD",
        hover = "开启后，管理员进入服务器时会重新加载自己原本启用的客户端 MOD；关闭后所有人的客户端 MOD 都由原版禁用。",
        options = {
            {description = "开启", data = true, hover = ""},
            {description = "关闭", data = false, hover = ""},
        },
        default = true,
    },
    {
        name = "AUTO_WALKING_STICK",
        label = "少人队自动发木手杖",
        hover = "第一天黄昏为人数较少的队伍成员发放木手杖。",
        options = {
            {description = "开启", data = true, hover = ""},
            {description = "关闭", data = false, hover = ""},
        },
        default = true,
    },
    {
        name = "shadowprotector_change",
        label = "影人修改",
        hover = "老麦影人第一天不会攻击非队友的玩家。",
        options = {
            {description = "开启", data = true, hover = ""},
            {description = "关闭", data = false, hover = ""},
        },
        default = true,
    },}
