# Enemy pilot: turns controls into the same stick / rudder / throttle inputs
# the player uses. Chases the lead point of its target with bank-and-pull
# turns, fires short bursts when the target is in its sights, breaks off
# before collisions and jinks when someone sits on its tail. To stay
# beatable it moves the stick with a reaction lag, never pulls quite as hard
# as it could, and after pressing an attack for a while it extends away in
# a straight line (a chance for the player to turn the tables).
class Pilot
  V = D3D::V

  attr_reader :state

  def initialize(plane, skill)
    @plane = plane
    @skill = skill
    @state = :attack
    @timer = 0.0
    @burst = 0.0
    @cool = 1.0 + rand * 2.0
    @dir = nil
    @pressure = 0.0
    @patience = 3.0 + skill * 3.0 + rand * 2.0
    @want = { pitch: 0.0, roll: 0.0, yaw: 0.0 }
    @ctl = { pitch: 0.0, roll: 0.0, yaw: 0.0, throttle: 1.0, fire: false }
  end

  def think(dt, target)
    plane = @plane
    p = plane.pose
    pos = p.position
    fwd = p.fwd
    @timer -= dt
    @cool -= dt
    @burst -= dt
    fire_ok = false
    # cruise below full power, so a player at full throttle can close in
    throttle = 0.78 + 0.12 * @skill
    dir = nil

    # terrain and ceiling come first
    alt = pos[1]
    if alt < 120 || alt + fwd[1] * plane.speed * 3.5 < 70
      dir = V.norm([fwd[0], 1.1, fwd[2]])
    elsif alt > 1150
      dir = V.norm([fwd[0], -0.35, fwd[2]])
    end

    unless dir
      case @state
      when :evade, :extend
        dir = @dir
        @state = :attack if @timer <= 0
      end
    end

    if !dir && target && target.flying?
      tpos = target.position
      to = V.sub(tpos, pos)
      dist = V.len(to)
      t = dist / (Plane::BULLET_SPEED + plane.speed * 0.3)
      lead = V.madd(tpos, target.velocity, t * (0.6 + 0.4 * @skill))
      dir = V.norm(V.sub(lead, pos))
      ahead = V.dot(V.norm(to), fwd)

      # pressing the attack from behind: after a while give up and extend
      @pressure += dt if ahead > 0.6 && dist < 500
      if @pressure > @patience
        @pressure = 0.0
        @patience = 3.0 + @skill * 3.0 + rand * 2.0
        side = rand < 0.5 ? -1 : 1
        @dir = V.norm([fwd[0] + p.right[0] * side * 0.5, 0.15, fwd[2] + p.right[2] * side * 0.5])
        @state = :extend
        @timer = 4.5 - @skill * 1.5 + rand * 1.5
        dir = @dir
      elsif dist < 60 && ahead > 0.3
        # about to collide: break away
        side = rand < 0.5 ? -1 : 1
        @dir = V.norm(V.add(V.add(fwd, V.scale(p.right, side * 1.2)), V.scale(p.up, 0.4 - rand * 0.8)))
        @state = :extend
        @timer = 1.6 + rand * 1.2
      else
        # target sitting on our tail?
        tf = target.fwd
        from_t = V.norm(V.sub(pos, tpos))
        if dist < 420 && V.dot(tf, from_t) > 0.96 && ahead < 0.2 && rand < dt * (0.1 + 0.6 * @skill)
          side = rand < 0.5 ? -1 : 1
          @dir = V.norm(V.add(V.scale(p.right, side), V.add(V.scale(p.up, rand * 1.2 - 0.5), V.scale(fwd, 0.15))))
          @state = :evade
          @timer = 0.9 + rand * 1.6
        end
        tol = 0.9985 - (1.0 - @skill) * 0.004
        fire_ok = dist < 400 && V.dot(fwd, dir) > tol
        throttle = 0.55 if dist < 160 && ahead > 0.8 && plane.speed > target.speed
      end
    end

    # nothing to do: lazy circle
    dir ||= V.norm(V.add([fwd[0], 0.0, fwd[2]], V.scale([p.right[0], 0.0, p.right[2]], 0.35)))

    steer(dir)
    # reaction lag and a limit on how hard it pulls
    k = [dt * (2.5 + 3.0 * @skill), 1.0].min
    max_pull = 0.55 + 0.35 * @skill
    ctl = @ctl
    want = @want
    want[:pitch] = max_pull if want[:pitch] > max_pull
    ctl[:pitch] += (want[:pitch] - ctl[:pitch]) * k
    ctl[:roll] += (want[:roll] - ctl[:roll]) * k
    ctl[:yaw] += (want[:yaw] * (0.4 + 0.4 * @skill) - ctl[:yaw]) * k
    @ctl[:throttle] = throttle

    if fire_ok && @cool <= 0 && @burst <= 0
      @burst = 0.35 + rand * 0.5 * (0.5 + @skill)
      @cool = @burst + 0.9 + rand * (2.0 - @skill)
    end
    @ctl[:fire] = @burst > 0 && fire_ok
    @ctl
  end

  def spread
    0.036 - 0.02 * @skill
  end

  private

  def steer(dir)
    p = @plane.pose
    r = p.right
    u = p.up
    lx = V.dot(dir, r)
    ly = V.dot(dir, u)
    lz = V.dot(dir, p.fwd)
    ctl = @want
    if lz > 0.992
      # fine tracking: rudder + elevator, wings towards level
      ctl[:pitch] = D3D.clamp(ly * 9.0, -1, 1)
      ctl[:yaw] = D3D.clamp(lx * 9.0, -1, 1)
      ctl[:roll] = D3D.clamp(Math.atan2(r[1], u[1]) * 0.8 + lx * 4.0, -1, 1)
    elsif lz > 0.5 && ly < 0 && ly.abs > lx.abs
      # target ahead and below: roll so it sits under the nose, push down
      ctl[:roll] = D3D.clamp(Math.atan2(-lx, -ly) * 2.2, -1, 1)
      ctl[:pitch] = D3D.clamp(ly * 3.0, -0.7, 0)
      ctl[:yaw] = D3D.clamp(lx * 3.0, -1, 1)
    else
      err = Math.atan2(lx, ly)
      ctl[:roll] = D3D.clamp(err * 2.4, -1, 1)
      pull = err.abs < 0.7 ? 1.0 : 0.35
      pull = 1.0 if lz < 0 && err.abs < 0.5
      ctl[:pitch] = D3D.clamp((ly > 0 ? 0.5 + ly : 0.2) * pull * 1.6, -0.3, 1.0)
      ctl[:yaw] = D3D.clamp(lx * 2.0, -1, 1)
    end
  end
end
