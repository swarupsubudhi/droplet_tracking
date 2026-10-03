# TrakLab v0.4 — Circle & Point Tracking GUI for MATLAB

TrakLab is a MATLAB GUI for measuring how objects move in video. It was built
for droplet experiments: it follows a droplet's centre from frame to frame and
can also follow up to two surface features on it. It writes out positions and
velocities in millimetres.

It combines two classical methods:

- **Circle detection.** For each frame, a circular Hough transform
  (`imfindcircles`) finds the droplet centre and radius.
- **Point tracking.** Up to two user-picked points (P1, P2) are followed with
  KLT optical flow (`vision.PointTracker`). For P2, you can re-anchor the
  tracker up to three times (A→B→C) when it loses lock.

The app reads the video and caches the frames it needs in RAM. It then
tracks, draws live overlays, and exports a per-frame Excel table plus an
optional MP4 with the overlays burned in.

<!-- TODO: add a screenshot of the GUI here once the v0.4 UI changes are final:
![TrakLab GUI](docs/img/traklab_gui.png) -->

---

## Requirements

| Requirement | Why | Required? |
|---|---|---|
| MATLAB **R2021a or later** | `uifigure` apps, scrollable panels, `im2gray` | Yes |
| **Image Processing Toolbox** | `imfindcircles`, `imresize`, `im2gray`, `drawrectangle`, `drawline`, `rgb2lab` | Yes |
| **Computer Vision Toolbox** | `vision.PointTracker` (KLT) | Yes, for P1/P2 tracking |
| Windows + Microsoft Excel | Cosmetic column auto-fit of the exported workbook (COM) | No. Skipped silently elsewhere |
| Windows or macOS | `VideoWriter` `'MPEG-4'` profile for the overlay video export | Only for MP4 export |

To check your installation, run:

```matlab
check_traklab_requirements
```

> **Platform note.** MATLAB on Linux has no `MPEG-4` `VideoWriter` profile,
> so the overlay-video export fails there. Excel export and tracking still work.
> Video *reading* depends on the codecs your OS has installed. If `VideoReader`
> cannot open your file, re-encode it to H.264 MP4.

---

## Files

```
TrakLab/
├── TrakLab.m                     Main GUI app — launch this
├── agg_vol_calc.m                Aggregate volume module (called by the GUI's
│                                 "Pick box -> calc volume"; also usable standalone)
├── vid2frames_v2.m               Standalone utility: export a cropped/resized
│                                 frame sequence to disk (not called by the GUI)
├── check_traklab_requirements.m  Dependency / platform checker
├── docs/
│   ├── USER_GUIDE.md             Panel-by-panel guide and workflow
│   └── OUTPUTS.md                Excel column dictionary, conventions, caveats
├── examples/
│   └── README.md                 Walkthrough on the bundled example clip
├── CHANGELOG.md
└── LICENSE
```

---

## Install & launch

```matlab
% 1. Clone or download this repository, then add it to the path:
addpath('path/to/TrakLab');        % savepath to make it permanent

% 2. Check dependencies:
check_traklab_requirements

% 3. Launch:
app = TrakLab;
```

---

## Quick start

1. **Load Video** (`.mp4 .avi .mov .mkv .mj2`).
2. **Set the region and sampling.** Use *Show Crop Preview* to drag the crop box,
   then set *Resize* and *kval* (process every k-th frame). Scrub the timeline
   and press **[ Set tStart** and **Set tEnd ]** to choose the time window.
3. **Calibrate the scale.** Press **⟷ Calibrate** and click the outer edge of
   two walls of known separation, or type a measured *px / mm*.
   **The default px/mm = 1 is a placeholder.** With it, every "mm" output is
   really full-resolution pixels.
4. **◉ Cache Frames.**
5. **Set up the trackers.**
   - *Circle detector:* set the start frame, radius range (displayed px), polarity and sensitivity.
   - *P1 / P2:* go to the frame where tracking should start, press `from ▶`,
     then `✛ Pick` and click the point you want to track.
6. **▶ RUN.** Press **⏹ STOP** to stop early. If you stop early, nothing is
   exported, but the results stay in the app.
7. Results are written to the output folder. The default is
   `./TrakLab_results` under the folder MATLAB was in at launch.
   - `<video>_results.xlsx`, with sheets `Data` and `Metadata`
   - `<video>_results.mp4`, if overlay export is enabled

For full details, see [docs/USER_GUIDE.md](docs/USER_GUIDE.md). For a worked
example, see [examples/README.md](examples/README.md).

---

## Conventions you must know before using the numbers

- **Scale.** `px/mm` is pixels per mm in the **full-resolution** frame. It does
  not refer to the cropped or resized frame.
  Positions in mm are `displayed_px / (px_per_mm × resize)`.
- **Origin.** mm coordinates are measured from the **top-left corner of the
  crop**, not from the corner of the original video. If you change the crop
  between runs, the coordinates shift.
- **Sign.** `z = −y`, so upward motion is positive. This makes most z values
  negative.
- **Frame numbers** in the GUI ("Start frame", P2 anchors) are indices into the
  **cached** sequence, not original video frame numbers.
- **Time.** Time comes from the real timestamp of each cached frame
  (`VideoReader.CurrentTime`), not from `frame / fps`. This handles
  variable-frame-rate files.

See [docs/OUTPUTS.md](docs/OUTPUTS.md) for the column dictionary and the known
caveats in the velocity columns.

---

## Main assumptions and error sources

| Assumption | When it breaks | What to do |
|---|---|---|
| One constant px/mm per video | Perspective or keystone (≈3 % top to bottom was measured in the original setup), depth changes (object moves toward or away from the camera) | Calibrate at the object's height; report the scale uncertainty |
| The strongest Hough circle is the tracked object | Several circular objects, reflections, or a deforming droplet | Narrow the radius range, raise or lower sensitivity, crop tighter |
| KLT features stay trackable | Reacting or deforming surfaces, motion larger than the pyramid search range, occlusion, lighting changes | Check the `p*_valid` columns, use compound P2 anchors, reduce `kval` |
| Velocity = first difference of position | Amplifies pixel jitter (noise ∝ 1/Δt) | Use the `*_smooth` columns or smooth positions yourself; see OUTPUTS.md |

---

## Citing

If TrakLab contributes to a publication, please cite this repository and the underlying methods:

- Lucas, B. D. & Kanade, T. (1981). *An iterative image registration technique with an application to stereo vision.* IJCAI.
- Tomasi, C. & Kanade, T. (1991). *Detection and tracking of point features.* CMU-CS-91-132.
- Shi, J. & Tomasi, C. (1994). *Good features to track.* CVPR.
- Yuen, H. K., Princen, J., Illingworth, J. & Kittler, J. (1990). *Comparative study of Hough transform methods for circle finding.* Image and Vision Computing 8(1).
- Atherton, T. J. & Kerbyson, D. J. (1999). *Size invariant circle detection.* Image and Vision Computing 17(11).

## License

MIT. See [LICENSE](LICENSE).
