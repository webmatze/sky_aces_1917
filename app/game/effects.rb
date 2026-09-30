# Billboard particles (smoke, fire, sparks, flak, dust) and tumbling debris.
class Effects
  PUFF = 'sprites/fx/puff.png'
  GLOW = 'sprites/d3d/glow.png'
  MAX = 700

  # particle: [x, y, z, vx, vy, vz, age, life, size0, size1, blend, r, g, b, a, drag, rise]
  def initialize
    @parts = []
    @debris = []
  end

  def clear
    @parts.clear
    @debris.clear
  end

  def count
    @parts.size
  end

  def add(pos, vel, life, s0, s1, blend, r, g, b, a, drag: 0.0, rise: 0.0)
    @parts.shift if @parts.size >= MAX
    @parts << [pos[0], pos[1], pos[2], vel[0], vel[1], vel[2], 0.0, life, s0, s1, blend, r, g, b, a, drag, rise]
  end

  def jitter(v, s)
    [v[0] + (rand - 0.5) * s, v[1] + (rand - 0.5) * s, v[2] + (rand - 0.5) * s]
  end

  # ------------------------------------------------------------ emitters

  def smoke(pos, vel, dark = 60, size = 3.0)
    add(jitter(pos, 0.8), D3D::V.scale(vel, 0.15), 2.4 + rand, size, size * 4.5, 1, dark, dark, dark * 0.95, 170,
        drag: 0.8, rise: 2.0)
  end

  def fire(pos, vel)
    add(jitter(pos, 0.6), D3D::V.scale(vel, 0.4), 0.35 + rand * 0.2, 3.5, 1.2, 2, 255, 150 + rand * 60, 50, 255, drag: 1.5)
  end

  def sparks(pos, n = 5)
    n.times do
      add(pos, D3D::V.scale(D3D::V.random_unit, 18 + rand * 20), 0.15 + rand * 0.2, 1.4, 0.4, 2, 255, 230, 150, 255,
          drag: 2.0)
    end
  end

  def muzzle_smoke(pos, vel)
    add(pos, D3D::V.scale(vel, 0.6), 0.6, 0.6, 2.4, 1, 210, 205, 195, 70, drag: 2.5)
  end

  def dust(pos)
    3.times do
      add(jitter(pos, 2.0), [(rand - 0.5) * 4, 5 + rand * 6, (rand - 0.5) * 4], 1.2 + rand * 0.6, 2.0, 7.0, 1,
          132, 112, 84, 190, drag: 1.5, rise: -4.0)
    end
  end

  def splash(pos)
    3.times do
      add(jitter(pos, 1.5), [(rand - 0.5) * 3, 8 + rand * 8, (rand - 0.5) * 3], 0.9, 1.6, 4.0, 1, 220, 228, 230, 200,
          drag: 1.0, rise: -9.0)
    end
  end

  def flak(pos)
    add(pos, [0, 0, 0], 0.18, 10.0, 16.0, 2, 255, 200, 120, 255)
    6.times do
      add(jitter(pos, 6.0), D3D::V.scale(D3D::V.random_unit, 3.0), 4.5 + rand * 2, 7.0, 20.0, 1, 34, 32, 30, 220,
          drag: 0.6, rise: 0.6)
    end
  end

  def explosion(pos, vel, colors = nil, big: 1.0)
    add(pos, [0, 0, 0], 0.25, 22.0 * big, 34.0 * big, 2, 255, 230, 170, 255)
    16.times do
      v = D3D::V.add(D3D::V.scale(vel, 0.3), D3D::V.scale(D3D::V.random_unit, 10 + rand * 18))
      add(jitter(pos, 3), v, 0.5 + rand * 0.6, 5.0 * big, 2.0, 2, 255, 120 + rand * 80, 40, 255, drag: 1.4)
    end
    20.times do
      v = D3D::V.add(D3D::V.scale(vel, 0.2), D3D::V.scale(D3D::V.random_unit, 5 + rand * 9))
      d = 40 + rand * 40
      add(jitter(pos, 4), v, 2.5 + rand * 2.5, 5.0 * big, 18.0 * big, 1, d, d, d, 200, drag: 0.9, rise: 1.5)
    end
    sparks(pos, 10)
    return unless colors
    7.times do |i|
      debris(pos, D3D::V.add(D3D::V.scale(vel, 0.5), D3D::V.scale(D3D::V.random_unit, 10 + rand * 20)),
             colors[i % colors.size])
    end
  end

  # Burning wreck hitting the ground.
  def crash(pos)
    p = [pos[0], 1.0, pos[2]]
    explosion(p, [0, 0, 0], nil, big: 1.3)
    14.times do
      add(jitter(p, 6), [(rand - 0.5) * 10, 8 + rand * 12, (rand - 0.5) * 10], 1.8 + rand, 5.0, 14.0, 1,
          120, 100, 76, 210, drag: 1.2, rise: -3.0)
    end
    10.times do |i|
      d = 30 + rand * 30
      add(jitter(p, 3), [(rand - 0.5) * 2, 6 + i * 1.5, (rand - 0.5) * 2], 6 + rand * 3, 6.0, 26.0, 1, d, d, d, 190,
          drag: 0.3, rise: 1.0)
    end
  end

  DEBRIS_MESHES = {}

  def debris(pos, vel, color)
    mesh = (DEBRIS_MESHES[color] ||= Models.debris(color))
    pose = D3D::Pose.new(pos, D3D::V.random_unit)
    @debris << [pose, vel.dup, [rand * 8 - 4, rand * 8 - 4, rand * 8 - 4], mesh]
  end

  # ------------------------------------------------------------ update / draw

  def update(dt)
    parts = @parts
    i = 0
    while i < parts.size
      p = parts[i]
      p[6] += dt
      if p[6] >= p[7]
        parts.delete_at(i)
        next
      end
      drag = p[15]
      if drag > 0
        k = 1.0 - drag * dt
        k = 0.0 if k < 0
        p[3] *= k
        p[4] *= k
        p[5] *= k
      end
      p[4] += p[16] * dt
      p[0] += p[3] * dt
      p[1] += p[4] * dt
      p[2] += p[5] * dt
      i += 1
    end

    @debris.reject! do |d|
      pose, vel, spin = d
      vel[1] -= 9.81 * dt
      pos = pose.position
      pos[0] += vel[0] * dt
      pos[1] += vel[1] * dt
      pos[2] += vel[2] * dt
      pose.yaw!(spin[0] * dt).pitch!(spin[1] * dt).roll!(spin[2] * dt).orthonormalize!
      if pos[1] < 0
        dust(pos)
        true
      else
        false
      end
    end
  end

  def draw(renderer)
    @parts.each do |p|
      t = p[6] / p[7]
      size = p[8] + (p[9] - p[8]) * t
      blend = p[10]
      a = p[14] * (1.0 - t)
      a *= t / 0.08 if blend == 1 && t < 0.08
      next if a < 3
      renderer.draw_billboard(p, size, blend == 2 ? GLOW : PUFF, p[11], p[12], p[13], a, blend: blend)
    end
    @debris.each do |pose, _vel, _spin, mesh|
      renderer.draw_model(mesh, pose.position, pose.right, pose.up, pose.fwd)
    end
  end
end

# Tethered enemy observation balloon ("Drachen"): a juicy target that burns.
class Balloon
  RADIUS = 13.0

  attr_reader :position, :state, :health

  def self.mesh
    @mesh ||= Models.balloon
  end

  def initialize(pos)
    @anchor = pos.dup
    @position = pos.dup
    @phase = rand * 6
    @health = 6
    @state = :up
    @burn = 0.0
    @hit_flash = 0.0
    alt = pos[1]
    @cable = Models::GameMesh.new.rod([0, -7.2, 1.0], [0, -alt, 1.0], 0.12, [50, 46, 40])
  end

  def alive?
    @state == :up
  end

  def gone?
    @state == :gone
  end

  # Returns true when the hit set it ablaze.
  def damage!(n)
    return false unless @state == :up
    @health -= n
    @hit_flash = 0.1
    if @health <= 0
      @state = :burning
      return true
    end
    false
  end

  def update(dt, effects)
    @phase += dt
    @hit_flash -= dt if @hit_flash > 0
    case @state
    when :up
      @position[1] = @anchor[1] + Math.sin(@phase * 0.6) * 1.5
    when :burning
      @burn += dt
      @position[1] -= dt * (6 + @burn * 10)
      6.times do
        effects.fire(D3D::V.add(@position, [(rand - 0.5) * 16, (rand - 0.3) * 8, (rand - 0.5) * 22]), [0, 4, 0])
      end
      effects.smoke(D3D::V.add(@position, [(rand - 0.5) * 10, 4, (rand - 0.5) * 10]), [0, 0, 0], 30, 6.0)
      if @burn > 2.4 || @position[1] < 10
        effects.explosion(@position, [0, -5, 0], [[196, 180, 136], [110, 86, 52]], big: 1.6)
        @state = :gone
      end
    end
  end

  def draw(renderer)
    return if @state == :gone
    flash = @hit_flash > 0 ? 0.4 : 0.0
    renderer.draw_model(Balloon.mesh, @position, [0.0, 0.0, -1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0], 1.0, flash)
    return unless @state == :up
    renderer.draw_model(@cable, @position, [0.0, 0.0, -1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0])
  end
end
