package com.explapp.walklegacy;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

public class MainActivity extends Activity implements LocationListener {
    private LocationManager locationManager;
    private TextView status, distanceView;
    private Location lastLocation;
    private float totalMeters = 0f;
    private boolean tracking = false;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setPadding(28, 28, 28, 28);
        TextView title = new TextView(this);
        title.setText("مساعد المشي");
        title.setTextSize(28);
        title.setGravity(Gravity.CENTER);
        status = new TextView(this);
        status.setText("جاهز لبدء المشي");
        status.setTextSize(18);
        status.setGravity(Gravity.CENTER);
        distanceView = new TextView(this);
        distanceView.setText("المسافة: 0 متر");
        distanceView.setTextSize(24);
        distanceView.setGravity(Gravity.CENTER);
        Button start = new Button(this);
        start.setText("بدء / إيقاف");
        start.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { toggleTracking(); }
        });
        root.addView(title);
        root.addView(status);
        root.addView(distanceView);
        root.addView(start);
        setContentView(root);
        locationManager = (LocationManager) getSystemService(LOCATION_SERVICE);
    }

    private void toggleTracking() {
        if (tracking) {
            tracking = false;
            locationManager.removeUpdates(this);
            status.setText("تم إيقاف التتبع");
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
            tracking = true;
            lastLocation = null;
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 2000L, 2f, this);
            status.setText("جاري حساب المسافة عبر GPS");
        } catch (SecurityException e) {
            status.setText("يرجى السماح باستخدام الموقع");
        }
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (requestCode == 7 && results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) startTracking();
    }

    @Override public void onLocationChanged(Location location) {
        if (lastLocation != null && location.getAccuracy() <= 40f) totalMeters += lastLocation.distanceTo(location);
        lastLocation = location;
        distanceView.setText("المسافة: " + Math.round(totalMeters) + " متر");
    }
    @Override public void onStatusChanged(String provider, int statusCode, Bundle extras) {}
    @Override public void onProviderEnabled(String provider) { status.setText("GPS متاح"); }
    @Override public void onProviderDisabled(String provider) { status.setText("يرجى تشغيل GPS"); }
}
