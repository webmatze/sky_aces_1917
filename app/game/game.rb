# SKY ACES 1917 - game flow: title (with an attract-mode dogfight), waves of
# enemy scouts and observation balloons, lives, score, camera views, audio
# and the render passes (sky, ground, haze, objects, overlays).
class Game
  DT = 1.0 / 60
  FOV = 78.0
  V = D3D::V
  HISCORE_FILE = 'data/hiscore.txt'

  ENEMY = [226, 92, 70].freeze
  BALLOON = [232, 170, 70].freeze

  attr_reader :state, :player, :enemies, :renderer

  def initialize(args)
    D3D::Native.load
    @world = World.new(FOV)
    @renderer = GameRenderer.new(fov: FOV, near: 0.5, fog: 1e9, view_distance: @world.far, headlight: 0.0)
    @effects = Effects.new
    @hud = Hud.new
    @cam = D3D::Pose.new([0.0, 400.0, -900.0], [0.0, 0.0, 1.0])
    @view = :chase
    @film = true
    @invert = false
    @muted = false
    @tick = 0
    @hiscore = (args.gtk.read_file(HISCORE_FILE) || '0').to_i
    @stick = { pitch: 0.0, roll: 0.0, yaw: 0.0 }
    start_title
  end

  # ------------------------------------------------------------ states

  def start_title
    @state = :title
    @bullets = []
    @effects.clear
    @hud.clear_messages
    @balloons = []
    x = 0.0
    z = @world.front_z(x) - 400
    @player = Plane.new([x, 420.0, z], [0.3, 0.0, 1.0], scheme: :allied, team: :player)
    @player_ai = Pilot.new(@player, 0.9)
    @enemies = [spawn_enemy(1, 0, [x + 300, 460.0, z + 500]), spawn_enemy(2, 1, [x - 300, 380.0, z + 700])]
    @orbit = 0.0
  end

  def start_game
    @state = :play
    @score = 0
    @kills = 0
    @lives = 2
    @wave = 0
    @bullets = []
    @effects.clear
    @hud.clear_messages
    @balloons = []
    @enemies = []
    @player_ai = nil
    spawn_player
    @wave_timer = 1.5
    @archie = 6.0
    @paused = false
  end

  def spawn_player
    x = @player && @player.alive? ? @player.position[0] : 0.0
    x = @crash_pos ? @crash_pos[0] : x
    z = @world.front_z(x) - 1100
    @player = Plane.new([x, 450.0, z], [0.0, 0.0, 1.0], scheme: :allied, team: :player, health: 30,
                                                    agility: 1.15)
    @player.throttle = 0.85
    @cam = D3D::Pose.new([x, 454.0, z - 16], [0.0, 0.0, 1.0])
    @respawn = nil
    @crash_pos = nil
    @stick = { pitch: 0.0, roll: 0.0, yaw: 0.0 }
  end

  def spawn_enemy(wave, index, pos = nil)
    triplane = wave >= 3 && index < (wave - 1) / 2
    skill = D3D.clamp(0.2 + wave * 0.1 + rand * 0.2 + (triplane ? 0.2 : 0.0), 0.0, 1.0)
    unless pos
      pp = @player.position
      ang = (rand - 0.5) * 2.4
      d = 1100 + rand * 500
      pos = [pp[0] + Math.sin(ang) * d, D3D.clamp(pp[1] + (rand - 0.4) * 300, 250, 900), pp[2] + Math.cos(ang) * d]
    end
    to = V.norm(V.sub(@player.position, pos))
    to = V.norm([to[0], 0.0, to[2]])
    plane = if triplane
              Plane.new(pos, to, kind: :triplane, scheme: :baron, team: :enemy, health: 10, agility: 0.78 + skill * 0.12)
            else
              Plane.new(pos, to, kind: :biplane, scheme: rand < 0.5 ? :albatros : :jasta, team: :enemy,
                                 health: 6, agility: 0.62 + skill * 0.16)
            end
    plane.name = triplane ? 'ACE' : 'SCOUT'
    plane.ai = Pilot.new(plane, skill)
    plane
  end

  def start_wave
    @wave += 1
    n = [1 + @wave, 7].min
    @enemies.concat(n.times.map { |i| spawn_enemy(@wave, i) })
    aces = @enemies.count { |e| e.kind == :triplane }
    if @wave.even? && @balloons.count(&:alive?) < 3
      2.times do
        x = @player.position[0] + (rand - 0.5) * 1800
        @balloons << Balloon.new([x, 280.0 + rand * 80, @world.front_z(x) + 650 + rand * 400])
      end
    end
    @hud.message("WAVE #{@wave}", time: 3.5, size: 44)
    @hud.message("#{n} enemy scouts sighted#{aces > 0 ? " - #{aces} ace#{aces > 1 ? 's' : ''} among them!" : ''}", time: 3.5, size: 24)
    @hud.message('Observation balloons over the enemy lines!', time: 3.5, size: 22, color: BALLOON) if @wave.even?
  end

  def game_over
    @state = :gameover
    @over_timer = 0.0
    if @score > @hiscore
      @hiscore = @score
      @new_hiscore = true
      $gtk.write_file(HISCORE_FILE, @hiscore.to_s)
    else
      @new_hiscore = false
    end
  end

  # ------------------------------------------------------------ tick

  def tick(args)
    @tick += 1
    @args = args
    input_global(args)
    case @state
    when :title
      update_title(args)
    when :play
      update_play(args) unless @paused
    when :gameover
      update_gameover(args)
    end
    update_audio(args)
    render(args)
  end

  def input_global(args)
    kb = args.inputs.keyboard
    @view = @view == :chase ? :cockpit : :chase if kb.key_down.c
    @film = !@film if kb.key_down.v
    @invert = !@invert if kb.key_down.i
    if kb.key_down.m
      @muted = !@muted
      args.audio.volume = @muted ? 0.0 : 1.0
    end
    @paused = !@paused if @state == :play && kb.key_down.p
    start_title if @state != :title && kb.key_down.escape
  end

  def start_pressed?(args)
    kb = args.inputs.keyboard
    c = args.inputs.controller_one
    kb.key_down.enter || kb.key_down.space || c.key_down.start || c.key_down.a
  end

  def update_title(args)
    @orbit += DT * 0.12
    ctl = @player_ai.think(DT, @enemies.first)
    @player.update(DT, ctl)
    b = @player.fire(DT, ctl[:fire], 0.02)
    @bullets << b if b
    @enemies.each do |e|
      ectl = e.ai.think(DT, @player)
      e.update(DT, ectl)
      b = e.fire(DT, ectl[:fire], 0.03)
      @bullets << b if b
    end
    update_bullets(false)
    @effects.update(DT)
    update_camera
    start_game if start_pressed?(args)
  end

  def update_gameover(args)
    @over_timer += DT
    @effects.update(DT)
    update_bullets(false)
    @enemies.each { |e| e.update(DT, e.ai.think(DT, nil)) }
    update_camera
    start_title if @over_timer > 1.5 && start_pressed?(args)
  end

  def update_play(args)
    @hud.update(DT)
    player_controls(args)
    update_enemies
    update_balloons
    update_bullets(true)
    update_archie
    check_collisions
    @effects.update(DT)
    update_waves
    update_camera
  end

  # ------------------------------------------------------------ player

  def player_controls(args)
    pl = @player
    kb = args.inputs.keyboard
    held = kb.key_held
    c = args.inputs.controller_one
    push = held.up || held.w ? 1 : 0
    pull = held.down || held.s ? 1 : 0
    pitch = (pull - push).to_f
    roll = ((held.right || held.d ? 1 : 0) - (held.left || held.a ? 1 : 0)).to_f
    yaw = ((held.e ? 1 : 0) - (held.q ? 1 : 0)).to_f
    fire = held.space || held.j
    thr = pl.throttle
    thr += DT * 0.6 if held.r || held.shift || c.key_held.r1
    thr -= DT * 0.6 if held.f || held.control || c.key_held.l1
    if c.connected
      lx = c.left_analog_x_perc || 0
      ly = c.left_analog_y_perc || 0
      rx = c.right_analog_x_perc || 0
      roll += lx if lx.abs > 0.12
      pitch -= ly if ly.abs > 0.12
      yaw += rx if rx.abs > 0.12
      fire ||= c.key_held.a || c.key_held.r2
    end
    pitch = -pitch if @invert
    # keyboard input ramps in, like moving a real stick
    k = [DT * 7.0, 1.0].min
    @stick[:pitch] += (D3D.clamp(pitch, -1, 1) - @stick[:pitch]) * k
    @stick[:roll] += (D3D.clamp(roll, -1, 1) - @stick[:roll]) * k
    @stick[:yaw] += (D3D.clamp(yaw, -1, 1) - @stick[:yaw]) * k
    was_jammed = pl.jammed?
    pl.update(DT, { pitch: @stick[:pitch], roll: @stick[:roll], yaw: @stick[:yaw], throttle: thr })
    b = pl.fire(DT, fire, 0.005)
    if b
      @bullets << b
      play(args, :gun, 'sounds/gun.wav', 0.42, 0.9 + rand * 0.2)
      @effects.muzzle_smoke(pl.muzzle_position, pl.velocity) if rand < 0.5
    end
    if pl.jammed? && !was_jammed
      @hud.message('GUNS JAMMED - let them cool!', time: 2.0, size: 24, color: [230, 110, 80])
      play(args, :jam, 'sounds/jam.wav', 0.8)
    end
    update_player_state
  end

  def update_player_state
    pl = @player
    pos = pl.position
    trail(pl)
    if pl.flying? && pos[1] < 2.0
      crash_player
    elsif pl.state == :falling && pos[1] < 1.0
      crash_player
    end
    return unless @respawn
    @respawn -= DT
    return if @respawn > 0
    if @lives.negative?
      game_over
    else
      spawn_player
      @hud.message('A replacement machine is ready. Good hunting!', time: 3, size: 24)
    end
  end

  def crash_player
    pl = @player
    @crash_pos = pl.position.dup
    @effects.crash(pl.position)
    sound(:boom, 'sounds/explosion.wav', 1.0)
    pl.crash!
    @lives -= 1
    @respawn = 3.5
    @hud.message(@lives.negative? ? 'SHOT DOWN - that was your last machine' : 'SHOT DOWN!', time: 3, size: 36, color: [230, 110, 80])
  end

  # Smoke and fire trails of damaged / falling planes.
  def trail(pl)
    return unless pl.alive?
    pl.smoke_timer -= DT
    return if pl.smoke_timer > 0
    pos = pl.position
    back = V.madd(pos, pl.fwd, -1.5)
    if pl.state == :falling
      pl.smoke_timer = 0.03
      @effects.fire(back, pl.velocity)
      @effects.smoke(back, pl.velocity, 45, 3.5)
    elsif pl.damaged?
      f = pl.health / pl.max_health.to_f
      pl.smoke_timer = 0.04 + f * 0.1
      dark = 60 + f * 120
      @effects.smoke(V.madd(pos, pl.fwd, 1.5), pl.velocity, dark, 2.0)
    end
  end

  # ------------------------------------------------------------ enemies

  def update_enemies
    target = @player.flying? ? @player : nil
    @enemies.each do |e|
      if e.flying?
        ctl = e.ai.think(DT, target)
        e.update(DT, ctl)
        b = e.fire(DT, ctl[:fire], e.ai.spread)
        if b
          @bullets << b
          d = V.dist(e.position, @cam.position)
          play(@args, :egun, 'sounds/gun.wav', 0.35 * (1 - d / 600.0), 1.25) if d < 600
        end
        if e.position[1] < 2.0
          e.shoot_down!
          kill(e, true)
        end
      else
        e.update(DT, nil)
        if e.state == :falling && e.position[1] < 1.0
          @effects.crash(e.position)
          d = V.dist(e.position, @cam.position)
          sound(:eboom, 'sounds/explosion.wav', D3D.clamp(1.2 - d / 1500.0, 0.2, 0.9)) if d < 1600
          e.crash!
        end
      end
      trail(e)
    end
    @enemies.reject! { |e| !e.alive? }
  end

  def kill(e, ground = false)
    value = e.kind == :triplane ? 250 : 100
    @score += value
    @kills += 1
    what = e.kind == :triplane ? 'ACE SHOT DOWN!' : 'Enemy down!'
    what = 'Enemy flew into the ground!' if ground
    @hud.message("#{what} +#{value}", time: 2.2, size: 28, color: [240, 214, 140])
    @hud.message('Five victories - you are an ACE!', time: 3.5, size: 30, color: [250, 220, 120]) if @kills == 5
  end

  def update_balloons
    @balloons.each { |b| b.update(DT, @effects) }
    @balloons.reject!(&:gone?)
  end

  def update_waves
    return if @respawn
    fighters = @enemies.count(&:flying?)
    if fighters.zero? && @enemies.empty?
      if @wave_timer.nil?
        if @wave > 0
          bonus = 200 * @wave
          @score += bonus
          @hud.message("WAVE #{@wave} CLEARED  +#{bonus}", time: 3, size: 36, color: [240, 214, 140])
          @player.health = [@player.health + @player.max_health * 0.5, @player.max_health].min
          @hud.message('Mechanics patched your machine', time: 3, size: 22)
        end
        @wave_timer = 4.5
      end
      @wave_timer -= DT
      if @wave_timer <= 0
        @wave_timer = nil
        start_wave
      end
    end
  end

  # "Archie": anti-aircraft fire over the enemy lines.
  def update_archie
    pl = @player
    return unless pl.flying?
    pos = pl.position
    return unless @world.enemy_side?(pos) && pos[1] < 1400
    @archie -= DT
    return if @archie > 0
    @archie = 1.6 + rand * 3.0
    v = pl.velocity
    burst = [pos[0] + v[0] * 1.3 + (rand - 0.5) * 110, pos[1] + v[1] * 1.3 + (rand - 0.4) * 70,
             pos[2] + v[2] * 1.3 + (rand - 0.5) * 110]
    @effects.flak(burst)
    d = V.dist(burst, pos)
    sound(:flak, 'sounds/explosion.wav', D3D.clamp(0.9 - d / 300.0, 0.15, 0.6), 1.6)
    return unless d < 22
    player_hit(2)
    @hud.message('Archie!', time: 1.2, size: 24, color: [230, 110, 80])
  end

  def player_hit(n)
    pl = @player
    return unless pl.flying?
    @hud.damage_flash!
    @shake = 0.25
    sound(:phit, 'sounds/hit.wav', 0.7, 0.8 + rand * 0.3)
    return unless pl.damage!(n)
    @hud.message('You are on fire!', time: 2, size: 30, color: [230, 110, 80])
  end

  def check_collisions
    pl = @player
    return unless pl.flying?
    @enemies.each do |e|
      next unless e.flying?
      next unless V.dist2(e.position, pl.position) < 7.5 * 7.5
      e.shoot_down!
      pl.damage!(99)
      kill(e)
      @effects.explosion(e.position, e.velocity, [[150, 106, 60], [96, 104, 64]])
      sound(:boom, 'sounds/explosion.wav', 1.0)
      @hud.message('MID-AIR COLLISION!', time: 2.5, size: 34, color: [230, 110, 80])
    end
  end

  # ------------------------------------------------------------ bullets

  def update_bullets(live)
    cam = @cam.position
    @bullets.reject! do |b|
      x0 = b[0]
      y0 = b[1]
      z0 = b[2]
      b[0] += b[3] * DT
      b[1] += b[4] * DT
      b[2] += b[5] * DT
      b[4] -= 9.81 * DT
      b[6] -= DT
      if b[1] <= 0
        near = (b[0] - cam[0])**2 + (b[2] - cam[2])**2 < 700 * 700
        if near
          @world.tile_type((b[0] / World::TILE).floor, (b[2] / World::TILE).floor) == :water ? @effects.splash([b[0], 0.0, b[2]]) : @effects.dust([b[0], 0.0, b[2]])
        end
        next true
      end
      next true if b[6] <= 0
      next false unless live
      bullet_hit?(b, x0, y0, z0)
    end
  end

  def seg_hit?(x0, y0, z0, x1, y1, z1, c, r)
    dx = x1 - x0
    dy = y1 - y0
    dz = z1 - z0
    fx = c[0] - x0
    fy = c[1] - y0
    fz = c[2] - z0
    dd = dx * dx + dy * dy + dz * dz
    t = dd > 0 ? (fx * dx + fy * dy + fz * dz) / dd : 0
    t = t < 0 ? 0 : (t > 1 ? 1 : t)
    ex = fx - dx * t
    ey = fy - dy * t
    ez = fz - dz * t
    ex * ex + ey * ey + ez * ez < r * r
  end

  def bullet_hit?(b, x0, y0, z0)
    x1 = b[0]
    y1 = b[1]
    z1 = b[2]
    if b[7] == :player
      @enemies.each do |e|
        next unless e.flying?
        next unless seg_hit?(x0, y0, z0, x1, y1, z1, e.position, Plane::RADIUS)
        @effects.sparks([x1, y1, z1], 4)
        sound(:hit, 'sounds/hit.wav', 0.45, 0.9 + rand * 0.3)
        if e.damage!(1, :player)
          kill(e)
          sound(:boom, 'sounds/explosion.wav', 0.7, 1.2)
          @effects.explosion(e.position, e.velocity, nil, big: 0.5)
        end
        return true
      end
      @balloons.each do |bl|
        next unless bl.alive?
        next unless seg_hit?(x0, y0, z0, x1, y1, z1, bl.position, Balloon::RADIUS)
        @effects.sparks([x1, y1, z1], 3)
        if bl.damage!(1)
          @score += 300
          @hud.message('BALLOON FLAMED! +300', time: 2.5, size: 30, color: BALLOON)
          sound(:boom, 'sounds/explosion.wav', 0.9, 0.7)
        end
        return true
      end
    else
      pl = @player
      if pl.flying? && seg_hit?(x0, y0, z0, x1, y1, z1, pl.position, Plane::RADIUS - 1.5)
        @effects.sparks([x1, y1, z1], 3)
        player_hit(1)
        return true
      end
    end
    false
  end

  # ------------------------------------------------------------ camera

  def update_camera
    pl = @player
    cam = @cam
    if @state == :title
      # attract mode: slow orbit around the dogfighting plane
      center = pl.position
      pos = V.add(center, [Math.sin(@orbit) * 26.0, 6.0, Math.cos(@orbit) * 26.0])
      cam.position = pos
      cam.look!(V.norm(V.sub(center, pos)))
      return
    end
    if !pl.alive? && @crash_pos
      # circle the wreck until the replacement arrives
      @orbit += DT * 0.25
      c = @crash_pos
      pos = [c[0] + Math.sin(@orbit) * 70, 35.0, c[2] + Math.cos(@orbit) * 70]
      cam.position = pos
      cam.look!(V.norm(V.sub([c[0], 5.0, c[2]], pos)))
      return
    end
    p = pl.pose
    padlock = @args && (@args.inputs.keyboard.key_held.t || @args.inputs.keyboard.key_held.tab)
    target = padlock ? nearest_enemy : nil
    if @view == :cockpit && !target
      cam.position = V.add(V.madd(p.position, p.up, 1.0), V.scale(p.fwd, -0.7))
      cam.right = p.right.dup
      cam.up = p.up.dup
      cam.fwd = p.fwd.dup
    else
      k = 1.0 - Math.exp(-DT * (target ? 5.0 : 7.0))
      want_f = target ? V.norm(V.sub(target.position, p.position)) : p.fwd
      want_u = target ? V.norm(V.lerp(p.up, [0.0, 1.0, 0.0], 0.5)) : p.up
      f = V.norm(V.lerp(cam.fwd, want_f, k))
      u = V.norm(V.lerp(cam.up, want_u, k * 0.8))
      cam.look!(f, u)
      back = target ? 21.0 : 17.0
      cam.position = V.add(V.madd(p.position, f, -back), V.scale(cam.up, 4.4))
    end
    if @shake && @shake > 0
      @shake -= DT
      s = @shake * 0.8
      cam.position = V.add(cam.position, [(rand - 0.5) * s, (rand - 0.5) * s, (rand - 0.5) * s])
    end
    cam.position[1] = 1.5 if cam.position[1] < 1.5
  end

  def nearest_enemy
    pos = @player.position
    best = nil
    bd = 1e18
    (@enemies + @balloons.select(&:alive?)).each do |e|
      next if e.is_a?(Plane) && !e.flying?
      d = V.dist2(e.position, pos)
      if d < bd
        bd = d
        best = e
      end
    end
    best
  end

  # ------------------------------------------------------------ audio

  def play(args, key, path, gain, pitch = 1.0)
    return unless args
    @snd_n = ((@snd_n || 0) + 1) % 6
    args.audio[:"#{key}#{@snd_n}"] = { input: path, gain: D3D.clamp(gain, 0.0, 1.0).to_f, pitch: pitch.to_f }
  end

  def sound(key, path, gain, pitch = 1.0)
    play(@args, key, path, gain, pitch)
  end

  def update_audio(args)
    @args = args
    pl = @player
    audible = pl.alive? && @state != :gameover && !@paused
    eng = args.audio[:engine] ||= { input: 'sounds/engine.wav', looping: true, gain: 0.0, pitch: 1.0 }
    target = audible ? (@state == :title ? 0.18 : 0.32) : 0.0
    target *= 0.8 if pl.state == :falling
    eng[:gain] = (eng[:gain] + (target - eng[:gain]) * 0.1).to_f
    eng[:pitch] = (0.62 + pl.throttle * 0.45 + pl.speed / 260.0).to_f
    wind = args.audio[:wind] ||= { input: 'sounds/wind.wav', looping: true, gain: 0.0, pitch: 1.0 }
    wind[:gain] = (audible ? D3D.clamp((pl.speed - 30) / 140.0, 0.02, 0.5) : 0.0).to_f
    near_ok = !@paused
    wind[:pitch] = (0.8 + pl.speed / 200.0).to_f
    # nearest enemy engine
    near = nil
    nd = 400.0
    @enemies.each do |e|
      next unless e.flying?
      d = V.dist(e.position, @cam.position)
      if d < nd
        nd = d
        near = e
      end
    end
    en = args.audio[:enemy_engine] ||= { input: 'sounds/engine.wav', looping: true, gain: 0.0, pitch: 1.2 }
    en[:gain] = (near && near_ok ? 0.35 * (1 - nd / 400.0) : 0.0).to_f
    en[:pitch] = (near ? 0.85 + near.speed / 180.0 : 1.2).to_f
  end

  # ------------------------------------------------------------ render

  def render(args)
    out = args.outputs.sprites
    hud = args.outputs.primitives
    cam = @cam
    r = @renderer
    pl = @player

    r.begin_frame(cam)
    r.draw_sky(out, World::GROUND_COLOR)
    shadow = nil
    if pl.alive? && pl.position[1] < 220
      shadow = @world.shadow_face(pl.position, pl.fwd)
    end
    @world.draw_ground(out, cam, shadow)
    r.draw_ground_haze(out, cam.position[1], @world.far)

    r.begin_frame(cam)
    @world.draw_objects(r, cam)
    inside = @world.draw_clouds(r, cam.position)
    pl.draw(r, cam.position) unless @view == :cockpit && @state == :play && pl.alive? && !padlock?
    @enemies.each { |e| e.draw(r, cam.position) }
    @balloons.each { |b| b.draw(r) }
    @effects.draw(r)
    @bullets.each do |b|
      r.draw_glow(b, 1.5, 255, 214, 130)
      r.draw_glow([b[0] - b[3] * 0.01, b[1] - b[4] * 0.01, b[2] - b[5] * 0.01], 1.1, 255, 170, 90)
    end
    out << r.sorted_primitives
    @tris = r.triangle_count + @world.ground_triangles
    out << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: 240, g: 240, b: 236, a: inside * 240 } if inside > 0

    playing = @state == :play && pl.alive?
    if playing && @view == :cockpit && !padlock?
      @hud.cockpit(out, @tick, pl.fire_timer > 0)
    end
    @hud.damage_overlay(out)
    @hud.film(out, @tick) if @film

    case @state
    when :title then draw_title(hud)
    when :play then draw_play_hud(hud, args)
    when :gameover then draw_gameover(hud)
    end
    draw_debug(hud, args) if args.inputs.keyboard.key_held.backspace || @debug
  end

  def padlock?
    @args && (@args.inputs.keyboard.key_held.t || @args.inputs.keyboard.key_held.tab)
  end

  def draw_play_hud(hud, args)
    pl = @player
    r = @renderer
    if pl.flying?
      if @view == :cockpit && !padlock?
        @hud.gunsight(hud, 640, 360, 56)
      else
        p = pl.pose
        aim = V.madd(p.position, p.fwd, 280.0)
        s = r.project(aim)
        @hud.gunsight(hud, s[0], s[1], 50) if s
      end
      # lead marker for the nearest enemy in front
      best = nil
      bd = 700.0
      @enemies.each do |e|
        next unless e.flying?
        d = V.dist(e.position, pl.position)
        next if d > bd || V.dot(V.sub(e.position, pl.position), pl.fwd) < 0
        bd = d
        best = e
      end
      if best
        t = bd / Plane::BULLET_SPEED
        @hud.lead_marker(hud, r, V.madd(best.position, V.sub(best.velocity, pl.velocity), t))
      end
      targets = @enemies.select(&:flying?).map { |e| [e.position, ENEMY, e.name] }
      @balloons.each { |b| targets << [b.position, BALLOON, 'BALLOON'] if b.alive? }
      @hud.markers(hud, r, targets, @cam.position)
      contacts = @enemies.select(&:flying?).map { |e| [e.position, ENEMY, e.kind == :triplane ? 4 : 3] }
      @balloons.each { |b| contacts << [b.position, BALLOON, 4] if b.alive? }
      @hud.radar(hud, pl.pose, contacts, @tick)
      @hud.instruments(hud, pl, { tick: @tick })
      @hud.compass(hud, @cam)
      @hud.text(hud, 640, 646, 'OVER ENEMY LINES', 16, [230, 150, 110]) if @world.enemy_side?(pl.position)
      if pl.speed < Plane::STALL + 3 && (@tick / 10).to_i.even?
        @hud.text(hud, 640, 250, 'STALL!', 30, [230, 110, 80], center: true)
      end
    end
    @hud.text(hud, 24, 700, "SCORE #{@score}", 26)
    @hud.text(hud, 24, 670, "VICTORIES #{@kills}", 18)
    @hud.text(hud, 24, 646, "SPARE MACHINES #{[@lives, 0].max}", 18)
    @hud.text(hud, 1256, 700, "WAVE #{@wave}", 26, right: true)
    @hud.text(hud, 1256, 670, "BEST #{@hiscore}", 18, right: true)
    left = @enemies.count(&:flying?)
    @hud.text(hud, 1256, 646, "HOSTILES #{left}", 18, ENEMY, right: true) if left > 0
    @hud.draw_messages(hud)
    @hud.text(hud, 640, 360, 'PAUSED', 50, center: true) if @paused
    return unless @paused
    controls_help(hud, 300)
  end

  def draw_title(hud)
    @hud.text(hud, 640, 640, 'SKY ACES', 84, [240, 222, 180], center: true)
    @hud.text(hud, 640, 578, '~ Western Front, 1917 ~', 26, [210, 180, 130], center: true)
    @hud.rect(hud, 300, 12, 680, 212, [28, 22, 16], 160)
    controls_help(hud, 206)
    blink = (@tick / 30).to_i.even?
    @hud.text(hud, 640, 300, 'Press SPACE to take off', 30, [250, 230, 170], center: true) if blink
    @hud.text(hud, 640, 262, "Best score: #{@hiscore}", 20, [210, 190, 150], center: true)
  end

  def controls_help(hud, top)
    lines = [
      ['Arrows / WASD', 'stick (Up = nose down)', "I: invert pitch#{@invert ? ' [on]' : ''}"],
      ['Q / E', 'rudder', 'R / F: throttle'],
      ['SPACE', 'fire twin Vickers', 'mind the gun heat!'],
      ['C', 'chase / cockpit view', 'hold T: padlock view'],
      ['V', "old film look #{@film ? '[on]' : '[off]'}", 'P: pause   M: mute']
    ]
    lines.each_with_index do |(k, a, b), i|
      y = top - i * 40
      @hud.text(hud, 480, y, k, 20, [240, 214, 140], right: true)
      @hud.text(hud, 500, y, a, 20)
      @hud.text(hud, 790, y, b, 18, [200, 186, 150])
    end
  end

  def draw_gameover(hud)
    @hud.rect(hud, 340, 200, 600, 330, [28, 22, 16], 180)
    @hud.text(hud, 640, 480, 'GAME OVER', 60, [230, 120, 90], center: true)
    @hud.text(hud, 640, 420, "Score #{@score}   -   #{@kills} victories   -   wave #{@wave}", 24, center: true)
    @hud.text(hud, 640, 370, @new_hiscore ? 'A new squadron record!' : "Squadron record: #{@hiscore}", 24,
              [240, 214, 140], center: true)
    @hud.text(hud, 640, 260, 'Press SPACE to return to the aerodrome', 22, center: true) if @over_timer > 1.5
  end

  def draw_debug(hud, args)
    @hud.text(hud, 640, 620, "fps #{args.gtk.current_framerate.round}  tris #{@tris}  parts #{@effects.count}  bullets #{@bullets.size}",
              16, center: true)
  end
end
