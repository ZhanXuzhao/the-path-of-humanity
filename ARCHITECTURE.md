# 项目架构文档 — The Path of Humanity

## 目录

1. [项目概述](#1-项目概述)
2. [目录结构](#2-目录结构)
3. [系统架构](#3-系统架构)
4. [游戏启动流程](#4-游戏启动流程)
5. [核心系统详解](#5-核心系统详解)
6. [数据流与依赖关系](#6-数据流与依赖关系)
7. [开发指南](#7-开发指南)

---

## 1. 项目概述

**人类来时路 (The Path of Humanity)** 是一款使用 **Godot 4.6** 引擎开发的 2D 文明演化模拟游戏，受《Factorio》与《RimWorld》启发。

采用 **模块化系统架构**，核心系统之间通过信号 (Signal) 和依赖注入解耦，所有物品/建筑/配方/科技数据集中管理（数据驱动）。

---

## 2. 目录结构

```
the-path-of-humanity/
├── assets/
│   └── art/                  # 图像素材 (SVG源文件，未直接使用)
│       ├── tiles/            # 地形瓦片
│       ├── resources/        # 资源节点
│       ├── buildings/        # 建筑
│       ├── characters/       # 角色
│       └── icons/            # UI图标
│
├── resources/
│   └── item_definitions.gd   # [数据] 物品/建筑/配方/科技定义 (Autoload)
│
├── scenes/
│   ├── main_menu.tscn        # [场景] 主菜单
│   ├── game.tscn             # [场景] 游戏主场景 (节点树根)
│   └── ui/notification.tscn  # [场景] 通知提示组件
│
├── scripts/
│   ├── autoload/
│   │   └── game_manager.gd   # [全局] 游戏管理器 (时间/状态/通知)
│   │
│   ├── core/
│   │   ├── game.gd           # [核心] 游戏主控制器
│   │   ├── world.gd          # [核心] 世界/地图系统 (区块生成/资源分布)
│   │   ├── world_renderer.gd # [核心] 世界渲染器 (绘制地形/资源/建筑)
│   │   ├── texture_generator.gd  # [核心] 运行时纹理生成
│   │   ├── inventory.gd      # [核心] 库存系统 (物品堆叠/转移)
│   │   └── camera_controller.gd  # [核心] 相机控制 (WASD/滚轮/拖拽)
│   │
│   ├── entities/
│   │   └── settler.gd        # [实体] 定居者角色 (属性/技能/需求/AI)
│   │
│   ├── systems/
│   │   ├── building_system.gd   # [系统] 建筑系统 (放置/建造/生产)
│   │   ├── crafting_system.gd   # [系统] 制作系统 (配方/队列)
│   │   └── tech_system.gd       # [系统] 科技系统 (研究/解锁)
│   │
│   └── ui/
│       ├── hud.gd            # [UI] 主界面HUD
│       ├── build_menu.gd     # [UI] 建筑菜单
│       ├── tech_panel.gd     # [UI] 科技面板
│       ├── notification.gd   # [UI] 通知组件
│       └── main_menu.gd      # [UI] 主菜单逻辑
│
├── ARCHITECTURE.md           # 本文件
├── README.md                 # 项目介绍
└── project.godot             # Godot 项目配置
```

---

## 3. 系统架构

### 3.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                      GameManager (Autoload)                      │
│             时间管理 | 游戏状态 | 通知分发                        │
└──────────┬──────────────────────────────────┬───────────────────┘
           │ 全局访问                          │ 全局访问
           ▼                                  ▼
┌──────────────────────┐    ┌──────────────────────────────┐
│    Game (主控制器)     │    │     ItemDefinitions (数据)    │
│  ┌───────┬──────┬───┐ │    │  物品/建筑/配方/科技定义      │
│  │ World │Camera│UI │ │    └──────────────────────────────┘
│  │       │      │   │ │
│  │ WorldRenderer│   │ │              ┌─────────────┐
│  │ (渲染所有精灵) │   │ │              │ Systems     │
│  └───────┴──────┴───┘ │              │ ┌─────────┐ │
└──────────────────────┘              │ │Building │ │
                                      │ │Crafting │ │
                                      │ │Tech     │ │
                                      │ └─────────┘ │
                                      └──────┬──────┘
                                             │
                                    ┌────────▼────────┐
                                    │   Entities      │
                                    │   Settler       │
                                    └─────────────────┘
```

### 3.2 系统分层

| 层级 | 说明 | 包含 |
|------|------|------|
| **全局层** | Autoload 单例，全局可访问 | `GameManager`, `ItemDefinitions` |
| **控制层** | 场景根节点，协调各系统 | `Game` |
| **核心层** | 基础游戏机制 | `World`, `Inventory` |
| **系统层** | 独立功能模块 | `BuildingSystem`, `CraftingSystem`, `TechSystem` |
| **实体层** | 游戏对象 | `Settler` |
| **表现层** | 渲染与UI | `WorldRenderer`, `TextureGenerator`, `HUD`, 各UI组件 |

---

## 4. 游戏启动流程

### 4.1 启动顺序

```
Godot 启动
    │
    ├─ 1. Autoload 初始化
    │   ├── GameManager._ready()
    │   └── ItemDefinitions._ready()
    │       └── 注册所有物品/建筑/配方/科技
    │
    └─ 2. 加载 main_menu.tscn
        │
        └─ 3. 用户点击 "开始游戏"
            │
            └─ 4. GameManager.start_game()
                │
                └─ 5. 切换到 game.tscn
                    │
                    ├─ 6. Game._ready()
                    │   ├── _generate_initial_area()
                    │   │   └── world.ensure_chunk_generated()
                    │   │       └── _generate_chunk()
                    │   │           ├── 使用噪声/随机生成地形
                    │   │           └── 分布自然资源 (树木/矿石/浆果)
                    │   │
                    │   └── _spawn_initial_settlers()
                    │       └── 创建 3 个 Settler 实例
                    │
                    ├─ 7. WorldRenderer._ready()
                    │   ├── TextureGenerator.generate_all()
                    │   │   └── 生成所有纹理 (运行时像素绘制)
                    │   └── _render_existing_chunks()
                    │       ├── 遍历已生成区块
                    │       ├── 为每个 Tile 创建 Sprite2D
                    │       ├── 为每个 Resource 创建 Sprite2D
                    │       └── 为每个 Building 创建 Sprite2D
                    │
                    └─ 8. 游戏进入帧循环
                        ├── GameManager._process() → 更新时间/昼夜
                        ├── BuildingSystem.process_buildings() → 自动生产
                        ├── CraftingSystem.process_crafting() → 制作进度
                        └── TechSystem.process_research() → 研究进度
```

### 4.2 帧循环 (每帧)

```
Game._process(delta)
  └── 如果处于建造模式 → _update_build_preview()

GameManager._process(delta)
  └── 如果处于 PLAYING 状态
      ├── game_time += delta * time_speed * (24/day_length)
      └── 如果跨天 → 发射 day_changed 信号

BuildingSystem.process_buildings(delta)
  └── 遍历所有已完成建筑
      └── 如果有生产配方 → 累加 timer → 到周期后消耗材料/产出物品

CraftingSystem.process_crafting(delta)
  └── 遍历活跃制作任务 → 累加 progress → 完成后产出

TechSystem.process_research(delta)
  └── 如果有当前研究 → 累加 progress → 完成后解锁科技/发射信号
```

---

## 5. 核心系统详解

### 5.1 物品定义系统 — `ItemDefinitions`

**文件**: `resources/item_definitions.gd`  
**类型**: Autoload 单例 (`extends Node`)

数据驱动设计的核心，集中管理所有游戏数据：

```
ItemDefinitions
├── static items: Dictionary      # 物品数据 {id: ItemData}
├── static buildings: Dictionary  # 建筑数据 {id: BuildingData}
├── static recipes: Dictionary    # 配方数据 {id: RecipeData}
└── static techs: Dictionary      # 科技数据 {id: TechData}
```

**内部数据结构** (Inner Classes):
- `ItemData` — id, name, description, category, max_stack, weight, nutrition...
- `BuildingData` — id, name, size, hp, work_cost, materials, produces, consumes...
- `RecipeData` — id, inputs, outputs, work_time, required_tech, crafted_at
- `TechData` — id, cost, research_time, prerequisites, unlocks, category

**设计特点**: 所有数据在游戏启动时一次性注册，通过静态方法全局访问。

---

### 5.2 世界系统 — `World`

**文件**: `scripts/core/world.gd`  
**类型**: `extends Node2D`, `class_name World`

采用**区块化 (Chunk)** 设计，按需生成：

```
World
├── CHUNK_SIZE = 16             # 每个区块 16x16 格
├── chunks: Dictionary          # {Vector2i(区块坐标): ChunkData}
│
├── ChunkData
│   ├── pos: Vector2i
│   ├── tiles: Dictionary       # {Vector2i(局部坐标): TileType}
│   ├── resources: Dictionary   # {Vector2i(局部坐标): ResourceDeposit}
│   ├── buildings: Dictionary   # {Vector2i(局部坐标): building_id}
│   └── is_generated: bool
│
├── ResourceDeposit
│   ├── type: ResourceNodeType  # TREE / STONE_DEPOSIT / IRON_DEPOSIT ...
│   ├── amount: float           # 剩余资源量
│   └── max_amount: float
│
├── TileType 枚举 (12种)
│   GRASS, DIRT, SAND, WATER, DEEP_WATER,
│   STONE, FOREST, MOUNTAIN, SNOW, ROAD, FLOOR, WALL
│
└── ResourceNodeType 枚举 (7种)
    NONE, TREE, STONE_DEPOSIT, IRON_DEPOSIT,
    COPPER_DEPOSIT, COAL_DEPOSIT, BERRY_BUSH, WILDLIFE
```

**区块生成流程**:
1. `ensure_chunk_generated(chunk_pos)` → 检查是否已生成
2. `_generate_chunk(chunk)` → 使用随机数生成地形 + 分布资源
3. 地形概率: 草地(主体) > 森林 > 岩石 > 水域 > 沙地 > 泥土
4. 资源分布: 树木只在森林中，矿石在岩石中，浆果在草地上

---

### 5.3 世界渲染器 — `WorldRenderer`

**文件**: `scripts/core/world_renderer.gd`  
**类型**: `extends Node2D`, `class_name WorldRenderer`  
**位置**: Game > World > WorldRenderer

将 World 的数据转换为可视化的 Sprite2D 节点：

```
WorldRenderer
├── tile_textures: Dictionary     # TileType → Texture2D
├── resource_textures: Dictionary # ResourceNodeType → Texture2D
├── building_textures: Dictionary # building_id → Texture2D
│
├── tile_sprites: Dictionary      # Vector2i → Sprite2D (已渲染的瓦片)
├── resource_sprites: Dictionary  # Vector2i → Sprite2D (已渲染的资源)
└── building_sprites: Dictionary  # Vector2i → Sprite2D (已渲染的建筑)
```

**渲染流程**:
1. `_ready()` → 生成纹理 → 连接信号 → 渲染已有区块
2. 每个 Tile/Resource/Building 对应一个 Sprite2D 节点
3. 监听 `tile_changed` / `resource_depleted` / `building_placed` 信号动态更新
4. Z-index 分层: 瓦片=0, 资源=1, 建筑=2, 角色=3

---

### 5.4 纹理生成器 — `TextureGenerator`

**文件**: `scripts/core/texture_generator.gd`  
**类型**: `extends Node`, `class_name TextureGenerator`

在运行时用代码生成所有纹理，无需外部图像文件：

```
TextureGenerator
├── generate_all() → Dictionary
│   ├── tiles: Dictionary       # TileType → Texture2D
│   ├── resources: Dictionary   # ResourceNodeType → Texture2D
│   ├── buildings: Dictionary   # building_id → Texture2D
│   └── character: Dictionary   # "settler" → Texture2D
│
├── _solid_tile(bg, accent)     # 纯色底 + 网格线 (32x32)
└── _solid_tex(w, h, c1, c2)    # 纯色底 + 条纹 (任意尺寸)
```

**实现细节**:
- 使用 `Image.create()` + `Image.set_pixel()` 逐像素绘制
- 地形瓦片: 底色 + 每8像素的网格线 (装饰色)
- 建筑/资源: 底色 + 水平条纹 (装饰色)
- 角色: 像素风格人形，直接填充像素块

---

### 5.5 建筑系统 — `BuildingSystem`

**文件**: `scripts/systems/building_system.gd`  
**类型**: `extends Node`, `class_name BuildingSystem`

```
BuildingSystem
├── buildings: Dictionary       # {Vector2i(格坐标): BuildingInstance}
│
├── BuildingInstance
│   ├── building_id: String
│   ├── grid_pos: Vector2i      # 主格子位置
│   ├── hp / max_hp: int
│   ├── is_completed: bool
│   ├── construction_progress: float
│   ├── production_timer: float
│   ├── inventory: Inventory    # 建筑内部库存
│   └── assigned_settlers: Array
│
├── can_place_building(id, pos) → {can_place, reason}
│   ├── 检查所有占用格子是否空置
│   ├── 检查地形是否可行走
│   └── 检查是否在边界内
│
├── place_building(id, pos)     # 注册建筑到所有占用格子
├── add_construction_progress() # 增加建造进度
├── process_buildings(delta)    # 处理自动生产
└── remove_building(pos)        # 拆除建筑
```

**信号**:
- `building_placed(building_id, pos)`
- `building_removed(building_id, pos)`
- `building_completed(pos)`
- `production_output(pos, item_id, amount)`

---

### 5.6 定居者系统 — `Settler`

**文件**: `scripts/entities/settler.gd`  
**类型**: `extends Node2D`, `class_name Settler`

```
Settler
├── 基本属性
│   ├── settler_name / settler_id
│   ├── hp / max_hp
│   ├── move_speed
│   └── carry_capacity
│
├── 属性 stats (6项, 范围3-8)
│   ├── strength     力量 → 近战/搬运
│   ├── constitution 体质 → 生命/耐力
│   ├── dexterity    敏捷 → 移动/制作
│   ├── intelligence 智力 → 研究/医疗
│   ├── perception   感知 → 采集/狩猎
│   └── charisma     魅力 → 交易/社交
│
├── 技能 skills (9项, 范围1-5)
│   mining, woodcutting, construction, crafting,
│   cooking, farming, research, combat, social
│
├── 需求 needs (5项, 0-100)
│   ├── hunger  饱食度 → 每小时-5
│   ├── rest    精力   → 每小时-3
│   ├── comfort 舒适度 → 每小时-1
│   ├── social  社交   → 每小时-2
│   └── safety  安全感 → 每小时-0.5
│
└── 状态 state
    IDLE, MOVING, WORKING, EATING, SLEEPING, FLEEING, COMBAT
```

---

### 5.7 科技系统 — `TechSystem`

**文件**: `scripts/systems/tech_system.gd`  
**类型**: `extends Node`, `class_name TechSystem`

```
TechSystem
├── researched_techs: Array[String]      # 已研究科技
├── current_research: ResearchProject    # 当前研究
├── unlocked_buildings: Array[String]    # 已解锁建筑
├── unlocked_recipes: Array[String]      # 已解锁配方
│
├── start_research(tech_id) → bool       # 开始研究
├── process_research(delta)              # 处理进度
├── can_research(tech_id) → {can, reason} # 检查前置
└── get_available_techs() → Array        # 可研究列表
```

**科技树**:
```
原始工具 ─→ 建筑构造 ─→ 金属加工 ─→ 高级冶金
                  ├→ 烹饪技术
                  ├→ 木工技术
                  ├→ 石工技术
                  └→ 科学研究
```

---

### 5.8 制作系统 — `CraftingSystem`

**文件**: `scripts/systems/crafting_system.gd`  
**类型**: `extends Node`, `class_name CraftingSystem`

```
CraftingSystem
├── crafting_queues: Dictionary  # {Vector2i(建筑位置): Array[CraftingJob]}
├── active_jobs: Array[CraftingJob]
│
├── add_to_queue(recipe_id, building_pos, settler_id)
├── remove_from_queue(pos, index)
└── process_crafting(delta)
```

---

### 5.9 库存系统 — `Inventory`

**文件**: `scripts/core/inventory.gd`  
**类型**: `extends RefCounted`, `class_name Inventory`

```
Inventory
├── items: Array[ItemStack]
├── max_slots: int
├── capacity: int (0=不限)
│
├── add_item(item_id, amount) → remaining
├── remove_item(item_id, amount) → removed
├── has_item(item_id, amount) → bool
├── get_item_count(item_id) → int
└── 序列化: to_dict() / from_dict()
```

---

### 5.10 游戏管理器 — `GameManager`

**文件**: `scripts/autoload/game_manager.gd`  
**类型**: Autoload 单例 (`extends Node`)

全局游戏状态管理：

```
GameManager
├── 时间系统
│   ├── game_time: float       # 当前时间(小时)
│   ├── time_speed: float      # 时间流速倍率
│   ├── day_length: float      # 一天的现实秒数
│   └── current_day: int
│
├── 游戏状态
│   ├── state: GameState       # MENU/PLAYING/PAUSED/GAME_OVER
│   └── colony_name: String
│
├── 昼夜判断
│   ├── is_daytime() → bool
│   └── get_daylight_factor() → float (0-1)
│
└── 通知系统
    ├── show_notification(msg, type)
    └── NotificationType: INFO/WARNING/ERROR/SUCCESS/RESEARCH/COMBAT
```

---

### 5.11 UI 系统

| 组件 | 文件 | 功能 |
|------|------|------|
| **HUD** | `hud.gd` | 顶部时间/资源显示，底部工具栏 |
| **BuildMenu** | `build_menu.gd` | 按分类列出可建造建筑，显示材料需求 |
| **TechPanel** | `tech_panel.gd` | 显示科技树，开始研究，进度追踪 |
| **Notification** | `notification.gd` | 淡入淡出通知提示 |
| **MainMenu** | `main_menu.gd` | 开始/读取/退出 |

---

## 6. 数据流与依赖关系

### 6.1 数据流方向

```
用户输入 (鼠标/键盘)
    │
    ▼
Game._input() / _process()
    │
    ├─ 建造模式 → BuildingSystem.place_building()
    │               │
    │               ├─ World.set_building_at()     ← 更新世界数据
    │               └─ WorldRenderer._on_building_placed() ← 更新渲染
    │
    ├─ 建造菜单 → BuildMenu → 选择建筑
    ├─ 科技面板 → TechPanel → TechSystem.start_research()
    └─ 工具栏   → HUD → GameManager.toggle_pause() / set_time_speed()
```

### 6.2 系统依赖关系

```
GameManager (独立, 全局访问)
ItemDefinitions (独立, 数据仓库)

Game
├── World (独立)
│   └── WorldRenderer (依赖 World, BuildingSystem)
├── BuildingSystem (依赖 World, Inventory, ItemDefinitions)
├── CraftingSystem (依赖 ItemDefinitions)
├── TechSystem (依赖 ItemDefinitions)
├── Camera (独立)
└── UI
    ├── HUD (依赖 GameManager, ItemDefinitions)
    ├── BuildMenu (依赖 TechSystem, BuildingSystem, ItemDefinitions)
    ├── TechPanel (依赖 TechSystem, ItemDefinitions, GameManager)
    ├── Notification (独立)
    └── MainMenu (依赖 GameManager)

Settler (依赖 Inventory, ItemDefinitions)
```

### 6.3 信号 (Signal) 通信

```
GameManager
├── day_changed(day)        → HUD 更新天数显示
├── time_changed(hour)       → HUD 更新时间显示
├── notification(msg, type)  → HUD → Notification 显示
└── game_paused(is_paused)

World
├── tile_changed(pos, type)  → WorldRenderer 更新瓦片
└── resource_depleted(pos)   → WorldRenderer 移除资源

BuildingSystem
├── building_placed(id, pos) → WorldRenderer 渲染建筑
├── building_removed(id, pos)→ WorldRenderer 清除建筑
├── building_completed(pos)
└── production_output(pos, item_id, amount)

CraftingSystem
├── crafting_started(recipe_id, building_pos, settler_id)
├── crafting_completed(recipe_id, building_pos)
└── crafting_queue_changed(building_pos)

TechSystem
├── research_started(tech_id)
├── research_completed(tech_id)
└── tech_unlocked(tech_id)

Settler
├── needs_changed(need_id, value)
├── task_assigned(task_id)
└── task_completed(task_id)
```

---

## 7. 开发指南

### 7.1 添加新物品

在 `item_definitions.gd` 的 `_register_items()` 中添加：

```gdscript
_add_item("new_item_id", "显示名称", "描述", ItemCategory.RAW_MATERIAL, 
           max_stack, weight, icon_frame, nutrition, fuel_value, value)
```

### 7.2 添加新建筑

在 `item_definitions.gd` 的 `_register_buildings()` 中添加：

```gdscript
_add_building("new_building", "建筑名", "描述", BuildingCategory.PRODUCTION,
              Vector2i(2, 2), hp, work_cost, {"wood": 10}, {}, {}, 0.0, 0, icon)
```

### 7.3 添加新配方

在 `item_definitions.gd` 的 `_register_recipes()` 中添加：

```gdscript
_add_recipe("recipe_id", "配方名", "描述", {"input": 2}, {"output": 1}, 
            work_time, "required_tech", "crafted_at_building")
```

### 7.4 添加新科技

在 `item_definitions.gd` 的 `_register_techs()` 中添加：

```gdscript
_add_tech("tech_id", "科技名", "描述", {"cost_item": 10}, research_time,
          ["prerequisite_tech"], ["unlock_building_id"], "分类")
```

### 7.5 添加新纹理

在 `texture_generator.gd` 对应的生成函数中添加：

```gdscript
# 在 _generate_tiles() 中:
tiles[World.TileType.NEW_TYPE] = _solid_tile(Color("#aabbcc"), Color("#ddeeff"))

# 在 _generate_buildings() 中:
bld["new_building_id"] = _solid_tex(width, height, Color("#aabbcc"), Color("#ddeeff"))
```

### 7.6 场景节点约定

添加新场景或节点时，遵循以下层级约定：

```
Game (Node2D)
├── World (Node2D)              # 世界系统
│   └── WorldRenderer (Node2D)  # 世界渲染器
├── Camera (Camera2D)           # 相机
├── Systems (Node)              # 系统容器
│   ├── BuildingSystem (Node)
│   ├── CraftingSystem (Node)
│   └── TechSystem (Node)
└── UI (CanvasLayer)            # UI容器
    ├── HUD (CanvasLayer)
    ├── BuildMenu (Panel)
    └── TechPanel (Panel)
```
