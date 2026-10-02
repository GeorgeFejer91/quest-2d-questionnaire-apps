package org.questquestionnaire.sam2d;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.view.MotionEvent;
import android.view.View;

import com.caverock.androidsvg.SVG;

import java.io.InputStream;
import java.util.Locale;

public final class SamScaleView extends View {
    interface OnScoreSelectedListener {
        void onScoreSelected(SamScaleView view, int score, String inputSource);
    }

    private static final int CHOICE_COUNT = 5;
    private static final int BITMAP_RENDER_WIDTH = 700;
    private static final int BITMAP_RENDER_HEIGHT = 749;

    private final Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint labelPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint linePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint slotPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint selectedPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint focusPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint bitmapPaint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG | Paint.DITHER_FLAG);
    private final RectF scaleRect = new RectF();
    private final RectF drawRect = new RectF();
    private final RectF slotRect = new RectF();
    private final RectF highlightRect = new RectF();
    private final Rect bitmapSrcRect = new Rect();
    private final float[] svgAspects = new float[5];

    private String dimensionId = "valence";
    private String title = "Valence";
    private String lowAnchor = "Very unpleasant";
    private String highAnchor = "Very pleasant";
    private String assetDir = "valence";
    private final SVG[] svgs = new SVG[5];
    private int selectedScore = 0;
    private int focusedScore = 3;
    private boolean activeRow = false;
    private OnScoreSelectedListener listener;

    public SamScaleView(Context context) {
        super(context);
        init();
    }

    public SamScaleView(Context context, AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    void configure(String dimensionId, String title, String lowAnchor, String highAnchor, String assetDir) {
        this.dimensionId = dimensionId;
        this.title = title;
        this.lowAnchor = lowAnchor;
        this.highAnchor = highAnchor;
        this.assetDir = assetDir;
        loadSvgs();
        setContentDescription(title + " SAM scale");
        invalidate();
    }

    String dimensionId() {
        return dimensionId;
    }

    int selectedScore() {
        return selectedScore;
    }

    int focusedScore() {
        return focusedScore;
    }

    void setSelectedScore(int score) {
        selectedScore = SamLaunchContext.clampScore(score);
        focusedScore = selectedScore;
        invalidate();
    }

    void clearSelection() {
        selectedScore = 0;
        invalidate();
    }

    void setFocusedScore(int score) {
        focusedScore = SamLaunchContext.clampScore(score);
        invalidate();
    }

    void moveFocus(int delta) {
        setFocusedScore(focusedScore + delta);
    }

    void setActiveRow(boolean activeRow) {
        this.activeRow = activeRow;
        invalidate();
    }

    void setOnScoreSelectedListener(OnScoreSelectedListener listener) {
        this.listener = listener;
    }

    void confirmFocusedScore(String inputSource) {
        setSelectedScore(focusedScore);
        if (listener != null) {
            listener.onScoreSelected(this, selectedScore, inputSource);
        }
    }

    static int scoreFromFraction(float fraction) {
        int score = (int) Math.floor(Math.max(0f, Math.min(0.9999f, fraction)) * CHOICE_COUNT) + 1;
        return SamLaunchContext.clampScore(score);
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int desiredHeight = dp(280);
        int height = resolveSize(desiredHeight, heightMeasureSpec);
        int width = resolveSize(dp(720), widthMeasureSpec);
        setMeasuredDimension(width, height);
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        float width = getWidth();
        float height = getHeight();
        float padding = dp(6);
        float top = dp(34);
        float bottom = height - dp(44);
        scaleRect.set(padding, top, width - padding, bottom);

        textPaint.setColor(Color.rgb(17, 24, 39));
        textPaint.setTextSize(sp(23));
        textPaint.setFakeBoldText(true);
        canvas.drawText(title, padding, dp(28), textPaint);

        selectedPaint.setColor(Color.rgb(250, 204, 21));
        focusPaint.setStyle(Paint.Style.STROKE);
        focusPaint.setStrokeWidth(dp(activeRow ? 4 : 2));
        focusPaint.setColor(activeRow ? Color.rgb(0, 92, 255) : Color.rgb(148, 163, 184));
        linePaint.setColor(Color.rgb(203, 213, 225));
        linePaint.setStrokeWidth(dp(1));

        float slotWidth = scaleRect.width() / CHOICE_COUNT;
        for (int score = 1; score <= CHOICE_COUNT; score++) {
            slotBounds(score, slotRect);
            float centerX = scaleRect.left + (score - 0.5f) * slotWidth;
            SVG svg = svgs[score - 1];
            figureBounds(score, slotRect, drawRect);
            highlightRect.set(
                drawRect.left - dp(8),
                drawRect.top - dp(8),
                drawRect.right + dp(8),
                drawRect.bottom + dp(8));
            if (score == selectedScore) {
                slotPaint.setColor(Color.rgb(254, 243, 199));
                slotPaint.setStyle(Paint.Style.FILL);
                canvas.drawRoundRect(highlightRect, dp(8), dp(8), slotPaint);
                slotPaint.setStyle(Paint.Style.STROKE);
                slotPaint.setStrokeWidth(dp(3));
                slotPaint.setColor(Color.rgb(202, 138, 4));
                canvas.drawRoundRect(highlightRect, dp(8), dp(8), slotPaint);
            } else if (score == focusedScore) {
                canvas.drawRoundRect(highlightRect, dp(8), dp(8), focusPaint);
            }

            if (svg != null) {
                drawManikin(canvas, score, svg);
            } else {
                drawFallbackFigure(canvas, drawRect);
            }

            labelPaint.setColor(Color.rgb(51, 65, 85));
            labelPaint.setTextSize(sp(16));
            labelPaint.setTextAlign(Paint.Align.CENTER);
            canvas.drawText(Integer.toString(score), centerX, scaleRect.bottom + dp(22), labelPaint);
        }

        labelPaint.setTextSize(sp(15));
        labelPaint.setTextAlign(Paint.Align.LEFT);
        canvas.drawText(lowAnchor, scaleRect.left, height - dp(8), labelPaint);
        labelPaint.setTextAlign(Paint.Align.RIGHT);
        canvas.drawText(highAnchor, scaleRect.right, height - dp(8), labelPaint);
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (event.getAction() != MotionEvent.ACTION_DOWN && event.getAction() != MotionEvent.ACTION_UP) {
            return true;
        }
        if (event.getX() < scaleRect.left || event.getX() > scaleRect.right) {
            return true;
        }
        int score = scoreFromFraction((event.getX() - scaleRect.left) / Math.max(1f, scaleRect.width()));
        focusedScore = score;
        if (event.getAction() == MotionEvent.ACTION_UP) {
            setSelectedScore(score);
            if (listener != null) {
                listener.onScoreSelected(this, score, "pointer");
            }
        } else {
            invalidate();
        }
        return true;
    }

    private void init() {
        setFocusable(true);
        setClickable(true);
        setBackgroundColor(Color.TRANSPARENT);
        textPaint.setTextAlign(Paint.Align.LEFT);
        labelPaint.setTextAlign(Paint.Align.LEFT);
    }

    private void loadSvgs() {
        for (int i = 0; i < svgs.length; i++) {
            String path = String.format(Locale.US, "sam/source/%s/%s-%d.svg", assetDir, assetDir, i + 1);
            try (InputStream input = getContext().getAssets().open(path)) {
                svgs[i] = SVG.getFromInputStream(input);
                bitmapSrcRect.setEmpty();
                Bitmap bitmap = renderCroppedBitmap(svgs[i], bitmapSrcRect);
                manikinBitmaps[i] = bitmap;
                manikinSources[i] = new Rect(bitmapSrcRect);
                svgAspects[i] = bitmapSrcRect.width() > 0 && bitmapSrcRect.height() > 0
                    ? bitmapSrcRect.width() / (float) bitmapSrcRect.height()
                    : 100f / 107f;
            } catch (Exception ignored) {
                svgs[i] = null;
                manikinBitmaps[i] = null;
                manikinSources[i] = null;
                svgAspects[i] = 100f / 107f;
            }
        }
    }

    private void slotBounds(int score, RectF out) {
        float slotWidth = scaleRect.width() / CHOICE_COUNT;
        float left = scaleRect.left + (score - 1) * slotWidth + dp(4);
        float right = scaleRect.left + score * slotWidth - dp(4);
        out.set(left, scaleRect.top, right, scaleRect.bottom);
    }

    private void figureBounds(int score, RectF slot, RectF out) {
        float maxHeight = Math.max(dp(80), scaleRect.height() - dp(34));
        float maxWidth = Math.max(dp(80), slot.width() - dp(16));
        float aspect = svgAspects[score - 1] > 0f ? svgAspects[score - 1] : 100f / 107f;
        float drawWidth = Math.min(maxWidth, maxHeight * aspect);
        float drawHeight = Math.min(maxHeight, maxWidth / aspect);
        float left = slot.centerX() - drawWidth / 2f;
        float top = scaleRect.top + dp(2);
        out.set(left, top, left + drawWidth, top + drawHeight);
    }

    private final Bitmap[] manikinBitmaps = new Bitmap[5];
    private final Rect[] manikinSources = new Rect[5];

    private void drawManikin(Canvas canvas, int score, SVG svg) {
        Bitmap bitmap = manikinBitmaps[score - 1];
        Rect src = manikinSources[score - 1];
        if (bitmap != null && src != null && !src.isEmpty()) {
            canvas.drawBitmap(bitmap, src, drawRect, bitmapPaint);
            return;
        }
        try {
            svg.renderToCanvas(canvas, drawRect);
        } catch (Exception ignored) {
            drawFallbackFigure(canvas, drawRect);
        }
    }

    private Bitmap renderCroppedBitmap(SVG svg, Rect outBounds) throws Exception {
        Bitmap bitmap = Bitmap.createBitmap(BITMAP_RENDER_WIDTH, BITMAP_RENDER_HEIGHT, Bitmap.Config.ARGB_8888);
        Canvas bitmapCanvas = new Canvas(bitmap);
        svg.renderToCanvas(bitmapCanvas, new RectF(0, 0, BITMAP_RENDER_WIDTH, BITMAP_RENDER_HEIGHT));
        findInkBounds(bitmap, outBounds);
        return bitmap;
    }

    private void findInkBounds(Bitmap bitmap, Rect outBounds) {
        int left = bitmap.getWidth();
        int top = bitmap.getHeight();
        int right = -1;
        int bottom = -1;
        for (int y = 0; y < bitmap.getHeight(); y++) {
            for (int x = 0; x < bitmap.getWidth(); x++) {
                if (Color.alpha(bitmap.getPixel(x, y)) > 8) {
                    if (x < left) {
                        left = x;
                    }
                    if (x > right) {
                        right = x;
                    }
                    if (y < top) {
                        top = y;
                    }
                    if (y > bottom) {
                        bottom = y;
                    }
                }
            }
        }
        if (right < left || bottom < top) {
            outBounds.set(0, 0, bitmap.getWidth(), bitmap.getHeight());
            return;
        }
        int margin = Math.max(8, BITMAP_RENDER_WIDTH / 90);
        outBounds.set(
            Math.max(0, left - margin),
            Math.max(0, top - margin),
            Math.min(bitmap.getWidth(), right + margin + 1),
            Math.min(bitmap.getHeight(), bottom + margin + 1));
    }

    private void drawFallbackFigure(Canvas canvas, RectF rect) {
        Paint paint = slotPaint;
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(dp(3));
        paint.setColor(Color.rgb(17, 24, 39));
        float cx = rect.centerX();
        canvas.drawCircle(cx, rect.top + rect.height() * 0.22f, rect.width() * 0.16f, paint);
        canvas.drawLine(cx, rect.top + rect.height() * 0.38f, cx, rect.top + rect.height() * 0.74f, paint);
        canvas.drawLine(cx, rect.top + rect.height() * 0.48f, rect.left + rect.width() * 0.2f, rect.top + rect.height() * 0.6f, paint);
        canvas.drawLine(cx, rect.top + rect.height() * 0.48f, rect.right - rect.width() * 0.2f, rect.top + rect.height() * 0.6f, paint);
        canvas.drawLine(cx, rect.top + rect.height() * 0.74f, rect.left + rect.width() * 0.25f, rect.bottom, paint);
        canvas.drawLine(cx, rect.top + rect.height() * 0.74f, rect.right - rect.width() * 0.25f, rect.bottom, paint);
    }

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private float sp(float value) {
        return value * getResources().getDisplayMetrics().scaledDensity;
    }
}
