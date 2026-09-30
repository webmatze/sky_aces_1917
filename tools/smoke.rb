#!/usr/bin/env ruby
# Runs the game headless in DragonRuby for ~23 s of game time with an
# autopilot, reports errors and tick timings, and saves screenshots.
#
#   ruby tools/smoke.rb [--out DIR] [--eval FILE]
#     --out   screenshot dir (default: $TMPDIR/sky-aces-smoke)
#     --eval  scenario (default: tools/smoke_eval.rb; tools/smoke_death.rb
#             lets the enemies shoot a passive player down until game over)
require "tmpdir"
require "fileutils"

root = File.expand_path("..", __dir__)
idx = ARGV.index("--out")
eidx = ARGV.index("--eval")
eval_file = eidx ? File.expand_path(ARGV[eidx + 1]) : File.join(__dir__, "smoke_eval.rb")
out = File.expand_path(idx ? ARGV[idx + 1] : File.join(Dir.tmpdir, "sky-aces-smoke"))
toml = File.read(File.join(root, "Smaug.toml"))[/\[dragonruby\][^\[]*/m]
version = toml[/^version\s*=\s*"([^"]+)"/, 1]
edition = toml[/^edition\s*=\s*"([^"]+)"/, 1] || "standard"
bin = ENV["DRAGONRUBY_BIN"] ||
      File.expand_path("~/Library/Application Support/org.Erebor-Studios.Smaug/dragonruby/#{edition}-#{version}/dragonruby")
abort "DragonRuby not found at #{bin}; set DRAGONRUBY_BIN" unless File.exist?(bin)

work = Dir.mktmpdir("sky-aces-")
begin
  game = File.join(work, "game")
  FileUtils.mkdir_p(game)
  %w[app metadata sprites sounds native data].each do |d|
    FileUtils.cp_r(File.join(root, d), game) if File.exist?(File.join(root, d))
  end
  FileUtils.mkdir_p(File.join(game, "smoke"))
  FileUtils.cp(eval_file, File.join(game, "smoke_eval.rb"))
  log = File.join(game, "dragonruby.log")
  pid = Process.spawn({ "SDL_VIDEODRIVER" => "dummy", "SDL_AUDIODRIVER" => "dummy" }, bin, game, "--eval", "smoke_eval.rb",
                      out: log, err: log)
  deadline = Time.now + 400
  until Process.wait(pid, Process::WNOHANG)
    if Time.now > deadline
      Process.kill("KILL", pid)
      Process.wait(pid)
      abort "timed out; log tail:\n" + File.read(log).lines.last(30).join
    end
    sleep 0.2
  end
  report = File.join(game, "smoke/report.txt")
  FileUtils.rm_rf(out)
  FileUtils.mkdir_p(out)
  Dir[File.join(game, "smoke/*.png")].each { |f| FileUtils.cp(f, out) }
  unless File.exist?(report)
    puts File.read(log).lines.last(40).join
    exit 1
  end
  text = File.read(report)
  puts text.sub("DONE\n", "")
  File.read(log).scan(/\* WARNING: (.+)$/).flatten.uniq.each { |w| puts "DragonRuby warning: #{w}" }
  File.read(log).scan(/^.*(?:Exception|error).*$/i).uniq.first(10).each { |w| puts "log: #{w}" }
  puts "screenshots: #{out}"
  exit(text.include?("FAIL") ? 1 : 0)
ensure
  FileUtils.rm_rf(work)
end
