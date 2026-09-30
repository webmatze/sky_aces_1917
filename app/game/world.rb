# The endless, procedurally generated countryside of the Western Front:
# patchwork fields, forests, villages, a winding river and the trench line
# through no man's land (allied side z < front, enemy side z > front).
class World
  TILE = 100.0
  # The ground pass renders a copy of the world shrunk by `scale`: projection
  # is unchanged, but SceneRenderer#draw_face's distance based subdivision
  # (made for 10 m mine cells) then kicks in at `scale` times the distance,
  # which hides the affine texture warping of the big ground tiles.
  # Detail per render path: [scale, far] with / without the D3D Pro C extension.
  DETAIL_NATIVE = [14.0, 2400.0].freeze
  DETAIL_RUBY = [8.0, 1800.0].freeze
  OBJECT_DIST = 750.0
  NEAR_OBJECT_DIST = 380.0

  GROUND_COLOR = [128, 126, 84].freeze

  # A ground quad in the shape SceneRenderer#draw_face expects, plus its
  # face data packed once for the D3D Pro C extension.
  class Tile
    attr_reader :normal, :c0, :eu, :ev, :center, :material, :shade, :packed

    def initialize(c0, eu, ev, center, material, shade)
      @normal = [0.0, 1.0, 0.0]
      @c0 = c0
      @eu = eu
      @ev = ev
      @center = center
      @material = material
      @shade = shade
      @packed = @normal + c0 + eu + ev + center + shade + [material]
    end
  end

  # Draws ground tiles with the optional D3D Pro C extension when it is loaded (its
  # cell-grid face loop mirrors draw_face exactly), else in Ruby. Each tile
  # is passed as a one-face "cell"; its packed data replaces the renderer's
  # object_id keyed packing cache, which is meant for long-lived cell lists.
  class GroundRenderer < D3D::SceneRenderer
    def draw_tiles(tiles)
      if D3D::Native.enabled?
        @last_visible = (0...tiles.size).to_a
        draw_grid_native(tiles)
      else
        tiles.each { |t| draw_face(t) }
      end
      self
    end

    def native_cell_faces(tile)
      tile.packed
    end
  end

  MATERIALS = %i[wheat green plowed meadow fallow forest mud trench village water].freeze

  attr_reader :ground_renderer

  attr_reader :far

  def initialize(fov)
    @scale, @far = D3D::Native.enabled? ? DETAIL_NATIVE : DETAIL_RUBY
    mats = {}
    MATERIALS.each { |m| mats[m] = { path: "sprites/ground/#{m}.png", size: 128 } }
    mats[:shadow] = { path: 'sprites/fx/shadow.png', size: 128 }
    @ground_renderer = GroundRenderer.new(
      fov: fov, near: 0.5 / @scale, fog: 1e9, view_distance: @far / @scale,
      headlight: 0.0, ambient_scale: 1.0, materials: mats
    )
    @tiles = {}
    @objects = {}
    @meshes = {
      house_red: Models.house([204, 194, 170], [150, 70, 50]),
      house_gray: Models.house([186, 180, 166], [92, 88, 90]),
      church: Models.church,
      ruin: Models.ruin,
      poplar: Models.poplar,
      tree: Models.tree,
      stump: Models.stump
    }
    @scaled_pose = D3D::Pose.new
    build_clouds
  end

  # ------------------------------------------------------------ geography

  def front_z(x)
    260.0 * Math.sin(x / 1100.0) + 90.0 * Math.sin(x / 380.0 + 1.3)
  end

  def river_x(z)
    1400.0 + 500.0 * Math.sin(z / 1600.0)
  end

  def enemy_side?(pos)
    pos[2] > front_z(pos[0]) + 150
  end

  # Deterministic hash of integer coordinates -> 0...1 (fits mruby's 64-bit ints).
  def rnd(i, j, s = 0)
    h = (i * 374_761_393 + j * 668_265_263 + s * 2_147_483_647) & 0xffffffff
    h = ((h ^ (h >> 13)) * 1_274_126_177) & 0xffffffff
    h ^= (h >> 16)
    (h & 0xffff) / 65_536.0
  end

  # Smooth value noise over tiles (cell of 5 tiles).
  def lowfreq(i, j, s)
    x = i / 5.0
    y = j / 5.0
    xi = x.floor
    yi = y.floor
    fx = x - xi
    fy = y - yi
    a = rnd(xi, yi, s)
    b = rnd(xi + 1, yi, s)
    c = rnd(xi, yi + 1, s)
    d = rnd(xi + 1, yi + 1, s)
    (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy
  end

  def tile_type(i, j)
    cx = (i + 0.5) * TILE
    cz = (j + 0.5) * TILE
    df = (cz - front_z(cx)).abs
    return :trench if df < 50
    return :mud if df < 300 || (df < 420 && rnd(i, j, 7) < 0.5)
    return :water if (cx - river_x(cz)).abs < 45
    return :forest if lowfreq(i, j, 3) > 0.66
    r = rnd(i, j, 1)
    return :village if r < 0.035
    %i[wheat green plowed meadow fallow green wheat meadow][(rnd(i, j, 2) * 8).to_i]
  end

  def tile(i, j)
    key = (i + 32_768) * 65_536 + (j + 32_768)
    t = @tiles[key]
    return t if t

    @tiles.clear if @tiles.size > 12_000
    type = tile_type(i, j)
    s = TILE / @scale
    x0 = i * s
    z0 = j * s
    v = 0.9 + rnd(i, j, 4) * 0.18
    shade = type == :water ? [1.0, 1.0, 1.0] : [v, v * (0.97 + rnd(i, j, 5) * 0.06), v * 0.96]
    if type == :trench || rnd(i, j, 6) < 0.5
      eu = [s, 0.0, 0.0]
      ev = [0.0, 0.0, s]
    else
      eu = [0.0, 0.0, s]
      ev = [s, 0.0, 0.0]
    end
    @tiles[key] = Tile.new([x0, 0.0, z0], eu, ev, [x0 + s / 2, 0.0, z0 + s / 2], type, shade)
  end

  # Static ground objects of a tile: [mesh, [x, y, z], yaw, scale].
  def objects(i, j)
    key = (i + 32_768) * 65_536 + (j + 32_768)
    o = @objects[key]
    return o if o

    @objects.clear if @objects.size > 6000
    list = []
    type = tile_type(i, j)
    x0 = i * TILE
    z0 = j * TILE
    c = TILE / 2
    add = ->(mesh, x, z, yaw = 0.0, s = 1.0) { list << [@meshes[mesh], [x0 + x, 0.0, z0 + z], yaw, s] }
    case type
    when :village
      n = 4 + (rnd(i, j, 10) * 5).to_i
      n.times do |k|
        side = rnd(i, j, 20 + k) < 0.5 ? -1 : 1
        along = 8 + rnd(i, j, 30 + k) * 38
        along = -along if rnd(i, j, 40 + k) < 0.5
        kind = rnd(i, j, 50 + k) < 0.6 ? :house_red : :house_gray
        if k.even?
          add.call(kind, c + along, c + side * 10, Math::PI / 2)
        else
          add.call(kind, c + side * 10, c + along, 0.0)
        end
      end
      add.call(:church, c + 22, c + 24, 0.0) if rnd(i, j, 11) < 0.5
    when :mud
      add.call(:ruin, 20 + rnd(i, j, 12) * 60, 20 + rnd(i, j, 13) * 60, rnd(i, j, 14) * 3) if rnd(i, j, 15) < 0.12
      2.times do |k|
        add.call(:stump, rnd(i, j, 16 + k) * TILE, rnd(i, j, 18 + k) * TILE, rnd(i, j, 60 + k) * 6) if rnd(i, j, 70 + k) < 0.35
      end
    when :forest
      3.times do |k|
        add.call(:tree, rnd(i, j, 80 + k) * TILE, rnd(i, j, 90 + k) * TILE, 0.0, 0.9 + rnd(i, j, 100 + k) * 0.5)
      end
    when :trench, :water
      nil
    else
      r = rnd(i, j, 110)
      if r < 0.22
        # row of poplars along an edge
        horizontal = rnd(i, j, 111) < 0.5
        5.times do |k|
          t = 10 + k * 20
          horizontal ? add.call(:poplar, t, 1, 0.0) : add.call(:poplar, 1, t, 0.0)
        end
      elsif r < 0.45
        add.call(:tree, 15 + rnd(i, j, 112) * 70, 15 + rnd(i, j, 113) * 70, 0.0, 0.8 + rnd(i, j, 114) * 0.6)
      end
    end
    @objects[key] = list
  end

  # ------------------------------------------------------------ drawing

  # Draws the ground tiles (and the player's shadow) with the scaled pass.
  def draw_ground(out, pose, shadow = nil)
    gr = @ground_renderer
    cam = pose.position
    sp = @scaled_pose
    sp.position = [cam[0] / @scale, cam[1] / @scale, cam[2] / @scale]
    sp.right = pose.right
    sp.up = pose.up
    sp.fwd = pose.fwd
    gr.begin_frame(sp)
    ci = (cam[0] / TILE).floor
    cj = (cam[2] / TILE).floor
    rad = (@far / TILE).ceil
    fx, fy, fz = pose.fwd
    alt = cam[1]
    lim = (@far + TILE) * (@far + TILE)
    back = -TILE * 0.75
    # Horizontal view cone (wide enough for any roll) to skip tiles far off
    # to the side; off when looking steeply up or down.
    hl = Math.sqrt(fx * fx + fz * fz)
    cone = hl > 0.6
    if cone
      hx = fx / hl
      hz = fz / hl
      tan_c = 1.25
      margin = TILE * 1.1 + alt * (1.0 - hl) * 2.0
    end
    tiles = @visible_tiles ||= []
    tiles.clear
    (-rad..rad).each do |di|
      i = ci + di
      dx = (i + 0.5) * TILE - cam[0]
      (-rad..rad).each do |dj|
        dz = (cj + dj + 0.5) * TILE - cam[2]
        next if dx * dx + dz * dz > lim
        next if dx * fx - alt * fy + dz * fz < back
        if cone
          along = dx * hx + dz * hz
          side = dx * hz - dz * hx
          side = -side if side < 0
          next if side > along * tan_c + margin
        end
        tiles << tile(i, cj + dj)
      end
    end
    gr.draw_tiles(tiles)
    @ground_tris = gr.triangle_count
    out << gr.sorted_primitives
    return unless shadow

    gr.begin_frame(sp)
    gr.draw_face(shadow)
    out << gr.sorted_primitives
  end

  def ground_triangles
    @ground_tris || 0
  end

  # Shadow quad of a plane (world units) under pos, oriented along fwd.
  def shadow_face(pos, fwd)
    h = Math.sqrt(fwd[0] * fwd[0] + fwd[2] * fwd[2])
    return nil if h < 1e-3
    s = 1.0 / @scale
    f = [fwd[0] / h, 0.0, fwd[2] / h]
    r = [f[2], 0.0, -f[0]]
    half = 5.2
    c0 = [(pos[0] - r[0] * half - f[0] * half) * s, 0.02, (pos[2] - r[2] * half - f[2] * half) * s]
    eu = [r[0] * half * 2 * s, 0.0, r[2] * half * 2 * s]
    ev = [f[0] * half * 2 * s, 0.0, f[2] * half * 2 * s]
    Tile.new(c0, eu, ev, [pos[0] * s, 0.0, pos[2] * s], :shadow, [0.0, 0.0, 0.0])
  end

  def draw_objects(renderer, pose)
    cam = pose.position
    ci = (cam[0] / TILE).floor
    cj = (cam[2] / TILE).floor
    rad = (OBJECT_DIST / TILE).ceil
    lim = OBJECT_DIST * OBJECT_DIST
    fx, fy, fz = pose.fwd
    alt = cam[1]
    # from high up only the bigger objects are worth drawing
    small_lim = NEAR_OBJECT_DIST * NEAR_OBJECT_DIST
    (-rad..rad).each do |di|
      i = ci + di
      dx = (i + 0.5) * TILE - cam[0]
      (-rad..rad).each do |dj|
        j = cj + dj
        dz = (j + 0.5) * TILE - cam[2]
        d2 = dx * dx + dz * dz + alt * alt
        next if d2 > lim
        next if dx * fx - alt * fy + dz * fz < -TILE
        objects(i, j).each do |mesh, pos, yaw, scale|
          next if d2 > small_lim && mesh.radius * scale < 6
          c = Math.cos(yaw)
          s = Math.sin(yaw)
          renderer.draw_model(mesh, pos, [c, 0.0, -s], [0.0, 1.0, 0.0], [s, 0.0, c], scale)
        end
      end
    end
  end

  # ------------------------------------------------------------ clouds

  CLOUD_AREA = 7000.0

  def build_clouds
    rng = D3D::Lcg.new(1917)
    @clouds = 42.times.map do
      w = 170 + rng.next_f * 220
      { base: [rng.next_f * CLOUD_AREA, 330 + rng.next_f * 380, rng.next_f * CLOUD_AREA],
        w: w, path: "sprites/fx/cloud#{rng.int(1, 3)}.png" }
    end
  end

  # Draws the clouds wrapped around the camera; returns how deep the camera
  # is inside one (0..1) for a white-out overlay.
  def draw_clouds(renderer, cam)
    inside = 0.0
    half = CLOUD_AREA / 2
    haze = renderer.haze
    @clouds.each do |c|
      b = c[:base]
      x = cam[0] + ((b[0] - cam[0] + half) % CLOUD_AREA) - half
      z = cam[2] + ((b[2] - cam[2] + half) % CLOUD_AREA) - half
      y = b[1]
      w = c[:w]
      dx = x - cam[0]
      dy = y - cam[1]
      dz = z - cam[2]
      d = Math.sqrt(dx * dx + dy * dy + dz * dz)
      next if d > half
      e = (dx / (w * 0.38))**2 + (dy / (w * 0.16))**2 + (dz / (w * 0.38))**2
      inside = [inside, 1.0 - e].max if e < 1
      f = d / half
      a = (235 * (1 - f * f)).to_i
      h = f * 0.6
      renderer.draw_billboard([x, y, z], w, c[:path],
                              255 * (1 - h) + haze[0] * h, 255 * (1 - h) + haze[1] * h, 252 * (1 - h) + haze[2] * h,
                              a, aspect: 0.5, bias: w * w * 0.05)
    end
    inside
  end
end
