package org.mesmerprism.viscereality.questionnaires2d;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;
import java.util.UUID;

final class TimeUtil {
    private TimeUtil() {
    }

    static String utcIsoNow() {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date());
    }

    static String utcIsoNowMillis() {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date());
    }

    static long unixMillisNow() {
        return System.currentTimeMillis();
    }

    static String utcFileStamp() {
        SimpleDateFormat format = new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date());
    }

    static String utcFileStampMillis() {
        SimpleDateFormat format = new SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date());
    }

    static String newRunId() {
        String uuid = UUID.randomUUID().toString().replace("-", "");
        return utcFileStampMillis() + "_" + uuid.substring(0, 8);
    }
}
