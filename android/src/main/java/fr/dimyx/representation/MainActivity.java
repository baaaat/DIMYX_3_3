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
            c.drawColor(Color.rgb(20, 21, 27));
            text(c, "DIMYX 3.3  /  REPRESENTATION", 24, 32, 20, Color.WHITE);
            text(c, engine.status, 24, 58, 14, engine.online ? Color.rgb(104,220,167) : Color.rgb(247,169,109));
            button(c, new RectF(w - 174, 14, w - 24, 58), "BLACKOUT", Color.rgb(191,37,63));
            String[] labels = {"SCENES", "CONFIG", "CARTES"};
            button(c, new RectF(w - 330, 14, w - 190, 58), labels[pickKind], Color.rgb(60,76,106));

            int left = 20, top = 86, gap = 10;
            int sceneX = Math.max(w - 300, 610);
            int channelW = Math.max(92, (sceneX - left - 4 * gap) / 5);
            for (int visible = 0; visible < 5; visible++) {
                int index = page * 5 + visible;
                if (index >= engine.channels.size()) break;
                drawChannel(c, engine.channels.get(index), left + visible * (channelW + gap), top, channelW, h - top - 24);
            }
            button(c, new RectF(left, h - 38, left + 82, h - 8), "◀ 1–5", Color.rgb(55,62,78));
            button(c, new RectF(left + 90, h - 38, left + 172, h - 8), "6–10 ▶", Color.rgb(55,62,78));
            drawScenes(c, sceneX, top, w - sceneX - 20, h - top - 24);
        }

        private void drawChannel(Canvas c, Channel ch, int x, int y, int w, int h) {
            p.setColor(Color.rgb(35,38,48)); c.drawRoundRect(new RectF(x,y,x+w,y+h), 14,14,p);
            text(c, ch.name, x + 10, y + 27, 15, Color.WHITE);
            int color = Color.rgb(ch.colorR, ch.colorG, ch.colorB);
            p.setColor(color); c.drawCircle(x+w/2f, y+66, 24, p);
            text(c, ch.sequencer.active ? "SEQ" : (ch.fxMode == 0 ? "MAN" : ch.effectName()), x+10, y+112, 12, Color.LTGRAY);
            text(c, String.format(Locale.US, "%d%%", Math.round(ch.gain * 100)), x+w/2f-18, y+112, 12, Color.WHITE);
            float fy = y + 130, fh = h - 160;
            p.setColor(Color.rgb(65,70,84)); c.drawRoundRect(new RectF(x+w/2f-10,fy,x+w/2f+10,fy+fh),10,10,p);
            float knob = fy + fh * (1f - ch.gain);
            p.setColor(Color.rgb(104,220,167)); c.drawRoundRect(new RectF(x+8,knob-9,x+w-8,knob+9),9,9,p);
            text(c, "TACTILE", x+10, y+h-12, 10, Color.GRAY);
        }

        private void drawScenes(Canvas c, int x, int y, int w, int h) {
            text(c, "SCÈNES", x, y + 24, 18, Color.WHITE);
            int row = 48;
            int first = engine.scenePage * 8;
            for (int i=0; i<8 && first+i<engine.scenes.size(); i++) {
                int idx=first+i; RectF r=new RectF(x,y+38+i*row,x+w,y+78+i*row);
                button(c,r,engine.scenes.get(idx).name, idx==engine.activeScene ? Color.rgb(55,98,82) : Color.rgb(48,52,64));
            }
            text(c, (first+1)+"–"+Math.min(first+8,engine.scenes.size())+" / "+engine.scenes.size(), x, y+h-12, 12, Color.GRAY);
        }

        private void button(Canvas c, RectF r, String s, int color) {
            p.setColor(color); c.drawRoundRect(r,10,10,p);
            p.setTextAlign(Paint.Align.CENTER); text(c,s,r.centerX(),r.centerY()+5,13,Color.WHITE); p.setTextAlign(Paint.Align.LEFT);
        }
        private void text(Canvas c,String s,float x,float y,float size,int color){p.setTextSize(size);p.setColor(color);c.drawText(s,x,y,p);}

        @Override public boolean onTouchEvent(MotionEvent e) {
            int w=getWidth(), h=getHeight(); float x=e.getX(), y=e.getY();
            if (e.getAction()==MotionEvent.ACTION_DOWN) {
                if (x>w-190 && y<70) { engine.blackout(); invalidate(); return true; }
                if (x>w-340 && x<w-180 && y<70) { pickJson(pickKind); return true; }
                if (y>h-50 && x<190) { page=x<90?0:1; invalidate(); return true; }
                int sceneX=Math.max(w-300,610);
                if (x>=sceneX && y>86) {
                    int slot=(int)((y-124)/48); int idx=engine.scenePage*8+slot;
                    if(slot>=0 && idx<engine.scenes.size()){engine.launch(idx);invalidate();} return true;
                }
                int left=20, top=86, gap=10, channelW=Math.max(92,(sceneX-left-4*gap)/5);
                int visible=(int)((x-left)/(channelW+gap)); int idx=page*5+visible;
                if(visible>=0&&visible<5&&idx<engine.channels.size()){activeFader=idx; setFader(y,top,h); return true;}
            } else if ((e.getAction()==MotionEvent.ACTION_MOVE || e.getAction()==MotionEvent.ACTION_UP) && activeFader>=0) {
                setFader(y,86,h); if(e.getAction()==MotionEvent.ACTION_UP) activeFader=-1; return true;
            }
            return true;
        }
        private void setFader(float y,int top,int h){ float t=1f-(y-top-130)/(float)(h-top-184); engine.setGain(activeFader,Math.max(0,Math.min(1,t))); invalidate(); }
    }

    static class Step { int i; int r=255,g=255,b=255; }
    static class SceneState { int m,fx,min; float f=1,bpm=120; int r=255,g=255,b=255; boolean sa; ArrayList<Step> steps=new ArrayList<>(); }
    static class Scene { String name; SceneState[] states=new SceneState[10]; }
    static class Channel { String name="Tranche"; boolean rgb; int pm=3,pr=3,pg=5,pb=6; String board="USB"; int colorR=255,colorG=255,colorB=255; int manual,fx,min; float freq=1,bpm=120; boolean seq; ArrayList<Step> steps=new ArrayList<>(); int current; long nextStep; float gain=1; SceneState target; int startManual,startR,startG,startB; long transitionStart; String effectName(){return fx==1?"STR":fx==2?"FEU":fx==3?"PUL":"MAN";} }

    class ShowEngine {
        ArrayList<Channel> channels=new ArrayList<>(); ArrayList<Scene> scenes=new ArrayList<>();
        Map<String,Board> boards=new HashMap<>(); int activeScene=-1,scenePage; boolean blackout; boolean online; String status="SPECTACLE DEMO — ESP32 DECONNECTE";
        long lastHeartbeat;
        ShowEngine(){ for(int i=0;i<10;i++){Channel c=new Channel();c.name="Tranche "+(i+1);channels.add(c);} loadDemo(); }
        void loadDemo(){ Scene s=new Scene();s.name="Démonstration";for(int i=0;i<10;i++){s.states[i]=new SceneState();s.states[i].m=i<2?4095:0;s.states[i].r=255;s.states[i].g=i==1?80:255;s.states[i].b=255;}scenes.add(s); }
        void loadScenes(String raw)throws Exception{JSONArray a=new JSONArray(raw);scenes.clear();for(int n=0;n<a.length();n++){JSONObject j=a.getJSONObject(n);Scene s=new Scene();s.name=j.optString("name","Scène "+(n+1));JSONArray states=j.getJSONArray("states");for(int i=0;i<10;i++){JSONObject q=states.getJSONObject(i);SceneState z=new SceneState();z.m=q.optInt("m");z.fx=q.optInt("fx");z.min=q.optInt("min");z.f=(float)q.optDouble("f",1);z.bpm=(float)q.optDouble("bpm",120);z.r=q.optInt("cr",255);z.g=q.optInt("cg",255);z.b=q.optInt("cb",255);z.sa=q.optBoolean("sa");JSONArray steps=q.optJSONArray("steps");if(steps!=null)for(int k=0;k<steps.length();k++){JSONObject p=steps.getJSONObject(k);Step t=new Step();t.i=p.optInt("i");t.r=p.optInt("r",255);t.g=p.optInt("g",255);t.b=p.optInt("b",255);z.steps.add(t);}s.states[i]=z;}scenes.add(s);}status="SPECTACLE CHARGE — ESP32 DECONNECTE";}
        void loadChannels(String raw)throws Exception{JSONObject root=new JSONObject(raw);JSONArray a=root.getJSONArray("channels");for(int i=0;i<Math.min(10,a.length());i++){JSONObject q=a.getJSONObject(i);Channel c=channels.get(i);c.name=q.optString("name",c.name);c.rgb=q.optBoolean("rgb",false);c.pm=q.optInt("pm",c.pm);c.pr=q.optInt("pr",c.pr);c.pg=q.optInt("pg",c.pg);c.pb=q.optInt("pb",c.pb);c.board=q.optString("board","USB");if(!c.board.equalsIgnoreCase("USB")&&!boards.containsKey(c.board))boards.put(c.board,new Board(c.board,"192.168.4.1",4210));}status="CONFIGURATION CHARGEE — ESP32 DECONNECTE";}
        void loadBoards(String raw)throws Exception{JSONObject root=new JSONObject(raw);JSONArray a=root.getJSONArray("boards");for(int i=0;i<a.length();i++){JSONObject q=a.getJSONObject(i);if(!q.optBoolean("enabled",true))continue;String id=q.optString("id",q.optString("board"));if(id.length()>0)boards.put(id,new Board(id,q.optString("host","192.168.4.1"),q.optInt("port",4210)));}status="CARTES CHARGEES — ESP32 DECONNECTE";}
        void launch(int idx){if(idx<0||idx>=scenes.size())return;Scene s=scenes.get(idx);long now=System.currentTimeMillis();for(int i=0;i<10;i++){SceneState z=s.states[i];Channel c=channels.get(i);c.startManual=c.manual;c.startR=c.colorR;c.startG=c.colorG;c.startB=c.colorB;c.target=z;c.transitionStart=now;c.gain=1;}activeScene=idx;blackout=false;status="TRANSITION : "+s.name+" — "+(online?"WIFI OK":"ESP32 DECONNECTE");}
        void setGain(int i,float v){if(i>=0&&i<channels.size())channels.get(i).gain=v;}
        void blackout(){blackout=true;for(Channel c:channels){c.gain=0;c.seq=false;}Network.sendAllBlackout(boards);status="BLACKOUT — "+(online?"WIFI OK":"ESP32 DECONNECTE");}
        void update(long now){for(Channel c:channels){if(c.target!=null){float t=Math.min(1,(now-c.transitionStart)/600f);c.manual=Math.round(c.startManual+(c.target.m-c.startManual)*t);c.colorR=Math.round(c.startR+(c.target.r-c.startR)*t);c.colorG=Math.round(c.startG+(c.target.g-c.startG)*t);c.colorB=Math.round(c.startB+(c.target.b-c.startB)*t);if(t>=1){SceneState z=c.target;c.target=null;c.fx=z.fx==4?0:z.fx;c.min=z.min;c.freq=z.f;c.bpm=Math.max(20,z.bpm);c.seq=z.sa;c.steps=new ArrayList<>(z.steps);c.current=0;c.nextStep=now;status=status.replace("TRANSITION : ","SCÈNE : ");}}if(c.seq&&!c.steps.isEmpty()&&now>=c.nextStep){c.current=(c.current+1)%c.steps.size();c.nextStep=now+(long)(60000.0/Math.max(20,c.bpm)/4);}}if(now-lastHeartbeat>500){Network.heartbeat(boards);lastHeartbeat=now;}send(now);}
        void send(long now){if(now%33>18)return;boolean any=false;for(Channel c:channels){float effect=1;float minN=c.min/4095f;if(c.fx==1)effect=(now%(long)(1000/Math.max(.1,c.freq))<500/Math.max(.1,c.freq))?1:minN;else if(c.fx==2)effect=(float)(minN+(1-minN)*((Math.sin(now*.013*c.freq+c.name.hashCode())+1)/2));else if(c.fx==3)effect=(float)(minN+(1-minN)*(Math.sin(now*.005*c.freq)+1)/2);float source=c.seq&&!c.steps.isEmpty()?c.steps.get(c.current).i/4095f:c.manual/4095f;float out=blackout?0:source*c.gain*effect;if(Network.send(c,out))any=true;}if(any)online=true;}
    }
    static class Board { String id,host; int port; Board(String i,String h,int p){id=i;host=h;port=p;} }
    static class Network {
        static final java.util.concurrent.ExecutorService pool=java.util.concurrent.Executors.newSingleThreadExecutor();
        static Map<String,Board> boards= new HashMap<>();
        static void heartbeat(Map<String,Board> b){boards=b;pool.submit(()->{for(Board x:b.values())sendRaw(x,"H\n");});}
        static void sendAllBlackout(Map<String,Board> b){for(Board x:b.values())sendRaw(x,"X\n");}
        static boolean send(Channel c,float out){if(c.board==null||c.board.equalsIgnoreCase("USB"))return false;Board b=boards.get(c.board);if(b==null){b=new Board(c.board,"192.168.4.1",4210);boards.put(c.board,b);}if(c.rgb){sendRaw(b,"P,"+c.pr+","+Math.round(out*4095*c.colorR/255f)+"\n");sendRaw(b,"P,"+c.pg+","+Math.round(out*4095*c.colorG/255f)+"\n");sendRaw(b,"P,"+c.pb+","+Math.round(out*4095*c.colorB/255f)+"\n");}else sendRaw(b,"P,"+c.pm+","+Math.round(out*4095)+"\n");return true;}
        static void sendRaw(Board b,String msg){try(java.net.DatagramSocket s=new java.net.DatagramSocket()){byte[] data=msg.getBytes(StandardCharsets.UTF_8);s.send(new java.net.DatagramPacket(data,data.length,java.net.InetAddress.getByName(b.host),b.port));}catch(Exception ignored){}}
    }
}
