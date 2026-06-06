package org.mesmerprism.viscereality.temporaltracer2d;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.view.MotionEvent;
import android.view.View;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

public final class TraceCanvasView extends View {
    interface CompletionListener {
        void onTraceCompletionChanged(boolean complete, String status);
    }

    private static final int BACKGROUND = Color.rgb(17, 19, 24);
    private static final int PANEL = Color.rgb(27, 31, 38);
    private static final int TEXT = Color.rgb(244, 245, 247);
    private static final int MUTED = Color.rgb(160, 168, 178);
    private static final int START_GATE = Color.argb(92, 70, 130, 210);
    private static final int END_GATE = Color.argb(70, 210, 110, 90);

    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF plotRect = new RectF();
    private final RectF startZoneRect = new RectF();
    private final List<TracePoint> rawPoints = new ArrayList<>();
    private TemporalTracerConfig.AxisConfig axis;
    private String language = "English";
    private boolean drawing;
    private boolean complete;
    private CompletionListener completionListener;
    private String status = "";

    public TraceCanvasView(Context context) {
        super(context);
        init();
    }

    public TraceCanvasView(Context context, AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    private void init() {
        setMinimumHeight(dp(360));
        setFocusable(true);
        setClickable(true);
        setContentDescription("Temporal trace drawing axis");
    }

    void configure(TemporalTracerConfig.AxisConfig axis, String language) {
        this.axis = axis;
        this.language = language == null ? "English" : language;
        updateStatus(false);
        invalidate();
    }

    void setCompletionListener(CompletionListener completionListener) {
        this.completionListener = completionListener;
    }

    void clearTrace() {
        rawPoints.clear();
        drawing = false;
        setComplete(false, "Start just outside the 0 axis.");
        invalidate();
    }

    boolean isTraceComplete() {
        return complete;
    }

    String getStatus() {
        return status;
    }

    List<TracePoint> rawPoints() {
        return Collections.unmodifiableList(rawPoints);
    }

    List<TracePoint> resampledPoints() {
        return TraceResampler.normalizeAndResample(rawPoints, axis != null ? axis.targetSampleCount : 1000);
    }

    void seedFixtureTrace() {
        rawPoints.clear();
        long base = TimeUtil.unixMillisNow();
        for (int i = 0; i < 80; i++) {
            double u = (double) i / 79.0;
            double v = 0.35 + (0.35 * Math.sin(u * Math.PI * 1.4));
            rawPoints.add(new TracePoint(u, v, base + (i * 120L), ""));
        }
        setComplete(true, "Trace complete.");
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        canvas.drawColor(BACKGROUND);
        computePlotRect();
        drawPanel(canvas);
        drawGrid(canvas);
        drawGateBands(canvas);
        drawTrace(canvas);
        drawLabels(canvas);
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        computePlotRect();
        int action = event.getActionMasked();
        if (action == MotionEvent.ACTION_DOWN) {
            performClick();
            if (!startZoneRect.contains(event.getX(), event.getY())) {
                setComplete(false, "Start in the blue start area just outside the 0 axis.");
                return true;
            }
            rawPoints.clear();
            drawing = true;
            addPoint(event.getX(), event.getY(), true);
            setComplete(false, "Cross the 0 axis and continue to the right edge.");
            return true;
        }

        if ((action == MotionEvent.ACTION_MOVE || action == MotionEvent.ACTION_UP) && drawing) {
            for (int i = 0; i < event.getHistorySize(); i++) {
                addPoint(event.getHistoricalX(i), event.getHistoricalY(i), false);
            }
            addPoint(event.getX(), event.getY(), false);
            updateCompletionFromPoints();
            if (action == MotionEvent.ACTION_UP) {
                drawing = false;
            }
            invalidate();
            return true;
        }

        if (action == MotionEvent.ACTION_CANCEL) {
            drawing = false;
            updateCompletionFromPoints();
            return true;
        }
        return true;
    }

    @Override
    public boolean performClick() {
        super.performClick();
        return true;
    }

    private void addPoint(float x, float y, boolean first) {
        double u = toU(x);
        double v = toV(y);
        if (first) {
            u = 0.0;
        }
        if (!first && !rawPoints.isEmpty()) {
            double lastU = rawPoints.get(rawPoints.size() - 1).u;
            if (u + 0.002 < lastU) {
                return;
            }
            if (Math.abs(u - lastU) < 0.001 && rawPoints.size() > 2) {
                return;
            }
        }
        rawPoints.add(new TracePoint(u, v, TimeUtil.unixMillisNow(), TimeUtil.utcIsoNowMillis()));
    }

    private void updateCompletionFromPoints() {
        boolean nowComplete = hasValidStart() && maxU() >= endGate() && rawPoints.size() >= 4;
        updateStatus(nowComplete);
    }

    private void updateStatus(boolean nowComplete) {
        if (nowComplete) {
            setComplete(true, "Trace complete.");
            return;
        }
        if (!hasValidStart()) {
            setComplete(false, "Start in the blue start area just outside the 0 axis.");
        } else {
            double progress = Math.max(0.0, Math.min(1.0, maxU()));
            setComplete(false, String.format(Locale.US, "Progress %.0f%%. Continue to the red end band.", progress * 100.0));
        }
    }

    private void setComplete(boolean complete, String status) {
        boolean changed = this.complete != complete || !this.status.equals(status);
        this.complete = complete;
        this.status = status == null ? "" : status;
        if (changed && completionListener != null) {
            completionListener.onTraceCompletionChanged(this.complete, this.status);
        }
    }

    private boolean hasValidStart() {
        return !rawPoints.isEmpty() && rawPoints.get(0).u <= 0.0001;
    }

    private double maxU() {
        double max = 0.0;
        for (TracePoint point : rawPoints) {
            max = Math.max(max, point.u);
        }
        return max;
    }

    private double startGate() {
        return axis == null ? 0.05 : axis.startGatePercent / 100.0;
    }

    private double endGate() {
        return axis == null ? 0.95 : axis.endGatePercent / 100.0;
    }

    private double toU(float x) {
        if (plotRect.width() <= 1f) {
            return 0.0;
        }
        return TemporalTracerConfig.clamp((x - plotRect.left) / plotRect.width(), 0.0, 1.0);
    }

    private double toV(float y) {
        if (plotRect.height() <= 1f) {
            return 0.0;
        }
        return TemporalTracerConfig.clamp(1.0 - ((y - plotRect.top) / plotRect.height()), 0.0, 1.0);
    }

    private float xForU(double u) {
        return (float) (plotRect.left + (TemporalTracerConfig.clamp(u, 0.0, 1.0) * plotRect.width()));
    }

    private float yForV(double v) {
        return (float) (plotRect.bottom - (TemporalTracerConfig.clamp(v, 0.0, 1.0) * plotRect.height()));
    }

    private void computePlotRect() {
        float left = dp(128);
        float right = getWidth() - dp(32);
        float top = dp(48);
        float bottom = getHeight() - dp(72);
        if (right <= left + dp(80)) {
            left = dp(24);
            right = getWidth() - dp(24);
        }
        if (bottom <= top + dp(80)) {
            top = dp(24);
            bottom = getHeight() - dp(36);
        }
        plotRect.set(left, top, right, bottom);
        float startGap = dp(10);
        float startWidth = dp(46);
        startZoneRect.set(plotRect.left - startGap - startWidth, plotRect.top, plotRect.left - startGap, plotRect.bottom);
    }

    private void drawPanel(Canvas canvas) {
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(PANEL);
        canvas.drawRoundRect(new RectF(dp(8), dp(8), getWidth() - dp(8), getHeight() - dp(8)), dp(6), dp(6), paint);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(dp(1));
        paint.setColor(axisColor());
        canvas.drawRect(plotRect, paint);
    }

    private void drawGrid(Canvas canvas) {
        List<String> horizontal = axis != null ? axis.horizontalGridLabels : Collections.emptyList();
        List<String> vertical = axis != null ? axis.verticalGridLabels : Collections.emptyList();

        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(dp(1));
        paint.setColor(gridColor());
        if (horizontal.size() > 1) {
            for (int i = 0; i < horizontal.size(); i++) {
                float y = plotRect.top + ((plotRect.height() * i) / (horizontal.size() - 1));
                canvas.drawLine(plotRect.left, y, plotRect.right, y, paint);
            }
        }
        if (vertical.size() > 1) {
            for (int i = 0; i < vertical.size(); i++) {
                float x = plotRect.left + ((plotRect.width() * i) / (vertical.size() - 1));
                canvas.drawLine(x, plotRect.top, x, plotRect.bottom, paint);
            }
        }

        paint.setStyle(Paint.Style.FILL);
        paint.setTextSize(sp(13));
        paint.setColor(MUTED);
        paint.setTextAlign(Paint.Align.RIGHT);
        if (horizontal.size() > 1) {
            for (int i = 0; i < horizontal.size(); i++) {
                float y = plotRect.top + ((plotRect.height() * i) / (horizontal.size() - 1));
                canvas.drawText(horizontal.get(i), plotRect.left - dp(10), y + dp(5), paint);
            }
        }
        paint.setTextAlign(Paint.Align.CENTER);
        if (vertical.size() > 1) {
            for (int i = 0; i < vertical.size(); i++) {
                float x = plotRect.left + ((plotRect.width() * i) / (vertical.size() - 1));
                canvas.drawText(vertical.get(i), x, plotRect.bottom + dp(28), paint);
            }
        }
    }

    private void drawGateBands(Canvas canvas) {
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(START_GATE);
        canvas.drawRect(startZoneRect, paint);
        paint.setColor(END_GATE);
        canvas.drawRect(xForU(endGate()), plotRect.top, plotRect.right, plotRect.bottom, paint);

        paint.setStyle(Paint.Style.FILL);
        paint.setTextSize(sp(12));
        paint.setTextAlign(Paint.Align.CENTER);
        paint.setColor(MUTED);
        canvas.drawText("start", startZoneRect.centerX(), startZoneRect.top - dp(8), paint);
    }

    private void drawTrace(Canvas canvas) {
        if (rawPoints.size() < 2) {
            return;
        }
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeCap(Paint.Cap.ROUND);
        paint.setStrokeJoin(Paint.Join.ROUND);
        paint.setStrokeWidth(dp(3));
        paint.setColor(traceColor());
        TracePoint first = rawPoints.get(0);
        TracePoint last = rawPoints.get(rawPoints.size() - 1);

        Path smooth = new Path();
        smooth.moveTo(xForU(first.u), yForV(first.v));
        for (int i = 1; i < rawPoints.size(); i++) {
            TracePoint a = rawPoints.get(i - 1);
            TracePoint b = rawPoints.get(i);
            float ax = xForU(a.u);
            float ay = yForV(a.v);
            float bx = xForU(b.u);
            float by = yForV(b.v);
            smooth.quadTo(ax, ay, (ax + bx) * 0.5f, (ay + by) * 0.5f);
        }
        smooth.lineTo(xForU(last.u), yForV(last.v));
        canvas.save();
        canvas.clipRect(plotRect);
        canvas.drawPath(smooth, paint);

        // Small filled samples make local Android render previews see the trace
        // even on renderers that under-report stroked paths.
        paint.setStyle(Paint.Style.FILL);
        float pointRadius = Math.max(1f, dp(1));
        for (int i = 0; i < rawPoints.size(); i += 3) {
            TracePoint point = rawPoints.get(i);
            float cx = xForU(point.u);
            float cy = yForV(point.v);
            canvas.drawCircle(cx, cy, pointRadius, paint);
        }
        canvas.drawCircle(xForU(first.u), yForV(first.v), dp(4), paint);
        canvas.drawCircle(xForU(last.u), yForV(last.v), dp(4), paint);
        canvas.restore();
    }

    private void drawLabels(Canvas canvas) {
        paint.setStyle(Paint.Style.FILL);
        paint.setTextSize(sp(14));
        paint.setColor(TEXT);
        paint.setTextAlign(Paint.Align.LEFT);
        String top = axis == null ? "" : axis.topLabel(language);
        String bottom = axis == null ? "" : axis.bottomLabel(language);
        canvas.drawText(top, plotRect.left, plotRect.top - dp(18), paint);
        canvas.drawText(bottom, plotRect.left, plotRect.bottom + dp(52), paint);
    }

    private int traceColor() {
        return axis == null ? Color.rgb(40, 209, 124) : axis.traceColor;
    }

    private int axisColor() {
        return axis == null ? TEXT : axis.axisColor;
    }

    private int gridColor() {
        return axis == null ? MUTED : axis.gridColor;
    }

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private float sp(float value) {
        return value * getResources().getDisplayMetrics().scaledDensity;
    }
}
