import { ROAD_CENTERS, ROUTE } from './drive-physics.js';

export class DriveCity {
  constructor(viewer) {
    const C=window.Cesium;
    this.viewer=viewer; this.obstacles=[]; this.gates=[];
    this.frame=C.Transforms.eastNorthUpToFixedFrame(C.Cartesian3.fromDegrees(0,0));
    this.point=(x,y,z=0)=>C.Matrix4.multiplyByPoint(this.frame,new C.Cartesian3(x,y,z),new C.Cartesian3());
    const color=s=>C.Color.fromCssColorString(s);
    const box=(x,y,z,w,d,h,material)=>viewer.entities.add({position:this.point(x,y,z),orientation:C.Transforms.headingPitchRollQuaternion(this.point(x,y,z),new C.HeadingPitchRoll()),box:{dimensions:new C.Cartesian3(w,d,h),material:color(material)}});
    // Cesium HPR's box X is east; the local city frame uses metres east/north/up.
    box(0,0,-.55,940,940,1,'#59765d');
    for (const c of ROAD_CENTERS) {
      box(c,0,.02,36,900,.1,'#9ca69f');
      box(0,c,.03,900,36,.1,'#9ca69f');
      box(c,0,.12,26,900,.1,'#323e45');
      box(0,c,.13,900,26,.1,'#323e45');
      for(let k=-430;k<440;k+=24) {
        if(ROAD_CENTERS.some(n=>Math.abs(n-k)<22)) continue;
        box(c,k,.2,.32,10,.04,'#e6d3a0');
        box(k,c,.21,10,.32,.04,'#e6d3a0');
      }
    }
    for(let ix=0;ix<4;ix++) for(let iy=0;iy<4;iy++) {
      const cx=-270+ix*180, cy=-270+iy*180;
      box(cx,cy,.25,140,140,.4,'#a5afa2');
      // One block is a public garden; the others contain a varied skyline.
      if(ix===1 && iy===2) {
        box(cx,cy,.5,120,120,.4,'#6d935e');
        box(cx,cy,.75,12,120,.4,'#c9b996');
        box(cx,cy,.8,120,12,.4,'#c9b996');
        continue;
      }
      for(let j=0;j<2;j++) {
        const x=cx+(j?33:-33), y=cy;
        const height=18+((ix*13+iy*7+j*11)%6)*9;
        const palette=['#d5c2a3','#8eaaa8','#b2bac6','#b88e74'];
        box(x,y,height/2+.5,53,108,height,palette[(ix+iy+j)%4]);
        this.obstacles.push({x,y,w:53,d:108});
        box(x,y,height+1.1,55,110,1.4,'#4c5d63');
        // Horizontal glass bands add depth without textures or network services.
        for(let z=5;z<height-2;z+=9) {
          box(x,y-54.1,z,46,.18,2.3,'#466470');
          box(x,y+54.1,z,46,.18,2.3,'#466470');
        }
      }
    }
    // Street trees stay clear of the road and are included in collision checks.
    for(const x of [-18,18,342,378]) for(let y=-310;y<=310;y+=80) {
      if(ROAD_CENTERS.some(c=>Math.abs(c-y)<25))continue;
      box(x,y,2,.65,.65,4,'#766653');
      viewer.entities.add({position:this.point(x,y,5.5),ellipsoid:{radii:new C.Cartesian3(3.3,3.3,4),material:color('#3d725a')}});
      this.obstacles.push({x,y,w:1,d:1});
    }
    // Ground markers are visual only: the target cannot block the player's car.
    ROUTE.forEach(([x,y],i)=> {
      const entity=viewer.entities.add({position:this.point(x,y,.4),ellipse:{semiMajorAxis:12,semiMinorAxis:12,height:.4,material:C.Color.GOLD.withAlpha(.34)},label:{text:String(i+1),font:'bold 22px sans-serif',pixelOffset:new C.Cartesian2(0,-60),fillColor:C.Color.GOLD,showBackground:true,scale:.85}});
      this.gates.push(entity);
    });
    this.setTarget(0);
  }
  setTarget(index) {
    this.gates.forEach((entity,i)=> {entity.show=i===index;});
  }
}
