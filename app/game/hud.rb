# 2D overlays: brass instruments, gunsight, target markers, compass tape,
# messages, the cockpit view and the old film look.
class Hud
  CREAM = [238, 226, 196].freeze
  INK = [34, 26, 18].freeze
  WHITE = 'sprites/d3d/white.png'
  GAUGE = 'sprites/hud/gauge.png'
  RING = 'sprites/hud/ring.png'
  GLOW = 'sprites/d3d/glow.png'

  def initialize
    @messages = []
    @scratches = []
    @damage_flash = 0.0
  end

  # ------------------------------------------------------------ messages

  def message(text, time: 2.5, size: 30, color: CREAM)
    @messages << { text: text, time: time, max: time, size: size, color: color }
    @messages.shift if @messages.size > 4
  end

  def clear_messages
    @messages.clear
  end

  def damage_flash!
    @damage_flash = 0.35
  end

  def update(dt)
    @messages.each { |m| m[:time] -= dt }
    @messages.reject! { |m| m[:time] <= 0 }
    @damage_flash -= dt if @damage_flash > 0
  end

  def draw_messages(out)
    y = 560
    @messages.each do |m|
      a = D3D.clamp(m[:time] / 0.4, 0, 1) * 255
      text(out, 640, y, m[:text], m[:size], m[:color], a, center: true)
      y -= m[:size] + 12
    end
  end

  # ------------------------------------------------------------ primitives

  def text(out, x, y, str, size, color = CREAM, a = 255, center: false, right: false)
    ax = center ? 0.5 : (right ? 1.0 : 0.0)
    out << { x: x + 2, y: y - 2, text: str, size_px: size, anchor_x: ax, anchor_y: 0.5,
             r: INK[0], g: INK[1], b: INK[2], a: a * 0.8 }
    out << { x: x, y: y, text: str, size_px: size, anchor_x: ax, anchor_y: 0.5,
             r: color[0], g: color[1], b: color[2], a: a }
  end

  def rect(out, x, y, w, h, col, a = 255)
    out << { x: x, y: y, w: w, h: h, path: :solid, r: col[0], g: col[1], b: col[2], a: a }
  end

  def tri(out, p0, p1, p2, col, a = 255)
    out << { x: p0[0], y: p0[1], x2: p1[0], y2: p1[1], x3: p2[0], y3: p2[1],
             source_x: 0, source_y: 0, source_x2: 8, source_y2: 0, source_x3: 0, source_y3: 8,
             path: WHITE, r: col[0], g: col[1], b: col[2], a: a }
  end

  def poly(out, pts, col, a = 255)
    (1...pts.size - 1).each { |i| tri(out, pts[0], pts[i], pts[i + 1], col, a) }
  end

  # Line of width w between two points (a rotated solid).
  def line(out, x0, y0, x1, y1, w, col, a = 255)
    dx = x1 - x0
    dy = y1 - y0
    len = Math.sqrt(dx * dx + dy * dy)
    return if len < 0.5
    out << { x: x0, y: y0 - w / 2.0, w: len, h: w, path: :solid, r: col[0], g: col[1], b: col[2], a: a,
             angle: Math.atan2(dy, dx) * 180 / Math::PI, angle_anchor_x: 0, angle_anchor_y: 0.5 }
  end

  # ------------------------------------------------------------ instruments

  # value 0..1 over a 270 degree dial; labels: [[t, "text"], ...]
  def gauge(out, cx, cy, size, value, title, labels, red_from: nil)
    out << { x: cx - size / 2, y: cy - size / 2, w: size, h: size, path: GAUGE }
    if red_from
      steps = 8
      steps.times do |i|
        t = red_from + (1 - red_from) * i / steps.to_f
        ang = (225 - t * 270) * Math::PI / 180
        rr = size * 0.37
        out << { x: cx + Math.cos(ang) * rr - 3, y: cy + Math.sin(ang) * rr - 3, w: 6, h: 6, path: :solid,
                 r: 190, g: 40, b: 30, a: 220 }
      end
    end
    labels.each do |t, s|
      ang = (225 - t * 270) * Math::PI / 180
      rr = size * 0.27
      out << { x: cx + Math.cos(ang) * rr, y: cy + Math.sin(ang) * rr, text: s, size_px: (size * 0.11).to_i,
               anchor_x: 0.5, anchor_y: 0.5, r: 232, g: 222, b: 196 }
    end
    out << { x: cx, y: cy - size * 0.2, text: title, size_px: (size * 0.1).to_i, anchor_x: 0.5, anchor_y: 0.5,
             r: 200, g: 170, b: 110 }
    v = D3D.clamp(value, 0, 1.04)
    ang = 225 - v * 270
    out << { x: cx, y: cy - 2, w: size * 0.39, h: 4, path: :solid, r: 240, g: 232, b: 210,
             angle: ang, angle_anchor_x: 0, angle_anchor_y: 0.5 }
    out << { x: cx - 7, y: cy - 7, w: 14, h: 14, path: GLOW, r: 200, g: 150, b: 70 }
  end

  def instruments(out, plane, score_info)
    size = 128
    y = 78
    kmh = plane.speed * 3.6
    gauge(out, 80, y, size, kmh / 300.0, 'km/h', [[0, '0'], [0.2, '60'], [0.4, '120'], [0.6, '180'], [0.8, '240'], [1, '300']],
          red_from: 0.88)
    gauge(out, 216, y, size, plane.position[1] / 1500.0, 'ALT m', [[0, '0'], [0.2, '3'], [0.4, '6'], [0.6, '9'], [0.8, '12'], [1, '15']])
    gauge(out, 1064, y, size, 0.15 + plane.throttle * 0.8, 'RPM', [[0, '0'], [0.25, '5'], [0.5, '10'], [0.75, '15'], [1, '20']])
    gauge(out, 1200, y, size, plane.heat, 'GUN °C', [[0, '0'], [0.5, '50'], [1, '100']], red_from: 0.8)
    out << { x: 216, y: y + size * 0.13, text: 'x100', size_px: 12, anchor_x: 0.5, anchor_y: 0.5, r: 200, g: 170, b: 110 }
    text(out, 1200, y + 76, 'JAMMED!', 20, [230, 80, 60]) if plane.jammed? && (score_info[:tick] / 8).to_i.even?

    # airframe integrity
    x = 290
    w = 170
    rect(out, x, 22, w + 8, 20, [96, 72, 34])
    rect(out, x + 3, 25, w + 2, 14, [30, 24, 18])
    f = D3D.clamp(plane.health / plane.max_health.to_f, 0, 1)
    col = f > 0.5 ? [180, 170, 120] : (f > 0.25 ? [210, 150, 60] : [200, 60, 40])
    rect(out, x + 4, 26, w * f, 12, col)
    text(out, x + 4, 54, 'AIRFRAME', 14, [220, 200, 150])
  end

  def compass(out, pose)
    f = pose.fwd
    heading = (Math.atan2(f[2], -f[0]) * 180 / Math::PI) % 360
    cx = 640
    y = 688
    rect(out, cx - 180, y - 16, 360, 32, [30, 24, 18], 150)
    names = { 0 => 'N', 90 => 'E', 180 => 'S', 270 => 'W', 45 => 'NE', 135 => 'SE', 225 => 'SW', 315 => 'NW' }
    (-7..7).each do |k|
      deg = ((heading / 10).round + k) * 10
      off = deg - heading
      x = cx + off * 2.8
      next if x < cx - 170 || x > cx + 170
      d = deg % 360
      label = names[d]
      if label
        out << { x: x, y: y + 1, text: label, size_px: 16, anchor_x: 0.5, anchor_y: 0.5,
                 r: d == 90 ? 230 : 236, g: d == 90 ? 120 : 226, b: d == 90 ? 90 : 196 }
      elsif (d % 30).zero?
        out << { x: x, y: y + 1, text: (d / 10).to_i.to_s, size_px: 12, anchor_x: 0.5, anchor_y: 0.5, r: 210, g: 200, b: 170 }
      else
        rect(out, x - 1, y - 12, 2, 6, [210, 200, 170])
      end
    end
    tri(out, [cx - 7, y - 24], [cx + 7, y - 24], [cx, y - 14], [220, 90, 60])
  end

  # ------------------------------------------------------------ sights & markers

  def gunsight(out, x, y, size = 60)
    out << { x: x - size / 2, y: y - size / 2, w: size, h: size, path: RING, r: 245, g: 236, b: 210, a: 210 }
    out << { x: x - size * 0.9, y: y - size * 0.9, w: size * 1.8, h: size * 1.8, path: RING, r: 245, g: 236, b: 210, a: 90 }
    rect(out, x - 2, y - 2, 4, 4, [245, 236, 210], 230)
    [[-1, 0], [1, 0], [0, -1], [0, 1]].each do |dx, dy|
      line(out, x + dx * size * 0.2, y + dy * size * 0.2, x + dx * size * 0.42, y + dy * size * 0.42, 2, [245, 236, 210], 200)
    end
  end

  def brackets(out, x, y, s, col, a = 230)
    l = s * 0.35
    [[-1, -1], [1, -1], [1, 1], [-1, 1]].each do |sx, sy|
      cx = x + sx * s
      cy = y + sy * s
      rect(out, sx < 0 ? cx : cx - l, cy - 1, l, 2, col, a)
      rect(out, cx - 1, sy < 0 ? cy : cy - l, 2, l, col, a)
    end
  end

  # Brackets around visible targets, arrows at the screen edge for the rest.
  def markers(out, renderer, targets, cam_pos)
    targets.each do |pos, col, label|
      c = renderer.to_cam(pos[0], pos[1], pos[2])
      d = D3D::V.dist(pos, cam_pos)
      on = false
      if c[2] > 1
        sx = 640 + c[0] * renderer.focal / c[2]
        sy = 360 + c[1] * renderer.focal / c[2]
        on = sx > 20 && sx < 1260 && sy > 20 && sy < 700
      end
      if on
        s = D3D.clamp(9.0 * renderer.focal / d, 14, 70)
        brackets(out, sx, sy, s, col)
        out << { x: sx, y: sy - s - 12, text: "#{label} #{d.round}m", size_px: 13, anchor_x: 0.5, anchor_y: 0.5,
                 r: col[0], g: col[1], b: col[2], a: 220 } if d < 2500
      else
        ang = Math.atan2(c[1], c[0])
        ang = Math.atan2(c[1], c[0] < 0 ? -1 : 1) if c[0].abs < 1e-3 && c[1].abs < 1e-3
        ex = 640 + Math.cos(ang) * 580
        ey = 360 + Math.sin(ang) * 310
        tip = [ex + Math.cos(ang) * 18, ey + Math.sin(ang) * 18]
        l = [ex + Math.cos(ang + 2.4) * 12, ey + Math.sin(ang + 2.4) * 12]
        r = [ex + Math.cos(ang - 2.4) * 12, ey + Math.sin(ang - 2.4) * 12]
        tri(out, tip, l, r, col, 210)
        out << { x: ex - Math.cos(ang) * 16, y: ey - Math.sin(ang) * 16, text: "#{(d / 10).round * 10}", size_px: 12,
                 anchor_x: 0.5, anchor_y: 0.5, r: col[0], g: col[1], b: col[2], a: 200 }
      end
    end
  end

  # Heading-up radar scope around the player. contacts: [[pos, color, size], ...]
  # Targets beyond range sit on the rim as hollow markers; a triangle instead
  # of a dot shows a target well above (pointing up) or below.
  def radar(out, pose, contacts, tick, cx = 918, cy = 84, rad = 72, range = 1500.0)
    out << { x: cx - rad, y: cy - rad, w: rad * 2, h: rad * 2, path: 'sprites/hud/radar.png' }
    face = rad - 8
    # sweep line
    ang = tick * 0.05
    line(out, cx, cy, cx + Math.cos(ang) * face, cy + Math.sin(ang) * face, 2, [150, 190, 130], 90)
    f = pose.fwd
    hl = Math.sqrt(f[0] * f[0] + f[2] * f[2])
    if hl > 1e-3
      fx = f[0] / hl
      fz = f[2] / hl
    else
      # looking straight up or down: use the up vector for the heading
      u = pose.up
      ul = Math.sqrt(u[0] * u[0] + u[2] * u[2]) + 1e-9
      s = f[1] > 0 ? -1 : 1
      fx = u[0] / ul * s
      fz = u[2] / ul * s
    end
    me = pose.position
    k = face / range
    contacts.each do |pos, col, size|
      dx = pos[0] - me[0]
      dz = pos[2] - me[2]
      sx = (dx * fz - dz * fx) * k
      sy = (dx * fx + dz * fz) * k
      l = Math.sqrt(sx * sx + sy * sy)
      outside = l > face - 3
      if outside
        sx *= (face - 3) / l
        sy *= (face - 3) / l
      end
      x = cx + sx
      y = cy + sy
      dh = pos[1] - me[1]
      s = size
      if outside
        rect(out, x - s, y - s, s * 2, 1, col)
        rect(out, x - s, y + s - 1, s * 2, 1, col)
        rect(out, x - s, y - s, 1, s * 2, col)
        rect(out, x + s - 1, y - s, 1, s * 2, col)
      elsif dh > 80
        tri(out, [x - s - 1, y - s], [x + s + 1, y - s], [x, y + s + 1], col)
      elsif dh < -80
        tri(out, [x - s - 1, y + s], [x + s + 1, y + s], [x, y - s - 1], col)
      else
        rect(out, x - s, y - s, s * 2, s * 2, col)
      end
    end
    # the player's own machine
    tri(out, [cx, cy + 7], [cx - 5, cy - 5], [cx + 5, cy - 5], [236, 226, 196])
    out << { x: cx, y: cy + rad + 9, text: "#{(range / 1000).round(1)} km", size_px: 13, anchor_x: 0.5,
             anchor_y: 0.5, r: 200, g: 170, b: 110 }
  end

  def lead_marker(out, renderer, point)
    s = renderer.project(point)
    return unless s
    x = s[0]
    y = s[1]
    col = [250, 200, 120]
    tri(out, [x, y + 7], [x + 7, y], [x, y - 7], col, 200)
    tri(out, [x, y + 7], [x - 7, y], [x, y - 7], col, 200)
  end

  # ------------------------------------------------------------ views

  # Fixed parts of the aircraft seen from the pilot's seat.
  def cockpit(out, tick, firing)
    under = [206, 196, 164]
    wood = [110, 78, 46]
    dark = [38, 36, 34]
    # upper wing underside with ribs and the centre cut-out
    poly(out, [[0, 720], [0, 612], [470, 628], [540, 660], [740, 660], [810, 628], [1280, 612], [1280, 720]], under)
    [60, 170, 280, 390, 890, 1000, 1110, 1220].each { |x| line(out, x, 617, x, 720, 3, [176, 166, 136]) }
    line(out, 0, 612, 470, 628, 4, [150, 140, 112])
    line(out, 810, 628, 1280, 612, 4, [150, 140, 112])
    # interplane struts and bracing wires
    poly(out, [[14, 0], [36, 0], [70, 614], [58, 614]], wood)
    poly(out, [[1244, 0], [1266, 0], [1222, 614], [1210, 614]], wood)
    line(out, 36, 90, 470, 628, 1, [50, 48, 46], 170)
    line(out, 1244, 90, 810, 628, 1, [50, 48, 46], 170)
    # cabane struts
    poly(out, [[440, 110], [450, 110], [536, 660], [528, 660]], dark)
    poly(out, [[830, 110], [840, 110], [752, 660], [744, 660]], dark)
    # cowling hump and twin guns
    poly(out, [[300, 0], [980, 0], [900, 90], [780, 142], [640, 156], [500, 142], [380, 90]], [60, 48, 36])
    poly(out, [[380, 0], [900, 0], [850, 60], [640, 104], [430, 60]], [84, 66, 48])
    [-1, 1].each do |s|
      x0 = 640 + s * 70
      poly(out, [[x0 - 34, 0], [x0 + 34, 0], [x0 + s * -20 + 9, 196], [x0 + s * -20 - 9, 196]], dark)
      8.times do |k|
        yy = 20 + k * 22
        w = 30 - k * 2.8
        xc = x0 + s * -20 * yy / 196.0
        rect(out, xc - w, yy, w * 2, 3, [70, 68, 64])
      end
      if firing
        out << { x: x0 + s * -20 - 22, y: 186, w: 44, h: 44, path: GLOW, r: 255, g: 210, b: 120, blendmode_enum: 2 }
      end
    end
    # Aldis sight tube
    poly(out, [[628, 0], [652, 0], [648, 190], [632, 190]], [30, 30, 30])
  end

  # ------------------------------------------------------------ film look

  def damage_overlay(out)
    return unless @damage_flash > 0
    out << { x: 0, y: 0, w: 1280, h: 720, path: 'sprites/fx/vignette.png', r: 255, g: 30, b: 10,
             a: 255 * @damage_flash / 0.35 }
  end

  def film(out, tick)
    out << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: 188, g: 176, b: 150, a: 58 }
    out << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: 255, g: 234, b: 196, blendmode: 4 }
    out << { x: -40, y: -24, w: 1360, h: 768, path: 'sprites/fx/vignette.png' }
    # grain
    50.times do
      s = rand < 0.9 ? 2 : 3
      c = rand < 0.5 ? 20 : 250
      out << { x: rand * 1280, y: rand * 720, w: s, h: s, path: :solid, r: c, g: c * 0.95, b: c * 0.85, a: 30 + rand * 60 }
    end
    # vertical scratches that live for a few frames
    @scratches << [rand * 1280, 4 + rand * 18, rand < 0.5 ? 30 : 230] if rand < 0.05
    @scratches.each do |s|
      s[0] += (rand - 0.5) * 3
      s[1] -= 1
      out << { x: s[0], y: 0, w: 1, h: 720, path: :solid, r: s[2], g: s[2] * 0.95, b: s[2] * 0.9, a: 70 }
    end
    @scratches.reject! { |s| s[1] <= 0 }
    # dust hair now and then
    if tick % 97 < 5
      x = (tick * 7919) % 1100 + 90
      y = (tick * 104_729) % 540 + 90
      line(out, x, y, x + 18, y + 9, 1, [20, 16, 12], 120)
      line(out, x + 18, y + 9, x + 30, y + 3, 1, [20, 16, 12], 120)
    end
    out << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: 0, g: 0, b: 0, a: rand * 14 }
  end
end
