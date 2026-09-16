// Driving state is independent of rendering, so collision and handling can be tested.
export const ROAD_CENTERS = [-360, -180, 0, 180, 360];
export const ROUTE = [[8, 0], [8, 188], [188, 188], [352, 188], [352, 8], [352, -172], [188, -172], [8, -172]];
export function onRoad(x, y) {
  return ROAD_CENTERS.some(c => Math.abs(x-c) <= 13 || Math.abs(y-c) <= 13);
}
export function collides(x, y, obstacles) {
  const radius = 1.45;
  if (Math.abs(x) > 445 || Math.abs(y) > 445) return true;
  return obstacles.some(b => {
    const dx = x - Math.max(b.x-b.w/2, Math.min(b.x+b.w/2, x));
    const dy = y - Math.max(b.y-b.d/2, Math.min(b.y+b.d/2, y));
    return dx*dx + dy*dy < radius*radius;
  });
}
export class DrivePhysics {
  constructor(obstacles = []) { this.obstacles = obstacles; this.reset(); }
  reset() {
    Object.assign(this, { x: 8, y: -310, heading: 0, speed: 0, steer: 0, elapsed: 0,
      distance: 0, topSpeed: 0, hits: 0, checkpoint: 0, laps: 0, lapTime: 0,
      lastLap: null, bestLap: null, hitCooldown: 0 });
  }
  recover() {
    const previous = this.checkpoint ? ROUTE[this.checkpoint-1] : [8,-310];
    [this.x,this.y] = previous;
    const target=ROUTE[this.checkpoint];
    this.heading=Math.atan2(target[0]-this.x,target[1]-this.y);
    this.speed=0; this.steer=0;
  }
  step(dt, input) {
    dt=Math.min(.05,Math.max(0,dt));
    this.elapsed+=dt; this.lapTime+=dt; this.hitCooldown=Math.max(0,this.hitCooldown-dt);
    const steer=(input.right?1:0)-(input.left?1:0);
    this.steer+=(steer-this.steer)*(1-Math.exp(-dt*7));
    let force=0;
    if (input.forward) force+=this.speed<-.5?12:8;
    if (input.reverse) force-=this.speed>.5?14:5;
    const friction=(.45+.008*this.speed*this.speed)*(onRoad(this.x,this.y)?1:4);
    const brake=input.brake?23:0;
    this.speed+=force*dt;
    this.speed=Math.sign(this.speed)*Math.max(0,Math.abs(this.speed)-(friction+brake)*dt);
    this.speed=Math.max(-8,Math.min(36,this.speed));
    this.heading+=this.steer*this.speed/2.8*Math.tan(.5)/(1+Math.abs(this.speed)*.16)*dt;
    const x=this.x+Math.sin(this.heading)*this.speed*dt;
    const y=this.y+Math.cos(this.heading)*this.speed*dt;
    if (collides(x,y,this.obstacles)) {
      if (!this.hitCooldown && Math.abs(this.speed)>1) {this.hits++;this.hitCooldown=1;}
      this.speed=0;
    } else {
      this.distance+=Math.hypot(x-this.x,y-this.y);
      this.x=x; this.y=y;
    }
    this.topSpeed=Math.max(this.topSpeed,Math.abs(this.speed)*3.6);
    const target=ROUTE[this.checkpoint];
    if (Math.hypot(this.x-target[0],this.y-target[1])<15) {
      this.checkpoint++;
      if (this.checkpoint===ROUTE.length) {
        this.checkpoint=0; this.laps++;
        this.lastLap=this.lapTime;
        this.bestLap=this.bestLap===null?this.lapTime:Math.min(this.bestLap,this.lapTime);
        this.lapTime=0;
      }
    }
  }
}
