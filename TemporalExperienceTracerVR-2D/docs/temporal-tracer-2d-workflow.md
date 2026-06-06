# Temporal Tracer 2D Workflow

This app is the native Android 2D panel counterpart to the Unity temporal experience tracer in `Viscereality/Assets/Scripts/Assesment`.

## Validation Ladder

- Static config: `tools\validate-temporal-tracer-assets.ps1`
- Logic: `TraceResamplerTest`
- Local render: `tools\render-temporal-tracer-visuals.ps1`
- APK build: `tools\build-apk.ps1`
- Quest command replay: launch with `mq.autoTrace=true`
- Manual gate: draw with Quest controller/hand panel input and confirm save only enables after left-to-right completion

## Export Contract

Each trace produces:

- one `.svg` vector file fitted to the configured axis `viewBox`,
- one point-level `.csv`,
- one full-fidelity `.json`,
- one row in `session-index.jsonl`,
- one row in `<runId>_session-summary.csv`.

Every run receives a unique `runId` in `yyyyMMdd_HHmmss_SSS_<uuid8>` format. Filenames include `runId`, trace number, participant name, and trace label, so repeated blocks do not overwrite data.

## Axis Customization

Use `TemporalTracerConfig.json` or the static editor to change:

- total elapsed time and display unit,
- x/y grid labels,
- y-axis range,
- top/bottom anchor text,
- SVG dimensions,
- start/end gate strictness,
- resampled point count.

The saved SVG contains the configured grid, axis labels, metadata, and a
visible `trace-smooth-vector` path. That path is true SVG vector geometry built
from the raw captured pointer samples, so it remains resolution-independent
when scaled or imported into later analysis/figure tools. The SVG also embeds
hidden raw and normalized point polylines for auditability. JSON stores both
raw and normalized points. CSV stores numeric values using normalized
`u_0to1`, `v_0to1`, plus axis-scaled `x_axis` and `y_axis`.

To avoid a vertical artifact at the 0 axis, the participant starts in the blue
area just outside the axis. Movement before crossing into the plot is ignored
after the first anchored point, and the exported x coordinates are clamped to
the final axis range.

## ChainLink Use

Unity or ChainLink can launch the app via explicit component intent and pass participant/session metadata. For chained completion, set:

- `mq.finishBehavior=resumeCaller` plus `mq.callerPackage` and optional `mq.callerActivity`, or
- `mq.finishBehavior=openNext` plus `mq.nextPackage` and optional `mq.nextActivity`, or
- `mq.finishBehavior=staySaved` for standalone review.

The app always saves first, then performs the requested completion behavior.
