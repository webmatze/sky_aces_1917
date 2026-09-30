# Low poly meshes built in code. Local space: +x right, +y up, +z forward,
# units are metres.
module Models
  extend self

  # FlatMesh that remembers a decal level per triangle (markings drawn on top
  # of a surface, see GameRenderer#draw_model).
  class GameMesh < D3D::FlatMesh
    attr_reader :bias

    def initialize
      super
      @bias = []
      @level = 0
    end

    def tri(a, b, c, color, **opts)
      super
      @bias << @level
    end

    def decal(level)
      old = @level
      @level = level
      yield
      @level = old
      self
    end

    # Box from min to max corner with separate top / bottom / side colours.
    def slab(x0, y0, z0, x1, y1, z1, top, bottom = nil, side = nil, **opts)
      bottom ||= top
      side ||= top
      v = []
      [z0, z1].each do |z|
        [y0, y1].each do |y|
          [x0, x1].each { |x| v << vert(x, y, z) }
        end
      end
      inside = [(x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0]
      quad(v[0], v[1], v[3], v[2], side, inside: inside, **opts)   # back
      quad(v[4], v[5], v[7], v[6], side, inside: inside, **opts)   # front
      quad(v[0], v[1], v[5], v[4], bottom, inside: inside, **opts) # bottom
      quad(v[2], v[3], v[7], v[6], top, inside: inside, **opts)    # top
      quad(v[0], v[2], v[6], v[4], side, inside: inside, **opts)   # left
      quad(v[1], v[3], v[7], v[5], side, inside: inside, **opts)   # right
      self
    end

    # Wing from -span..span split into segments (keeps painter's sorting sane).
    def wing(span, y, z0, z1, thick, top, bottom, segments: 6, x_off: 0.0, gap: nil)
      step = span * 2.0 / segments
      segments.times do |i|
        xa = -span + i * step
        xb = xa + step
        next if gap && xb > -gap && xa < gap
        slab(x_off + xa, y - thick / 2, z0, x_off + xb, y + thick / 2, z1, top, bottom, D3D::V.scale(bottom, 0.8))
      end
      self
    end

    # Fuselage from stations [z, half_width, top, bottom] (y offsets), with a
    # colour per segment: [side, top, bottom].
    def fuselage(stations, colors)
      rings = stations.map do |z, hw, ht, hb|
        [vert(-hw, -hb, z), vert(hw, -hb, z), vert(hw, ht, z), vert(-hw, ht, z)]
      end
      (rings.size - 1).times do |i|
        a = rings[i]
        b = rings[i + 1]
        side, top, bot = colors[i] || colors.last
        za = stations[i][0]
        zb = stations[i + 1][0]
        inside = [0, 0, (za + zb) / 2.0]
        quad(a[0], a[1], b[1], b[0], bot, inside: inside)
        quad(a[1], a[2], b[2], b[1], side, inside: inside)
        quad(a[2], a[3], b[3], b[2], top, inside: inside)
        quad(a[3], a[0], b[0], b[3], side, inside: inside)
      end
      f = rings.first
      l = rings.last
      zf = stations.first[0]
      zl = stations.last[0]
      quad(f[0], f[1], f[2], f[3], colors.first[0], inside: [0, 0, zf - 1])
      quad(l[0], l[1], l[2], l[3], colors.last[0], inside: [0, 0, zl + 1])
      self
    end

    # Cylinder along z.
    def cylinder_z(cx, cy, z0, z1, r, sides, color, cap = nil)
      cap ||= color
      a = []
      b = []
      sides.times do |i|
        ang = Math::PI * 2 * i / sides + Math::PI / sides
        x = cx + Math.cos(ang) * r
        y = cy + Math.sin(ang) * r
        a << vert(x, y, z0)
        b << vert(x, y, z1)
      end
      inside = [cx, cy, (z0 + z1) / 2.0]
      sides.times do |i|
        j = (i + 1) % sides
        quad(a[i], a[j], b[j], b[i], color, inside: inside)
      end
      (1...sides - 1).each do |i|
        tri(b[0], b[i], b[i + 1], cap, inside: inside)
        tri(a[0], a[i], a[i + 1], color, inside: inside)
      end
      self
    end

    # Cylinder along x (wheels).
    def cylinder_x(cx, cy, cz, half, r, sides, color, cap)
      a = []
      b = []
      sides.times do |i|
        ang = Math::PI * 2 * i / sides
        y = cy + Math.cos(ang) * r
        z = cz + Math.sin(ang) * r
        a << vert(cx - half, y, z)
        b << vert(cx + half, y, z)
      end
      inside = [cx, cy, cz]
      sides.times do |i|
        j = (i + 1) % sides
        quad(a[i], a[j], b[j], b[i], color, inside: inside)
      end
      (1...sides - 1).each do |i|
        tri(a[0], a[i], a[i + 1], cap, inside: inside)
        tri(b[0], b[i], b[i + 1], cap, inside: inside)
      end
      self
    end

    # Thin rod between two points (struts, mostly vertical).
    def rod(p0, p1, w, color)
      v = []
      [p0, p1].each do |p|
        [[-w, -w], [w, -w], [w, w], [-w, w]].each { |dx, dz| v << vert(p[0] + dx, p[1], p[2] + dz) }
      end
      inside = D3D::V.lerp(p0, p1, 0.5)
      4.times do |i|
        j = (i + 1) % 4
        quad(v[i], v[j], v[j + 4], v[i + 4], color, inside: inside)
      end
      self
    end

    # Flat disc in the xz plane facing up (dir 1) or down (dir -1).
    def disc_y(cx, y, cz, r, sides, color, dir = 1)
      c = vert(cx, y, cz)
      ring = sides.times.map do |i|
        ang = Math::PI * 2 * i / sides
        vert(cx + Math.cos(ang) * r, y, cz + Math.sin(ang) * r)
      end
      sides.times do |i|
        tri(c, ring[i], ring[(i + 1) % sides], color, inside: [cx, y - dir, cz])
      end
      self
    end

    # Flat quad in the xz plane facing up/down (dir), from x0..x1, z0..z1.
    def plate_y(x0, z0, x1, z1, y, color, dir = 1)
      a = vert(x0, y, z0)
      b = vert(x1, y, z0)
      c = vert(x1, y, z1)
      d = vert(x0, y, z1)
      quad(a, b, c, d, color, inside: [(x0 + x1) / 2.0, y - dir, (z0 + z1) / 2.0])
      self
    end

    # Flat quad in the yz plane at x facing +x (dir 1) or -x (dir -1).
    def plate_x(x, y0, z0, y1, z1, color, dir = 1)
      a = vert(x, y0, z0)
      b = vert(x, y1, z0)
      c = vert(x, y1, z1)
      d = vert(x, y0, z1)
      quad(a, b, c, d, color, inside: [x - dir, (y0 + y1) / 2.0, (z0 + z1) / 2.0])
      self
    end

    # Balkenkreuz (iron cross) on a horizontal surface.
    def cross_y(cx, y, cz, s, dir = 1)
      decal(1) { plate_y(cx - s, cz - s, cx + s, cz + s, y, [235, 232, 222], dir) }
      decal(2) do
        plate_y(cx - s * 0.8, cz - s * 0.22, cx + s * 0.8, cz + s * 0.22, y, [22, 20, 20], dir)
        plate_y(cx - s * 0.22, cz - s * 0.8, cx + s * 0.22, cz + s * 0.8, y, [22, 20, 20], dir)
      end
    end

    def cross_x(x, cy, cz, s, dir)
      decal(1) { plate_x(x, cy - s, cz - s, cy + s, cz + s, [235, 232, 222], dir) }
      decal(2) do
        plate_x(x, cy - s * 0.8, cz - s * 0.22, cy + s * 0.8, cz + s * 0.22, [22, 20, 20], dir)
        plate_x(x, cy - s * 0.22, cz - s * 0.8, cy + s * 0.22, cz + s * 0.8, [22, 20, 20], dir)
      end
    end

    def roundel_y(cx, y, cz, r, dir = 1)
      decal(1) { disc_y(cx, y, cz, r, 10, [40, 60, 130], dir) }
      decal(2) { disc_y(cx, y, cz, r * 0.66, 10, [236, 232, 222], dir) }
      decal(3) { disc_y(cx, y, cz, r * 0.33, 8, [170, 40, 36], dir) }
    end
  end

  METAL = [150, 148, 140].freeze
  DARK = [44, 42, 40].freeze
  WOOD = [120, 84, 50].freeze
  TYRE = [36, 34, 32].freeze

  # Colour schemes: body side/top/bottom, wing top/bottom, cowling, nation.
  SCHEMES = {
    allied: { side: [122, 112, 70], top: [104, 96, 58], bottom: [216, 206, 174],
              wing: [112, 104, 62], under: [212, 202, 170], cowl: [176, 172, 160], nation: :allied },
    albatros: { side: [176, 128, 74], top: [150, 106, 60], bottom: [150, 172, 186],
                wing: [96, 104, 64], under: [148, 170, 184], cowl: [70, 70, 66], nation: :central },
    jasta: { side: [200, 176, 60], top: [70, 60, 50], bottom: [150, 170, 184],
             wing: [110, 76, 110], under: [150, 170, 184], cowl: [200, 176, 60], nation: :central },
    baron: { side: [178, 34, 30], top: [160, 28, 26], bottom: [168, 32, 28],
             wing: [176, 34, 30], under: [168, 32, 28], cowl: [178, 34, 30], nation: :central }
  }.freeze

  def biplane(scheme)
    s = SCHEMES[scheme]
    m = GameMesh.new
    body = [s[:side], s[:top], s[:bottom]]
    cowl = [s[:cowl], s[:cowl], s[:cowl]]
    m.fuselage([[2.3, 0.5, 0.5, 0.5], [1.5, 0.52, 0.54, 0.5], [0.2, 0.5, 0.56, 0.5],
                [-1.0, 0.42, 0.46, 0.44], [-2.6, 0.24, 0.3, 0.25], [-3.9, 0.07, 0.14, 0.06]],
               [cowl, body, body, body, body])
    m.cylinder_z(0, 0, 2.3, 2.55, 0.46, 8, DARK, METAL)
    # cockpit, pilot, guns
    m.decal(1) { m.plate_y(-0.34, -0.8, 0.34, 0.1, 0.561, [30, 24, 20]) }
    m.slab(-0.17, 0.56, -0.55, 0.17, 0.92, -0.25, [96, 66, 44], [96, 66, 44], [110, 76, 50])
    m.slab(-0.26, 0.54, 0.3, -0.16, 0.66, 1.8, DARK)
    m.slab(0.16, 0.54, 0.3, 0.26, 0.66, 1.8, DARK)
    # wings
    m.wing(4.3, 1.55, -0.3, 1.2, 0.12, s[:wing], s[:under])
    m.wing(4.0, -0.45, -0.2, 1.1, 0.1, s[:wing], s[:under], gap: 0.45)
    # struts
    [-2.9, 2.9].each do |x|
      m.rod([x, -0.4, 0.95], [x, 1.5, 0.95], 0.05, WOOD)
      m.rod([x, -0.4, 0.0], [x, 1.5, 0.0], 0.05, WOOD)
    end
    [-0.38, 0.38].each do |x|
      m.rod([x, 0.5, 0.95], [x * 1.3, 1.5, 0.95], 0.04, DARK)
      m.rod([x, 0.5, 0.1], [x * 1.3, 1.5, 0.1], 0.04, DARK)
    end
    # tail
    m.wing(1.7, 0.15, -3.95, -3.05, 0.06, s[:wing], s[:under], segments: 2)
    if s[:nation] == :allied
      [[-3.4, -3.15, [40, 60, 130]], [-3.7, -3.4, [236, 232, 222]], [-4.05, -3.7, [170, 40, 36]]].each do |z0, z1, c|
        m.slab(-0.04, 0.15, z0, 0.04, 1.2, z1, c)
      end
    else
      m.slab(-0.04, 0.15, -4.05, 0.04, 1.2, -3.15, [230, 226, 214])
      m.cross_x(0.045, 0.7, -3.6, 0.38, 1)
      m.cross_x(-0.045, 0.7, -3.6, 0.38, -1)
    end
    # landing gear
    [-1, 1].each do |sx|
      m.rod([sx * 0.4, -0.5, 1.0], [sx * 0.8, -1.3, 0.85], 0.04, DARK)
      m.rod([sx * 0.4, -0.5, 0.3], [sx * 0.8, -1.3, 0.85], 0.04, DARK)
      m.cylinder_x(sx * 0.86, -1.35, 0.85, 0.06, 0.36, 8, TYRE, [170, 166, 150])
    end
    markings(m, s, 1.55 + 0.061, -0.45 - 0.051, 3.2, 0.45, 0.6)
    m
  end

  # Fokker Dr.I style triplane.
  def triplane(scheme)
    s = SCHEMES[scheme]
    m = GameMesh.new
    body = [s[:side], s[:top], s[:bottom]]
    cowl = [s[:cowl], s[:cowl], s[:cowl]]
    m.fuselage([[2.0, 0.5, 0.5, 0.5], [1.4, 0.52, 0.54, 0.5], [0.1, 0.48, 0.56, 0.5],
                [-1.2, 0.36, 0.42, 0.4], [-3.4, 0.06, 0.14, 0.06]],
               [cowl, body, body, body])
    m.cylinder_z(0, 0, 2.0, 2.3, 0.47, 8, DARK, METAL)
    m.slab(-0.17, 0.56, -0.6, 0.17, 0.92, -0.3, [96, 66, 44], [96, 66, 44], [110, 76, 50])
    m.slab(-0.26, 0.54, 0.2, -0.16, 0.66, 1.6, DARK)
    m.slab(0.16, 0.54, 0.2, 0.26, 0.66, 1.6, DARK)
    m.wing(3.6, 1.45, -0.1, 0.95, 0.12, s[:wing], s[:under])
    m.wing(3.4, 0.52, -0.05, 1.0, 0.1, s[:wing], s[:under], gap: 0.5)
    m.wing(3.2, -0.45, 0.0, 1.05, 0.1, s[:wing], s[:under], gap: 0.45)
    [-2.4, 2.4].each { |x| m.rod([x, -0.45, 0.45], [x, 1.45, 0.45], 0.06, WOOD) }
    m.wing(1.4, 0.12, -3.5, -2.8, 0.06, s[:wing], s[:under], segments: 2)
    m.slab(-0.04, 0.12, -3.6, 0.04, 1.0, -2.95, [232, 228, 216])
    m.cross_x(0.045, 0.56, -3.28, 0.3, 1)
    m.cross_x(-0.045, 0.56, -3.28, 0.3, -1)
    [-1, 1].each do |sx|
      m.rod([sx * 0.4, -0.5, 0.9], [sx * 0.75, -1.2, 0.8], 0.04, DARK)
      m.cylinder_x(sx * 0.8, -1.25, 0.8, 0.06, 0.34, 8, TYRE, [170, 166, 150])
    end
    markings(m, s, 1.45 + 0.061, -0.45 - 0.051, 2.6, 0.45, 0.5)
    m
  end

  def markings(m, s, top_y, bottom_y, x, z, r)
    [-x, x].each do |mx|
      if s[:nation] == :allied
        m.roundel_y(mx, top_y, z, r, 1)
        m.roundel_y(mx, bottom_y, z, r, -1)
      else
        m.cross_y(mx, top_y, z, r * 0.9, 1)
        m.cross_y(mx, bottom_y, z, r * 0.9, -1)
      end
    end
  end

  # Cheap version for distant planes.
  def plane_lod(scheme, tri = false)
    s = SCHEMES[scheme]
    m = GameMesh.new
    m.slab(-0.45, -0.45, -3.8, 0.45, 0.5, 2.4, s[:side], s[:bottom], s[:side])
    if tri
      m.slab(-3.6, 1.4, -0.1, 3.6, 1.5, 0.95, s[:wing], s[:under], s[:under])
      m.slab(-3.4, 0.47, -0.05, 3.4, 0.57, 1.0, s[:wing], s[:under], s[:under])
      m.slab(-3.2, -0.5, 0.0, 3.2, -0.4, 1.05, s[:wing], s[:under], s[:under])
    else
      m.slab(-4.3, 1.49, -0.3, 4.3, 1.61, 1.2, s[:wing], s[:under], s[:under])
      m.slab(-4.0, -0.5, -0.2, 4.0, -0.4, 1.1, s[:wing], s[:under], s[:under])
    end
    m.slab(-1.7, 0.12, -3.95, 1.7, 0.18, -3.05, s[:wing], s[:under], s[:under])
    m.slab(-0.05, 0.15, -4.0, 0.05, 1.2, -3.15, s[:nation] == :allied ? [236, 232, 222] : [230, 226, 214])
    m
  end

  def propeller
    m = GameMesh.new
    col = [92, 62, 38]
    a = m.vert(-0.09, 0.0, 0)
    b = m.vert(0.09, 0.0, 0)
    c = m.vert(0.07, 1.3, 0)
    d = m.vert(-0.07, 1.3, 0)
    m.tri(a, b, c, col, inside: [0, 0, -1], double_sided: true)
    m.tri(a, c, d, col, inside: [0, 0, -1], double_sided: true)
    e = m.vert(0.07, -1.3, 0)
    f = m.vert(-0.07, -1.3, 0)
    m.tri(a, b, e, col, inside: [0, 0, -1], double_sided: true)
    m.tri(a, e, f, col, inside: [0, 0, -1], double_sided: true)
    m.cylinder_z(0, 0, -0.05, 0.22, 0.14, 6, METAL)
    m
  end

  # Caquot observation balloon, nose towards +z.
  def balloon
    m = GameMesh.new
    col = [196, 180, 136]
    len = 13.0
    rad = 4.4
    sides = 8
    stations = [-1.0, -0.8, -0.45, 0.0, 0.45, 0.8, 1.0]
    rings = stations.map do |t|
      z = t * len
      r = rad * Math.sqrt([1 - t * t, 0.0].max)
      r = 0.2 if r < 0.2
      sides.times.map do |i|
        ang = Math::PI * 2 * i / sides
        m.vert(Math.cos(ang) * r, Math.sin(ang) * r, z)
      end
    end
    (rings.size - 1).times do |k|
      a = rings[k]
      b = rings[k + 1]
      inside = [0, 0, (stations[k] + stations[k + 1]) * len / 2]
      sides.times do |i|
        j = (i + 1) % sides
        shade = i < sides / 2 ? col : D3D::V.scale(col, 0.86)
        m.quad(a[i], a[j], b[j], b[i], shade, inside: inside)
      end
    end
    # three tail lobes
    m.slab(-0.3, 1.5, -13.5, 0.3, 5.2, -8.0, [180, 164, 124])
    m.slab(-5.0, -2.0, -13.5, -1.6, -1.4, -8.0, [180, 164, 124])
    m.slab(1.6, -2.0, -13.5, 5.0, -1.4, -8.0, [180, 164, 124])
    # basket
    m.slab(-0.6, -8.2, 0.4, 0.6, -7.2, 1.6, [110, 86, 52])
    m.rod([0, -7.2, 1.0], [0, -3.8, 1.0], 0.03, DARK)
    m
  end

  # ------------------------------------------------------------ ground

  def house(wall, roof)
    m = GameMesh.new
    m.slab(-3, 0, -4.5, 3, 3.8, 4.5, wall)
    a = m.vert(-3.3, 3.8, -4.8)
    b = m.vert(3.3, 3.8, -4.8)
    c = m.vert(3.3, 3.8, 4.8)
    d = m.vert(-3.3, 3.8, 4.8)
    e = m.vert(0, 6.6, -4.8)
    f = m.vert(0, 6.6, 4.8)
    inside = [0, 4.6, 0]
    m.quad(a, e, f, d, roof, inside: inside)
    m.quad(b, e, f, c, D3D::V.scale(roof, 0.85), inside: inside)
    m.tri(a, b, e, wall, inside: inside)
    m.tri(d, c, f, wall, inside: inside)
    m
  end

  def church
    m = house([196, 188, 170], [96, 84, 76])
    m.slab(-1.6, 0, 4.5, 1.6, 12, 7.7, [190, 182, 164])
    m.bipyramid(4, 2.4, 7.0, 0.01, [[70, 72, 76]], center: [0, 12, 6.1], axis: :y)
    m
  end

  def ruin
    m = GameMesh.new
    wall = [150, 140, 124]
    m.slab(-3, 0, -4, -2.5, 3.2, 4, wall)
    m.slab(-3, 0, 3.5, 1.5, 2.2, 4, wall)
    m.slab(2.5, 0, -4, 3, 1.4, 0, wall)
    m
  end

  def poplar
    m = GameMesh.new
    m.slab(-0.2, 0, -0.2, 0.2, 2.0, 0.2, [80, 62, 44])
    m.bipyramid(5, 1.5, 9.0, 1.0, [[58, 88, 44], [48, 76, 38]], center: [0, 3.0, 0], axis: :y)
    m
  end

  def tree
    m = GameMesh.new
    m.slab(-0.3, 0, -0.3, 0.3, 2.4, 0.3, [84, 64, 44])
    m.bipyramid(6, 3.4, 3.4, 2.2, [[70, 98, 50], [56, 84, 42]], center: [0, 4.2, 0], axis: :y)
    m
  end

  def stump
    m = GameMesh.new
    m.slab(-0.25, 0, -0.25, 0.25, 4.5, 0.25, [60, 52, 44])
    m.slab(-0.1, 3.0, -0.1, 1.4, 3.2, 0.1, [60, 52, 44])
    m
  end

  def debris(color)
    m = GameMesh.new
    m.slab(-0.6, -0.08, -0.4, 0.6, 0.08, 0.4, color)
    m
  end
end
