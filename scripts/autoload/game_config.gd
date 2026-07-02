# 游戏配置 - Game Config (Autoload)
# 所有脚本通过 GameConfig.属性名 直接访问，无需经过 Dictionary 中转
# 数值直接写死在默认值中，参照 resources/game_settings.cfg
extends Node

# ===== 时间设置 =====
var day_length: float = 240.0

# ===== 相机设置 =====
var scroll_speed: float = 1000.0
var edge_scroll_margin: int = 20

# ===== 定居者设置 =====
var carry_capacity: float = 50.0
var base_move_speed: float = 60.0
var dexterity_move_bonus: float = 3.0
var base_hp: float = 80.0
var constitution_hp_bonus: float = 4.0
var hunger_decay_per_hour: float = 4.17
var rest_decay_per_hour: float = 5.0
var comfort_decay_per_hour: float = 1.0
var social_decay_per_hour: float = 2.0
var safety_decay_per_hour: float = 0.5
var food_restore_amount: float = 100.0
var sleep_restore_per_hour: float = 50.0
var sleep_min_time: float = 3.0
var sleep_max_time: float = 8.0
var storage_search_radius: float = 300.0
var food_search_radius: float = 400.0
var passive_heal_per_hour: float = 5.0

# ===== 资源采集设置 =====
var harvest_amount: float = 5.0
var harvest_count: int = 5
var resource_amount_multiplier: float = 5.0

# ===== 工作速度设置 =====
var work_speed_base: float = 1.0
var work_speed_level_bonus: float = 0.1

# ===== 工作优先级设置 =====
var mining_priority: int = 2
var woodcutting_priority: int = 3
var construction_priority: int = 4
var crafting_priority: int = 3
var cooking_priority: int = 2
var farming_priority: int = 2
var hauling_priority: int = 1
var research_priority: int = 3
var combat_priority: int = 1
var hunting_priority: int = 3
var repair_priority: int = 3

# ===== 速度档位 =====
var speed_levels: Array[float] = [0.1, 0.2, 0.5, 1.0, 2.0, 3.0, 5.0, 10.0]

# ===== 世界设置 =====
var chunk_size: int = 16
var world_chunks_x: int = 3
var world_chunks_y: int = 3
var initial_settler_count: int = 1
var initial_boar_count: int = 3

# ===== 建筑设置 =====
var storage_rack_capacity: int = 10000

# ===== 敌对敌人设置 =====
var enemy_base_hp: float = 80.0
var enemy_hp_variance: float = 40.0
var enemy_attack_damage: float = 5.0
var enemy_attack_cooldown: float = 2.5
var enemy_base_move_speed: float = 30.0
var enemy_move_speed_variance: float = 15.0
var enemy_arrow_damage: float = 5.0
var enemy_arrow_range: float = 4.0  # 格数
var enemy_arrow_speed: float = 200.0
