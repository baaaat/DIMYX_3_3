package fr.dimyx.representation;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.PowerManager;

/** Maintient la sortie DIMYX quand l’Activity est suspendue écran éteint. */
public class BackgroundOutputService extends Service {
    private static final String CHANNEL = "dimyx-output";
    private final Handler handler = new Handler();
    private PowerManager.WakeLock wakeLock;
    private WifiManager.WifiLock wifiLock;
    private final Runnable tick = new Runnable() {
        @Override public void run() {
            MainActivity.ShowEngine engine = MainActivity.sharedEngine;
            if (engine != null) engine.update(System.currentTimeMillis());
            handler.postDelayed(this, 33);
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        Notification notification = new Notification.Builder(this, CHANNEL)
                .setContentTitle("DIMYX — sortie active")
                .setContentText("Le spectacle continue écran éteint")
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setOngoing(true)
                .build();
        startForeground(17, notification);

        PowerManager power = (PowerManager)getSystemService(POWER_SERVICE);
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DIMYX:Output");
        wakeLock.acquire();
        WifiManager wifi = (WifiManager)getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifi != null) {
            wifiLock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "DIMYX:Wifi");
            wifiLock.acquire();
        }
        handler.post(tick);
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override public void onDestroy() {
        handler.removeCallbacks(tick);
        if (wifiLock != null && wifiLock.isHeld()) wifiLock.release();
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) { return null; }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(CHANNEL, "Sortie DIMYX", NotificationManager.IMPORTANCE_LOW);
            getSystemService(NotificationManager.class).createNotificationChannel(channel);
        }
    }
}
