package com.explapp.walklegacy;

import android.Manifest;
import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.Locale;

public class MainActivity extends Activity {
    private static final int LOCATION_REQUEST = 41;
    private TextView timerText, distanceText, speedText, gpsText;
    private Button actionButton;
    private SharedPreferences prefs;
    private boolean tracking;
    private long startElapsed;
    private double distance;
    private final android.os.Handler handler = new android.os.Handler();

    private final BroadcastReceiver receiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            distance = intent.getDoubleExtra(LocationTrackingService.EXTRA_DISTANCE, distance);
            long elapsed = intent.getLongExtra(LocationTrackingService.EXTRA_ELAPSED, elapsedSeconds());
            float accuracy = intent.getFloatExtra(LocationTrackingService.EXTRA_ACCURACY, 999f);
            String status = intent.getStringExtra(LocationTrackingService.EXTRA_STATUS);
            updateValues(elapsed, accuracy, status);
        }
    };

    private final Runnable ticker = new Runnable() {
        @Override public void run() {
            if (tracking) updateValues(elapsedSeconds(), -1f, null);
            handler.postDelayed(this, 1000L);
        }
    };

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.rgb(23, 107, 135));
        prefs = getSharedPreferences("walk_legacy", MODE_PRIVATE);
        tracking = prefs.getBoolean("tracking", false);
        startElapsed = prefs.getLong("start_elapsed", 0L);
        distance = prefs.getFloat("distance", 0f);
        buildUi();
        syncButton();
        handler.post(ticker);
    }

    @Override protected void onResume() {
        super.onResume();
        IntentFilter filter = new IntentFilter(LocationTrackingService.ACTION_UPDATE);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, RECEIVER_NOT_EXPORTED);
        else registerReceiver(receiver, filter);
        tracking = prefs.getBoolean("tracking", false);
        startElapsed = prefs.getLong("start_elapsed", startElapsed);
        distance = prefs.getFloat("distance", (float) distance);
        syncButton();
    }

    @Override protected void onPause() {
        try { unregisterReceiver(receiver); } catch (Exception ignored) { }
        super.onPause();
    }

    @Override protected void onDestroy() {
        handler.removeCallbacks(ticker);
        super.onDestroy();
    }

    private void buildUi() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(Color.rgb(245, 249, 247));

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(16), dp(16), dp(24));
        root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        scroll.addView(root);

        TextView title = text("رفيق المشي", 28, Color.WHITE, true);
        TextView subtitle = text("نسخة الأجهزة القديمة • GPS مباشر دون خدمات جوجل", 14, Color.argb(230,255,255,255), false);
        LinearLayout header = card(Color.rgb(23,107,135), 22);
        header.setPadding(dp(20), dp(20), dp(20), dp(20));
        header.addView(title);
        header.addView(subtitle);
        root.addView(header, matchWrap(0, dp(120)));

        LinearLayout session = card(Color.WHITE, 20);
        session.setGravity(Gravity.CENTER_HORIZONTAL);
        session.setPadding(dp(18), dp(22), dp(18), dp(22));
        TextView active = text("التتبع النشط", 16, Color.rgb(22,107,87), true);
        timerText = text("00:00:00", 38, Color.rgb(20,32,27), true);
        distanceText = text("0 متر", 27, Color.rgb(20,32,27), true);
        gpsText = text("جاهز لبدء المشي", 15, Color.rgb(196,108,21), true);
        session.addView(active);
        session.addView(space(12));
        session.addView(timerText);
        session.addView(distanceText);
        session.addView(gpsText);
        root.addView(space(14));
        root.addView(session, matchWrap(0, dp(270)));

        LinearLayout stats = new LinearLayout(this);
        stats.setOrientation(LinearLayout.HORIZONTAL);
        stats.setWeightSum(2f);
        speedText = text("0.0 كم/س\nالسرعة", 17, Color.rgb(20,96,145), true);
        speedText.setGravity(Gravity.CENTER);
        TextView gpsHint = text("GPS + الشبكة\nمصدر الموقع", 16, Color.rgb(196,108,21), true);
        gpsHint.setGravity(Gravity.CENTER);
        LinearLayout speedCard = card(Color.WHITE, 18); speedCard.setGravity(Gravity.CENTER); speedCard.addView(speedText);
        LinearLayout gpsCard = card(Color.WHITE, 18); gpsCard.setGravity(Gravity.CENTER); gpsCard.addView(gpsHint);
        stats.addView(speedCard, new LinearLayout.LayoutParams(0, dp(110), 1f));
        stats.addView(spaceH(12));
        stats.addView(gpsCard, new LinearLayout.LayoutParams(0, dp(110), 1f));
        root.addView(space(14));
        root.addView(stats);

        actionButton = new Button(this);
        actionButton.setTextSize(18);
        actionButton.setTextColor(Color.WHITE);
        actionButton.setTypeface(Typeface.DEFAULT_BOLD);
        actionButton.setAllCaps(false);
        actionButton.setMinHeight(dp(58));
        actionButton.setOnClickListener(v -> { if (tracking) stopTracking(); else beginTracking(); });
        root.addView(space(18));
        root.addView(actionButton, matchWrap(0, dp(62)));

        TextView note = text("يستخدم التطبيق GPS الأصلي وموفر الشبكة معاً. اخرج إلى مكان مكشوف وانتظر أول إشارة؛ يقبل الجهاز القراءة المتوسطة ثم يحسن الدقة تلقائياً.", 14, Color.rgb(92,108,98), false);
        note.setLineSpacing(0, 1.35f);
        LinearLayout noteCard = card(Color.rgb(235,246,251), 16);
        noteCard.setPadding(dp(16), dp(14), dp(16), dp(14));
        noteCard.addView(note);
        root.addView(space(14));
        root.addView(noteCard);

        setContentView(scroll);
    }

    private void beginTracking() {
        if (!locationEnabled()) {
            gpsText.setText("خدمة الموقع متوقفة — افتحها أولاً");
            startActivity(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS));
            return;
        }
        if (Build.VERSION.SDK_INT >= 23 && checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION}, LOCATION_REQUEST);
            return;
        }
        distance = 0d;
        startElapsed = SystemClock.elapsedRealtime();
        tracking = true;
        prefs.edit().putBoolean("tracking", true).putLong("start_elapsed", startElapsed).putFloat("distance", 0f).apply();
        Intent service = new Intent(this, LocationTrackingService.class);
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(service); else startService(service);
        gpsText.setText("جاري البحث عن الأقمار...");
        syncButton();
    }

    private void stopTracking() {
        stopService(new Intent(this, LocationTrackingService.class));
        tracking = false;
        prefs.edit().putBoolean("tracking", false).apply();
        gpsText.setText("تم حفظ الجلسة على الجهاز");
        syncButton();
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (requestCode == LOCATION_REQUEST && results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) beginTracking();
        else gpsText.setText("صلاحية الموقع مطلوبة لتشغيل GPS");
    }

    private void updateValues(long elapsed, float accuracy, String status) {
        timerText.setText(formatTime(elapsed));
        distanceText.setText(String.format(Locale.US, "%.0f متر", distance));
        double kmh = elapsed > 0 ? (distance / 1000d) / (elapsed / 3600d) : 0d;
        speedText.setText(String.format(Locale.US, "%.1f كم/س\nالسرعة", kmh));
        if (status != null) {
            gpsText.setText(accuracy < 900f ? status + " • دقة ±" + Math.round(accuracy) + " م" : status);
        }
    }

    private long elapsedSeconds() { return tracking && startElapsed > 0 ? Math.max(0, (SystemClock.elapsedRealtime() - startElapsed) / 1000L) : 0L; }
    private boolean locationEnabled() {
        LocationManager lm = (LocationManager) getSystemService(LOCATION_SERVICE);
        try { return lm != null && (lm.isProviderEnabled(LocationManager.GPS_PROVIDER) || lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)); }
        catch (Exception e) { return false; }
    }

    private void syncButton() {
        actionButton.setText(tracking ? "إيقاف الجلسة وحفظها" : "ابدأ المشي الآن");
        GradientDrawable bg = rounded(tracking ? Color.rgb(229,126,34) : Color.rgb(20,157,131), 16);
        actionButton.setBackground(bg);
        if (!tracking) updateValues(0, -1, null);
    }

    private String formatTime(long seconds) {
        long h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60;
        return String.format(Locale.US, "%02d:%02d:%02d", h, m, s);
    }

    private TextView text(String value, int sp, int color, boolean bold) {
        TextView v = new TextView(this); v.setText(value); v.setTextSize(sp); v.setTextColor(color); v.setGravity(Gravity.CENTER);
        if (bold) v.setTypeface(Typeface.DEFAULT_BOLD); return v;
    }
    private LinearLayout card(int color, int radius) { LinearLayout v = new LinearLayout(this); v.setOrientation(LinearLayout.VERTICAL); v.setBackground(rounded(color, radius)); return v; }
    private GradientDrawable rounded(int color, int radius) { GradientDrawable d = new GradientDrawable(); d.setColor(color); d.setCornerRadius(dp(radius)); return d; }
    private View space(int h) { View v = new View(this); v.setLayoutParams(new LinearLayout.LayoutParams(1, dp(h))); return v; }
    private View spaceH(int w) { View v = new View(this); v.setLayoutParams(new LinearLayout.LayoutParams(dp(w), 1)); return v; }
    private LinearLayout.LayoutParams matchWrap(int margin, int height) { LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, height); p.setMargins(0, dp(margin), 0, 0); return p; }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
}
