# Evaluated inside DragonRuby by tools/smoke.rb: shows the title, then plays
# with an autopilot (the enemy AI flying the player's plane), takes
# screenshots and measures the Ruby time per tick. Writes smoke/report.txt.
SHOTS = { 60 => 'title', 400 => 'chase', 700 => 'chase2', 1000 => 'cockpit', 1300 => 'late' }.freeze
FRAMES = 1400
$smoke = { frame: 0, times: [], tris: [], log: [] }

class Game
  attr_accessor :view, :debug

  # autopilot instead of the keyboard
  def player_controls(args)
    pl = @player
    @auto ||= {}
    ai = (@auto[pl.object_id] ||= Pilot.new(pl, 0.8))
    target = nearest_enemy
    target = nil if target.is_a?(Balloon)
    ctl = ai.think(DT, target)
    pl.update(DT, ctl)
    b = pl.fire(DT, ctl[:fire], 0.005)
    @bullets << b if b
    update_player_state
  end
end

def tick(args)
  s = $smoke
  f = s[:frame]
  begin
    $game ||= Game.new(args)
    if f == 90
      $game.start_game
      $game.player.health = 999 # survive the whole run
    end
    $game.view = f >= 900 && f < 1100 ? :cockpit : :chase
    t0 = Time.now
    $game.tick(args)
    if f > 100
      s[:times] << (Time.now - t0) * 1000
      s[:tris] << ($game.instance_variable_get(:@tris) || 0)
    end
  rescue Exception => e
    s[:log] << "FAIL frame #{f}: #{e.class}: #{e.message} | #{e.backtrace.to_a.first(6).join(' | ')}"
    s[:frame] = FRAMES
  end
  name = SHOTS[f]
  args.outputs.screenshots << { x: 0, y: 0, w: 1280, h: 720, path: "smoke/#{name}.png", a: 255 } if name
  s[:frame] += 1
  return if s[:frame] < FRAMES

  t = s[:times].sort
  unless t.empty?
    avg = t.sum / t.size
    s[:log] << format('ticks %d  avg %.1f ms  median %.1f ms  p95 %.1f ms  max %.1f ms',
                      t.size, avg, t[t.size / 2], t[(t.size * 0.95).to_i], t.last)
    tr = s[:tris].sort
    s[:log] << format('triangles avg %d  max %d', tr.sum / tr.size, tr.last)
    g = $game
    s[:log] << "state #{g.state} enemies #{g.enemies.size} score #{g.instance_variable_get(:@score)} wave #{g.instance_variable_get(:@wave)} kills #{g.instance_variable_get(:@kills)}"
  end
  $gtk.write_file('smoke/report.txt', s[:log].join("\n") + "\nDONE\n")
  $gtk.request_quit
end
