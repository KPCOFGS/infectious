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

    local blacklist = self._blacklist or {}
    local best_target = nil
    local best_dist = ZOMBIE_RANGE

    for _, player in ipairs(core.get_connected_players()) do
        if not core.is_creative_enabled(player:get_player_name()) then
            local key = player:get_player_name()
            if not blacklist[key] then
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
    end

    for _, obj in ipairs(core.get_objects_inside_radius(pos, ZOMBIE_RANGE)) do
        if obj ~= self.object and not obj:is_player() and not is_zombie(obj) then
            local ent = obj:get_luaentity()
            if ent and ent.name ~= "__builtin:item"
                    and ent.name ~= "__builtin:falling_node" then
                local key = tostring(obj)
                if not blacklist[key] then
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
-- Helper: find ground position (feet on solid, head in air)
-- =============================================================================

local function find_ground(pos)
    local rpos = vector.round(pos)
    -- Search down for solid ground
    for dy = 0, -3, -1 do
        local check = {x = rpos.x, y = rpos.y + dy, z = rpos.z}
        if is_blocked(check) then
            return {x = rpos.x, y = rpos.y + dy + 1, z = rpos.z}
        end
    end
    return rpos
end

-- =============================================================================
-- A* pathfinding with waypoint following
-- =============================================================================

local PATH_RECALC_INTERVAL = 2.0   -- recalculate path every 2 seconds
local PATH_SEARCH_DIST     = 30    -- max pathfinding search distance
local PATH_MAX_JUMP        = 2     -- can jump up 2 blocks
local PATH_MAX_DROP        = 4     -- can drop 4 blocks
local WAYPOINT_REACH_DIST  = 1.5   -- how close to get before next waypoint

local function move_toward(self, target_pos, speed)
    local pos = self.object:get_pos()
    if not pos or not target_pos then return end

    local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
    local new_y = vel.y

    -- Initialize path state
    if not self._path then self._path = nil end
    if not self._path_index then self._path_index = 1 end
    if not self._path_timer then self._path_timer = 0 end
    if not self._last_pos then self._last_pos = pos end
    if not self._stuck_count then self._stuck_count = 0 end

    -- Recalculate path periodically
    self._path_timer = self._path_timer + 0.1
    if self._path_timer >= PATH_RECALC_INTERVAL or not self._path then
        self._path_timer = 0

        local start_pos = find_ground(pos)
        local end_pos = find_ground(target_pos)

        local path = core.find_path(start_pos, end_pos,
            PATH_SEARCH_DIST, PATH_MAX_JUMP, PATH_MAX_DROP, "A*_noprefetch")

        if path and #path > 0 then
            self._path = path
            self._path_index = 1
            self._stuck_count = 0
            self._nopath_count = 0
        else
            -- No path found
            self._path = nil
            self._nopath_count = (self._nopath_count or 0) + 1

            -- After 5 failed path attempts, blacklist current target for 30 seconds
            if self._nopath_count >= 5 and self._target then
                local key
                if self._target:is_player() then
                    key = self._target:get_player_name()
                else
                    key = tostring(self._target)
                end
                if self._blacklist then
                    self._blacklist[key] = core.get_gametime() + 30
                end
                self._target = nil
                self._nopath_count = 0
            end
        end
    end

    -- Stuck detection
    local horiz_moved = math.abs(pos.x - self._last_pos.x) + math.abs(pos.z - self._last_pos.z)
    if self._path_timer == 0 then  -- check every recalc cycle
        if horiz_moved < 0.3 then
            self._stuck_count = (self._stuck_count or 0) + 1
            if self._stuck_count >= 3 then
                -- Really stuck: blacklist target and move on
                if self._target and self._blacklist then
                    local key
                    if self._target:is_player() then
                        key = self._target:get_player_name()
                    else
                        key = tostring(self._target)
                    end
                    self._blacklist[key] = core.get_gametime() + 30
                    self._target = nil
                end
                self._path = nil
                self._stuck_count = 0
                new_y = ZOMBIE_JUMP_HEIGHT
            end
        else
            self._stuck_count = 0
        end
        self._last_pos = vector.new(pos)
    end

    -- Determine movement target: next waypoint or direct
    local move_target
    if self._path and self._path_index <= #self._path then
        local wp = self._path[self._path_index]
        local wp_dist = vector.distance(
            {x = pos.x, y = 0, z = pos.z},
            {x = wp.x, y = 0, z = wp.z}
        )

        if wp_dist < WAYPOINT_REACH_DIST then
            -- Reached waypoint, advance to next
            self._path_index = self._path_index + 1
            if self._path_index > #self._path then
                move_target = target_pos
            else
                move_target = self._path[self._path_index]
            end
        else
            move_target = wp
        end
    else
        -- No path: direct movement toward target
        move_target = target_pos
    end

    local dir = vector.direction(pos, move_target)
    dir.y = 0
    if vector.length(dir) < 0.01 then return end
    dir = vector.normalize(dir)

    -- Face movement direction
    local yaw = math.atan2(-dir.x, dir.z)
    self.object:set_yaw(yaw)

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

    -- Jump up if waypoint is above
    if move_target.y > pos.y + 0.5 then
        if vel.y >= -0.5 and vel.y <= 0.5 then
            new_y = ZOMBIE_JUMP_HEIGHT
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
-- Chunk-based mob cap: max zombies per 16x16x16 mapblock
-- =============================================================================

local CHUNK_MOB_CAP = 8
local all_zombies = {}

local function register_zombie(self)
    all_zombies[tostring(self.object)] = self
end

local function unregister_zombie(self)
    all_zombies[tostring(self.object)] = nil
end

local function pos_to_chunk(pos)
    return math.floor(pos.x / 16) .. ":" ..
           math.floor(pos.y / 16) .. ":" ..
           math.floor(pos.z / 16)
end

local cull_timer = 0
core.register_globalstep(function(dtime)
    cull_timer = cull_timer + dtime
    if cull_timer < 10 then return end
    cull_timer = 0

    -- Clean dead refs
    for key, z in pairs(all_zombies) do
        if not z.object or not z.object:get_pos() then
            all_zombies[key] = nil
        end
    end

    -- Group zombies by chunk
    local chunks = {}
    for key, z in pairs(all_zombies) do
        local zpos = z.object:get_pos()
        if zpos then
            local chunk = pos_to_chunk(zpos)
            if not chunks[chunk] then chunks[chunk] = {} end
            table.insert(chunks[chunk], {key = key, zombie = z})
        end
    end

    -- Cull randomly in overpopulated chunks
    for chunk, list in pairs(chunks) do
        if #list > CHUNK_MOB_CAP then
            -- Shuffle the list
            for i = #list, 2, -1 do
                local j = math.random(1, i)
                list[i], list[j] = list[j], list[i]
            end
            -- Remove excess
            for i = CHUNK_MOB_CAP + 1, #list do
                local entry = list[i]
                if entry.zombie.object and entry.zombie.object:get_pos() then
                    entry.zombie.object:remove()
                    all_zombies[entry.key] = nil
                end
            end
        end
    end
end)

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

    -- Blacklist tracking: targets we can't reach
    if not self._blacklist then self._blacklist = {} end
    if not self._nopath_count then self._nopath_count = 0 end

    -- Retarget
    self._retarget_timer = (self._retarget_timer or 0) + dtime
    if self._retarget_timer >= 1.0 then
        self._retarget_timer = 0
        self._target = find_target(self)
    end

    -- Clean expired blacklist entries
    local now = core.get_gametime()
    for key, expire_time in pairs(self._blacklist) do
        if now > expire_time then
            self._blacklist[key] = nil
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
        self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0})
        if self._set_anim then self:_set_anim("stand") end
        return
    end

    local tpos = target:get_pos()
    if not tpos then self._target = nil; return end

    local thp = target:get_hp()
    if not thp or thp <= 0 then self._target = nil; return end

    local dist = vector.distance(pos, tpos)
    if dist > ZOMBIE_RANGE * 1.5 then self._target = nil; return end

    self._attack_timer = (self._attack_timer or 0) + dtime

    if dist <= ZOMBIE_ATTACK_DIST then
        if self._set_anim then self:_set_anim("attack") end
        if self._attack_timer >= 0.8 then
            self._attack_timer = 0

            target:punch(self.object, 1.0, {
                full_punch_interval = 1.0,
                damage_groups = {fleshy = damage},
            }, vector.direction(pos, tpos))

            local kb_dir = vector.direction(pos, tpos)
            kb_dir.y = 0.3
            local tvel = target:get_velocity()
            if tvel then
                target:set_velocity(vector.add(tvel,
                    vector.multiply(kb_dir, ZOMBIE_KNOCKBACK)))
            end

            if not target:is_player() then
                try_infect(target)
            end
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
local SPAWN_MOB_CAP      = 10       -- max zombies within 50 blocks of player

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

        -- Check mob cap around player
        local nearby = core.get_objects_inside_radius(ppos, 50)
        local zombie_count = 0
        for _, obj in ipairs(nearby) do
            if is_zombie(obj) then
                zombie_count = zombie_count + 1
            end
        end
        if zombie_count >= SPAWN_MOB_CAP then goto continue end

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
                    if zombie_count >= SPAWN_MOB_CAP then break end

                    local offset = {
                        x = spawn_pos.x + math.random(-2, 2),
                        y = spawn_pos.y,
                        z = spawn_pos.z + math.random(-2, 2),
                    }
                    local obj = core.add_entity(offset, "infectious:zombie")
                    if obj then
                        obj:set_yaw(math.random() * math.pi * 2)
                        zombie_count = zombie_count + 1
                    end
                end
                break  -- one successful pack per player per cycle
            end
        end

        ::continue::
    end
end)

core.log("action", "[infectious] Loaded!")
