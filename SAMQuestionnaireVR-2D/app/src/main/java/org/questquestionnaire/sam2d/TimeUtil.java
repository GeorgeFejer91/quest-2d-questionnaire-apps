package org.questquestionnaire.sam2d;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import java.util.UUID;

final class TimeUtil {
    private static final DateTimeFormatter FILE_STAMP = DateTimeFormatter
        .ofPattern("yyyyMMdd'T'HHmmssSSS'Z'", Locale.US)
        .withZone(ZoneOffset.UTC);

    private TimeUtil() {
    }

    static String utcIsoNowMillis() {
        return Instant.now().toString();
    }

    static long unixMillisNow() {
        return Instant.now().toEpochMilli();
    }

    static String utcFileStampMillis() {
        return FILE_STAMP.format(Instant.now());
    }

    static String newRunId() {
        String suffix = UUID.randomUUID().toString().replace("-", "").substring(0, 10);
        return "sam-" + utcFileStampMillis() + "-" + suffix;
    }
}
