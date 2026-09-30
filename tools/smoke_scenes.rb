# Scenario for tools/smoke.rb --eval: stages a few fixed scenes (low level
# flight, enemy close-ups, a balloon, an explosion) and screenshots each.
FRAMES = 60 * 14
$smoke = { frame: 0, log: [] }

class Game
  attr_accessor :view
  attr_reader :effects, :balloons

  def player_controls(_args)
    @player.update(DT, { pitch: 0.0, roll: 0.0, yaw: 0.0, throttle: 0.8 })
  end

  def stage(scene)
    pp = @player.position
    case scene
    when :low
      @player.pose = D3D::Pose.new([pp[0], 35.0, pp[2]], [0.3, -0.05, 1.0])
      @enemies = []
    when :enemies
      @player.pose = D3D::Pose.new([pp[0], 400.0, pp[2]], [0.0, 0.0, 1.0])
      p = @player.position
      @enemies = [spawn_enemy(1, 5, [p[0] - 9, 404.0, p[2] + 40]), spawn_enemy(5, 0, [p[0] + 14, 398.0, p[2] + 60])]
      @enemies.each { |e| e.pose = D3D::Pose.new(e.position, [0.8, 0.1, -0.4]); e.ai = nil }
    when :balloon
      p = @player.position
      @enemies = []
      @balloons = [Balloon.new([p[0] + 20, 300.0, p[2] + 160])]
      @player.pose = D3D::Pose.new([p[0], 305.0, p[2]], [0.1, 0.0, 1.0])
    when :boom
      p = @player.position
      @effects.explosion(V.madd(p, @player.fwd, 70), [0, 0, 20], [[150, 106, 60], [96, 104, 64]])
      @effects.flak(V.add(V.madd(p, @player.fwd, 120), [30, 15, 0]))
    end
  end

  def update_enemies; end
end

SCENES = { 60 => :low, 200 => :enemies, 360 => :balloon, 520 => :boom }.freeze
SHOTS = { 130 => 'scene_low', 150 => 'scene_low_cockpit', 206 => 'scene_enemies', 440 => 'scene_balloon', 540 => 'scene_boom' }.freeze

def tick(args)
  s = $smoke
  f = s[:frame]
  begin
    $game ||= Game.new(args)
    $game.start_game if f == 30
    $game.stage(SCENES[f]) if SCENES[f]
    $game.view = f.between?(140, 160) ? :cockpit : :chase
    $game.tick(args)
  rescue Exception => e
    s[:log] << "FAIL frame #{f}: #{e.class}: #{e.message} | #{e.backtrace.to_a.first(6).join(' | ')}"
    s[:frame] = FRAMES
  end
  name = SHOTS[f]
  args.outputs.screenshots << { x: 0, y: 0, w: 1280, h: 720, path: "smoke/#{name}.png", a: 255 } if name
  s[:frame] += 1
  return if s[:frame] < FRAMES
  s[:log] << 'scenes ok' if s[:log].empty?
  $gtk.write_file('smoke/report.txt', s[:log].join("\n") + "\nDONE\n")
  $gtk.request_quit
end
