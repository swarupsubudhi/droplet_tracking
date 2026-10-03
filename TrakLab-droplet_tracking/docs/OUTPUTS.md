# TrakLab v0.4 — Output Reference

When a run finishes (and is not stopped early), TrakLab writes the files below
to the output folder. `<video>` is the base name of the loaded file.

| File | Written when |
|---|---|
| `<video>_results.xlsx` | **Export Excel** is ticked |
| `<video>_results.mp4` | **Export overlay video** is ticked (Windows or macOS) |
| `<video>_aggbox_HHmmss.png` | The aggregate-volume tool is used |
| `<video>_log_yyyyMMdd_HHmmss.txt` | **Save Log** is pressed |

An existing `<video>_results.xlsx` is **deleted and overwritten** without
warning. Rename it or change the output folder if you want to keep earlier runs.

---

## Excel — sheet `Data` (one row per cached frame)

| Column | Unit | Meaning |
|---|---|---|
| `frame_index` | — | Cached-frame index (1…N). This is **not** the original video frame number |
| `time_s` | s | Time from the first cached frame. Taken from real frame timestamps |
| `center_detected` | 0/1 | Whether `imfindcircles` returned a circle on this frame |
| `center_status` | text | `OK` or `droplet not detected` |
| `xc_mm`, `zc_mm` | mm | Centre position. NaN where it was not detected |
| `xc_mm_interp`, `zc_mm_interp` | mm | The same, with **interior** gaps linearly interpolated in time. Ends are not extrapolated |
| `vxc_mms`, `vzc_mms` | mm/s | Centre velocity by first difference |
| `vzc_mms_smooth` | mm/s | `smoothdata(vzc, 'gaussian', 20)`. The window is 20 samples. This is the curve shown in the results plot |
| `center_radius_px` | px | Detected radius in **displayed (resized) px**. To get mm, divide by (px/mm × resize) |
| `p1_valid` | 0/1 | Whether the KLT tracker reported a valid point on this frame |
| `x1_mm`, `z1_mm` | mm | P1 position |
| `vx1_mms`, `vz1_mms`, `vz1_mms_smooth` | mm/s | P1 velocity (raw and smoothed) |
| `p2_valid`, `x2_mm`, `z2_mm`, `vx2_mms`, `vz2_mms`, `vz2_mms_smooth` | | The same columns for P2 |

## Excel — sheet `Metadata`

The sheet records the source video, export time, frame counts, the crop
(`crop_x/y/w/h_px`), `resize_factor`, `px2mm_fullres`, and **`px2mm_source`**
(calibrated, manual, or uncalibrated placeholder). It also records the
calibration width and row, `kval`, `video_fps`, `t_start_s`/`t_end_s`, and the
sign and unit conventions.

**Check `px2mm_source` before using any mm value.** If it says *placeholder*,
the "mm" columns are actually full-resolution pixels.

---

## Coordinate system

```
 crop top-left (0,0) ──► x (mm)
        │
        ▼  y (image rows)          exported z = −y   (up = positive)
```

- `x_mm = x_display_px / (px_per_mm × resize)`, measured from the crop's left edge.
- `z_mm = −y_display_px / (px_per_mm × resize)`, measured from the crop's top
  edge. Most z values are therefore negative.
- To get original-video pixel coordinates, compute
  `x_orig = x_mm × px_per_mm + crop_x_px`. Use the same form for y (with
  `y = −z`).

---

## Velocity caveats

These follow directly from how v0.4 computes velocities. Account for them in
your analysis.

1. **First difference.** Velocity is `v_i = (s_i − s_{i−1}) / (t_i − t_{i−1})`.
   Position noise σ becomes velocity noise of about √2·σ/Δt. Reducing `kval`
   (smaller Δt) therefore makes raw velocities *noisier*, not cleaner.
2. **Centre, frame after a gap.** If the centre was missed on frame *i−1* but
   found on frame *i*, `vxc/vzc` on frame *i* is **0**, not NaN. Treat a 0 that
   follows a `center_detected = 0` row as missing.
3. **P1, and P2 with compound off: frames where lock was lost.** The position
   is **held at the last valid value** and velocity is **0** on those frames.
   Filter with `p1_valid == 1` / `p2_valid == 1`. On the first valid frame after
   a loss, the velocity is computed against the held position, which can
   produce a spike.
4. **Compound P2.** Lost frames and anchor seams already have NaN velocity, so
   rule 3 does not apply.
5. **Smoothed columns.** The Gaussian window is a fixed **20 samples**. Its
   length in time depends on `kval` and on the dense region. `smoothdata` also
   treats the zeros described in rules 2 and 3 as real data. When those occur,
   smooth the *valid positions* yourself and differentiate the result.

## Calibration caveats

- One constant px/mm for the whole video. Perspective, keystone, and
  out-of-focal-plane motion are not corrected.
- Positions scale as 1/(px/mm), and the aggregate volume scales as
  1/(px/mm)³. A 1 % scale error therefore becomes about 1 % in positions and
  velocities, and about 3 % in volume.
