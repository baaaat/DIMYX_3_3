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

int layoutWidth = -1, layoutHeight = -1;
int channelPage = 0, channelsPerPage = 10;
int stripWidth = 148, stripControlWidth = 128;
int scenePanelX = 1200, scenePanelWidth = 260;
int sceneListY = 244, sceneRowHeight = 38;
boolean outputsView = false, scenesView = false, narrowLayout = false;
boolean blindActive = false;
boolean whiteBalanceDirty = false;
long whiteBalanceSaveAt = 0;
final int stepSize = 22, stepGap = 4;
PFont interfaceFont;
String[] availablePorts = new String[0];
ArrayList<Button> portButtons = new ArrayList<Button>();
int portPage = 0;
final int portsPerPage = 6;
int effectMenuChannel = -1;

String fitText(PGraphics g, String value, float available) {
  if (g.textWidth(value) <= available) return value;
  while (value.length() > 0 && g.textWidth(value + "...") > available) value = value.substring(0, value.length() - 1);
  return value + "...";
}

class CapsuleButtonView implements ControllerView<Button> {
  public void display(PGraphics g, Button button) {
    g.pushStyle();
    g.rectMode(CORNER);
    int accent = button.getColor().getBackground();
    g.fill(button.isPressed() ? lerpColor(accent, color(0), 0.3) : button.isMouseOver() ? lerpColor(accent, color(255), 0.18) : accent);
    g.stroke(button.isMouseOver() ? color(230) : lerpColor(accent, color(255), 0.25));
    g.strokeWeight(1);
    g.rect(0, 0, button.getWidth(), button.getHeight(), button.getHeight() / 2.0);
    g.fill(255);
    g.textFont(interfaceFont);
    g.textAlign(CENTER, CENTER);
    g.text(fitText(g, button.getCaptionLabel().getText(), button.getWidth() - 16), button.getWidth() / 2, button.getHeight() / 2 - 1);
    g.popStyle();
  }
}

class CapsuleSliderView implements ControllerView<Slider> {
  public void display(PGraphics g, Slider slider) {
    g.pushStyle();
    g.rectMode(CORNER);
    g.ellipseMode(CENTER);
    float w = slider.getWidth(), h = slider.getHeight();
    float amount = constrain((slider.getValue() - slider.getMin()) / (slider.getMax() - slider.getMin()), 0, 1);
    boolean vertical = slider.getDirection() == ControlP5.VERTICAL;
    int accent = slider.getColor().getActive();
    g.fill(lerpColor(accent, color(18, 24, 33), 0.85));
    g.stroke(slider.isMouseOver() ? color(220) : color(66, 82, 98));
    g.strokeWeight(1);
    g.rect(0, 0, w, h, min(w, h) / 2);
    g.noStroke();
    g.fill(accent);
    if (vertical) {
      float cy = lerp(h - w / 2, w / 2, amount);
      g.rect(w / 2 - 3, cy, 6, max(1, h - w / 2 - cy), 3);
      g.fill(245);
      g.ellipse(w / 2, cy, w - 8, w - 8);
    } else {
      // La piste reste sous le texte pour garder la valeur lisible.
      float cx = constrain(slider.getValuePosition(), 9, w - 9);
      g.rect(9, h - 7, max(1, cx - 9), 3, 2);
      g.fill(255);
      g.ellipse(cx, h - 6, 8, 8);
      g.textFont(interfaceFont);
      g.textAlign(CENTER, CENTER);
      String value = slider.getName().startsWith("freq_") ? nf(slider.getValue(), 0, 1) : str(round(slider.getValue()));
      String label = slider.getCaptionLabel().getText() + " " + value;
      g.fill(255);
      g.text(fitText(g, label, w - 20), w / 2, h / 2 - 5);
    }
    g.popStyle();
  }
}

// La saisie et les raccourcis restent ceux de Textfield ; seul le dessin change.
class CapsuleTextfield extends Textfield {
  CapsuleTextfield(String name) { super(DIMYX_3_3.this.cp5, name); }

  public void draw(PGraphics g) {
    g.pushStyle();
    g.pushMatrix();
    g.translate(getPosition()[0], getPosition()[1]);
    g.rectMode(CORNER);
    g.fill(22, 29, 39);
    g.stroke(isFocus() ? color(0, 200, 255) : color(67, 83, 101));
    g.strokeWeight(1);
    g.rect(0, 0, getWidth(), getHeight(), getHeight() / 2.0);
    g.textFont(interfaceFont);
    g.fill(240);
    g.textAlign(LEFT, CENTER);
    String value = getText();
    int cursor = constrain(getIndex(), 0, value.length());
    int start = 0;
    if (isFocus()) while (start < cursor && g.textWidth(value.substring(start, cursor)) > getWidth() - 24) start++;
    String visible = value.substring(start);
    while (visible.length() > 0 && g.textWidth(visible) > getWidth() - 20) visible = visible.substring(0, visible.length() - 1);
    g.text(visible, 10, getHeight() / 2 - 1);
    if (isFocus() && (millis() / 500) % 2 == 0) {
      float cx = 10 + g.textWidth(value.substring(start, cursor));
      g.stroke(255);
      g.line(cx, 6, cx, getHeight() - 6);
    }
    g.popMatrix();
    g.popStyle();
  }
}

Button capsuleButton(String name, String label, int accent) {
  return cp5.addButton(name).setLabel(label).setColorBackground(accent).setView(new CapsuleButtonView());
}

Slider capsuleSlider(String name, String label, float lo, float hi, float value, int accent) {
  return cp5.addSlider(name).setRange(lo, hi).setValue(value).setLabel(label).setColorActive(accent).setView(new CapsuleSliderView());
}

int firstChannel() { return channelPage * channelsPerPage; }
boolean channelVisible(int i) {
  return !(narrowLayout && scenesView) && i >= firstChannel() && i < min(nbChannels, firstChannel() + channelsPerPage);
}
int channelX(int i) { return 22 + (i - firstChannel()) * stripWidth; }
int wheelY() { return height - 180; }
int stepsY() { return height - 150; }
int stepsX(int i) { return channelX(i) + (stripControlWidth - (5 * stepSize + 4 * stepGap)) / 2; }

void place(String name, int x, int y, int w, int h, boolean visible) {
  Controller<?> c = cp5.getController(name);
  if (c == null) return;
  c.setPosition(x, y);
  c.setSize(w, h);
  c.setVisible(visible);
  if (c instanceof Slider) {
    Slider slider = (Slider)c;
    slider.setSliderMode(Slider.FIX);
    slider.setView(new CapsuleSliderView());
  }
  if (!visible && c instanceof Textfield) ((Textfield)c).setFocus(false);
}

void placeEffectList(String name, int x, int y, int w, boolean visible) {
  ScrollableList list = cp5.get(ScrollableList.class, name);
  if (list == null) return;
  list.setPosition(x, y);
  list.setSize(w, 140);
  list.setBarHeight(28);
  list.setItemHeight(28);
  list.setVisible(visible);
  if (!visible) list.close();
}
void layoutInterface() {
  if (cp5 == null) return;
  cp5.setBroadcast(false);
  cp5.setGraphics(this, 0, 0);
  int anchor = firstChannel();
  narrowLayout = width < 1000;
  scenePanelWidth = narrowLayout ? min(480, width - 44) : 264;
  scenePanelX = narrowLayout ? (width - scenePanelWidth) / 2 : width - scenePanelWidth - 22;
  int available = narrowLayout ? width - 32 : scenePanelX - 32;
  channelsPerPage = constrain(available / 148, 1, nbChannels);
  channelPage = min(anchor / channelsPerPage, (nbChannels - 1) / channelsPerPage);
  stripWidth = available / channelsPerPage;
  stripControlWidth = stripWidth - 20;
  place("outputsView", 136, 16, 124, 32, true);
  cp5.get(Button.class, "outputsView").setLabel(outputsView ? "< CONSOLE" : "SORTIES");
  place("channelPrev", 276, 16, 34, 32, !(narrowLayout && scenesView));
  place("channelNext", 316, 16, 34, 32, !(narrowLayout && scenesView));
  place("blindMode", 356, 16, 94, 32, true);
  place("scenesView", width - 284, 16, 104, 32, narrowLayout);
  cp5.get(Button.class, "scenesView").setLabel(outputsView ? (scenesView ? "SORTIES" : "USB") : (scenesView ? "TRANCHES" : "SCENES"));
  place("blackout", width - 168, 16, 146, 32, true);
  for (int i = 0; i < nbChannels; i++) {
    int x = channelX(i), w = stripControlWidth;
    boolean visible = channelVisible(i), live = visible && !outputsView;
    place("name_" + i, x, 88, w, 28, visible);
    placeEffectList("effect_" + i, x, 120, w, live);
    place("rgb_" + i, x, 136, w, 28, visible && outputsView);
    place("seq_" + i, x, 184, w, 28, live);
    for (int mode = 0; mode < 4; mode++) place("fxChoice_" + i + "_" + mode, x, 152 + mode * 32, w, 28, false);
    place("freq_" + i, x, 216, w, 28, live);
    place("min_" + i, x, 248, w, 28, live);
    place("fader_" + i, x + w / 2 - 16, 284, 32, max(48, height - 492), live);
    place("bpm_" + i, x, height - 92, w, 28, live);
    place("clone_" + i, x, height - 52, w, 32, live);
    place("pinMono_" + i, x, 210, w, 32, visible && outputsView);
    place("pinR_" + i, x, 210, w, 32, visible && outputsView);
    place("pinG_" + i, x, 278, w, 32, visible && outputsView);
    place("pinB_" + i, x, 346, w, 32, visible && outputsView);
    boolean showWhiteBalance = visible && outputsView && allChannels.get(i).isRGB;
    place("whiteR_" + i, x, 402, w, 28, showWhiteBalance);
    place("whiteG_" + i, x, 434, w, 28, showWhiteBalance);
    place("whiteB_" + i, x, 466, w, 28, showWhiteBalance);
    updateChannelControls(i);
    syncPinControls(i);
  }
  boolean showScenes = (!narrowLayout || scenesView) && !outputsView;
  int x = scenePanelX, w = scenePanelWidth, bw = (w - 18) / 4;
  String[] actions = {"newScene", "recScene", "goScene", "deleteScene"};
  for (int i = 0; i < actions.length; i++) place(actions[i], x + i * (bw + 6), 88, bw, 30, showScenes);
  place("moveSceneUp", x, 128, (w - 8) / 2, 30, showScenes);
  place("moveSceneDown", x + (w + 8) / 2, 128, (w - 8) / 2, 30, showScenes);
  place("fadeTimeSlider", x, 168, w, 30, showScenes);
  place("sceneName", x, 208, w - 62, 28, showScenes);
  place("clearName", x + w - 54, 208, 54, 28, showScenes);
  int oldFirstScene = currentPage * scenesPerPage;
  int oldSceneCount = scenesPerPage;
  scenesPerPage = constrain((height - 306) / sceneRowHeight, 4, 8);
  int sceneAnchor = (selectedSceneIndex >= oldFirstScene && selectedSceneIndex < oldFirstScene + oldSceneCount) ? selectedSceneIndex : oldFirstScene;
  currentPage = min(sceneAnchor / scenesPerPage, max(0, (scenes.size() - 1) / scenesPerPage));
  refreshSceneButtons();
  place("refreshPorts", x, 100, w, 32, outputsView && (!narrowLayout || scenesView));
  refreshPortButtons();
  layoutWidth = width;
  layoutHeight = height;
  cp5.setBroadcast(true);
}

public void channelPrev() {
  effectMenuChannel = -1;
  channelPage = max(0, channelPage - 1);
  layoutInterface();
}
public void channelNext() {
  effectMenuChannel = -1;
  channelPage = min((nbChannels - 1) / channelsPerPage, channelPage + 1);
  layoutInterface();
}
public void outputsView() { effectMenuChannel = -1; outputsView = !outputsView; layoutInterface(); }
public void blindMode(boolean v) {
  blindActive = v;
  invalidateOutputCache();
  println("BLIND " + (v ? "ON" : "OFF"));
}
public void scenesView() { effectMenuChannel = -1; scenesView = !scenesView; layoutInterface(); }
public void refreshPorts() {
  availablePorts = Serial.list();
  portPage = min(portPage, max(0, (availablePorts.length - 1) / portsPerPage));
  refreshPortButtons();
}
public void prevPorts() { portPage = max(0, portPage - 1); refreshPortButtons(); }
public void nextPorts() { portPage = min(max(0, (availablePorts.length - 1) / portsPerPage), portPage + 1); refreshPortButtons(); }

void refreshPortButtons() {
  for (Button b : portButtons) b.remove();
  portButtons.clear();
  boolean visible = outputsView && (!narrowLayout || scenesView);
  for (int i = portPage * portsPerPage; i < min(availablePorts.length, (portPage + 1) * portsPerPage); i++) {
    Button b = capsuleButton("usbPort_" + i, availablePorts[i], color(58, 77, 102));
    b.setPosition(scenePanelX, 152 + (i % portsPerPage) * 40).setSize(scenePanelWidth, 32).setVisible(visible);
    portButtons.add(b);
  }
  place("prevPorts", scenePanelX, 400, 50, 30, visible && portPage > 0);
  place("nextPorts", scenePanelX + scenePanelWidth - 50, 400, 50, 30, visible && (portPage + 1) * portsPerPage < availablePorts.length);
}

void drawConsoleInterface() {
  pushStyle();
  textFont(interfaceFont);
  textAlign(LEFT, BASELINE);
  background(18, 23, 31);
  noStroke();
  fill(242);
  textSize(24);
  text("DIMYX", 22, 40);
  textSize(13);
  if (!(narrowLayout && scenesView)) text((firstChannel() + 1) + "-" + min(nbChannels, firstChannel() + channelsPerPage) + "/" + nbChannels, 458, 37);
  fill(serialConnected ? color(104, 220, 167) : color(247, 169, 109));
  text(serialConnected ? "USB CONNECTE" : "USB DECONNECTE", 22, 68);
  fill(190, 203, 217);
  text(fitText(g, "SCENE : " + getCurrentSceneName(), width - 220), 192, 68);
  for (int i = 0; i < nbChannels; i++) {
    if (!channelVisible(i)) continue;
    int x = channelX(i), w = stripControlWidth;
    fill(26, 34, 45);
    rect(x - 8, 80, w + 16, height - 96, 18);
    if (outputsView) {
      fill(197, 212, 229);
      text(allChannels.get(i).isRGB ? "SORTIE ROUGE" : "SORTIE MONO", x, 199);
      if (allChannels.get(i).isRGB) {
        text("SORTIE VERTE", x, 267);
        text("SORTIE BLEUE", x, 335);
      }
      if (allChannels.get(i).isRGB) text("BALANCE BLANC", x, 396);
      text("Valider avec Entree", x, height - 22);
      continue;
    }
    Channel ch = allChannels.get(i);
    fill(220);
    textAlign(LEFT, CENTER);
    text(str(ch.manualVal), x + w / 2 + 23, 300);
    textAlign(LEFT, BASELINE);
    if (ch.isRGB) {
      color wheelColor = ch.baseColor;
      if (stepEditMode && i == selectedStepChannel && hasSelectedStep()) {
        Step step = ch.sequencer.steps.get(selectedStepIndex);
        wheelColor = color(step.colorR, step.colorG, step.colorB);
      }
      drawHSVWheel(x + w / 2, wheelY(), 18, wheelColor);
    }
    drawStepSequencer(stepsX(i), stepsY(), i);
  }
  fill(168, 185, 204);
  textSize(11);
  text(fitText(g, cloneStatus, width - 44), 22, height - 3);
  if (outputsView && (!narrowLayout || scenesView)) {
    textSize(13);
    text(fitText(g, "PORT USB : " + connectedPortName, scenePanelWidth), scenePanelX, 88);
    if (availablePorts.length == 0) text("Aucun port detecte", scenePanelX, 175);
  }
  popStyle();
}

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
    g.textFont(interfaceFont);
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
  float whiteBalanceR, whiteBalanceG, whiteBalanceB;
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
    whiteBalanceR = 1.0;
    whiteBalanceG = 1.0;
    whiteBalanceB = 1.0;
    sequencer = new StepSequencer();
  }
}

ArrayList<Channel> allChannels = new ArrayList<Channel>();

final int FX_MANUAL = 0;
final int FX_STROBE = 1;
final int FX_FIRE = 2;
final int FX_PULSE = 3;
final int LEGACY_FX_SEQUENCER = 4;

float channelMaster(Channel ch) {
  return (ch.sequencer.active ? ch.sequencer.getCurrentIntensity() : ch.manualVal) / 4095.0;
}

int computeMonoOutput(Channel ch, float eff) {
  return constrain(round(4095.0 * eff * channelMaster(ch)), 0, 4095);
}

void invalidateChannelOutputCache(Channel ch) {
  ch.valR = -1;
  ch.valG = -1;
  ch.valB = -1;
  ch.value = -1;
}

void markWhiteBalanceDirty() {
  whiteBalanceDirty = true;
  whiteBalanceSaveAt = millis() + 400;
}
boolean physicalOutputEnabled() {
  return !blindActive;
}

void settings() {
  size(min(1600, max(800, displayWidth - 60)), min(1000, max(540, displayHeight - 100)));
}

void setup() {
  surface.setResizable(true);
  if (surface.getNative() instanceof processing.awt.PSurfaceAWT.SmoothCanvas) {
    processing.awt.PSurfaceAWT.SmoothCanvas canvas = (processing.awt.PSurfaceAWT.SmoothCanvas)surface.getNative();
    canvas.getFrame().setMinimumSize(new java.awt.Dimension(800, 580));
  }
  interfaceFont = createFont("SansSerif", 13, true);
  textFont(interfaceFont);
  surface.setTitle("Console Theatre");
  cp5 = new ControlP5(this);
  cp5.setAutoDraw(false);
  cp5.setFont(interfaceFont);
  
  for (int i = 0; i < nbChannels; i++) {
    allChannels.add(new Channel("Tranche " + (i + 1), i));
  }
  
  createGUI();
  loadScenes();
  loadChannelConfig();
  updateGUIFromChannels();
  layoutInterface();
  
  println("Scan des ports USB...");
  String foundPort = findArduinoPort();
  
  if (foundPort != null) {
    connectToSerial(foundPort);
  } else {
    println("Detection auto echouee.");
    nextPortScanTime = millis() + portScanInterval;
    refreshPorts();
  }
}

void draw() {
  if (width != layoutWidth || height != layoutHeight) {
    effectMenuChannel = -1;
    layoutInterface();
  }
  long now = millis();
  if (whiteBalanceDirty && now >= whiteBalanceSaveAt) {
    whiteBalanceDirty = false;
    saveChannelConfig();
  }
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
  
  drawConsoleInterface();
  
  if (serialConnected && myPort != null) {
    if (now - lastHeartbeatTime > heartbeatInterval) {
      try {
        myPort.write("H\n");
      } catch (Exception e) {
        handleConnectionLoss();
      }
      lastHeartbeatTime = now;
    }
    
    if (serialConnected && myPort != null && physicalOutputEnabled() && now - lastSendTime > sendInterval) {
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
        
        float master = channelMaster(ch);
        float fin = eff * master;
        
        if (ch.isRGB) {
          color col = (ch.sequencer.active) ? ch.sequencer.getCurrentColor() : ch.baseColor;
          float nr = red(col) / 255.0;
          float ng = green(col) / 255.0;
          float nb = blue(col) / 255.0;
          float whitePart = min(nr, min(ng, nb));
          nr = constrain((nr - whitePart) + whitePart * ch.whiteBalanceR, 0, 1);
          ng = constrain((ng - whitePart) + whitePart * ch.whiteBalanceG, 0, 1);
          nb = constrain((nb - whitePart) + whitePart * ch.whiteBalanceB, 0, 1);
          int vr = int(nr * 4095 * fin);
          int vg = int(ng * 4095 * fin);
          int vb = int(nb * 4095 * fin);
          
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
          int fv = computeMonoOutput(ch, eff);
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
  if (outputsView || (narrowLayout && !scenesView)) return;
  if (selectedSceneIndex < 0 || selectedSceneIndex >= scenes.size()) return;
  int sceneOffset = selectedSceneIndex - currentPage * scenesPerPage;
  if (sceneOffset < 0 || sceneOffset >= scenesPerPage) return;
  
  noFill();
  stroke(230, 40, 40);
  strokeWeight(3);
  rect(scenePanelX - 2, sceneListY + sceneOffset * sceneRowHeight - 2, scenePanelWidth + 4, 34, 17);
  noStroke();
}

void drawStepSequencer(int x, int y, int i) {
  Channel ch = allChannels.get(i);
  ArrayList<Step> steps = ch.sequencer.steps;
  int sz = stepSize, gap = stepGap, perRow = sequencerStepsPerRow;
  
  fill(ch.sequencer.active ? color(50, 50, 80) : color(40));
  noStroke();
  rect(x - 4, y - 4, perRow * (sz + gap), 56, 12);
  
  fill(ch.sequencer.active ? color(0, 255, 0) : color(100));
  ellipse(x + perRow * (sz + gap) - 10, y - 10, 8, 8);

  if (stepEditMode && i == selectedStepChannel && hasSelectedStep()) {
    fill(0, 200, 255);
    textAlign(LEFT, BASELINE);
    textSize(10);
    text("EDIT " + (selectedStepIndex + 1), x, y - 7);
  }
  
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
    rect(x + col * (sz + gap), y + r * (sz + gap), sz, sz, 7);
  }
  
  if (steps.size() < maxSequencerSteps) {
    int nj = visibleSteps;
    int nr = nj / perRow;
    int nc = nj % perRow;
    fill(80);
    stroke(150);
    strokeWeight(2);
    rect(x + nc * (sz + gap), y + nr * (sz + gap), sz, sz, 7);
    
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
    updateEffectButton(i);
    
    updateChannelControls(i);
    cp5.get(Slider.class, "freq_" + i).setValue(ch.fxFreq);
    cp5.get(Slider.class, "min_" + i).setValue(ch.fxMin);
    cp5.get(Toggle.class, "rgb_" + i).setValue(ch.isRGB ? 1 : 0);
    cp5.get(Toggle.class, "seq_" + i).setBroadcast(false).setValue(ch.sequencer.active).setBroadcast(true);
    cp5.get(Slider.class, "bpm_" + i).setValue(ch.sequencer.bpm);
    cp5.get(Slider.class, "whiteR_" + i).setValue(ch.whiteBalanceR * 100.0);
    cp5.get(Slider.class, "whiteG_" + i).setValue(ch.whiteBalanceG * 100.0);
    cp5.get(Slider.class, "whiteB_" + i).setValue(ch.whiteBalanceB * 100.0);
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

void updateEffectButton(int i) {
  String[] labels = {"MAN", "STR", "FEU", "PUL"};
  int mode = constrain(allChannels.get(i).fxMode, 0, 3);
  ScrollableList fx = cp5.get(ScrollableList.class, "effect_" + i);
  if (fx == null) return;
  fx.changeValue(mode);
  fx.getCaptionLabel().setText("FX  " + labels[mode] + "  v");
}

void updateChannelControls(int i) {
  Channel ch = allChannels.get(i);
  boolean live = channelVisible(i) && !outputsView;
  boolean showFX = live && ch.fxMode != FX_MANUAL;
  cp5.get(Slider.class, "freq_" + i).setVisible(showFX);
  cp5.get(Slider.class, "min_" + i).setVisible(showFX);
  cp5.get(Slider.class, "bpm_" + i).setVisible(live && ch.sequencer.active);
}

String getCurrentSceneName() {
  if (activeSceneIndex >= 0 && activeSceneIndex < scenes.size()) return scenes.get(activeSceneIndex).name;
  return "AUCUNE";
}

void drawHSVWheel(float cx, float cy, float rad, color sel) {
  float whiteRadius = 5.0;
  noStroke();

  for (float r = whiteRadius; r < rad; r += 1) {
    for (float a = 0; a < 360; a += 3) {
      float radA = radians(a);
      float x = cx + r * cos(radA);
      float y = cy + r * sin(radA);
      float saturation = constrain((r - whiteRadius) / (rad - whiteRadius), 0, 1);
      fill(hsvToRgb(a / 360.0, saturation, 1.0));
      rect(x, y, 2, 2);
    }
  }

  fill(255);
  stroke(45, 55, 65);
  strokeWeight(1);
  ellipse(cx, cy, whiteRadius * 2, whiteRadius * 2);

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
  if (outputsView || (narrowLayout && scenesView)) return;
  for (int i = 0; i < nbChannels; i++) {
    if (!channelVisible(i)) continue;
    Channel ch = allChannels.get(i);
    float cx = channelX(i) + stripControlWidth / 2, cy = wheelY();
    float wheelDistance = dist(mouseX, mouseY, cx, cy);
    if (mouseButton == LEFT && ch.isRGB && wheelDistance < 18) {
      float a = atan2(mouseY - cy, mouseX - cx);
      if (a < 0) a += TWO_PI;

      float whiteRadius = 5.0;
      float saturation = constrain((wheelDistance - whiteRadius) / (18.0 - whiteRadius), 0, 1);
      color selectedColor = hsvToRgb(a / TWO_PI, saturation, 1.0);

      if (stepEditMode && i == selectedStepChannel && hasSelectedStep()) {
        Step step = ch.sequencer.steps.get(selectedStepIndex);
        step.colorR = red(selectedColor);
        step.colorG = green(selectedColor);
        step.colorB = blue(selectedColor);
      } else {
        ch.baseColor = selectedColor;
      }
      return;
    }
    for (int j = 0; j < maxSequencerSteps; j++) {
      int x = stepsX(i) + (j % sequencerStepsPerRow) * (stepSize + stepGap);
      int y = stepsY() + (j / sequencerStepsPerRow) * (stepSize + stepGap);
      if (mouseX < x || mouseX >= x + stepSize || mouseY < y || mouseY >= y + stepSize) continue;
      if (j < ch.sequencer.steps.size()) {
        if (mouseButton == LEFT) {
          // A single click edits the step: fader = intensity, wheel = RGB color.
          startStepEditing(i, j);
          lastStepClickTime = millis();
          lastClickedStepChannel = i;
          lastClickedStepIndex = j;
        } else if (mouseButton == RIGHT) {
          ch.sequencer.steps.remove(j);
          ch.sequencer.currentStep = ch.sequencer.steps.isEmpty() ? 0 : min(ch.sequencer.currentStep, ch.sequencer.steps.size() - 1);
          if (selectedStepChannel == i) { selectedStepIndex = -1; stepEditMode = false; }
        }
      } else if (j == ch.sequencer.steps.size() && mouseButton == LEFT) {
        color col = ch.baseColor;
        ch.sequencer.steps.add(new Step(constrain(ch.manualVal, 0, 4095), red(col), green(col), blue(col)));
        startStepEditing(i, j);
      }
      return;
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
  refreshPorts();
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
  if (interfaceFont == null) interfaceFont = createFont("SansSerif", 13, true);
  cp5.setFont(interfaceFont);
  for (int i = 0; i < nbChannels; i++) {

    cp5.addToggle("rgb_" + i).setSize(128, 28).setValue(false).setLabel("").setView(new ChipView("RGB", color(0, 200, 255)));
    cp5.addToggle("seq_" + i).setSize(128, 28).setValue(false).setLabel("").setView(new ChipView("SEQ", color(255, 200, 0)));
    capsuleSlider("whiteR_" + i, "BLANC R %", 0, 100, 100, color(145, 80, 80));
    capsuleSlider("whiteG_" + i, "BLANC V %", 0, 100, 100, color(80, 145, 95));
    capsuleSlider("whiteB_" + i, "BLANC B %", 0, 100, 100, color(80, 105, 155));
    capsuleButton("clone_" + i, "CLONER", color(58, 77, 102));
    capsuleSlider("freq_" + i, "FREQ", 0.1, 10, 1, color(64, 111, 153));
    capsuleSlider("min_" + i, "MIN", 0, 4095, 0, color(64, 111, 153));
    capsuleSlider("bpm_" + i, "BPM", 60, 240, 120, color(121, 99, 32));
    capsuleSlider("fader_" + i, "", 0, 4095, 0, color(0, 183, 223));
    new CapsuleTextfield("name_" + i).setText(allChannels.get(i).name).setAutoClear(false).setLabel("");
    new CapsuleTextfield("pinMono_" + i).setText(str(allChannels.get(i).pinMono)).setAutoClear(false).setLabel("");
    new CapsuleTextfield("pinR_" + i).setText(str(allChannels.get(i).pinR)).setAutoClear(false).setLabel("");
    new CapsuleTextfield("pinG_" + i).setText(str(allChannels.get(i).pinG)).setAutoClear(false).setLabel("");
    new CapsuleTextfield("pinB_" + i).setText(str(allChannels.get(i).pinB)).setAutoClear(false).setLabel("");
  }
  for (int i = 0; i < nbChannels; i++) {
    ScrollableList fx = cp5.addScrollableList("effect_" + i);
    fx.setBarHeight(28);
    fx.setItemHeight(28);
    fx.setItems(new String[]{"MAN", "STR", "FEU", "PUL"});
    fx.setColorBackground(color(60, 83, 109));
    fx.setColorForeground(color(74, 99, 132));
    fx.setColorActive(color(92, 124, 165));
    fx.getCaptionLabel().setText("FX  MAN  v");
    fx.close();
    fx.bringToFront();
  }
  capsuleButton("outputsView", "SORTIES", color(58, 77, 102));
  cp5.addToggle("blindMode").setValue(false).setLabel("").setView(new ChipView("BLIND", color(191, 139, 48)));
  capsuleButton("scenesView", "SCENES", color(83, 64, 123));
  capsuleButton("channelPrev", "<", color(58, 77, 102));
  capsuleButton("channelNext", ">", color(58, 77, 102));
  capsuleButton("newScene", "+ NEW", color(43, 109, 169));
  capsuleButton("recScene", "REC", color(143, 103, 27));
  capsuleButton("goScene", "GO", color(32, 125, 80));
  capsuleButton("deleteScene", "DEL", color(151, 58, 71));
  capsuleButton("moveSceneUp", "MONTER", color(58, 77, 102));
  capsuleButton("moveSceneDown", "DESCENDRE", color(58, 77, 102));
  capsuleButton("prevPage", "<", color(58, 77, 102));
  capsuleButton("nextPage", ">", color(58, 77, 102));
  capsuleSlider("fadeTimeSlider", "FONDU ms", 0, 10000, 2000, color(64, 111, 153));
  new CapsuleTextfield("sceneName").setText("Nouvelle Scene").setAutoClear(false).setLabel("");
  capsuleButton("clearName", "CLR", color(58, 77, 102));
  capsuleButton("blackout", "BLACKOUT", color(191, 37, 63));
  capsuleButton("refreshPorts", "ACTUALISER LES PORTS", color(58, 77, 102));
  capsuleButton("prevPorts", "<", color(58, 77, 102));
  capsuleButton("nextPorts", ">", color(58, 77, 102));
  availablePorts = Serial.list();
  layoutInterface();
  cp5.setBroadcast(true);
}

void refreshSceneButtons() {
  for (Button b : sceneButtons) b.remove();
  sceneButtons.clear();
  boolean visible = !outputsView && (!narrowLayout || scenesView);
  int first = currentPage * scenesPerPage;
  color[] accents = {color(57, 98, 135), color(105, 73, 137), color(143, 69, 105), color(139, 95, 47), color(83, 114, 58), color(43, 115, 107), color(108, 72, 107), color(69, 103, 112)};
  for (int i = first; i < min(first + scenesPerPage, scenes.size()); i++) {
    int offset = i - first;
    Button b = capsuleButton("scene_" + offset, scenes.get(i).name, accents[i % accents.length]);
    b.setPosition(scenePanelX, sceneListY + offset * sceneRowHeight).setSize(scenePanelWidth, 30).setVisible(visible);
    sceneButtons.add(b);
  }
  int pagerY = sceneListY + scenesPerPage * sceneRowHeight + 8;
  place("prevPage", scenePanelX, pagerY, 50, 30, visible && currentPage > 0);
  place("nextPage", scenePanelX + scenePanelWidth - 50, pagerY, 50, 30, visible && (currentPage + 1) * scenesPerPage < scenes.size());
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
      ch.whiteBalanceR = savedChannel.hasKey("wr") ? constrain(savedChannel.getFloat("wr"), 0, 1) : 1.0;
      ch.whiteBalanceG = savedChannel.hasKey("wg") ? constrain(savedChannel.getFloat("wg"), 0, 1) : 1.0;
      ch.whiteBalanceB = savedChannel.hasKey("wb") ? constrain(savedChannel.getFloat("wb"), 0, 1) : 1.0;
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
    savedChannel.setFloat("wr", ch.whiteBalanceR);
    savedChannel.setFloat("wg", ch.whiteBalanceG);
    savedChannel.setFloat("wb", ch.whiteBalanceB);
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
  if (e.isController() && e.getName().startsWith("effect_")) {
    int i = int(e.getName().substring(7));
    Channel ch = allChannels.get(i);
    ch.fxMode = constrain(round(e.getValue()), 0, 3);
    updateEffectButton(i);
    updateChannelControls(i);
    cp5.get(ScrollableList.class, "effect_" + i).close();
    return;
  }
  if (e.isController() && e.getName().startsWith("whiteR_")) {
    int i = int(e.getName().substring(7));
    Channel ch = allChannels.get(i);
    ch.whiteBalanceR = constrain(e.getValue() / 100.0, 0, 1);
    invalidateChannelOutputCache(ch);
    markWhiteBalanceDirty();
    return;
  }
  if (e.isController() && e.getName().startsWith("whiteG_")) {
    int i = int(e.getName().substring(7));
    Channel ch = allChannels.get(i);
    ch.whiteBalanceG = constrain(e.getValue() / 100.0, 0, 1);
    invalidateChannelOutputCache(ch);
    markWhiteBalanceDirty();
    return;
  }
  if (e.isController() && e.getName().startsWith("whiteB_")) {
    int i = int(e.getName().substring(7));
    Channel ch = allChannels.get(i);
    ch.whiteBalanceB = constrain(e.getValue() / 100.0, 0, 1);
    invalidateChannelOutputCache(ch);
    markWhiteBalanceDirty();
    return;
  }
  if (e.isController() && e.getName().startsWith("usbPort_")) {
    int index = int(e.getName().substring(8));
    if (index >= 0 && index < availablePorts.length) connectToSerial(availablePorts[index]);
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
  Channel ch = allChannels.get(i);
  if (ch.isRGB != v) {
    ch.isRGB = v;
    invalidateChannelOutputCache(ch);
  }
  syncPinControls(i);
}

void syncPinControls(int i) {
  boolean visible = channelVisible(i) && outputsView;
  boolean rgb = allChannels.get(i).isRGB;
  cp5.get(Textfield.class, "pinMono_" + i).setVisible(visible && !rgb);
  cp5.get(Textfield.class, "pinR_" + i).setVisible(visible && rgb);
  cp5.get(Textfield.class, "pinG_" + i).setVisible(visible && rgb);
  cp5.get(Textfield.class, "pinB_" + i).setVisible(visible && rgb);
  cp5.get(Slider.class, "whiteR_" + i).setVisible(visible && rgb);
  cp5.get(Slider.class, "whiteG_" + i).setVisible(visible && rgb);
  cp5.get(Slider.class, "whiteB_" + i).setVisible(visible && rgb);
  String[] fields = {"pinMono_", "pinR_", "pinG_", "pinB_"};
  for (String field : fields) {
    Textfield input = cp5.get(Textfield.class, field + i);
    if (!input.isVisible()) input.setFocus(false);
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
  invalidateChannelOutputCache(ch);
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

public void fx_0(int v) { allChannels.get(0).fxMode = v; updateEffectButton(0); }
public void fx_1(int v) { allChannels.get(1).fxMode = v; updateEffectButton(1); }
public void fx_2(int v) { allChannels.get(2).fxMode = v; updateEffectButton(2); }
public void fx_3(int v) { allChannels.get(3).fxMode = v; updateEffectButton(3); }
public void fx_4(int v) { allChannels.get(4).fxMode = v; updateEffectButton(4); }
public void fx_5(int v) { allChannels.get(5).fxMode = v; updateEffectButton(5); }
public void fx_6(int v) { allChannels.get(6).fxMode = v; updateEffectButton(6); }
public void fx_7(int v) { allChannels.get(7).fxMode = v; updateEffectButton(7); }
public void fx_8(int v) { allChannels.get(8).fxMode = v; updateEffectButton(8); }
public void fx_9(int v) { allChannels.get(9).fxMode = v; updateEffectButton(9); }

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
    updateEffectButton(i);
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
