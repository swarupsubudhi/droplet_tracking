# Example — tracking a droplet in the bundled clip

<!-- MAINTAINER: fill every «TBD» before release. Values must be measured on
     the TRIMMED clip, not the original 4K recording (see "Preparing the clip"). -->

**File:** `examples/example_clip.mp4` («TBD» MB, «TBD» × «TBD» px, «TBD» fps, «TBD» s)

**What it shows:** «TBD — one sentence, e.g. a magnetically actuated droplet
moving through the cuvette.»

## 1. Settings used

| Setting | Value | Notes |
|---|---|---|
| tStart / tEnd | «TBD» s / «TBD» s | |
| Crop X / Y / W / H | «TBD» | original px of *this clip* |
| Resize | «TBD» | |
| kval | «TBD» | |
| Reference width W0 (cuvette mm) | «TBD» mm | |
| Calibrated px/mm | «TBD» | from ⟷ Calibrate on this clip |
| Circle: radius min / max | «TBD» / «TBD» px | displayed px |
| Circle: polarity / sensitivity | «TBD» / «TBD» | |
| P1 start frame, (x, y) | «TBD» | |
| P2 anchors A / B / C | «TBD» | |

## 2. Steps

1. `addpath` the repository root, then run `app = TrakLab;`.
2. Click **Load Video** and select `examples/example_clip.mp4`.
3. Enter the crop, resize and kval values from the table, or use
   **⊞ Show Crop Preview**.
4. Scrub to tStart and press **[ Set tStart**. Scrub to tEnd and press
   **Set tEnd ]**.
5. Press **⟷ Calibrate** and click the outer edges of the left and right
   walls. Check that px/mm is close to «TBD».
6. Press **◉ Cache Frames**.
7. Enter the circle and point settings from the table. Use **✛ Pick** to place
   points.
8. Press **▶ RUN**.

## 3. Expected results

Your numbers should be close to these, within about one pixel of position
(≈ «TBD» mm):

| Quantity | Expected |
|---|---|
| Frames processed | «TBD» |
| Centre detected / missed | «TBD» / «TBD» |
| Centre displacement z (first → last valid) | «TBD» mm |
| Peak smoothed v_z (centre) | «TBD» mm/s |

Small differences between MATLAB releases are normal, because of
`imfindcircles` and codec decoding. Large differences usually mean the
calibration or radius range is different.

---

## Preparing the clip (maintainer notes)

GitHub rejects files larger than 100 MB and warns above 50 MB. Aim for
**≤ 20 MB** so the repository stays quick to clone. Two example `ffmpeg`
commands:

```bash
# Trim only (keeps resolution, so a calibration made on the original still applies)
ffmpeg -ss 00:00:05 -i original.mp4 -t 4 -c:v libx264 -crf 23 -pix_fmt yuv420p -an example_clip.mp4

# Trim + halve the resolution (smaller file)
ffmpeg -ss 00:00:05 -i original.mp4 -t 4 -vf "scale=iw/2:-2" -c:v libx264 -crf 23 -pix_fmt yuv420p -an example_clip.mp4
```

Things that can make the example disagree with the original analysis:

- **Downscaling changes px/mm.** Halving the resolution halves px/mm. Calibrate
  on the trimmed clip, not the original.
- **Re-encoding can change timestamps.** Check the clip with
  `ffprobe -show_streams example_clip.mp4` (frame rate, `nb_frames`). If the
  source has a variable frame rate, add `-fps_mode cfr` (or `-vsync cfr` on
  older ffmpeg). Only do this if you accept that frames may be duplicated or
  dropped.
- **Compression (CRF) softens edges.** This can shift `imfindcircles` radii
  and the calibration edge snap by a fraction of a pixel. Use a lower CRF
  (for example 18) if the file size allows it.
- **Permission to publish.** Confirm that the lab or university allows the
  clip to be published.
