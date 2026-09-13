import controlP5.*;
import processing.awt.PGraphicsJava2D;
import processing.core.PApplet;
import java.nio.file.*;
public class InterfaceCheck {
  public static class TestConsole extends DIMYX_3_3 {
    int sceneSaves, configSaves;
    String chosenPort;
    // Ces tests n'ecrivent aucun JSON et n'ouvrent aucun port physique.
    @Override public void saveScenes() { sceneSaves++; }
    @Override public void saveChannelConfig() { configSaves++; }
    @Override public void connectToSerial(String name) { chosenPort = name; }
  }
  static void check(boolean value, String reason) { if (!value) throw new AssertionError(reason); }
  static TestConsole app;
  static String renderDirectory;
  static void size(int w, int h) {
    app.width = w; app.height = h;
    app.g = new PGraphicsJava2D(); app.g.setParent(app); app.g.setSize(w,h);
    app.g.beginDraw(); app.g.endDraw();
    if (app.cp5 != null) app.layoutInterface();
  }
  static void render(String name) {
    if (renderDirectory == null) return;
    app.g.beginDraw(); app.drawConsoleInterface(); app.cp5.draw(); app.drawSelectedSceneBorder(); app.g.endDraw();
    app.g.save(Path.of(renderDirectory, name + ".png").toAbsolutePath().toString());
  }
  static void bounds() {
    var visible = new java.util.ArrayList<Controller<?>>();
    for (var c : app.cp5.getAll()) if (c instanceof Controller<?> && c.isVisible()) {
      float[] p = c.getPosition();
      check(p[0] >= 0 && p[1] >= 0 && p[0] + c.getWidth() <= app.width && p[1] + c.getHeight() <= app.height,
        "bounds " + app.width + "x" + app.height + " " + c.getName());
      for (var other : visible) {
        float[] q = other.getPosition();
        boolean overlaps = p[0] < q[0]+other.getWidth() && p[0]+c.getWidth()>q[0]
          && p[1]<q[1]+other.getHeight() && p[1]+c.getHeight()>q[1];
        check(!overlaps,"overlap " + c.getName() + " / " + other.getName());
      }
      visible.add((Controller<?>)c);
    }
  }
  static void click(String name) {
    var c = app.cp5.getController(name);
    int x = (int)c.getPosition()[0] + c.getWidth()/2;
    int y = (int)c.getPosition()[1] + c.getHeight()/2;
    app.mousePressed=false;
    app.cp5.getWindow().mouseEvent(x,y,false);
    app.mousePressed=true;
    app.cp5.getWindow().mouseEvent(x,y,true);
    app.mousePressed=false;
    app.cp5.getWindow().mouseEvent(x,y,false);
  }
  public static void main(String[] args) {
    renderDirectory = args.length > 0 ? args[0] : null;
    app = new TestConsole(); size(1366,768);
    app.nextPortScanTime = Long.MAX_VALUE;
    app.cp5 = new ControlP5(app); app.cp5.setAutoDraw(false);
    for (int i=0;i<10;i++) {
      var ch = app.new Channel("Tranche " + (i+1),i);
      ch.manualVal=1200+i*250; ch.fxMin=100; ch.fxMode=i%4; ch.isRGB=i%2==0;
      ch.sequencer.active=i%3==0;
      for(int j=0;j<10;j++) ch.sequencer.steps.add(app.new Step(1000+j*300,255,j*20,80));
      app.allChannels.add(ch);
    }
    app.createGUI(); app.updateGUIFromChannels();
    for(int i=0;i<12;i++) { var scene=app.new Scene("Scene " + (i+1));scene.capture();app.scenes.add(scene); }
    app.selectedSceneIndex=0; app.layoutInterface();
    for(int[] wh: new int[][]{{1600,1000},{1366,768},{1280,800},{1024,600},{800,540}}) {
      size(wh[0],wh[1]); bounds(); render(wh[0]+"x"+wh[1]);
      int first=app.firstChannel();
      boolean originalRgb=app.allChannels.get(first).isRGB;
      check(!app.cp5.getController("rgb_"+first).isVisible(),"RGB hidden in console");
      app.allChannels.get(first).fxMode=app.FX_MANUAL;
      app.updateEffectButton(first);
      app.updateChannelControls(first);
      if (!app.allChannels.get(first).sequencer.active) click("seq_"+first);
      check(app.allChannels.get(first).sequencer.active,"sequencer active before FX cycle");
      for (int fx : new int[]{1,2,3}) {
        click("effect_"+first);
        check(app.allChannels.get(first).fxMode==fx,"FX cycle mode "+fx);
        check(app.allChannels.get(first).sequencer.active,"SEQ stays active with FX "+fx);
        check(app.cp5.getController("bpm_"+first).isVisible(),"BPM visible with SEQ+FX "+fx);
        check(app.cp5.getController("freq_"+first).isVisible(),"FREQ visible with FX "+fx);
        check(app.cp5.getController("min_"+first).isVisible(),"MIN visible with FX "+fx);
      }
      click("effect_"+first);
      check(app.allChannels.get(first).fxMode==app.FX_MANUAL,"FX cycle back to MAN");
      click("effect_"+first);
      check(app.allChannels.get(first).fxMode==app.FX_STROBE,"FX still clickable after full cycle");
      float oldBpm=app.allChannels.get(first).sequencer.bpm;
      app.cp5.get(Slider.class,"bpm_"+first).setValue(Math.min(240f,oldBpm+1));
      check(app.allChannels.get(first).sequencer.bpm!=oldBpm || oldBpm==240,"BPM reacts after SEQ+FX");
      float oldFreq=app.allChannels.get(first).fxFreq;
      app.cp5.get(Slider.class,"freq_"+first).setValue(oldFreq>=9.9 ? 9.8 : oldFreq+0.1);
      check(app.allChannels.get(first).fxFreq!=oldFreq,"FREQ reacts after SEQ+FX");
      var mono=app.allChannels.get(first);
      mono.isRGB=false;
      mono.sequencer.active=true;
      mono.sequencer.currentStep=0;
      mono.sequencer.steps.get(0).intensity=1536;
      check(Math.abs(app.channelMaster(mono)-(1536f/4095f))<0.0001f,"mono sequencer intensity");
      mono.isRGB=originalRgb;
      check(app.physicalOutputEnabled(),"output live by default");
      click("blindMode");
      check(app.blindActive && !app.physicalOutputEnabled(),"BLIND blocks physical output");
      click("blindMode");
      check(!app.blindActive && app.physicalOutputEnabled(),"leaving BLIND restores output");
      var slider=app.cp5.get(Slider.class,"fader_"+first);
      int x=(int)slider.getPosition()[0]+slider.getWidth()/2;
      int y=(int)slider.getPosition()[1];
      app.cp5.getWindow().mouseEvent(x,y+1,false);
      app.cp5.getWindow().mouseEvent(x,y+1,true);
      slider.updateInternalEvents(app);
      app.cp5.getWindow().mouseEvent(x,y+1,false);
      check(app.allChannels.get(first).manualVal>3800,"fader top after resize");
      app.cp5.getWindow().mouseEvent(x,y+slider.getHeight()-1,false);
      app.cp5.getWindow().mouseEvent(x,y+slider.getHeight()-1,true);
      slider.updateInternalEvents(app);
      app.cp5.getWindow().mouseEvent(x,y+slider.getHeight()-1,false);
      check(app.allChannels.get(first).manualVal<300,"fader bottom after resize");
      click("channelNext"); bounds();
      check(app.firstChannel()>first || app.channelsPerPage==10,"channel navigation");
      app.mouseX=app.stepsX(app.firstChannel())+5; app.mouseY=app.stepsY()+5; app.mouseButton=PApplet.LEFT;
      app.mousePressed(); check(app.selectedStepChannel==app.firstChannel(),"step hit after paging");
      click("outputsView"); check(app.outputsView,"routing view button"); bounds();
      check(!app.cp5.getController("fader_"+app.firstChannel()).isVisible(),"routing hides live controls");
      check(app.cp5.getController("rgb_"+app.firstChannel()).isVisible(),"routing shows RGB selector");
      boolean routingRgb=app.allChannels.get(app.firstChannel()).isRGB;
      click("rgb_"+app.firstChannel());
      check(app.allChannels.get(app.firstChannel()).isRGB!=routingRgb,"RGB changes in routing view");
      click("rgb_"+app.firstChannel());
      if(app.narrowLayout) {click("scenesView");bounds();render("usb-"+wh[0]);click("scenesView");}
      render("outputs-"+wh[0]);
      click("outputsView"); check(!app.outputsView,"console return");
      check(!app.cp5.getController("rgb_"+app.firstChannel()).isVisible(),"RGB hidden after console return");
      if(app.narrowLayout) { click("scenesView");check(app.scenesView,"scene tab");bounds();render("scenes-"+wh[0]);click("scenesView"); }
      app.channelPage=0;app.layoutInterface();
    }
    app.cloneChannel(0); app.channelNext(); app.cloneChannel(app.firstChannel());
    check(app.channelClipboard==null,"clone across pages");
    var source=app.allChannels.get(0);
    var destination=app.allChannels.get(app.firstChannel());
    check(destination.sequencer.steps.get(0)!=source.sequencer.steps.get(0),"deep copy of steps");
    app.outputsView=true; app.scenesView=true; app.layoutInterface();
    app.availablePorts=new String[]{"TEST0","TEST1","TEST2","TEST3","TEST4","TEST5","TEST6","TEST7"};
    app.refreshPortButtons(); bounds(); click("nextPorts"); click("usbPort_6");
    check("TEST6".equals(app.chosenPort),"port choice after paging");
    app.outputsView=false; app.layoutInterface();
    app.selectedSceneIndex=7; app.currentPage=1;
    size(1600,1000);
    check(app.selectedSceneIndex/app.scenesPerPage==app.currentPage,"scene selection survives responsive repagination");
    app.channelPage=0; app.layoutInterface();
    var hiddenSequencer=app.allChannels.get(9).sequencer;
    hiddenSequencer.active=true; hiddenSequencer.currentStep=0; hiddenSequencer.lastStepTime=app.millis()-2000;
    app.g.beginDraw(); app.draw(); app.g.endDraw();
    check(hiddenSequencer.currentStep==1,"hidden sequencers continue playing");
    var name=app.cp5.get(Textfield.class,"sceneName");
    name.setText("Test de scene");
    int previous=app.scenes.size(); app.newScene();
    check(app.scenes.size()==previous+1 && app.sceneSaves>0,"scene creation");
    app.allChannels.get(0).manualVal=2345; app.recScene();
    app.allChannels.get(0).manualVal=0; app.launchScene(app.selectedSceneIndex,true);
    check(app.allChannels.get(0).manualVal==2345,"record and instant recall");
    app.cp5.get(Slider.class,"fadeTimeSlider").setValue(1000);
    app.launchScene(0,false); app.cloneChannel(0);
    check(app.channelClipboard==null,"clone blocked during transition");
    app.transitionStartTime=app.millis()-1000;
    app.g.beginDraw(); app.draw(); app.g.endDraw();
    check(!app.isTransitioning,"transition completes");
    app.outputsView=true; app.scenesView=false; app.channelPage=0; app.layoutInterface();
    var field=app.cp5.get(Textfield.class,"name_0");
    field.setText("Nom modifie"); field.submit();
    check(app.allChannels.get(0).name.equals("Nom modifie") && app.configSaves>0,"textfield submit");
    field.setFocus(true);
    app.cp5.getWindow().keyEvent(new processing.event.KeyEvent(null,0,processing.event.KeyEvent.PRESS,0,'Z',90));
    app.cp5.getWindow().keyEvent(new processing.event.KeyEvent(null,0,processing.event.KeyEvent.RELEASE,0,'Z',90));
    check(field.getText().contains("Z"),"native keyboard input");
    app.channelNext();
    check(!field.isFocus(),"hidden fields lose keyboard focus");
    app.applyBlackout(false);
    for(var ch:app.allChannels) check(ch.manualVal==0 && !ch.sequencer.active,"blackout hidden channels");
    System.out.println("PASS: resolutions, FX cycle, BLIND, mono sequencer, routing RGB, paging, scenes, clone, text fields and blackout");
  }
}
