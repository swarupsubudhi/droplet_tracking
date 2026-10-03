# TrakLab v0.4 — User Guide

This guide follows the GUI from top to bottom and then covers the full workflow.
Default values are the ones in `TrakLab.m` v0.4.

---

## 1. Layout

| Region | Contents |
|---|---|
| Header | Load Video, Clear Cache, maximise/restore, loaded file path |
| Video area | Displays frames, live overlays, a pixel ruler on the border, and an mm scale bar |
| Transport bar | Go to start, step back, play/pause, step forward, go to end, **⊕ Zoom**, **⊹ Coords**, **─ Datum** |
| Timeline | Seek slider, **[ Set tStart**, **Set tEnd ]**, and a time readout in ms plus the cached-frame index |
| Right column | Preprocessing, Circle Detector, Point 1, Point 2, Aggregate volume, Output, Process log |
| Status bar | Current state and the last message |

The app moves through these states: `IDLE → VIDEO_LOADED → CACHED → PROCESSING → DONE`.
Each control is enabled only in the states where it makes sense.

---

## 2. Preprocessing panel

| Control | Default | Meaning |
|---|---|---|
| Crop X / Y / W / H | — | Region of interest in **original video pixels** (1-based) |
| Resize | 0.4 | Scale factor applied after cropping. Smaller is faster but less precise |
| px / mm | **1 (placeholder)** | Pixels per mm in the **full-resolution** frame |
| cuvette mm | 12 | Known physical width (W0) used by **⟷ Calibrate** |
| ⟷ Calibrate | — | Two-click scale calibration (see §2.1) |
| kval | 3 | Keep every k-th video frame |
| Enable dense region / fine kval / [ Set start, Set end ] | off / 1 | A time window that is sampled with `fine kval` instead of `kval` |
| ⊞ Show Crop Preview | — | Shows the full frame with a draggable crop rectangle |
| ◉ Cache Frames | — | Reads, crops and resizes the selected frames into RAM |

Changing the crop, resize, kval, tStart/tEnd, or the dense-region settings
**invalidates the cache**, so you must cache again. Loading another video also
clears it.

### 2.1 Calibrate (px/mm)

1. Press **⟷ Calibrate**. The full-resolution frame at the current time is shown.
2. Click the **outer edge of the left wall**, then the **outer edge of the
   right wall**, at the height of the object you are tracking. Press `Esc` to cancel.
3. Each click snaps to the outermost strong intensity edge within about 30 px
   outward or 10 px inward of where you clicked. The search uses the gradient
   of an intensity profile averaged over 41 rows, and the edge position is
   refined to sub-pixel accuracy.
4. `px/mm = W_px / W0`. The label under the field then shows `cal: <W_px> px / <W0> mm`.

Notes and failure modes:

- **The snap looks for an edge, not specifically a wall.** If another strong edge
  (a label, a shadow, the droplet) lies inside the search window, the snap can
  land on it. Check the markers before you accept the result.
- If you change *cuvette mm* after calibrating, px/mm is recomputed from the
  stored pixel width. If you type a px/mm value directly, the calibration is
  discarded and the source is recorded as "manual entry".
- One constant is used per video, with no perspective or keystone correction.
- The scale source is written to the Excel `Metadata` sheet (`px2mm_source`).
  Runs with an uncalibrated scale also log a warning when you press RUN.

### 2.2 Dense (critical) region

Use this when one part of the clip needs finer time resolution, for example the
moment two droplets merge. Frames inside `[start, end]` are kept every
`fine kval` frames. Frames outside are kept every `kval` frames.

> **Caveat:** the sample spacing Δt is then non-uniform. Velocities use the
> true per-frame Δt, so they stay correct. However, the `*_smooth` columns use
> a fixed window of 20 **samples**, so the smoothing covers a different span of
> time inside and outside the dense region. The exported MP4 also plays at a
> constant `fps / kval`, so the dense region appears in slow motion.

---

## 3. Circle Detector panel

| Control | Default | Meaning |
|---|---|---|
| Enable circle detection | on | Run `imfindcircles` on every cached frame from *Start frame* onward |
| Start frame / from ▶ | — | Cached-frame index where detection begins. `from ▶` copies the current timeline position |
| Radius min / max | 40 / 140 | Search radius in **displayed (resized) px** |
| Polarity | dark | `dark` = object darker than the background; `bright` = the opposite |
| Sensitivity | 0.90 | Higher values find more circles, including false ones |

The **first** circle returned (the one with the strongest accumulator peak) is
taken as the droplet. When no circle is found, that frame is flagged
`center_detected = 0`, and a console line is printed.

Tips:

- Keep `max/min` radius ≲ 3 for reliable detection. Very wide ranges degrade
  accuracy and speed (see the MATLAB `imfindcircles` docs).
- Below a radius of about 10 px, `imfindcircles` accuracy degrades. Increase
  *Resize* if needed.

---

## 4. Point 1 / Point 2 panels (KLT)

| Control | Default | Meaning |
|---|---|---|
| Enable tracking | on | Turn this point on |
| Start frame / from ▶ | — | Cached-frame index where the tracker is initialised |
| x, y (orig px) / ✛ Pick | — | Seed point. `✛ Pick` then a click on the video sets it. `Esc` cancels |
| Pyramid lvls | P1: 4, P2: 5 | `NumPyramidLevels`. More levels allow larger motion between frames |
| Bidir error | P1: 4.0, P2: 5.0 | `MaxBidirectionalError` (px). Smaller values reject drift sooner |
| Block W × H | 51 × 51 | Neighbourhood size in px (odd). Larger is more robust but blurs local motion |

### 4.1 Compound P2 (A → B → C)

Use this when P2 loses lock, for example on a deforming droplet or after an
occlusion. **Compound (A→B→C)** is ticked by default. Enter up to three anchors
(frame, x, y). Each anchor needs a frame number ≥ 1, and the frame numbers
must strictly increase. Anchors that do not meet this are dropped and logged.
Leave the B or C frame at 0 to skip that anchor. With compound off, only
anchor A is used and P2 behaves like P1.

- The tracker is **hard-reset** at each anchor and tracks forward to the next one.
- If lock is lost inside a segment, the last good position is **held** (it
  never borrows a future anchor's position). Those frames are marked invalid,
  their velocity is set to NaN, and the log suggests where to add an anchor.
- The velocity at each anchor (seam) frame is set to NaN, so the forced jump in
  position does not appear as a velocity spike.

---

## 5. Transport tools

- **⊕ Zoom.** Toggles mouse zoom on the video (`zoomInteraction`).
- **⊹ Coords.** Click to read a position in display px, original px, and mm.
  The mm value is measured from the crop's top-left corner.
- **─ Datum.** Places a draggable horizontal reference line. The label shows
  its y position in original px and in mm. *The datum is a visual reference
  only. It is not exported.*

---

## 6. Aggregate volume panel

This panel calls `agg_vol_calc.m`.

1. Set the box size (default 200 px) and the axis of revolution (vertical or horizontal).
2. Click **Pick box → calc volume**, position the square on the aggregate, and
   **double-click** it to confirm.
3. The box is saved as a PNG in the output folder. The volume is then computed
   as a solid of revolution of the segmented (CIELAB brown) silhouette.

The method makes three assumptions. Read the header of `agg_vol_calc.m` before
reporting numbers:

1. **Axisymmetry.** The `asymmetry` field quantifies how well this holds, and
   the log warns above 15 %.
2. **Calibration.** Volume scales with (mm/px)³. The GUI uses
   `1/(px2mm·resize)` because the box comes from the displayed frame.
3. **Colour segmentation.** The default brown reference and Otsu threshold may
   need tuning for your lighting.

---

## 7. Output panel and process log

| Control | Default | Meaning |
|---|---|---|
| Folder / Browse | `./TrakLab_results` | Output folder. It is created if missing |
| Export Excel | on | Writes `<video>_results.xlsx` after a completed run |
| Export overlay video | on | Writes `<video>_results.mp4` (Windows and macOS) |
| ▶ RUN / ⏹ STOP | — | Starts or stops tracking. **STOP skips the export** |
| Process log (Save Log / Clear) | — | Timestamped messages. They are also printed to the Command Window |

After a completed run, a figure shows position versus time and velocity versus time.

---

## 8. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `VideoReader` error on load | Missing codec | Re-encode: `ffmpeg -i in.mov -c:v libx264 -pix_fmt yuv420p out.mp4` |
| Out of memory while caching | Too many frames or too large | Lower *Resize*, raise *kval*, shorten the window, crop tighter |
| Circle jumps between objects | Several candidates in the radius range | Narrow the radius range, crop, adjust sensitivity or polarity |
| Many `center_detected = 0` | Radius range is in the wrong units (it uses displayed px), sensitivity too low, or wrong polarity | Measure the radius with **⊹ Coords**, then retune |
| P1/P2 freezes in place | KLT lost lock. The position is held, and `p*_valid = 0` | Lower kval, more pyramid levels, larger block, or compound P2 anchors |
| MP4 export error on Linux | No `MPEG-4` profile | Export on Windows or macOS, or use the Excel data |
| Numbers look ~100× too large | px/mm left at the placeholder value of 1 | Calibrate, then re-run |
