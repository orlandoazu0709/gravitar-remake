-- title:  Gravitar Remake


-- author: Levin Ho and Orlando Azuara
-- desc:   Remake of the infamous Gravitar Atari game :)
-- script: lua

--[[
 Strict variable declarations for Lua 5.1, 5.2, 5.3 & 5.4.
 Copyright (C) 2006-2023 std.strict authors
]]
--[[--
 Diagnose uses of undeclared variables.
 All variables(including functions!) must be "declared" through a regular
 assignment(even assigning `nil` will do) in a strict scope before being
 used anywhere or assigned to inside a nested scope.
 Use the callable returned by this module to interpose a strictness check
 proxy table to the given environment.   The callable runs `setfenv`
 appropriately in Lua 5.1 interpreters to ensure the semantic equivalence.
 @module std.strict
]]





local middleclass = {
  _VERSION     = 'middleclass v4.1.1',
  _DESCRIPTION = 'Object Orientation for Lua',
  _URL         = 'https://github.com/kikito/middleclass',
  _LICENSE     = [[
    MIT LICENSE
    Copyright (c) 2011 Enrique García Cota
    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:
    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  ]]
}

local function _createIndexWrapper(aClass, f)
  if f == nil then
    return aClass.__instanceDict
  elseif type(f) == "function" then
    return function(self, name)
      local value = aClass.__instanceDict[name]

      if value ~= nil then
        return value
      else
        return (f(self, name))
      end
    end
  else -- if  type(f) == "table" then
    return function(self, name)
      local value = aClass.__instanceDict[name]

      if value ~= nil then
        return value
      else
        return f[name]
      end
    end
  end
end

local function _propagateInstanceMethod(aClass, name, f)
  f = name == "__index" and _createIndexWrapper(aClass, f) or f
  aClass.__instanceDict[name] = f

  for subclass in pairs(aClass.subclasses) do
    if rawget(subclass.__declaredMethods, name) == nil then
      _propagateInstanceMethod(subclass, name, f)
    end
  end
end

local function _declareInstanceMethod(aClass, name, f)
  aClass.__declaredMethods[name] = f

  if f == nil and aClass.super then
    f = aClass.super.__instanceDict[name]
  end

  _propagateInstanceMethod(aClass, name, f)
end

local function _tostring(self) return "class " .. self.name end
local function _call(self, ...) return self:new(...) end

local function _createClass(name, super)
  local dict = {}
  dict.__index = dict

  local aClass = { name = name, super = super, static = {},
                   __instanceDict = dict, __declaredMethods = {},
                   subclasses = setmetatable({}, {__mode='k'})  }

  if super then
    setmetatable(aClass.static, {
      __index = function(_,k)
        local result = rawget(dict,k)
        if result == nil then
          return super.static[k]
        end
        return result
      end
    })
  else
    setmetatable(aClass.static, { __index = function(_,k) return rawget(dict,k) end })
  end

  setmetatable(aClass, { __index = aClass.static, __tostring = _tostring,
                         __call = _call, __newindex = _declareInstanceMethod })

  return aClass
end

local function _includeMixin(aClass, mixin)
  assert(type(mixin) == 'table', "mixin must be a table")

  for name,method in pairs(mixin) do
    if name ~= "included" and name ~= "static" then aClass[name] = method end
  end

  for name,method in pairs(mixin.static or {}) do
    aClass.static[name] = method
  end

  if type(mixin.included)=="function" then mixin:included(aClass) end
  return aClass
end

local DefaultMixin = {
  __tostring   = function(self) return "instance of " .. tostring(self.class) end,

  initialize   = function(self, ...) end,

  isInstanceOf = function(self, aClass)
    return type(aClass) == 'table'
       and type(self) == 'table'
       and (self.class == aClass
            or type(self.class) == 'table'
            and type(self.class.isSubclassOf) == 'function'
            and self.class:isSubclassOf(aClass))
  end,

  static = {
    allocate = function(self)
      assert(type(self) == 'table', "Make sure that you are using 'Class:allocate' instead of 'Class.allocate'")
      return setmetatable({ class = self }, self.__instanceDict)
    end,

    new = function(self, ...)
      assert(type(self) == 'table', "Make sure that you are using 'Class:new' instead of 'Class.new'")
      local instance = self:allocate()
      instance:initialize(...)
      return instance
    end,

    subclass = function(self, name)
      assert(type(self) == 'table', "Make sure that you are using 'Class:subclass' instead of 'Class.subclass'")
      assert(type(name) == "string", "You must provide a name(string) for your class")

      local subclass = _createClass(name, self)

      for methodName, f in pairs(self.__instanceDict) do
        if not (methodName == "__index" and type(f) == "table") then
          _propagateInstanceMethod(subclass, methodName, f)
        end
      end
      subclass.initialize = function(instance, ...) return self.initialize(instance, ...) end

      self.subclasses[subclass] = true
      self:subclassed(subclass)

      return subclass
    end,

    subclassed = function(self, other) end,

    isSubclassOf = function(self, other)
      return type(other)      == 'table' and
             type(self.super) == 'table' and
             ( self.super == other or self.super:isSubclassOf(other) )
    end,

    include = function(self, ...)
      assert(type(self) == 'table', "Make sure you that you are using 'Class:include' instead of 'Class.include'")
      for _,mixin in ipairs({...}) do _includeMixin(self, mixin) end
      return self
    end
  }
}

function middleclass.class(name, super)
  assert(type(name) == 'string', "A name (string) is needed for the new class")
  return super and super:subclass(name) or _includeMixin(_createClass(name), DefaultMixin)
end

setmetatable(middleclass, { __call = function(_, ...) return middleclass.class(...) end })

--return middleclass


local class = middleclass.class


--------------------------
-- Vector functions
--------------------------

pi2 = math.pi*2.0

-- gets a vector of given length
-- oriented on the given angle
function vector(length, angle)
 -- this could actually be optimized 
 -- since the X is always 0, to avoid
 -- two sin/cos calls.
 return rotate(0, -length, angle)
end

-- rotate a vector by a certain angle
function rotate(x,y,a)
 return 
  x*math.cos(a)-y*math.sin(a),
  x*math.sin(a)+y*math.cos(a)
end

-- gives the angle of a given vector
function angle(x,y)
 return math.pi - math.atan2(x,y)
end

-- give the angle from a certain point
-- to another point
function angle2(fromx,fromy, tox, toy)
 return angle(tox-fromx, toy-fromy)
end

-- calculates if an angle is closer
-- to a given angle in the positive
-- direction rather than the negative
-- returns -1, 0 or +1
function angleDir(from, to)
 local diff = to-from
 if math.abs(diff) < 0.00001 then return 0 end -- avoid rounding errors that will prevent settling
 if diff > math.pi then 
   return -1 
 elseif diff < -math.pi then
   return 1 
 else 
   return diff>0 and 1 or -1
 end
end

-- return the length of a vector
function vecLen(x,y)
  return math.sqrt(x ^ 2 + y ^ 2)
end

-- normalize vector to magnitude 1
function normalizeVec(x, y)
  local mag = vecLen(x, y)
  local new_x = x / mag
  local new_y = y / mag
  return x, y
end

-- adds two angles ensuring the
-- result is in the 0..2pi range
function angleAdd(a, d)
 a=a+d
 -- ensure angle is in 0..2pi range
 if a<0 then 
   a=a+pi2
 elseif a>=pi2 then 
   a=a-pi2
 end
 return a
end


----------------


TURN_RADIUS = 0.08    -- how much the car turn when pressing left or right
ACCEL_VALUE = 0.05    -- acceleration
MAX_VELOCITY = 1
FRICTION = 0 --0.98       -- how much the car decelerate on asphalt
DIRT_FRICTION = 0.95  -- deceleration on dirt
ALIGNEMENT = 0.025     -- how fast the velocity catch up with direciton

GRAVITY = 0.007

MAX_HEALTH = 30

function playSound(id, note, time, channel, vol, toggle)
  if toggle == 0 then
    sfx(id, note, time, channel, vol, toggle)
  end
end

local sound1_toggle = 0
local sound2_toggle = 0
local sound3_toggle = 0
local sound4_toggle = 0

local scorePlayer1 = 20
local scorePlayer2 = 0
local displayPlayer1 = "Player1: " .. scorePlayer1
local displayPlayer2 = "Player2: " .. scorePlayer2

local playerX = 0
local playerY = 0
local playerVX = 0
local playerVY = 0

local bullets = {}
local beams = {}
local turrets = {}
local ships = {}
local stars = {}
local explosions = {}
local orbs = {}
local bosses = {}

local level = nil

local isScrollingLevel = false

local topLeftCornerMapX = 0
local topLeftCornerMapY = 0

-- FOR USE ON SCROLLING MAPS ONLY -- the coord of the top left corner of screen, times eight
local mx = 0
local my = 0

Score = class("score")
function Score:initialize(x,y,score,color)
  self.x = x
  self.y = y
  self.color = color
  self.l = score
end
function Score:draw()
  rect((self.x - 2), (self.y - 2), MAX_HEALTH * 2 + 4, 8, 15)
  rect((self.x - 1), (self.y - 1), MAX_HEALTH * 2 + 2, 6, 0)
  rect((self.x), (self.y), self.l, 4, self.color)
end

HealthManager = class("healthManager")
function HealthManager:initialize(h)
  self.maxHealth = h
  self.invincibleTimer = 0
  self.damageCooldown = 10
  self:resetHealth()
end
function HealthManager:decreaseHealth(damage)
  --trace("TOOK DAMAGE")
  if self.invincibleTimer == 0 then
    scorePlayer1 = scorePlayer1 - damage
    sfx(11)
    self:setInvincibleTimer(self.damageCooldown)
  end
end
function HealthManager:increaseHealth(healing)
  scorePlayer1 = scorePlayer1 + healing
  if scorePlayer1 > MAX_HEALTH then
    scorePlayer1 = MAX_HEALTH
  end
end
function HealthManager:setInvincibleTimer(cycles)
  if cycles > self.invincibleTimer then
    self.invincibleTimer = cycles
  end
end
function HealthManager:loop()
  if self.invincibleTimer > 0 then
    self.invincibleTimer = self.invincibleTimer - 1
  end
end
function HealthManager:resetHealth()
  scorePlayer1 = self.maxHealth
end

local healthManager = HealthManager:new(MAX_HEALTH)

function isBlockingTile (tile_id)
  --bossTiles = {[1]=108, [2]=109, [3]=110, [4]=111, [5]=124, [6]=125, [7]=126, [8]=127, [9]=140, [10]=141, [11]=142, [12]=143, [13]=156, [14]=157,
  --[15]=158, [16]=159, [17]=172, [18]=173, [19]=174, [20]=175, [21]=188, [22]=189, [23]=190, [24]=191, [25]=204, [26]=205, [27]=206, [28]=207,
  --[29]=220, [30]=221, [31]=222, [32]=223, [33]=236, [34]=237, [35]=238, [36]=239, [37]=252, [38]=253, [39]=254, [40]=255}

  --boss_tile = false
  --for i,tile in pairs(bossTiles) do
  --  if tile_id == tile then
  --    boss_tile = true
  --  end
  --end

  if (tile_id >= 80 and tile_id <= 95) or (tile_id >= 117 and tile_id <= 120) then
    return true
  end
  return false
end

function clean_bullets_and_beams_table() -- removes collided bullets from the bullets table
  for i, b in pairs(bullets) do
    if b.collided == true then
      table.remove(bullets, i)
    end
  end
  for i, beam in pairs(beams) do
    if beam.done == true then
      table.remove(beams, i)
    end
  end
end
function clean_orbs_table()
  for i, orb in pairs(orbs) do
    if orb.collected == true then
      table.remove(orbs, i)
    end
  end
end

Explosion = class("explosion")
function Explosion:initialize(x, y)
  self.x = x
  self.y = y
  self.age = 0
end
function Explosion:draw()
  if self.age < 10 then
    spr(240, self.x-4, self.y-4, 0)
  elseif self.age < 40 then
    spr(241, self.x-4, self.y-4, 0)
  end
  self.age = self.age + 1
end

GravParticle = class("gravparticle")
function GravParticle:initialize()
  self.x = 0
  self.y = 0
  self.age = 0
  self:reset()
end
function GravParticle:reset()
  self.x = math.random(0, 240)
  self.y = math.random(0, 136)
  self.age = 0
end
function GravParticle:loop()
  self.y = self.y + GRAVITY*120
  circ(self.x, self.y, 0.5, 1)
  self.age = self.age + 1
  if self.age > 5 then
    self:reset()
  end
end

Orb = class("orb")
function Orb:initialize(x, y)
  self.x = x
  self.y = y
  self.collected = false
  self.collectedTimer = -1
  self.sprite = 169
end
function Orb:draw()
  spr(self.sprite, self.x, self.y, 0, 1, 0, 0, 1, 1)
end
function Orb:detectCollection()
  if self.collectedTimer > 0 then
    self.sprite = 185
    self.collectedTimer = self.collectedTimer - 1
  elseif self.collectedTimer == 0 then
    self.collected = true
    sfx(14)
    explosions[#explosions+1] = Explosion:new(self.x+4, self.y+4)
  elseif math.abs(self.x - playerX) < 8 and math.abs(self.y - playerY) < 8 then
    self.collectedTimer = 20
  end
end

Beam = class("beam")
function Beam:initialize(source, startx, starty, dir, maxChargeTime, maxShootTime, color1, color2, chargeColor)
  self.source = source
  self.startx = startx
  self.starty = starty
  self.dir = dir
  self.maxChargeTime = maxChargeTime
  self.chargeTime = maxChargeTime
  self.maxShootTime = maxShootTime
  self.shootTime = maxShootTime
  self.color1 = color1
  self.color2 = color2
  self.chargeColor = chargeColor
  self.done = false

  local stepx, stepy = vector(240, dir)
  self.targetx = startx + stepx
  self.targety = starty + stepy

end
function Beam:loop()
  if self.source.hit == true then
    self.done = true
  end

  if self.chargeTime > 0 then
    self.chargeTime = self.chargeTime - 1
    self:draw()
  elseif self.shootTime > 0 then
    self.shootTime = self.shootTime - 1
    self:draw()
  else
    self.done = true
  end
end
function Beam:draw()
  if self.chargeTime > 0 and self.chargeTime % 10 == 0 then
    line(self.startx, self.starty, self.targetx, self.targety, self.chargeColor)
  elseif self.chargeTime == 0 and self.shootTime > 0 then
    if self.shootTime % 6 == 0 then
      line(self.startx, self.starty, self.targetx, self.targety, self.chargeColor)
    else
      line(self.startx, self.starty, self.targetx, self.targety, self.color1)
      sfx(12)
    end
  end
end



Projectile = class("projectile")
function Projectile:initialize(source, startx, starty, startvx, startvy)
  self.initx = startx
  self.inity = starty
  self.x = startx
  self.y = starty
  self.vx = startvx
  self.vy = startvy
  self.vel = ((self.vx^2) +(self.vy^2))^(.5) 
  self.collided = false
  self.from_player = false
  self.source = source
  self.homing = false
  self.xray = false
  self.hit1 = false
  self.hit2 = false
  self.hit3 = false
  self.hit4 = false
  self.age = 0
end

function Projectile:playerMove()
  return 0
end

function Projectile:move(n)
  if self.homing then
    self.age = self.age + 1
    if self.age > 300 then
      self:set_collided()
    end
  end
  
  if self.homing then
    local angleOfAim = angle2(self.x, self.y, playerX, playerY)
    local currentAngle = angle(self.vx, self.vy)
    local angleAdjust = angleDir(currentAngle, angleOfAim)
    local currSpeed = vecLen(self.vx, self.vy)
    self.vx, self.vy = vector(currSpeed, currentAngle + 0.02*angleAdjust)
  end


  self.vy = self.vy

  self.x = self.x+self.vx
  self.y = self.y+self.vy

  if not self.xray then
    local on_tile_id = level_adjusted_mget(self.x // 8, self.y // 8)
    if isBlockingTile(on_tile_id) or self.x < 0 or self.x > 240 or self.y < 0 or self.y > 136 then
      self:set_collided()
    end
  end
end
function Projectile:draw()
  if self.from_player then
    self.color = 15
  elseif self.homing then
    self.color = 12
  elseif self.xray then
    self.color = 14
  else
    self.color = 6
  end
  rect((self.x), (self.y), 2, 2, self.color)
end
function Projectile:set_collided()
  self.collided = true
end

Boss = class('Boss')
-- flies in a circle around the middle of the arena
-- every 15 seconds, stops to shoot 3 lasers in succession at the player
-- every 3 seconds, shoots aimed projectiles at player
-- second phase?
function Boss:initialize()
  -- center of arena: 120, 68
  -- radius = 30?
  self.x = 120
  self.y = -100
  self.circlex = 0
  self.circley = 0
  self.angle = 0 --angle around circle. starts from right side
  self.laserCooldown = 400
  self.laserFireTimer = 0
  self.hp = 60
  self.bulletCooldown = 0
  self.isEnemy = true
  self.stage = 1
  self.action = 'circle'
  -- action is only for stage 2.
    -- circle: fly around in circle, occasionally shooting lasers.
    -- center: fly to center screen, shoot lasers in all directions

  --sprite id is 124
  --width is 4 sprites
  --height is 3 sprites
  --draw center should be x+16, y+12

end
function Boss:draw()
  if self.stage == 1 then
    spr(156, self.x-12, self.y-16, 2, 1, 0, 0, 4, 3)
  elseif self.stage == 2 then
    spr(108, self.x-12, self.y-16, 2, 1, 0, 0, 4, 3)
  end
end
function Boss:move()
  local targetx, targety = 0
  if self.action == 'circle' then
    targetx = self.circlex
    targety = self.circley
  end

  local dx, dy = normalizeVec(targetx - self.x, targety - self.y)
  self.x = self.x + 0.02*dx
  self.y = self.y + 0.02*dy

end
function Boss:loop()
  self:detectCollisions()

  if self.stage == 2 then
    if self.bulletCooldown == 0 then
      local bullet1x, bullet1y = self.x-12, self.y-10
      local bullet2x, bullet2y = self.x+12, self.y-10

      local distToPlayer = ((bullet1x - playerX)^2 + (bullet1y - playerY)^2)^0.5
      local angleOfAim = angle2(bullet1x, bullet1y, playerX + 0.3*distToPlayer*playerVX,
                                                    playerY + 0.3*distToPlayer*playerVY)
      local shoot_vx, shoot_vy = vector(0.8, angleOfAim)
      local bullet1 = Projectile:new(self, bullet1x, bullet1y, shoot_vx, shoot_vy)
      bullets[#bullets + 1] = bullet1

      local distToPlayer = ((bullet2x - playerX)^2 + (bullet2y - playerY)^2)^0.5
      local angleOfAim = angle2(bullet2x, bullet2y, playerX + 0.6*distToPlayer*playerVX,
                                                    playerY + 0.6*distToPlayer*playerVY)
      local shoot_vx, shoot_vy = vector(0.8, angleOfAim)
      local bullet2 = Projectile:new(self, bullet2x, bullet2y, shoot_vx, shoot_vy)
      bullets[#bullets + 1] = bullet2
      self.bulletCooldown = 100
    else
      self.bulletCooldown = self.bulletCooldown - 1
    end
  end

  if self.laserCooldown == 0 then
    local laserx, lasery = self.x+4, self.y-12

    local beamDir = angle2(laserx, lasery, playerX, playerY)
    local beam = Beam:new(self, laserx, lasery, beamDir, 50, 100, 6, 14, 14)
    beams[#beams + 1] = beam
    if self.stage == 2 then
      local beam2 = Beam:new(self, laserx, lasery, beamDir+0.5, 50, 100, 6, 14, 14)
      beams[#beams + 1] = beam2
      local beam3 = Beam:new(self, laserx, lasery, beamDir-0.5, 50, 100, 6, 14, 14)
      beams[#beams + 1] = beam3
    end
    self.laserCooldown = 400
    self.laserFireTimer = 150
  else
    self.laserCooldown = self.laserCooldown - 1
  end

  -- calculate circle
  local d_x = 0
  local d_y = 0
  if self.stage == 1 then
    d_x, d_y = vector(18, self.angle)
  elseif self.stage == 2 then
    d_x, d_y = vector(50, self.angle)
  end
  self.circlex = 120+d_x
  self.circley = 68+d_y
  if self.laserFireTimer == 0 then
    if self.stage == 1 then
      self.angle = self.angle + 0.006
    elseif self.stage == 2 then
      self.angle = self.angle - 0.015
    end
  else
    self.laserFireTimer = self.laserFireTimer - 1
  end

  -- move boss
  if self.laserFireTimer == 0 then
    self:move()
  end
end
function Boss:detectCollisions()
  --detects collisions with both player and player bullets.
  --returns true if collided with player.
  --processes damage internally if collided with bullets
  --collision box: x, x+32. y, y+24
  local bulletThatHit = detectBullets(self.x, self.y, 32, 24)
  if bulletThatHit ~= nil and bulletThatHit.from_player == true then
    bulletThatHit:set_collided()
    self.hp = self.hp -1
    bossHealth.l = bossHealth.l - 1
    trace(self.hp)
  end
  if self.hp <= 30 then
    self.stage = 2
  end
end

Turret = class("Turret")
function Turret:initialize(x, y, c, a, b)
  self.x = x
  self.y = y
  self.max_cooldown = c
  self.cooldown = 30
  self.a = a
  
  self.behavior = b
  self.isEnemy = true
  self.hit = false

end
function Turret:loop()
  if self.cooldown == 0 then
    if self.behavior == 'beam-aim' then
      --(source, startx, starty, targetx, targety, maxChargeTime, maxShootTime, color1, color2, chargeColor)
      local beamDir = angle2(self.x, self.y, playerX, playerY)
      local beam = Beam:new(self, self.x, self.y, beamDir, 50, 100, 6, 14, 14)
      beams[#beams + 1] = beam
      self.cooldown = self.max_cooldown
    else
      if self.behavior == "random" then
        self.shoot_vx, self.shoot_vy = vector(0.6, self.a + math.random()*math.pi - (math.pi/2))
      elseif self.behavior == "aim" or self.behavior == "xray" then
        local distToPlayer = ((self.x - playerX)^2 + (self.y - playerY)^2)^0.5
        local angleOfAim = angle2(self.x, self.y, playerX + 0.6*distToPlayer*playerVX,
                                                  playerY + 0.6*distToPlayer*playerVY)
        self.shoot_vx, self.shoot_vy = vector(0.8, angleOfAim)
      elseif self.behavior == "homing" then
        self.shoot_vx, self.shoot_vy = vector(0.6, self.a)
      else
        self.shoot_vx, self.shoot_vy = vector(0.6, self.a)
      end
      
      local bullet = Projectile:new(self, self.x, self.y, self.shoot_vx, self.shoot_vy)
      if self.behavior == "homing" then
        bullet.homing = true
      elseif self.behavior == "xray" then
        bullet.xray = true
      end

      bullets[#bullets + 1] = bullet
      self.cooldown = self.max_cooldown
    end
  elseif self.cooldown > 0 then
    self.cooldown = self.cooldown - 1
  end

  local bulletHit = detectBullets(self.x, self.y, 16, 16)
  if bulletHit ~= nil and bulletHit.source.isEnemy == false then
    self.cooldown = -1
    self.hit = true
    sfx(9)
    explosions[#explosions+1] = Explosion:new(self.x, self.y)
    for tilex = self.x//8 - 1, self.x//8 + 1 do
      for tiley = self.y//8 - 1, self.y//8 + 1 do
        if level_adjusted_mget(tilex, tiley) >= 1 and level_adjusted_mget(tilex, tiley) <= 14 then
          level_adjusted_mset(tilex, tiley, 0)
        end 
      end
    end
  end
end

Ship = class("Ship")
function Ship:initialize(x, y)
  self.x = x
  self.y = y
  self.moving_left = true
  self.max_cooldown = 90
  self.cooldown = 0
  self.id = 288
  self.isEnemy = true
  self.hit = false
end
function Ship:move()
  if self.moving_left == true then
    if self.x > 20 then
      self.x = self.x - 0.5
    else
      self.moving_left = false
    end
  else
    if self.x < 220 then
      self.x = self.x + 0.5
    else
      self.moving_left = true
    end
  end
end
function Ship:draw()
  if not self.hit then
    spr(self.id, self.x-7, self.y-10, 0, 1, 0, 0, 2, 2)
  end
end
function Ship:shoot()
  if self.cooldown == 0 then
    bullets[#bullets + 1] = Projectile:new(self, self.x, self.y, 0, 1)
    self.cooldown = self.max_cooldown
  elseif self.cooldown > 0 then
    self.cooldown = self.cooldown - 1
  end
end
function Ship:loop()
  if not self.hit then
    self:shoot()
    self:move()
    local bulletHit = detectBullets(self.x, self.y, 16, 8)
    if bulletHit ~= nil and bulletHit.source.isEnemy == false then
      self.hit = true
      sfx(9)
      explosions[#explosions+1] = Explosion:new(self.x, self.y)
    end
  end
end

Car = class("Car")
function Car:initialize(startx, starty)
  self.x = startx
  self.y = starty
  self.vx = 0
  self.vy = 0
  self.vel = ((self.vx^2) +(self.vy^2))^(.5) 
  self.a = 0
  self.accelerating = false
  self.spinning = false
  self.spinTimer = 0
  self.cooldown = 0
  self.max_cooldown = 30
  self.isEnemy = false
  self.beamDamage_cooldown = 0
  self.wasHit = false
  self.healingTimer = 0
  self.healingCooldown = 0
end

function Car:spin(car)
    self.a=angleAdd(self.a,-(TURN_RADIUS * 2))
end
    
function Car:move(left, right, forward, backward, heal, player_num)
 if scorePlayer1 < 1 then
  return
 end

 -- rotate our direction
 if btn(left) then self.a=angleAdd(self.a,-TURN_RADIUS) end
 if btn(right) then self.a=angleAdd(self.a,TURN_RADIUS) end
  
 self.vel = ((self.vx^2) +(self.vy^2))^(.5) 
 self.accelerating = false
 if self.healingTimer == 0 then
    if btn(forward) then
      self.accelerating = true
      local ax,ay = vector(ACCEL_VALUE,self.a)
      self.vx=self.vx+ax
      self.vy=self.vy+ay
    elseif btn(backward) then
      self.accelerating = true
      local ax,ay = vector(-1*ACCEL_VALUE,self.a)
      self.vx=self.vx+ax
      self.vy=self.vy+ay 
    end
  end

 --enforcing a maximum velocity
 self.vel = ((self.vx^2) +(self.vy^2))^(.5) 
 if self.vel > MAX_VELOCITY then
  self.vx = self.vx * .9
  self.vy = self.vy * .9
  self.vel = ((self.vx^2) +(self.vy^2))^(.5) 
 end

 -- collision and boundary
 local bounce_offset = 0.5
 local bounce = -0.6
 local bounce_dmg = 1

 if self.x < 2 and self.vx < 0 then
  self.vx = 0
 elseif self.x > 238 and self.vx > 0 then
  self.vx = 0
 elseif math.fmod(self.x, 8) < 2 then -- to the left
  local left_tile = level_adjusted_mget((self.x - 8) // 8, self.y // 8)
  if isBlockingTile(left_tile) then
    self.x = self.x + bounce_offset
    self.vx = bounce*self.vx
    healthManager:decreaseHealth(bounce_dmg)
  end
 elseif math.fmod(self.x, 8) > 5 then
  local right_tile = level_adjusted_mget((self.x + 8) // 8, self.y // 8)
  if isBlockingTile(right_tile) then
    self.x = self.x - bounce_offset
    self.vx = bounce*self.vx
    healthManager:decreaseHealth(bounce_dmg)
  end
 end

 if self.y < 2 and self.vy < 0 then
  self.vy = 0
 elseif self.y > 134 and self.vy > 0 then
  self.vy = 0
 elseif math.fmod(self.y, 8) < 2 then
  local top_tile = level_adjusted_mget(self.x // 8, (self.y - 8) // 8)
  if isBlockingTile(top_tile) then
    self.y = self.y + bounce_offset
    self.vy = bounce*self.vy
    healthManager:decreaseHealth(bounce_dmg)
  end
 elseif math.fmod(self.y, 8) > 5 then
  local bottom_tile = level_adjusted_mget(self.x // 8, (self.y + 8) // 8)
  if isBlockingTile(bottom_tile) then
    self.y = self.y - bounce_offset
    self.vy = bounce*self.vy
    healthManager:decreaseHealth(bounce_dmg)
  end
 end

--  trace(self.healingTimer)
--  if self.healingTimer == 0 then
--   if self.healingCooldown == 0 and btn(heal) then
--     self.healingTimer = 120
--     self.healingCooldown = 900
--   end
--  else
--   self.healingTimer = self.healingTimer - 1
--   if self.healingTimer == 10 then
--     sfx(14, 34, 30, 0)
--     sfx(14, 38, 30, 1)
--     sfx(14, 42, 30, 2)
    
--     -- sfx(14, 34)
--     -- sfx(14, 38)
--     healthManager:increaseHealth(15)
--   end
--  end
--  if self.healingCooldown > 0 then
--   self.healingCooldown = self.healingCooldown - 1
--  end

  -- applying gravity
  self.vy = self.vy + GRAVITY

 -- add velocity to car
 self.x=self.x+self.vx
 self.y=self.y+self.vy

end
function Car:detectBulletHit()
  local bulletHit = detectBullets(self.x, self.y, 8, 8)
  if bulletHit ~= nil and bulletHit.source.isEnemy == true then
    bulletHit:set_collided()
    self.wasHit = true
    return true
  end
  return false
end
function Car:detectBeamHit()
  if self.beamDamage_cooldown == 0 then
    for i, beam in pairs(beams) do
      if beam.chargeTime == 0 then
        local angle_to_player = angle2(beam.startx, beam.starty, self.x, self.y)
        local theta = angle_to_player - beam.dir
        if math.abs(theta) < math.pi/2 then
          -- trace(theta)
          local hypo = vecLen(beam.startx - self.x, beam.starty - self.y)
          local oppo = hypo * math.sin(theta)
          -- trace(margin)
          local margin = 4
          if oppo < margin and oppo > -margin then
            self.beamDamage_cooldown = 2
            self.wasHit = true
            return true
          end
        end
      else
        break
      end
    end
    return false
  else
    self.beamDamage_cooldown = self.beamDamage_cooldown -1
  end
end
function Car:shoot(button)
  if self.cooldown <= 0 then
    if btn(button) then
      local ax,ay = vector(1 + (5*ACCEL_VALUE),self.a)
      local bullet = Projectile:new(self, self.x, self.y, ax*1.5, ay*1.5)
      bullet.from_player = true
      --bullet.xray = true -- CHEAT MODE
      bullets[#bullets + 1] = bullet
      sfx(8)
      self.cooldown = self.max_cooldown
    end
  else
    self.cooldown = self.cooldown - 1
  end
end
function Car:draw()
  if scorePlayer1 >= 1 then
    local color = 13
    if self.wasHit then
      color = 6
      self.wasHit = false
    end

    local ax,ay = vector(10, self.a)
  
    local visx = self.x - 0.2*ax
    local visy = self.y - 0.2*ay
  
    line(visx, visy, visx + 0.6*ax, visy + 0.6*ay, color)
    line(visx + 1.5*ax, visy + 1.5*ay, visx + 1.7*ax, visy + 1.7*ay, 15)
  
    local px,py = vector(10, self.a + 3*pi2/8)
    line(visx, visy, visx - 0.3*px, visy - 0.3*py, color)
  
    local px,py = vector(10, self.a + 1*pi2/8)
    line(visx, visy, visx + 0.3*px, visy + 0.3*py, color)
  
    if self.accelerating then
      circ(visx - 0.2*ax, visy - 0.2*ay, 0.5, 15)
    end

    if self.healingTimer > 20 then
      if self.healingTimer % 10 < 2 then
        circb(self.x+0.2*ax, self.y+0.2*ay, 5, 11)
      end
    elseif self.healingTimer > 0 then
      circb(self.x+0.2*ax, self.y+0.2*ay, 10-(self.healingTimer/2), 11)
    end

    if self.healingCooldown > 0 and self.healingCooldown < 50 then
      circb(self.x+0.2*ax, self.y+0.2*ay, self.healingCooldown / 5, 11)
    end
  end
end

local gravParticles = {}
function generateGravParticles()
  if GRAVITY ~= 0 then
    if #gravParticles < 2 then
      gravParticles[#gravParticles+1] = GravParticle:new()
    end
    for i, particle in pairs(gravParticles) do
      particle:loop()
    end
  end
end

-- detect if there are bullets within a rectangular aea
function detectBullets (x, y, width, height)
  for i, b in pairs(bullets) do
    if detectBulletInBox(b, x, y, width, height) == true then
      return b
    end
  end
  return nil
end

-- detect if a specific bullet instance is inside a rectangular area
function detectBulletInBox (bullet, x, y, width, height)
  if bullet.x > x-(width/2) and bullet.x < x+(width/2) then
    if bullet.y > y-(height/2) and bullet.y < y+(height/2) then
      return true
    end
  end
  return false
end

local player_ship = Car:new(120, 68)

Star = class("star")
function Star:initialize(x, y, levelNum)
  self.x = x
  self.y = y
  self.levelNum = levelNum
  self.levelAndSprite = {
    [1] = 480,
    [2] = 482,
    [3] = 484,
    [4] = 486,
    [5] = 421
  }
  self.levelAndBeatSprite = { --sprites for if the level has been beaten
    [1] = 448,
    [2] = 450,
    [3] = 452,
    [4] = 454,
    [5] = 421
  }
end

bossHealth = Score:new(88,130, 60, 6)

local starsBeat = {[1] = false, [2] = false, [3] = false, [4] = false, [5] = false}

local levelWinCondition = 'none'
-- 'enemies': win by killing all enemies
-- 'orbs': win by collecting all orbs that appear
-- 'boss': win by killing the boss
-- 'none': not a level

local nextLevel = 0

function levelSelect(num)
  level = num
  player_ship = Car:new(120, 68)
  -- healthManager:setInvincibleTimer(180)
  sync(0,0,false) -- this undoes mset() effects

  bullets = {}
  beams = {}
  turrets = {}
  ships = {}
  stars = {}
  explosions = {}
  orbs = {}
  bosses = {}

  levelWinCondition = 'none'
  nextLevel = 0

  isScrollingLevel = false

  if level == 1 then -- BROWN STAR PT 1
    healthManager:resetHealth()
    music(1)
    topLeftCornerMapX = 0
    topLeftCornerMapY = 0
    levelWinCondition = 'enemies'
    nextLevel = 10
  
    GRAVITY = 0.0065
    -- turrets[1] = Turret:new(159, 56, 150, 0, "homing")
    turrets[1] = Turret:new(159, 56, 140, 0, "homing")
    turrets[2] = Turret:new(40,88, 80, 120, 1.5*math.pi,"")
    turrets[3] = Turret:new(224, 104, 120, 1.5*math.pi, "")
    --turrets[3] = Turret:new(224, 104, 180, 1.5*math.pi, "beam")
  
    -- ships[1] = Ship:new(159, 30)
  elseif level == 10 then -- BROWN STAR PT 2
    topLeftCornerMapX = 0
    topLeftCornerMapY = 17
    levelWinCondition = 'enemies'
  
    GRAVITY = 0.007
    turrets[1] = Turret:new(216, 48, 120, 1.5*math.pi, "")
    turrets[2] = Turret:new(192, 80, 120, 1.5*math.pi, "")
    turrets[3] = Turret:new(180, 120, 70, 1.5*math.pi, "")
    turrets[4] = Turret:new(64, 112, 120, 0, "homing")
  elseif level == 11 then -- BROWN STAR PT 3 -- incomplete
    topLeftCornerMapX = 0
    topLeftCornerMapY = 34

    GRAVITY = 0.007
  elseif level == 2 then -- BLUE STAR PT 1
    healthManager:resetHealth()
    music(3)
    topLeftCornerMapX = 30
    topLeftCornerMapY = 0
    levelWinCondition = 'enemies'
    nextLevel = 20
  
    GRAVITY = -0.002
    player_ship.y = 10

    turrets[1] = Turret:new(56, 88, 50, 1.5*math.pi, "")
    turrets[2] = Turret:new(48, 52, 50, 0, "random")
    turrets[3] = Turret:new(192, 52, 50, 0, "homing")
    turrets[4] = Turret:new(192, 92, 100, 0, "xray")

  elseif level == 20 then -- BLUE STAR PT 2
    topLeftCornerMapX = 30
    topLeftCornerMapY = 17
    levelWinCondition = 'enemies'

    GRAVITY = -0.002
    player_ship.y = 10
  
    turrets[1] = Turret:new(64, 96, 90, 0, "aim")
    turrets[2] = Turret:new(104, 64, 135, 0, "xray")
    turrets[3] = Turret:new(168, 104, 50, 1.5*math.pi, "random")
    turrets[4] = Turret:new(200, 80, 50, 0, "aim")

  elseif level == 3 then -- GREEN STAR PT 1
    healthManager:resetHealth()
    music(4)
    topLeftCornerMapX = 60
    topLeftCornerMapY = 0
    levelWinCondition = 'enemies'
    nextLevel = 30

    GRAVITY = -0.005
    player_ship.x = 30

    turrets[1] = Turret:new(40, 96, 90, 0, "aim")
    turrets[2] = Turret:new(200, 96, 90, 0, "aim")
    turrets[3] = Turret:new(120, 72, 60, 0, "homing")
  elseif level == 30 then -- GREEN STAR PT 2
    topLeftCornerMapX = 60
    topLeftCornerMapY = 17
    levelWinCondition = 'enemies'

    GRAVITY = -0.005
    --player_ship.x = 30

    turrets[1] = Turret:new(24, 112, 130, 0, "homing")
    turrets[2] = Turret:new(96, 112, 90, 0, "aim")
    turrets[3] = Turret:new(136, 112, 90, 0, "aim")
    turrets[4] = Turret:new(200, 64, 90, 1.5*math.pi, "")
  elseif level == 4 then -- GREY STAR PT 1
    healthManager:resetHealth()
    music(5)
    topLeftCornerMapX = 90
    topLeftCornerMapY = 0
    levelWinCondition = 'enemies'
    nextLevel = 40

    GRAVITY = 0.017

    turrets[1] = Turret:new(96, 88, 90, 0, "")
    turrets[2] = Turret:new(144, 88, 90, 0, "")
    turrets[3] = Turret:new(192, 80, 90, 1.5*math.pi, "")
    turrets[4] = Turret:new(32, 104, 90, 0, "aim")
  elseif level == 40 then -- GREY STAR PT 2
    topLeftCornerMapX = 90
    topLeftCornerMapY = 17
    levelWinCondition = 'enemies'

    GRAVITY = 0.017
    player_ship.y = 30

    turrets[1] = Turret:new(32, 112, 110, 0, "aim")
    turrets[2] = Turret:new(120, 120, 110, 0, "aim")
    turrets[3] = Turret:new(160, 112, 90, 0, "aim")
    turrets[4] = Turret:new(200, 112, 100, 0, "homing")
    turrets[5] = Turret:new(112, 72, 50, 0, "random")
  elseif level == 5 then -- FINAL LEVEL PT 1
    --trace('here')
    healthManager:resetHealth()
    music(6)
    topLeftCornerMapX = 150
    topLeftCornerMapY = 0
    levelWinCondition = 'orbs'
    nextLevel = 6
  
    GRAVITY = 0.008
    -- turrets[1] = Turret:new(159, 56, 150, 0, "homing")
    --turrets[1] = Turret:new(159, 56, 140, 0, "homing")
    player_ship.y = 100
    turrets[1] = Turret:new(120,20, 280, math.pi/4, "beam-aim")
    turrets[2] = Turret:new(40,130, 210, math.pi/4, "beam-aim")
    turrets[3] = Turret:new(200,130, 350, math.pi/4, "beam-aim")
    turrets[4] = Turret:new(120, 65, 100, 0, "xray")
    --turrets[3] = Turret:new(224, 104, 180, 1.5*math.pi, "beam")
  
    -- ships[1] = Ship:new(159, 30)
    --GRAVITY = 0

    --ships[1] = Ship:new(159, 30)

    --GENERATE ORBS

    for i=1,6 do
      local orbx, orby = 0, 0
      repeat
        orbx = math.random(25, 207)
        orby = math.random(33, 103)
      until orbx > 24 and orbx < 208 and not (orbx > 88 and orbx < 152) and orby > 32 and orby < 104
      orbs[#orbs+1] = Orb:new(orbx, orby)
    end

  elseif level == 6 then --FINAL LEVEL PT 2
    healthManager:resetHealth()
    topLeftCornerMapX = 150
    topLeftCornerMapY = 35
    levelWinCondition = 'enemies'
    nextLevel = 99
  
    GRAVITY = 0.008
    
    player_ship.x = 20
    player_ship.y = 100
    turrets[1] = Turret:new(56,36, 370, math.pi/4, "beam-aim")
    turrets[2] = Turret:new(16,70, 410, math.pi/4, "beam-aim")
    turrets[3] = Turret:new(120,84, 440, math.pi/4, "beam-aim")
    turrets[4] = Turret:new(175,36, 340, math.pi/4, "beam-aim")




  elseif level == 99 then -- experimental boss arena
    healthManager:resetHealth()
    music(6)
    topLeftCornerMapX = 180
    topLeftCornerMapY = 34
    levelWinCondition = 'boss'

    GRAVITY = 0

    bosses[1] = Boss:new()
    bossHealth.l = 60

    turrets[1] = Turret:new(16,16, 280, 0, 'beam-aim')
    turrets[2] = Turret:new(224,16, 350, 0, 'beam-aim')
    turrets[3] = Turret:new(16,120, 180, 0, 'xray')
    turrets[4] = Turret:new(224,120, 180, 0, 'xray')

  elseif level == 0 then -- STAR SCREEN
    music(2)
    healthManager:resetHealth()
    topLeftCornerMapX = 0
    topLeftCornerMapY = 119

    GRAVITY = 0

    stars[1] = Star:new(50, 60, 1) -- easiest
    if starsBeat[1] then
      explosions[#explosions+1] = Explosion:new(50, 60)
    end
    stars[2] = Star:new(90, 30, 2) -- second easiest
    if starsBeat[2] then
      explosions[#explosions+1] = Explosion:new(90, 30)
    end
    stars[3] = Star:new(180, 45, 3) -- most difficult
    if starsBeat[3] then
      explosions[#explosions+1] = Explosion:new(180, 45)
    end
    stars[4] = Star:new(140, 25, 4) -- third easiest
    if starsBeat[4] then
      explosions[#explosions+1] = Explosion:new(140, 25)
    end
    --if starsBeat[1] and starsBeat[2] and starsBeat[3] and starsBeat[4] then
      stars[5] = Star:new(200, 90, 5) -- final level
      if starsBeat[5] then
        explosions[#explosions+1] = Explosion:new(200, 90)
      end
    --ends
  elseif level == -1 then -- INTRO SCREEN
    healthManager:resetHealth()
    music(2)
    topLeftCornerMapX = 0
    topLeftCornerMapY = 119

    GRAVITY = 0
  end
  mx = 0
  my = 0
end

function Star:loop()
  local bulletHit = detectBullets(self.x, self.y, 12, 12)
  if bulletHit ~= nil and bulletHit.source.isEnemy == false then
    if self.levelNum == 5 then
      bulletHit:set_collided()
      continue = true
    else
      bulletHit:set_collided()
      levelSelect(self.levelNum)
    end
  end
end
function Star:draw()
  if not starsBeat[self.levelNum] then
    spr(self.levelAndSprite[self.levelNum], self.x - 8, self.y - 8, 0, 1, 0, 0, 2, 2)
  else
    spr(self.levelAndBeatSprite[self.levelNum], self.x - 8, self.y - 8, 0, 1, 0, 0, 2, 2)
  end
  
end

levelSelect(-1)

function level_adjusted_mget(x, y)
  if x >= 0 and x <= 29 and y >= 0 and y <= 17 then
    x = x + topLeftCornerMapX
    y = y + topLeftCornerMapY
    return mget(x, y)
  end
  return 0
end

function level_adjusted_mset(x, y, id)
  x = x + topLeftCornerMapX
  y = y + topLeftCornerMapY
  return mset(x, y, id)
end

function scroll_adjusted_spr(t)
  setmetatable(t, {__index={colorkey=-1,scale=1,flip=0,rotate=0,w=1,h=1}})
  local id, x, y, colorkey, scale, flip, rotate, w, h =
    t[1] or t.id,
    t[2] or t.x,
    t[3] or t.y,
    t[4] or t.colorkey,
    t[5] or t.scale,
    t[6] or t.flip,
    t[7] or t.rotate,
    t[8] or t.w,
    t[9] or t.h
  spr(id, x-mx, y-my, colorkey, scale, flip, rotate, w, h)
end


local health = Score:new(88,2,scorePlayer1,15)
local t = 0
continue = false

function updateScores()
  health.l = scorePlayer1 * 2
  displayPlayer1 = "Player1: " .. scorePlayer1
  displayPlayer2 = "Player2: " .. scorePlayer2
end

function remap(tile, x, y)
    local outTile, flip, rotate = tile, x, y
    return outTile, flip, rotate
end

function textbox(x,y)
  rect(x-2,y-2,190,30,15)
  print("Your greatest challenge awaits.", x, y, 0, true)
  print("Do you wish to continue?", x, y+10, 0, true)
  print("X-Yes (There's no other option)", x, y+20, 0, true)
end

local m = 0
local call = 0

local lossTimer = 0

function TIC()
 -- if m == 0 then
 --   music(2)
 -- end
-- m = 1
  --BEHAVIOR LOOP
  healthManager:loop()
  player_ship:move(2, 3, 7, 4, 6, 1)

  playerX = player_ship.x
  playerY = player_ship.y
  playerVX = player_ship.vx
  playerVY = player_ship.vy
  -- t = t + 1
  -- my = my + 0.25

  player_ship:shoot(5)

  for i, stars in pairs(stars) do  
    stars:loop()
  end

  local allTurretsDead = true
  for i, turret in pairs(turrets) do
    if not turret.hit then
      allTurretsDead = false
      turret:loop()
    end
  end

  for i, ships in pairs(ships) do
    ships:loop()
  end

  for i, boss in pairs(bosses) do
    boss:loop()
  end

 -- DETECT WIN
  if levelWinCondition == 'enemies' then
    if allTurretsDead then
      if level == 10 then
        starsBeat[1] = true
      elseif level == 20 then
        starsBeat[2] = true
      elseif level == 30 then
        starsBeat[3] = true
      elseif level == 40 then
        starsBeat[4] = true
      end
      levelSelect(nextLevel)
    end
  end
  if levelWinCondition == 'orbs' then
    if #orbs == 0 then
      levelSelect(nextLevel)
    end
  end
  if levelWinCondition == 'boss' then
    if bosses[1].hp <= 0 then
      levelSelect(nextLevel)
    end
  end

  -- PLAYER HIT DETECTION
  if player_ship:detectBulletHit() == true then
    healthManager:decreaseHealth(3)
    -- scorePlayer1 = scorePlayer1 -3
    -- health.l = health.l -3
    sfx(13)
    player_ship:spin(player_ship)
  end
  if player_ship:detectBeamHit() == true then
    healthManager:decreaseHealth(3)
    sfx(13)
  end

  for i, orb in pairs(orbs) do
    orb:detectCollection()
    break
  end
  for i, bullet in pairs(bullets) do
    bullet:move()
  end

  -- DETECT LOSS
  if scorePlayer1 < 1 then
    if lossTimer == 0 then
      sfx(10)
      explosions[#explosions+1] = Explosion:new(playerX, playerY)
      lossTimer = 120
    elseif lossTimer == 1 then
      -- healthManager:resetHealth()
      levelSelect(0)
    end
  end
  if lossTimer > 0 then
    lossTimer = lossTimer - 1
  end

  clean_bullets_and_beams_table()
  clean_orbs_table()

  cls(3)
  mx = (playerX-120)
  my = (playerY-68)

  -- DRAW LOOP
  if isScrollingLevel == false then
    map(topLeftCornerMapX, topLeftCornerMapY)
  else
    map(topLeftCornerMapX, topLeftCornerMapY,100,100,-mx,-my)
  end
  
  if level == -1 then
    --print("GRAVITAR", 60, 40, 15, true)
    spr(160, 88, 30, 0, 1, 0, 0, 8, 5)
    print("Press S for forwards, Z for backwards.", 15, 90, 4, true)
    print("Left/right arrows to turn,", 25, 100, 4, true)
    print("X to shoot.", 30, 110, 4, true)
    print("Press X to continue.", 35, 125, 4, true)
    if btn(5) then
      levelSelect(0)
    end
  else
    updateScores()
    health:draw()
    if level == 99 then
    bossHealth:draw()
    end

    generateGravParticles()
    for i, star in pairs(stars) do
    star:draw()
    end
    for i, bullet in pairs(bullets) do
    bullet:draw()
    end
    for i, beam in pairs(beams) do
      beam:draw()
    end
    for i, ship in pairs(ships) do
    ship:draw()
    end
    player_ship:draw()
    for i, explosion in pairs(explosions) do
    explosion:draw()
    end
    for i, orb in pairs(orbs) do
      orb:draw()
      break
    end
    for i, boss in pairs(bosses) do
      boss:draw()
    end
    for i, beam in pairs(beams) do
      beam:loop()
    end

    if level == 0 and continue == false then
      print("Shoot a star to begin.", 45, 115, 4, true)
      print("(Tip: The left is easiest.)", 30, 125, 4, true)
    end
    if continue == true then
      textbox(30,100)
      if btn(5) then
        continue = false
        levelSelect(5)
      end
    end
  end
end

function soundTrigger()
  if t == 1 then
    sfx(0)
  end
end
function flr(a) return math.floor(a) end
function rou(x) return x + 0.5 - (x + 0.5) % 1 end

-- <TILES>
-- 001:0000000000000000000000090000099900099000009009990900906690090000
-- 002:0000000000000000900000009990000000099000999009006609009000009009
-- 003:0099096000090960000909000000909000009009000009000000009000000009
-- 004:0000000900000090000009000000900900009090000909000009096000990960
-- 005:0000000000000005000000050000055000055000005005550500506650050000
-- 006:0000000050000000500000000550000000055000555005006605005000005005
-- 007:000000000000000000000cc00000c00c000c000000c00ccc0c00c066c00c0000
-- 008:00000000000000000cc00000c00c00000000c000ccc00c00660c00c00000c00c
-- 009:000000d00000000d000000d000000ddd000dd00000d00ddd0d00d006d00d0006
-- 010:0d000000d00000000d000000ddd00000000dd000ddd00d00600d00d06000d00d
-- 011:000007000000706000070060007006600006600e00600fff0600706660070000
-- 012:00700000060700000600700006600700e0066000fff006006607006000007006
-- 013:600700000600706600600fff0006600e00700660000700600000706000000700
-- 014:0000700666070060fff00600e006600006600700060070000607000000700000
-- 017:333333333aaaaa3a3aaaaa3a3aaaaa3a3aaaaa3a3aaaaa3a3333333a3aaaaaaa
-- 018:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa33333333
-- 080:1111111110000000101111111011111110111111101111111011111110111111
-- 081:1111111100000001111111011111110111111101111111011111110111111101
-- 082:1111110111111101111111011111110111111101111111010000000111111111
-- 083:1011111110111111101111111011111110111111101111111000000011111111
-- 084:1111111100000000111111111111111111111111111111111111111111111111
-- 085:1111110111111101111111011111110111111101111111011111110111111101
-- 086:1111111111111111111111111111111111111111111111110000000011111111
-- 087:1011111110111111101111111011111110111111101111111011111110111111
-- 088:1011111100111111111111111111111111111111111111111111111111111111
-- 089:1111110111111100111111111111111111111111111111111111111111111111
-- 090:1111111111111111111111111111111111111111111111111111110011111101
-- 091:1111111111111111111111111111111111111111111111110011111110111111
-- 092:1011111100111111111111111111111111111111111111111111110011111101
-- 093:1111110111111100111111111111111111111111111111110011111110111111
-- 095:0000000001111110011111100111111001111110001111100000111000000000
-- 108:2222222222222222222222222222722222270722227070722707670722716172
-- 109:222227062222706122270061227006192226611e2261111e2227761f2222776f
-- 110:60722222160722221600722291600722e1166222e1111622f1677222f6772222
-- 111:2222222222222222222222222227222222707222270707227076707227161722
-- 112:1111111111111111111111111111111111111111111111111111111111111111
-- 113:1000000011000000111000001111000011111000111111001111111011111111
-- 114:1111111111111110111111001111100011110000111000001100000010000000
-- 115:1111111101111111001111110001111100001111000001110000001100000001
-- 116:0000000100000011000001110000111100011111001111110111111111111111
-- 117:8888888888888888088888800008880008888880888888880888888000088800
-- 118:0000000000b0b0b000bbbbb000bbbbb00bbbbbb00bbbbbb00b0b0bb000000000
-- 119:0003333003333330333333303333333033330303333030303303030300000000
-- 120:6000000666666666061111600611116006111166066611600606666666000006
-- 124:2271117222271732222270632222230622222230222222302222230677223063
-- 125:2222277622227077227700073770000663070006666670073266677022266006
-- 126:6772222277072222700077226000077360007036700766660776662360066222
-- 127:2711172223717222360722226032222203222222032222226032222236032277
-- 140:7073063227076032270070322270070327000070277700072222700022222777
-- 141:2770030670070300270072332277222232222222322222227222222272222222
-- 142:6030077200307007332700722222772222222223222222232222222722222227
-- 143:2360370723067072230700723070072207000072700077720007222277722222
-- 156:2222222222222222222222222222722222270722227070722707070722700072
-- 157:222227222222707722270000227006662226600e226000762227707022227700
-- 158:22722222770722220000722266600722e0066222670006220707722200772222
-- 159:2222222222222222222222222227222222707222270707227070707227000722
-- 160:00000000000000cc0000cccc00ccccccccccccccc0ccccccc0ccccccc0cccccc
-- 161:cccccccccccccccccccccccccccc0000cc00000000cccccc0000000000000000
-- 162:ccccccc0ccccc000ccc00000000ccccc0000cc00cccc0000000000cc0000cccc
-- 163:00000cc00000000000000000000000000000000c000000000000000000000000
-- 164:0000000000000000000cc00000000cccc00cc0000cc00ccc000ccccc0ccccccc
-- 165:00000000000000000cc00000c00000000cc00cc0c00cc000ccc00000ccccc000
-- 167:00000000cc000000000000000000000000000000000000000000000000000000
-- 169:0000000000088800008ee88008ee8e8008e8ee80088ee8000088800000000000
-- 172:2270007222270732222270032222230022222230222222302222230077223003
-- 173:2222277022227077227700073770000003070000000670073000677022000006
-- 174:0772222277072222700077220000077300007030700760000776000360000022
-- 175:2700072223707222300722220032222203222222032222220032222230032277
-- 176:c0ccccccc0ccccccc0ccccccc0ccccccc0ccccccc0ccccccc0ccccccc0cccccc
-- 177:0000000000000000000000cc0000cc0000000000000000000000000000000000
-- 178:00cccccccccccccccccccccc00cccccc00cccccc00cccccc00cccccc00cccccc
-- 179:0000000c00cc000000000000000000000000000c000000000000000000000000
-- 180:c00ccccc0ccccccc000ccccc0cc00cccc00cc00000000ccc000cc00000000000
-- 181:ccc00cc0ccccc000ccc00000c00cc0000cc00cc0c00000000cc0000000000000
-- 182:0000cc0000000000000000000000000c0000000c0000000c0000000c000cc00c
-- 183:000000000000000000000000ccc00000ccccc000ccccccc0ccccccccccc0cccc
-- 184:000000000000000000000000000000000000000000000000c0000000c0000000
-- 185:00eee00f0ee000f0ee000000e00ff00ee00ff00e000000ee0f000ee0f00eee00
-- 188:7073003227070032270070322270070327000070277700072222700022222777
-- 189:2770030070070300270072332277222232222222322222227222222272222222
-- 190:0030077200307007332700722222772222222223222222232222222722222227
-- 191:2300370723007072230700723070072207000072700077720007222277722222
-- 192:c0ccccccc000cccc000000cccccc0000cccccc00cccccccccccccccccccc0ccc
-- 193:cc000000cccc00cccccccccccccccccc00cccccc0000cc00cc000000cc000000
-- 194:cccccccccccccc00cccc00cccc00000c000000cc0000cc0000cc0000ccccc0cc
-- 195:00000cc0000000000000000000000000000000000000000000000000cc00cccc
-- 196:000000000000000000000000000ccccc000ccccc000ccccc000000cc0cccc0cc
-- 197:000000000000000c00000ccccccccccccccccccccccccccccc00cccccc00cccc
-- 198:0ccccc0ccccccc0ccccccc0cc0cccc0c00cccc0c00cccc0ccccccc0ccccccc0c
-- 199:ccc00cccccc00cccccccccccccccccc0ccccccccccc00cccccc00cccccc00ccc
-- 200:c0000000c0000000c000000000000000c0000000c0000000c0000000c0000000
-- 204:0000000000000000000000000000700000070700007070700707670700706070
-- 205:000007060000706100070061007006110006611e0061111e0007761f0000776f
-- 206:60700000160700001600700011600700e1166000e1111600f1677000f6770000
-- 207:0000000000000000000000000007000000707000070707007076707007060700
-- 208:cccc00cccccc00cccccccccccccccccccccccccccccc00cccccc00cccccc00cc
-- 209:cc0000cccc00cccccc0ccccc000cccc0cc0cccc0cc0ccccccc0ccccccc0ccccc
-- 210:ccccc0ccccccc0cc0cccc0cc0cccc0cc0cccc0ccccccc0ccccccc0ccccccc0cc
-- 211:cc00cccccc00cccccc00cccccc00cccccc00cccccc00cccccc00cccccc00cccc
-- 212:0cccc0cc0cccc0cc0cccc0cc0cccc0cc0cccc0cc0cccc0cc0cccc0cc0cccc0cc
-- 213:cc00cccccc00cccccc00cccccc00cccccc00cccccc00cccccc000000cc000000
-- 214:cccccc0c00cccc0c00cccc0000cccc0000cccc0000cccc000000000000000000
-- 215:ccc00cccccc00ccc000000000000000000000000000000000000000000000000
-- 216:c0000000c0000000000000000000000000000000000000000000000000000000
-- 220:0070007000070730000070630000030600000030000000300000030677003063
-- 221:0000077600007077000700073070000663070006666670073066677000066006
-- 222:6770000077070000700070006000070360007036700766660776660360066000
-- 223:0700070003707000360700006030000003000000030000006030000036030077
-- 224:cccc00cccccc00cc000000000000000000000000000000000000000000000000
-- 225:cc0cccc0cc0cccc0000cccc0000cccc0000cccc0000000000000000000000000
-- 226:0cccc0cc0cccc0cc0cccc0cc0cccc0000cccc000000000000000000000000000
-- 227:cc00cccccc00cccccccccccccccccc0000cc0000000000000000000000000000
-- 228:0cccc0cc0cccc0000cccc0000cccc0000cccc000000000000000000000000000
-- 229:cc00000000000000000000000000000000000000000000000000000000000000
-- 236:7073063070076030070070300700070300700070006700070066700000066777
-- 237:0770030670070300070070330077000030000000300000007000000070000000
-- 238:6030077000307007330700700000770000000003000000030000000700000007
-- 239:0360370703067007030700703070007007000700700076000007660077766000
-- 240:f00f00000f0f00f000f00f00ff0f00000000f0ff00f00f000f00f0f00000f00f
-- 241:a000000a0a0a000000000a000a000000000000a000a000000000a0a0a000000a
-- 252:000066ee00000666000000660000000000000000000000000000000000000000
-- 253:f0000000eff000006eff000066eff000066eeff0006660000000000000000000
-- 254:0000000f00000ffe0000ffe6000ffe660ffee660000666000000000000000000
-- 255:ee66000066600000660000000000000000000000000000000000000000000000
-- </TILES>

-- <SPRITES>
-- 000:00000000000dd000000dd000000dd000000dd000000dd00000d00d000d0000d0
-- 001:000000000000dd000000dd00000dd00000ddd000dd00d0000000d0000000d000
-- 002:0000000000000d000000ddd0000ddd00ddddd000000d0000000d0000000d0000
-- 003:000000000000000000000dd0ddddddd0000dd000000d000000d0000000d00000
-- 016:00000000000dd000000dd000000dd000000dd000000dd00000dffd000d0000d0
-- 017:000000000000dd000000dd00000dd00000ddd000ddffd0000000d0000000d000
-- 018:0000000000000d000000ddd0000ddd00ddddd00000fd0000000d0000000d0000
-- 019:000000000000000000000dd0ddddddd000fdd00000fd000000d0000000d00000
-- 032:0000000000000000000000000000000000000099999009000999900000990099
-- 033:0000000000000000000000000000000099000000009009990009999099009900
-- 034:0008800000800800080880808806608800800800000880000080080000800800
-- 048:0000990600000000000000000000000000000000000000000000000000000000
-- 049:6099000000000000000000000000000000000000000000000000000000000000
-- 064:3333333333e55e33305dd50333d55d3333555533305555033355553333333333
-- 065:33333333333e5533330dd5e333d55d0330555d33355550333335533333333333
-- 066:333333333330e533333ddd5330555de335555d03335553333335033333333333
-- 067:3333333333330e33330dd55335555d5335555de33355d0333350333333333333
-- 080:3333333333e11e33301dd10333d11d3333111133301111033311113333333333
-- 081:33333333333e1133330dd1e333d11d0330111d33311110333331133333333333
-- 082:333333333330e133333ddd1330111de331111d03331113333331033333333333
-- 083:3333333333330e33330dd11331111d1331111de33311d0333310333333333333
-- 096:3333333333ecce3330cddc0333dccd3333cccc3330cccc0333cccc3333333333
-- 097:33333333333ecc33330ddce333dccd0330cccd333cccc033333cc33333333333
-- 098:333333333330ec33333dddc330cccde33ccccd0333ccc333333c033333333333
-- 099:3333333333330e33330ddcc33ccccdc33ccccde333ccd03333c0333333333333
-- 160:0000000000000000000001110001100000100011060001000000600100000010
-- 161:6111000000011000110101000011010010106011010606001060606006060606
-- 162:0000000001001001110110111010010010010010010110110010010000100100
-- 163:0000000000100000011000001001000001001000011011001001001010010010
-- 165:0000000000000600000060000006000000060060006006000060200200202020
-- 166:0000000000600000000600000000600006006000006006002002060002020200
-- 176:0000001000006001060001000010001100011000000001110000000000000000
-- 177:0060606010060600010060001010001100110100110101000001100061110000
-- 178:0010010000100100010110111001001010100100110110110100100100000000
-- 179:1001001010010010011011000100100010010000011000000010000000000000
-- 181:6020202060200200600220066222006006000606002200600000200600000222
-- 182:0202020660200206060220066060222606060060606022000602000022200000
-- 192:0000000000000011000000110010000100010001000010010000010000000010
-- 193:0000000011000000110000001000000010000100100010000011000001000000
-- 194:0000000000000008000000000000000800000088000008880008888808800888
-- 195:8000000088000000800000008800000088800000888800008888880088880088
-- 196:0000000000bbbbbb000bbbbb0000b0b00000b0b0000000b000000000000000b0
-- 197:00000000bbbbbb00bbbbb000b0b0b000b0b0b000b0b00000b0b00000b0000000
-- 198:0000003300000300000030000000300300030003000300330003003300030033
-- 199:0000000000000000033330003333000033330030333330033333333333333333
-- 204:3333333333110033310000033103300330033103300010033300003333333333
-- 205:3333333333333333333333333333333333333333333333333333333333333333
-- 206:3333333333333333333333333333333333333333333333333333333333333333
-- 207:3333333333333333333333333333333333333333333333333333333333333333
-- 208:0111110000000010000011000001000100100001000000010000001100000011
-- 209:0011111001000000001000001001000010001000100001001100000011000000
-- 210:0000000008800888000888880000088800000088000000080000000000000000
-- 211:0000000088880088888888008888000088800000880000008000000000000000
-- 212:000000b00000b0b00000b0b00000b0b000bbbbbb0bbbbbbb000bbbbb0000000b
-- 213:00b00000b0b00000b0b0b000b0b0b000bbbbbb00bbbbbbb0bbbbbb00bbbb0000
-- 214:0033303303000303300000333000003030000030030003030000000000000000
-- 215:3333333333333330333333300333300000000000000000033333333000000000
-- 220:3333333333333333333333333333333333333333333333333333333333333333
-- 221:3333333333333333333333333333333333333333333333333333333333333333
-- 222:3333333333333333333333333333333333333333333333333333333333333333
-- 223:3333333333333333333333333333333333333333333333333333333333333333
-- 224:0000000000000011000000110010000100010001000010010000010000000010
-- 225:0000000011000000110000001000000010000100100010000011000001000000
-- 226:0000000000000008000000000000000800000088000008880008888808800888
-- 227:8000000088000000800000008800000088800000888800008888880088880088
-- 228:0000000000bbbbbb000bbbbb0000b0b00000b0b0000000b000000000000000b6
-- 229:00000000bbbbbb00bbbbb000b0b0b000b0b0b000b0b00000b0b00000b6000000
-- 230:0000003300000300000030000000300300030003000300330003003300030033
-- 231:0000000000000000033330003333000033330030333330033333333333333333
-- 236:3333333333333333333333333333333333333333333333333333333333333333
-- 237:3333333333333333333333333333333333333333333333333333333333333333
-- 238:3333333333333333333333333333333333333333333333333333333333333333
-- 239:3333333333333333333333333333333333333333333333333333333333333333
-- 240:0111110600000016000011000001000100100001000000010000001100000011
-- 241:6011111061000000001000001001000010001000100001001100000011000000
-- 242:0000000608800888000888880000088800000088000000080000000000000000
-- 243:6600000088880088888888008888000088800000880000008000000000000000
-- 244:000000b60000b0b60000b0b00000b0b000bbbbbb0bbbbbbb000bbbbb0000000b
-- 245:66b00000b0b00000b0b0b000b0b0b000bbbbbb00bbbbbbb0bbbbbb00bbbb0000
-- 246:0033303303000303300660333006603030000030030003030000000000000000
-- 247:3333333333333330333333300333300000000000000000033333333000000000
-- 252:3333333333333333333333333333333333333333333333333333333333333333
-- 253:3333333333333333333333333333333333333333333333333333333333333333
-- 254:3333333333333333333333333333333333333333333333333333333333333333
-- 255:3333333333333333333333333333333333333333333333333333333333333333
-- </SPRITES>

-- <MAP>
-- 000:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000676767676767676767676767676767676767676767676767676767676767000000000000000000000000000000000000000000000077777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 001:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000067676767676700006767676767676767676700006767676767670000000000000000000000000000000000000000000000000000777777777700000000000000000000000000000000000000000000000000000000000000878787878787878787878787777777777777878787878787878787878787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:0000000000000000000000004454000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000067670000000000006767676767670000000000006767000000000000000000000000000000000000000000000000000000000077777777770000000000000000000000000000000000000000000000000000000000008700000000000000000087878700d0e00087878700000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:000000000000000000000000000000000000000000000000000000000000000000000000000000575700000000000000005757000000000000000000000000000000000000000000000067670000000000000000000000000000000000777777000000000000000000000000000000000000000077777777000000000000000000000000000000000000000000000000000000000000870000000000000000000087000000000000870000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 004:0000000000000000000000000000000000000000000000000000000000f5000000000000000057575757570000000057575757570000000000000000000000000000000000000000000000000000000000000000000000000000007777777777000000000000000000000000000000000000000000777777000000000000000000000000000000000000000000000000000000000000878700000000000000000000000000000000000000000000000000008787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 005:00000000000000000000000000000000060000000000000000000000f5f5000000000000000000005757575700005757575700000000000000000000000000000000000000000000000000000000000000000000000000000000777777770000000000000000000000000000000000000000000000777777000000000000000000000000000000000000000000000000000000000000878700000000000000000000000000000000000000000000000000008787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 006:000000004151000000000000000000000000000000000000000000f5f5f5000000000010200057570000575757575757000057570070800000000000000000000000000000000000000000000000000000000000000000000000777777000000000000000000000000000000000000000000000000007777000000000000000000000000000000000000000000000000000000000000870087000000000000000000000000000000000000000000000000870087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 007:00000000f5f50000000000000000000000000070806262000000f5f5f5f5000000000057575757575700575757575757005757575757570000000000000000000000000000000000000000000000000000000000000000000000777700000000000000000000000000000000000000000000000000007777000000000000000000000000000000000000000000000000000000000000870000000000000000000087008787878700870000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 008:000000f5f5f50000410000000000000000f5f5f5f5f5f5f5f5f5f5f5f5f5000000000000575757005757575757575757575700575757000000000000000000000000000000000000000000000000000000000000000000000000777700000000000000000000000000000000000000000000000077777777000000000000000000000000000000000000000000000000000000000000870000000000000000000000870090a00087000000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 009:0000f5f5f500000000f5f5f5000000000000f5f5f5f5f5f5f5f5f5f5f5f5000000000000000000005757575757575757575700000000000000000000000000000000000000000000000070800000000000000000000000000000770000000000000000000000000000000000000000000000407777777777000000000000000000000000000000000000000000000000000000000000870000000000000000000087008787878700870000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:00f5f5f500000000f5f5f50000000000000000000000000000000000f5f5000000000000004057575757575757575757575757570000000000000000000000000000000000000000000067670000000000000000000000000000770000000000007777000000000000000000000000000000307777777777000000000000000000000000000000000000000000000000000000000000870087000000000000000000000000000000000000000000000000870087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:f5f5f5f5102000f5f5f5f5090000000000000000000000000000000000f5000000000000003057000057575757575757570000570090a00000000000000000000000000000000000000067670000000000000000000000000000770000000000007777770010200077770010200077770000777777777777000000000000000000000000000000000000000000000000000000000000878700000000000000000000000000000000000000000000000000008787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 012:f5f5f5f5f5f5f5f5f5f5f5000000000000000000000000000000000040f5000000000057575757575757575757575757575757575757570000000000000000005060000000000000000067670000000000000000506000000000770000000000007777777777777777777777777777777777777777777777000000000000000000000000000000000000000000000000000000000000878700000000000000000000000000000000000000000000000000008787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 013:f5f5f5f5f5f5f5f5f5f5f5000000000000000000000000000000000030f5000000000000575757000000575757575757000057575700000000000000000000006767000000000000000067670000000000000000676700000000777700506000777777777777777777777777777777777777777777777777000000000000000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 014:f5f5f5f5f5f5f5f5f5f5f5000000000000000000000000000000000000f5000000000000000000000000000057570000000000000000000000000000000000006767000000000000000067670000000000000000676700000000777777777777777777777777777777777777777777777777777777777777000000000000000000000000000000000000000000000000000000000000870000008787000000000000000000000000000000000000878700000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:f5f5f5f5f5f5f5f5f5f5f5004656465659000000000000000000000000f5000000000000000000000000000000000000000000000000000000000000000000006767000000000000000067670000000000000000676700000000777777777777777777777777777777777777777777777777777777777777000000000000000000000000000000000000000000000000000000000000870087878787878700000000000000000000000000008787878787870087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:f5f5f5f5f5f5f5f5f5f5f5000000000000f5f5f5f5f5f5f5f5f5f5f5f5f500000000000000000000000000000000000000000000000000000000000000000000676700000000000000006767000000000000000067670000000077777777777777777777777777777777777777777777777777777777777700000000000000000000000000000000000000000000000000000000000087878700b0c0008787878787878787878787878787878700b0c000878787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 017:00f5f5f5f5f5f5f50000000000000000f5f5f5f5f5f5f5f5f5f5f5f5f5f5000000000000000000000000000000000000000000000000000000000000000000676767676767676767676767676767676767676767676700000000000000777777777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011111111000000001111111111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 018:f5f5f5f5f5f5f5f5000000000000000000f5f5f5f5f5f5f5f5f5f5f5f5f5000000000000000000000000000000000000000000000000000000000000000000006767670000000000000000000000000000006767670000000000000077777777777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111111111111111111111111111111111111111111111111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 019:f5f5f5f5f5f5f50000000000000000000000f5f5f5f5f5f5f5f5f5f5f5f5000000000000000000000000000000000000000000000000000000000000000000000067676700000000000000000000000000676767000000000000007777777777777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878787878787878787878787878787878787878787878787878787878787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 020:f5f5f5f5f5f500000000000000000000000000f5f5f5f5f5f5f5f5f5f5f50000000000000000000000000000000000000000005757000000000000000000000000006767670000000000000000000000676767000000000000007777777777777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008700d0e000878787008787870000878700008787870087878700d0e00087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 021:f5f5f5f500000000000000000000000000000000f5f5f5f5f5f5f5f5f5f5000000000000000000000000000000000000005757575757570000000000000000000000006767670000000000000000006767670000000067000000777777777777777700000000000000000000000000000000000000777777000000000000000000000000000000000000000000000000000000000000000000000000878700008787000000000000878700008787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 022:f5f5f5f5000000000000000000000000000000000000000000000040f5f5000000000000005757000000000057570000000000575700000000000000000000000000000067670000000000000000006767000000000067670000777777777777770000000000000000000000000000000000007777777777000000000000000000000000000000000000000000000000000000000000000000000000008700000087000000000000870000008700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 023:f5f5f500000000000000f5f500000000000000000000000000000030f5f5000000000000575757570000575757575757000000575700000000000000000000000000000000000000000000000000000000000000000067670000777777777777000000000000000000000000000000007777777777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 024:f5f5f500000000000000f5f5f50000000000f5f5f5f5f5f5f5f5f5f5f5f5000000000000005757000000000057570000005757575757570000000000000000000000000000000000000000000000000000000000004067670000777777777700000000000000000000000000000000777777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 025:f5f5f500000000000000f5f500000000000000f5f5f5f5f5f5f5f5f5f5f500000000000000000000000090a057570000000000575700000000000000000000000000000000000000000000000000000000000000003067670000777777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 026:f5f5f500000000000000000000000000000000000000000040f5f5f5f5f5000000000057570000000000575757575757000000000000000000000000000000000000000000000000000000000000006700000000000067670000777777770000000000000000001020777777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 027:f5f5f500000000000000000000000000000000000000000030f5f5f5f5f5000000575757575757000000000057570000000000005757506000000000000000000000000000000000000000000000676700000000000067670000777777770000000000000000007777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 028:f5f5f500000000000000f5f500000000000000f5f5f5f5f5f5f5f5f5f5f5000000000057570000000000000000000000000000575757575700000000000000000000000067000000000000000000006767000000000067670000777777000000000000000077777777000000000000000000000000000077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 029:f5f5f500000000000000f5f5f500000000000000f5f5f5f5f5f5f5f5f5f5000000000057575060000000000000000000000000405757000000000000000000000000000067670000000000000000006767000000000067670000777777000000000000007777770000000000000000000000000000007777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 030:f5f5f500000000000000f5f5f500000000000000000000f5f5f5f5f5f5f5000000575757575757000000000000000000000000305757000000000000000000000000006767000000000000000000000067670000000067670000777700000000000000777777000000000000000000000000000000007777000000000000000000000000000000000000000000000000000000000000870000000000000000000087000000000000870000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 031:f5f5f5000000007080f5f5f5f50000000000000000000040f5f5f5f5f5f5000000000057570000000000000000000000000000575757575700000000000070800000006767000050600000005060000067670000000067670000777700506000000077777700000000000000005060000000708077777777000000000000000000000000000000000000000000000000000000000000878700000000000000878787000070800000878787000000000000008787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 032:f5f5f500000000f5f5f5f5f5f50000000000000000000030f5f5f5f5f5f500000000000000000000000000000000000000000000575700000000000000006767000067670000006767000000676700000067670000006767000077777777777777777777000000005060000077777777000077777777777700000000000000000000000000000000000000000000000000000000000087878700b0c0008787878787000011110000878787878700b0c000878787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 033:f5f5f5000000f5f5f5f5f5f5f50000000000000000000000f5f5f5f5f5f5000000000000000000000000000000000000000000000000000000000000000067670000676700000067670000006767000000676700000067670000777777777777777777777777777777777777777777777777777777777777000000000000000000000000000000000000000000000000000000000000878787878787878787878787111111111111878787878787878787878787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 034:f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878787000087008787878700878700000000870000008700878787000000878787870000000000000000000000000000000000000000000087878787000000000000000000000000000000000000000000000000000000000000
-- 035:f5f5f5f5f5f5f5f5f5000000000000000000000000f5f5f5f5f5f5f5f5f500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000087878787878787878787878787878787878787878787878787878787878787d0e0008700000000000000000000000000000000000000008700d0e087000000000000000000000000000000000000000000000000000000000000
-- 036:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000878700000000000000000000000000000087870000000000000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000
-- 037:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000008700000000000000000000000000000087878700000000000000000000000000000000000000000000000000008787000000000000000000000000000000000000000000000000000000000000
-- 038:f5f5f5f5f5f5f500000000000000000000000000000000f5f5f5f5f5f5f5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000008787878787870000000087000000000087878787000000000087878700000000000000000000000000000000000000000000000000008700000000000000000000000000000000000000000000000000000000000000
-- 039:f5f5f5f5f5f5000000000000000000000000000000000000f5f5f5f5f5f5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000008700d0e000870000000087000000878700d0e000870000000087000087000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000000000000000000000
-- 040:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000087000000000000000087000000870000000000870000000087870000000000000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000
-- 041:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000878700000000000087000000878700000000870000000087870000000000000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000
-- 042:f5f5f5f5f5f5000000000000000000000000000000000000f5f5f5f5f5f5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000008787000000000087000000008700000000878700000087878700000000000000000000000000000000000000000000000000008787000000000000000000000000000000000000000000000000000000000000
-- 043:f5f5f5f5f50000000000000000000000000000000000000000f5f5f5f5f500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000087b0c0000000000087000000008787000000008787000000008700000087870000000000000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000
-- 044:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878787870000000000870000008700000000008787870000008700000087870000000000000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000
-- 045:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008787878700000000000000000087b0c00000000087870000008700000087000087000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000000000000000000000
-- 046:f5f5f5f5f50000000000000000000000000000000000000000f5f5f5f5f5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878787000000000000000000000087870000000087870000008700000087008700000000000000000000000000000000000000000000000000008700000000000000000000000000000000000000000000000000000000000000
-- 047:f5f5f5f500000000000000000000000000000000000000000000f5f5f5f5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878700000000870000878700000000878700000087870000000087000087878700000000000000000000000000000000000000000000000000008787000000000000000000000000000000000000000000000000000000000000
-- 048:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000087870000008700000000000000000000870000000000000087870000000000000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000
-- 049:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008700000087870000000087870000000000000000878700000000000000878790a000870000000000000000000000000000000000000000870090a087000000000000000000000000000000000000000000000000000000000000
-- 050:f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878787878787878787878787878787878787878787878787878787878787878787870000000000000000000000000000000000000000000087878787000000000000000000000000000000000000000000000000000000000000
-- 085:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878777877777778787878787878787878787878777778777777787878787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 086:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000777777777777777777777777777777777777777777777777777777777777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 087:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000008787878787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 088:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000000087878787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 089:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 090:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878787878700000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 091:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878787870000000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 092:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 093:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000008787878787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 094:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000000087878787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 095:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 096:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878787878700000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 097:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878787870000000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 098:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000000087878787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 099:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000000000870087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 100:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000000000008787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 101:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 103:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878787878787878787878787777777777777878787878787878787878787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 104:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008700000000000000000087878700d0e00087878700000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 105:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000087000000000000870000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 106:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878700000000000000000000000000000000000000000000000000008787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 107:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878700000000000000000000000000000000000000000000000000008787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 108:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870087000000000000000000000000000000000000000000000000870087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 109:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000087008787878700870000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 110:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000870090a00087000000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 111:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000087008787878700870000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 112:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870087000000000000000000000000000000000000000000000000870087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 113:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878700000000000000000000000000000000000000000000000000008787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 114:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000878700000000000000000000000000000000000000000000000000008787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 115:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000000000000000000000000000000000000000000000000000000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 116:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870000008787000000000000000000000000000000000000878700000087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 117:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000870087878787878700000000000000000000000000008787878787870087000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 118:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000087878700b0c0008787878787878787878787878787878700b0c000878787000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdef0123456789abcdef
-- </WAVES>

-- <SFX>
-- 000:02000240023002000210024002600230021002000240026002700250024002200240026002700260024002200230026002700240022002200250027030200000f000
-- 001:501050005000500050005000500050005000500050005000500050005000500050005000500050005000500050005000500050005000500050005000407000000000
-- 002:0740079007b007d007d007d007d007c007b007a00770073007000700071007400750076007800790079007a007a007b007a007600720070007400740209000000000
-- 003:b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100b100505000000000
-- 004:410041004100410041004100410041004100410041004100410041004100410041004100410041004100410041004100410041004100410041004100000000000000
-- 005:b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000b000201000000000
-- 008:6042607360346005608560656005f026f066f066f055f025f004f044f034f023f013f012f012f002f001f001f001f001f000f000f000f00ce00cf00c300000000000
-- 009:463046c046904630467046d096a09660964096b0969096409610e610f600f600f600f600f600f600f600f600f600f600f600f600f600f600f600f600300000000000
-- 010:04700430040004700460040004601480143024304440445044504440340034104440546074609440b430d420e400f400e400e400e400f400f400f400206000000000
-- 011:30403010300030403050302030303060f050f030f060f050f020f010f010f010f010f000f000f000f000f000f000f000f000f000f000f000f000f000105000000000
-- 012:5a605a805aa05a405a005a00fab0fad0fad0fa70fa30fa30fa90fac0fac0fa60fa40fa40fa80fae0fa20fa00fa20fa60fac0fa40fa50fa30fa20fa00502000000000
-- 013:02c002d002c0026002300230028002e002f002d01270124002400260329012900290028002700260028002400240028002a002b002900250f260f250300000000000
-- 014:01700180017001600160019001c001f001f0f140f160f190f1a0f1b0f1b0f1b0f1a0f1a0f180f150f150f140f140f140f140f140f140f140f140f150402000000000
-- 016:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000105000000000
-- </SFX>

-- <PATTERNS>
-- 000:800014100010900016100010900016000000800014000000900016000000900016000000800014000000a00016100010800014100010900016100010900016000000800014000000900016000000900016000000800014000000a00016000000c00016000010a00016a00016a00016a00016000000000000000000000000000000000000000000000000000000000000700016900016a00016c00016900016c00016000000000000000000000000000000000000000000000000000000000000
-- 001:400006600006000000000000000000000000000000000000000000000000000000000000000000000000000000000000700018000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600006500006000000000000500006000000000000700006500006700006000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:60003a60003a60003a60003a40003a40003a40003a40003af00038f00038f00038f0003840003a40003a60003a60003a80003a80003a80003a80003a10001010001090003a90003a80003a80003a60003a60003a40003a40003a60003a10003060003a60003a60003a60003a40003a40003a40003a40003af00038f00038f00038f0003840003a40003af00038f00038d00038d00038d00038d00038100030100030d00038d00038f00038f0003840003a40003a60003a60003a40003a40003a
-- 003:400048400048400048400048400048400048400048400048f00046f00046f00046f00046f00046f00046f00046f00046600048600048600048600048600048600048600048600048400048400048400048400048400048400048400048400048f00046f00046f00046f00046f00046f00046f00046f00046d00046d00046d00046d00046d00046d00046d00046d00046b00046b00046b00046b00046b00046b00046b00046b00046b00046b00046b00046b00046b00046b00046b00046b00046
-- 004:800048800048800048800048800048800048800048800048600048600048600048600048600048600048600048600048900048900048900048900048900048900048900048900048800048800048800048800048800048800048800048800048600048600048600048600048600048600048600048600048400048400048400048400048400048400048400048400048f00046f00046f00046f00046f00046f00046f00046f00046400048400048400048400048400048400048400048400048
-- 005:b00046b00046b00046b00046b00046b00046b00046b00046900046900046900046900046900046900046900046900046d00046d00046d00046d00046d00046d00046d00046d00046b00046b00046b00046b00046b00046b00046b00046b00046900046900046900046900046900046900046900046900046800046800046800046800046800046800046800046800046600046600046600046600046600046600046600046600046800046800046800046800046800046800046800046800046
-- 006:e00052e00052e00052e00052e00052e00052e00052100040e00052e00052e00052e00052e00052e00052e00052000000c00052c00052c00052c00052c00052c00052c00052000000e00052e00052e00052e00052e00052e00052e00052100040e00052e00052e00052e00052e00052e00052e00052100010e00052e00052e00052e00052e00052e00052e00052000000c00052c00052c00052c00052c00052c00052c00052000000a00052a00052a00052a00052a00052a00052a00052a00052
-- 007:700056100050700056100050700056100050700056100050700056100050700056100050700056100050700056100050700056100050700056100050700056100050700056100050700056100050700056100050700056100030700056100050a00056100050a00056100050a00056100050a00056100050a00056100050a00056100050a00056100050a00056100050500056100050500056100050500056100050500056100050500056100050500056100050500056100050500056100050
-- 008:40005a10001040005a10001040005a10001040005a100010f00058100010f00058100010f00058100010f0005810005040005a10005040005a10005040005a10005040005a100050f00058100050f00058100050f00058100050f0005810005040005a10005040005a10005040005a10005040005a100050f00058100050f00058100050f00058100050f0005810005040005a10005040005a10005040005a10005040005a100050f00058100050f00058100050f00058100050f00058100050
-- 009:60005a100030b0005a100030d0005a100030f0005a10003060005a100030b0005a100030d0005a100030f0005a10003060005a100030b0005a100030d0005a100030f0005a10003060005a100030b0005a100030d0005a100030f0005a10003060003c100030b0003c100030d0003c100030f0003c10003060003c100030b0003c100030d0003c100030f0003c10003060003c100030b0003c100030d0003c100030f0003c10003060003c100030b0003c100030d0003c100030f0003c100030
-- 010:b00056100050b00056000050600056000000b00056100050b00056000000600056000000b00056000050600056000000900056900056900056000050400056400056400056400056000050000050000050000000000050000050000050000000b00056100050b00056000050600056000000b00056100050b00056000000600056000000b00056000050600056000000900056900056900056900056000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:600058100050600058000000b00056000000600058100050600058000000b00056000000600058000000b00056000000400058000000d00056d00056000050000000000000000000000050000000100050000000b00056100050b00056000000d00056d00056000050100050000050000000d00056000050f00056000050000050000050600058000000000050000000f00056000000000050000000000050000000000000000000000050000000000000000000000000000000000000000000
-- 012:600052100050600052100050000000000000000000000000000000000000000050000050000050000050000050000050400052100050400052100050000050000050000050000050000050000050000050000050000000000000000050000050600052100050600052100050000050000050000050000000000050000050000000000000000000000000000000000000400052400052100050000000800052800052000000000000000000000000000000000000000000000000000000000000
-- 013:b00054100050b00054100050000000000000000000000000000000000050000050000050000050000000000000000000900054100050900054100050000000000000000000000000000050000050000050000000000050000050000000000000b00054100050b00054100050000000000000000000000000000000000000000000000000000000000000000000000000900054900054100050000050d00054d00054000000000000000000000000000000000000000000000000000000000000
-- 014:c00054100050c00054000000a00054000000c00054000000a00054100050a00054000000c00054100050c00054000000a00054000000c00054000000e00054100050e00054000000c00056100050c00056000000a00056000000c00056000000a00056100050a00056000000c00056100050c00056000000a00056000000c00056000000e00056c00056a00056e00056c00056a00056c00056e00056e00056000000000000000050400058400058000000000000000000000000000000000000
-- 015:600018500018400018f00016600018d00016e00016d00016600018c00016d00016c00016600018b00016c00016b00016600018a00016b00016a00016600018900016a00016900016600018800016900016800016600018700016800016700016600018600016700016600016600018500016600016500016600018400016500016400016600018f00014400016f00014000010000010000010000010000010000000000010000000600016000000000010000000000010000000000010000000
-- 016:e00014000010000010100010d00014100010e00014100010b00014100010e00014100010900014100010e00014100010700014100010e00014100010600014100010e00014100010400014000010000010100010600014000010000010100010e00014000010000010100010d00014100010e00014100010b00014100010e00014100010900014100010e00014100010700014100010e00014100010600014100010e00014100010400014000010000010100010600014000010000000100010
-- 017:000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e00014000000000000100010d00014000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 018:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e00034000000000000100010d00044000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 019:600018500018400018f00016600018d00016e00016d00016600016500016400016f00014600016d00014e00014d00014600018500018400018f00016600018d00016e00016d00016600016500016400016f00014600016d00014e00014d00014600018500018400018f00016600018d00016e00016d00016600016500016400016f00014600016d00014e00014d00014600018500018400018f00016600018d00016e00016d00016600016500016400016f00014600016d00014e00014d00014
-- 020:a00014000010100010000010a00014000010100010000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700014000000100010000000700014000000100010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 021:400016000010100010000010400016000010100010000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b00014000000100010000000b00014000000100010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 022:b00014000010000010000010800014000010a00014000010d00014000010000010000000a00014000000d00014000010f00014000000000010000000d00014000000f00014000000400016000000000010000000f00014000000400016000000700016000000000010000000600016000000000010000000000010000000000010000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 023:b00014000000000000000000800014000000a00014000000d00014000000000000000000a00014000000d00014000000f00014000000000000000000d00014000000f00014000000400016000000000000000000d00014000000b00014000000600014000000000000000000000010000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 024:600016000000000000000000400016000000600016000000b00014000000000000100010b00014100010b00014100010600016000000000000000000400016000000600016000000b00014000000000000100010b00014100010b00014100010600016000000000010000000400016000000600016000010b00014000000000000100010b00014100010b00014100010600016000000000000000000400016000000600016000000b00014000000000000000000000000000000000000000000
-- </PATTERNS>

-- <TRACKS>
-- 000:300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 001:040000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:300000301581301581300500300500301581000000000000000000000000000000000000000000000000000000000000ec0000
-- 003:700000702000702000702900702000702000702900000000000000000000000000000000000000000000000000000000000000
-- 004:a00000ac2000ac2000a03000ac2000ac20000c2000000000000000000000000000000000000000000000000000000000000000
-- 005:d83000d83000d83f00d83f00d83f00d83f00000000000000000000000000000000000000000000000000000000000000000000
-- 006:084314044595044595044410044410044710044810044710044910554495554495554610554610000000000000000000910000
-- </TRACKS>

-- <SCREEN>
-- 000:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 001:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 002:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 003:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 004:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 005:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 006:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 007:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 008:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 009:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 010:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 011:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 012:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 013:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 014:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 015:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 016:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 017:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 018:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 019:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 020:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 021:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 022:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 023:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 024:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 025:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 026:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 027:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 028:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 029:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 030:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 031:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 032:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 033:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 034:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 035:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 036:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 037:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 038:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 039:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 040:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 041:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 042:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 043:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 044:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 045:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 046:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 047:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 048:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 049:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 050:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 051:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 052:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 053:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 054:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 055:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 056:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 057:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 058:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 059:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 060:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 061:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 062:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 063:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 064:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 065:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 066:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 067:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 068:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 069:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 070:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 071:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 072:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 073:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 074:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 075:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 076:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 077:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 078:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 079:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 080:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 081:333333333333333333333333333333333333333333333333333333333333333333333333333333333333e66333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 082:333333333333333333333333333333333333333333333333333333333333333333333333333333333330dd6e33333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 083:33333333333333333333333333333333333333333333333333333333333333333333333333333333333d66d033333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 084:33333333333333333333333333333333333333333333333333333333333333333333333333333333330666d333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 085:333333333333333333333333333333333333333333333333333333333333333333333333333333333366660333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 086:333333333333333333333333333333333333333333333333333333333333333333333333333333333333663333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 087:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 088:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 089:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 090:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 091:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 092:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 093:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 094:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 095:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 096:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 097:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 098:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 099:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 100:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 101:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 102:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 103:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 104:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 105:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 106:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 107:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 108:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 109:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 110:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 111:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 112:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 113:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 114:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 115:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 116:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 117:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 118:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 119:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 120:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 121:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 122:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 123:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 124:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 125:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 126:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 127:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 128:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 129:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 130:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 131:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 132:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 133:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 134:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- 135:333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
-- </SCREEN>

-- <PALETTE>
-- 000:140c1c44243430346d4e4a4e854c30346524d04648757161597dced27d2c8595a16daa2cd2aa996dc2cadad45edeeed6
-- </PALETTE>
