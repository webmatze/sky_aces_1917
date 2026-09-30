# A biplane or triplane with an arcade flight model: the nose points where
# the plane flies, banking turns it, gravity trades height for speed and slow
# planes stall. Player and enemies share this class; they only differ in who
# fills in the controls ({ pitch:, roll:, yaw:, throttle:, fire: }).
class Plane
  RADIUS = 5.5
  G = 9.81
  ROLL_RATE = 2.7
  PITCH_RATE = 1.25
  YAW_RATE = 0.5
  BANK_TURN = 0.75
  THRUST = 15.5
  DRAG = 0.0038
  STALL = 24.0
  MIN_SPEED = 10.0
  MAX_SPEED = 125.0
  CEILING = 1500.0
  BULLET_SPEED = 430.0
  GUN_INTERVAL = 0.075
  LOD_DIST = 260.0

  MESHES = {}

  def self.meshes(kind, scheme)
    MESHES[[kind, scheme]] ||= begin
      tri = kind == :triplane
      { near: tri ? Models.triplane(scheme) : Models.biplane(scheme),
        far: Models.plane_lod(scheme, tri) }
    end
  end

  def self.prop_mesh
    @prop_mesh ||= Models.propeller
  end

  attr_accessor :pose, :speed, :throttle, :health, :max_health, :state, :team, :kind, :scheme,
                :heat, :jam_time, :hit_flash, :ai, :agility, :burning, :smoke_timer, :name,
                :last_hit_by, :fire_timer

  def initialize(pos, fwd, kind: :biplane, scheme: :allied, team: :player, health: 20, agility: 1.0)
    @pose = D3D::Pose.new(pos, fwd)
    @kind = kind
    @scheme = scheme
    @team = team
    @speed = 52.0
    @throttle = 0.8
    @health = health
    @max_health = health
    @agility = agility
    @state = :flying
    @heat = 0.0
    @jam_time = 0.0
    @gun_cd = 0.0
    @gun_side = 1
    @prop_angle = rand * 6.0
    @hit_flash = 0.0
    @spin = 0.0
    @smoke_timer = 0.0
    @fire_timer = 0.0
    @burning = false
    meshes = Plane.meshes(kind, scheme)
    @mesh = meshes[:near]
    @lod = meshes[:far]
    @prop_offset = kind == :triplane ? 2.35 : 2.62
  end

  def position
    @pose.position
  end

  def fwd
    @pose.fwd
  end

  def flying?
    @state == :flying
  end

  def alive?
    @state != :dead
  end

  def damaged?
    @health < @max_health * 0.5
  end

  def velocity
    f = @pose.fwd
    [f[0] * @speed, f[1] * @speed - sink, f[2] * @speed]
  end

  def sink
    @speed < 32 ? (32 - @speed) * 0.55 : 0.0
  end

  def jammed?
    @jam_time > 0
  end

  # ------------------------------------------------------------ physics

  def update(dt, ctl)
    @hit_flash -= dt if @hit_flash > 0
    @prop_angle += (8 + @throttle * 30) * dt
    return update_falling(dt) if @state == :falling
    return if @state == :dead

    @throttle = D3D.clamp(ctl[:throttle] || @throttle, 0.0, 1.0)
    eff = D3D.clamp((@speed - 12) / 36.0, 0.25, 1.0) * @agility
    p = @pose
    p.roll!(D3D.clamp(ctl[:roll] || 0, -1, 1) * ROLL_RATE * eff * dt)
    p.pitch!(D3D.clamp(ctl[:pitch] || 0, -1, 1) * PITCH_RATE * eff * dt)
    p.yaw!(D3D.clamp(ctl[:yaw] || 0, -1, 1) * YAW_RATE * eff * dt)
    # banking turns the plane around the world vertical
    rotate_world_y(-p.right[1] * BANK_TURN * eff * dt)
    # stall: the nose drops towards the ground
    if @speed < STALL
      k = (STALL - @speed) / STALL * 1.6 * dt
      p.pitch!(p.up[1] >= 0 ? -k : k)
    end
    p.orthonormalize!

    density = p.position[1] > CEILING ? D3D.clamp(1.0 - (p.position[1] - CEILING) / 400.0, 0.0, 1.0) : 1.0
    acc = THRUST * @throttle * density - DRAG * @speed * @speed - G * p.fwd[1]
    @speed = D3D.clamp(@speed + acc * dt, MIN_SPEED, MAX_SPEED)
    move(dt)

    @heat -= dt * (jammed? ? 0.18 : 0.26)
    @heat = 0.0 if @heat < 0
    @jam_time -= dt if @jam_time > 0
    @gun_cd -= dt
    @fire_timer -= dt if @fire_timer > 0
  end

  def move(dt)
    v = velocity
    pos = @pose.position
    pos[0] += v[0] * dt
    pos[1] += v[1] * dt
    pos[2] += v[2] * dt
  end

  def rotate_world_y(a)
    return if a == 0
    c = Math.cos(a)
    s = Math.sin(a)
    p = @pose
    p.fwd = rot_y(p.fwd, c, s)
    p.right = rot_y(p.right, c, s)
    p.up = rot_y(p.up, c, s)
  end

  def rot_y(v, c, s)
    [v[0] * c + v[2] * s, v[1], -v[0] * s + v[2] * c]
  end

  # Shot down: spin towards the ground trailing fire and smoke.
  def shoot_down!
    return unless @state == :flying
    @state = :falling
    @burning = true
    @spin = (rand < 0.5 ? -1 : 1) * (1.2 + rand * 2.0)
    @throttle = 0.0
  end

  def update_falling(dt)
    p = @pose
    # nose goes down
    f = D3D::V.norm(D3D::V.lerp(p.fwd, [0.0, -1.0, 0.0], 1.3 * dt))
    p.look!(f, p.up)
    p.roll!(@spin * dt)
    p.orthonormalize!
    @speed = D3D.clamp(@speed + (G * 1.6 - @speed * 0.02) * dt, 20, 115)
    move(dt)
  end

  def crash!
    @state = :dead
  end

  # ------------------------------------------------------------ guns

  # Returns new bullets as [x, y, z, vx, vy, vz, life, team] arrays.
  def fire(dt, trigger, spread = 0.006)
    return nil if @state != :flying || !trigger || jammed? || @gun_cd > 0
    @gun_cd = GUN_INTERVAL
    @gun_side = -@gun_side
    @heat += 0.022
    if @heat >= 1.0
      @heat = 0.75
      @jam_time = 2.2
    end
    @fire_timer = 0.06
    p = @pose
    f = p.fwd
    u = p.up
    r = p.right
    pos = p.position
    side = @gun_side * 0.21
    origin = [pos[0] + f[0] * 2.4 + u[0] * 0.62 + r[0] * side,
              pos[1] + f[1] * 2.4 + u[1] * 0.62 + r[1] * side,
              pos[2] + f[2] * 2.4 + u[2] * 0.62 + r[2] * side]
    d = [f[0] + (rand - 0.5) * spread * 2 + u[0] * 0.004,
         f[1] + (rand - 0.5) * spread * 2 + u[1] * 0.004,
         f[2] + (rand - 0.5) * spread * 2 + u[2] * 0.004]
    d = D3D::V.norm(d)
    v = velocity
    sp = BULLET_SPEED
    [origin[0], origin[1], origin[2],
     v[0] + d[0] * sp, v[1] + d[1] * sp, v[2] + d[2] * sp, 1.4, @team]
  end

  def muzzle_position
    p = @pose
    pos = p.position
    [pos[0] + p.fwd[0] * 3.2 + p.up[0] * 0.62, pos[1] + p.fwd[1] * 3.2 + p.up[1] * 0.62,
     pos[2] + p.fwd[2] * 3.2 + p.up[2] * 0.62]
  end

  # ------------------------------------------------------------ damage

  # Returns true when this hit shot the plane down.
  def damage!(amount, by = nil)
    return false unless @state == :flying
    @health -= amount
    @hit_flash = 0.12
    @last_hit_by = by
    if @health <= 0
      @health = 0
      shoot_down!
      return true
    end
    false
  end

  # ------------------------------------------------------------ drawing

  def draw(renderer, cam_pos)
    return if @state == :dead
    p = @pose
    pos = p.position
    d = D3D::V.dist(pos, cam_pos)
    flash = @hit_flash > 0 ? 0.5 : 0.0
    if d > LOD_DIST
      renderer.draw_model(@lod, pos, p.right, p.up, p.fwd, 1.0, flash)
      return
    end
    renderer.draw_model(@mesh, pos, p.right, p.up, p.fwd, 1.0, flash)
    # spinning propeller
    a = @prop_angle
    c = Math.cos(a)
    s = Math.sin(a)
    r = p.right
    u = p.up
    f = p.fwd
    pr = [r[0] * c + u[0] * s, r[1] * c + u[1] * s, r[2] * c + u[2] * s]
    pu = [u[0] * c - r[0] * s, u[1] * c - r[1] * s, u[2] * c - r[2] * s]
    o = @prop_offset
    hub = [pos[0] + f[0] * o, pos[1] + f[1] * o, pos[2] + f[2] * o]
    renderer.draw_model(Plane.prop_mesh, hub, pr, pu, f)
    if @fire_timer > 0
      renderer.draw_glow(muzzle_position, 1.6, 255, 220, 140)
    end
  end
end
