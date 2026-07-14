package com.explapp.walklegacy;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.SystemClock;

import java.util.Locale;

public class WalkTrackingService extends Service implements LocationListener {
    public static final String PREFS = "walk_legacy_v3";
    public static final String ACTION_START = "com.explapp.walklegacy.START";
    public static final String ACTION_PAUSE = "com.explapp.walklegacy.PAUSE";
    public static final String ACTION_FINISH = "com.explapp.walklegacy.FINISH";
    public static final String ACTION_RESET = "com.explapp.walklegacy.RESET";
    public static final String ACTION_UPDATE = "com.explapp.walklegacy.UPDATE";
    private static final String CHANNEL = "walk_tracking";
    private static final int NOTIFICATION_ID = 4404;

    private LocationManager locationManager;
    private SharedPreferences prefs;
    private Location lastLocation;
    private long lastAcceptedTime;
    private long startedAtElapsed;
    private long elapsedBeforeStart;
    private long lastSaveElapsed;
    private long lastNotificationElapsed;
    private float distanceMeters;
    private float currentSpeedKmh;
    private float accuracyMeters = -1f;
    private boolean tracking;
    private final Handler handler = new Handler();
    private final Runnable ticker = new Runnable() {
        public void run() {
            if (tracking) {
                if (lastAcceptedTime > 0L && System.currentTimeMillis() - lastAcceptedTime > 8000L) currentSpeedKmh = 0f;
                persist(false);
                broadcastState();
                if (SystemClock.elapsedRealtime() - lastNotificationElapsed >= 15000L) {
                    lastNotificationElapsed = SystemClock.elapsedRealtime();
                    updateNotification();
                }
                handler.postDelayed(this, 2000L);
            }
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        locationManager = (LocationManager) getSystemService(LOCATION_SERVICE);
        restoreState();
        createChannel();
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? null : intent.getAction();
        if (ACTION_START.equals(action)) startTracking();
        else if (ACTION_PAUSE.equals(action)) pauseTracking();
        else if (ACTION_FINISH.equals(action)) finishSession();
        else if (ACTION_RESET.equals(action)) resetSession();
        else if (prefs.getBoolean("tracking", false)) startTracking();
        return START_STICKY;
    }

    @android.annotation.SuppressLint("MissingPermission")
    private void startTracking() {
        if (tracking) { broadcastState(); return; }
        tracking = true;
        startedAtElapsed = SystemClock.elapsedRealtime();
        lastLocation = null;
        lastAcceptedTime = 0L;
        currentSpeedKmh = 0f;
        accuracyMeters = -1f;
        startForeground(NOTIFICATION_ID, notification());
        if (Build.VERSION.SDK_INT >= 23 && checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            stopForLocationFailure();
            return;
        }

        boolean providerRequested = false;
        try {
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 1f, this);
                providerRequested = true;
            }
        } catch (Exception ignored) { }

        try {
            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 3000L, 3f, this);
                providerRequested = true;
            }
        } catch (Exception ignored) { }

        if (!providerRequested) {
            stopForLocationFailure();
            return;
        }

        seedFromLastKnownLocation();
        persist(true);
        handler.removeCallbacks(ticker);
        handler.post(ticker);
        broadcastState();
    }

    @android.annotation.SuppressLint("MissingPermission")
    private void seedFromLastKnownLocation() {
        Location best = null;
        try { best = betterLocation(best, locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)); }
        catch (Exception ignored) { }
        try { best = betterLocation(best, locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)); }
        catch (Exception ignored) { }
        if (best == null) return;
        long age = best.getTime() > 0L ? Math.abs(System.currentTimeMillis() - best.getTime()) : Long.MAX_VALUE;
        if (age <= 120000L) onLocationChanged(best);
    }

    private Location betterLocation(Location current, Location candidate) {
        if (candidate == null) return current;
        if (current == null) return candidate;
        float currentAccuracy = current.hasAccuracy() ? current.getAccuracy() : Float.MAX_VALUE;
        float candidateAccuracy = candidate.hasAccuracy() ? candidate.getAccuracy() : Float.MAX_VALUE;
        if (candidate.getTime() > current.getTime() + 30000L) return candidate;
        return candidateAccuracy < currentAccuracy ? candidate : current;
    }

    private void stopForLocationFailure() {
        tracking = false;
        accuracyMeters = -1f;
        persist(true);
        broadcastState();
        stopForeground(true);
        stopSelf();
    }

    private void pauseTracking() {
        if (tracking) elapsedBeforeStart += SystemClock.elapsedRealtime() - startedAtElapsed;
        tracking = false;
        currentSpeedKmh = 0f;
        lastLocation = null;
        handler.removeCallbacks(ticker);
        try { locationManager.removeUpdates(this); } catch (SecurityException ignored) { }
        persist(true);
        broadcastState();
        stopForeground(true);
        stopSelf();
    }

    private void finishSession() {
        if (tracking) elapsedBeforeStart += SystemClock.elapsedRealtime() - startedAtElapsed;
        tracking = false;
        handler.removeCallbacks(ticker);
        try { locationManager.removeUpdates(this); } catch (SecurityException ignored) { }
        long duration = elapsedBeforeStart;
        float distance = distanceMeters;
        if (duration >= 10000L || distance >= 5f) saveCompletedSession(duration, distance);
        clearCurrent();
        broadcastState();
        stopForeground(true);
        stopSelf();
    }

    private void resetSession() {
        if (tracking) {
            elapsedBeforeStart = 0L;
            startedAtElapsed = SystemClock.elapsedRealtime();
        } else elapsedBeforeStart = 0L;
        distanceMeters = 0f;
        currentSpeedKmh = 0f;
        accuracyMeters = -1f;
        lastLocation = null;
        lastAcceptedTime = 0L;
        persist(true);
        broadcastState();
    }

    @Override public void onLocationChanged(Location location) {
        if (!tracking || location == null) return;
        long now = System.currentTimeMillis();
        if (location.getTime() > 0 && Math.abs(now - location.getTime()) > 120000L) return;
        float accuracy = location.hasAccuracy() ? location.getAccuracy() : 999f;
        accuracyMeters = accuracy;
        if (accuracy > 60f) { broadcastState(); return; }

        long locationTime = location.getTime() > 0L ? location.getTime() : now;
        if (lastLocation != null && locationTime >= lastAcceptedTime) {
            long gapMillis = locationTime - lastAcceptedTime;
            if (gapMillis <= 0L) gapMillis = 2000L;
            float seconds = gapMillis / 1000f;
            float segment = lastLocation.distanceTo(location);
            float previousAccuracy = lastLocation.hasAccuracy() ? lastLocation.getAccuracy() : accuracy;
            float noiseFloor = Math.max(1.5f, (previousAccuracy + accuracy) * .08f);
            float plausibleLimit = Math.max(12f, seconds * 4.5f + Math.min(accuracy, 25f) * .35f);
            if (segment >= noiseFloor && segment <= plausibleLimit && gapMillis <= 20000L) {
                distanceMeters += segment;
                currentSpeedKmh = location.hasSpeed() ? location.getSpeed() * 3.6f : (segment / seconds) * 3.6f;
                currentSpeedKmh = Math.max(0f, Math.min(25f, currentSpeedKmh));
            }
        }
        lastLocation = new Location(location);
        lastAcceptedTime = locationTime;
        persist(false);
        broadcastState();
    }

    private long elapsedMillis() {
        return elapsedBeforeStart + (tracking ? SystemClock.elapsedRealtime() - startedAtElapsed : 0L);
    }

    private void restoreState() {
        distanceMeters = prefs.getFloat("distance", 0f);
        elapsedBeforeStart = prefs.getLong("elapsed", 0L);
        tracking = false;
    }

    private void persist(boolean force) {
        long now = SystemClock.elapsedRealtime();
        if (!force && now - lastSaveElapsed < 10000L) return;
        lastSaveElapsed = now;
        prefs.edit().putFloat("distance", distanceMeters).putLong("elapsed", elapsedMillis())
                .putBoolean("tracking", tracking).putFloat("speed", currentSpeedKmh)
                .putFloat("accuracy", accuracyMeters).apply();
    }

    private void clearCurrent() {
        distanceMeters = 0f;
        elapsedBeforeStart = 0L;
        currentSpeedKmh = 0f;
        accuracyMeters = -1f;
        lastLocation = null;
        lastAcceptedTime = 0L;
        prefs.edit().putFloat("distance", 0f).putLong("elapsed", 0L).putBoolean("tracking", false)
                .putFloat("speed", 0f).putFloat("accuracy", -1f).apply();
    }

    private void saveCompletedSession(long duration, float distance) {
        String current = prefs.getString("sessions", "");
        String item = System.currentTimeMillis() + "," + duration + "," + Math.round(distance);
        String combined = item + (current.length() == 0 ? "" : ";" + current);
        String[] rows = combined.split(";");
        StringBuilder limited = new StringBuilder();
        for (int i = 0; i < rows.length && i < 30; i++) {
            if (limited.length() > 0) limited.append(';');
            limited.append(rows[i]);
        }
        prefs.edit().putString("sessions", limited.toString()).apply();
    }

    private void broadcastState() {
        Intent update = new Intent(ACTION_UPDATE);
        update.setPackage(getPackageName());
        update.putExtra("tracking", tracking);
        update.putExtra("distance", distanceMeters);
        update.putExtra("elapsed", elapsedMillis());
        update.putExtra("speed", currentSpeedKmh);
        update.putExtra("accuracy", accuracyMeters);
        sendBroadcast(update);
    }

    private Notification notification() {
        Intent open = new Intent(this, SoundMainActivity.class);
        int pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 23) pendingFlags |= PendingIntent.FLAG_IMMUTABLE;
        PendingIntent pending = PendingIntent.getActivity(this, 0, open, pendingFlags);
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, CHANNEL) : new Notification.Builder(this);
        return builder.setSmallIcon(R.drawable.ic_walk_notification)
                .setContentTitle("رفيق المشي • التتبع نشط")
                .setContentText(String.format(Locale.US, "%.2f كم • %s", distanceMeters / 1000f, formatTime(elapsedMillis())))
                .setContentIntent(pending).setOngoing(true).setOnlyAlertOnce(true).setShowWhen(false).build();
    }

    private void updateNotification() {
        ((NotificationManager) getSystemService(NOTIFICATION_SERVICE)).notify(NOTIFICATION_ID, notification());
    }

    private void createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(CHANNEL, "تتبع المشي", NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("إشعار صامت أثناء جلسة المشي فقط");
            channel.setSound(null, null);
            ((NotificationManager) getSystemService(NOTIFICATION_SERVICE)).createNotificationChannel(channel);
        }
    }

    private String formatTime(long millis) {
        long seconds = millis / 1000L;
        return String.format(Locale.US, "%02d:%02d:%02d", seconds / 3600L, (seconds % 3600L) / 60L, seconds % 60L);
    }

    @Override public void onProviderDisabled(String provider) { accuracyMeters = -1f; broadcastState(); }
    @Override public void onProviderEnabled(String provider) { broadcastState(); }
    @Override public void onStatusChanged(String provider, int status, Bundle extras) { }
    @Override public IBinder onBind(Intent intent) { return null; }
    @Override public void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        try { locationManager.removeUpdates(this); } catch (SecurityException ignored) { }
        if (tracking) persist(true);
        super.onDestroy();
    }
}
