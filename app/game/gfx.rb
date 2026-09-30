# Rendering additions on top of D3D::SceneRenderer for an open-air scene:
# sun lit meshes that fade into the horizon haze, alpha blended billboards
# (smoke, clouds) and a 2D sky / horizon drawn from the camera pose.
class GameRenderer < D3D::SceneRenderer
  SUN = D3D::V.norm([0.45, 0.8, -0.35])
  WHITE = 'sprites/d3d/white.png'

  attr_accessor :haze

  def initialize(**opts)
    super(**opts)
    @haze = [200, 196, 180]
  end

  # Screen rotation (degrees) that keeps billboards upright in the world.
  def roll_angle
    Math.atan2(-@ry, @uy) * 180.0 / Math::PI
  end

  # A FlatMesh (Models::GameMesh) lit by the sun, with haze towards the
  # horizon colour. Triangles with a decal level are sorted slightly towards
  # the camera so markings stay on top of the surface they sit on.
  def draw_model(mesh, pos, right, up, fwd, scale = 1.0, flash = 0.0)
    o = to_cam(pos[0], pos[1], pos[2])
    rad = mesh.radius * scale
    oz = o[2]
    return if oz < -rad
    dist = Math.sqrt(o[0] * o[0] + o[1] * o[1] + oz * oz)
    return if dist - rad > @view_distance
    kx = rad * Math.sqrt(1 + @tan_x * @tan_x)
    return if o[0].abs - oz * @tan_x > kx
    ky = rad * Math.sqrt(1 + @tan_y * @tan_y)
    return if o[1].abs - oz * @tan_y > ky
    # tiny on screen: skip
    return if oz > 0 && rad * @focal / oz < 0.8

    rc = dir_to_cam(right[0] * scale, right[1] * scale, right[2] * scale)
    uc = dir_to_cam(up[0] * scale, up[1] * scale, up[2] * scale)
    fc = dir_to_cam(fwd[0] * scale, fwd[1] * scale, fwd[2] * scale)
    r0, r1, r2 = rc
    u0, u1, u2 = uc
    f0, f1, f2 = fc
    ox, oy = o
    verts = mesh.verts
    cam = @model_verts ||= []
    i = 0
    n = verts.size
    while i < n
      p = verts[i]
      x = p[0]
      y = p[1]
      z = p[2]
      cam[i] = [ox + r0 * x + u0 * y + f0 * z,
                oy + r1 * x + u1 * y + f1 * z,
                oz + r2 * x + u2 * y + f2 * z]
      i += 1
    end

    # sun direction in the model's local frame
    sl0 = SUN[0] * right[0] + SUN[1] * right[1] + SUN[2] * right[2]
    sl1 = SUN[0] * up[0] + SUN[1] * up[1] + SUN[2] * up[2]
    sl2 = SUN[0] * fwd[0] + SUN[1] * fwd[1] + SUN[2] * fwd[2]

    h = dist / @view_distance
    h = h > 1 ? 1.0 : h
    h = h * h * 0.9
    hz = @haze
    hr = hz[0] * h
    hg = hz[1] * h
    hb = hz[2] * h
    keep = 1.0 - h
    inv_s = 1.0 / scale
    near = @near
    focal = @focal
    hw = @half_w
    hh = @half_h
    ws = @white_size
    list = @list
    bias = mesh.bias
    tris = mesh.tris
    ti = 0
    tn = tris.size
    while ti < tn
      t = tris[ti]
      a = cam[t.a]
      b = cam[t.b]
      c = cam[t.c]
      ti += 1
      next if a[2] < near || b[2] < near || c[2] < near
      nm = t.normal
      n0 = nm[0]
      n1 = nm[1]
      n2 = nm[2]
      ncx = (r0 * n0 + u0 * n1 + f0 * n2) * inv_s
      ncy = (r1 * n0 + u1 * n1 + f1 * n2) * inv_s
      ncz = (r2 * n0 + u2 * n1 + f2 * n2) * inv_s
      facing = -(a[0] * ncx + a[1] * ncy + a[2] * ncz)
      if facing <= 0
        next unless t.double_sided
        n0 = -n0
        n1 = -n1
        n2 = -n2
      end
      col = t.color
      if t.emissive
        lit = 1.0
      else
        l = n0 * sl0 + n1 * sl1 + n2 * sl2
        lit = l > 0 ? 0.52 + 0.62 * l : 0.52 + 0.12 * l
      end
      lk = lit * keep
      r = col[0] * lk + hr
      g = col[1] * lk + hg
      bb = col[2] * lk + hb
      if flash > 0
        r += (255 - r) * flash
        g += (255 - g) * flash
        bb += (255 - bb) * flash
      end
      mx = (a[0] + b[0] + c[0]) / 3.0
      my = (a[1] + b[1] + c[1]) / 3.0
      mz = (a[2] + b[2] + c[2]) / 3.0
      key = mx * mx + my * my + mz * mz
      lv = bias[ti - 1]
      key -= lv * 1.6 * dist if lv > 0
      ia = focal / a[2]
      ib = focal / b[2]
      ic = focal / c[2]
      @triangle_count += 1
      list << [key, {
        x: hw + a[0] * ia, y: hh + a[1] * ia,
        x2: hw + b[0] * ib, y2: hh + b[1] * ib,
        x3: hw + c[0] * ic, y3: hh + c[1] * ic,
        source_x: 0, source_y: 0, source_x2: ws, source_y2: 0, source_x3: 0, source_y3: ws,
        path: WHITE,
        r: r > 255 ? 255 : r, g: g > 255 ? 255 : g, b: bb > 255 ? 255 : bb
      }]
    end
    self
  end

  # Camera facing sprite of world width w (height w * aspect), alpha blended
  # (blend 1) or additive (blend 2), rotated with the camera roll.
  def draw_billboard(pos, w, path, r, g, b, a, aspect: 1.0, blend: 1, bias: 0.0, min_px: 0.6)
    c = to_cam(pos[0], pos[1], pos[2])
    z = c[2]
    return if z < @near + w * 0.1
    k = @focal / z
    s = w * k
    return if s < min_px
    # fade out sprites the camera is about to fly through
    fade = w * 1.5
    if z < fade
      a *= (z - w * 0.1) / (fade - w * 0.1)
      return if a < 2
    end
    sh = s * aspect
    sx = @half_w + c[0] * k
    sy = @half_h + c[1] * k
    return if sx < -s || sx > @width + s || sy < -s || sy > @height + s
    d2 = c[0] * c[0] + c[1] * c[1] + z * z
    @list << [d2 + bias, {
      x: sx - s * 0.5, y: sy - sh * 0.5, w: s, h: sh, path: path,
      r: r, g: g, b: b, a: a, blendmode_enum: blend, angle: @roll_deg
    }]
    self
  end

  def begin_frame(pose, lights: [], ambient_boost: [0.0, 0.0, 0.0])
    super
    @roll_deg = roll_angle
    self
  end

  # ------------------------------------------------------------ sky & haze

  # Value > 0 above the horizon for a screen point: world y of the view ray
  # through it (not normalised, forward component 1).
  def horizon_coeffs
    [@ry / @focal, @uy / @focal, @fy - (@ry * @half_w + @uy * @half_h) / @focal]
  end

  # Screen rectangle clipped to a*x + b*y + c >= 0.
  def self.clip_halfplane(poly, a, b, c)
    out = []
    n = poly.size
    n.times do |i|
      p = poly[i]
      q = poly[(i + 1) % n]
      dp = a * p[0] + b * p[1] + c
      dq = a * q[0] + b * q[1] + c
      out << p if dp >= 0
      if (dp >= 0) != (dq >= 0)
        t = dp / (dp - dq)
        out << [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t]
      end
    end
    out
  end

  SCREEN = [[0.0, 0.0], [1280.0, 0.0], [1280.0, 720.0], [0.0, 720.0]].freeze

  def self.fill_poly(out, poly, r, g, b, a = 255)
    return if poly.size < 3
    p0 = poly[0]
    (1...poly.size - 1).each do |i|
      p1 = poly[i]
      p2 = poly[i + 1]
      out << { x: p0[0], y: p0[1], x2: p1[0], y2: p1[1], x3: p2[0], y3: p2[1],
               source_x: 0, source_y: 0, source_x2: 8, source_y2: 0, source_x3: 0, source_y3: 8,
               path: WHITE, r: r, g: g, b: b, a: a }
    end
  end

  # Region of the screen where the view ray's world y lies in [lo, hi].
  def band(lo, hi)
    a, b, c = horizon_coeffs
    poly = SCREEN
    poly = GameRenderer.clip_halfplane(poly, a, b, c - lo) if lo
    poly = GameRenderer.clip_halfplane(poly, -a, -b, hi - c) if hi && poly.size >= 3
    poly
  end

  SKY = 'sprites/fx/sky.png'
  HAZE = 'sprites/fx/haze.png'
  SKY_MAX = 1.3            # ray elevation at the top of sky.png
  SKY_TOP = [88, 116, 158].freeze
  HAZE_START = 0.45        # fraction of the ground distance where haze begins (see tools/gen_assets.rb)

  # Fills poly with a vertical gradient texture whose rows run from ray
  # elevation t0 (bottom row) to t1 (top row). The elevation is linear in
  # screen space, so the affine texture mapping of DragonRuby's triangles
  # reproduces the gradient exactly, without banding.
  def gradient_poly(out, poly, path, t0, t1, r = 255, g = 255, b = 255)
    return if poly.size < 3
    a, bb, c = horizon_coeffs
    k = 255.0 / (t1 - t0)
    sy = poly.map do |p|
      v = (a * p[0] + bb * p[1] + c - t0) * k
      v < 0.5 ? 0.5 : (v > 255.5 ? 255.5 : v)
    end
    p0 = poly[0]
    (1...poly.size - 1).each do |i|
      p1 = poly[i]
      p2 = poly[i + 1]
      out << { x: p0[0], y: p0[1], x2: p1[0], y2: p1[1], x3: p2[0], y3: p2[1],
               source_x: 2, source_y: sy[0], source_x2: 6, source_y2: sy[i], source_x3: 4, source_y3: sy[i + 1],
               path: path, r: r, g: g, b: b }
    end
  end

  # Sky gradient and flat ground colour behind everything.
  def draw_sky(out, ground_color)
    top = SKY_TOP
    out << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: top[0], g: top[1], b: top[2] }
    gradient_poly(out, band(0.0, SKY_MAX), SKY, 0.0, SKY_MAX)
    GameRenderer.fill_poly(out, band(nil, 0.0), ground_color[0], ground_color[1], ground_color[2])
  end

  # Haze over the ground towards the horizon, for a camera at altitude alt:
  # ground at distance d appears at ray elevation -alt / d, so it is fully
  # hazy where the drawn ground ends (far).
  def draw_ground_haze(out, alt, far)
    alt = 1.0 if alt < 1.0
    t_near = -alt / (far * HAZE_START)
    hz = @haze
    gradient_poly(out, band(t_near, 0.0), HAZE, 0.0, t_near, hz[0], hz[1], hz[2])
  end
end
