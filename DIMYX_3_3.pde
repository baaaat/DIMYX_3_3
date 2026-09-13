import controlP5.*;
import processing.serial.*;

ControlP5 cp5;
Serial myPort;

int nbChannels = 10;
boolean serialConnected = false;
String connectedPortName = "Aucun";
String lastKnownPortName = null;

long lastSendTime = 0;
long lastHeartbeatTime = 0;
long lastSerialResponseTime = 0;
long nextReconnectAttemptTime = 0;
long nextPortScanTime = 0;
int sendInterval = 33;
int heartbeatInterval = 500;
int connectionTimeout = 1500;
int reconnectInterval = 2000;
int portScanInterval = 5000;
boolean watchdogArmed = false;
boolean connectionFailSafeActive = false;
int sceneToResumeIndex = -1;

ArrayList<Scene> scenes = new ArrayList<Scene>();
int selectedSceneIndex = -1;
int activeSceneIndex = -1;
int currentPage = 0;
int scenesPerPage = 8;
final int maxSequencerSteps = 10;
final int sequencerStepsPerRow = 5;
int selectedStepChannel = -1;
int selectedStepIndex = -1;
boolean stepEditMode = false;
long lastStepClickTime = 0;
int lastClickedStepChannel = -1;
int lastClickedStepIndex = -1;

ArrayList<Button> sceneButtons = new ArrayList<Button>();

boolean isTransitioning = false;
long transitionStartTime = 0;
int transitionDuration = 0;
ChannelState[] startStates;
ChannelState[] targetStates;
ChannelState channelClipboard = null;
int cloneSourceIndex = -1;
String cloneStatus = "CLONER : choisir une tranche source";

class ChipView implements ControllerView<Toggle> {
  String label;
  int accent;

  ChipView(String label, int accent) {
    this.label = label;
    this.accent = accent;
  }

  public void display(PGraphics g, Toggle toggle) {
    boolean on = toggle.getState();
    float w = toggle.getWidth(), h = toggle.getHeight();
    g.pushStyle();
    g.rectMode(CORNER);
    g.ellipseMode(CENTER);
    g.stroke(toggle.isMouseOver() ? color(255) : lerpColor(accent, color(30), 0.4));
    g.strokeWeight(1);
    g.fill(on ? accent : lerpColor(accent, color(20), 0.78));
    g.rect(0, 0, w, h, h / 2);
    g.noStroke();
    g.fill(on ? color(255) : color(190));
    g.ellipse(on ? w - h / 2 : h / 2, h / 2, h - 6, h - 6);
    g.fill(on ? color(15, 25, 30) : color(245));
    g.textAlign(CENTER, CENTER);
    g.textSize(11);
    g.text(label + (on ? " ON" : " OFF"), on ? (w - h) / 2 : (w + h) / 2, h / 2 - 1);
    g.popStyle();
  }
}

class Step {
  int intensity;
  float colorR, colorG, colorB;
  
  Step() {
    intensity = 0;
    colorR = 255;
    colorG = 255;
    colorB = 255;
  }
  
  Step(int i, float r, float g, float b) {
    intensity = i;
    colorR = r;
    colorG = g;
    colorB = b;
  }
}

class StepSequencer {
  ArrayList<Step> steps;
  int currentStep;
  boolean active;
  float bpm;
  long lastStepTime;
  
  StepSequencer() {
    steps = new ArrayList<Step>();
    currentStep = 0;
    active = false;
    bpm = 120;
    lastStepTime = millis();
  }
  
  void update() {
    if (!active || steps.isEmpty()) return;
    long now = millis();
    long stepDuration = (long)(60000.0 / bpm / 4);
    if (now - lastStepTime >= stepDuration) {
      currentStep = (currentStep + 1) % steps.size();
      lastStepTime = now;
    }
  }
  
  int getCurrentIntensity() {
    if (!active || steps.isEmpty()) return 0;
    return steps.get(currentStep).intensity;
  }
  
  color getCurrentColor() {
    if (!active || steps.isEmpty()) return color(255);
    Step s = steps.get(currentStep);
    return color(s.colorR, s.colorG, s.colorB);
  }
}

class ChannelState {
  int manualVal, fxMode, fxMin;
  float fxFreq, colorR, colorG, colorB, sequencerBpm;
  boolean isRGB, sequencerActive;
  ArrayList<Step> sequencerSteps;
  
  ChannelState() {}
  
  ChannelState(Channel ch) {
    manualVal = ch.manualVal;
    fxMode = ch.fxMode;
    fxFreq = ch.fxFreq;
    fxMin = ch.fxMin;
    isRGB = ch.isRGB;
    colorR = red(ch.baseColor);
    colorG = green(ch.baseColor);
    colorB = blue(ch.baseColor);
    sequencerActive = ch.sequencer.active;
    sequencerBpm = ch.sequencer.bpm;
    sequencerSteps = new ArrayList<Step>();
    for (Step s : ch.sequencer.steps) {
      sequencerSteps.add(new Step(s.intensity, s.colorR, s.colorG, s.colorB));
    }
  }
  
  void applyTo(Channel ch) {
    ch.manualVal = manualVal;
    ch.fxMode = fxMode;
    ch.fxFreq = fxFreq;
    ch.fxMin = fxMin;
    ch.isRGB = isRGB;
    ch.baseColor = color(colorR, colorG, colorB);
    ch.sequencer.active = sequencerActive;
    ch.sequencer.bpm = sequencerBpm;
    ch.sequencer.steps.clear();
    for (Step s : sequencerSteps) {
      ch.sequencer.steps.add(new Step(s.intensity, s.colorR, s.colorG, s.colorB));
    }
  }
  
  ChannelState interpolate(ChannelState o, float t) {
    ChannelState r = new ChannelState();
    r.manualVal = int(lerp(this.manualVal, o.manualVal, t));
    r.fxMode = (t < 0.5) ? this.fxMode : o.fxMode;
    r.fxFreq = lerp(this.fxFreq, o.fxFreq, t);
    r.fxMin = int(lerp(this.fxMin, o.fxMin, t));
    r.isRGB = (t < 0.5) ? this.isRGB : o.isRGB;
    r.colorR = lerp(this.colorR, o.colorR, t);
    r.colorG = lerp(this.colorG, o.colorG, t);
    r.colorB = lerp(this.colorB, o.colorB, t);
    r.sequencerActive = (t < 0.5) ? this.sequencerActive : o.sequencerActive;
    r.sequencerBpm = lerp(this.sequencerBpm, o.sequencerBpm, t);
    r.sequencerSteps = (t < 0.5) ? this.sequencerSteps : o.sequencerSteps;
    return r;
  }
}

class Scene {
  String name;
  ChannelState[] states;
  
  Scene(String n) {
    name = n;
    states = new ChannelState[nbChannels];
  }
  
  void capture() {
    for (int i = 0; i < nbChannels; i++) {
      states[i] = new ChannelState(allChannels.get(i));
    }
  }
  
  void apply() {
    for (int i = 0; i < nbChannels; i++) {
      states[i].applyTo(allChannels.get(i));
    }
  }
}

class Channel {
  String name;
  int id;
  boolean isRGB;
  int pinMono, pinR, pinG, pinB;
  color baseColor;
  int valR, valG, valB, value, manualVal, fxMode, fxMin;
  float fxFreq;
  StepSequencer sequencer;
  
  Channel(String n, int i) {
    name = n;
    id = i;
    isRGB = false;
    pinMono = 3;
    pinR = 3;
    pinG = 5;
    pinB = 6;
    baseColor = color(255);
    valR = 0;
    valG = 0;
    valB = 0;
    value = 0;
    manualVal = 0;
    fxMode = 0;
    fxMin = 0;
    fxFreq = 1.0;
    sequencer = new StepSequencer();
  }
}

ArrayList<Channel> allChannels = new ArrayList<Channel>();

final int FX_MANUAL = 0;
final int FX_STROBE = 1;
final int FX_FIRE = 2;
final int FX_PULSE = 3;
final int LEGACY_FX_SEQUENCER = 4;

void setup() {
  size(1600, 1000);
  surface.setTitle("Console Theatre");
  cp5 = new ControlP5(this);
  cp5.setAutoDraw(false);
  
  for (int i = 0; i < nbChannels; i++) {
    allChannels.add(new Channel("Tranche " + (i + 1), i));
  }
  
  createGUI();
  loadScenes();
  loadChannelConfig();
  updateGUIFromChannels();
  
  println("Scan des ports USB...");
  String foundPort = findArduinoPort();
  
  if (foundPort != null) {
    connectToSerial(foundPort);
  } else {
    println("Detection auto echouee.");
    nextPortScanTime = millis() + portScanInterval;
    cp5.get(ScrollableList.class, "portSelector").show();
  }
}

void draw() {
  background(30);
  long now = millis();
  pollSerialResponses();
  
  if (serialConnected && watchdogArmed && now - lastSerialResponseTime > connectionTimeout) {
    handleConnectionLoss();
  }
  
  if (!serialConnected && lastKnownPortName != null && now >= nextReconnectAttemptTime) {
    nextReconnectAttemptTime = now + reconnectInterval;
    connectToSerial(lastKnownPortName);
  }
  
  if (!serialConnected && lastKnownPortName == null && now >= nextPortScanTime) {
    nextPortScanTime = now + portScanInterval;
    String foundPort = findArduinoPort();
    if (foundPort != null) connectToSerial(foundPort);
  }
  
  for (int i = 0; i < nbChannels; i++) {
    allChannels.get(i).sequencer.update();
    updateChannelControls(i);
  }
  
  if (isTransitioning) {
    float t = constrain((millis() - transitionStartTime) / (float)transitionDuration, 0, 1);
    for (int i = 0; i < nbChannels; i++) {
      startStates[i].interpolate(targetStates[i], t).applyTo(allChannels.get(i));
    }
    updateGUIFromChannels();
    if (t >= 1) {
      isTransitioning = false;
    }
  }
  
  fill(255);
  textSize(24);
  text("CONSOLE THEATRE", 20, 35);
  
  fill(serialConnected ? color(100, 255, 100) : color(255, 100, 100));
  textSize(14);
  text("● " + (serialConnected ? "CONNECTE" : "DECONNECTE"), 20, 60);
  fill(220);
  text("SCENE : " + getCurrentSceneName(), 180, 60);
  textSize(12);
  text(cloneStatus, 510, 60);
  
  for (int i = 0; i < nbChannels; i++) {
    int x = 30 + i * 115;
    if (allChannels.get(i).isRGB) {
      color wheelColor = allChannels.get(i).baseColor;
      if (stepEditMode && i == selectedStepChannel && hasSelectedStep()) {
        Step step = allChannels.get(i).sequencer.steps.get(selectedStepIndex);
        wheelColor = color(step.colorR, step.colorG, step.colorB);
      }
      drawHSVWheel(x + 50, 815, 22, wheelColor);
    }
    drawStepSequencer(x, 875, i);
  }
  
  if (serialConnected && myPort != null) {
    if (now - lastHeartbeatTime > heartbeatInterval) {
      try {
        myPort.write("H\n");
      } catch (Exception e) {
        handleConnectionLoss();
      }
      lastHeartbeatTime = now;
    }
    
    if (serialConnected && myPort != null && now - lastSendTime > sendInterval) {
      for (int i = 0; i < nbChannels; i++) {
        Channel ch = allChannels.get(i);
        float eff = 1.0;
        float minN = ch.fxMin / 4095.0;
        
        if (ch.fxMode == FX_STROBE) {
          eff = (now % (long)(1000.0 / ch.fxFreq) < (500.0 / ch.fxFreq)) ? 1.0 : minN;
        } else if (ch.fxMode == FX_FIRE) {
          eff = lerp(minN, 1.0, noise(i * 100, frameCount * 0.01 * ch.fxFreq));
        } else if (ch.fxMode == FX_PULSE) {
          eff = lerp(minN, 1.0, (sin(frameCount * 0.05 * ch.fxFreq + i) + 1) / 2.0);
        }
        
        float master = (ch.sequencer.active ? ch.sequencer.getCurrentIntensity() : ch.manualVal) / 4095.0;
        float fin = eff * master;
        
        if (ch.isRGB) {
          color col = (ch.sequencer.active) ? ch.sequencer.getCurrentColor() : ch.baseColor;
          int vr = int((red(col) / 255.0) * 4095 * fin);
          int vg = int((green(col) / 255.0) * 4095 * fin);
          int vb = int((blue(col) / 255.0) * 4095 * fin);
          
          if (ch.valR != vr) {
            myPort.write("P," + ch.pinR + "," + vr + "\n");
            ch.valR = vr;
          }
          if (ch.valG != vg) {
            myPort.write("P," + ch.pinG + "," + vg + "\n");
            ch.valG = vg;
          }
          if (ch.valB != vb) {
            myPort.write("P," + ch.pinB + "," + vb + "\n");
            ch.valB = vb;
          }
        } else {
          int fv = int(4095 * fin);
          if (ch.value != fv) {
            myPort.write("P," + ch.pinMono + "," + fv + "\n");
            ch.value = fv;
          }
        }
      }
      lastSendTime = now;
    }
  }
  
  cp5.draw();
  drawSelectedSceneBorder();
}

void drawSelectedSceneBorder() {
  if (selectedSceneIndex < 0 || selectedSceneIndex >= scenes.size()) return;
  int sceneOffset = selectedSceneIndex - currentPage * scenesPerPage;
  if (sceneOffset < 0 || sceneOffset >= scenesPerPage) return;
  
  noFill();
  stroke(230, 40, 40);
  strokeWeight(3);
  rect(1198, 308 + sceneOffset * 40, 264, 39);
  noStroke();
}

void drawStepSequencer(int x, int y, int i) {
  Channel ch = allChannels.get(i);
  ArrayList<Step> steps = ch.sequencer.steps;
  int sz = 18, gap = 3, perRow = sequencerStepsPerRow;
  
  fill(ch.sequencer.active ? color(50, 50, 80) : color(40));
  noStroke();
  rect(x - 5, y - 5, perRow * (sz + gap) + 10, 60);
  
  fill(ch.sequencer.active ? color(0, 255, 0) : color(100));
  ellipse(x + perRow * (sz + gap) - 10, y - 10, 8, 8);
  
  int visibleSteps = min(steps.size(), maxSequencerSteps);
  for (int j = 0; j < visibleSteps; j++) {
    Step s = steps.get(j);
    float inten = s.intensity / 4095.0;
    color c = ch.isRGB ? color(s.colorR * inten, s.colorG * inten, s.colorB * inten) : color(255 * inten);
    fill(c);
    
    if (i == selectedStepChannel && j == selectedStepIndex) {
      stroke(0, 200, 255);
      strokeWeight(3);
    } else if (ch.sequencer.active && j == ch.sequencer.currentStep) {
      stroke(255, 255, 0);
      strokeWeight(3);
    } else {
      stroke(100);
      strokeWeight(1);
    }
    
    int r = j / perRow;
    int col = j % perRow;
    rect(x + col * (sz + gap), y + r * (sz + gap), sz, sz);
  }
  
  if (steps.size() < maxSequencerSteps) {
    int nj = visibleSteps;
    int nr = nj / perRow;
    int nc = nj % perRow;
    fill(80);
    stroke(150);
    strokeWeight(2);
    rect(x + nc * (sz + gap), y + nr * (sz + gap), sz, sz);
    
    stroke(255);
    strokeWeight(3);
    float cx = x + nc * (sz + gap) + sz / 2;
    float cy = y + nr * (sz + gap) + sz / 2;
    line(cx - 5, cy, cx + 5, cy);
    line(cx, cy - 5, cx, cy + 5);
  }
  
  noStroke();
}

void updateGUIFromChannels() {
  // Une synchronisation visuelle ne doit pas editer un pas ni relancer ses callbacks.
  cp5.setBroadcast(false);
  for (int i = 0; i < nbChannels; i++) {
    Channel ch = allChannels.get(i);
    cp5.get(Slider.class, "fader_" + i).setValue(ch.manualVal);
    cp5.get(DropdownList.class, "fx_" + i).setValue(ch.fxMode);
    
    updateChannelControls(i);
    cp5.get(Slider.class, "freq_" + i).setValue(ch.fxFreq);
    cp5.get(Slider.class, "min_" + i).setValue(ch.fxMin);
    cp5.get(Toggle.class, "rgb_" + i).setValue(ch.isRGB ? 1 : 0);
    cp5.get(Toggle.class, "seq_" + i).setBroadcast(false).setValue(ch.sequencer.active).setBroadcast(true);
    cp5.get(Slider.class, "bpm_" + i).setValue(ch.sequencer.bpm);
    cp5.get(Textfield.class, "pinMono_" + i).setText(str(ch.pinMono));
    cp5.get(Textfield.class, "pinR_" + i).setText(str(ch.pinR));
    cp5.get(Textfield.class, "pinG_" + i).setText(str(ch.pinG));
    cp5.get(Textfield.class, "pinB_" + i).setText(str(ch.pinB));
    cp5.get(Textfield.class, "name_" + i).setText(ch.name);
    syncPinControls(i);
  }
  cp5.setBroadcast(true);
}

void cloneChannel(int index) {
  if (index < 0 || index >= nbChannels) return;
  if (index == cloneSourceIndex) {
    clearChannelClipboard();
    return;
  }
  if (isTransitioning) {
    cloneStatus = "CLONER : attendre la fin de la transition";
    return;
  }
  if (channelClipboard == null) {
    channelClipboard = new ChannelState(allChannels.get(index));
    cloneSourceIndex = index;
    cloneStatus = "Tranche " + (index + 1) + " copiee : choisir COLLER (remplace la destination)";
    for (int i = 0; i < nbChannels; i++) {
      cp5.get(Button.class, "clone_" + i).setLabel(i == index ? "ANNULER" : "COLLER ICI");
    }
    return;
  }
  Channel destination = allChannels.get(index);
  channelClipboard.applyTo(destination);
  destination.sequencer.currentStep = 0;
  destination.sequencer.lastStepTime = millis();
  if (selectedStepChannel == index) {
    selectedStepChannel = -1;
    selectedStepIndex = -1;
    stepEditMode = false;
  }
  lastClickedStepChannel = -1;
  lastClickedStepIndex = -1;
  destination.value = destination.valR = destination.valG = destination.valB = -1;
  updateGUIFromChannels();
  String message = "Tranche " + (cloneSourceIndex + 1) + " clonee vers " + (index + 1);
  clearChannelClipboard();
  cloneStatus = message;
}

void clearChannelClipboard() {
  channelClipboard = null;
  cloneSourceIndex = -1;
  cloneStatus = "CLONER : choisir une tranche source";
  for (int i = 0; i < nbChannels; i++) cp5.get(Button.class, "clone_" + i).setLabel("CLONER");
}

void updateChannelControls(int i) {
  Channel ch = allChannels.get(i);
  boolean showFX = ch.fxMode == FX_STROBE || ch.fxMode == FX_FIRE || ch.fxMode == FX_PULSE;
  cp5.get(Slider.class, "freq_" + i).setVisible(showFX);
  cp5.get(Slider.class, "min_" + i).setVisible(showFX);
  cp5.get(Slider.class, "bpm_" + i).setVisible(ch.sequencer.active);
}

String getCurrentSceneName() {
  if (activeSceneIndex >= 0 && activeSceneIndex < scenes.size()) return scenes.get(activeSceneIndex).name;
  return "AUCUNE";
}

void drawHSVWheel(float cx, float cy, float rad, color sel) {
  noStroke();
  for (float r = 0; r < rad; r += 1) {
    for (float a = 0; a < 360; a += 3) {
      float radA = radians(a);
      float x = cx + r * cos(radA);
      float y = cy + r * sin(radA);
      fill(hsvToRgb(a / 360.0, r / rad, 1.0));
      rect(x, y, 2, 2);
    }
  }
  fill(sel);
  stroke(255);
  strokeWeight(2);
  ellipse(cx, cy, 14, 14);
  noStroke();
}

color hsvToRgb(float h, float s, float v) {
  int i = int(h * 6);
  float f = h * 6 - i;
  float p = v * (1 - s);
  float q = v * (1 - f * s);
  float t = v * (1 - (1 - f) * s);
  float r = 0, g = 0, b = 0;
  
  switch (i % 6) {
    case 0: r = v; g = t; b = p; break;
    case 1: r = q; g = v; b = p; break;
    case 2: r = p; g = v; b = t; break;
    case 3: r = p; g = q; b = v; break;
    case 4: r = t; g = p; b = v; break;
    case 5: r = v; g = p; b = q; break;
  }
  
  return color(r * 255, g * 255, b * 255);
}

void startStepEditing(int channelIndex, int stepIndex) {
  selectedStepChannel = channelIndex;
  selectedStepIndex = stepIndex;
  stepEditMode = true;
  Step step = allChannels.get(channelIndex).sequencer.steps.get(stepIndex);
  allChannels.get(channelIndex).manualVal = step.intensity;
  cp5.get(Slider.class, "fader_" + channelIndex).setValue(step.intensity);
}

boolean hasSelectedStep() {
  if (selectedStepChannel < 0 || selectedStepChannel >= nbChannels) return false;
  ArrayList<Step> steps = allChannels.get(selectedStepChannel).sequencer.steps;
  return selectedStepIndex >= 0 && selectedStepIndex < steps.size();
}

void mousePressed() {
  for (int i = 0; i < nbChannels; i++) {
    if (allChannels.get(i).isRGB) {
      float cx = 30 + i * 115 + 50;
      float cy = 815;
      if (dist(mouseX, mouseY, cx, cy) < 22) {
        float a = atan2(mouseY - cy, mouseX - cx);
        if (a < 0) a += TWO_PI;
        color selectedColor = hsvToRgb(a / TWO_PI, dist(mouseX, mouseY, cx, cy) / 22, 1.0);
        if (stepEditMode && i == selectedStepChannel && hasSelectedStep()) {
          Step step = allChannels.get(i).sequencer.steps.get(selectedStepIndex);
          step.colorR = red(selectedColor);
          step.colorG = green(selectedColor);
          step.colorB = blue(selectedColor);
        } else {
          allChannels.get(i).baseColor = selectedColor;
        }
      }
    }
  }
  
  for (int i = 0; i < nbChannels; i++) {
    int x = 30 + i * 115;
    int y = 875;
    int sz = 18, gap = 3, perRow = sequencerStepsPerRow;
    ArrayList<Step> steps = allChannels.get(i).sequencer.steps;
    
    if (mouseX >= x - 5 && mouseX < x + perRow * (sz + gap) + 5 && mouseY >= y - 5 && mouseY < y + 60) {
      boolean clickedOnStep = false;
      
      int visibleSteps = min(steps.size(), maxSequencerSteps);
      for (int j = 0; j < visibleSteps; j++) {
        int r = j / perRow;
        int c = j % perRow;
        
        if (mouseX >= x + c * (sz + gap) && mouseX < x + (c + 1) * (sz + gap) && 
            mouseY >= y + r * (sz + gap) && mouseY < y + (r + 1) * (sz + gap)) {
          
          if (mouseButton == LEFT) {
            selectedStepChannel = i;
            selectedStepIndex = j;
            boolean isDoubleClick = lastClickedStepChannel == i && lastClickedStepIndex == j && millis() - lastStepClickTime < 350;
            if (isDoubleClick) startStepEditing(i, j);
            else stepEditMode = false;
            lastStepClickTime = millis();
            lastClickedStepChannel = i;
            lastClickedStepIndex = j;
          } else if (mouseButton == RIGHT) {
            steps.remove(j);
            if (selectedStepChannel == i) {
              selectedStepIndex = -1;
              stepEditMode = false;
            }
          }
          clickedOnStep = true;
          break;
        }
      }
      
      if (!clickedOnStep && mouseButton == LEFT && steps.size() < maxSequencerSteps) {
        color col = allChannels.get(i).baseColor;
        steps.add(new Step(2048, red(col), green(col), blue(col)));
        selectedStepChannel = i;
        selectedStepIndex = steps.size() - 1;
        stepEditMode = false;
      }
    }
  }
  
}

String findArduinoPort() {
  String[] ports = Serial.list();
  for (int i = 0; i < ports.length; i++) {
    String portName = ports[i];
    Serial testPort = null;
    try {
      testPort = new Serial(this, portName, 115200);
      testPort.clear();
      delay(1800);
      String startupResponse = testPort.readString();
      testPort.write("H\n");
      delay(300);
      String heartbeatResponse = testPort.readString();
      testPort.stop();
      boolean hasStartupBanner = startupResponse != null && startupResponse.contains("THEATRE_CONSOLE");
      boolean hasHeartbeat = heartbeatResponse != null && trim(heartbeatResponse).endsWith("H");
      if (hasStartupBanner || hasHeartbeat) {
        println("Arduino trouve : " + portName);
        return portName;
      }
    } catch (Exception e) {
      if (testPort != null) testPort.stop();
    }
  }
  return null;
}

void connectToSerial(String portName) {
  try {
    myPort = new Serial(this, portName, 115200);
    serialConnected = true;
    connectedPortName = portName;
    lastKnownPortName = portName;
    watchdogArmed = false;
    lastSerialResponseTime = millis();
    println("Connecte a " + portName);
    if (connectionFailSafeActive) resumeLastScene();
  } catch (Exception e) {
    println("Erreur : " + e.getMessage());
    serialConnected = false;
    myPort = null;
  }
}

void pollSerialResponses() {
  if (!serialConnected || myPort == null || myPort.available() == 0) return;
  
  String response = myPort.readStringUntil('\n');
  if (response != null && trim(response).endsWith("H")) {
    lastSerialResponseTime = millis();
    watchdogArmed = true;
  }
}

void handleConnectionLoss() {
  if (connectionFailSafeActive) return;
  
  println("Perte de connexion : BLACKOUT de securite");
  connectionFailSafeActive = true;
  sceneToResumeIndex = activeSceneIndex;
  applyBlackout(false);
  invalidateOutputCache();
  serialConnected = false;
  lastKnownPortName = connectedPortName;
  nextReconnectAttemptTime = millis() + reconnectInterval;
  connectedPortName = "Aucun";
  watchdogArmed = false;
  
  if (myPort != null) {
    try {
      myPort.stop();
    } catch (Exception e) {
    }
    myPort = null;
  }
  cp5.get(ScrollableList.class, "portSelector").show();
}

void resumeLastScene() {
  connectionFailSafeActive = false;
  if (sceneToResumeIndex >= 0 && sceneToResumeIndex < scenes.size()) {
    println("Reprise de la scene : " + scenes.get(sceneToResumeIndex).name);
    launchScene(sceneToResumeIndex, true);
  }
  sceneToResumeIndex = -1;
}

void createGUI() {
  cp5.setBroadcast(false);
  for (int i = 0; i < nbChannels; i++) {
    int x = 30 + i * 115;
    
     cp5.addDropdownList("fx_" + i).setPosition(x, 100).setSize(80, 120).setItemHeight(20).setBarHeight(20)
       .addItem("MAN", FX_MANUAL).addItem("STR", FX_STROBE).addItem("FEU", FX_FIRE).addItem("PUL", FX_PULSE).setValue(FX_MANUAL).setOpen(false);
    
    cp5.addToggle("rgb_" + i).setPosition(x, 226).setSize(100, 24).setValue(false).setLabel("").setView(new ChipView("RGB", color(0, 200, 255)));
    
    cp5.addToggle("seq_" + i).setPosition(x, 255).setSize(100, 24).setValue(false).setLabel("").setView(new ChipView("SEQ", color(255, 200, 0)));
    cp5.addButton("clone_" + i).setPosition(x, 970).setSize(100, 24).setLabel("CLONER");
    
    cp5.addSlider("freq_" + i).setPosition(x, 285).setSize(100, 20).setRange(0.1, 10.0).setValue(1.0).setDecimalPrecision(1).setLabel("FREQ");
    
    cp5.addSlider("min_" + i).setPosition(x, 315).setSize(100, 20).setRange(0, 4095).setValue(0).setDecimalPrecision(0).setLabel("MIN");
    
    cp5.addSlider("bpm_" + i).setPosition(x, 940).setSize(100, 20).setRange(60, 240).setValue(120).setDecimalPrecision(0).setLabel("BPM").setVisible(false);
    
    cp5.addSlider("fader_" + i).setPosition(x + 10, 345).setSize(80, 360).setRange(0, 4095).setValue(0).setDecimalPrecision(0).setLabel("");
    
    cp5.addTextfield("name_" + i).setPosition(x, 720).setSize(100, 20).setText(allChannels.get(i).name).setLabel("").setAutoClear(false);
    
    cp5.addTextfield("pinMono_" + i).setPosition(x, 748).setSize(100, 20).setText(str(3)).setLabel("PIN").setAutoClear(false);
    
    cp5.addTextfield("pinR_" + i).setPosition(x, 748).setSize(30, 20).setText(str(3)).setLabel("R").setAutoClear(false).hide();
    
    cp5.addTextfield("pinG_" + i).setPosition(x + 35, 748).setSize(30, 20).setText(str(5)).setLabel("G").setAutoClear(false).hide();
    
    cp5.addTextfield("pinB_" + i).setPosition(x + 70, 748).setSize(30, 20).setText(str(6)).setLabel("B").setAutoClear(false).hide();
  }
  
  int px = 1200;
  
  cp5.addTextlabel("sceneTitle").setText("SCENES").setPosition(px, 90);
  
  cp5.addButton("newScene").setPosition(px, 120).setSize(60, 40).setColorBackground(color(50, 120, 200)).setLabel("+ NEW");
  
  cp5.addButton("recScene").setPosition(px + 65, 120).setSize(60, 40).setColorBackground(color(200, 150, 50)).setLabel("REC");
  
  cp5.addButton("goScene").setPosition(px + 130, 120).setSize(60, 40).setColorBackground(color(50, 200, 50)).setLabel("GO");
  
  cp5.addButton("deleteScene").setPosition(px + 195, 120).setSize(65, 40).setColorBackground(color(150, 50, 50)).setLabel("DEL");
  
  cp5.addButton("moveSceneUp").setPosition(px, 170).setSize(125, 25).setLabel("MONTER");
  cp5.addButton("moveSceneDown").setPosition(px + 135, 170).setSize(125, 25).setLabel("DESCENDRE");

  cp5.addButton("prevPage").setPosition(px, 650).setSize(40, 30).setLabel("<").hide();
  
  cp5.addButton("nextPage").setPosition(px + 220, 650).setSize(40, 30).setLabel(">").hide();
  
  cp5.addSlider("fadeTimeSlider").setPosition(px, 210).setSize(260, 30).setRange(0, 10000).setValue(2000).setDecimalPrecision(0).setLabel("FADE TIME (ms)");
  
  cp5.addTextfield("sceneName").setPosition(px, 260).setSize(200, 25).setText("Nouvelle Scene").setLabel("Nom :").setAutoClear(false);
  
  cp5.addButton("clearName").setPosition(px + 210, 260).setSize(50, 25).setLabel("CLR").setColorBackground(color(80));
  
  cp5.addButton("blackout").setPosition(px, 900).setSize(260, 60).setColorBackground(color(200, 0, 0)).setLabel("BLACKOUT");
  
  cp5.addScrollableList("portSelector").setPosition(px, 700).setSize(260, 180).setBarHeight(20).setItemHeight(20).addItems(Serial.list()).setType(ScrollableList.LIST).hide();
  cp5.setBroadcast(true);
}

void refreshSceneButtons() {
  for (Button b : sceneButtons) {
    b.remove();
  }
  sceneButtons.clear();
  
  int px = 1200;
  int sy = 310;
  int bh = 35;
  int sp = 5;
  int si = currentPage * scenesPerPage;
  int ei = min(si + scenesPerPage, scenes.size());
  
  color[] sc = {
    color(100, 150, 200), color(150, 100, 200), color(200, 100, 150), color(200, 150, 100),
    color(150, 200, 100), color(100, 200, 150), color(180, 120, 180), color(120, 180, 180)
  };
  
  for (int i = si; i < ei; i++) {
    int d = i - si;
    String label = scenes.get(i).name;
    
    if (i == selectedSceneIndex) {
      label = "▶ " + label;
    }
    
    Button b = cp5.addButton("scene_" + d).setPosition(px, sy + d * (bh + sp)).setSize(260, bh)
       .setLabel(label)
       .setColorBackground(sc[d % 8])
       .setColorForeground(color(red(sc[d % 8]) + 30, green(sc[d % 8]) + 30, blue(sc[d % 8]) + 30))
       .setColorActive(color(red(sc[d % 8]) + 50, green(sc[d % 8]) + 50, blue(sc[d % 8]) + 50));
    
    if (i == selectedSceneIndex) {
      b.setColorBackground(sc[d % 8]);
      b.setColorForeground(color(red(sc[d % 8]) + 30, green(sc[d % 8]) + 30, blue(sc[d % 8]) + 30));
      b.setColorActive(color(red(sc[d % 8]) + 50, green(sc[d % 8]) + 50, blue(sc[d % 8]) + 50));
      b.getCaptionLabel().setColor(color(255));
    }
    
    sceneButtons.add(b);
  }
  
  if (scenes.size() > scenesPerPage) {
    cp5.get(Button.class, "prevPage").show();
    cp5.get(Button.class, "nextPage").show();
  } else {
    cp5.get(Button.class, "prevPage").hide();
    cp5.get(Button.class, "nextPage").hide();
  }
}

public void moveSceneUp() {
  moveSelectedScene(-1);
}

public void moveSceneDown() {
  moveSelectedScene(1);
}

void moveSelectedScene(int direction) {
  int sourceIndex = selectedSceneIndex;
  int destinationIndex = sourceIndex + direction;
  if (sourceIndex < 0 || sourceIndex >= scenes.size() || destinationIndex < 0 || destinationIndex >= scenes.size()) return;
  if (direction != -1 && direction != 1) return;

  Scene moved = scenes.get(sourceIndex);
  scenes.set(sourceIndex, scenes.get(destinationIndex));
  scenes.set(destinationIndex, moved);

  // Keep playback and reconnection attached to the same scene objects.
  if (activeSceneIndex == sourceIndex) activeSceneIndex = destinationIndex;
  else if (activeSceneIndex == destinationIndex) activeSceneIndex = sourceIndex;
  if (sceneToResumeIndex == sourceIndex) sceneToResumeIndex = destinationIndex;
  else if (sceneToResumeIndex == destinationIndex) sceneToResumeIndex = sourceIndex;

  selectedSceneIndex = destinationIndex;
  currentPage = destinationIndex / scenesPerPage;
  refreshSceneButtons();
  saveScenes();
}

public void newScene() {
  String n = cp5.get(Textfield.class, "sceneName").getText();
  if (n.isEmpty() || n.equals("Nouvelle Scene")) n = "Scene " + (scenes.size() + 1);
  Scene s = new Scene(n);
  s.capture();
  scenes.add(s);
  selectedSceneIndex = scenes.size() - 1;
  currentPage = selectedSceneIndex / scenesPerPage;
  refreshSceneButtons();
  saveScenes();
  println("Nouvelle scene : " + n);
}

public void recScene() {
  if (selectedSceneIndex < 0 || selectedSceneIndex >= scenes.size()) return;
  String n = cp5.get(Textfield.class, "sceneName").getText();
  Scene s = scenes.get(selectedSceneIndex);
  if (!n.isEmpty() && !n.equals("Nouvelle Scene") && !n.equals(s.name)) s.name = n;
  s.capture();
  refreshSceneButtons();
  saveScenes();
  println("Scene mise a jour : " + s.name);
}

public void goScene() {
  launchScene(selectedSceneIndex, false);
}

void launchScene(int idx, boolean inst) {
  if (idx < 0 || idx >= scenes.size()) return;
  activeSceneIndex = idx;
  startStates = new ChannelState[nbChannels];
  targetStates = scenes.get(idx).states;
  for (int i = 0; i < nbChannels; i++) {
    startStates[i] = new ChannelState(allChannels.get(i));
  }
  if (inst) {
    scenes.get(idx).apply();
    updateGUIFromChannels();
    println("Transition instantanee");
  } else {
    transitionDuration = int(cp5.get(Slider.class, "fadeTimeSlider").getValue());
    if (transitionDuration == 0) {
      scenes.get(idx).apply();
      updateGUIFromChannels();
    } else {
      transitionStartTime = millis();
      isTransitioning = true;
      println("Transition " + transitionDuration + "ms");
    }
  }
}

public void deleteScene() {
  if (selectedSceneIndex < 0 || selectedSceneIndex >= scenes.size()) return;
  scenes.remove(selectedSceneIndex);
  selectedSceneIndex = -1;
  if (currentPage > 0 && currentPage * scenesPerPage >= scenes.size()) currentPage--;
  refreshSceneButtons();
  saveScenes();
  println("Scene supprimee");
}

public void clearName() {
  cp5.get(Textfield.class, "sceneName").setText("");
  cp5.get(Textfield.class, "sceneName").setFocus(true);
}

public void prevPage() {
  if (currentPage > 0) {
    currentPage--;
    refreshSceneButtons();
  }
}

public void nextPage() {
  if ((currentPage + 1) * scenesPerPage < scenes.size()) {
    currentPage++;
    refreshSceneButtons();
  }
}

public void scene_0(int v) { selectScene(currentPage * scenesPerPage + 0); }
public void scene_1(int v) { selectScene(currentPage * scenesPerPage + 1); }
public void scene_2(int v) { selectScene(currentPage * scenesPerPage + 2); }
public void scene_3(int v) { selectScene(currentPage * scenesPerPage + 3); }
public void scene_4(int v) { selectScene(currentPage * scenesPerPage + 4); }
public void scene_5(int v) { selectScene(currentPage * scenesPerPage + 5); }
public void scene_6(int v) { selectScene(currentPage * scenesPerPage + 6); }
public void scene_7(int v) { selectScene(currentPage * scenesPerPage + 7); }

void selectScene(int idx) {
  if (idx >= 0 && idx < scenes.size()) {
    selectedSceneIndex = idx;
    println("Selection : " + scenes.get(idx).name);
    if (keyPressed && keyCode == SHIFT) launchScene(idx, true);
    refreshSceneButtons();
  }
}

void saveScenes() {
  JSONArray a = new JSONArray();
  for (Scene s : scenes) {
    JSONObject j = new JSONObject();
    j.setString("name", s.name);
    JSONArray st = new JSONArray();
    for (int i = 0; i < nbChannels; i++) {
      ChannelState cs = s.states[i];
      JSONObject c = new JSONObject();
      c.setInt("m", cs.manualVal);
      c.setInt("fx", cs.fxMode);
      c.setFloat("f", cs.fxFreq);
      c.setInt("min", cs.fxMin);
      c.setBoolean("rgb", cs.isRGB);
      c.setFloat("cr", cs.colorR);
      c.setFloat("cg", cs.colorG);
      c.setFloat("cb", cs.colorB);
      c.setBoolean("sa", cs.sequencerActive);
      c.setFloat("bpm", cs.sequencerBpm);
      JSONArray ss = new JSONArray();
      for (int k = 0; k < cs.sequencerSteps.size(); k++) {
        JSONObject sk = new JSONObject();
        sk.setInt("i", cs.sequencerSteps.get(k).intensity);
        sk.setFloat("r", cs.sequencerSteps.get(k).colorR);
        sk.setFloat("g", cs.sequencerSteps.get(k).colorG);
        sk.setFloat("b", cs.sequencerSteps.get(k).colorB);
        ss.setJSONObject(k, sk);
      }
      c.setJSONArray("steps", ss);
      st.setJSONObject(i, c);
    }
    j.setJSONArray("states", st);
    a.append(j);
  }
  saveJSONArray(a, "scenes.json");
}

void loadScenes() {
  try {
    JSONArray a = loadJSONArray("scenes.json");
    scenes.clear();
    for (int i = 0; i < a.size(); i++) {
      JSONObject j = a.getJSONObject(i);
      Scene s = new Scene(j.getString("name"));
      JSONArray st = j.getJSONArray("states");
      for (int k = 0; k < nbChannels; k++) {
        JSONObject c = st.getJSONObject(k);
        ChannelState cs = new ChannelState();
        cs.manualVal = c.getInt("m");
        cs.fxMode = c.getInt("fx");
        // Old SEQ scenes now use the independent sequencer without an effect.
        if (cs.fxMode == LEGACY_FX_SEQUENCER) cs.fxMode = FX_MANUAL;
        cs.fxFreq = c.getFloat("f");
        cs.fxMin = c.getInt("min");
        cs.isRGB = c.getBoolean("rgb");
        cs.colorR = c.getFloat("cr");
        cs.colorG = c.getFloat("cg");
        cs.colorB = c.getFloat("cb");
        cs.sequencerActive = c.getBoolean("sa");
        cs.sequencerBpm = c.getFloat("bpm");
        cs.sequencerSteps = new ArrayList<Step>();
        JSONArray ss = c.getJSONArray("steps");
        for (int m = 0; m < ss.size(); m++) {
          JSONObject sk = ss.getJSONObject(m);
          cs.sequencerSteps.add(new Step(sk.getInt("i"), sk.getFloat("r"), sk.getFloat("g"), sk.getFloat("b")));
        }
        s.states[k] = cs;
      }
      scenes.add(s);
    }
    refreshSceneButtons();
    println(scenes.size() + " scenes");
  } catch (Exception e) {
    println("Aucun fichier");
  }
}

void loadChannelConfig() {
  try {
    JSONObject config = loadJSONObject("channelConfig.json");
    JSONArray channels = config.getJSONArray("channels");
    for (int i = 0; i < min(nbChannels, channels.size()); i++) {
      JSONObject savedChannel = channels.getJSONObject(i);
      Channel ch = allChannels.get(i);
      ch.name = savedChannel.getString("name");
      ch.pinMono = savedChannel.getInt("pm");
      ch.pinR = savedChannel.getInt("pr");
      ch.pinG = savedChannel.getInt("pg");
      ch.pinB = savedChannel.getInt("pb");
    }
    println("Configuration des tranches chargee");
  } catch (Exception e) {
    try {
      JSONArray savedScenes = loadJSONArray("scenes.json");
      if (savedScenes.size() > 0) {
        JSONArray savedStates = savedScenes.getJSONObject(0).getJSONArray("states");
        for (int i = 0; i < min(nbChannels, savedStates.size()); i++) {
          JSONObject savedChannel = savedStates.getJSONObject(i);
          Channel ch = allChannels.get(i);
          if (savedChannel.hasKey("name")) ch.name = savedChannel.getString("name");
          if (savedChannel.hasKey("pm")) ch.pinMono = savedChannel.getInt("pm");
          if (savedChannel.hasKey("pr")) ch.pinR = savedChannel.getInt("pr");
          if (savedChannel.hasKey("pg")) ch.pinG = savedChannel.getInt("pg");
          if (savedChannel.hasKey("pb")) ch.pinB = savedChannel.getInt("pb");
        }
      }
    } catch (Exception ignored) {
    }
    saveChannelConfig();
    println("Configuration des tranches par defaut");
  }
}

void saveChannelConfig() {
  JSONObject config = new JSONObject();
  JSONArray channels = new JSONArray();
  for (int i = 0; i < nbChannels; i++) {
    Channel ch = allChannels.get(i);
    JSONObject savedChannel = new JSONObject();
    savedChannel.setString("name", ch.name);
    savedChannel.setInt("pm", ch.pinMono);
    savedChannel.setInt("pr", ch.pinR);
    savedChannel.setInt("pg", ch.pinG);
    savedChannel.setInt("pb", ch.pinB);
    channels.setJSONObject(i, savedChannel);
  }
  config.setJSONArray("channels", channels);
  saveJSONObject(config, "channelConfig.json");
}

public void controlEvent(ControlEvent e) {
  if (e.isController() && e.getName().startsWith("clone_")) {
    cloneChannel(int(e.getName().substring(6)));
    return;
  }
  if (e.isGroup() && e.getName().equals("portSelector")) {
    connectToSerial(e.getGroup().getValueLabel().getText());
    e.getGroup().hide();
  }
  if (e.isGroup() && e.getName().startsWith("fx_")) {
    int idx = int(e.getName().substring(3));
    int m = (int) e.getGroup().getValue();
    Channel ch = allChannels.get(idx);
    ch.fxMode = m;
    
    updateChannelControls(idx);
  }
}

public void name_0(String s) { setChannelName(0, s); }
public void name_1(String s) { setChannelName(1, s); }
public void name_2(String s) { setChannelName(2, s); }
public void name_3(String s) { setChannelName(3, s); }
public void name_4(String s) { setChannelName(4, s); }
public void name_5(String s) { setChannelName(5, s); }
public void name_6(String s) { setChannelName(6, s); }
public void name_7(String s) { setChannelName(7, s); }
public void name_8(String s) { setChannelName(8, s); }
public void name_9(String s) { setChannelName(9, s); }

void setChannelName(int i, String name) {
  String trimmedName = trim(name);
  if (!trimmedName.isEmpty()) {
    allChannels.get(i).name = trimmedName;
    saveChannelConfig();
  }
}

public void rgb_0(boolean v) { toggleRGB(0, v); }
public void rgb_1(boolean v) { toggleRGB(1, v); }
public void rgb_2(boolean v) { toggleRGB(2, v); }
public void rgb_3(boolean v) { toggleRGB(3, v); }
public void rgb_4(boolean v) { toggleRGB(4, v); }
public void rgb_5(boolean v) { toggleRGB(5, v); }
public void rgb_6(boolean v) { toggleRGB(6, v); }
public void rgb_7(boolean v) { toggleRGB(7, v); }
public void rgb_8(boolean v) { toggleRGB(8, v); }
public void rgb_9(boolean v) { toggleRGB(9, v); }

void toggleRGB(int i, boolean v) {
  allChannels.get(i).isRGB = v;
  syncPinControls(i);
}

void syncPinControls(int i) {
  boolean isRGB = allChannels.get(i).isRGB;
  String s = "_" + i;
  if (isRGB) {
    cp5.get(Textfield.class, "pinMono" + s).hide();
    cp5.get(Textfield.class, "pinR" + s).show();
    cp5.get(Textfield.class, "pinG" + s).show();
    cp5.get(Textfield.class, "pinB" + s).show();
  } else {
    cp5.get(Textfield.class, "pinMono" + s).show();
    cp5.get(Textfield.class, "pinR" + s).hide();
    cp5.get(Textfield.class, "pinG" + s).hide();
    cp5.get(Textfield.class, "pinB" + s).hide();
  }
}

public void seq_0(boolean v) { toggleSeq(0, v); }
public void seq_1(boolean v) { toggleSeq(1, v); }
public void seq_2(boolean v) { toggleSeq(2, v); }
public void seq_3(boolean v) { toggleSeq(3, v); }
public void seq_4(boolean v) { toggleSeq(4, v); }
public void seq_5(boolean v) { toggleSeq(5, v); }
public void seq_6(boolean v) { toggleSeq(6, v); }
public void seq_7(boolean v) { toggleSeq(7, v); }
public void seq_8(boolean v) { toggleSeq(8, v); }
public void seq_9(boolean v) { toggleSeq(9, v); }

void toggleSeq(int i, boolean v) {
  Channel ch = allChannels.get(i);
  if (v && !ch.sequencer.active) {
    if (ch.sequencer.steps.isEmpty()) {
      ch.sequencer.steps.add(new Step(4095, red(ch.baseColor), green(ch.baseColor), blue(ch.baseColor)));
    }
    ch.sequencer.currentStep = 0;
    ch.sequencer.lastStepTime = millis();
  }
  ch.sequencer.active = v;
  if (!v && stepEditMode && selectedStepChannel == i) stepEditMode = false;
  updateChannelControls(i);
  println("Tranche " + i + " : Sequenceur " + (v ? "ACTIVE" : "DESACTIVE"));
}

public void bpm_0(float v) { allChannels.get(0).sequencer.bpm = v; }
public void bpm_1(float v) { allChannels.get(1).sequencer.bpm = v; }
public void bpm_2(float v) { allChannels.get(2).sequencer.bpm = v; }
public void bpm_3(float v) { allChannels.get(3).sequencer.bpm = v; }
public void bpm_4(float v) { allChannels.get(4).sequencer.bpm = v; }
public void bpm_5(float v) { allChannels.get(5).sequencer.bpm = v; }
public void bpm_6(float v) { allChannels.get(6).sequencer.bpm = v; }
public void bpm_7(float v) { allChannels.get(7).sequencer.bpm = v; }
public void bpm_8(float v) { allChannels.get(8).sequencer.bpm = v; }
public void bpm_9(float v) { allChannels.get(9).sequencer.bpm = v; }

public void fx_0(int v) { allChannels.get(0).fxMode = v; }
public void fx_1(int v) { allChannels.get(1).fxMode = v; }
public void fx_2(int v) { allChannels.get(2).fxMode = v; }
public void fx_3(int v) { allChannels.get(3).fxMode = v; }
public void fx_4(int v) { allChannels.get(4).fxMode = v; }
public void fx_5(int v) { allChannels.get(5).fxMode = v; }
public void fx_6(int v) { allChannels.get(6).fxMode = v; }
public void fx_7(int v) { allChannels.get(7).fxMode = v; }
public void fx_8(int v) { allChannels.get(8).fxMode = v; }
public void fx_9(int v) { allChannels.get(9).fxMode = v; }

public void fader_0(int v) { setFaderValue(0, v); }
public void fader_1(int v) { setFaderValue(1, v); }
public void fader_2(int v) { setFaderValue(2, v); }
public void fader_3(int v) { setFaderValue(3, v); }
public void fader_4(int v) { setFaderValue(4, v); }
public void fader_5(int v) { setFaderValue(5, v); }
public void fader_6(int v) { setFaderValue(6, v); }
public void fader_7(int v) { setFaderValue(7, v); }
public void fader_8(int v) { setFaderValue(8, v); }
public void fader_9(int v) { setFaderValue(9, v); }

void setFaderValue(int i, int value) {
  allChannels.get(i).manualVal = value;
  if (stepEditMode && selectedStepChannel == i && hasSelectedStep()) {
    allChannels.get(i).sequencer.steps.get(selectedStepIndex).intensity = value;
  }
  check(i);
}

void check(int i) {
  if (allChannels.get(i).manualVal < allChannels.get(i).fxMin) {
    allChannels.get(i).fxMin = allChannels.get(i).manualVal;
    cp5.get(Slider.class, "min_" + i).setValue(allChannels.get(i).fxMin);
  }
}

public void freq_0(float v) { allChannels.get(0).fxFreq = v; }
public void freq_1(float v) { allChannels.get(1).fxFreq = v; }
public void freq_2(float v) { allChannels.get(2).fxFreq = v; }
public void freq_3(float v) { allChannels.get(3).fxFreq = v; }
public void freq_4(float v) { allChannels.get(4).fxFreq = v; }
public void freq_5(float v) { allChannels.get(5).fxFreq = v; }
public void freq_6(float v) { allChannels.get(6).fxFreq = v; }
public void freq_7(float v) { allChannels.get(7).fxFreq = v; }
public void freq_8(float v) { allChannels.get(8).fxFreq = v; }
public void freq_9(float v) { allChannels.get(9).fxFreq = v; }

public void min_0(int v) { allChannels.get(0).fxMin = constrain(v, 0, allChannels.get(0).manualVal); }
public void min_1(int v) { allChannels.get(1).fxMin = constrain(v, 0, allChannels.get(1).manualVal); }
public void min_2(int v) { allChannels.get(2).fxMin = constrain(v, 0, allChannels.get(2).manualVal); }
public void min_3(int v) { allChannels.get(3).fxMin = constrain(v, 0, allChannels.get(3).manualVal); }
public void min_4(int v) { allChannels.get(4).fxMin = constrain(v, 0, allChannels.get(4).manualVal); }
public void min_5(int v) { allChannels.get(5).fxMin = constrain(v, 0, allChannels.get(5).manualVal); }
public void min_6(int v) { allChannels.get(6).fxMin = constrain(v, 0, allChannels.get(6).manualVal); }
public void min_7(int v) { allChannels.get(7).fxMin = constrain(v, 0, allChannels.get(7).manualVal); }
public void min_8(int v) { allChannels.get(8).fxMin = constrain(v, 0, allChannels.get(8).manualVal); }
public void min_9(int v) { allChannels.get(9).fxMin = constrain(v, 0, allChannels.get(9).manualVal); }

public void pinMono_0(String s) { pin(0, s, "m"); }
public void pinMono_1(String s) { pin(1, s, "m"); }
public void pinMono_2(String s) { pin(2, s, "m"); }
public void pinMono_3(String s) { pin(3, s, "m"); }
public void pinMono_4(String s) { pin(4, s, "m"); }
public void pinMono_5(String s) { pin(5, s, "m"); }
public void pinMono_6(String s) { pin(6, s, "m"); }
public void pinMono_7(String s) { pin(7, s, "m"); }
public void pinMono_8(String s) { pin(8, s, "m"); }
public void pinMono_9(String s) { pin(9, s, "m"); }

public void pinR_0(String s) { pin(0, s, "r"); }
public void pinR_1(String s) { pin(1, s, "r"); }
public void pinR_2(String s) { pin(2, s, "r"); }
public void pinR_3(String s) { pin(3, s, "r"); }
public void pinR_4(String s) { pin(4, s, "r"); }
public void pinR_5(String s) { pin(5, s, "r"); }
public void pinR_6(String s) { pin(6, s, "r"); }
public void pinR_7(String s) { pin(7, s, "r"); }
public void pinR_8(String s) { pin(8, s, "r"); }
public void pinR_9(String s) { pin(9, s, "r"); }

public void pinG_0(String s) { pin(0, s, "g"); }
public void pinG_1(String s) { pin(1, s, "g"); }
public void pinG_2(String s) { pin(2, s, "g"); }
public void pinG_3(String s) { pin(3, s, "g"); }
public void pinG_4(String s) { pin(4, s, "g"); }
public void pinG_5(String s) { pin(5, s, "g"); }
public void pinG_6(String s) { pin(6, s, "g"); }
public void pinG_7(String s) { pin(7, s, "g"); }
public void pinG_8(String s) { pin(8, s, "g"); }
public void pinG_9(String s) { pin(9, s, "g"); }

public void pinB_0(String s) { pin(0, s, "b"); }
public void pinB_1(String s) { pin(1, s, "b"); }
public void pinB_2(String s) { pin(2, s, "b"); }
public void pinB_3(String s) { pin(3, s, "b"); }
public void pinB_4(String s) { pin(4, s, "b"); }
public void pinB_5(String s) { pin(5, s, "b"); }
public void pinB_6(String s) { pin(6, s, "b"); }
public void pinB_7(String s) { pin(7, s, "b"); }
public void pinB_8(String s) { pin(8, s, "b"); }
public void pinB_9(String s) { pin(9, s, "b"); }

void pin(int i, String s, String t) {
  try {
    int p = int(s);
    if (p >= 0 && p <= 15) {
      if (t.equals("m")) allChannels.get(i).pinMono = p;
      else if (t.equals("r")) allChannels.get(i).pinR = p;
      else if (t.equals("g")) allChannels.get(i).pinG = p;
      else if (t.equals("b")) allChannels.get(i).pinB = p;
      saveChannelConfig();
    }
  } catch (Exception e) {
  }
}

public void blackout() {
  println("BLACKOUT !");
  applyBlackout(true);
}

void applyBlackout(boolean sendCommand) {
  for (int i = 0; i < nbChannels; i++) {
    allChannels.get(i).manualVal = 0;
    allChannels.get(i).fxMode = FX_MANUAL;
    allChannels.get(i).fxFreq = 1.0;
    allChannels.get(i).fxMin = 0;
    allChannels.get(i).sequencer.active = false;
    cp5.get(Slider.class, "fader_" + i).setValue(0);
    cp5.get(DropdownList.class, "fx_" + i).setValue(FX_MANUAL);
    cp5.get(Slider.class, "freq_" + i).setValue(1.0);
    cp5.get(Slider.class, "min_" + i).setValue(0);
    cp5.get(Toggle.class, "seq_" + i).setValue(false);
    updateChannelControls(i);
  }
  if (sendCommand && serialConnected && myPort != null) {
    myPort.write("X\n");
  }
}

void invalidateOutputCache() {
  for (int i = 0; i < nbChannels; i++) {
    allChannels.get(i).valR = -1;
    allChannels.get(i).valG = -1;
    allChannels.get(i).valB = -1;
    allChannels.get(i).value = -1;
  }
}
