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
import android.os.Build;

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
    static ShowEngine sharedEngine;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        engine = new ShowEngine();
        sharedEngine = engine;
        console = new ConsoleView();
        setContentView(console);
    }

    @Override protected void onPause() {
        super.onPause();
        if (!isFinishing()) {
            Intent service = new Intent(this, BackgroundOutputService.class);
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(service); else startService(service);
        }
    }

    @Override protected void onResume() {
        super.onResume();
        stopService(new Intent(this, BackgroundOutputService.class));
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
        private int screen = 0; // 0 configuration, 1 scènes

        ConsoleView() { super(MainActivity.this); p.setTypeface(android.graphics.Typeface.create("sans", 0)); }

        @Override protected void onDraw(Canvas c) {
            super.onDraw(c);
            long now = System.currentTimeMillis();
            engine.update(now);
            if (screen == 0) drawConfiguration(c); else drawScenesScreen(c);
            postInvalidateDelayed(33);
        }

        private void drawConfiguration(Canvas c) {
            int w=getWidth(),h=getHeight(), bg=Color.rgb(32,36,45), panel=Color.rgb(48,54,67), accent=Color.rgb(104,167,177), secondary=Color.rgb(174,185,201);
            c.drawColor(bg); p.setColor(panel); c.drawRect(0,0,w,64,p);
            text(c,"DIMYX — CONFIGURATION",20,28,19,Color.WHITE); text(c,engine.connectionLabel(),20,50,11,engine.connectionColor());
            text(c,"Préparer le spectacle puis ouvrir l’écran des scènes.",20,96,14,secondary);
            int bw=Math.min(520,w-40), x=(w-bw)/2;
            button(c,new RectF(x,122,x+bw,180),"CHARGER SCENES.JSON",accent,Color.WHITE,15);
            button(c,new RectF(x,194,x+bw,252),"CHARGER CHANNELCONFIG.JSON",panel,Color.WHITE,15);
            button(c,new RectF(x,266,x+bw,324),"CHARGER ESP32BOARDS.JSON (OPTIONNEL)",panel,Color.WHITE,13);
            button(c,new RectF(x,Math.min(h-112,350),x+bw,Math.min(h-54,408)),"OUVRIR LES SCÈNES",Color.rgb(66,73,87),Color.WHITE,15);
            text(c,"Écran maintenu actif pendant la représentation.",20,h-22,11,secondary);
            button(c,new RectF(w-126,h-52,w-12,h-12),"BLACKOUT",Color.rgb(164,47,65),Color.WHITE,12);
        }

        private void drawScenesScreen(Canvas c) {
            int w=getWidth(),h=getHeight(), bg=Color.rgb(32,36,45), panel=Color.rgb(48,54,67), secondary=Color.rgb(174,185,201);
            c.drawColor(bg); p.setColor(panel); c.drawRect(0,0,w,64,p);
            text(c,"DIMYX — SCÈNES",20,28,19,Color.WHITE); text(c,engine.connectionLabel(),20,50,11,engine.connectionColor());
            button(c,new RectF(w-250,12,w-138,52),"CONFIG",Color.rgb(66,73,87),Color.WHITE,12);
            button(c,new RectF(w-126,12,w-12,52),"BLACKOUT",Color.rgb(164,47,65),Color.WHITE,12);
            int margin=16, top=82, bottom=h-54, gap=10, cols=w<700?2:(w<1100?3:4), rowH=Math.max(58,Math.min(88,(bottom-top)/Math.max(1,Math.min(6,(engine.scenes.size()+cols-1)/cols))));
            int rows=Math.max(1,(bottom-top)/rowH), perPage=cols*rows, first=engine.scenePage*perPage;
            for(int i=0;i<perPage&&first+i<engine.scenes.size();i++){int idx=first+i;int col=i%cols,row=i/cols;float bw=(w-2*margin-(cols-1)*gap)/(float)cols;RectF r=new RectF(margin+col*(bw+gap),top+row*rowH,margin+(col+1)*bw-gap,top+row*rowH+rowH-gap);button(c,r,(idx+1)+". "+engine.scenes.get(idx).name,idx==engine.activeScene?Color.rgb(104,167,177):sceneColor(idx),Color.WHITE,Math.max(12,Math.min(18,bw/18)));}
            text(c,engine.scenes.isEmpty()?"AUCUNE SCÈNE":(first+1)+"–"+Math.min(first+perPage,engine.scenes.size())+" / "+engine.scenes.size()+"    SCÈNE ACTIVE : "+engine.currentSceneName(),margin,h-22,12,secondary);
            if(engine.scenePage>0)button(c,new RectF(w-210,h-46,w-112,h-10),"PRÉCÉDENT",panel,Color.WHITE,11);
            if((engine.scenePage+1)*perPage<engine.scenes.size())button(c,new RectF(w-104,h-46,w-12,h-10),"SUIVANT",panel,Color.WHITE,11);
        }

        private int sceneColor(int index){int[] colors={Color.rgb(68,87,111),Color.rgb(73,101,105),Color.rgb(92,81,113),Color.rgb(105,82,71),Color.rgb(65,99,87),Color.rgb(83,86,102)};return colors[index%colors.length];}
        private void button(Canvas c, RectF r, String s, int color, int textColor, float size) {
            p.setColor(color); c.drawRoundRect(r,10,10,p);
            p.setTextAlign(Paint.Align.CENTER); text(c,s,r.centerX(),r.centerY()+size*.35f,size,textColor); p.setTextAlign(Paint.Align.LEFT);
        }
        private void text(Canvas c,String s,float x,float y,float size,int color){p.setTextSize(size);p.setColor(color);c.drawText(s,x,y,p);}

        @Override public boolean onTouchEvent(MotionEvent e) {
            int w=getWidth(), h=getHeight(); float x=e.getX(), y=e.getY();
            if (e.getAction()!=MotionEvent.ACTION_DOWN) return true;
            if ((x>w-140 && y<70)||(x>w-140&&y>h-70)) { engine.blackout(); invalidate(); return true; }
            if(screen==0){int bw=Math.min(520,w-40),x0=(w-bw)/2,openY=Math.min(h-112,350);if(y>=122&&y<180)pickJson(0);else if(y>=194&&y<252)pickJson(1);else if(y>=266&&y<324)pickJson(2);else if(y>=openY&&y<openY+58){screen=1;invalidate();}return true;}
            if(y<70&&x>w-270&&x<w-130){screen=0;invalidate();return true;}
            int margin=16,top=82,bottom=h-54,gap=10,cols=w<700?2:(w<1100?3:4),rowH=Math.max(58,Math.min(88,(bottom-top)/Math.max(1,Math.min(6,(engine.scenes.size()+cols-1)/cols)))),rows=Math.max(1,(bottom-top)/rowH),perPage=cols*rows,first=engine.scenePage*perPage;
            if(y>=top&&y<bottom){int col=(int)((x-margin)/((w-2*margin-(cols-1)*gap)/(float)cols+gap)),row=(int)((y-top)/rowH),idx=first+row*cols+col;if(col>=0&&col<cols&&row>=0&&row<rows&&idx<engine.scenes.size()){engine.launch(idx);invalidate();}return true;}
            if(y>h-54&&x>w-220&&x<w-110&&engine.scenePage>0){engine.scenePage--;invalidate();return true;}
            if(y>h-54&&x>w-112&&(engine.scenePage+1)*perPage<engine.scenes.size()){engine.scenePage++;invalidate();return true;}
            return true;
        }
    }

    static class Step { int i; int r=255,g=255,b=255; }
    static class SceneState { int m,fx,min; float f=1,bpm=120; int r=255,g=255,b=255; boolean sa; ArrayList<Step> steps=new ArrayList<>(); }
    static class Scene { String name; SceneState[] states=new SceneState[10]; }
    static class Channel { String name="Tranche"; boolean rgb; int pm=3,pr=3,pg=5,pb=6; String board="USB"; int colorR=255,colorG=255,colorB=255; float whiteR=1,whiteG=1,whiteB=1; int manual,fx,min; float freq=1,bpm=120; boolean seq; ArrayList<Step> steps=new ArrayList<>(); int current; long nextStep; float gain=1; SceneState target; int startManual,startR,startG,startB; long transitionStart; float visibleLevel(){float source=seq&&!steps.isEmpty()?steps.get(current).i/4095f:manual/4095f;return Math.max(0,Math.min(1,source*gain));} String effectName(){return fx==1?"STR":fx==2?"FEU":fx==3?"PUL":"MAN";} }

    static class ShowEngine {
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
