package fr.dimyx.representation;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.net.Uri;
import android.os.Bundle;
import android.view.MotionEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

public class MainActivity extends Activity {
    private static final int PICK_JSON = 41;
    private ShowEngine engine;
    private ConsoleView console;
    private int pickKind = 0; // 0 scènes, 1 configuration, 2 cartes

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN);
        engine = new ShowEngine();
        console = new ConsoleView();
        setContentView(console);
    }

    private void pickJson(int kind) {
        pickKind = kind;
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.setType("application/json");
        i.addCategory(Intent.CATEGORY_OPENABLE);
        startActivityForResult(i, PICK_JSON);
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request != PICK_JSON || result != RESULT_OK || data == null) return;
        try (InputStream in = getContentResolver().openInputStream(data.getData())) {
            String text = readAll(in);
            if (pickKind == 0) engine.loadScenes(text);
            else if (pickKind == 1) engine.loadChannels(text);
            else engine.loadBoards(text);
            pickKind = (pickKind + 1) % 3;
            console.invalidate();
        } catch (Exception ignored) { engine.status = "FICHIER INVALIDE"; }
    }

    private static String readAll(InputStream in) throws Exception {
        BufferedReader r = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8));
        StringBuilder b = new StringBuilder(); String line;
        while ((line = r.readLine()) != null) b.append(line).append('\n');
        return b.toString();
    }

    private class ConsoleView extends View {
        private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        private long lastFrame;
        private int page;
        private int activeFader = -1;

        ConsoleView() { super(MainActivity.this); p.setTypeface(android.graphics.Typeface.create("sans", 0)); }

        @Override protected void onDraw(Canvas c) {
            super.onDraw(c);
            long now = System.currentTimeMillis();
            engine.update(now);
            drawConsole(c);
            lastFrame = now;
            postInvalidateDelayed(33);
        }

        private void drawConsole(Canvas c) {
            int w = getWidth(), h = getHeight();
            int bg = Color.rgb(32,36,45), panel = Color.rgb(48,54,67);
            int strip = Color.rgb(66,73,87), track = Color.rgb(36,42,53);
            int accent = Color.rgb(104,167,177), secondary = Color.rgb(174,185,201);
            c.drawColor(bg);
            p.setColor(panel); c.drawRect(0,0,w,58,p);
            text(c, "DIMYX — REPRÉSENTATION", 16, 24, 17, Color.WHITE);
            text(c, engine.connectionLabel(), 16, 45, 11, engine.connectionColor());
            int loadW = Math.max(58, Math.min(92, w / 7));
            button(c, new RectF(w - 2 * loadW - 94, 12, w - loadW - 48, 48), new String[]{"SCÈNES","CONFIG","CARTES"}[pickKind], panel, secondary, 11);
            button(c, new RectF(w - loadW - 36, 12, w - 12, 48), "X", Color.rgb(164,47,65), Color.WHITE, 16);

            int margin = 12, gap = 8, top = 72, footer = 48;
            int sceneW = Math.max(128, Math.min(280, Math.round(w * .29f)));
            int sceneX = w - margin - sceneW;
            int leftW = sceneX - margin - gap;
            p.setColor(panel); c.drawRoundRect(new RectF(margin,top,sceneX-gap,h-footer),10,10,p);
            p.setColor(panel); c.drawRoundRect(new RectF(sceneX,top,w-margin,h-footer),10,10,p);
            text(c, "TRANCHES", margin+12, top+25, 14, Color.WHITE);
            button(c, new RectF(sceneX-132, top+9, sceneX-76, top+37), "1–5", page==0?accent:strip, Color.WHITE, 11);
            button(c, new RectF(sceneX-70, top+9, sceneX-14, top+37), "6–10", page==1?accent:strip, Color.WHITE, 11);
            int channelTop = top + 46, channelBottom = h-footer-12;
            int channelW = Math.max(42, (leftW - 5 * gap) / 5);
            for (int visible = 0; visible < 5; visible++) {
                int index = page * 5 + visible;
                if (index >= engine.channels.size()) break;
                drawChannel(c, engine.channels.get(index), margin + visible * (channelW + gap), channelTop, channelW, channelBottom-channelTop, strip, track, accent, secondary);
            }
            drawScenes(c, sceneX, top, sceneW, h-footer-top, accent, secondary, strip);
            p.setColor(panel); c.drawRect(0,h-footer,w,h,p);
            text(c, "SCÈNE : " + engine.currentSceneName(), margin+12, h-19, 13, Color.WHITE);
            text(c, engine.status, margin+12, h-5, 10, secondary);
            button(c, new RectF(w-126,h-footer+8,w-12,h-8), "BLACKOUT", Color.rgb(164,47,65), Color.WHITE, 12);
        }

        private void drawChannel(Canvas c, Channel ch, int x, int y, int w, int h, int strip, int track, int accent, int secondary) {
            p.setColor(strip); c.drawRoundRect(new RectF(x,y,x+w,y+h), 8,8,p);
            text(c, "CH " + (engine.channels.indexOf(ch)+1), x+5, y+20, 11, Color.WHITE);
            text(c, shortName(ch.name,w), x+5, y+35, 9, secondary);
            int color = Color.rgb(ch.colorR, ch.colorG, ch.colorB);
            p.setColor(color); c.drawCircle(x+w/2f, y+55, Math.max(9,Math.min(18,w/3f)), p);
            text(c, String.format(Locale.US, "%d%%", Math.round(ch.visibleLevel() * 100)), x+4, y+88, 11, Color.WHITE);
            text(c, ch.seq ? "SEQ" : (ch.fx == 0 ? "MAN" : ch.effectName()), x+4, y+103, 9, secondary);
            float fy = y + 116, fh = Math.max(40, h - 154);
            p.setColor(track); c.drawRoundRect(new RectF(x+w/2f-7,fy,x+w/2f+7,fy+fh),7,7,p);
            float knob = fy + fh * (1f - ch.visibleLevel());
            p.setColor(accent); c.drawRoundRect(new RectF(x+4,knob-7,x+w-4,knob+7),7,7,p);
            text(c, ch.board.equalsIgnoreCase("USB") || ch.board.matches("COM.*") ? "PC" : "WIFI", x+4, y+h-10, 8, secondary);
        }

        private void drawScenes(Canvas c, int x, int y, int w, int h, int accent, int secondary, int strip) {
            text(c, "SCÈNES", x+12, y + 25, 14, Color.WHITE);
            int row = Math.max(34, Math.min(50, (h-58)/8));
            int first = engine.scenePage * 8;
            for (int i=0; i<8 && first+i<engine.scenes.size(); i++) {
                int idx=first+i; RectF r=new RectF(x+8,y+38+i*row,x+w-8,y+34+(i+1)*row);
                button(c,r,(idx+1)+". "+engine.scenes.get(idx).name, idx==engine.activeScene ? accent : strip, Color.WHITE, 11);
            }
            text(c, engine.scenes.isEmpty()?"AUCUNE SCÈNE":(first+1)+"–"+Math.min(first+8,engine.scenes.size())+" / "+engine.scenes.size(), x+12, y+h-12, 10, secondary);
        }

        private String shortName(String name, int width) { if (width < 65) return ""; return name.length()>10 ? name.substring(0,9)+"…" : name; }
        private void button(Canvas c, RectF r, String s, int color, int textColor, float size) {
            p.setColor(color); c.drawRoundRect(r,10,10,p);
            p.setTextAlign(Paint.Align.CENTER); text(c,s,r.centerX(),r.centerY()+size*.35f,size,textColor); p.setTextAlign(Paint.Align.LEFT);
        }
        private void text(Canvas c,String s,float x,float y,float size,int color){p.setTextSize(size);p.setColor(color);c.drawText(s,x,y,p);}

        @Override public boolean onTouchEvent(MotionEvent e) {
            int w=getWidth(), h=getHeight(); float x=e.getX(), y=e.getY();
            if (e.getAction()==MotionEvent.ACTION_DOWN) {
                if ((x>w-140 && y<60) || (x>w-140 && y>h-50)) { engine.blackout(); invalidate(); return true; }
                int loadW=Math.max(58,Math.min(92,w/7));
                if (x>w-2*loadW-100 && x<w-loadW-40 && y<60) { pickJson(pickKind); return true; }
                int margin=12,gap=8,top=72,footer=48,sceneW=Math.max(128,Math.min(280,Math.round(w*.29f))),sceneX=w-margin-sceneW,leftW=sceneX-margin-gap;
                if (y>top+7 && y<top+45 && x>=sceneX-138 && x<sceneX-74) { page=0; invalidate(); return true; }
                if (y>top+7 && y<top+45 && x>=sceneX-74 && x<sceneX-8) { page=1; invalidate(); return true; }
                if (x>=sceneX && y>top+34 && y<h-footer) {
                    int row=Math.max(34,Math.min(50,((h-footer-top)-58)/8)); int slot=(int)((y-(top+38))/row); int idx=engine.scenePage*8+slot;
                    if(slot>=0 && idx<engine.scenes.size()){engine.launch(idx);invalidate();} return true;
                }
                int channelTop=top+46, channelBottom=h-footer-12,channelW=Math.max(42,(leftW-5*gap)/5);
                int visible=(int)((x-margin)/(channelW+gap)); int idx=page*5+visible;
                if(visible>=0&&visible<5&&idx<engine.channels.size()&&y>=channelTop){activeFader=idx; setFader(y,channelTop,channelBottom-channelTop); return true;}
            } else if ((e.getAction()==MotionEvent.ACTION_MOVE || e.getAction()==MotionEvent.ACTION_UP) && activeFader>=0) {
                int channelTop=118, channelHeight=h-48-12-channelTop; setFader(y,channelTop,channelHeight); if(e.getAction()==MotionEvent.ACTION_UP) activeFader=-1; return true;
            }
            return true;
        }
        private void setFader(float y,int top,int h){ float fy=top+116, fh=Math.max(40,h-154); float t=1f-(y-fy)/fh; engine.setGain(activeFader,Math.max(0,Math.min(1,t))); invalidate(); }
    }

    static class Step { int i; int r=255,g=255,b=255; }
    static class SceneState { int m,fx,min; float f=1,bpm=120; int r=255,g=255,b=255; boolean sa; ArrayList<Step> steps=new ArrayList<>(); }
    static class Scene { String name; SceneState[] states=new SceneState[10]; }
    static class Channel { String name="Tranche"; boolean rgb; int pm=3,pr=3,pg=5,pb=6; String board="USB"; int colorR=255,colorG=255,colorB=255; float whiteR=1,whiteG=1,whiteB=1; int manual,fx,min; float freq=1,bpm=120; boolean seq; ArrayList<Step> steps=new ArrayList<>(); int current; long nextStep; float gain=1; SceneState target; int startManual,startR,startG,startB; long transitionStart; float visibleLevel(){float source=seq&&!steps.isEmpty()?steps.get(current).i/4095f:manual/4095f;return Math.max(0,Math.min(1,source*gain));} String effectName(){return fx==1?"STR":fx==2?"FEU":fx==3?"PUL":"MAN";} }

    class ShowEngine {
        ArrayList<Channel> channels=new ArrayList<>(); ArrayList<Scene> scenes=new ArrayList<>();
        Map<String,Board> boards=new java.util.concurrent.ConcurrentHashMap<>(); int activeScene=-1,scenePage; boolean blackout; boolean online; String status="SPECTACLE DEMO — ESP32 DECONNECTE";
        long lastHeartbeat;
        ShowEngine(){ for(int i=0;i<10;i++){Channel c=new Channel();c.name="Tranche "+(i+1);channels.add(c);} loadDemo(); }
        void loadDemo(){ Scene s=new Scene();s.name="Démonstration";for(int i=0;i<10;i++){s.states[i]=new SceneState();s.states[i].m=i<2?4095:0;s.states[i].r=255;s.states[i].g=i==1?80:255;s.states[i].b=255;}scenes.add(s); }
        void loadScenes(String raw)throws Exception{JSONArray a=new JSONArray(raw);scenes.clear();for(int n=0;n<a.length();n++){JSONObject j=a.getJSONObject(n);Scene s=new Scene();s.name=j.optString("name","Scène "+(n+1));JSONArray states=j.getJSONArray("states");for(int i=0;i<10;i++){JSONObject q=states.getJSONObject(i);SceneState z=new SceneState();z.m=q.optInt("m");z.fx=q.optInt("fx");z.min=q.optInt("min");z.f=(float)q.optDouble("f",1);z.bpm=(float)q.optDouble("bpm",120);z.r=q.optInt("cr",255);z.g=q.optInt("cg",255);z.b=q.optInt("cb",255);z.sa=q.optBoolean("sa");JSONArray steps=q.optJSONArray("steps");if(steps!=null)for(int k=0;k<steps.length();k++){JSONObject p=steps.getJSONObject(k);Step t=new Step();t.i=p.optInt("i");t.r=p.optInt("r",255);t.g=p.optInt("g",255);t.b=p.optInt("b",255);z.steps.add(t);}s.states[i]=z;}scenes.add(s);}status="SCENES CHARGEES : "+scenes.size()+" — sélectionner une scène";}
        void loadChannels(String raw)throws Exception{JSONObject root=new JSONObject(raw);JSONArray a=root.getJSONArray("channels");for(int i=0;i<Math.min(10,a.length());i++){JSONObject q=a.getJSONObject(i);Channel c=channels.get(i);c.name=q.optString("name",c.name);c.rgb=q.optBoolean("rgb",false);c.pm=q.optInt("pm",c.pm);c.pr=q.optInt("pr",c.pr);c.pg=q.optInt("pg",c.pg);c.pb=q.optInt("pb",c.pb);c.whiteR=(float)q.optDouble("wr",1);c.whiteG=(float)q.optDouble("wg",1);c.whiteB=(float)q.optDouble("wb",1);c.board=q.optString("board","USB");if(c.board.startsWith("ESP32")&&!boards.containsKey(c.board))boards.put(c.board,new Board(c.board,"192.168.4.1",4210));}status="CONFIGURATION CHARGEE : "+Math.min(10,a.length())+" tranches"+(hasUnsupportedFirmwarePin()?" — GPIO non supporté par le firmware fourni":"");}
        void loadBoards(String raw)throws Exception{JSONObject root=new JSONObject(raw);JSONArray a=root.getJSONArray("boards");for(int i=0;i<a.length();i++){JSONObject q=a.getJSONObject(i);if(!q.optBoolean("enabled",true))continue;String id=q.optString("id",q.optString("board"));if(id.length()>0)boards.put(id,new Board(id,q.optString("host","192.168.4.1"),q.optInt("port",4210)));}status="CARTES CHARGEES — ESP32 DECONNECTE";}
        void launch(int idx){if(idx<0||idx>=scenes.size())return;Scene s=scenes.get(idx);long now=System.currentTimeMillis();for(int i=0;i<10;i++){SceneState z=s.states[i];Channel c=channels.get(i);c.startManual=c.manual;c.startR=c.colorR;c.startG=c.colorG;c.startB=c.colorB;c.target=z;c.transitionStart=now;c.gain=1;}activeScene=idx;blackout=false;status="TRANSITION : "+s.name+" — "+(online?"WIFI OK":"ESP32 DECONNECTE");}
        void setGain(int i,float v){if(i>=0&&i<channels.size())channels.get(i).gain=v;}
        void blackout(){blackout=true;for(Channel c:channels){c.gain=0;c.seq=false;}Network.sendAllBlackout(boards);status="BLACKOUT — "+(online?"WIFI OK":"ESP32 DECONNECTE");}
        void update(long now){for(Channel c:channels){if(c.target!=null){float t=Math.min(1,(now-c.transitionStart)/600f);c.manual=Math.round(c.startManual+(c.target.m-c.startManual)*t);c.colorR=Math.round(c.startR+(c.target.r-c.startR)*t);c.colorG=Math.round(c.startG+(c.target.g-c.startG)*t);c.colorB=Math.round(c.startB+(c.target.b-c.startB)*t);if(t>=1){SceneState z=c.target;c.target=null;c.fx=z.fx==4?0:z.fx;c.min=z.min;c.freq=z.f;c.bpm=Math.max(20,z.bpm);c.seq=z.sa;c.steps=new ArrayList<>(z.steps);c.current=0;c.nextStep=now;status=status.replace("TRANSITION : ","SCÈNE : ");}}if(c.seq&&!c.steps.isEmpty()&&now>=c.nextStep){c.current=(c.current+1)%c.steps.size();c.nextStep=now+(long)(60000.0/Math.max(20,c.bpm)/4);}}if(now-lastHeartbeat>500){Network.heartbeat(boards);lastHeartbeat=now;}Network.discover(now);online=Network.isConnected(boards,now);send(now);}
        void send(long now){if(now%33>18)return;for(Channel c:channels){float effect=1;float minN=c.min/4095f;if(c.fx==1)effect=(now%(long)(1000/Math.max(.1,c.freq))<500/Math.max(.1,c.freq))?1:minN;else if(c.fx==2)effect=(float)(minN+(1-minN)*((Math.sin(now*.013*c.freq+c.name.hashCode())+1)/2));else if(c.fx==3)effect=(float)(minN+(1-minN)*(Math.sin(now*.005*c.freq)+1)/2);float source=c.seq&&!c.steps.isEmpty()?c.steps.get(c.current).i/4095f:c.manual/4095f;float out=blackout?0:source*c.gain*effect;Network.send(c,out);}}
        String currentSceneName(){return activeScene>=0&&activeScene<scenes.size()?scenes.get(activeScene).name:"AUCUNE";}
        boolean hasNetworkAssignment(){for(Channel c:channels)if(c.board!=null&&!c.board.equalsIgnoreCase("USB")&&!c.board.matches("COM.*"))return true;return false;}
        boolean hasUnsupportedFirmwarePin(){for(Channel c:channels){if(!c.board.equalsIgnoreCase("USB")&&!c.board.matches("COM.*")){if(!pinSupported(c.pm)||!pinSupported(c.pr)||!pinSupported(c.pg)||!pinSupported(c.pb))return true;}}return false;}
        boolean pinSupported(int pin){return pin==4||pin==5||pin==6;}
        String connectionLabel(){if(!hasNetworkAssignment())return "WIFI : AUCUNE AFFECTATION ESP32 — préparer sur PC";if(boards.isEmpty())return "WIFI : RECHERCHE DES ESP32...";return online?"WIFI : CONNECTE — réponse ESP32 reçue":"WIFI : EN ATTENTE — aucune réponse ESP32";}
        int connectionColor(){return online?Color.rgb(104,167,177):Color.rgb(247,169,109);}
    }
    static class Board { String id,host; int port; Board(String i,String h,int p){id=i;host=h;port=p;} }
    static class Network {
        static final java.util.concurrent.ExecutorService pool=java.util.concurrent.Executors.newSingleThreadExecutor();
        static Map<String,Board> boards= new java.util.concurrent.ConcurrentHashMap<>();
        static volatile long lastReplyAt;
        static volatile boolean receiverStarted;
        static volatile long lastDiscoveryAt;
        static java.net.DatagramSocket socket;
        static synchronized void ensureSocket(){if(socket!=null)return;try{socket=new java.net.DatagramSocket();socket.setBroadcast(true);socket.setSoTimeout(250);}catch(Exception ignored){return;}if(!receiverStarted){receiverStarted=true;Thread t=new Thread(Network::receiveLoop,"dimyx-udp-receiver");t.setDaemon(true);t.start();}}
        static void heartbeat(Map<String,Board> b){boards=b;ensureSocket();for(Board x:b.values())sendRaw(x,"H\n");}
        static void discover(long now){if(now-lastDiscoveryAt<3000)return;ensureSocket();if(socket==null)return;lastDiscoveryAt=now;pool.submit(()->{try{byte[] data="DISCOVER\n".getBytes(StandardCharsets.UTF_8);socket.send(new java.net.DatagramPacket(data,data.length,java.net.InetAddress.getByName("255.255.255.255"),4210));}catch(Exception ignored){}});}
        static void sendAllBlackout(Map<String,Board> b){for(Board x:b.values())sendRaw(x,"X\n");}
        static boolean send(Channel c,float out){if(c.board==null||c.board.equalsIgnoreCase("USB")||c.board.matches("COM.*"))return false;Board b=boards.get(c.board);if(b==null)return false;ensureSocket();int red=c.colorR,green=c.colorG,blue=c.colorB;if(c.seq&&!c.steps.isEmpty()){Step step=c.steps.get(c.current);red=step.r;green=step.g;blue=step.b;}if(c.rgb){float nr=red/255f,ng=green/255f,nb=blue/255f;float white=Math.min(nr,Math.min(ng,nb));nr=Math.max(0,Math.min(1,(nr-white)+white*c.whiteR));ng=Math.max(0,Math.min(1,(ng-white)+white*c.whiteG));nb=Math.max(0,Math.min(1,(nb-white)+white*c.whiteB));sendRaw(b,"P,"+c.pr+","+Math.round(out*4095*nr)+"\n");sendRaw(b,"P,"+c.pg+","+Math.round(out*4095*ng)+"\n");sendRaw(b,"P,"+c.pb+","+Math.round(out*4095*nb)+"\n");}else sendRaw(b,"P,"+c.pm+","+Math.round(out*4095)+"\n");return true;}
        static void sendRaw(Board b,String msg){ensureSocket();if(socket==null)return;pool.submit(()->{try{byte[] data=msg.getBytes(StandardCharsets.UTF_8);socket.send(new java.net.DatagramPacket(data,data.length,java.net.InetAddress.getByName(b.host),b.port));}catch(Exception ignored){}});}
        static void receiveLoop(){byte[] buffer=new byte[128];while(socket!=null&&!socket.isClosed()){try{java.net.DatagramPacket packet=new java.net.DatagramPacket(buffer,buffer.length);socket.receive(packet);String response=new String(packet.getData(),packet.getOffset(),packet.getLength(),StandardCharsets.UTF_8).trim();if(response.contains("DIMYX_DISCOVERY")){String id=field(response,"BOARD_ID");String host=field(response,"IP");String port=field(response,"UDP_PORT");if(id.length()>0&&host.length()>0)boards.put(id,new Board(id,host,port.length()>0?Integer.parseInt(port):4210));lastReplyAt=System.currentTimeMillis();}else if(response.endsWith("H"))lastReplyAt=System.currentTimeMillis();}catch(java.net.SocketTimeoutException ignored){}catch(Exception ignored){break;}}}
        static String field(String text,String name){String marker=name+":";int start=text.indexOf(marker);if(start<0)return "";start+=marker.length();int end=text.indexOf(';',start);return (end<0?text.substring(start):text.substring(start,end)).trim();}
        static boolean isConnected(Map<String,Board> targets,long now){return !targets.isEmpty()&&lastReplyAt>0&&now-lastReplyAt<1800;}
    }
}
