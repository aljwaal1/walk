package com.explapp.walklegacy;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

public class MainActivity extends Activity {
    private static final int GREEN = Color.rgb(15, 145, 102);
    private static final int GREEN_DARK = Color.rgb(10, 97, 72);
    private static final int BLUE = Color.rgb(35, 137, 190);
    private static final int ORANGE = Color.rgb(238, 143, 57);
    private static final int RED = Color.rgb(202, 69, 68);
    private static final int INK = Color.rgb(32, 48, 58);
    private static final int MUTED = Color.rgb(93, 111, 121);
    private static final int BG = Color.rgb(245, 250, 247);
    private static final int REQUEST_LOCATION = 70;

    private SharedPreferences prefs;
    private LinearLayout content;
    private CircularProgressView ring;
    private TextView statusView;
    private TextView distanceView;
    private TextView timeView;
    private TextView speedView;
    private TextView accuracyView;
    private TextView dailyGoalView;
    private View dailyProgress;
    private Button startButton;
    private boolean tracking;
    private float distanceMeters;
    private float speedKmh;
    private float accuracyMeters = -1f;
    private long elapsedMillis;
    private int section;
    private boolean receiverRegistered;
    private final Handler handler = new Handler();
    private final Runnable uiTick = new Runnable() {
        public void run() { if (section == 0) refreshSessionViews(); handler.postDelayed(this, 1000L); }
    };
    private final BroadcastReceiver updates = new BroadcastReceiver() {
        public void onReceive(Context context, Intent intent) {
            tracking = intent.getBooleanExtra("tracking", false);
            distanceMeters = intent.getFloatExtra("distance", 0f);
            elapsedMillis = intent.getLongExtra("elapsed", 0L);
            speedKmh = intent.getFloatExtra("speed", 0f);
            accuracyMeters = intent.getFloatExtra("accuracy", -1f);
            if (section == 0) refreshSessionViews();
        }
    };

    private static class Session {
        long timestamp;
        long duration;
        float distance;
        Session(long timestamp, long duration, float distance) { this.timestamp = timestamp; this.duration = duration; this.distance = distance; }
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        prefs = getSharedPreferences(WalkTrackingService.PREFS, MODE_PRIVATE);
        readState();
        showSession();
    }

    private void page(String title, String subtitle, int active) {
        section = active;
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        root.setBackgroundColor(BG);

        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.VERTICAL);
        header.setPadding(dp(17), dp(14), dp(17), dp(13));
        header.setBackground(gradient());
        TextView app = text("رفيق المشي", 25, Color.WHITE, Typeface.BOLD);
        TextView context = text(title + "  •  " + subtitle, 14, Color.rgb(218, 245, 235), Typeface.NORMAL);
        header.addView(app);
        header.addView(context, lp(-1, -2, 0, 0, 4, 0, 0));
        root.addView(header);

        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(14), dp(11), dp(14), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.addView(content, new ScrollView.LayoutParams(-1, -2));
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        LinearLayout nav = new LinearLayout(this);
        nav.setPadding(dp(4), dp(4), dp(4), dp(4));
        nav.setBackgroundColor(Color.WHITE);
        nav.addView(navButton("المشي", 0), navLp());
        nav.addView(navButton("السجل", 1), navLp());
        nav.addView(navButton("الإنجازات", 2), navLp());
        root.addView(nav);
        setContentView(root);
        content.setAlpha(0f);
        content.setTranslationY(dp(7));
        content.animate().alpha(1f).translationY(0).setDuration(170).start();
    }

    private void showSession() {
        readState();
        int challenge = prefs.getInt("challenge_minutes", 20);
        page("جلسة المشي", "تحدي " + challenge + " دقيقة", 0);

        LinearLayout hero = card();
        hero.setGravity(Gravity.CENTER);
        statusView = text("", 15, GREEN_DARK, Typeface.BOLD);
        statusView.setGravity(Gravity.CENTER);
        hero.addView(statusView, lp(-1, -2, 0, 0, 0, 0, 3));
        ring = new CircularProgressView(this);
        hero.addView(ring, lp(-1, compactHeight() ? dp(165) : dp(205), 0, 0, 0, 0, 1));
        distanceView = text("", 24, INK, Typeface.BOLD);
        distanceView.setGravity(Gravity.CENTER);
        hero.addView(distanceView, lp(-1, -2, 0, 0, 0, 0, 3));
        timeView = text("", 16, MUTED, Typeface.BOLD);
        timeView.setGravity(Gravity.CENTER);
        hero.addView(timeView);
        content.addView(elevated(hero), lp(-1, -2, 0, 0, 0, 0, 9));

        LinearLayout stats = new LinearLayout(this);
        speedView = stat("السرعة", "0.0 كم/س", BLUE);
        accuracyView = stat("دقة GPS", "بانتظار الإشارة", ORANGE);
        stats.addView(speedView, weight(1, 0, 4));
        stats.addView(accuracyView, weight(1, 4, 0));
        content.addView(stats, lp(-1, dp(78), 0, 0, 0, 0, 9));

        LinearLayout goalCard = card();
        dailyGoalView = text("", 15, INK, Typeface.BOLD);
        goalCard.addView(dailyGoalView);
        dailyProgress = progressBar(0f);
        goalCard.addView(dailyProgress, lp(-1, dp(9), 0, 0, 8, 0, 5));
        Button goalButton = outline("تغيير الهدف اليومي");
        goalButton.setOnClickListener(new View.OnClickListener() { public void onClick(View view) { cycleGoal(); showSession(); } });
        goalCard.addView(goalButton, lp(-1, dp(46)));
        content.addView(elevated(goalCard), lp(-1, -2, 0, 0, 0, 0, 9));

        startButton = primary(tracking ? "إيقاف مؤقت" : elapsedMillis > 0 || distanceMeters > 0 ? "متابعة المشي" : "بدء المشي");
        startButton.setOnClickListener(new View.OnClickListener() {
            public void onClick(View view) { if (tracking) sendService(WalkTrackingService.ACTION_PAUSE); else ensureLocationAndStart(); }
        });
        content.addView(startButton, lp(-1, dp(56), 0, 0, 1, 0, 8));
        LinearLayout actions = new LinearLayout(this);
        Button challengeButton = outline("مدة التحدي");
        challengeButton.setOnClickListener(new View.OnClickListener() { public void onClick(View view) { cycleChallenge(); showSession(); } });
        Button finishButton = colored("إنهاء وحفظ", BLUE);
        finishButton.setEnabled(elapsedMillis >= 10000L || distanceMeters >= 5f);
        finishButton.setAlpha(finishButton.isEnabled() ? 1f : .45f);
        finishButton.setOnClickListener(new View.OnClickListener() { public void onClick(View view) { confirmFinish(); } });
        actions.addView(challengeButton, weight(1, 0, 4));
        actions.addView(finishButton, weight(1, 4, 0));
        content.addView(actions, lp(-1, dp(52), 0, 0, 0, 0, 8));
        Button reset = outline("تصفير الجلسة الحالية");
        reset.setTextColor(RED);
        reset.setOnClickListener(new View.OnClickListener() { public void onClick(View view) { confirmResetCurrent(); } });
        content.addView(reset, lp(-1, dp(49)));
        TextView hint = text("عند بدء المشي يظهر إشعار صامت ويحافظ على التتبع عند قفل الشاشة. يمكن حفظ الجلسة بعد 10 ثوانٍ أو 5 أمتار، واخرج إلى مكان مكشوف حتى تستقر إشارة GPS.", 13, MUTED, Typeface.NORMAL);
        hint.setGravity(Gravity.CENTER);
        content.addView(hint, lp(-1, -2, 0, 5, 9, 5, 0));
        refreshSessionViews();
    }

    private void refreshSessionViews() {
        if (distanceView == null || section != 0) return;
        int challengeMinutes = prefs.getInt("challenge_minutes", 20);
        float challengeProgress = Math.min(1f, elapsedMillis / (challengeMinutes * 60000f));
        ring.setProgress(challengeProgress, formatClock(elapsedMillis), "من " + challengeMinutes + " دقيقة");
        distanceView.setText(formatDistance(distanceMeters));
        timeView.setText("مدة الجلسة " + formatClock(elapsedMillis));
        speedView.setText(String.format(Locale.US, "%.1f كم/س\nالسرعة", speedKmh));
        String accuracy = accuracyMeters < 0 ? "بانتظار الإشارة" : Math.round(accuracyMeters) + " متر";
        accuracyView.setText(accuracy + "\nدقة GPS");
        if (tracking) statusView.setText(accuracyMeters > 35f ? "إشارة ضعيفة • انتظر قليلاً" : "التتبع نشط في الخلفية");
        else statusView.setText(elapsedMillis > 0 || distanceMeters > 0 ? "الجلسة متوقفة مؤقتاً" : "جاهز لبدء المشي");
        if (startButton != null) startButton.setText(tracking ? "إيقاف مؤقت" : elapsedMillis > 0 || distanceMeters > 0 ? "متابعة المشي" : "بدء المشي");
        float today = todayDistance() + distanceMeters;
        float goal = prefs.getFloat("goal", 3000f);
        dailyGoalView.setText("هدف اليوم  •  " + Math.round(today) + " من " + Math.round(goal) + " متر");
        if (dailyProgress instanceof FrameLayout) updateProgressBar((FrameLayout) dailyProgress, goal <= 0 ? 0 : today / goal);
    }

    private void showHistory() {
        page("سجل المشي", "آخر الجلسات والأسبوع الحالي", 1);
        ArrayList<Session> sessions = sessions();
        if (sessions.isEmpty()) {
            content.addView(empty("لا توجد جلسات بعد", "ابدأ جلسة مشي، ثم اضغط «إنهاء وحفظ» لتظهر هنا."));
            return;
        }
        WeeklyChart chart = new WeeklyChart(this, sessions);
        content.addView(elevated(chart), lp(-1, dp(210), 0, 0, 0, 0, 10));
        LinearLayout summary = new LinearLayout(this);
        summary.addView(stat("إجمالي المسافة", formatDistance(totalDistance(sessions)), GREEN), weight(1, 0, 4));
        summary.addView(stat("عدد الجلسات", String.valueOf(sessions.size()), BLUE), weight(1, 4, 0));
        content.addView(summary, lp(-1, dp(82), 0, 0, 0, 0, 11));
        TextView title = text("الجلسات الأخيرة", 19, INK, Typeface.BOLD);
        content.addView(title, lp(-1, -2, 0, 0, 0, 0, 6));
        SimpleDateFormat date = new SimpleDateFormat("EEE d MMM • HH:mm", new Locale("ar"));
        for (Session session : sessions) {
            LinearLayout row = card();
            TextView day = text(date.format(session.timestamp), 15, INK, Typeface.BOLD);
            TextView detail = text(formatDistance(session.distance) + "  •  " + formatClock(session.duration) + "  •  " + averageSpeed(session) + " كم/س", 14, MUTED, Typeface.NORMAL);
            row.addView(day);
            row.addView(detail, lp(-1, -2, 0, 0, 4, 0, 0));
            content.addView(elevated(row), lp(-1, -2, 0, 0, 0, 0, 7));
        }
        Button clear = outline("حذف السجل");
        clear.setTextColor(RED);
        clear.setOnClickListener(new View.OnClickListener() { public void onClick(View view) { confirmClearHistory(); } });
        content.addView(clear, lp(-1, dp(49), 0, 0, 4, 0, 0));
    }

    private void showAchievements() {
        ArrayList<Session> sessions = sessions();
        float total = totalDistance(sessions);
        int streak = calculateStreak(sessions);
        page("الإنجازات", "استمرارية هادئة وليست منافسة", 2);
        LinearLayout streakCard = card();
        streakCard.setGravity(Gravity.CENTER);
        ImageView icon = new ImageView(this);
        icon.setImageDrawable(new NavGlyph(2, ORANGE, dp(52)));
        streakCard.addView(icon, new LinearLayout.LayoutParams(dp(58), dp(58)));
        TextView number = text(streak + " أيام", 26, GREEN_DARK, Typeface.BOLD);
        number.setGravity(Gravity.CENTER);
        streakCard.addView(number);
        TextView caption = text("سلسلة المشي الحالية", 14, MUTED, Typeface.NORMAL);
        caption.setGravity(Gravity.CENTER);
        streakCard.addView(caption);
        content.addView(elevated(streakCard), lp(-1, -2, 0, 0, 0, 0, 11));

        String[] names = {"الخطوة الأولى", "خمس جلسات", "مستمر", "كيلومتر واحد", "عشرة كيلومترات", "خمسون كيلومتراً", "3 أيام متتالية", "7 أيام متتالية"};
        String[] descriptions = {"أكمل أول جلسة", "أكمل 5 جلسات", "أكمل 25 جلسة", "اجمع 1 كم", "اجمع 10 كم", "اجمع 50 كم", "امشِ 3 أيام متتالية", "امشِ أسبوعاً متتالياً"};
        boolean[] earned = {sessions.size() >= 1, sessions.size() >= 5, sessions.size() >= 25, total >= 1000f, total >= 10000f, total >= 50000f, streak >= 3, streak >= 7};
        int earnedCount = 0;
        for (boolean value : earned) if (value) earnedCount++;
        TextView heading = text("الشارات  •  " + earnedCount + " من " + earned.length, 19, INK, Typeface.BOLD);
        content.addView(heading, lp(-1, -2, 0, 0, 0, 0, 7));
        for (int i = 0; i < names.length; i++) {
            LinearLayout badge = new LinearLayout(this);
            badge.setGravity(Gravity.CENTER_VERTICAL);
            badge.setPadding(dp(13), dp(12), dp(13), dp(12));
            badge.setBackground(round(earned[i] ? Color.rgb(232, 248, 239) : Color.WHITE, 15, Color.rgb(222, 233, 227), 1));
            ImageView badgeIcon = new ImageView(this);
            badgeIcon.setImageDrawable(new NavGlyph(earned[i] ? 2 : 3, earned[i] ? ORANGE : Color.rgb(160, 172, 177), dp(42)));
            badge.addView(badgeIcon, new LinearLayout.LayoutParams(dp(48), dp(48)));
            LinearLayout copy = new LinearLayout(this);
            copy.setOrientation(LinearLayout.VERTICAL);
            copy.addView(text(names[i], 16, earned[i] ? GREEN_DARK : INK, Typeface.BOLD));
            copy.addView(text(descriptions[i], 13, MUTED, Typeface.NORMAL), lp(-1, -2, 0, 0, 3, 0, 0));
            badge.addView(copy, new LinearLayout.LayoutParams(0, -2, 1));
            content.addView(elevated(badge), lp(-1, -2, 0, 0, 0, 0, 7));
        }
    }

    private void ensureLocationAndStart() {
        LocationManager manager = (LocationManager) getSystemService(LOCATION_SERVICE);
        if (!manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            new AlertDialog.Builder(this).setTitle("GPS متوقف").setMessage("شغّل الموقع للحصول على مسافة دقيقة أثناء المشي.")
                    .setNegativeButton("لاحقاً", null).setPositiveButton("فتح الإعدادات", new DialogInterface.OnClickListener() {
                        public void onClick(DialogInterface dialog, int which) {
                            try { startActivity(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)); } catch (Exception ignored) { }
                        }
                    }).show();
            return;
        }
        if (Build.VERSION.SDK_INT >= 23 && checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION}, REQUEST_LOCATION);
            return;
        }
        sendService(WalkTrackingService.ACTION_START);
    }

    private void sendService(String action) {
        Intent intent = new Intent(this, WalkTrackingService.class);
        intent.setAction(action);
        startService(intent);
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (requestCode == REQUEST_LOCATION && results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) sendService(WalkTrackingService.ACTION_START);
        else if (requestCode == REQUEST_LOCATION) Toast.makeText(this, "يحتاج تتبع المسافة إلى إذن الموقع", Toast.LENGTH_LONG).show();
    }

    private void confirmFinish() {
        new AlertDialog.Builder(this).setTitle("إنهاء الجلسة وحفظها؟")
                .setMessage(formatDistance(distanceMeters) + " خلال " + formatClock(elapsedMillis))
                .setNegativeButton("إلغاء", null).setPositiveButton("حفظ", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface dialog, int which) { sendService(WalkTrackingService.ACTION_FINISH); handler.postDelayed(new Runnable() { public void run() { readState(); showHistory(); } }, 350L); }
                }).show();
    }

    private void confirmResetCurrent() {
        new AlertDialog.Builder(this).setTitle("تصفير الجلسة؟").setMessage("ستُحذف المسافة والمدة الحالية دون إضافتها للسجل.")
                .setNegativeButton("إلغاء", null).setPositiveButton("تصفير", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface dialog, int which) { sendService(WalkTrackingService.ACTION_RESET); }
                }).show();
    }

    private void confirmClearHistory() {
        new AlertDialog.Builder(this).setTitle("حذف سجل المشي؟").setMessage("لا يمكن استعادة الجلسات بعد حذفها.")
                .setNegativeButton("إلغاء", null).setPositiveButton("حذف", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface dialog, int which) { prefs.edit().remove("sessions").apply(); showHistory(); }
                }).show();
    }

    private void cycleGoal() {
        float goal = prefs.getFloat("goal", 3000f);
        if (goal < 3000f) goal = 3000f; else if (goal < 5000f) goal = 5000f; else if (goal < 10000f) goal = 10000f; else goal = 1000f;
        prefs.edit().putFloat("goal", goal).apply();
    }

    private void cycleChallenge() {
        int minutes = prefs.getInt("challenge_minutes", 20);
        if (minutes < 10) minutes = 10; else if (minutes < 20) minutes = 20; else if (minutes < 30) minutes = 30; else if (minutes < 45) minutes = 45; else minutes = 5;
        prefs.edit().putInt("challenge_minutes", minutes).apply();
    }

    private void readState() {
        tracking = prefs.getBoolean("tracking", false);
        distanceMeters = prefs.getFloat("distance", 0f);
        elapsedMillis = prefs.getLong("elapsed", 0L);
        speedKmh = prefs.getFloat("speed", 0f);
        accuracyMeters = prefs.getFloat("accuracy", -1f);
    }

    private ArrayList<Session> sessions() {
        ArrayList<Session> result = new ArrayList<Session>();
        String raw = prefs.getString("sessions", "");
        if (raw.length() == 0) return result;
        for (String row : raw.split(";")) {
            try {
                String[] values = row.split(",");
                if (values.length == 3) result.add(new Session(Long.parseLong(values[0]), Long.parseLong(values[1]), Float.parseFloat(values[2])));
            } catch (Exception ignored) { }
        }
        Collections.sort(result, new Comparator<Session>() { public int compare(Session a, Session b) { return a.timestamp < b.timestamp ? 1 : a.timestamp == b.timestamp ? 0 : -1; } });
        return result;
    }

    private float todayDistance() {
        Calendar today = Calendar.getInstance();
        float distance = 0f;
        for (Session session : sessions()) if (sameDay(today, session.timestamp)) distance += session.distance;
        return distance;
    }

    private boolean sameDay(Calendar day, long timestamp) {
        Calendar value = Calendar.getInstance(); value.setTimeInMillis(timestamp);
        return day.get(Calendar.YEAR) == value.get(Calendar.YEAR) && day.get(Calendar.DAY_OF_YEAR) == value.get(Calendar.DAY_OF_YEAR);
    }

    private int calculateStreak(ArrayList<Session> sessions) {
        Set<String> days = new HashSet<String>();
        SimpleDateFormat key = new SimpleDateFormat("yyyy-MM-dd", Locale.US);
        for (Session session : sessions) days.add(key.format(session.timestamp));
        Calendar day = Calendar.getInstance();
        int streak = 0;
        if (!days.contains(key.format(day.getTime()))) day.add(Calendar.DAY_OF_YEAR, -1);
        while (days.contains(key.format(day.getTime()))) { streak++; day.add(Calendar.DAY_OF_YEAR, -1); }
        return streak;
    }

    private float totalDistance(ArrayList<Session> sessions) { float total = 0f; for (Session session : sessions) total += session.distance; return total; }
    private String averageSpeed(Session session) { if (session.duration <= 0) return "0.0"; return String.format(Locale.US, "%.1f", (session.distance / 1000f) / (session.duration / 3600000f)); }
    private String formatDistance(float meters) { return meters < 1000f ? Math.round(meters) + " متر" : String.format(Locale.US, "%.2f كم", meters / 1000f); }
    private String formatClock(long millis) { long s = millis / 1000L; return String.format(Locale.US, "%02d:%02d:%02d", s / 3600L, (s % 3600L) / 60L, s % 60L); }

    private Button navButton(String label, final int target) {
        Button button = new Button(this);
        button.setText(label); button.setTextSize(12); button.setAllCaps(false); button.setGravity(Gravity.CENTER);
        button.setTextColor(section == target ? GREEN : MUTED); button.setTypeface(Typeface.DEFAULT, section == target ? Typeface.BOLD : Typeface.NORMAL);
        Drawable icon = new NavGlyph(target, section == target ? GREEN : MUTED, dp(23));
        button.setCompoundDrawables(null, icon, null, null); button.setCompoundDrawablePadding(dp(2)); button.setBackgroundColor(Color.TRANSPARENT);
        button.setOnClickListener(new View.OnClickListener() { public void onClick(View view) { if (target == 0) showSession(); else if (target == 1) showHistory(); else showAchievements(); } });
        return button;
    }

    private LinearLayout card() { LinearLayout card = new LinearLayout(this); card.setOrientation(LinearLayout.VERTICAL); card.setPadding(dp(14), dp(12), dp(14), dp(12)); card.setBackground(round(Color.WHITE, 16, Color.rgb(222, 233, 227), 1)); return card; }
    private TextView stat(String label, String value, int color) { TextView stat = text(value + "\n" + label, 15, color, Typeface.BOLD); stat.setGravity(Gravity.CENTER); stat.setBackground(round(Color.WHITE, 15, Color.rgb(222, 233, 227), 1)); return stat; }
    private LinearLayout empty(String title, String body) { LinearLayout empty = card(); empty.setGravity(Gravity.CENTER); empty.setPadding(dp(20), dp(38), dp(20), dp(38)); ImageView image = new ImageView(this); image.setImageDrawable(new NavGlyph(1, GREEN, dp(52))); empty.addView(image, new LinearLayout.LayoutParams(dp(58), dp(58))); TextView heading = text(title, 20, INK, Typeface.BOLD); heading.setGravity(Gravity.CENTER); empty.addView(heading, lp(-1, -2, 0, 0, 10, 0, 5)); TextView copy = text(body, 15, MUTED, Typeface.NORMAL); copy.setGravity(Gravity.CENTER); empty.addView(copy); return empty; }
    private TextView text(String value, int size, int color, int style) { TextView text = new TextView(this); text.setText(value); text.setTextSize(size); text.setTextColor(color); text.setTypeface(Typeface.DEFAULT, style); text.setLineSpacing(0, 1.08f); return text; }
    private Button primary(String label) { return colored(label, GREEN); }
    private Button colored(String label, int color) { Button button = new Button(this); button.setText(label); button.setTextSize(16); button.setTextColor(Color.WHITE); button.setTypeface(Typeface.DEFAULT, Typeface.BOLD); button.setAllCaps(false); button.setGravity(Gravity.CENTER); button.setPadding(dp(8), 0, dp(8), 0); button.setBackground(round(color, 14)); return button; }
    private Button outline(String label) { Button button = new Button(this); button.setText(label); button.setTextSize(15); button.setTextColor(GREEN_DARK); button.setTypeface(Typeface.DEFAULT, Typeface.BOLD); button.setAllCaps(false); button.setGravity(Gravity.CENTER); button.setPadding(dp(8), 0, dp(8), 0); button.setBackground(round(Color.WHITE, 14, Color.rgb(170, 205, 187), 1)); return button; }
    private View progressBar(float value) { FrameLayout track = new FrameLayout(this); track.setBackground(round(Color.rgb(224, 234, 229), 8)); updateProgressBar(track, value); return track; }
    private void updateProgressBar(FrameLayout track, float value) { track.removeAllViews(); View fill = new View(this); fill.setBackground(round(GREEN, 8)); int available = (int) (getResources().getDisplayMetrics().widthPixels * .78f); track.addView(fill, new FrameLayout.LayoutParams(Math.max(dp(3), (int) (available * Math.max(0f, Math.min(1f, value)))), -1)); }
    private View elevated(View view) { if (Build.VERSION.SDK_INT >= 21) view.setElevation(dp(2)); return view; }
    private GradientDrawable gradient() { return new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{GREEN_DARK, BLUE}); }
    private GradientDrawable round(int color, int radius) { return round(color, radius, Color.TRANSPARENT, 0); }
    private GradientDrawable round(int color, int radius, int stroke, int width) { GradientDrawable drawable = new GradientDrawable(); drawable.setColor(color); drawable.setCornerRadius(dp(radius)); if (width > 0) drawable.setStroke(dp(width), stroke); return drawable; }
    private LinearLayout.LayoutParams navLp() { return new LinearLayout.LayoutParams(0, dp(58), 1); }
    private LinearLayout.LayoutParams weight(float value, int left, int right) { LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, -1, value); params.setMargins(dp(left), 0, dp(right), 0); return params; }
    private LinearLayout.LayoutParams lp(int width, int height) { return new LinearLayout.LayoutParams(width, height); }
    private LinearLayout.LayoutParams lp(int width, int height, float weight, int left, int top, int right, int bottom) { LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(width, height, weight); params.setMargins(dp(left), dp(top), dp(right), dp(bottom)); return params; }
    private int dp(int value) { return (int) (value * getResources().getDisplayMetrics().density + .5f); }
    private boolean compactHeight() { return getResources().getDisplayMetrics().heightPixels / getResources().getDisplayMetrics().density < 560; }

    @Override protected void onResume() {
        super.onResume();
        readState();
        if (!receiverRegistered) { registerReceiver(updates, new IntentFilter(WalkTrackingService.ACTION_UPDATE)); receiverRegistered = true; }
        handler.removeCallbacks(uiTick); handler.post(uiTick);
        if (section == 0) refreshSessionViews();
    }
    @Override protected void onPause() { handler.removeCallbacks(uiTick); if (receiverRegistered) { unregisterReceiver(updates); receiverRegistered = false; } super.onPause(); }
    @Override public void onBackPressed() { if (section != 0) showSession(); else super.onBackPressed(); }

    private static class NavGlyph extends Drawable {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path path = new Path();
        private final int type;
        private final int size;
        NavGlyph(int type, int color, int size) { this.type = type; this.size = size; paint.setColor(color); paint.setStyle(Paint.Style.STROKE); paint.setStrokeWidth(Math.max(2f, size * .085f)); paint.setStrokeCap(Paint.Cap.ROUND); paint.setStrokeJoin(Paint.Join.ROUND); setBounds(0, 0, size, size); }
        @Override public void draw(Canvas canvas) {
            RectF b = new RectF(getBounds()); float w = b.width(), h = b.height(), l = b.left, t = b.top;
            paint.setStyle(Paint.Style.STROKE); path.reset();
            if (type == 0) {
                canvas.drawOval(new RectF(l+w*.18f,t+h*.11f,l+w*.48f,t+h*.48f), paint);
                canvas.drawOval(new RectF(l+w*.53f,t+h*.52f,l+w*.82f,t+h*.88f), paint);
                canvas.drawCircle(l+w*.20f,t+h*.11f,w*.035f,paint); canvas.drawCircle(l+w*.31f,t+h*.07f,w*.035f,paint); canvas.drawCircle(l+w*.42f,t+h*.09f,w*.035f,paint);
                canvas.drawCircle(l+w*.58f,t+h*.52f,w*.035f,paint); canvas.drawCircle(l+w*.69f,t+h*.48f,w*.035f,paint); canvas.drawCircle(l+w*.80f,t+h*.50f,w*.035f,paint);
            } else if (type == 1) {
                canvas.drawRoundRect(new RectF(l+w*.12f,t+h*.16f,l+w*.88f,t+h*.86f),w*.1f,w*.1f,paint);
                canvas.drawLine(l+w*.27f,t+h*.08f,l+w*.27f,t+h*.28f,paint); canvas.drawLine(l+w*.73f,t+h*.08f,l+w*.73f,t+h*.28f,paint);
                canvas.drawLine(l+w*.25f,t+h*.66f,l+w*.42f,t+h*.51f,paint); canvas.drawLine(l+w*.42f,t+h*.51f,l+w*.58f,t+h*.62f,paint); canvas.drawLine(l+w*.58f,t+h*.62f,l+w*.77f,t+h*.39f,paint);
            } else if (type == 2) {
                for (int i=0;i<10;i++) { double a=-Math.PI/2+i*Math.PI/5; float r=i%2==0?w*.39f:w*.19f; float x=l+w*.5f+(float)Math.cos(a)*r; float y=t+h*.5f+(float)Math.sin(a)*r; if(i==0)path.moveTo(x,y);else path.lineTo(x,y); } path.close(); canvas.drawPath(path,paint);
                canvas.drawCircle(l+w*.5f,t+h*.5f,w*.09f,paint);
            } else {
                canvas.drawRoundRect(new RectF(l+w*.22f,t+h*.42f,l+w*.78f,t+h*.88f),w*.08f,w*.08f,paint);
                canvas.drawArc(new RectF(l+w*.30f,t+h*.10f,l+w*.70f,t+h*.62f),190,160,false,paint);
                canvas.drawCircle(l+w*.5f,t+h*.64f,w*.045f,paint); canvas.drawLine(l+w*.5f,t+h*.68f,l+w*.5f,t+h*.77f,paint);
            }
        }
        @Override public void setAlpha(int alpha) { paint.setAlpha(alpha); }
        @Override public void setColorFilter(ColorFilter filter) { paint.setColorFilter(filter); }
        @Override public int getOpacity() { return PixelFormat.TRANSLUCENT; }
        @Override public int getIntrinsicWidth() { return size; }
        @Override public int getIntrinsicHeight() { return size; }
    }

    private static class CircularProgressView extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private float progress;
        private String center = "00:00:00";
        private String caption = "";
        CircularProgressView(Context context) { super(context); }
        void setProgress(float progress, String center, String caption) { this.progress = Math.max(0f, Math.min(1f, progress)); this.center = center; this.caption = caption; invalidate(); }
        @Override protected void onDraw(Canvas canvas) {
            float w = getWidth(), h = getHeight(), radius = Math.min(w, h) * .34f, cx = w / 2f, cy = h / 2f;
            paint.setStyle(Paint.Style.STROKE); paint.setStrokeCap(Paint.Cap.ROUND); paint.setStrokeWidth(Math.max(10f, radius * .12f)); paint.setColor(Color.rgb(222, 235, 228));
            RectF oval = new RectF(cx - radius, cy - radius, cx + radius, cy + radius); canvas.drawArc(oval, -90, 360, false, paint);
            paint.setColor(GREEN); canvas.drawArc(oval, -90, progress * 360f, false, paint);
            paint.setStyle(Paint.Style.FILL); paint.setTextAlign(Paint.Align.CENTER); paint.setTypeface(Typeface.DEFAULT_BOLD); paint.setColor(INK); paint.setTextSize(radius * .32f); canvas.drawText(center, cx, cy + radius * .05f, paint);
            paint.setTypeface(Typeface.DEFAULT); paint.setColor(MUTED); paint.setTextSize(radius * .17f); canvas.drawText(caption, cx, cy + radius * .34f, paint);
        }
    }

    private static class WeeklyChart extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final float[] meters = new float[7];
        private final String[] labels = new String[7];
        WeeklyChart(Context context, ArrayList<Session> sessions) {
            super(context); setBackgroundColor(Color.WHITE);
            SimpleDateFormat dayLabel = new SimpleDateFormat("EEE", new Locale("ar"));
            Calendar day = Calendar.getInstance(); day.add(Calendar.DAY_OF_YEAR, -6);
            for (int i = 0; i < 7; i++) { labels[i] = dayLabel.format(day.getTime()); for (Session session : sessions) if (sameCalendarDay(day, session.timestamp)) meters[i] += session.distance; day.add(Calendar.DAY_OF_YEAR, 1); }
            if (Build.VERSION.SDK_INT >= 21) setElevation(2f * getResources().getDisplayMetrics().density);
            setPadding(10, 10, 10, 10);
        }
        private static boolean sameCalendarDay(Calendar day, long timestamp) { Calendar other = Calendar.getInstance(); other.setTimeInMillis(timestamp); return day.get(Calendar.YEAR) == other.get(Calendar.YEAR) && day.get(Calendar.DAY_OF_YEAR) == other.get(Calendar.DAY_OF_YEAR); }
        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas); float w = getWidth(), h = getHeight(), left = w * .08f, right = w * .96f, top = h * .18f, bottom = h * .78f; float max = 100f; for (float value : meters) max = Math.max(max, value);
            paint.setTextAlign(Paint.Align.RIGHT); paint.setColor(INK); paint.setTypeface(Typeface.DEFAULT_BOLD); paint.setTextSize(h * .085f); canvas.drawText("المسافة خلال 7 أيام", right, h * .12f, paint);
            float slot = (right - left) / 7f; for (int i = 0; i < 7; i++) { float barHeight = (meters[i] / max) * (bottom - top); float x = left + i * slot + slot * .18f; paint.setColor(meters[i] > 0 ? GREEN : Color.rgb(224, 234, 229)); canvas.drawRoundRect(new RectF(x, bottom - barHeight, x + slot * .62f, bottom), slot * .13f, slot * .13f, paint); paint.setTextAlign(Paint.Align.CENTER); paint.setColor(MUTED); paint.setTypeface(Typeface.DEFAULT); paint.setTextSize(h * .065f); canvas.drawText(labels[i], x + slot * .31f, h * .9f, paint); }
        }
    }
}
