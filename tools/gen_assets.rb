#!/usr/bin/env ruby
# Generates every texture, sprite and sound of the game procedurally (plain
# Ruby + zlib, no image or audio tools needed). Run from the game directory:
#
#   ruby tools/gen_assets.rb
#
# Output: sprites/ground/*.png, sprites/fx/*.png, sprites/hud/*.png, sounds/*.wav
require "zlib"
require "fileutils"

ROOT = File.expand_path("..", __dir__)

# ------------------------------------------------------------------ helpers

class Image
  attr_reader :w, :h

  def initialize(w, h, rgba = [0, 0, 0, 0])
    @w = w
    @h = h
    @px = Array.new(w * h) { rgba.dup }
  end

  def get(x, y)
    @px[(y % @h) * @w + (x % @w)]
  end

  def set(x, y, rgba)
    @px[(y % @h) * @w + (x % @w)] = rgba.map { |c| c.round.clamp(0, 255) }
  end

  # Alpha blends rgb over the pixel with opacity a (0..1), wrapping around.
  def blend(x, y, rgb, a)
    return if a <= 0
    p = get(x, y)
    a = 1.0 if a > 1
    set(x, y, [p[0] + (rgb[0] - p[0]) * a, p[1] + (rgb[1] - p[1]) * a, p[2] + (rgb[2] - p[2]) * a,
               p[3] + (255 - p[3]) * a])
  end

  def each_pixel
    @h.times { |y| @w.times { |x| yield x, y } }
  end

  # PNG rows go top to bottom; we keep y=0 at the top as well.
  def save(path)
    FileUtils.mkdir_p(File.dirname(path))
    raw = +""
    @h.times do |y|
      raw << 0.chr
      @w.times { |x| raw << get(x, y).pack("C4") }
    end
    chunk = lambda do |type, data|
      [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
    end
    png = "\x89PNG\r\n\x1a\n".b
    png << chunk.call("IHDR", [@w, @h, 8, 6, 0, 0, 0].pack("N2C5"))
    png << chunk.call("IDAT", Zlib::Deflate.deflate(raw, 9))
    png << chunk.call("IEND", "")
    File.binwrite(path, png)
    puts "wrote #{path.sub(ROOT + '/', '')}"
  end
end

# Tileable value noise with the given period (in lattice cells).
class Noise
  def initialize(seed, period)
    rng = Random.new(seed)
    @period = period
    @v = Array.new(period * period) { rng.rand }
  end

  def at(x, y)
    xi = x.floor
    yi = y.floor
    fx = x - xi
    fy = y - yi
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    a = lat(xi, yi)
    b = lat(xi + 1, yi)
    c = lat(xi, yi + 1)
    d = lat(xi + 1, yi + 1)
    (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy
  end

  def lat(x, y)
    @v[(y % @period) * @period + (x % @period)]
  end
end

def fbm(noises, x, y, size)
  total = 0.0
  amp = 0.5
  noises.each_with_index do |n, i|
    f = 2**i
    total += n.at(x * 4.0 * f / size, y * 4.0 * f / size) * amp
    amp *= 0.5
  end
  total
end

def mix(a, b, t)
  [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
end

def smoothstep(e0, e1, x)
  t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0)
  t * t * (3 - 2 * t)
end

def noises(seed, octaves = 4)
  octaves.times.map { |i| Noise.new(seed + i, 4 * 2**i) }
end

# Anti-aliased soft disc blended into the image (wraps around edges).
def disc(img, cx, cy, r, rgb, alpha = 1.0, soft = 1.0)
  (cy - r - 2).floor.upto((cy + r + 2).ceil) do |y|
    (cx - r - 2).floor.upto((cx + r + 2).ceil) do |x|
      d = Math.sqrt((x + 0.5 - cx)**2 + (y + 0.5 - cy)**2)
      a = (r - d) / soft + 0.5
      img.blend(x, y, rgb, a.clamp(0.0, 1.0) * alpha)
    end
  end
end

# ------------------------------------------------------------------ ground

S = 128

def field(path, base, stripe, seed, stripe_every: 6, hedge: true, flowers: nil)
  img = Image.new(S, S)
  ns = noises(seed)
  img.each_pixel do |x, y|
    n = fbm(ns, x, y, S)
    c = mix(base, stripe, 0.0)
    c = c.map { |v| v * (0.82 + n * 0.36) }
    if stripe_every && (y % stripe_every) < 2
      c = mix(c, stripe, 0.55)
    end
    img.set(x, y, c + [255])
  end
  if flowers
    rng = Random.new(seed * 7)
    180.times { img.blend(rng.rand(S), rng.rand(S), flowers, 0.8) }
  end
  if hedge
    hedge_col = [52, 70, 38]
    S.times do |i|
      [0, 1, S - 1].each do |e|
        img.blend(i, e, hedge_col, 0.9)
        img.blend(e, i, hedge_col, 0.9)
      end
    end
    rng = Random.new(seed * 3)
    14.times do
      t = rng.rand(S)
      e = rng.rand < 0.5
      e ? disc(img, t, 1, 2.2, [40, 58, 30]) : disc(img, 1, t, 2.2, [40, 58, 30])
    end
  end
  img.save(File.join(ROOT, "sprites/ground/#{path}.png"))
end

def forest
  img = Image.new(S, S)
  ns = noises(11)
  img.each_pixel do |x, y|
    n = fbm(ns, x, y, S)
    img.set(x, y, [34 + n * 20, 52 + n * 26, 28 + n * 12, 255])
  end
  rng = Random.new(5)
  320.times do
    x = rng.rand * S
    y = rng.rand * S
    r = 3 + rng.rand * 4
    shade = 0.8 + rng.rand * 0.4
    disc(img, x + 1, y + 1.5, r, [20, 32, 18], 0.7)
    disc(img, x, y, r, [48 * shade, 78 * shade, 38 * shade])
    disc(img, x - r * 0.3, y - r * 0.3, r * 0.45, [72 * shade, 104 * shade, 52 * shade], 0.6)
  end
  img.save(File.join(ROOT, "sprites/ground/forest.png"))
end

def mud(name, trench: false)
  img = Image.new(S, S)
  ns = noises(21)
  img.each_pixel do |x, y|
    n = fbm(ns, x, y, S)
    img.set(x, y, [92 + n * 40, 78 + n * 32, 58 + n * 22, 255])
  end
  rng = Random.new(trench ? 31 : 23)
  (trench ? 9 : 16).times do
    x = rng.rand * S
    y = rng.rand * S
    r = 3 + rng.rand * 7
    disc(img, x, y, r + 1.5, [138, 120, 92], 0.6)
    disc(img, x, y, r, [58, 48, 36])
    disc(img, x + r * 0.2, y + r * 0.2, r * 0.55, [70, 78, 80], 0.8) if rng.rand < 0.4
  end
  if trench
    # zigzag trench along x (period 32 so the texture tiles), with sandbag rim
    S.times do |x|
      ph = (x % 32) / 32.0
      off = ph < 0.5 ? ph * 4 - 1 : 3 - ph * 4
      cy = S / 2 + off * 9
      (-6..6).each do |dy|
        d = dy.abs
        if d <= 3
          img.blend(x, (cy + dy).round, [30, 24, 18], 1.0)
        elsif d <= 5
          img.blend(x, (cy + dy).round, [150, 138, 110], 0.8)
        end
      end
    end
    # barbed wire rows: dotted dark lines either side
    S.times do |x|
      next unless (x % 3).zero?
      img.blend(x, 22 + (x % 6 < 3 ? 1 : 0), [40, 36, 32], 0.8)
      img.blend(x, S - 22 + (x % 6 < 3 ? 1 : 0), [40, 36, 32], 0.8)
    end
  end
  img.save(File.join(ROOT, "sprites/ground/#{name}.png"))
end

def village
  img = Image.new(S, S)
  ns = noises(41)
  img.each_pixel do |x, y|
    n = fbm(ns, x, y, S)
    img.set(x, y, [104 + n * 30, 128 + n * 30, 72 + n * 20, 255])
  end
  # dirt road crossing
  S.times do |i|
    (-3..3).each do |d|
      img.blend(i, S / 2 + d, [150, 128, 96], d.abs == 3 ? 0.5 : 1.0)
      img.blend(S / 2 + d, i, [150, 128, 96], d.abs == 3 ? 0.5 : 1.0)
    end
  end
  # garden plots
  rng = Random.new(3)
  12.times do
    x = rng.rand(S)
    y = rng.rand(S)
    col = [[120, 96, 64], [96, 124, 60], [150, 140, 80]][rng.rand(3)]
    w = 8 + rng.rand(10)
    h = 8 + rng.rand(10)
    w.times { |a| h.times { |b| img.blend(x + a, y + b, col, 0.7) } }
  end
  img.save(File.join(ROOT, "sprites/ground/village.png"))
end

def water
  img = Image.new(S, S)
  ns = noises(51)
  img.each_pixel do |x, y|
    n = fbm(ns, x * 0.5 + y * 0.1, y * 2.0, S)
    img.set(x, y, [70 + n * 30, 96 + n * 34, 104 + n * 36, 255])
  end
  img.save(File.join(ROOT, "sprites/ground/water.png"))
end

# ------------------------------------------------------------------ fx sprites

def puff
  n = 64
  img = Image.new(n, n)
  img.each_pixel do |x, y|
    d = Math.sqrt((x + 0.5 - n / 2.0)**2 + (y + 0.5 - n / 2.0)**2) / (n / 2.0)
    a = Math.exp(-d * d * 3.2) * (1 - smoothstep(0.85, 1.0, d))
    img.set(x, y, [255, 255, 255, a * 255])
  end
  img.save(File.join(ROOT, "sprites/fx/puff.png"))
end

def cloud(name, seed)
  w = 256
  h = 128
  img = Image.new(w, h)
  rng = Random.new(seed)
  blobs = []
  # flat-bottomed cumulus from overlapping discs (y=0 is the top)
  14.times do |i|
    t = i / 13.0
    cx = 36 + t * (w - 72) + rng.rand(-8.0..8.0)
    r = 18 + Math.sin(t * Math::PI) * 26 + rng.rand * 10
    cy = h - 26 - r * 0.55 - rng.rand * 10
    blobs << [cx, cy, r]
  end
  ns = noises(seed + 90)
  img.each_pixel do |x, y|
    dens = 0.0
    top = 1e9
    blobs.each do |cx, cy, r|
      d = Math.sqrt((x - cx)**2 + (y - cy)**2) / r
      dens = [dens, 1 - d].max
      top = cy - r if d < 1 && cy - r < top
    end
    next if dens <= 0
    n = fbm(ns, x, y, w)
    dens = dens * (0.8 + n * 0.5)
    a = smoothstep(0.0, 0.35, dens) * (1 - smoothstep(h - 26, h - 14, y))
    shade = 1.0 - smoothstep(h * 0.35, h - 20, y) * 0.28
    img.set(x, y, [248 * shade, 246 * shade, 240 * shade, a * 235])
  end
  img.save(File.join(ROOT, "sprites/fx/#{name}.png"))
end

def vignette
  w = 320
  h = 180
  img = Image.new(w, h)
  img.each_pixel do |x, y|
    dx = (x + 0.5 - w / 2.0) / (w / 2.0)
    dy = (y + 0.5 - h / 2.0) / (h / 2.0)
    d = Math.sqrt(dx * dx * 0.8 + dy * dy)
    a = smoothstep(0.55, 1.45, d)
    img.set(x, y, [20, 12, 4, a * 235])
  end
  img.save(File.join(ROOT, "sprites/fx/vignette.png"))
end

# Top view silhouette of a biplane for the ground shadow (nose at the top,
# 128 px = 10.4 m).
def shadow
  n = 128
  k = n / 10.4
  img = Image.new(n, n)
  rect = lambda do |x0, x1, z0, z1|
    # metres (x right, z forward) -> soft edged pixels
    px0 = n / 2.0 + x0 * k
    px1 = n / 2.0 + x1 * k
    py0 = n / 2.0 - z1 * k
    py1 = n / 2.0 - z0 * k
    img.each_pixel do |x, y|
      ax = [(x + 0.5 - px0), (px1 - x - 0.5)].min
      ay = [(y + 0.5 - py0), (py1 - y - 0.5)].min
      a = ([ax, ay].min / 2.0 + 0.5).clamp(0.0, 1.0)
      next if a <= 0
      p = img.get(x, y)
      img.set(x, y, [0, 0, 0, [p[3], a * 120].max])
    end
  end
  rect.call(-4.3, 4.3, -0.3, 1.2)
  rect.call(-0.5, 0.5, -3.9, 2.5)
  rect.call(-1.7, 1.7, -3.95, -3.05)
  img.save(File.join(ROOT, "sprites/fx/shadow.png"))
end

# Sky colour over view ray elevation t = 0..1.3 (world y of a ray with
# forward length 1), bottom row = horizon. Must match GameRenderer::SKY_TOP.
SKY_STOPS = [[0.0, [200, 196, 180]], [0.03, [186, 194, 194]], [0.08, [168, 184, 196]], [0.16, [148, 170, 192]],
             [0.3, [126, 154, 184]], [0.5, [108, 138, 174]], [0.8, [96, 126, 166]], [1.3, [88, 116, 158]]].freeze

def sky_gradient
  img = Image.new(8, 256)
  img.each_pixel do |x, y|
    t = (255 - y) / 255.0 * 1.3
    i = 0
    i += 1 while i < SKY_STOPS.size - 2 && SKY_STOPS[i + 1][0] < t
    a, ca = SKY_STOPS[i]
    b, cb = SKY_STOPS[i + 1]
    img.set(x, y, mix(ca, cb, ((t - a) / (b - a)).clamp(0.0, 1.0)) + [255])
  end
  img.save(File.join(ROOT, "sprites/fx/sky.png"))
end

# Ground haze opacity over u = t / t_near (bottom row u = 0 at the horizon,
# u = 1 where the haze starts, u = HAZE_START at the far end of the ground).
HAZE_START = 0.45

def haze_gradient
  img = Image.new(8, 256)
  img.each_pixel do |x, y|
    u = (255 - y) / 255.0
    d = u > 1e-4 ? HAZE_START / u : 99.0 # distance / far
    a = ((d - HAZE_START) / (1.0 - HAZE_START)).clamp(0.0, 1.0)
    a = a**1.6
    img.set(x, y, [255, 255, 255, a * 255])
  end
  img.save(File.join(ROOT, "sprites/fx/haze.png"))
end

# ------------------------------------------------------------------ hud

# Brass rimmed instrument dial with a 270 degree tick scale (starting at the
# bottom left, clockwise), numbers are drawn by the game.
def gauge
  n = 256
  c = n / 2.0
  img = Image.new(n, n)
  ns = noises(61)
  img.each_pixel do |x, y|
    d = Math.sqrt((x + 0.5 - c)**2 + (y + 0.5 - c)**2)
    next if d > c
    nn = fbm(ns, x, y, n)
    if d > c - 16
      # brass bezel with a highlight at the top left
      ang = Math.atan2(y - c, x - c)
      hl = 0.75 + 0.35 * Math.cos(ang + 2.4)
      rim = 1 - ((d - (c - 8)).abs / 8.0) * 0.35
      col = [196 * hl * rim, 150 * hl * rim, 72 * hl * rim]
      a = (c - d).clamp(0.0, 1.0)
      img.set(x, y, col + [255 * a])
    else
      v = 26 + nn * 14
      img.set(x, y, [v, v * 0.95, v * 0.85, 255])
    end
  end
  # ticks
  51.times do |i|
    t = i / 50.0
    ang = (225 - t * 270) * Math::PI / 180
    major = (i % 5).zero?
    r0 = c - 20
    r1 = major ? c - 40 : c - 30
    steps = 40
    steps.times do |s|
      r = r0 + (r1 - r0) * s / steps.to_f
      x = c + Math.cos(ang) * r
      y = c - Math.sin(ang) * r
      disc(img, x, y, major ? 2.2 : 1.2, [232, 222, 196])
    end
  end
  img.save(File.join(ROOT, "sprites/hud/gauge.png"))
end

# Radar scope: brass bezel, dark face, two range rings and a crosshair.
def radar
  n = 256
  c = n / 2.0
  img = Image.new(n, n)
  ns = noises(71)
  img.each_pixel do |x, y|
    d = Math.sqrt((x + 0.5 - c)**2 + (y + 0.5 - c)**2)
    next if d > c
    if d > c - 12
      ang = Math.atan2(y - c, x - c)
      hl = 0.75 + 0.35 * Math.cos(ang + 2.4)
      rim = 1 - ((d - (c - 6)).abs / 6.0) * 0.35
      img.set(x, y, [196 * hl * rim, 150 * hl * rim, 72 * hl * rim, 255 * (c - d).clamp(0.0, 1.0)])
    else
      v = 22 + fbm(ns, x, y, n) * 12 + (1 - d / c) * 10
      col = [v * 0.9, v * 1.05, v * 0.85]
      [(c - 12) / 3.0, (c - 12) * 2 / 3.0].each do |r|
        a = (1.2 - (d - r).abs).clamp(0.0, 1.0) * 0.5
        col = mix(col, [150, 170, 130], a)
      end
      line = [(x + 0.5 - c).abs, (y + 0.5 - c).abs].min
      col = mix(col, [150, 170, 130], (1.0 - line).clamp(0.0, 1.0) * 0.35)
      img.set(x, y, col + [235])
    end
  end
  img.save(File.join(ROOT, "sprites/hud/radar.png"))
end

def ring
  n = 256
  c = n / 2.0
  img = Image.new(n, n)
  img.each_pixel do |x, y|
    d = Math.sqrt((x + 0.5 - c)**2 + (y + 0.5 - c)**2)
    a = (1.8 - (d - (c - 4)).abs).clamp(0.0, 1.0)
    img.set(x, y, [255, 255, 255, a * 255])
  end
  img.save(File.join(ROOT, "sprites/hud/ring.png"))
end

# ------------------------------------------------------------------ sounds

RATE = 22_050

def write_wav(name, samples)
  path = File.join(ROOT, "sounds/#{name}.wav")
  FileUtils.mkdir_p(File.dirname(path))
  data = samples.map { |s| (s.clamp(-1.0, 1.0) * 32_000).round }.pack("s<*")
  header = ["RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, RATE, RATE * 2, 2, 16,
            "data", data.bytesize].pack("A4VA4A4VvvVVvvA4V")
  File.binwrite(path, header + data)
  puts "wrote sounds/#{name}.wav"
end

def lowpass(samples, k)
  y = 0.0
  samples.map { |s| y += (s - y) * k }
end

def normalize(samples, peak = 0.9)
  m = samples.map(&:abs).max
  m = 1e-9 if m < 1e-9
  samples.map { |s| s / m * peak }
end

# Loopable rotary engine drone: 1 second with whole numbers of every cycle.
def engine
  n = RATE
  rng = Random.new(1)
  noise = lowpass(Array.new(n) { rng.rand * 2 - 1 }, 0.08)
  fire = 45.0 # firing pulses per second
  s = Array.new(n) do |i|
    t = i.to_f / RATE
    ph = (t * fire) % 1.0
    pulse = Math.exp(-ph * 7.0)
    base = Math.sin(2 * Math::PI * 90 * t) * 0.35 + Math.sin(2 * Math::PI * 45 * t) * 0.45 +
           Math.sin(2 * Math::PI * 135 * t) * 0.15
    base * (0.5 + pulse * 0.7) + noise[i] * (0.4 + pulse * 1.4)
  end
  # crossfade the ends so the loop is seamless despite the noise
  fade = 800
  fade.times do |i|
    t = i / fade.to_f
    s[i] = s[i] * t + s[n - fade + i] * (1 - t)
  end
  write_wav("engine", normalize(lowpass(s[0...(n - fade)], 0.35), 0.7))
end

def gun
  n = (RATE * 0.11).to_i
  rng = Random.new(2)
  s = Array.new(n) do |i|
    t = i.to_f / RATE
    env = Math.exp(-t * 55)
    (rng.rand * 2 - 1) * env + Math.sin(2 * Math::PI * 110 * t) * Math.exp(-t * 30) * 0.8
  end
  write_wav("gun", normalize(lowpass(s, 0.45), 0.8))
end

def hit
  n = (RATE * 0.16).to_i
  rng = Random.new(3)
  s = Array.new(n) do |i|
    t = i.to_f / RATE
    (rng.rand * 2 - 1) * Math.exp(-t * 60) * 0.7 +
      Math.sin(2 * Math::PI * 780 * t) * Math.exp(-t * 28) * 0.4 +
      Math.sin(2 * Math::PI * 1230 * t) * Math.exp(-t * 34) * 0.25
  end
  write_wav("hit", normalize(s, 0.7))
end

def explosion
  n = (RATE * 1.8).to_i
  rng = Random.new(4)
  raw = Array.new(n) { rng.rand * 2 - 1 }
  lp = lowpass(lowpass(raw, 0.06), 0.1)
  s = Array.new(n) do |i|
    t = i.to_f / RATE
    env = t < 0.01 ? t / 0.01 : Math.exp(-(t - 0.01) * 2.6)
    crackle = rng.rand < 0.004 * Math.exp(-t * 2) ? (rng.rand - 0.5) * 3 : 0
    lp[i] * env * 3 + crackle + Math.sin(2 * Math::PI * 42 * t) * Math.exp(-t * 4) * 0.5
  end
  write_wav("explosion", normalize(s, 0.95))
end

def jam
  n = (RATE * 0.25).to_i
  rng = Random.new(5)
  s = Array.new(n) do |i|
    t = i.to_f / RATE
    click = (t < 0.02 || (t > 0.12 && t < 0.14)) ? (rng.rand * 2 - 1) : 0
    click * Math.exp(-((t % 0.12) * 90)) + Math.sin(2 * Math::PI * 1800 * t) * Math.exp(-t * 40) * 0.2
  end
  write_wav("jam", normalize(s, 0.6))
end

def wind
  n = RATE * 2
  rng = Random.new(6)
  raw = lowpass(lowpass(Array.new(n) { rng.rand * 2 - 1 }, 0.05), 0.2)
  fade = 2000
  fade.times do |i|
    t = i / fade.to_f
    raw[i] = raw[i] * t + raw[n - fade + i] * (1 - t)
  end
  write_wav("wind", normalize(raw[0...(n - fade)], 0.6))
end

# ------------------------------------------------------------------ main

field("wheat", [196, 168, 92], [168, 138, 70], 1)
field("green", [104, 134, 66], [86, 114, 54], 2)
field("plowed", [118, 92, 64], [92, 70, 48], 3, stripe_every: 4)
field("meadow", [96, 132, 62], [96, 132, 62], 4, stripe_every: nil, flowers: [210, 196, 120])
field("fallow", [150, 142, 90], [132, 124, 78], 5, stripe_every: 9)
forest
mud("mud")
mud("trench", trench: true)
village
water
puff
cloud("cloud1", 100)
cloud("cloud2", 200)
cloud("cloud3", 300)
vignette
shadow
sky_gradient
haze_gradient
gauge
radar
ring
engine
gun
hit
explosion
jam
wind
