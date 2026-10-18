package com.vedder.vesc;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import d7.vesc.hud.R;

public class VConnectionService extends Service {
    static boolean start(Context context) {
        if (context == null) {
            return false;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED &&
                context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
            return false;
        }

        Intent intent = new Intent(context, VConnectionService.class);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent);
            } else {
                context.startService(intent);
            }
            return true;
        } catch (RuntimeException exception) {
            Log.w("VESC", "Cannot start Bluetooth connection service", exception);
            return false;
        }
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        try {
            Notification.Builder builder;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                String channelId = "VESC_CONNECTION_CHANNEL";
                NotificationChannel channel = new NotificationChannel(
                        channelId, "VESC Bluetooth", NotificationManager.IMPORTANCE_LOW);
                getSystemService(NotificationManager.class).createNotificationChannel(channel);
                builder = new Notification.Builder(this, channelId);
            } else {
                builder = new Notification.Builder(this);
            }

            builder.setContentTitle("VESC Tool");
            builder.setContentText("Keeping the controller connection active and searching for preferred devices.");
            builder.setSmallIcon(R.drawable.icon);
            builder.setOngoing(true);

            Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
            if (launchIntent != null) {
                builder.setContentIntent(PendingIntent.getActivity(
                        this, 0, launchIntent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(2, builder.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE);
            } else {
                startForeground(2, builder.build());
            }
        } catch (RuntimeException exception) {
            Log.w("VESC", "Cannot keep Bluetooth connection service in foreground", exception);
            stopSelf();
        }

        return START_NOT_STICKY;
    }
}
