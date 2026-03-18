-- Infectious Mod
-- Aggressive apocalyptic zombies that infect all animalia mobs

local S = core.get_translator("infectious")

-- =============================================================================
-- Configuration
-- =============================================================================

local ZOMBIE_HP          = 30
local ZOMBIE_DAMAGE      = 6
local ZOMBIE_SPEED       = 4.5
local ZOMBIE_RANGE       = 64
local ZOMBIE_ATTACK_DIST = 2.5
local ZOMBIE_KNOCKBACK   = 5
local ZOMBIE_JUMP_HEIGHT = 6

local INFECTED_HP        = 25
local INFECTED_DAMAGE    = 5
local INFECTED_SPEED     = 5
local INFECT_CHANCE      = 0.3

local SPAWN_CHANCE_NIGHT = 500

-- =============================================================================
-- Void Reaper stacking wither system
-- =============================================================================

local VOID_WITHER_DURATION   = 10    -- each application lasts 10 seconds
local VOID_WITHER_TICK       = 0.5   -- damage every 0.5 seconds
local VOID_WITHER_BASE_DMG   = 2     -- damage per stack per tick
local VOID_WITHER_MAX_STACKS = 10
local VOID_WITHER_RESET_TIME = 3     -- stacks reset after 3s of no new hits

local void_wither_targets = {}  -- key -> {target, stacks, timer, remaining, last_hit}

local function apply_void_wither(target)
    if not target or not target:get_pos() then return end
    local key = tostring(target)
    local existing = void_wither_targets[key]
    local stacks
    if existing then
        existing.stacks = math.min(existing.stacks + 1, VOID_WITHER_MAX_STACKS)
        existing.remaining = VOID_WITHER_DURATION
        existing.last_hit = 0
        stacks = existing.stacks
    else
        void_wither_targets[key] = {
            target = target,
            stacks = 1,
            timer = 0,
            remaining = VOID_WITHER_DURATION,
            last_hit = 0,
        }
        stacks = 1
    end

    -- Wither particles on application (scales with stacks)
    local pos = target:get_pos()
    if pos then
        core.add_particlespawner({
            amount = 5 + stacks * 2,
            time = 0.3,
            minpos = vector.subtract(pos, 0.4),
            maxpos = vector.add(pos, {x = 0.4, y = 1.5, z = 0.4}),
            minvel = {x = -0.5, y = 0.5, z = -0.5},
            maxvel = {x = 0.5, y = 1.5, z = 0.5},
            minacc = {x = 0, y = 0.2, z = 0},
            maxacc = {x = 0, y = 0.5, z = 0},
            minexptime = 0.4, maxexptime = 1.0,
            minsize = 1, maxsize = 2,
            texture = "default_dirt.png^[colorize:#6020A0FF",
            glow = 8,
        })
    end
end

-- Process void wither in globalstep (added to spawner globalstep later would be messy,
-- so register a separate one)
core.register_globalstep(function(dtime)
    for key, vw in pairs(void_wither_targets) do
        local obj = vw.target
        if not obj or not obj:get_pos() then
            void_wither_targets[key] = nil
        else
            vw.timer = vw.timer + dtime
            vw.remaining = vw.remaining - dtime
            vw.last_hit = vw.last_hit + dtime

            -- Reset stacks if no new hit for 3 seconds
            if vw.last_hit >= VOID_WITHER_RESET_TIME then
                vw.stacks = 0
            end

            if vw.remaining <= 0 or vw.stacks <= 0 then
                void_wither_targets[key] = nil
            else
                -- Higher stacks = faster ticks (0.5s at 1 stack, 0.05s at 10 stacks)
                local tick_rate = VOID_WITHER_TICK / vw.stacks
            if vw.timer >= tick_rate then
                vw.timer = 0
                local dmg = VOID_WITHER_BASE_DMG * vw.stacks
                -- True damage: bypass armor
                local ent = not obj:is_player() and obj:get_luaentity() or nil
                if ent and ent._hp then
                    ent._hp = ent._hp - dmg
                elseif obj:is_player() then
                    local hp = obj:get_hp()
                    if hp and hp > 0 then
                        obj:set_hp(hp - dmg, {type = "set_hp", wither = true})
                    end
                end
                -- Purple particles
                local pos = obj:get_pos()
                if pos then
                    core.add_particlespawner({
                        amount = 3 * vw.stacks, time = 0.3,
                        minpos = vector.subtract(pos, 0.3),
                        maxpos = vector.add(pos, {x = 0.3, y = 1.5, z = 0.3}),
                        minvel = {x = -0.3, y = 0.3, z = -0.3},
                        maxvel = {x = 0.3, y = 1.0, z = 0.3},
                        minexptime = 0.3, maxexptime = 0.8,
                        minsize = 1, maxsize = 2,
                        texture = "default_dirt.png^[colorize:#6020A0FF",
                        glow = 6,
                    })
                end
            end
            end
        end
    end
end)
local SPAWN_MAX_LIGHT    = 7       -- only spawn where light level <= this

local ZOMBIE_TAG = "infectious:aggressive"

-- Bloodmoon integration: check for multipliers
local function get_damage_mult()
    if bloodmoon and bloodmoon.is_active and bloodmoon.is_active() then
        return bloodmoon.get_damage_mult()
    end
    return 1.0
end

local function get_speed_mult()
    if bloodmoon and bloodmoon.is_active and bloodmoon.is_active() then
        return bloodmoon.get_speed_mult()
    end
    return 1.0
end

-- Model info
local MODEL = "character.b3d"
local ANIM_STAND     = {x = 0, y = 79}
local ANIM_WALK      = {x = 168, y = 187}
local ANIM_WALK_ATK  = {x = 200, y = 219}

-- Animalia mobs with their models and zombified textures
local ANIMALIA_MOBS = {
    {name = "animalia:cow",          mesh = "animalia_cow.b3d",      tex = "infectious_z_cow_1.png",         w = 0.5,  h = 1.0},
    {name = "animalia:pig",          mesh = "animalia_pig.b3d",      tex = "infectious_z_pig_1.png",         w = 0.35, h = 0.7},
    {name = "animalia:sheep",        mesh = "animalia_sheep.b3d",    tex = "infectious_z_sheep.png",         w = 0.4,  h = 0.8},
    {name = "animalia:chicken",      mesh = "animalia_chicken.b3d",  tex = "infectious_z_chicken_1.png",     w = 0.25, h = 0.5},
    {name = "animalia:wolf",         mesh = "animalia_wolf.b3d",     tex = "infectious_z_wolf_1.png",        w = 0.35, h = 0.7},
    {name = "animalia:fox",          mesh = "animalia_fox.b3d",      tex = "infectious_z_fox_1.png",         w = 0.35, h = 0.5},
    {name = "animalia:grizzly_bear", mesh = "animalia_bear.b3d",     tex = "infectious_z_bear_grizzly.png",  w = 0.5,  h = 1.0},
    {name = "animalia:horse",        mesh = "animalia_horse.b3d",    tex = "infectious_z_horse_1.png",       w = 0.65, h = 1.95},
    {name = "animalia:cat",          mesh = "animalia_cat.b3d",      tex = "infectious_z_cat_1.png",         w = 0.2,  h = 0.4},
    {name = "animalia:turkey",       mesh = "animalia_turkey.b3d",   tex = "infectious_z_turkey_hen.png",    w = 0.3,  h = 0.6},
    {name = "animalia:reindeer",     mesh = "animalia_reindeer.b3d", tex = "infectious_z_reindeer.png",      w = 0.45, h = 0.9},
    {name = "animalia:opossum",      mesh = "animalia_opossum.b3d",  tex = "infectious_z_opossum.png",       w = 0.25, h = 0.4},
    {name = "animalia:rat",          mesh = "animalia_rat.b3d",      tex = "infectious_z_rat_1.png",         w = 0.15, h = 0.3},
    {name = "animalia:bat",          mesh = "animalia_bat.b3d",      tex = "infectious_z_bat_1.png",         w = 0.15, h = 0.3},
    {name = "animalia:frog",         mesh = "animalia_frog.b3d",     tex = "infectious_z_tree_frog.png",     w = 0.25, h = 0.4},
    {name = "animalia:owl",          mesh = "animalia_owl.b3d",      tex = "infectious_z_owl.png",           w = 0.15, h = 0.3},
    {name = "animalia:song_bird",    mesh = "animalia_bird.b3d",     tex = "infectious_z_cardinal.png",      w = 0.2,  h = 0.4},
}

-- Map animalia entity name -> zombified entity name
local zombified_map = {}

-- =============================================================================
-- Helper: check if entity is a zombie/infected
-- =============================================================================

local function is_zombie(obj)
    if not obj then return false end
    local ent = obj:get_luaentity()
    if ent then
        return ent._zombie_tag == ZOMBIE_TAG
    end
    return false
end

-- =============================================================================
-- Helper: find nearest target
-- =============================================================================

local function find_target(self)
    local pos = self.object:get_pos()
    if not pos then return nil end

    local best_target = nil
    local best_dist = ZOMBIE_RANGE

    for _, player in ipairs(core.get_connected_players()) do
        if not core.is_creative_enabled(player:get_player_name()) then
            local ppos = player:get_pos()
            if ppos then
                local dist = vector.distance(pos, ppos)
                if dist < best_dist then
                    best_dist = dist
                    best_target = player
                end
            end
        end
    end

    for _, obj in ipairs(core.get_objects_inside_radius(pos, ZOMBIE_RANGE)) do
        if obj ~= self.object and not obj:is_player() and not is_zombie(obj) then
            local ent = obj:get_luaentity()
            if ent and ent.name ~= "__builtin:item"
                    and ent.name ~= "__builtin:falling_node" then
                local opos = obj:get_pos()
                if opos then
                    local dist = vector.distance(pos, opos)
                    if dist < best_dist then
                        best_dist = dist
                        best_target = obj
                    end
                end
            end
        end
    end

    return best_target
end

-- =============================================================================
-- Helper: check if a position is blocked (walkable node)
-- =============================================================================

local function is_blocked(pos)
    local node = core.get_node(vector.round(pos))
    local def = core.registered_nodes[node.name]
    return def and def.walkable
end

-- =============================================================================
-- Movement: direct chase with spread offset and obstacle jumping
-- =============================================================================

local function move_toward(self, target_pos, speed)
    local pos = self.object:get_pos()
    if not pos or not target_pos then return end

    local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
    local new_y = vel.y

    -- Each mob gets a unique spread offset so they don't all line up
    if not self._spread_offset then
        self._spread_offset = {
            x = (math.random() - 0.5) * 4,
            z = (math.random() - 0.5) * 4,
        }
    end

    -- Apply spread when far, go direct when close
    local dist_to_target = vector.distance(pos, target_pos)
    local move_target
    if dist_to_target > ZOMBIE_ATTACK_DIST + 2 then
        move_target = {
            x = target_pos.x + self._spread_offset.x,
            y = target_pos.y,
            z = target_pos.z + self._spread_offset.z,
        }
    else
        move_target = target_pos
    end

    local dir = vector.direction(pos, move_target)
    dir.y = 0
    if vector.length(dir) < 0.01 then return end
    dir = vector.normalize(dir)

    -- Face movement direction
    self.object:set_yaw(math.atan2(-dir.x, dir.z))

    -- Jump if blocked ahead
    local front_feet = {x = pos.x + dir.x, y = pos.y, z = pos.z + dir.z}
    if is_blocked(front_feet) then
        local front_head = {x = pos.x + dir.x, y = pos.y + 1, z = pos.z + dir.z}
        if not is_blocked(front_head) then
            if vel.y >= -0.5 and vel.y <= 0.5 then
                new_y = ZOMBIE_JUMP_HEIGHT
            end
        end
    end

    self.object:set_velocity({
        x = dir.x * speed,
        y = new_y,
        z = dir.z * speed,
    })
end

-- =============================================================================
-- Infect: replace animalia mob with zombified version
-- =============================================================================

local function try_infect(target)
    if not target or target:is_player() then return false end
    if is_zombie(target) then return false end
    if math.random() > INFECT_CHANCE then return false end

    local ent = target:get_luaentity()
    if not ent then return false end

    -- Infected brutes can't be re-infected
    if ent.name == "infectious:infected_brute" then return false end

    local pos = target:get_pos()
    if not pos then return false end

    -- Check if this mob type has a zombified version
    local zombie_name = zombified_map[ent.name]
    if not zombie_name then
        -- Generic infection: just spawn a regular zombie
        zombie_name = "infectious:zombie"
    end

    local infected = core.add_entity(pos, zombie_name)
    if infected then
        infected:set_yaw(target:get_yaw() or 0)
        core.add_particlespawner({
            amount = 20,
            time = 0.5,
            minpos = vector.subtract(pos, 0.5),
            maxpos = vector.add(pos, {x = 0.5, y = 1.5, z = 0.5}),
            minvel = {x = -1, y = 0.5, z = -1},
            maxvel = {x = 1, y = 2, z = 1},
            minexptime = 0.5,
            maxexptime = 1.0,
            minsize = 1,
            maxsize = 3,
            texture = "default_dirt.png^[colorize:#200808A0",
            glow = 5,
        })
        core.log("action", "[infectious] " .. ent.name .. " was zombified!")
    end

    target:remove()
    return true
end

-- =============================================================================
-- Chunk-based mob cap: max zombies per 16x16x16 mapblock
-- =============================================================================

local all_zombies = {}

local function register_zombie(self)
    all_zombies[tostring(self.object)] = self
end

local function unregister_zombie(self)
    all_zombies[tostring(self.object)] = nil
end

-- =============================================================================
-- Common zombie AI step (shared by humanoid zombie and animal zombies)
-- =============================================================================

local function zombie_die(self)
    local pos = self.object:get_pos()
    if pos then
        -- Dark smoke burst
        core.add_particlespawner({
            amount = 30,
            time = 0.3,
            minpos = vector.subtract(pos, 0.5),
            maxpos = vector.add(pos, {x = 0.5, y = 1.8, z = 0.5}),
            minvel = {x = -2, y = 1, z = -2},
            maxvel = {x = 2, y = 4, z = 2},
            minacc = {x = 0, y = -3, z = 0},
            maxacc = {x = 0, y = -1, z = 0},
            minexptime = 0.8,
            maxexptime = 2.0,
            minsize = 0.5,
            maxsize = 1.5,
            texture = "default_dirt.png^[colorize:#200505FF",
            glow = 4,
        })
        -- Blood splatter
        core.add_particlespawner({
            amount = 20,
            time = 0.2,
            minpos = vector.subtract(pos, 0.3),
            maxpos = vector.add(pos, {x = 0.3, y = 1.2, z = 0.3}),
            minvel = {x = -3, y = 0, z = -3},
            maxvel = {x = 3, y = 2, z = 3},
            minacc = {x = 0, y = -9, z = 0},
            maxacc = {x = 0, y = -5, z = 0},
            minexptime = 0.3,
            maxexptime = 0.8,
            minsize = 0.3,
            maxsize = 0.8,
            texture = "default_dirt.png^[colorize:#8B0000FF",
            glow = 2,
        })
        -- Red flash
        core.add_particlespawner({
            amount = 3,
            time = 0.1,
            minpos = pos,
            maxpos = vector.add(pos, {x = 0, y = 1, z = 0}),
            minvel = {x = 0, y = 0, z = 0},
            maxvel = {x = 0, y = 0.5, z = 0},
            minexptime = 0.15,
            maxexptime = 0.3,
            minsize = 2,
            maxsize = 3,
            texture = "default_dirt.png^[colorize:#FF0000A0",
            glow = 14,
        })
        -- Death sound
        core.sound_play("default_break_glass", {
            pos = pos, gain = 0.6, max_hear_distance = 20,
        }, true)

    end
    unregister_zombie(self)
    self.object:remove()
end

-- =============================================================================

local function zombie_ai_step(self, dtime, base_damage, base_speed)
    local damage = base_damage * get_damage_mult()
    local speed = base_speed * get_speed_mult()
    local pos = self.object:get_pos()
    if not pos then return end

    -- Death check
    if (self._hp or 1) <= 0 then
        zombie_die(self)
        return
    end

    -- Entity cramming: if too many zombies in 2-block radius, take damage
    if not self._cram_timer then self._cram_timer = 0 end
    self._cram_timer = self._cram_timer + dtime
    if self._cram_timer >= 1.0 then
        self._cram_timer = 0
        local cramped = 0
        for _, obj in ipairs(core.get_objects_inside_radius(pos, 2)) do
            if obj ~= self.object and is_zombie(obj) then
                cramped = cramped + 1
            end
        end
        if cramped >= 8 then
            -- Suffocation damage from cramming
            self._hp = self._hp - 2
            if self._hp <= 0 then
                zombie_die(self)
                return
            end
        end
    end

    -- Despawn if too far from all players (120+ blocks)
    if not self._despawn_timer then self._despawn_timer = 0 end
    self._despawn_timer = self._despawn_timer + dtime
    if self._despawn_timer >= 5.0 then
        self._despawn_timer = 0
        local nearest_player_dist = 999
        for _, player in ipairs(core.get_connected_players()) do
            local ppos = player:get_pos()
            if ppos then
                local d = vector.distance(pos, ppos)
                if d < nearest_player_dist then
                    nearest_player_dist = d
                end
            end
        end
        if nearest_player_dist > 120 then
            self.object:remove()
            return
        end
    end

    -- Retarget: only search for new target if current one is gone
    self._retarget_timer = (self._retarget_timer or 0) + dtime
    if self._retarget_timer >= 1.0 then
        self._retarget_timer = 0
        local target = self._target
        if not target or not target:get_pos() then
            -- Target gone, find a new one
            self._target = find_target(self)
        else
            -- Check if target moved out of range
            local dist = vector.distance(pos, target:get_pos())
            if dist > ZOMBIE_RANGE * 1.5 then
                self._target = find_target(self)
            end
        end
    end

    -- Sounds
    self._sound_timer = (self._sound_timer or 0) + dtime
    if self._sound_timer >= 5 + math.random() * 5 then
        self._sound_timer = 0
        core.sound_play("default_gravel_footstep", {
            pos = pos, gain = 0.4, max_hear_distance = 16,
        }, true)
    end

    local target = self._target
    if not target then
        local cur_vel = self.object:get_velocity()
        self.object:set_velocity({x = 0, y = cur_vel and cur_vel.y or 0, z = 0})
        if self._set_anim then self:_set_anim("stand") end
        return
    end

    local tpos = target:get_pos()
    if not tpos then
        -- Don't clear immediately, wait a few frames in case it's a Creatura glitch
        self._target_lost_frames = (self._target_lost_frames or 0) + 1
        if self._target_lost_frames > 10 then
            self._target = nil
            self._target_lost_frames = 0
        end
        return
    end
    self._target_lost_frames = 0

    local dist = vector.distance(pos, tpos)
    if dist > ZOMBIE_RANGE * 1.5 then self._target = nil; return end

    self._attack_timer = (self._attack_timer or 0) + dtime

    if dist <= ZOMBIE_ATTACK_DIST then
        if self._set_anim then self:_set_anim("attack") end
        if self._attack_timer >= 0.8 then
            self._attack_timer = 0

            -- Punch with direction so target gets knocked back
            local attack_dir = vector.direction(pos, tpos)
            attack_dir.y = 0.3
            target:punch(self.object, 1.0, {
                full_punch_interval = 1.0,
                damage_groups = {fleshy = damage},
            }, attack_dir)

            if not target:is_player() then
                try_infect(target)
            end

            -- Cancel any knockback applied to US (not the target)
            core.after(0.05, function()
                if self.object and self.object:get_pos() then
                    local v = self.object:get_velocity()
                    if v then
                        self.object:set_velocity({x = 0, y = v.y, z = 0})
                    end
                end
            end)
        end
        local dir = vector.direction(pos, tpos)
        self.object:set_yaw(math.atan2(-dir.x, dir.z))
    else
        if self._set_anim then self:_set_anim("walk") end
        move_toward(self, tpos, speed)
    end
end

-- =============================================================================
-- Humanoid Zombie entity
-- =============================================================================

core.register_entity("infectious:zombie", {
    initial_properties = {
        physical = true,
        collide_with_objects = true,
        collisionbox = {-0.35, 0, -0.35, 0.35, 1.8, 0.35},
        selectionbox = {-0.35, 0, -0.35, 0.35, 1.8, 0.35},
        visual = "mesh",
        mesh = MODEL,
        visual_size = {x = 1, y = 1, z = 1},
        textures = {"infectious_zombie.png"},
        makes_footstep_sound = true,
        glow = 3,
        stepheight = 1.1,
    },

    _zombie_tag = ZOMBIE_TAG,
    _hp = ZOMBIE_HP,
    _target = nil,
    _attack_timer = 0,
    _retarget_timer = 0,
    _sound_timer = 0,
    _anim = "",

    on_activate = function(self, staticdata)
        self.object:set_acceleration({x = 0, y = -9.81, z = 0})
        self.object:set_armor_groups({fleshy = 0, immortal = 1})
        register_zombie(self)
        self._hp = ZOMBIE_HP
        if staticdata and staticdata ~= "" then
            local data = core.deserialize(staticdata)
            if data and data.hp then
                self._hp = data.hp
            end
        end
    end,

    on_step = function(self, dtime)
        zombie_ai_step(self, dtime, ZOMBIE_DAMAGE, ZOMBIE_SPEED)
    end,

    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
        if puncher and puncher:get_pos() then
            if puncher:is_player() then
                if not core.is_creative_enabled(puncher:get_player_name()) then
                    self._target = puncher
                end
            else
                self._target = puncher
            end
        end
        -- Calculate damage manually
        local dmg = 1
        if tool_capabilities and tool_capabilities.damage_groups then
            dmg = tool_capabilities.damage_groups.fleshy or 1
        end
        self._hp = self._hp - dmg
        self.object:set_texture_mod("^[colorize:#ff000040")
        if self._hp <= 0 then
            zombie_die(self)
        else
            core.after(0.15, function()
                if self.object and self.object:get_pos() then
                    self.object:set_texture_mod("")
                end
            end)
        end
    end,

    _set_anim = function(self, name)
        if self._anim == name then return end
        self._anim = name
        if name == "stand" then
            self.object:set_animation(ANIM_STAND, 15, 0, true)
        elseif name == "walk" then
            self.object:set_animation(ANIM_WALK, 30, 0, true)
        elseif name == "attack" then
            self.object:set_animation(ANIM_WALK_ATK, 30, 0, true)
        end
    end,

    get_staticdata = function(self)
        return core.serialize({hp = self._hp})
    end,
})

-- =============================================================================
-- Register zombified versions of all animalia mobs
-- =============================================================================

for _, mob in ipairs(ANIMALIA_MOBS) do
    local zombie_name = "infectious:zombified_" .. mob.name:gsub("animalia:", "")
    zombified_map[mob.name] = zombie_name

    core.register_entity(zombie_name, {
        initial_properties = {
            physical = true,
            collide_with_objects = true,
            collisionbox = {-mob.w, 0, -mob.w, mob.w, mob.h, mob.w},
            selectionbox = {-mob.w, 0, -mob.w, mob.w, mob.h, mob.w},
            visual = "mesh",
            mesh = mob.mesh,
            visual_size = {x = 10, y = 10, z = 10},
            textures = {mob.tex},
            makes_footstep_sound = true,
            glow = 5,
            stepheight = 1.1,
        },

        _zombie_tag = ZOMBIE_TAG,
        _hp = INFECTED_HP,
        _target = nil,
        _attack_timer = 0,
        _retarget_timer = 0,
        _sound_timer = 0,
        _anim = "",
        _original_mob = mob.name,

        on_activate = function(self, staticdata)
            self.object:set_acceleration({x = 0, y = -9.81, z = 0})
            self.object:set_armor_groups({fleshy = 0, immortal = 1})
            register_zombie(self)
            self._hp = INFECTED_HP
            if staticdata and staticdata ~= "" then
                local data = core.deserialize(staticdata)
                if data and data.hp then
                    self._hp = data.hp
                end
            end
        end,

        on_step = function(self, dtime)
            zombie_ai_step(self, dtime, INFECTED_DAMAGE, INFECTED_SPEED)
        end,

        on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
            if puncher and puncher:get_pos() then
                if puncher:is_player() then
                    if not core.is_creative_enabled(puncher:get_player_name()) then
                        self._target = puncher
                    end
                else
                    self._target = puncher
                end
            end
            local dmg = 1
            if tool_capabilities and tool_capabilities.damage_groups then
                dmg = tool_capabilities.damage_groups.fleshy or 1
            end
            self._hp = self._hp - dmg
            self.object:set_texture_mod("^[colorize:#ff000040")
            if self._hp <= 0 then
                zombie_die(self)
            else
                core.after(0.15, function()
                    if self.object and self.object:get_pos() then
                        self.object:set_texture_mod("")
                    end
                end)
            end
        end,

        _set_anim = function(self, name)
            -- Animalia models use different frame ranges
            -- Use stand=1-60, walk=70-89 (common across most animalia models)
            if self._anim == name then return end
            self._anim = name
            if name == "stand" then
                self.object:set_animation({x = 1, y = 60}, 20, 0, true)
            elseif name == "walk" or name == "attack" then
                self.object:set_animation({x = 70, y = 89}, 40, 0, true)
            end
        end,

        get_staticdata = function(self)
            return core.serialize({hp = self._hp})
        end,
    })
end

-- =============================================================================
-- Brute Mace (dropped weapon)
-- =============================================================================

core.register_tool("infectious:brute_mace", {
    description = S("Brute Mace"),
    inventory_image = "infectious_brute_mace.png",
    wield_image = "infectious_brute_mace.png",
    wield_scale = {x = 2.5, y = 2.5, z = 2},

    tool_capabilities = {
        full_punch_interval = 1.5,
        max_drop_level = 1,
        groupcaps = {
            cracky = {
                times = {[3] = 2.0},
                uses = 150,
                maxlevel = 0,
            },
        },
        damage_groups = {fleshy = 10},
    },

    groups = {weapon = 1},

    -- Area damage on hit: damages all entities within 3 blocks of target
    on_use = function(itemstack, user, pointed_thing)
        if pointed_thing.type == "object" then
            local target = pointed_thing.ref
            if target and target ~= user then
                local tpos = target:get_pos()
                if tpos then
                    local upos = user:get_pos()
                    -- Hit everything nearby (area damage, no knockback)
                    for _, obj in ipairs(core.get_objects_inside_radius(tpos, 3)) do
                        if obj ~= user then
                            local opos = obj:get_pos()
                            if opos then
                                obj:punch(user, 1.0, itemstack:get_tool_capabilities(), nil)
                            end
                        end
                    end
                    -- Slam particles
                    core.add_particlespawner({
                        amount = 10,
                        time = 0.2,
                        minpos = vector.subtract(tpos, {x = 2, y = 0, z = 2}),
                        maxpos = vector.add(tpos, {x = 2, y = 0.5, z = 2}),
                        minvel = {x = -2, y = 1, z = -2},
                        maxvel = {x = 2, y = 3, z = 2},
                        minacc = {x = 0, y = -9, z = 0},
                        maxacc = {x = 0, y = -5, z = 0},
                        minexptime = 0.3,
                        maxexptime = 0.6,
                        minsize = 0.5,
                        maxsize = 1.0,
                        texture = "default_dirt.png",
                        glow = 0,
                    })
                end
                itemstack:add_wear(65535 / 150)
                return itemstack
            end
        end
    end,
})

-- =============================================================================
-- Brute entity - NOT a zombie, can be attacked by infectious mobs
-- =============================================================================

local BRUTE_HP          = 80
local BRUTE_DAMAGE      = 12
local BRUTE_SPEED       = 2.0
local BRUTE_RANGE       = 40
local BRUTE_ATTACK_DIST = 3.0
local BRUTE_KNOCKBACK   = 12

core.register_entity("infectious:brute", {
    initial_properties = {
        physical = true,
        collide_with_objects = true,
        collisionbox = {-0.5, 0, -0.5, 0.5, 2.7, 0.5},
        selectionbox = {-0.5, 0, -0.5, 0.5, 2.7, 0.5},
        visual = "mesh",
        mesh = "character.b3d",
        visual_size = {x = 1.5, y = 1.5, z = 1.5},
        textures = {"infectious_brute.png"},
        makes_footstep_sound = true,
        glow = 2,
        stepheight = 1.1,
    },

    -- NOT zombie tagged: infectious mobs will attack it
    _hp = BRUTE_HP,
    _target = nil,
    _attack_timer = 0,
    _retarget_timer = 0,
    _sound_timer = 0,
    _anim = "",

    on_activate = function(self, staticdata)
        self.object:set_acceleration({x = 0, y = -9.81, z = 0})
        self.object:set_armor_groups({fleshy = 0, immortal = 1})
        register_zombie(self)
        self._hp = BRUTE_HP
        if staticdata and staticdata ~= "" then
            local data = core.deserialize(staticdata)
            if data and data.hp then
                self._hp = data.hp
            end
        end
    end,

    on_step = function(self, dtime)
        local pos = self.object:get_pos()
        if not pos then return end

        if (self._hp or 1) <= 0 then
            self:_die()
            return
        end

        -- Despawn if far from players
        if not self._despawn_timer then self._despawn_timer = 0 end
        self._despawn_timer = self._despawn_timer + dtime
        if self._despawn_timer >= 5.0 then
            self._despawn_timer = 0
            local nearest = 999
            for _, player in ipairs(core.get_connected_players()) do
                local ppos = player:get_pos()
                if ppos then
                    local d = vector.distance(pos, ppos)
                    if d < nearest then nearest = d end
                end
            end
            if nearest > 120 then
                unregister_zombie(self)
                self.object:remove()
                return
            end
        end

        -- Ground stomp particles (every step)
        if not self._step_timer then self._step_timer = 0 end
        self._step_timer = self._step_timer + dtime
        local vel = self.object:get_velocity()
        if vel and self._step_timer >= 0.4 then
            local hspeed = math.sqrt(vel.x * vel.x + vel.z * vel.z)
            if hspeed > 0.5 then
                self._step_timer = 0
                core.add_particlespawner({
                    amount = 4,
                    time = 0.2,
                    minpos = vector.subtract(pos, {x = 0.3, y = 0, z = 0.3}),
                    maxpos = vector.add(pos, {x = 0.3, y = 0.2, z = 0.3}),
                    minvel = {x = -0.5, y = 0.3, z = -0.5},
                    maxvel = {x = 0.5, y = 0.8, z = 0.5},
                    minexptime = 0.3,
                    maxexptime = 0.6,
                    minsize = 0.5,
                    maxsize = 1.0,
                    texture = "default_dirt.png",
                    glow = 0,
                })
            end
        end

        -- Sounds (heavy footsteps)
        self._sound_timer = (self._sound_timer or 0) + dtime
        if self._sound_timer >= 3 + math.random() * 3 then
            self._sound_timer = 0
            core.sound_play("default_dig_cracky", {
                pos = pos, gain = 0.5, max_hear_distance = 24,
            }, true)
        end

        -- Retarget: prefer players, but fight back against attackers
        self._retarget_timer = (self._retarget_timer or 0) + dtime
        if self._retarget_timer >= 1.5 then
            self._retarget_timer = 0
            -- If we have an attacker, keep targeting them
            if not self._target or not self._target:get_pos() then
                self._target = nil
                -- Find nearest player (non-creative)
                local best = nil
                local best_dist = BRUTE_RANGE
                for _, player in ipairs(core.get_connected_players()) do
                    if not core.is_creative_enabled(player:get_player_name()) then
                        local ppos = player:get_pos()
                        if ppos then
                            local d = vector.distance(pos, ppos)
                            if d < best_dist then
                                best_dist = d
                                best = player
                            end
                        end
                    end
                end
                self._target = best
            end
        end

        local target = self._target
        if not target then
            -- Random roaming
            if not self._roam_timer then self._roam_timer = 0 end
            if not self._roam_dir then self._roam_dir = nil end
            self._roam_timer = self._roam_timer + dtime

            if self._roam_timer >= 3 + math.random() * 4 then
                self._roam_timer = 0
                -- Pick a new random direction or stop
                if math.random(1, 3) == 1 then
                    -- Pause briefly
                    self._roam_dir = nil
                else
                    local angle = math.random() * math.pi * 2
                    self._roam_dir = {
                        x = math.cos(angle),
                        y = 0,
                        z = math.sin(angle),
                    }
                end
            end

            if self._roam_dir then
                self:_set_anim("walk")
                local vy = vel and vel.y or 0
                self.object:set_velocity({
                    x = self._roam_dir.x * BRUTE_SPEED * 0.5,
                    y = vy,
                    z = self._roam_dir.z * BRUTE_SPEED * 0.5,
                })
                self.object:set_yaw(math.atan2(-self._roam_dir.x, self._roam_dir.z))
            else
                self.object:set_velocity({x = 0, y = vel and vel.y or 0, z = 0})
                self:_set_anim("stand")
            end
            return
        end

        local tpos = target:get_pos()
        if not tpos then self._target = nil; return end

        local thp = target:get_hp()
        if thp and thp <= 0 then self._target = nil; return end

        local dist = vector.distance(pos, tpos)
        if dist > BRUTE_RANGE * 1.5 then self._target = nil; return end

        self._attack_timer = (self._attack_timer or 0) + dtime

        if dist <= BRUTE_ATTACK_DIST then
            -- Keep walking animation (arms swinging) while in melee
            self:_set_anim("walk")

            -- Face target
            local dir = vector.direction(pos, tpos)
            self.object:set_yaw(math.atan2(-dir.x, dir.z))

            if self._attack_timer >= 1.5 then
                self._attack_timer = 0

                -- AREA DAMAGE: hit everything within 4 blocks
                local aoe_radius = 4
                for _, obj in ipairs(core.get_objects_inside_radius(pos, aoe_radius)) do
                    if obj ~= self.object then
                        local opos = obj:get_pos()
                        if opos then
                            local kb = vector.direction(pos, opos)
                            kb.y = 0.3
                            obj:punch(self.object, 1.0, {
                                full_punch_interval = 1.5,
                                damage_groups = {fleshy = BRUTE_DAMAGE},
                            }, kb)
                        end
                    end
                end

                -- Ground slam particles
                core.add_particlespawner({
                    amount = 20,
                    time = 0.2,
                    minpos = vector.subtract(pos, {x = aoe_radius, y = 0, z = aoe_radius}),
                    maxpos = vector.add(pos, {x = aoe_radius, y = 0.5, z = aoe_radius}),
                    minvel = {x = -2, y = 1, z = -2},
                    maxvel = {x = 2, y = 3, z = 2},
                    minacc = {x = 0, y = -9, z = 0},
                    maxacc = {x = 0, y = -5, z = 0},
                    minexptime = 0.3,
                    maxexptime = 0.8,
                    minsize = 0.5,
                    maxsize = 1.5,
                    texture = "default_dirt.png",
                    glow = 0,
                })

                core.sound_play("default_dig_cracky", {
                    pos = pos, gain = 1.0, max_hear_distance = 30,
                }, true)
            end
        else
            self:_set_anim("walk")
            move_toward(self, tpos, BRUTE_SPEED)
        end
    end,

    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
        -- Fight back against anyone who hits us
        if puncher and puncher:get_pos() then
            if puncher:is_player() then
                if not core.is_creative_enabled(puncher:get_player_name()) then
                    self._target = puncher
                end
            else
                self._target = puncher
            end
        end

        local dmg = 1
        if tool_capabilities and tool_capabilities.damage_groups then
            dmg = tool_capabilities.damage_groups.fleshy or 1
        end
        -- High armor: reduce damage by 40%
        dmg = math.max(1, math.floor(dmg * 0.6))
        self._hp = self._hp - dmg

        self.object:set_texture_mod("^[colorize:#ff000040")

        -- Cancel any knockback - brute doesn't flinch
        core.after(0.05, function()
            if self.object and self.object:get_pos() then
                local v = self.object:get_velocity()
                if v then
                    self.object:set_velocity({x = 0, y = v.y, z = 0})
                end
            end
        end)

        if self._hp <= 0 then
            self:_die()
        else
            core.after(0.15, function()
                if self.object and self.object:get_pos() then
                    self.object:set_texture_mod("")
                end
            end)
        end
    end,

    _die = function(self)
        local pos = self.object:get_pos()
        if pos then
            -- Big death explosion particles
            core.add_particlespawner({
                amount = 25,
                time = 0.3,
                minpos = vector.subtract(pos, 0.5),
                maxpos = vector.add(pos, {x = 0.5, y = 2.5, z = 0.5}),
                minvel = {x = -2, y = 1, z = -2},
                maxvel = {x = 2, y = 4, z = 2},
                minacc = {x = 0, y = -3, z = 0},
                maxacc = {x = 0, y = -1, z = 0},
                minexptime = 0.8,
                maxexptime = 2.0,
                minsize = 0.5,
                maxsize = 1.5,
                texture = "default_dirt.png^[colorize:#30251FFF",
                glow = 2,
            })

            core.sound_play("default_break_glass", {
                pos = pos, gain = 0.8, max_hear_distance = 30,
            }, true)

            -- Drops: rare mace, chance for armor
            -- Always drop some iron
            core.add_item(pos, "default:steel_ingot " .. math.random(1, 3))

            -- 1 in 10: drop the brute mace
            if math.random(1, 10) == 1 then
                core.add_item(pos, "infectious:brute_mace")
            end

            -- 1 in 10: drop diamond
            if math.random(1, 10) == 1 then
                core.add_item(pos, "default:diamond " .. math.random(1, 2))
            end
        end
        unregister_zombie(self)
        self.object:remove()
    end,

    _set_anim = function(self, name)
        if self._anim == name then return end
        self._anim = name
        if name == "stand" then
            self.object:set_animation({x = 0, y = 79}, 10, 0, true)
        elseif name == "walk" then
            self.object:set_animation({x = 200, y = 219}, 15, 0, true)
        end
    end,

    get_staticdata = function(self)
        return core.serialize({hp = self._hp})
    end,
})

-- =============================================================================
-- Brute spawn egg
-- =============================================================================

local function spawn_brute_at(itemstack, user, pointed_thing)
    if pointed_thing.type == "node" then
        local pos = pointed_thing.above
        pos.y = pos.y + 0.5
        local obj = core.add_entity(pos, "infectious:brute")
        if obj then
            obj:set_yaw(math.random() * math.pi * 2)
        end
        if not core.is_creative_enabled(user:get_player_name()) then
            itemstack:take_item()
        end
        return itemstack
    end
end

core.register_craftitem("infectious:brute_spawn_egg", {
    description = S("Brute Spawn Egg"),
    inventory_image = "infectious_brute_egg.png",
    on_use = spawn_brute_at,
    on_place = spawn_brute_at,
    on_secondary_use = spawn_brute_at,
})

-- =============================================================================
-- Infected Brute - zombified brute with zombie tag, fast, bloodmoon buffs
-- =============================================================================

local INFECTED_BRUTE_HP     = 120
local INFECTED_BRUTE_DAMAGE = 16
local INFECTED_BRUTE_SPEED  = ZOMBIE_SPEED  -- same as normal zombie
local INFECTED_BRUTE_ARMOR  = 0.4           -- 60% damage reduction

-- Register brute -> infected brute mapping
zombified_map["infectious:brute"] = "infectious:infected_brute"

core.register_entity("infectious:infected_brute", {
    initial_properties = {
        physical = true,
        collide_with_objects = true,
        collisionbox = {-0.5, 0, -0.5, 0.5, 2.7, 0.5},
        selectionbox = {-0.5, 0, -0.5, 0.5, 2.7, 0.5},
        visual = "mesh",
        mesh = "character.b3d",
        visual_size = {x = 1.5, y = 1.5, z = 1.5},
        textures = {"infectious_infected_brute.png"},
        makes_footstep_sound = true,
        glow = 5,
        stepheight = 1.1,
    },

    -- Zombie tagged: won't be attacked by other zombies, won't be re-infected
    _zombie_tag = ZOMBIE_TAG,
    _hp = INFECTED_BRUTE_HP,
    _target = nil,
    _attack_timer = 0,
    _retarget_timer = 0,
    _sound_timer = 0,
    _anim = "",
    _roam_timer = 0,
    _roam_dir = nil,

    on_activate = function(self, staticdata)
        self.object:set_acceleration({x = 0, y = -9.81, z = 0})
        self.object:set_armor_groups({fleshy = 0, immortal = 1})
        register_zombie(self)
        self._hp = INFECTED_BRUTE_HP
        if staticdata and staticdata ~= "" then
            local data = core.deserialize(staticdata)
            if data and data.hp then
                self._hp = data.hp
            end
        end
    end,

    on_step = function(self, dtime)
        -- Uses zombie_ai_step but with brute stats + bloodmoon buffs
        local base_damage = INFECTED_BRUTE_DAMAGE
        local base_speed = INFECTED_BRUTE_SPEED
        local damage = base_damage * get_damage_mult()
        local speed = base_speed * get_speed_mult()

        local pos = self.object:get_pos()
        if not pos then return end

        if (self._hp or 1) <= 0 then
            zombie_die(self)
            return
        end

        -- Entity cramming
        if not self._cram_timer then self._cram_timer = 0 end
        self._cram_timer = self._cram_timer + dtime
        if self._cram_timer >= 1.0 then
            self._cram_timer = 0
            local cramped = 0
            for _, obj in ipairs(core.get_objects_inside_radius(pos, 2)) do
                if obj ~= self.object and is_zombie(obj) then
                    cramped = cramped + 1
                end
            end
            if cramped >= 8 then
                self._hp = self._hp - 2
                if self._hp <= 0 then zombie_die(self); return end
            end
        end

        -- Despawn far from players
        if not self._despawn_timer then self._despawn_timer = 0 end
        self._despawn_timer = self._despawn_timer + dtime
        if self._despawn_timer >= 5.0 then
            self._despawn_timer = 0
            local nearest = 999
            for _, player in ipairs(core.get_connected_players()) do
                local ppos = player:get_pos()
                if ppos then
                    local d = vector.distance(pos, ppos)
                    if d < nearest then nearest = d end
                end
            end
            if nearest > 120 then
                unregister_zombie(self)
                self.object:remove()
                return
            end
        end

        -- Ground stomp particles
        if not self._step_timer then self._step_timer = 0 end
        self._step_timer = self._step_timer + dtime
        local vel = self.object:get_velocity()
        if vel and self._step_timer >= 0.3 then
            local hspeed = math.sqrt(vel.x * vel.x + vel.z * vel.z)
            if hspeed > 0.5 then
                self._step_timer = 0
                core.add_particlespawner({
                    amount = 4, time = 0.2,
                    minpos = vector.subtract(pos, {x = 0.3, y = 0, z = 0.3}),
                    maxpos = vector.add(pos, {x = 0.3, y = 0.2, z = 0.3}),
                    minvel = {x = -0.5, y = 0.3, z = -0.5},
                    maxvel = {x = 0.5, y = 0.8, z = 0.5},
                    minexptime = 0.3, maxexptime = 0.6,
                    minsize = 0.5, maxsize = 1.0,
                    texture = "default_dirt.png^[colorize:#200808A0",
                    glow = 3,
                })
            end
        end

        -- Sounds
        self._sound_timer = (self._sound_timer or 0) + dtime
        if self._sound_timer >= 3 + math.random() * 3 then
            self._sound_timer = 0
            core.sound_play("default_dig_cracky", {
                pos = pos, gain = 0.6, max_hear_distance = 24,
            }, true)
        end

        -- Retarget: only find new target if current one is gone
        self._retarget_timer = (self._retarget_timer or 0) + dtime
        if self._retarget_timer >= 1.0 then
            self._retarget_timer = 0
            local cur = self._target
            if not cur or not cur:get_pos() then
                self._target = find_target(self)
            else
                local d = vector.distance(pos, cur:get_pos())
                if d > ZOMBIE_RANGE * 1.5 then
                    self._target = find_target(self)
                end
            end
        end

        local target = self._target
        if not target then
            self.object:set_velocity({x = 0, y = vel and vel.y or 0, z = 0})
            self:_set_anim("stand")
            return
        end

        local tpos = target:get_pos()
        if not tpos then
            self._target_lost_frames = (self._target_lost_frames or 0) + 1
            if self._target_lost_frames > 10 then
                self._target = nil
                self._target_lost_frames = 0
            end
            return
        end
        self._target_lost_frames = 0

        local dist = vector.distance(pos, tpos)

        self._attack_timer = (self._attack_timer or 0) + dtime

        if dist <= BRUTE_ATTACK_DIST then
            self:_set_anim("walk")
            local dir = vector.direction(pos, tpos)
            self.object:set_yaw(math.atan2(-dir.x, dir.z))

            if self._attack_timer >= 1.2 then
                self._attack_timer = 0

                -- Area damage
                local aoe_radius = 4
                for _, obj in ipairs(core.get_objects_inside_radius(pos, aoe_radius)) do
                    if obj ~= self.object and not is_zombie(obj) then
                        local opos = obj:get_pos()
                        if opos then
                            local kb = vector.direction(pos, opos)
                            kb.y = 0.3
                            obj:punch(self.object, 1.0, {
                                full_punch_interval = 1.2,
                                damage_groups = {fleshy = damage},
                            }, kb)
                        end
                    end
                end

                -- Infection on hit
                for _, obj in ipairs(core.get_objects_inside_radius(pos, aoe_radius)) do
                    if obj ~= self.object and not obj:is_player() and not is_zombie(obj) then
                        try_infect(obj)
                    end
                end

                -- Slam particles
                core.add_particlespawner({
                    amount = 20, time = 0.2,
                    minpos = vector.subtract(pos, {x = aoe_radius, y = 0, z = aoe_radius}),
                    maxpos = vector.add(pos, {x = aoe_radius, y = 0.5, z = aoe_radius}),
                    minvel = {x = -2, y = 1, z = -2},
                    maxvel = {x = 2, y = 3, z = 2},
                    minacc = {x = 0, y = -9, z = 0},
                    maxacc = {x = 0, y = -5, z = 0},
                    minexptime = 0.3, maxexptime = 0.8,
                    minsize = 0.5, maxsize = 1.5,
                    texture = "default_dirt.png^[colorize:#200808A0",
                    glow = 3,
                })

                core.sound_play("default_dig_cracky", {
                    pos = pos, gain = 1.0, max_hear_distance = 30,
                }, true)

                -- Cancel any knockback applied to us
                core.after(0.05, function()
                    if self.object and self.object:get_pos() then
                        local v = self.object:get_velocity()
                        if v then
                            self.object:set_velocity({x = 0, y = v.y, z = 0})
                        end
                    end
                end)
            end
        else
            self:_set_anim("walk")
            move_toward(self, tpos, speed)
        end
    end,

    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
        if puncher and puncher:get_pos() then
            if puncher:is_player() then
                if not core.is_creative_enabled(puncher:get_player_name()) then
                    self._target = puncher
                end
            else
                self._target = puncher
            end
        end

        local dmg = 1
        if tool_capabilities and tool_capabilities.damage_groups then
            dmg = tool_capabilities.damage_groups.fleshy or 1
        end
        -- 60% damage reduction, 95% during bloodmoon
        local armor_mult = INFECTED_BRUTE_ARMOR
        if bloodmoon and bloodmoon.is_active and bloodmoon.is_active() then
            armor_mult = 0.05
        end
        dmg = math.max(1, math.floor(dmg * armor_mult))
        self._hp = self._hp - dmg

        self.object:set_texture_mod("^[colorize:#ff000040")

        -- Cancel knockback
        core.after(0.05, function()
            if self.object and self.object:get_pos() then
                local v = self.object:get_velocity()
                if v then
                    self.object:set_velocity({x = 0, y = v.y, z = 0})
                end
            end
        end)

        if self._hp <= 0 then
            zombie_die(self)
        else
            core.after(0.15, function()
                if self.object and self.object:get_pos() then
                    self.object:set_texture_mod("")
                end
            end)
        end
    end,

    _set_anim = function(self, name)
        if self._anim == name then return end
        self._anim = name
        if name == "stand" then
            self.object:set_animation({x = 0, y = 79}, 10, 0, true)
        elseif name == "walk" then
            self.object:set_animation({x = 200, y = 219}, 18, 0, true)
        end
    end,

    get_staticdata = function(self)
        return core.serialize({hp = self._hp})
    end,
})

-- Infected brute spawn egg
local function spawn_infected_brute_at(itemstack, user, pointed_thing)
    if pointed_thing.type == "node" then
        local pos = pointed_thing.above
        pos.y = pos.y + 0.5
        local obj = core.add_entity(pos, "infectious:infected_brute")
        if obj then
            obj:set_yaw(math.random() * math.pi * 2)
        end
        if not core.is_creative_enabled(user:get_player_name()) then
            itemstack:take_item()
        end
        return itemstack
    end
end

core.register_craftitem("infectious:infected_brute_spawn_egg", {
    description = S("Infected Brute Spawn Egg"),
    inventory_image = "infectious_infected_brute_egg.png",
    on_use = spawn_infected_brute_at,
    on_place = spawn_infected_brute_at,
    on_secondary_use = spawn_infected_brute_at,
})

-- =============================================================================
-- Spawn egg
-- =============================================================================

local function spawn_zombie_at(itemstack, user, pointed_thing)
    if pointed_thing.type == "node" then
        local pos = pointed_thing.above
        pos.y = pos.y + 0.5
        local obj = core.add_entity(pos, "infectious:zombie")
        if obj then
            obj:set_yaw(math.random() * math.pi * 2)
        end
        if not core.is_creative_enabled(user:get_player_name()) then
            itemstack:take_item()
        end
        return itemstack
    end
end

core.register_craftitem("infectious:spawn_egg", {
    description = S("Zombie Spawn Egg"),
    inventory_image = "infectious_spawn_egg.png",
    on_use = spawn_zombie_at,
    on_place = spawn_zombie_at,
    on_secondary_use = spawn_zombie_at,
})

-- =============================================================================
-- Natural spawning (Minecraft-style: player-centric, pack spawning)
-- =============================================================================

local SPAWN_INTERVAL     = 5        -- try spawning every 5 seconds
local SPAWN_MIN_DIST     = 20       -- minimum distance from player
local SPAWN_MAX_DIST     = 60       -- maximum distance from player
local SPAWN_ATTEMPTS     = 8        -- random positions to try per player
local SPAWN_PACK_MIN     = 1        -- minimum pack size
local SPAWN_PACK_MAX     = 3        -- maximum pack size
local spawn_timer = 0

core.register_globalstep(function(dtime)
    spawn_timer = spawn_timer + dtime
    -- Blood moon: spawn twice as fast
    local interval = SPAWN_INTERVAL
    if bloodmoon and bloodmoon.is_active and bloodmoon.is_active() then
        interval = interval / 2
    end
    if spawn_timer < interval then return end
    spawn_timer = 0

    for _, player in ipairs(core.get_connected_players()) do
        local ppos = player:get_pos()
        if not ppos then goto continue end

        -- Try random positions around the player
        for _ = 1, SPAWN_ATTEMPTS do
            -- Pick random angle and distance
            local angle = math.random() * math.pi * 2
            local dist = SPAWN_MIN_DIST + math.random() * (SPAWN_MAX_DIST - SPAWN_MIN_DIST)
            local try_pos = {
                x = math.floor(ppos.x + math.cos(angle) * dist),
                y = math.floor(ppos.y),
                z = math.floor(ppos.z + math.sin(angle) * dist),
            }

            -- Search vertically for a valid surface (up and down from player Y)
            local spawn_pos = nil
            for dy = -10, 10 do
                local ground = {x = try_pos.x, y = try_pos.y + dy, z = try_pos.z}
                local ground_node = core.get_node(ground)
                local ground_def = core.registered_nodes[ground_node.name]

                if ground_def and ground_def.walkable then
                    local above1 = {x = ground.x, y = ground.y + 1, z = ground.z}
                    local above2 = {x = ground.x, y = ground.y + 2, z = ground.z}

                    if core.get_node(above1).name == "air"
                            and core.get_node(above2).name == "air" then
                        -- Check light
                        local light = core.get_node_light(above1)
                        if light and light <= SPAWN_MAX_LIGHT then
                            spawn_pos = above1
                            break
                        end
                    end
                end
            end

            if spawn_pos then
                -- Spawn a pack
                local pack_max = SPAWN_PACK_MAX
                if bloodmoon and bloodmoon.is_active and bloodmoon.is_active() then
                    pack_max = pack_max * 2
                end
                local pack_size = math.random(SPAWN_PACK_MIN, pack_max)
                for i = 1, pack_size do
                    local offset = {
                        x = spawn_pos.x + math.random(-2, 2),
                        y = spawn_pos.y,
                        z = spawn_pos.z + math.random(-2, 2),
                    }
                    -- 1 in 15 chance to spawn a brute instead
                    local mob_name = "infectious:zombie"
                    if math.random(1, 15) == 1 then
                        mob_name = "infectious:brute"
                    end
                    local obj = core.add_entity(offset, mob_name)
                    if obj then
                        obj:set_yaw(math.random() * math.pi * 2)
                    end
                end
                break  -- one successful pack per player per cycle
            end
        end

        ::continue::
    end
end)

-- =============================================================================
-- Trident Bosses: 5 elemental bosses that drop tridents
-- =============================================================================

local BOSS_DEFINITIONS = {
    {
        name = "infectious:boss_fire",
        desc = "Inferno Titan",
        texture = "infectious_boss_fire.png",
        egg_texture = "infectious_boss_fire_egg.png",
        hp = 600,
        damage = 21,
        armor = 0.75,
        drop = "tridents:fire_trident",
        scale = 4.0,
        glow = 8,
    },
    {
        name = "infectious:boss_lightning",
        desc = "Storm Colossus",
        texture = "infectious_boss_lightning.png",
        egg_texture = "infectious_boss_lightning_egg.png",
        hp = 540,
        damage = 24,
        armor = 0.725,
        drop = "tridents:lightning_trident",
        scale = 4.0,
        glow = 10,
    },
    {
        name = "infectious:boss_wither",
        desc = "Void Reaper",
        texture = "infectious_boss_wither.png",
        egg_texture = "infectious_boss_wither_egg.png",
        hp = 200,
        damage = 27,
        armor = 1.0,        -- no damage reduction
        drop = "tridents:wither_trident",
        scale = 1.0,
        glow = 8,
        speed_override = ZOMBIE_SPEED * 2,    -- as fast as bloodmoon zombies
        attack_speed_override = 0.4,           -- very fast attacks
        single_target = true,                  -- no area damage
    },
    {
        name = "infectious:boss_support",
        desc = "Life Warden",
        texture = "infectious_boss_support.png",
        egg_texture = "infectious_boss_support_egg.png",
        hp = 750,
        damage = 15,
        armor = 0.675,
        drop = "tridents:support_trident",
        scale = 4.0,
        glow = 7,
    },
}

for _, boss in ipairs(BOSS_DEFINITIONS) do
    local b = boss  -- capture for closures

    -- Make boss immune to infection
    zombified_map[b.name] = nil

    core.register_entity(b.name, {
        initial_properties = {
            physical = true,
            collide_with_objects = true,
            collisionbox = {-0.5 * b.scale, 0, -0.5 * b.scale,
                             0.5 * b.scale, 1.8 * b.scale, 0.5 * b.scale},
            selectionbox = {-0.5 * b.scale, 0, -0.5 * b.scale,
                             0.5 * b.scale, 1.8 * b.scale, 0.5 * b.scale},
            visual = "mesh",
            mesh = "character.b3d",
            visual_size = {x = b.scale, y = b.scale, z = b.scale},
            textures = {b.texture},
            makes_footstep_sound = true,
            glow = b.glow,
            stepheight = 1.1,
        },

        _hp = b.hp,
        _target = nil,
        _attack_timer = 0,
        _retarget_timer = 0,
        _sound_timer = 0,
        _anim = "",
        _roam_timer = 0,
        _roam_dir = nil,

        on_activate = function(self, staticdata)
            self.object:set_acceleration({x = 0, y = -9.81, z = 0})
            self.object:set_armor_groups({fleshy = 0, immortal = 1})
            register_zombie(self)
            self._hp = b.hp
            if staticdata and staticdata ~= "" then
                local data = core.deserialize(staticdata)
                if data and data.hp then
                    self._hp = data.hp
                end
            end
        end,

        on_step = function(self, dtime)
            local pos = self.object:get_pos()
            if not pos then return end

            if (self._hp or 1) <= 0 then
                -- Boss death: drop trident + big particle explosion
                if pos then
                    core.add_particlespawner({
                        amount = 40, time = 0.5,
                        minpos = vector.subtract(pos, 1),
                        maxpos = vector.add(pos, {x = 1, y = 3, z = 1}),
                        minvel = {x = -3, y = 1, z = -3},
                        maxvel = {x = 3, y = 5, z = 3},
                        minacc = {x = 0, y = -3, z = 0},
                        maxacc = {x = 0, y = -1, z = 0},
                        minexptime = 1, maxexptime = 3,
                        minsize = 1, maxsize = 3,
                        texture = "default_dirt.png^[colorize:#FFAA00FF",
                        glow = 14,
                    })
                    core.add_particlespawner({
                        amount = 20, time = 0.3,
                        minpos = vector.subtract(pos, 0.5),
                        maxpos = vector.add(pos, {x = 0.5, y = 2, z = 0.5}),
                        minvel = {x = -1, y = 2, z = -1},
                        maxvel = {x = 1, y = 4, z = 1},
                        minexptime = 0.5, maxexptime = 1.5,
                        minsize = 2, maxsize = 5,
                        texture = "default_dirt.png^[colorize:#FFFFFF80",
                        glow = 14,
                    })
                    core.sound_play("default_break_glass", {
                        pos = pos, gain = 1.5, max_hear_distance = 50,
                    }, true)
                    -- Drop the trident
                    core.add_item(pos, b.drop)
                    -- Also drop diamonds
                    core.add_item(pos, "default:diamond " .. math.random(2, 5))
                    -- Announce
                    for _, player in ipairs(core.get_connected_players()) do
                        core.chat_send_player(player:get_player_name(),
                            core.colorize("#ffd700", b.desc .. " has been slain!"))
                    end
                end
                unregister_zombie(self)

                self.object:remove()
                return
            end

            -- Despawn far from players
            if not self._despawn_timer then self._despawn_timer = 0 end
            self._despawn_timer = self._despawn_timer + dtime
            if self._despawn_timer >= 5.0 then
                self._despawn_timer = 0
                local nearest = 999
                for _, player in ipairs(core.get_connected_players()) do
                    local ppos = player:get_pos()
                    if ppos then
                        local d = vector.distance(pos, ppos)
                        if d < nearest then nearest = d end
                    end
                end
                if nearest > 120 then
                    unregister_zombie(self)
    
                    self.object:remove()
                    return
                end
            end

            -- Stomp particles
            if not self._step_timer then self._step_timer = 0 end
            self._step_timer = self._step_timer + dtime
            local vel = self.object:get_velocity()
            if vel and self._step_timer >= 0.3 then
                local hspeed = math.sqrt(vel.x * vel.x + vel.z * vel.z)
                if hspeed > 0.5 then
                    self._step_timer = 0
                    core.add_particlespawner({
                        amount = 5, time = 0.2,
                        minpos = vector.subtract(pos, {x = 0.5, y = 0, z = 0.5}),
                        maxpos = vector.add(pos, {x = 0.5, y = 0.3, z = 0.5}),
                        minvel = {x = -0.5, y = 0.3, z = -0.5},
                        maxvel = {x = 0.5, y = 1, z = 0.5},
                        minexptime = 0.3, maxexptime = 0.6,
                        minsize = 0.5, maxsize = 1.0,
                        texture = "default_dirt.png", glow = 0,
                    })
                end
            end

            -- Sounds
            self._sound_timer = (self._sound_timer or 0) + dtime
            if self._sound_timer >= 4 + math.random() * 3 then
                self._sound_timer = 0
                core.sound_play("default_dig_cracky", {
                    pos = pos, gain = 0.7, max_hear_distance = 30,
                }, true)
            end

            -- Target: players only (non-creative)
            self._retarget_timer = (self._retarget_timer or 0) + dtime
            if self._retarget_timer >= 1.5 then
                self._retarget_timer = 0
                if not self._target or not self._target:get_pos() then
                    self._target = nil
                    local best = nil
                    local best_dist = ZOMBIE_RANGE
                    for _, player in ipairs(core.get_connected_players()) do
                        if not core.is_creative_enabled(player:get_player_name()) then
                            local ppos = player:get_pos()
                            if ppos then
                                local d = vector.distance(pos, ppos)
                                if d < best_dist then
                                    best_dist = d
                                    best = player
                                end
                            end
                        end
                    end
                    self._target = best
                end
            end

            local target = self._target
            if not target then
                -- Roaming
                self._roam_timer = (self._roam_timer or 0) + dtime
                if self._roam_timer >= 3 + math.random() * 4 then
                    self._roam_timer = 0
                    if math.random(1, 3) == 1 then
                        self._roam_dir = nil
                    else
                        local angle = math.random() * math.pi * 2
                        self._roam_dir = {x = math.cos(angle), y = 0, z = math.sin(angle)}
                    end
                end
                local vy = vel and vel.y or 0
                if self._roam_dir then
                    self:_set_anim("walk")
                    self.object:set_velocity({
                        x = self._roam_dir.x * 1.5,
                        y = vy,
                        z = self._roam_dir.z * 1.5,
                    })
                    self.object:set_yaw(math.atan2(-self._roam_dir.x, self._roam_dir.z))
                else
                    self.object:set_velocity({x = 0, y = vy, z = 0})
                    self:_set_anim("stand")
                end
                return
            end

            local tpos = target:get_pos()
            if not tpos then self._target = nil; return end
            local dist = vector.distance(pos, tpos)
            if dist > ZOMBIE_RANGE * 1.5 then self._target = nil; return end

            self._attack_timer = (self._attack_timer or 0) + dtime

            local boss_attack_speed = b.attack_speed_override or 1.2
            local boss_move_speed = b.speed_override or 3.0
            local boss_aoe = (b.scale >= 2) and 5 or 3

            if dist <= 3.5 then
                self:_set_anim("walk")
                local dir = vector.direction(pos, tpos)
                self.object:set_yaw(math.atan2(-dir.x, dir.z))

                if self._attack_timer >= boss_attack_speed then
                    self._attack_timer = 0

                    if b.single_target then
                        -- Single target attack (Void Reaper)
                        local kb = vector.direction(pos, tpos)
                        kb.y = 0.3
                        target:punch(self.object, 1.0, {
                            full_punch_interval = boss_attack_speed,
                            damage_groups = {fleshy = b.damage},
                        }, kb)
                        if b.name == "infectious:boss_wither" then
                            apply_void_wither(target)
                        end
                    else
                        -- Area damage with knockback
                        for _, obj in ipairs(core.get_objects_inside_radius(pos, boss_aoe)) do
                            if obj ~= self.object then
                                local opos = obj:get_pos()
                                if opos then
                                    local kb = vector.direction(pos, opos)
                                    kb.y = 0.3
                                    obj:punch(self.object, 1.0, {
                                        full_punch_interval = boss_attack_speed,
                                        damage_groups = {fleshy = b.damage},
                                    }, kb)
                                end
                            end
                        end
                    end
                    -- Slam particles
                    core.add_particlespawner({
                        amount = 15, time = 0.2,
                        minpos = vector.subtract(pos, {x = boss_aoe, y = 0, z = boss_aoe}),
                        maxpos = vector.add(pos, {x = boss_aoe, y = 0.5, z = boss_aoe}),
                        minvel = {x = -2, y = 1, z = -2},
                        maxvel = {x = 2, y = 3, z = 2},
                        minacc = {x = 0, y = -9, z = 0},
                        maxacc = {x = 0, y = -5, z = 0},
                        minexptime = 0.3, maxexptime = 0.8,
                        minsize = 0.5, maxsize = 1.5,
                        texture = "default_dirt.png", glow = 0,
                    })
                    core.sound_play("default_dig_cracky", {
                        pos = pos, gain = 1.0, max_hear_distance = 30,
                    }, true)
                end
            else
                self:_set_anim("walk")
                move_toward(self, tpos, boss_move_speed)
            end
        end,

        on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
            if puncher and puncher:get_pos() then
                if puncher:is_player() then
                    if not core.is_creative_enabled(puncher:get_player_name()) then
                        self._target = puncher
                    end
                else
                    self._target = puncher
                end
            end
            local dmg = 1
            if tool_capabilities and tool_capabilities.damage_groups then
                dmg = tool_capabilities.damage_groups.fleshy or 1
            end
            dmg = math.max(1, math.floor(dmg * b.armor))
            self._hp = self._hp - dmg
            self.object:set_texture_mod("^[colorize:#ff000040")
            -- No knockback
            core.after(0.05, function()
                if self.object and self.object:get_pos() then
                    local v = self.object:get_velocity()
                    if v then
                        self.object:set_velocity({x = 0, y = v.y, z = 0})
                    end
                end
            end)
            if self._hp > 0 then
                core.after(0.15, function()
                    if self.object and self.object:get_pos() then
                        self.object:set_texture_mod("")
                    end
                end)
            end
        end,

        _set_anim = function(self, name)
            if self._anim == name then return end
            self._anim = name
            if name == "stand" then
                self.object:set_animation({x = 0, y = 79}, 10, 0, true)
            elseif name == "walk" then
                self.object:set_animation({x = 200, y = 219}, 15, 0, true)
            end
        end,

        get_staticdata = function(self)
            return core.serialize({hp = self._hp})
        end,
    })

    -- Boss immune to infection
    zombified_map[b.name] = b.name

    -- Spawn egg
    local function spawn_boss(itemstack, user, pointed_thing)
        if pointed_thing.type == "node" then
            local pos = pointed_thing.above
            pos.y = pos.y + 0.5
            local obj = core.add_entity(pos, b.name)
            if obj then
                obj:set_yaw(math.random() * math.pi * 2)
                -- Announce to players within 128 blocks
                for _, p in ipairs(core.get_connected_players()) do
                    local pp = p:get_pos()
                    if pp and vector.distance(pos, pp) <= 128 then
                        core.chat_send_player(p:get_player_name(),
                            core.colorize("#ff4444", b.desc .. " has appeared nearby!"))
                    end
                end
            end
            if not core.is_creative_enabled(user:get_player_name()) then
                itemstack:take_item()
            end
            return itemstack
        end
    end

    core.register_craftitem(b.name .. "_spawn_egg", {
        description = S(b.desc .. " Spawn Egg"),
        inventory_image = b.egg_texture,
        on_use = spawn_boss,
        on_place = spawn_boss,
        on_secondary_use = spawn_boss,
    })
end

-- =============================================================================
-- Boss natural spawning (rare, any light level)
-- =============================================================================

local boss_spawn_timer = 0  -- starts at 0, first check after full 120 seconds
core.register_globalstep(function(dtime)
    boss_spawn_timer = boss_spawn_timer + dtime
    if boss_spawn_timer < 120 then return end
    boss_spawn_timer = 0

    for _, player in ipairs(core.get_connected_players()) do
        local ppos = player:get_pos()
        if not ppos then goto boss_continue end

        -- Check if a boss already exists within 200 blocks
        local boss_nearby = false
        for _, obj in ipairs(core.get_objects_inside_radius(ppos, 200)) do
            local ent = obj:get_luaentity()
            if ent then
                for _, b in ipairs(BOSS_DEFINITIONS) do
                    if ent.name == b.name then
                        boss_nearby = true
                        break
                    end
                end
            end
            if boss_nearby then break end
        end
        if boss_nearby then goto boss_continue end

        -- 1 in 50 chance per player per check
        if math.random(1, 50) ~= 1 then goto boss_continue end

        local angle = math.random() * math.pi * 2
        local dist = 40 + math.random() * 40
        local try_pos = {
            x = math.floor(ppos.x + math.cos(angle) * dist),
            y = math.floor(ppos.y),
            z = math.floor(ppos.z + math.sin(angle) * dist),
        }

        for dy = -10, 10 do
            local ground = {x = try_pos.x, y = try_pos.y + dy, z = try_pos.z}
            local gnode = core.get_node(ground)
            local gdef = core.registered_nodes[gnode.name]
            if gdef and gdef.walkable then
                local above1 = {x = ground.x, y = ground.y + 1, z = ground.z}
                local above2 = {x = ground.x, y = ground.y + 2, z = ground.z}
                local above3 = {x = ground.x, y = ground.y + 3, z = ground.z}
                if core.get_node(above1).name == "air"
                        and core.get_node(above2).name == "air"
                        and core.get_node(above3).name == "air" then
                    -- Build weighted boss list
                    -- Void Reaper: 2x weight at night, 3x during bloodmoon
                    local boss_pool = {}
                    local tod = core.get_timeofday()
                    local is_night = tod < 0.23 or tod > 0.77
                    local is_bloodmoon = bloodmoon and bloodmoon.is_active and bloodmoon.is_active()
                    for _, bd in ipairs(BOSS_DEFINITIONS) do
                        local weight = 1
                        if bd.name == "infectious:boss_wither" then
                            if is_bloodmoon then
                                weight = 3
                            elseif is_night then
                                weight = 2
                            end
                        end
                        for _ = 1, weight do
                            table.insert(boss_pool, bd)
                        end
                    end
                    local boss = boss_pool[math.random(1, #boss_pool)]
                    local obj = core.add_entity(above1, boss.name)
                    if obj then
                        obj:set_yaw(math.random() * math.pi * 2)
                        -- Announce to players within 128 blocks
                        for _, p in ipairs(core.get_connected_players()) do
                            local pp = p:get_pos()
                            if pp and vector.distance(above1, pp) <= 128 then
                                core.chat_send_player(p:get_player_name(),
                                    core.colorize("#ff4444", boss.desc .. " has appeared nearby!"))
                            end
                        end
                    end
                    break
                end
            end
        end

        ::boss_continue::
    end
end)

core.log("action", "[infectious] Loaded!")
