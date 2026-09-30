# SKY ACES 1917 - a vintage dogfighting game built on the d3d engine.
GC.generational_mode = false if GC.respond_to?(:generational_mode=)

require 'app/d3d/d3d.rb'
require 'app/game/gfx.rb'
require 'app/game/models.rb'
require 'app/game/world.rb'
require 'app/game/plane.rb'
require 'app/game/ai.rb'
require 'app/game/effects.rb'
require 'app/game/hud.rb'
require 'app/game/game.rb'

def tick(args)
  $game ||= Game.new(args)
  $game.tick(args)
end

# Start over after editing game code: $gtk.reset in the console.
def reset(_args = nil)
  $game = nil
end
