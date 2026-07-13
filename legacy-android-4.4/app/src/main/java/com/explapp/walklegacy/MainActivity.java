package com.explapp.walklegacy;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
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
    private ProgressBar goalProgress;
    private Location lastLocation;
    private float totalMeters;
    private float goalMeters;
    private boolean tracking;
    private long startedAtElapsed;
    private long elapsedBeforeStart;
    private final Handler uiHandler = new Handler();
    private final Runnable uiTick = new Runnable() {
        @Override public void run() { if (tracking) refreshViews(); uiHandler.postDelayed(this, 1000L); }
    };

    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        loadSavedState();

        ScrollView scroll = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(dp(14), dp(14), dp(14), dp(14));
        root.setBackgroundColor(Color.rgb(244, 250, 247));

        LinearLayout hero=new LinearLayout(this); hero.setOrientation(LinearLayout.VERTICAL); hero.setGravity(Gravity.CENTER); hero.setPadding(dp(18),dp(18),dp(18),dp(18));
        hero.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR,new int[]{Color.rgb(5,150,105),Color.rgb(14,165,233)}));
        TextView title = createText("رفيق المشي", 28); title.setTextColor(Color.WHITE); title.setTypeface(Typeface.DEFAULT,Typeface.BOLD); hero.addView(title);
        statusView = createText("جاهز لبدء المشي", 18);
        statusView.setTextColor(Color.rgb(220,252,231)); hero.addView(statusView);
        distanceView = createText("", 36); distanceView.setTextColor(Color.WHITE); distanceView.setTypeface(Typeface.DEFAULT,Typeface.BOLD); hero.addView(distanceView);
        root.addView(hero,new LinearLayout.LayoutParams(-1,-2));

        LinearLayout goalCard=card();
        goalView = createText("", 17);
        goalView.setTypeface(Typeface.DEFAULT,Typeface.BOLD); goalCard.addView(goalView);
        goalProgress=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal); goalProgress.setMax(1000); goalCard.addView(goalProgress,new LinearLayout.LayoutParams(-1,dp(12)));
        root.addView(goalCard,top(-1,-2,10));

        LinearLayout stats=new LinearLayout(this); stats.setOrientation(LinearLayout.HORIZONTAL);
        speedView = createText("السرعة: 0.0 كم/س", 20);
        timeView = createText("", 20);
        accuracyView = createText("دقة GPS: غير متوفرة", 16);
        stats.addView(statCard(speedView),new LinearLayout.LayoutParams(0,-2,1));
        stats.addView(space(),new LinearLayout.LayoutParams(dp(8),1));
        stats.addView(statCard(timeView),new LinearLayout.LayoutParams(0,-2,1));
        root.addView(stats,top(-1,-2,10));
        LinearLayout accuracyCard=card(); accuracyCard.addView(accuracyView); root.addView(accuracyCard,top(-1,-2,8));

        startButton = actionButton("بدء المشي",Color.rgb(5,150,105));
        startButton.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { toggleTracking(); }
        });

        final Button goalButton = actionButton("الهدف: " + Math.round(goalMeters / 1000f) + " كم",Color.rgb(14,116,144));
        goalButton.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { cycleGoal(); goalButton.setText("الهدف: " + Math.round(goalMeters / 1000f) + " كم"); }
        });

        Button resetButton = actionButton("تصفير الرحلة",Color.rgb(71,85,105));
        resetButton.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { confirmReset(); }
        });

        root.addView(startButton,top(-1,dp(56),12));
        LinearLayout secondary=new LinearLayout(this); secondary.setOrientation(LinearLayout.HORIZONTAL); secondary.addView(goalButton,new LinearLayout.LayoutParams(0,dp(52),1)); LinearLayout.LayoutParams rp=new LinearLayout.LayoutParams(0,dp(52),1);rp.leftMargin=dp(8);secondary.addView(resetButton,rp);root.addView(secondary,top(-1,-2,8));
        TextView footer=createText("ثبت الهاتف واترك GPS يعمل في مكان مكشوف للحصول على مسافة أدق.",12);footer.setTextColor(Color.rgb(100,116,139));root.addView(footer,top(-1,-2,8));
        scroll.addView(root); setContentView(scroll);

        locationManager = (LocationManager) getSystemService(LOCATION_SERVICE);
        refreshViews();
        uiHandler.post(uiTick);
    }

    private TextView createText(String text, int size) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(size);
        view.setGravity(Gravity.CENTER);
        view.setPadding(dp(8), dp(9), dp(8), dp(9));
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
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
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
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
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

    private void confirmReset() {
        new AlertDialog.Builder(this).setTitle("تصفير الرحلة؟").setMessage("سيتم حذف المسافة والمدة الحالية.")
                .setNegativeButton("إلغاء",null).setPositiveButton("تصفير",new DialogInterface.OnClickListener(){@Override public void onClick(DialogInterface d,int w){resetTrip();}}).show();
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
        goalProgress.setProgress(Math.round(progress*10f));
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

        if (accuracy > 35f) { statusView.setText("إشارة GPS ضعيفة • انتظر في مكان مكشوف"); refreshViews(); return; }
        float kmh = location.hasSpeed() ? location.getSpeed() * 3.6f : 0f;
        if (kmh > 30f) { statusView.setText("تم تجاهل قراءة لا تشبه سرعة المشي"); return; }
        if (lastLocation != null) {
            float segment = lastLocation.distanceTo(location);
            long gap=Math.abs(location.getTime()-lastLocation.getTime());
            if (segment >= 1f && segment <= 40f && gap <= 15000L) totalMeters += segment;
        }
        lastLocation = location;

        statusView.setText("GPS متصل • المشي قيد التسجيل");
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
        uiHandler.removeCallbacksAndMessages(null);
        if (locationManager != null) locationManager.removeUpdates(this);
        super.onDestroy();
    }

    @Override public void onStatusChanged(String provider, int statusCode, Bundle extras) {}
    @Override public void onProviderEnabled(String provider) { statusView.setText("GPS متاح"); }
    @Override public void onProviderDisabled(String provider) { statusView.setText("يرجى تشغيل GPS"); }

    private LinearLayout card(){LinearLayout c=new LinearLayout(this);c.setOrientation(LinearLayout.VERTICAL);c.setGravity(Gravity.CENTER);c.setPadding(dp(12),dp(10),dp(12),dp(10));c.setBackground(round(Color.WHITE,18));return c;}
    private LinearLayout statCard(TextView view){LinearLayout c=card();c.addView(view);return c;}
    private Button actionButton(String label,int color){Button b=new Button(this);b.setText(label);b.setTextColor(Color.WHITE);b.setTextSize(16);b.setTypeface(Typeface.DEFAULT,Typeface.BOLD);b.setAllCaps(false);b.setBackground(round(color,16));return b;}
    private GradientDrawable round(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
    private LinearLayout.LayoutParams top(int w,int h,int margin){LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(w,h);p.topMargin=dp(margin);return p;}
    private View space(){return new View(this);}
    private int dp(int value){return (int)(value*getResources().getDisplayMetrics().density+0.5f);}
}
