package com.explapp.walklegacy;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.os.PowerManager;
import android.os.SystemClock;

public class LocationTrackingService extends Service implements LocationListener {
    public static final String ACTION_UPDATE = "com.explapp.walklegacy.UPDATE";
    public static final String ACTION_STOP = "com.explapp.walklegacy.STOP";
    public static final String EXTRA_DISTANCE = "distance";
    public static final String EXTRA_ACCURACY = "accuracy";
    public static final String EXTRA_ELAPSED = "elapsed";
    public static final String EXTRA_STATUS = "status";

    private static final String CHANNEL_ID = "walk_tracking";
    private static final int NOTIFICATION_ID = 4044;
    private static final long MIN_TIME_MS = 1500L;
    private static final float MIN_DISTANCE_M = 1.5f;

    private LocationManager locationManager;
    private Location lastAccepted;
    private double distanceMeters;
    private long startElapsed;
    private PowerManager.WakeLock wakeLock;
    private SharedPreferences prefs;

    @Override public void onCreate() {
        super.onCreate();
        prefs = getSharedPreferences("walk_legacy", MODE_PRIVATE);
        distanceMeters = prefs.getFloat("distance", 0f);
        startElapsed = prefs.getLong("start_elapsed", SystemClock.elapsedRealtime());
        locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
        PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "WalkLegacy:Tracking");
        wakeLock.setReferenceCounted(false);
        wakeLock.acquire();
        createChannel();
        startForeground(NOTIFICATION_ID, buildNotification("جاري البحث عن إشارة GPS"));
        requestProviders();
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_STOP.equals(intent.getAction())) {
            stopSelf();
            return START_NOT_STICKY;
        }
        if (startElapsed <= 0) startElapsed = SystemClock.elapsedRealtime();
        prefs.edit().putBoolean("tracking", true).putLong("start_elapsed", startElapsed).apply();
        requestProviders();
        return START_STICKY;
    }

    @SuppressWarnings("MissingPermission")
    private void requestProviders() {
        if (locationManager == null) return;
        try {
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, MIN_TIME_MS, MIN_DISTANCE_M, this);
                Location cached = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER);
                if (cached != null) onLocationChanged(cached);
            }
        } catch (Exception ignored) { }
        try {
            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 3000L, 3f, this);
                Location cached = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER);
                if (cached != null && lastAccepted == null) onLocationChanged(cached);
            }
        } catch (Exception ignored) { }
    }

    @Override public void onLocationChanged(Location location) {
        if (location == null) return;
        float accuracy = location.hasAccuracy() ? location.getAccuracy() : 999f;
        long ageMs = Math.abs(System.currentTimeMillis() - location.getTime());
        if (ageMs > 120000L && lastAccepted != null) return;

        boolean acceptable = accuracy <= 120f || lastAccepted == null;
        if (!acceptable) {
            broadcast("إشارة ضعيفة، مستمر في البحث", accuracy);
            return;
        }

        if (lastAccepted != null) {
            float segment = lastAccepted.distanceTo(location);
            long dtMs = Math.max(1L, location.getTime() - lastAccepted.getTime());
            float speedMps = segment / (dtMs / 1000f);
            float noiseFloor = Math.max(1.5f, Math.min(8f, accuracy * 0.12f));
            if (segment >= noiseFloor && segment <= 100f && speedMps <= 12f) {
                distanceMeters += segment;
            }
        }

        lastAccepted = location;
        prefs.edit().putFloat("distance", (float) distanceMeters).apply();
        String status = accuracy <= 20f ? "إشارة ممتازة" : accuracy <= 50f ? "إشارة جيدة" : "إشارة مقبولة";
        broadcast(status, accuracy);
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (nm != null) nm.notify(NOTIFICATION_ID, buildNotification(status + " • " + Math.round(distanceMeters) + " م"));
    }

    private void broadcast(String status, float accuracy) {
        long elapsed = Math.max(0L, (SystemClock.elapsedRealtime() - startElapsed) / 1000L);
        Intent update = new Intent(ACTION_UPDATE);
        update.setPackage(getPackageName());
        update.putExtra(EXTRA_DISTANCE, distanceMeters);
        update.putExtra(EXTRA_ACCURACY, accuracy);
        update.putExtra(EXTRA_ELAPSED, elapsed);
        update.putExtra(EXTRA_STATUS, status);
        sendBroadcast(update);
    }

    private Notification buildNotification(String text) {
        Intent open = new Intent(this, MainActivity.class);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 23) flags |= PendingIntent.FLAG_IMMUTABLE;
        PendingIntent pi = PendingIntent.getActivity(this, 0, open, flags);
        Notification.Builder b = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, CHANNEL_ID) : new Notification.Builder(this);
        return b.setContentTitle("رفيق المشي")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentIntent(pi)
                .setOngoing(true)
                .build();
    }

    private void createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            NotificationChannel channel = new NotificationChannel(CHANNEL_ID, "تتبع المشي", NotificationManager.IMPORTANCE_LOW);
            channel.setSound(null, null);
            if (nm != null) nm.createNotificationChannel(channel);
        }
    }

    @Override public void onProviderDisabled(String provider) { broadcast("خدمة الموقع متوقفة", 999f); }
    @Override public void onProviderEnabled(String provider) { requestProviders(); }
    @Override public void onStatusChanged(String provider, int status, Bundle extras) { }
    @Override public IBinder onBind(Intent intent) { return null; }

    @Override public void onDestroy() {
        if (locationManager != null) {
            try { locationManager.removeUpdates(this); } catch (Exception ignored) { }
        }
        prefs.edit().putBoolean("tracking", false).apply();
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        super.onDestroy();
    }
}
