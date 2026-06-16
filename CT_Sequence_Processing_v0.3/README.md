# TrakLab v0.3 — Point & Circle Tracking GUI
## MATLAB App Designer (code-based)

---

### Requirements
| Toolbox | Used for |
|---|---|
| Image Processing Toolbox | `imfindcircles`, `imresize`, `im2gray`, `imshow` |
| Computer Vision Toolbox | `vision.PointTracker` (KLT optical flow) |
| MATLAB R2021a or later | `uifigure` scrollable panels, `uiprogressdlg` |

---

### Files
```
TrakLab/
├── TrakLab.m          ← Main GUI app (launch this)
├── vid2frames_v2.m    ← Optional disk-cache helper function
└── README.md          ← This file
```

---

### Launch
```matlab
% Add folder to path (once):
addpath('C:\path\to\TrakLab');

% Launch:
TrakLab;
```

---

### Workflow

**Step 1 — Load video**
Click `Load Video`. The app opens a file picker for `.mp4`, `.avi`, `.mov`, `.mkv`, `.mj2`.

**Step 2 — Set crop, resize & time window**
- Set **Crop X/Y/W/H** to match your region of interest (original video pixel space).
- Set **Resize** factor (0.4 = 40% of cropped size — smaller = faster).
- Set **px/mm** calibration for your lens/camera setup.
- Set **kval** = frame interval (3 = process every 3rd frame).
- Scrub the timeline to `tStart`, click `[ Set tStart`. Repeat for `Set tEnd ]`.

**Step 3 — Cache frames**
Click `◉ Cache Frames`. The app reads the video, applies crop + resize for the
selected time range, and stores all frames in RAM. A progress dialog appears.

**Cache invalidation:** If you change *any* of crop, resize, kval, tStart, or
tEnd *after* caching, the cache is automatically cleared and must be rebuilt.
Loading a different video also clears the cache.

**Step 4 — Set circle detector parameters**
Enable/disable the circle detector. Set start frame (the frame at which
`imfindcircles` begins searching), radius range, polarity, and sensitivity.

**Step 5 — Pick tracking points**
For each point (P1, P2):
1. Scrub timeline to the frame where tracking should begin.
2. Click `from ▶` to lock that frame number.
3. Click `✛ Pick`, then click directly on the video display to set (x, y).
   Press **Esc** to cancel pick mode.
4. Fine-tune pyramid levels, bidirectional error, and block size for the
   `vision.PointTracker` as needed.

**Step 6 — Run**
Click `▶ RUN`. The processing loop:
- Reads frames from RAM cache (fast)
- Runs `imfindcircles` per-frame for the droplet centre
- Runs KLT `vision.PointTracker` for P1 and P2
- Draws live trajectory overlays and moving annotation boxes in the axes
- Updates the timeline slider in real time

Click `⏹ STOP` at any time to halt. Results up to that frame are preserved.

**Step 7 — Results**
On completion:
- A results figure window opens with position-vs-time and velocity-vs-time plots.
- If **Export Excel** is checked → `results.xlsx` is written to the output folder.
- If **Export overlay video** is checked → `tracking_overlay.mp4` is rendered.

---

### Output Files
| File | Contents |
|---|---|
| `results.xlsx` | time, x/z coords (mm), velocities (mm/s) for centre, P1, P2 |
| `tracking_overlay.mp4` | Rendered MP4 with trajectory overlays burned in |

---

### Coordinate conventions
- All pixel coordinates displayed in fields are in **original video pixel space**
  (before crop or resize). This is what you would measure in the raw video.
- Internal processing uses **resized + cropped** pixel space.
- `px/mm` is defined as pixels-per-mm *in the cropped + resized* image.
  Default: `56.5` px/mm (= 113/2 from original script).
- z-coordinates in plots are negated (`z = -y_pixel / px_mm`) so that
  upward motion appears positive.

---

### Cache key
The cache is keyed on the combination of:
```
videoFile + tStart + tEnd + cropX + cropY + cropW + cropH + resize + kval
```
Changing any of these parameters invalidates the cache automatically.

---

### Known limitations / TODO
- Only 2 tracking points currently (P1, P2). More can be added by duplicating
  the `buildPointPanel` call and adding matching state variables.
- The `viscircles` call inside the processing loop is redrawn each frame
  (not cached). For very high sensitivity detection finding many circles,
  this can slow the live display.
- Video export renders frames using `getframe` (off-screen figure), which is
  slower than writing annotated frames directly. This is done after processing
  so it doesn't affect tracking speed.
- Tested on R2021a/R2022a on Windows. The `Scrollable` property on `uipanel`
  requires R2021a+. On older MATLAB, replace the right-side scrollable panel
  with a `uitabgroup` split across tabs.
