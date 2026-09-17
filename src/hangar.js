// The hangar renders the same GLB and mounting used by the flight engine.
export class Hangar {
  constructor(container) {
    const C=window.Cesium;
    this.viewer=new C.Viewer(container,{baseLayer:false,baseLayerPicker:false,geocoder:false,homeButton:false,sceneModePicker:false,navigationHelpButton:false,fullscreenButton:false,timeline:false,animation:false,infoBox:false,selectionIndicator:false,requestRenderMode:true,maximumRenderTimeChange:Infinity,contextOptions:{webgl:{preserveDrawingBuffer:true,alpha:true}}});
    const scene=this.viewer.scene;
    scene.globe.show=false;scene.skyAtmosphere.show=false;scene.skyBox.show=false;scene.sun.show=false;scene.moon.show=false;
    scene.backgroundColor=C.Color.TRANSPARENT;scene.screenSpaceCameraController.enableInputs=false;
    scene.light=new C.DirectionalLight({direction:C.Cartesian3.normalize(new C.Cartesian3(-1,.2,-.6),new C.Cartesian3()),intensity:3});
    scene.postProcessStages.fxaa.enabled=false;scene.msaaSamples=4;this.viewer.resolutionScale=1;
    this.anchor=C.Cartesian3.fromDegrees(0,0,1000);this.heading=2.35;this.pitch=-.3;this.range=15;this.generation=0;
    this.frame=C.Transforms.eastNorthUpToFixedFrame(this.anchor);
  }
  async show(vehicle) {
    const C=window.Cesium, generation=++this.generation;
    this.viewer.scene.primitives.removeAll();this.model=null;
    const matrix=C.Transforms.headingPitchRollToFixedFrame(this.anchor,new C.HeadingPitchRoll(vehicle.yaw*Math.PI/180,0,0));
    const model=await C.Model.fromGltfAsync({url:vehicle.uri,modelMatrix:matrix,scale:vehicle.scale});
    if(this.viewer.isDestroyed() || generation!==this.generation){model.destroy();return false;}
    this.viewer.scene.primitives.add(model);this.model=model;
    this.range=vehicle.id==='plane'?18:15;this.orbit(0);
    await new Promise((resolve,reject)=> {
      let done=false;
      const finish=err=>{if(done)return;done=true;this.abortPending=null;clearTimeout(timer);removeReady();removeError();err?reject(err):resolve();};
      const removeReady=model.readyEvent.addEventListener(()=>finish());
      const removeError=model.errorEvent.addEventListener(e=>finish(e));
      const timer=setTimeout(()=>finish(new Error('Aircraft preview timed out')),20000);
      this.abortPending=()=>finish(new Error("Aircraft inspection closed"));
      if(model.ready)finish();
      this.viewer.scene.requestRender();
    });
    if(generation!==this.generation || this.viewer.isDestroyed())return false;
    this.viewer.render();return true;
  }
  orbit(delta) {
    const C=window.Cesium;this.heading+=delta;
    this.viewer.camera.lookAt(this.anchor,new C.HeadingPitchRange(this.heading,this.pitch,this.range));
    this.viewer.scene.requestRender();
  }
  destroy() {this.generation++;this.abortPending?.();if(!this.viewer.isDestroyed())this.viewer.destroy();}
}
