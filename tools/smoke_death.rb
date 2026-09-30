# Scenario for tools/smoke.rb --eval: the player flies in gentle circles and
# never shoots, so the enemies shoot it down; checks respawn and game over.
FRAMES = 60 * 150
$smoke = { frame: 0, log: [], last_state: nil, last_lives: nil }

class Game
  def player_controls(_args)
    pl = @player
    pl.update(DT, { pitch: 0.12, roll: pl.pose.right[1] > -0.3 ? 0.3 : 0.0, yaw: 0.0, throttle: 0.7 })
    update_player_state
  end
end

def tick(args)
  s = $smoke
  f = s[:frame]
  begin
    $game ||= Game.new(args)
    $game.start_game if f == 30
    $game.tick(args)
    g = $game
    lives = g.instance_variable_get(:@lives)
    st = "#{g.state}/#{g.player.state}"
    if st != s[:last_state] || lives != s[:last_lives]
      s[:log] << format('t=%5.1fs %-16s lives %s health %s wave %s', f / 60.0, st, lives.inspect,
                        g.player.health.round(1), g.instance_variable_get(:@wave).inspect)
      args.outputs.screenshots << { x: 0, y: 0, w: 1280, h: 720, path: "smoke/death_#{f}.png", a: 255 } if g.player.state == :falling || g.state == :gameover
      s[:last_state] = st
      s[:last_lives] = lives
    end
    s[:frame] = FRAMES if g.state == :gameover && f > 0 && (s[:over] = (s[:over] || 0) + 1) > 120
  rescue Exception => e
    s[:log] << "FAIL frame #{f}: #{e.class}: #{e.message} | #{e.backtrace.to_a.first(6).join(' | ')}"
    s[:frame] = FRAMES
  end
  s[:frame] += 1
  return if s[:frame] < FRAMES
  args.outputs.screenshots << { x: 0, y: 0, w: 1280, h: 720, path: 'smoke/death_end.png', a: 255 }
  $gtk.write_file('smoke/report.txt', s[:log].join("\n") + "\nDONE\n")
  $gtk.request_quit
end
