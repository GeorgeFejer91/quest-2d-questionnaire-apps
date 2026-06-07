package org.viscereality.temporaltracer2d;

import android.content.Intent;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public final class TemporalTracerLaunchContextTest {
    @Test
    public void autoTraceAcceptsBooleanExtraFromAdb() {
        Intent intent = new Intent(TemporalTracerLaunchContext.ACTION_RUN);
        intent.putExtra(TemporalTracerLaunchContext.EXTRA_AUTO_TRACE, true);

        TemporalTracerLaunchContext context = TemporalTracerLaunchContext.fromIntent(intent);

        assertTrue(context.autoTrace);
    }

    @Test
    public void autoTraceAcceptsStringExtraFromUnityBridge() {
        Intent intent = new Intent(TemporalTracerLaunchContext.ACTION_RUN);
        intent.putExtra(TemporalTracerLaunchContext.EXTRA_AUTO_TRACE, "true");

        TemporalTracerLaunchContext context = TemporalTracerLaunchContext.fromIntent(intent);

        assertTrue(context.autoTrace);
    }

    @Test
    public void autoTraceAcceptsFalseStringExtraFromUnityBridge() {
        Intent intent = new Intent(TemporalTracerLaunchContext.ACTION_RUN);
        intent.putExtra(TemporalTracerLaunchContext.EXTRA_AUTO_TRACE, "false");

        TemporalTracerLaunchContext context = TemporalTracerLaunchContext.fromIntent(intent);

        assertFalse(context.autoTrace);
    }
}
