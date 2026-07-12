package com.explapp.walklegacy;

import android.Manifest;
import android.app.Activity;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.Locale;

public class MainActivity extends Activity implements LocationListener {
    private static final String PREFS = "walk_legacy";
    private LocationManager locationManager;
    private TextView statusView;
    private TextView distanceView;
    private TextView speedView;
    private TextView timeView;
    private TextView accuracyView;
    private TextView goalView;
    private Button startButton;
    private Location lastLocation;
    private float totalMeters;
    private float goalMeters;
    private boolean tracking;
    private long startedAtElapsed;
    private long elapsedBeforeStart;

    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        loadSavedState();

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(28, 32, 28, 28);
        root.setBackgroundColor(android.graphics.Color.rgb(244, 250, 247));

        TextView title = createText("مساعد المشي", 28);
        statusView = createText("جاهز لبدء المشي", 18);
        distanceView = createText("", 27);
        goalView = createText("", 17);
        speedView = createText("السرعة: 0.0 كم/س", 20);
        timeView = createText("", 20);
        accuracyView = createText("دقة GPS: غير متوفرة", 16);

        startButton = new Button(this);
        startButton.setText("بدء المشي");
        startButton.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { toggleTracking(); }
        });

        Button goalButton = new Button(this);
        goalButton.setText("تغيير الهدف اليومي: " + Math.round(goalMeters / 1000f) + " كم");
        goalButton.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { cycleGoal(); goalButton.setText("تغيير الهدف اليومي: " + Math.round(goalMeters / 1000f) + " كم"); }
        });

        Button resetButton = new Button(this);
        resetButton.setText("تصفير الرحلة");
        resetButton.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { resetTrip(); }
        });

        root.addView(title);
        root.addView(statusView);
        root.addView(distanceView);
        root.addView(goalView);
        root.addView(speedView);
        root.addView(timeView);
        root.addView(accuracyView);
        root.addView(startButton);
        root.addView(goalButton);
        root.addView(resetButton);
        setContentView(root);

        locationManager = (LocationManager) getSystemService(LOCATION_SERVICE);
        refreshViews();
    }

    private TextView createText(String text, int size) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(size);
        view.setGravity(Gravity.CENTER);
        view.setPadding(8, 12, 8, 12);
        return view;
    }

    private void toggleTracking() {
        if (tracking) {
            stopTracking();
            return;
        }
        if (Build.VERSION.SDK_INT >= 23 && checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION}, 7);
            return;
        }
        startTracking();
    }

    private void startTracking() {
        try {
            if (!locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                statusView.setText("يرجى تشغيل GPS أولاً");
                return;
            }
            tracking = true;
            lastLocation = null;
            startedAtElapsed = SystemClock.elapsedRealtime();
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 2000L, 2f, this);
            statusView.setText("جاري تتبع المشي عبر GPS");
            startButton.setText("إيقاف المشي");
            refreshViews();
        } catch (SecurityException e) {
            tracking = false;
            statusView.setText("يرجى السماح باستخدام الموقع");
        }
    }

    private void stopTracking() {
        if (!tracking) return;
        tracking = false;
        elapsedBeforeStart += SystemClock.elapsedRealtime() - startedAtElapsed;
        locationManager.removeUpdates(this);
        lastLocation = null;
        statusView.setText("تم إيقاف التتبع");
        startButton.setText("متابعة المشي");
        speedView.setText("السرعة: 0.0 كم/س");
        saveState();
        refreshViews();
    }

    private void resetTrip() {
        if (tracking) stopTracking();
        totalMeters = 0f;
        elapsedBeforeStart = 0L;
        lastLocation = null;
        statusView.setText("تم تصفير الرحلة");
        accuracyView.setText("دقة GPS: غير متوفرة");
        startButton.setText("بدء المشي");
        saveState();
        refreshViews();
    }

    private long currentElapsedMillis() {
        if (tracking) return elapsedBeforeStart + (SystemClock.elapsedRealtime() - startedAtElapsed);
        return elapsedBeforeStart;
    }

    private void refreshViews() {
        if (distanceView == null) return;
        if (totalMeters < 1000f) {
            distanceView.setText("المسافة: " + Math.round(totalMeters) + " متر");
        } else {
            distanceView.setText(String.format(Locale.US, "المسافة: %.2f كم", totalMeters / 1000f));
        }
        long totalSeconds = currentElapsedMillis() / 1000L;
        long hours = totalSeconds / 3600L;
        long minutes = (totalSeconds % 3600L) / 60L;
        long seconds = totalSeconds % 60L;
        timeView.setText(String.format(Locale.US, "المدة: %02d:%02d:%02d", hours, minutes, seconds));
        float progress = goalMeters > 0f ? Math.min(100f, (totalMeters * 100f) / goalMeters) : 0f;
        goalView.setText(String.format(Locale.US, "هدف اليوم: %.0f / %.0f متر  (%.0f%%)", totalMeters, goalMeters, progress));
        if (tracking) {
            timeView.postDelayed(new Runnable() {
                @Override public void run() {
                    if (tracking) refreshViews();
                }
            }, 1000L);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (requestCode == 7 && results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) {
            startTracking();
        } else if (requestCode == 7) {
            statusView.setText("لم يتم منح صلاحية الموقع");
        }
    }

    @Override
    public void onLocationChanged(Location location) {
        if (!tracking) return;
        float accuracy = location.hasAccuracy() ? location.getAccuracy() : 999f;
        accuracyView.setText("دقة GPS: " + Math.round(accuracy) + " متر");

        if (lastLocation != null && accuracy <= 40f) {
            float segment = lastLocation.distanceTo(location);
            if (segment >= 1f && segment <= 100f) totalMeters += segment;
        }
        lastLocation = location;

        float kmh = location.hasSpeed() ? location.getSpeed() * 3.6f : 0f;
        speedView.setText(String.format(Locale.US, "السرعة: %.1f كم/س", kmh));
        saveState();
        refreshViews();
    }

    private void cycleGoal() {
        if (goalMeters < 3000f) goalMeters = 3000f;
        else if (goalMeters < 5000f) goalMeters = 5000f;
        else if (goalMeters < 10000f) goalMeters = 10000f;
        else goalMeters = 1000f;
        saveState();
        refreshViews();
    }

    private void loadSavedState() {
        SharedPreferences preferences = getSharedPreferences(PREFS, MODE_PRIVATE);
        totalMeters = preferences.getFloat("distance", 0f);
        elapsedBeforeStart = preferences.getLong("elapsed", 0L);
        goalMeters = preferences.getFloat("goal", 3000f);
    }

    private void saveState() {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putFloat("distance", totalMeters)
                .putLong("elapsed", currentElapsedMillis())
                .putFloat("goal", goalMeters)
                .apply();
    }

    @Override protected void onPause() {
        super.onPause();
        if (tracking) saveState();
    }

    @Override protected void onDestroy() {
        if (locationManager != null) locationManager.removeUpdates(this);
        super.onDestroy();
    }

    @Override public void onStatusChanged(String provider, int statusCode, Bundle extras) {}
    @Override public void onProviderEnabled(String provider) { statusView.setText("GPS متاح"); }
    @Override public void onProviderDisabled(String provider) { statusView.setText("يرجى تشغيل GPS"); }
}