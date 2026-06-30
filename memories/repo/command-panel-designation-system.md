# 指令面板与资源标记系统

## 概述
玩家通过右侧指令面板（CommandPanel）标记资源，定居者只采集被标记的资源。

## 文件
- `scripts/ui/command_panel.gd` - 指令面板UI逻辑
- `scripts/core/game.gd` - 标记数据存储、标记模式、AI过滤
- `scripts/core/world_renderer.gd` - 标记视觉覆盖层
- `scenes/game.tscn` - 指令面板场景节点

## 工作流
1. 玩家点击指令面板上的按钮（采矿/伐木/农业/搬运）
2. 游戏进入标记模式（`designation_mode = true`）
3. 玩家在地图上点选或拖拽框选资源
4. 被选中的资源显示对应颜色的边框标记
5. 定居者AI只能看到被标记的资源，只采集标记的资源

## 关键数据
- `Game.designated_resources: Dictionary` - `"x,y" -> WorkType`
- `Game.designation_mode: bool` - 是否处于标记模式
- `Game.designation_work_type: int` - 当前标记的工作类型

## 标记视觉颜色
- 采矿 (MINING, 0): 灰色边框
- 伐木 (WOODCUTTING, 1): 绿色边框
- 农业 (FARMING, 5): 橙色边框
- 搬运 (HAULING, 6): 蓝色边框

## AI过滤
- `_scan_nearby_resources`: 只包含 `designated_resources` 中的资源
- `_scan_ground_item_storage_tasks`: 当有标记时，只搬运标记的地面物品
- 无标记时，搬运任务仍正常工作（兼容旧行为）
