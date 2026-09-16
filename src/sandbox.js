// Generated scenery: no imagery, terrain service, Google API or access token.
export class Sandbox {
  constructor(viewer) {
    this.viewer = viewer;
    this.entities = [];
    this.gates = [];
    this.next = 0;
    const C = window.Cesium;
    this.frame = C.Transforms.eastNorthUpToFixedFrame(C.Cartesian3.fromDegrees(0, 0));
    this.point = (x, y, z) => C.Matrix4.multiplyByPoint(this.frame, new C.Cartesian3(x, y, z), new C.Cartesian3());
    const add = spec => { const e = viewer.entities.add(spec); this.entities.push(e); return e; };
    const box = (x, y, z, w, d, h, color) => add({
      position: this.point(x, y, z),
      orientation: C.Transforms.headingPitchRollQuaternion(this.point(x,y,z), new C.HeadingPitchRoll()),
      box: { dimensions: new C.Cartesian3(w,d,h), material: C.Color.fromCssColorString(color) },
    });
    // Patchwork fields make movement and altitude readable, even on low settings.
    for (let x = -8; x <= 8; x++) for (let y = -6; y <= 12; y++) {
      const colors = ['#567849', '#708551', '#8b9259', '#456943'];
      box(x*800, y*800, -2, 790, 790, 4, colors[((x*7+y*13)%4+4)%4]);
    }
    box(0, 0, 2, 65, 1500, 4, '#384447');
    for (let y=-650; y<=650; y+=100) box(0,y,4.5,4,45,1,'#e4dfc4');
    for (let y=-500; y<=500; y+=250) {
      box(-160,y,22,110,150,44,'#82938a');
      box(100,y,3,30,12,6,'#d8b467');
    }
    for (let i=0; i<60; i++) {
      const x = Math.sin(i*7.13)*5000, y = Math.cos(i*3.71)*5000+1500;
      if (Math.abs(x)<250) continue;
      add({position:this.point(x,y,40), ellipsoid:{radii:new C.Cartesian3(45,45,65),material:C.Color.fromCssColorString('#2d593e')}});
    }
    for (let i=0; i<8; i++) {
      const x = i < 2 ? 0 : Math.sin((i-1)*.6)*650;
      const y = 600+i*650, z = 350 + Math.sin(i*.8)*70;
      const center = this.point(x,y,z), positions=[];
      for (let j=0; j<=64; j++) { const a=j/64*Math.PI*2; positions.push(this.point(x+100*Math.cos(a),y,z+100*Math.sin(a))); }
      const entity=add({position:center, polyline:{positions,width:6,material:C.Color.GOLD},label:{show:i===0,text:String(i+1),font:'bold 22px sans-serif',pixelOffset:new C.Cartesian2(0,-110),fillColor:C.Color.GOLD,showBackground:true}});
      this.gates.push({center,entity});
    }
  }
  reset() {
    this.next=0;
    for (const [i,g] of this.gates.entries()) { g.entity.polyline.material=window.Cesium.Color.GOLD; g.entity.label.show=i===0; }
  }
  status(position) {
    const C=window.Cesium, gate=this.gates[this.next];
    if (!gate) return 'Course complete · 8 / 8 gates! Keep exploring.';
    const distance=C.Cartesian3.distance(position,gate.center);
    if (distance<100) { gate.entity.polyline.material=C.Color.LIME; gate.entity.label.show=false; this.next++; if (this.gates[this.next]) this.gates[this.next].entity.label.show=true; return this.status(position); }
    return `Sandbox · ${this.next} / 8 gates · Gate ${this.next+1}: ${Math.round(distance)} m`;
  }
  destroy() { for (const e of this.entities) this.viewer.entities.remove(e); }
}
