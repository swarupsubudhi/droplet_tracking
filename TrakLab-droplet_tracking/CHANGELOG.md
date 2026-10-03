# Changelog

## v0.4 — 2026-10
- **Scale calibration from a reference width.** The new **⟷ Calibrate** button
  takes two clicks on the outer wall edges. Each click snaps to the edge with
  sub-pixel refinement, and px/mm is computed as W_px / W0. The scale source
  is recorded in the Excel `Metadata` sheet (`px2mm_source`), and RUN warns
  when the scale is uncalibrated.
- px/mm is now explicitly the **full-resolution** pixels per mm
  (mm = displayed px / (px/mm × resize)).
- The default px/mm is now a **placeholder (1.0)**. The previous default
  (56.5) was never calibrated (≈ 2.4× too small for the original setup).
  Calibrate every video.
- The default output folder is `./TrakLab_results`. It was previously a
  hard-coded `D:\TrakLab\results`.
- Added `check_traklab_requirements.m`, full documentation (`docs/`), and an
  example walkthrough (`examples/`).

## v0.33
- **Compound P2:** when lock is lost inside a segment, the tracker now holds
  the last good position **causally** and marks those frames invalid with NaN
  velocity. It no longer interpolates toward the next anchor, which had placed
  the marker ahead of the frame being shown. Lock loss is now logged with the
  frame number.

## v0.32
- Added the coordinate readout (⊹ Coords) and the horizontal datum line (─ Datum).

## v0.31 — stable
- Included: circle detection (CHT), P1 KLT tracking, compound P2 (A→B→C
  anchors), dense critical time region (fine kval), aggregate volume tool
  (`agg_vol_calc.m`), process log, per-frame Excel export (`Data` +
  `Metadata`) with real frame timestamps, and MP4 overlay export.

## v0.30 — stable
