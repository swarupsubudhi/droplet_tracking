classdef TrakLab < matlab.apps.AppBase
% TrakLab v0.4  —  Point & Circle Tracking GUI
% v0.4: px/mm is calibrated from the cuvette OUTER width (W0, default 12 mm),
%       the same scale used for the CT volumetry (s = W/W0, full-resolution px).
%       'Calibrate' button: click the outer edge of the left and right cuvette
%       walls on the full frame; each click snaps to the outermost wall edge
%       nearby (sub-pixel).  One constant px/mm per video (no keystone model).
% Requires: Image Processing Toolbox, Computer Vision Toolbox
% Tested on MATLAB R2021a+
%
% Launch:   app = TrakLab;
% -------------------------------------------------------------------------

    %% ── PUBLIC UI COMPONENTS ──────────────────────────────────────────────
    properties (Access = public)
        UIFigure        matlab.ui.Figure

        % Header
        LblTitle        matlab.ui.control.Label
        LblVideoPath    matlab.ui.control.Label
        BtnLoadVideo    matlab.ui.control.Button
        BtnClearCache   matlab.ui.control.Button
        BtnMaximize     matlab.ui.control.Button
        PnlHeader       matlab.ui.container.Panel
        PnlTransport    matlab.ui.container.Panel
        PnlTimeline     matlab.ui.container.Panel
        PnlStatus       matlab.ui.container.Panel
        PnlRight        matlab.ui.container.Panel
  
        % Video axes
        VideoAxes       matlab.ui.control.UIAxes

        % Transport bar
        BtnGoStart      matlab.ui.control.Button
        BtnStepBack     matlab.ui.control.Button
        BtnPlayPause    matlab.ui.control.Button
        BtnStepFwd      matlab.ui.control.Button
        BtnGoEnd        matlab.ui.control.Button
        BtnZoom         matlab.ui.control.Button
        LblTime         matlab.ui.control.Label

        % Timeline
        SliderTimeline  matlab.ui.control.Slider
        BtnSetTStart    matlab.ui.control.Button
        BtnSetTEnd      matlab.ui.control.Button
        LblTStart       matlab.ui.control.Label
        LblTEnd         matlab.ui.control.Label

        % Status bar
        LblStatus       matlab.ui.control.Label

        % ── Settings: Preprocessing ────────────────────────────────────
        PnlPreproc      matlab.ui.container.Panel
        FldCropX        matlab.ui.control.NumericEditField
        FldCropY        matlab.ui.control.NumericEditField
        FldCropW        matlab.ui.control.NumericEditField
        FldCropH        matlab.ui.control.NumericEditField
        FldResize       matlab.ui.control.NumericEditField
        FldPx2mm        matlab.ui.control.NumericEditField
        FldKval         matlab.ui.control.NumericEditField
        ChkCritEnable   matlab.ui.control.CheckBox
        FldCritKval     matlab.ui.control.NumericEditField
        BtnSetCritStart matlab.ui.control.Button
        BtnSetCritEnd   matlab.ui.control.Button
        LblCritStart    matlab.ui.control.Label
        LblCritEnd      matlab.ui.control.Label
        BtnShowCropPreview matlab.ui.control.Button
        BtnCacheFrames  matlab.ui.control.Button

        % ── Settings: Circle Detector ──────────────────────────────────
        PnlCircle       matlab.ui.container.Panel
        ChkCircleEnable matlab.ui.control.CheckBox
        FldCircleFrame  matlab.ui.control.NumericEditField
        BtnCircleFromT  matlab.ui.control.Button
        FldCircleRMin   matlab.ui.control.NumericEditField
        FldCircleRMax   matlab.ui.control.NumericEditField
        DdCirclePol     matlab.ui.control.DropDown
        SldCircleSens   matlab.ui.control.Slider
        LblCircleSens   matlab.ui.control.Label

        % ── Settings: Point 1 ──────────────────────────────────────────
        PnlP1           matlab.ui.container.Panel
        ChkP1Enable     matlab.ui.control.CheckBox
        FldP1Frame      matlab.ui.control.NumericEditField
        BtnP1FromT      matlab.ui.control.Button
        FldP1X          matlab.ui.control.NumericEditField
        FldP1Y          matlab.ui.control.NumericEditField
        BtnPickP1       matlab.ui.control.Button
        FldP1Pyr        matlab.ui.control.NumericEditField
        FldP1Bde        matlab.ui.control.NumericEditField
        FldP1BlkW       matlab.ui.control.NumericEditField
        FldP1BlkH       matlab.ui.control.NumericEditField

        % ── Settings: Point 2 ──────────────────────────────────────────
        PnlP2           matlab.ui.container.Panel
        ChkP2Enable     matlab.ui.control.CheckBox
        FldP2Frame      matlab.ui.control.NumericEditField
        BtnP2FromT      matlab.ui.control.Button
        FldP2X          matlab.ui.control.NumericEditField
        FldP2Y          matlab.ui.control.NumericEditField
        BtnPickP2       matlab.ui.control.Button
        FldP2Pyr        matlab.ui.control.NumericEditField
        FldP2Bde        matlab.ui.control.NumericEditField
        FldP2BlkW       matlab.ui.control.NumericEditField
        FldP2BlkH       matlab.ui.control.NumericEditField
        ChkP2Compound   matlab.ui.control.CheckBox
        FldP2bFrame     matlab.ui.control.NumericEditField
        FldP2bX         matlab.ui.control.NumericEditField
        FldP2bY         matlab.ui.control.NumericEditField
        BtnPickP2b      matlab.ui.control.Button
        FldP2cFrame     matlab.ui.control.NumericEditField
        FldP2cX         matlab.ui.control.NumericEditField
        FldP2cY         matlab.ui.control.NumericEditField
        BtnPickP2c      matlab.ui.control.Button

        % ── Settings: Output ───────────────────────────────────────────
        PnlOutput       matlab.ui.container.Panel
        FldOutFolder    matlab.ui.control.EditField
        BtnBrowseOut    matlab.ui.control.Button
        ChkExportVid    matlab.ui.control.CheckBox
        ChkExportXls    matlab.ui.control.CheckBox
        BtnRun          matlab.ui.control.Button
        BtnStop         matlab.ui.control.Button

        % Process log
        TxtLog          matlab.ui.control.TextArea
        BtnSaveLog      matlab.ui.control.Button
        BtnClearLog     matlab.ui.control.Button

        % Aggregate volume tool
        FldAggBox       matlab.ui.control.NumericEditField
        DdAggAxis       matlab.ui.control.DropDown
        BtnAggPick      matlab.ui.control.Button
        LblAggResult    matlab.ui.control.Label
    end

    %% ── PRIVATE STATE ─────────────────────────────────────────────────────
    properties (Access = private)

        % State machine
        AppState    = 'IDLE'   % IDLE | VIDEO_LOADED | CACHED | PROCESSING | DONE

        % Video
        VideoFile   = ''
        VidReader               % VideoReader object
        VideoDuration = 0
        VideoFPS      = 24

        % Cache
        FrameCache  = {}        % cell array of uint8 RGB images
        GrayCache   = {}        % cell array of uint8 grayscale images
        FrameTimestamps = []    % timestamps of each cached frame (seconds)
        NCachedFrames   = 0
        CacheKeyStr     = ''
        CacheValid      = false

        % Timeline state
        TStart = 0
        TEnd   = 5

        % Pick mode
        PickMode = ''           % '' | 'p1' | 'p2'

        % Crop preview
        hCropRect               % drawrectangle handle
        InCropPreview = false   % true while crop overlay is active

        % Playback timer
        PlayTimer
        IsPlaying    = false
        IsDragging   = false   % true while user drags slider; blocks timer updates

        % Authoritative display time — always in sync with what is shown.
        % VidReader.CurrentTime can drift due to keyframe snapping, so we track
        % this separately and use it as the reference for playback start position.
        CurrentDisplayTime = 0
        TCritStart = 0          % critical (dense-kval) region start time (s)
        TCritEnd   = 0          % critical (dense-kval) region end time (s)

        % Image/axes handle
        ImgHandle               % handle to imshow image object

        % Overlay handles (pre-allocated for speed)
        hCenterLine, hCenterPt, hCenterCirc
        hP1Line, hP1Pt
        hP2Line, hP2Pt
        hAnnCenter, hAnnP1, hAnnP2
        hScaleBar, hScaleTxt          % mm scale-bar overlay
        hPickP1, hPickP2              % seed-point pick markers (clearable/re-pickable)
        hPickP2b, hPickP2c            % compound-P2 anchor pick markers

        % ── Datum line + coords readout (viewspace overlays) ────────────
        CoordsMode      = false   % true while coord-readout click mode active
        DatumMode       = false   % true while datum placement active
        hDatum                    % images.roi.Line handle (draggable datum)
        hDatumListener            % MovingROI listener (locks horizontal)
        BtnCoords       matlab.ui.control.Button
        BtnDatum        matlab.ui.control.Button
        LblDatum        matlab.ui.control.Label

        % ── px/mm calibration from the cuvette outer width (v0.4) ──────
        FldCuvMM        matlab.ui.control.NumericEditField   % cuvette outer width W0 (mm)
        BtnCalib        matlab.ui.control.Button
        LblCalib        matlab.ui.control.Label
        CalibMode       = false   % true while collecting the two wall clicks
        CalibPts        = zeros(0,2)  % clicked/snapped wall points (full-res px)
        CalibWpx        = NaN     % measured cuvette outer width (full-res px)
        CalibRow        = NaN     % image row of the measurement (full-res px)
        CalibSource     = 'placeholder default (1 px/mm), uncalibrated'
        CalibFrame      = []      % raw full-resolution frame used for calibration

        SnapGuard       = false   % guards slider write-back against ValueChanged re-entry
        LblSeek         matlab.ui.control.Label   % live ms + frame readout under the seek bar

        % Processing
        StopRequested = false
        LogLines = {}                   % accumulated process-log lines (cellstr)

        % Results storage
        RealTime
        CenterTraj, CenterTraj_mm
        P1Traj, P1Traj_mm
        P2Traj, P2Traj_mm
        VelCz, VelCx
        VelP1x, VelP1y
        VelP2x, VelP2y
        CenterFound, P1Valid, P2Valid   % per-frame detection / tracking-validity flags
        CenterRadius                    % per-frame detected circle radius (displayed px)
        N_proc = 0

        % Colors (RGB 0-1)
        ColCenter = [0.85 0.23 0.23]
        ColP1     = [0.22 0.53 0.86]
        ColP2     = [0.11 0.62 0.46]
    end

    %% ── PRIVATE METHODS ───────────────────────────────────────────────────
    methods (Access = private)

        % ════════════════════════════════════════════════════════════════════
        %  STARTUP
        % ════════════════════════════════════════════════════════════════════
        function startupFcn(app)
            app.AppState = 'IDLE';
            app.updateStateUI();
            app.setStatus('Load a video to begin.', 'idle');
        end

        % ════════════════════════════════════════════════════════════════════
        %  STATE MACHINE
        % ════════════════════════════════════════════════════════════════════
        function setState(app, s)
            app.AppState = s;
            app.updateStateUI();
        end

        function updateStateUI(app)
            hasVid  = ~isempty(app.VideoFile);
            cached  = app.CacheValid;
            isProc  = strcmp(app.AppState, 'PROCESSING');
            isDone  = strcmp(app.AppState, 'DONE');

            % Header
            app.BtnClearCache.Enable  = onoff(hasVid);

            % Transport
            app.BtnGoStart.Enable     = onoff(hasVid && ~isProc);
            app.BtnStepBack.Enable    = onoff(hasVid && ~isProc);
            app.BtnPlayPause.Enable   = onoff(hasVid && ~isProc);
            app.BtnStepFwd.Enable     = onoff(hasVid && ~isProc);
            app.BtnGoEnd.Enable       = onoff(hasVid && ~isProc);
            app.SliderTimeline.Enable = onoff(hasVid && ~isProc);
            app.BtnSetTStart.Enable   = onoff(hasVid && ~isProc);
            app.BtnSetTEnd.Enable     = onoff(hasVid && ~isProc);

            % Preprocessing
            app.BtnCacheFrames.Enable = onoff(hasVid && ~isProc);
            if ~isempty(app.BtnCalib) && isvalid(app.BtnCalib)
                app.BtnCalib.Enable = onoff(hasVid && ~isProc);
            end

            % "From ▶" buttons (need video, not necessarily cache)
            app.BtnCircleFromT.Enable = onoff(hasVid);
            app.BtnP1FromT.Enable     = onoff(hasVid);
            app.BtnP2FromT.Enable     = onoff(hasVid);

            % Point picking (needs cache)
            app.BtnPickP1.Enable = onoff(cached && ~isProc);
            app.BtnPickP2.Enable = onoff(cached && ~isProc);
            app.BtnPickP2b.Enable = onoff(cached && ~isProc);
            app.BtnPickP2c.Enable = onoff(cached && ~isProc);
            if ~isempty(app.BtnCoords) && isvalid(app.BtnCoords)
                app.BtnCoords.Enable = onoff(cached && ~isProc);
            end
            if ~isempty(app.BtnDatum) && isvalid(app.BtnDatum)
                app.BtnDatum.Enable = onoff(cached && ~isProc);
            end

            % Run / Stop
            app.BtnRun.Enable  = onoff(cached && ~isProc);
            app.BtnStop.Enable = onoff(isProc);

            % Highlight active pick buttons
            if strcmp(app.PickMode, 'p1')
                app.BtnPickP1.BackgroundColor = app.ColP1;
                app.BtnPickP1.FontColor = [1 1 1];
            else
                app.BtnPickP1.BackgroundColor = [0.18 0.22 0.28];
                app.BtnPickP1.FontColor = [0.75 0.75 0.75];
            end
            if strcmp(app.PickMode, 'p2')
                app.BtnPickP2.BackgroundColor = app.ColP2;
                app.BtnPickP2.FontColor = [1 1 1];
            else
                app.BtnPickP2.BackgroundColor = [0.18 0.22 0.28];
                app.BtnPickP2.FontColor = [0.75 0.75 0.75];
            end
            app.highlightPickBtn(app.BtnPickP2b, strcmp(app.PickMode, 'p2b'));
            app.highlightPickBtn(app.BtnPickP2c, strcmp(app.PickMode, 'p2c'));
        end

        function highlightPickBtn(app, btn, active)
            if isempty(btn) || ~isvalid(btn), return; end
            if active
                btn.BackgroundColor = app.ColP2; btn.FontColor = [1 1 1];
            else
                btn.BackgroundColor = [0.18 0.22 0.28]; btn.FontColor = [0.75 0.75 0.75];
            end
        end

        function setStatus(app, msg, level)
            app.LblStatus.Text = msg;
            switch level
                case 'ok',    app.LblStatus.FontColor = [0.15 0.72 0.38];
                case 'warn',  app.LblStatus.FontColor = [0.90 0.62 0.05];
                case 'error', app.LblStatus.FontColor = [0.85 0.23 0.23];
                otherwise,    app.LblStatus.FontColor = [0.50 0.53 0.58];
            end
            app.log(msg, level);          % mirror every status line into the log
            drawnow limitrate;
        end

        function log(app, msg, level)
            % Append a timestamped line to the process log (and the console).
            if nargin < 3 || isempty(level), level = 'info'; end
            ts = char(datetime('now', 'Format', 'HH:mm:ss'));
            switch lower(level)
                case 'error',            tag = 'ERR ';
                case {'warn','warning'}, tag = 'WARN';
                case 'ok',               tag = 'OK  ';
                otherwise,               tag = '    ';
            end
            entry = sprintf('%s %s %s', ts, tag, msg);
            app.LogLines{end+1,1} = entry;
            maxN = 1000;                                   % cap in-memory history
            if numel(app.LogLines) > maxN
                app.LogLines = app.LogLines(end-maxN+1:end);
            end
            fprintf('%s\n', entry);
            if ~isempty(app.TxtLog) && isvalid(app.TxtLog)
                app.TxtLog.Value = app.LogLines;
                try, scroll(app.TxtLog, 'bottom'); catch, end %#ok<NOSEMI>
            end
        end

        function saveLogFcn(app)
            try
                outDir = app.FldOutFolder.Value;
                if ~exist(outDir, 'dir'), mkdir(outDir); end
                fn = fullfile(outDir, [app.baseName() '_log_' ...
                    char(datetime('now','Format','yyyyMMdd_HHmmss')) '.txt']);
                fid = fopen(fn, 'w');
                if fid < 0
                    app.setStatus('Could not open log file for writing.', 'error'); return;
                end
                for k = 1:numel(app.LogLines)
                    fprintf(fid, '%s\r\n', app.LogLines{k});
                end
                fclose(fid);
                app.setStatus(['Log saved -> ' fn], 'ok');
            catch ME
                app.setStatus(['Log save error: ' ME.message], 'error');
            end
        end

        function clearLogFcn(app)
            app.LogLines = {};
            if ~isempty(app.TxtLog) && isvalid(app.TxtLog)
                app.TxtLog.Value = {''};
            end
            app.setStatus('Log cleared.', 'info');
        end

        function aggVolumeFcn(app)
            % Bridge to the standalone agg_vol_calc module: let the user draw a
            % fixed NxN box on the current frame, save it as PNG (no JPEG colour
            % bleed), and compute the axisymmetric aggregate volume.
            try
                if isempty(app.ImgHandle) || ~isvalid(app.ImgHandle)
                    app.setStatus('Preview or process a frame first.', 'warn'); return;
                end
                if exist('agg_vol_calc', 'file') ~= 2
                    app.setStatus('agg_vol_calc.m not found on the MATLAB path.', 'error'); return;
                end
                I = app.ImgHandle.CData;
                [H, W, ~] = size(I);
                n = round(app.FldAggBox.Value);
                n = max(8, min(n, min(H, W)));

                app.log(sprintf('Draw the %dx%d ROI on the aggregate, then double-click it to confirm.', n, n));
                x0 = round(W/2 - n/2); y0 = round(H/2 - n/2);
                roi = drawrectangle(app.VideoAxes, 'Position', [x0 y0 n n], ...
                    'FixedAspectRatio', true, 'Color', [0.55 0.35 0.20], 'LineWidth', 1);
                wait(roi);                              % blocks until double-click
                p = round(roi.Position); delete(roi);

                % Snap to exactly NxN at the chosen top-left, clamped to bounds
                xs = max(1, min(W-n+1, p(1)));
                ys = max(1, min(H-n+1, p(2)));
                box = I(ys:ys+n-1, xs:xs+n-1, :);

                outDir = app.FldOutFolder.Value;
                if ~exist(outDir, 'dir'), mkdir(outDir); end
                imgPath = fullfile(outDir, [app.baseName() '_aggbox_' ...
                    char(datetime('now','Format','HHmmss')) '.png']);
                imwrite(box, imgPath);
                app.log(['Saved aggregate ROI -> ' imgPath]);

                % Calibration: ImgHandle is the displayed (cropped+resized) frame,
                % so mm/px = 1/(px2mm * resize).  *** If you ran this on a RAW
                % (full-resolution) preview instead, the true mm/px = 1/px2mm. ***
                mmPerPx = 1 / (app.FldPx2mm.Value * app.FldResize.Value);
                app.log(sprintf('Assuming displayed-frame calibration: mmPerPx = %.6g (= 1/(px2mm*resize))', mmPerPx), 'warn');

                res = agg_vol_calc(imgPath, mmPerPx, ...
                    'Axis', app.DdAggAxis.Value, 'ShowPlots', true);

                app.LblAggResult.Text = sprintf('V = %.4g mm^3  (asym %.0f%%)', ...
                    res.volume_mm3, 100*res.asymmetry);
                app.log(sprintf(['Aggregate volume = %.4g mm^3 | height %.3f mm | maxR %.3f mm | ' ...
                    'asymmetry %.1f%% | area %d px'], res.volume_mm3, res.height_mm, ...
                    res.maxRadius_mm, 100*res.asymmetry, res.area_px), 'ok');
                if res.asymmetry > 0.15
                    app.log('High asymmetry — the axisymmetric assumption is weak here; treat the volume as approximate.', 'warn');
                end
            catch ME
                app.setStatus(['Aggregate volume error: ' ME.message], 'error');
            end
        end

        % ════════════════════════════════════════════════════════════════════
        %  VIDEO LOAD
        % ════════════════════════════════════════════════════════════════════
        function loadVideoFcn(app)
            [f, p] = uigetfile( ...
                {'*.mp4;*.avi;*.mov;*.mkv;*.mj2', 'Video Files (*.mp4,*.avi,*.mov,*.mkv,*.mj2)'}, ...
                'Select Input Video');
            if isequal(f, 0), return; end

            newFile = fullfile(p, f);

            % Different video → invalidate cache and cancel any active preview
            if ~strcmp(newFile, app.VideoFile)
                app.cancelCropPreview();
                app.clearCacheData();
                app.resetSession();        % clean slate so files don't bleed together
                app.cancelCalibration(false);
                app.CalibWpx = NaN; app.CalibRow = NaN;
                app.CalibSource = sprintf('carried over (%.2f px/mm), NOT calibrated for this video', ...
                    app.FldPx2mm.Value);
                app.updateCalibLabel();
            end

            app.VideoFile = newFile;
            app.LblVideoPath.Text = f;

            try
                if ~isempty(app.VidReader)
                    delete(app.VidReader);
                end
                app.VidReader      = VideoReader(newFile);
                app.VideoDuration  = app.VidReader.Duration;
                app.VideoFPS       = app.VidReader.FrameRate;

                % Timeline slider range (guarded: don't fire seekTo during load)
                app.SnapGuard = true;
                app.SliderTimeline.Limits = [0, app.VideoDuration];
                app.SliderTimeline.Value  = 0;
                app.SnapGuard = false;
                app.TStart = 0;
                app.TEnd   = app.VideoDuration;   % default = full clip, not 5 s
                app.CurrentDisplayTime = 0;
                app.updateTStartEndLabels();

                % Show first frame
                app.VidReader.CurrentTime = 0;
                app.displayVideoFrame(readFrame(app.VidReader));

                app.setState('VIDEO_LOADED');
                app.setStatus(sprintf('Loaded — Duration: %.1f s  |  FPS: %.0f', ...
                    app.VideoDuration, app.VideoFPS), 'ok');
                app.updateTimeLabel(0);

            catch ME
                uialert(app.UIFigure, ME.message, 'Video Load Error');
                app.setStatus(['Load error: ' ME.message], 'error');
            end
        end

        % ── Display a raw (uncropped) frame in VideoAxes ──────────────────
        function displayVideoFrame(app, frame)
            if isempty(frame), return; end
            axes(app.VideoAxes);
            if isempty(app.ImgHandle) || ~isvalid(app.ImgHandle)
                cla(app.VideoAxes);
                app.ImgHandle = imshow(frame, 'Parent', app.VideoAxes);
            else
                app.ImgHandle.CData = frame;
            end
            % Always sync limits to current frame size — critical when switching
            % between full-resolution preview and cropped+resized cached frames
            app.VideoAxes.XLim = [0.5, size(frame,2) + 0.5];
            app.VideoAxes.YLim = [0.5, size(frame,1) + 0.5];
            % Raw preview has no consistent mm calibration — hide ruler/scale bar
            app.VideoAxes.XColor = 'none'; app.VideoAxes.YColor = 'none';
            app.VideoAxes.XTick = []; app.VideoAxes.YTick = [];
            xlabel(app.VideoAxes, ''); ylabel(app.VideoAxes, '');
            app.VideoAxes.Visible = 'off';   % decorations off (image still renders)
            if ~isempty(app.hScaleBar) && isvalid(app.hScaleBar)
                app.hScaleBar.XData = NaN; app.hScaleBar.YData = NaN;
                app.hScaleTxt.String = '';
            end
        end

        % ── Display a cached (cropped+resized) frame ──────────────────────
        function displayCachedFrame(app, idx)
            if ~app.CacheValid || idx < 1 || idx > app.NCachedFrames, return; end
            delete(findobj(app.VideoAxes, 'Tag', 'CalibMark'));   % calibration marks live in full-frame px
            frame = app.FrameCache{idx};
            axes(app.VideoAxes);
            if isempty(app.ImgHandle) || ~isvalid(app.ImgHandle)
                cla(app.VideoAxes);
                app.ImgHandle = imshow(frame, 'Parent', app.VideoAxes);
            else
                app.ImgHandle.CData = frame;
            end
            % Always sync axes limits — cached frames are smaller than raw video
            app.VideoAxes.XLim = [0.5, size(frame,2) + 0.5];
            app.VideoAxes.YLim = [0.5, size(frame,1) + 0.5];
            app.applyPixelRuler();
            app.placeScaleBar();
        end

        % ════════════════════════════════════════════════════════════════════
        %  CACHE SYSTEM
        % ════════════════════════════════════════════════════════════════════
        function key = buildCacheKey(app)
            key = sprintf('%s_t%.3f_%.3f_cx%d_cy%d_cw%d_ch%d_r%.3f_k%d_crit%d_kf%d_tc%.3f_%.3f', ...
                app.VideoFile, app.TStart, app.TEnd, ...
                app.FldCropX.Value, app.FldCropY.Value, ...
                app.FldCropW.Value, app.FldCropH.Value, ...
                app.FldResize.Value, app.FldKval.Value, ...
                app.ChkCritEnable.Value, app.FldCritKval.Value, ...
                app.TCritStart, app.TCritEnd);
        end

        function cacheFramesFcn(app)
            newKey = app.buildCacheKey();

            % Already cached with same params → skip
            if app.CacheValid && strcmp(newKey, app.CacheKeyStr)
                app.setStatus(sprintf('Cache valid — %d frames ready.', app.NCachedFrames), 'ok');
                app.setState('CACHED');
                return;
            end

            % Invalidate old cache
            app.clearCacheData();

            % Read params
            cropRect = [app.FldCropX.Value, app.FldCropY.Value, ...
                        app.FldCropW.Value, app.FldCropH.Value];
            rsz      = app.FldResize.Value;
            kv       = app.FldKval.Value;
            t0       = app.TStart;
            t1       = app.TEnd;

            % Variable-kval: dense sampling inside the critical time window
            useCrit  = app.ChkCritEnable.Value;
            kvFine   = max(1, app.FldCritKval.Value);
            tc0      = min(app.TCritStart, app.TCritEnd);
            tc1      = max(app.TCritStart, app.TCritEnd);
            critOK   = useCrit && (tc1 > tc0);
            if useCrit && ~critOK
                app.log('Critical region enabled but window is empty — using uniform kval.', 'warn');
            end

            app.setStatus('Caching frames — please wait...', 'warn');

            try
                vr = VideoReader(app.VideoFile);
                vr.CurrentTime = max(0, t0);

                frames    = {};
                grays     = {};
                stamps    = [];
                nextKeep  = t0;
                fIdx      = 0;

                d = uiprogressdlg(app.UIFigure, ...
                    'Title',      'Caching Frames', ...
                    'Message',    'Reading video...', ...
                    'Cancelable', 'on', ...
                    'Value',      0);

                while hasFrame(vr) && vr.CurrentTime <= t1 + 1/vr.FrameRate
                    if d.CancelRequested, break; end

                    raw  = readFrame(vr);
                    tNow = vr.CurrentTime;

                    % Skip frames below the next keep timestamp
                    if tNow < nextKeep - 1/(2*vr.FrameRate), continue; end
                    % Dense (fine kval) inside the critical window, normal kval outside
                    if critOK && tNow >= tc0 && tNow <= tc1
                        frameStep = kvFine / vr.FrameRate;
                    else
                        frameStep = kv / vr.FrameRate;
                    end
                    nextKeep = tNow + frameStep;

                    fIdx = fIdx + 1;

                    % Crop (with bounds checking)
                    [H, W, ~] = size(raw);
                    cx = max(1, round(cropRect(1)));
                    cy = max(1, round(cropRect(2)));
                    cw = min(round(cropRect(3)), W - cx + 1);
                    ch = min(round(cropRect(4)), H - cy + 1);
                    if cw <= 0 || ch <= 0, continue; end
                    cropped = raw(cy:cy+ch-1, cx:cx+cw-1, :);

                    % Resize
                    resized = imresize(cropped, rsz);
                    gray    = im2gray(resized);

                    frames{end+1} = resized; %#ok<AGROW>
                    grays{end+1}  = gray;     %#ok<AGROW>
                    stamps(end+1) = tNow;     %#ok<AGROW>

                    pct = (tNow - t0) / max(t1 - t0, 0.001);
                    d.Value   = min(pct, 1);
                    d.Message = sprintf('Frame %d  |  t = %.2f s', fIdx, tNow);
                end

                close(d);

                app.FrameCache      = frames;
                app.GrayCache       = grays;
                app.FrameTimestamps = stamps;
                app.NCachedFrames   = fIdx;
                app.CacheKeyStr     = newKey;
                app.CacheValid      = true;

                % Constrain slider to the cached range so the seek bar length
                % matches exactly the cached footage — no seeking into uncached
                % territory (Issue #4 fix).
                if fIdx > 0
                    app.SnapGuard = true;
                    app.SliderTimeline.Limits = [stamps(1), stamps(end)];
                    app.SliderTimeline.Value  = stamps(1);
                    app.SnapGuard = false;
                    app.CurrentDisplayTime    = stamps(1);
                end

                app.setState('CACHED');
                app.setStatus(sprintf('Cached %d frames  |  t = %.2f → %.2f s', ...
                    fIdx, t0, t1), 'ok');
                if critOK
                    nDense = sum(stamps >= tc0 & stamps <= tc1);
                    app.log(sprintf('Dense region kval=%d over t=%.2f–%.2f s: %d frames at fine rate.', ...
                        kvFine, tc0, tc1, nDense), 'info');
                end

                % Preview first cached frame
                if fIdx > 0, app.displayCachedFrame(1); end

            catch ME
                app.setStatus(['Cache error: ' ME.message], 'error');
            end
        end

        function clearCacheData(app)
            app.FrameCache      = {};
            app.GrayCache       = {};
            app.FrameTimestamps = [];
            app.NCachedFrames   = 0;
            app.CacheValid      = false;
            app.CacheKeyStr     = '';
        end

        function resetAxesOverlays(app)
            % Remove every overlay graphic on the video axes (trajectories,
            % markers, circles, annotation boxes, pick markers, scale bar),
            % leaving only the image, then null the stored handles so they are
            % cleanly recreated on the next run. Fixes marks persisting after
            % Clear Cache / a new run.
            if isempty(app.VideoAxes) || ~isvalid(app.VideoAxes), return; end
            img = app.ImgHandle;
            hasImg = ~isempty(img) && isvalid(img);
            kids = allchild(app.VideoAxes);
            for k = 1:numel(kids)
                if ~(hasImg && kids(k) == img)
                    delete(kids(k));
                end
            end
            [app.hCenterLine, app.hCenterPt, app.hCenterCirc] = deal([]);
            [app.hP1Line, app.hP1Pt, app.hP2Line, app.hP2Pt]  = deal([]);
            [app.hAnnCenter, app.hAnnP1, app.hAnnP2]           = deal([]);
            [app.hScaleBar, app.hScaleTxt]                     = deal([]);
            [app.hPickP1, app.hPickP2]                         = deal([]);
            [app.hPickP2b, app.hPickP2c]                       = deal([]);
            % Datum ROI is deleted by the allchild loop above; drop stale
            % handles + listener (a listener is not an axes child).
            if ~isempty(app.hDatumListener), delete(app.hDatumListener); app.hDatumListener = []; end
            app.hDatum = [];
            if ~isempty(app.LblDatum) && isvalid(app.LblDatum)
                app.LblDatum.Text = 'datum: —'; app.LblDatum.Visible = 'off';
            end
        end

        function resetSession(app)
            % Full return-to-clean-state, used when loading a new file, clearing
            % the cache, or recovering from an error — so several files can be
            % analysed in one session without restarting TrakLab.
            app.StopRequested = false;
            app.PickMode = '';
            app.CoordsMode = false; app.DatumMode = false;
            if ~isempty(app.BtnCoords) && isvalid(app.BtnCoords), app.highlightPickBtn(app.BtnCoords, false); end
            if ~isempty(app.BtnDatum)  && isvalid(app.BtnDatum),  app.highlightPickBtn(app.BtnDatum, false); end
            if ~isempty(app.ImgHandle) && isvalid(app.ImgHandle)
                app.ImgHandle.ButtonDownFcn = '';
            end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                app.UIFigure.KeyPressFcn = '';
            end
            app.resetAxesOverlays();
            % Drop stored results from any previous run
            app.CenterTraj = []; app.CenterTraj_mm = [];
            app.P1Traj = []; app.P1Traj_mm = []; app.P2Traj = []; app.P2Traj_mm = [];
            app.VelCz = []; app.VelCx = []; app.VelP1x = []; app.VelP1y = [];
            app.VelP2x = []; app.VelP2y = [];
            app.CenterFound = []; app.P1Valid = []; app.P2Valid = []; app.CenterRadius = [];
            app.RealTime = []; app.N_proc = 0;
            if ~isempty(app.LblAggResult) && isvalid(app.LblAggResult)
                app.LblAggResult.Text = 'volume: —';
            end
        end

        function clearCacheFcn(app)
            app.clearCacheData();
            app.resetSession();        % also clear marks, results, and pick state
            % Restore slider to full video range (cache was constraining it)
            if app.VideoDuration > 0
                app.SnapGuard = true;
                app.SliderTimeline.Limits = [0, app.VideoDuration];
                app.SliderTimeline.Value  = app.CurrentDisplayTime;
                app.SnapGuard = false;
            end
            if ~isempty(app.VideoFile)
                app.setState('VIDEO_LOADED');
            else
                app.setState('IDLE');
            end
            app.setStatus('Cache cleared and view reset.', 'idle');
        end

        % ════════════════════════════════════════════════════════════════════
        %  VIDEO PLAYBACK (timer-based)
        % ════════════════════════════════════════════════════════════════════
        function togglePlay(app)
            if app.IsPlaying
                app.pauseVideo();
            else
                app.playVideo();
            end
        end

        function playVideo(app)
            if isempty(app.VidReader), return; end

            % If display time is at or past TEnd, restart from TStart
            if app.CurrentDisplayTime >= app.TEnd
                app.CurrentDisplayTime = app.TStart;
            end

            % Sync VideoReader to where we are currently displaying.
            % CurrentDisplayTime is always accurate; VidReader.CurrentTime may
            % have drifted due to keyframe snapping during earlier seeks.
            try
                app.VidReader.CurrentTime = max(0, app.CurrentDisplayTime - 1/app.VideoFPS);
            catch; end

            app.IsPlaying = true;
            app.BtnPlayPause.Text = '⏸';
            app.BtnPlayPause.BackgroundColor = [0.18 0.22 0.28];

            app.PlayTimer = timer( ...
                'ExecutionMode', 'fixedRate', ...
                'Period',        max(0.01, round(1000/app.VideoFPS)/1000), ...
                'TimerFcn',      @(~,~) app.playbackTick());
            start(app.PlayTimer);
        end

        function pauseVideo(app)
            app.IsPlaying = false;
            app.BtnPlayPause.Text = '▶';
            app.BtnPlayPause.BackgroundColor = app.ColCenter;
            if ~isempty(app.PlayTimer) && isvalid(app.PlayTimer)
                stop(app.PlayTimer);
                delete(app.PlayTimer);
            end
        end

        function playbackTick(app)
            if ~app.IsPlaying || isempty(app.VidReader), return; end

            % Never fight the user while they are dragging the slider
            if app.IsDragging, return; end

            try
                t = app.VidReader.CurrentTime;
                if hasFrame(app.VidReader) && t <= app.TEnd
                    frame = readFrame(app.VidReader);
                    app.displayVideoFrame(frame);
                    t = app.VidReader.CurrentTime;

                    % Update authoritative time & slider (safe: not dragging)
                    app.CurrentDisplayTime  = t;
                    app.snapSliderTo(t);
                    app.updateTimeLabel(t);
                    if app.CacheValid && app.NCachedFrames > 0
                        [~, pidx] = min(abs(app.FrameTimestamps - t));
                        app.updateSeekReadout(t, pidx);
                    else
                        app.updateSeekReadout(t, []);
                    end
                else
                    app.pauseVideo();
                end
            catch
                app.pauseVideo();
            end
        end

        % ── Seek ──────────────────────────────────────────────────────────
        function seekTo(app, t)
            if isempty(app.VidReader), return; end
            t = max(app.SliderTimeline.Limits(1), ...
                min(t, app.SliderTimeline.Limits(2)));

            if app.CacheValid && app.NCachedFrames > 0
                % Fast path: snap to the nearest cached frame ---------------
                [~, idx] = min(abs(app.FrameTimestamps - t));
                tFrame = app.FrameTimestamps(idx);      % real frame timestamp
                app.CurrentDisplayTime = tFrame;        % authoritative = frame time
                app.displayCachedFrame(idx);
                try
                    app.VidReader.CurrentTime = max(0, tFrame - 1/app.VideoFPS);
                catch; end
                app.snapSliderTo(tFrame);               % guarded write-back
                app.updateTimeLabel(tFrame);
                app.updateSeekReadout(tFrame, idx);
            else
                % Slow path: no cache — seek in VideoReader, snap to grabbed frame
                app.CurrentDisplayTime = t;
                try
                    app.VidReader.CurrentTime = max(0, t - 0.001);
                    if hasFrame(app.VidReader)
                        app.displayVideoFrame(readFrame(app.VidReader));
                        t = app.VidReader.CurrentTime; % the frame actually read
                        app.CurrentDisplayTime = t;
                    end
                catch; end
                app.snapSliderTo(t);
                app.updateTimeLabel(t);
                app.updateSeekReadout(t, []);
            end
        end

        % Guarded slider write-back: setting .Value fires ValueChangedFcn,
        % which calls seekTo again. SnapGuard breaks that loop (see the
        % historical snap-back bug this replaces).
        function snapSliderTo(app, tVal)
            tVal = max(app.SliderTimeline.Limits(1), ...
                       min(tVal, app.SliderTimeline.Limits(2)));
            app.SnapGuard = true;
            try
                app.SliderTimeline.Value = tVal;
            catch; end
            app.SnapGuard = false;
        end

        function updateSeekReadout(app, t, idx)
            if isempty(app.LblSeek) || ~isvalid(app.LblSeek), return; end
            if isempty(idx)
                app.LblSeek.Text = sprintf('t = %s', app.formatTime(t));
            else
                app.LblSeek.Text = sprintf('t = %s   |   frame %d / %d', ...
                    app.formatTime(t), idx, app.NCachedFrames);
            end
        end

        function stepFrame(app, direction)
            if isempty(app.VidReader), return; end
            if app.CacheValid && app.NCachedFrames > 0
                % Index-based stepping — always lands on a real frame
                [~, idx] = min(abs(app.FrameTimestamps - app.CurrentDisplayTime));
                idx = max(1, min(app.NCachedFrames, idx + direction));
                app.seekTo(app.FrameTimestamps(idx));
            else
                dt = app.FldKval.Value / app.VideoFPS;
                app.seekTo(app.CurrentDisplayTime + direction * dt);
            end
        end

        % Called continuously while the user is dragging (ValueChangingFcn)
        function sliderChangingCb(app, event)
            if app.SnapGuard, return; end   % ignore our own write-back
            app.IsDragging = true;
            app.seekTo(event.Value);
        end

        % Called once when the user releases the slider (ValueChangedFcn)
        function sliderReleasedCb(app, event)
            if app.SnapGuard, return; end   % ignore our own write-back
            app.IsDragging = false;
            app.seekTo(event.Value);
        end

        function setTStartNow(app)
            app.TStart = app.CurrentDisplayTime;
            app.LblTStart.Text = app.formatTime(app.TStart);
            if app.CacheValid && ~strcmp(app.buildCacheKey(), app.CacheKeyStr)
                app.clearCacheFcn();
                app.setStatus('tStart changed — re-cache frames.', 'warn');
            end
        end

        function setTEndNow(app)
            app.TEnd = app.CurrentDisplayTime;
            app.LblTEnd.Text = app.formatTime(app.TEnd);
            if app.CacheValid && ~strcmp(app.buildCacheKey(), app.CacheKeyStr)
                app.clearCacheFcn();
                app.setStatus('tEnd changed — re-cache frames.', 'warn');
            end
        end

        function updateTStartEndLabels(app)
            app.LblTStart.Text = app.formatTime(app.TStart);
            app.LblTEnd.Text   = app.formatTime(app.TEnd);
        end

        function setCritStartNow(app)
            app.TCritStart = app.CurrentDisplayTime;
            app.LblCritStart.Text = app.formatTime(app.TCritStart);
            if app.CacheValid && ~strcmp(app.buildCacheKey(), app.CacheKeyStr)
                app.clearCacheFcn();
                app.setStatus('Critical-region start changed — re-cache frames.', 'warn');
            end
        end

        function setCritEndNow(app)
            app.TCritEnd = app.CurrentDisplayTime;
            app.LblCritEnd.Text = app.formatTime(app.TCritEnd);
            if app.CacheValid && ~strcmp(app.buildCacheKey(), app.CacheKeyStr)
                app.clearCacheFcn();
                app.setStatus('Critical-region end changed — re-cache frames.', 'warn');
            end
        end

        function critParamChanged(app)
            % Enabling the dense region or changing fine-kval alters the cache
            % schedule, so the existing cache is stale — drop it and prompt.
            if app.CacheValid && ~strcmp(app.buildCacheKey(), app.CacheKeyStr)
                app.clearCacheFcn();
                app.setStatus('Critical-region setting changed — re-cache frames.', 'warn');
            end
        end

        function updateTimeLabel(app, t)
            app.LblTime.Text = sprintf('%s / %s', ...
                app.formatTime(t), app.formatTime(app.VideoDuration));
        end

        % ════════════════════════════════════════════════════════════════════
        %  ZOOM TOGGLE
        % ════════════════════════════════════════════════════════════════════
        function toggleZoom(app)
            interactions = app.VideoAxes.Interactions;
            if isempty(interactions)
                app.VideoAxes.Interactions = zoomInteraction;
                app.BtnZoom.BackgroundColor = app.ColP1;
                app.BtnZoom.FontColor = [1 1 1];
            else
                app.VideoAxes.Interactions = [];
                app.BtnZoom.BackgroundColor = [0.18 0.22 0.28];
                app.BtnZoom.FontColor = [0.75 0.75 0.75];
            end
        end

        % ════════════════════════════════════════════════════════════════════
        %  px/mm CALIBRATION FROM THE CUVETTE OUTER WIDTH  (v0.4)
        % ════════════════════════════════════════════════════════════════════
        %  s [px/mm] = W_px / W0, with W_px the outer-to-outer cuvette width
        %  measured on the FULL-RESOLUTION frame (same definition as the CT
        %  volumetry, cuvette_scale.csv).  Positions in mm = px / (s * resize).

        function toggleCalibration(app)
            if app.CalibMode
                app.cancelCalibration(true);
                app.setStatus('Calibration cancelled.', 'idle');
                return;
            end
            if isempty(app.VideoFile) || isempty(app.VidReader)
                app.setStatus('Load a video first.', 'warn'); return;
            end
            if app.IsPlaying, app.pauseVideo(); end
            if app.InCropPreview, app.confirmCropPreview(); end
            app.releaseAxesModes('calib');
            app.freezeDatum(true);

            % Full-resolution frame at the current time: the cuvette walls are
            % normally OUTSIDE the tracking crop, so never calibrate on the cache.
            try
                app.VidReader.CurrentTime = max(0, app.CurrentDisplayTime - 1/app.VideoFPS);
                if ~hasFrame(app.VidReader), app.VidReader.CurrentTime = 0; end
                frame = readFrame(app.VidReader);
            catch ME
                app.setStatus(['Calibration: could not read frame — ' ME.message], 'error'); return;
            end
            app.CalibFrame = frame;
            app.displayVideoFrame(frame);
            app.CalibPts = zeros(0,2);
            delete(findobj(app.VideoAxes, 'Tag', 'CalibMark'));
            app.CalibMode = true;
            app.highlightPickBtn(app.BtnCalib, true);
            app.VideoAxes.Interactions = [];
            if ~isempty(app.ImgHandle) && isvalid(app.ImgHandle)
                app.ImgHandle.ButtonDownFcn = @(~,evt) app.calibClickCb(evt);
            end
            app.UIFigure.KeyPressFcn = @(~,evt) app.calibKey(evt);
            app.setStatus(['CALIBRATE: click the OUTER edge of the LEFT cuvette wall, then the RIGHT wall, ' ...
                'at the height of the drop (each click snaps to the outermost wall edge nearby). Esc cancels.'], 'warn');
        end

        function calibKey(app, evt)
            if strcmp(evt.Key, 'escape') && app.CalibMode
                app.cancelCalibration(true);
                app.setStatus('Calibration cancelled.', 'idle');
            end
        end

        function calibClickCb(app, event)
            if ~app.CalibMode, return; end
            pos = event.IntersectionPoint(1:2);
            [xs, ys] = app.snapWallEdge(pos(1), pos(2));
            app.CalibPts(end+1,:) = [xs ys];
            hold(app.VideoAxes, 'on');
            c = [1.0 0.85 0.45];
            plot(app.VideoAxes, [xs xs], ys + [-60 60], '-', 'Color', c, 'LineWidth', 1.5, ...
                'Tag', 'CalibMark', 'PickableParts', 'none');
            plot(app.VideoAxes, pos(1), pos(2), '+', 'Color', [1 0.4 0.4], 'MarkerSize', 10, ...
                'Tag', 'CalibMark', 'PickableParts', 'none');
            hold(app.VideoAxes, 'off');
            app.log(sprintf('Calibration click %d: clicked x=%.1f, snapped x=%.2f (row %.0f)', ...
                size(app.CalibPts,1), pos(1), xs, ys));
            if size(app.CalibPts,1) < 2
                app.setStatus('CALIBRATE: now click the OUTER edge of the RIGHT cuvette wall.', 'warn');
                return;
            end
            app.finishCalibration();
        end

        function [xs, ys] = snapWallEdge(app, x, y)
            % Snap a click to the OUTER cuvette-wall edge: gradient of a 41-row
            % averaged intensity profile, searched 30 px outward / 10 px inward
            % of the click; the outermost local gradient peak >= 25 % of the
            % window maximum wins ("first edge from the background inward",
            % as in the volumetry cuvette_scale), refined to sub-pixel.
            % Tested on CT_Sep2026 run 05: W = 1590.8 px vs 1591.6 px (0.05 %).
            xs = x; ys = y;
            F = app.CalibFrame;
            if isempty(F), return; end
            g = double(im2gray(F));
            [H, W] = size(g);
            r0 = max(1, round(y) - 20); r1 = min(H, round(y) + 20);
            prof = mean(g(r0:r1, :), 1);
            prof = conv(prof, ones(1,3)/3, 'same');
            d = abs(gradient(prof));
            outward = sign(x - W/2); if outward == 0, outward = 1; end
            if outward < 0
                c0 = round(x) - 30; c1 = round(x) + 10;      % left wall: search mostly leftward
            else
                c0 = round(x) - 10; c1 = round(x) + 30;      % right wall: search mostly rightward
            end
            c0 = max(2, c0); c1 = min(W - 1, c1);
            thr = 0.25 * max(d(c0:c1));
            ks = c0:c1;
            isPk = d(ks) >= thr & d(ks) >= d(ks-1) & d(ks) >= d(ks+1);
            pk = ks(isPk);
            if isempty(pk), ys = (r0 + r1)/2; return; end
            if outward < 0, k = min(pk); else, k = max(pk); end
            den = d(k-1) - 2*d(k) + d(k+1);
            dx = 0; if den ~= 0, dx = 0.5*(d(k-1) - d(k+1))/den; end
            xs = k + max(-0.5, min(0.5, dx));
            ys = (r0 + r1)/2;
        end

        function finishCalibration(app)
            P = app.CalibPts;
            Wpx = abs(P(2,1) - P(1,1));
            row = mean(P(:,2));
            W0  = app.FldCuvMM.Value;
            if abs(P(2,2) - P(1,2)) > 40
                app.log('Calibration: the two clicks are > 40 rows apart; width measured at their mean row.', 'warn');
            end
            if Wpx < 50
                app.cancelCalibration(true);
                app.setStatus('Calibration failed: walls too close together (< 50 px). Try again.', 'error');
                return;
            end
            s = Wpx / W0;
            app.CalibWpx = Wpx; app.CalibRow = row;
            app.CalibSource = sprintf('cuvette: W = %.2f px at row %.0f / W0 = %g mm', Wpx, row, W0);
            app.FldPx2mm.Value = s;
            app.log(sprintf('px/mm calibrated: %.2f px / %g mm = %.3f px/mm (full res, row %.0f).', ...
                Wpx, W0, s, row), 'ok');
            if s < 110 || s > 160
                app.log(sprintf(['px/mm = %.1f is outside the CT range seen so far (≈128–141). ' ...
                    'Check that both clicks were on the OUTER wall edges.'], s), 'warn');
            end
            app.cancelCalibration(false);
            app.updateCalibLabel();
            app.setStatus(sprintf('px/mm = %.3f (cuvette %.1f px / %g mm). Markers clear when you move the timeline.', ...
                s, Wpx, W0), 'ok');
        end

        function cancelCalibration(app, restoreView)
            if nargin < 2, restoreView = true; end
            wasActive = app.CalibMode;
            app.CalibMode = false;
            if ~isempty(app.BtnCalib) && isvalid(app.BtnCalib)
                app.highlightPickBtn(app.BtnCalib, false);
            end
            if ~isempty(app.ImgHandle) && isvalid(app.ImgHandle) && wasActive
                app.ImgHandle.ButtonDownFcn = '';
            end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure) && wasActive
                app.UIFigure.KeyPressFcn = '';
            end
            if restoreView
                delete(findobj(app.VideoAxes, 'Tag', 'CalibMark'));
                if app.CacheValid && app.NCachedFrames > 0
                    [~, idx] = min(abs(app.FrameTimestamps - app.CurrentDisplayTime));
                    app.displayCachedFrame(idx);
                end
            end
        end

        function px2mmEdited(app)
            app.CalibWpx = NaN; app.CalibRow = NaN;
            app.CalibSource = sprintf('manual entry (%.3f px/mm)', app.FldPx2mm.Value);
            app.updateCalibLabel();
            app.placeScaleBar();
        end

        function cuvetteMMEdited(app)
            % Keep the measured pixel width; only the physical width changed.
            if ~isnan(app.CalibWpx)
                W0 = app.FldCuvMM.Value;
                app.FldPx2mm.Value = app.CalibWpx / W0;
                app.CalibSource = sprintf('cuvette: W = %.2f px at row %.0f / W0 = %g mm', ...
                    app.CalibWpx, app.CalibRow, W0);
                app.log(sprintf('W0 changed to %g mm → px/mm = %.3f', W0, app.FldPx2mm.Value), 'info');
                app.placeScaleBar();
            end
            app.updateCalibLabel();
        end

        function updateCalibLabel(app)
            if isempty(app.LblCalib) || ~isvalid(app.LblCalib), return; end
            if ~isnan(app.CalibWpx)
                app.LblCalib.Text = sprintf('cal: %.1f px / %g mm', app.CalibWpx, app.FldCuvMM.Value);
                app.LblCalib.FontColor = [0.45 0.85 0.45];
            elseif startsWith(app.CalibSource, 'manual')
                app.LblCalib.Text = 'scale: manual entry';
                app.LblCalib.FontColor = [0.85 0.85 0.55];
            else
                app.LblCalib.Text = 'scale: NOT calibrated';
                app.LblCalib.FontColor = [0.95 0.65 0.20];
            end
        end

        % ════════════════════════════════════════════════════════════════════
        %  COORDS READOUT  +  DRAGGABLE DATUM  (viewspace only)
        % ════════════════════════════════════════════════════════════════════

        % Cancel any pick mode and turn zoom off — shared entry guard so the
        % three axes-click modes never fight over ButtonDownFcn / Interactions.
        function releaseAxesModes(app, keep)
            if nargin < 2, keep = ''; end
            if ~strcmp(keep,'calib') && app.CalibMode
                app.cancelCalibration(true);
            end
            if ~isempty(app.PickMode)
                app.PickMode = '';
                if ~isempty(app.ImgHandle) && isvalid(app.ImgHandle)
                    app.ImgHandle.ButtonDownFcn = '';
                end
            end
            app.VideoAxes.Interactions = [];
            if ~isempty(app.BtnZoom) && isvalid(app.BtnZoom)
                app.BtnZoom.BackgroundColor = [0.18 0.22 0.28];
                app.BtnZoom.FontColor = [0.75 0.75 0.75];
            end
            if ~strcmp(keep,'coords') && app.CoordsMode
                app.CoordsMode = false;
                app.highlightPickBtn(app.BtnCoords, false);
            end
            if ~strcmp(keep,'datum') && app.DatumMode
                app.DatumMode = false;
                app.highlightPickBtn(app.BtnDatum, false);
            end
            app.updateStateUI();
        end

        function toggleCoordsMode(app)
            if ~app.CacheValid || app.NCachedFrames == 0
                app.setStatus('Cache frames first to read coordinates.', 'warn'); return;
            end
            if app.CoordsMode                       % toggle off
                app.CoordsMode = false;
                if ~isempty(app.ImgHandle) && isvalid(app.ImgHandle)
                    app.ImgHandle.ButtonDownFcn = '';
                end
                delete(findobj(app.VideoAxes, 'Tag', 'CoordMark'));
                app.highlightPickBtn(app.BtnCoords, false);
                app.setStatus('Coords readout off.', 'idle');
                return;
            end
            app.releaseAxesModes('coords');         % cancel siblings, take over
            app.freezeDatum(true);                  % don't let datum eat clicks
            app.CoordsMode = true;
            app.highlightPickBtn(app.BtnCoords, true);
            app.VideoAxes.Interactions = [];
            if ~isempty(app.ImgHandle) && isvalid(app.ImgHandle)
                app.ImgHandle.ButtonDownFcn = @(~,evt) app.coordsClickCb(evt);
            end
            app.setStatus('COORDS: click the image to read x,y (px & mm). Toggle off when done.', 'warn');
        end

        function coordsClickCb(app, event)
            if ~app.CoordsMode, return; end
            pos = event.IntersectionPoint(1:2);
            cx = round(pos(1));  cy = round(pos(2));           % display px
            rsz = app.FldResize.Value;
            ox = round(cx / rsz + app.FldCropX.Value);         % original px
            oy = round(cy / rsz + app.FldCropY.Value);
            mmPerPx = 1 / (app.FldPx2mm.Value * rsz);          % matches mmPerPx elsewhere
            xmm = cx * mmPerPx;  ymm = cy * mmPerPx;           % mm from display-space origin
            app.drawCoordMarker(cx, cy, xmm, ymm);             % visible mark at the click
            app.setStatus(sprintf( ...
                'disp(%d,%d)px  |  orig(%d,%d)px  |  (%.3f, %.3f) mm', ...
                cx, cy, ox, oy, xmm, ymm), 'ok');
        end

        function drawCoordMarker(app, cx, cy, xmm, ymm)
            % Each click replaces the previous coord marker. Tagged 'CoordMark'
            % so resetAxesOverlays' allchild loop wipes it on cache-clear.
            delete(findobj(app.VideoAxes, 'Tag', 'CoordMark'));
            hold(app.VideoAxes, 'on');
            c = [0.20 0.90 1.00];   % cyan — distinct from P1/P2/datum
            plot(app.VideoAxes, cx, cy, 'o', 'Color', c, 'MarkerSize', 10, ...
                'LineWidth', 1.5, 'Tag', 'CoordMark', 'PickableParts','none');
            plot(app.VideoAxes, [cx-14 cx+14], [cy cy], '-', 'Color', c, ...
                'LineWidth', 1, 'Tag', 'CoordMark', 'PickableParts','none');
            plot(app.VideoAxes, [cx cx], [cy-14 cy+14], '-', 'Color', c, ...
                'LineWidth', 1, 'Tag', 'CoordMark', 'PickableParts','none');
            text(app.VideoAxes, cx+12, cy-8, ...
                sprintf('(%.2f, %.2f) mm', xmm, ymm), ...
                'Color', c, 'FontName','Courier New', 'FontSize', 8, ...
                'FontWeight','bold', 'Tag','CoordMark', 'PickableParts','none');
            hold(app.VideoAxes, 'off');
        end

        function toggleDatumMode(app)
            if ~app.CacheValid || app.NCachedFrames == 0
                app.setStatus('Cache frames first to place a datum.', 'warn'); return;
            end
            if app.DatumMode                        % toggle off = lock placement
                app.DatumMode = false;
                if ~isempty(app.ImgHandle) && isvalid(app.ImgHandle)
                    app.ImgHandle.ButtonDownFcn = '';
                end
                app.highlightPickBtn(app.BtnDatum, false);
                app.setStatus('Datum locked (still draggable). Toggle to re-enable placement.', 'idle');
                return;
            end
            app.releaseAxesModes('datum');
            app.DatumMode = true;
            app.highlightPickBtn(app.BtnDatum, true);
            app.VideoAxes.Interactions = [];
            if ~isempty(app.ImgHandle) && isvalid(app.ImgHandle)
                app.ImgHandle.ButtonDownFcn = @(~,evt) app.placeDatumCb(evt);
            end
            app.setStatus('DATUM: click to set the y=0 line. Drag it after. Toggle off to lock.', 'warn');
        end

        function placeDatumCb(app, event)
            if ~app.DatumMode, return; end
            y = event.IntersectionPoint(2);
            if isempty(app.ImgHandle) || ~isvalid(app.ImgHandle), return; end
            W = size(app.ImgHandle.CData, 2);

            app.clearDatum();                        % remove any prior datum + listener

            app.hDatum = drawline(app.VideoAxes, ...
                'Position', [0.5 y; W+0.5 y], ...
                'Color', [1.0 0.85 0.10], 'LineWidth', 1.0, ...
                'Label', 'y=0', 'InteractionsAllowed', 'all');

            app.hDatumListener = addlistener(app.hDatum, 'MovingROI', ...
                @(src,evt) app.constrainDatumHorizontal(src, evt));

            app.updateDatumLabel(y);
            app.LblDatum.Visible = 'on';
            app.setStatus('Datum placed — drag to adjust. Toggle Datum off to lock.', 'ok');
        end

        function constrainDatumHorizontal(app, src, evt)
            % Force both endpoints to one y and keep the line spanning the frame.
            p = evt.CurrentPosition;                 % 2×2 [x y; x y]
            y = mean(p(:,2));
            if isempty(app.ImgHandle) || ~isvalid(app.ImgHandle), return; end
            W = size(app.ImgHandle.CData, 2);
            src.Position = [0.5 y; W+0.5 y];
            app.updateDatumLabel(y);
        end

        function updateDatumLabel(app, yDisp)
            rsz = app.FldResize.Value;
            oy  = round(yDisp / rsz + app.FldCropY.Value);        % original px
            ymm = yDisp * (1 / (app.FldPx2mm.Value * rsz));       % mm (display origin)
            if ~isempty(app.LblDatum) && isvalid(app.LblDatum)
                app.LblDatum.Text = sprintf('datum y: %d px | %.3f mm', oy, ymm);
            end
        end

        % Freeze/unfreeze datum interactivity so it never intercepts pick clicks.
        function freezeDatum(app, frozen)
            if ~isempty(app.hDatum) && isvalid(app.hDatum)
                if frozen
                    app.hDatum.InteractionsAllowed = 'none';
                else
                    app.hDatum.InteractionsAllowed = 'all';
                end
            end
        end

        function clearDatum(app)
            if ~isempty(app.hDatumListener)
                delete(app.hDatumListener); app.hDatumListener = [];
            end
            if ~isempty(app.hDatum) && isvalid(app.hDatum)
                delete(app.hDatum);
            end
            app.hDatum = [];
            if ~isempty(app.LblDatum) && isvalid(app.LblDatum)
                app.LblDatum.Text = 'datum: —'; app.LblDatum.Visible = 'off';
            end
        end

        % ════════════════════════════════════════════════════════════════════
        %  POINT PICKING
        % ════════════════════════════════════════════════════════════════════
        function enterPickMode(app, pt)
            % Disable zoom while picking
            app.VideoAxes.Interactions = [];
            app.freezeDatum(true);   % datum must not swallow the pick click
            app.BtnZoom.BackgroundColor = [0.18 0.22 0.28];

            if strcmp(app.PickMode, pt)
                % Toggle off if already in this pick mode
                app.PickMode = '';
                app.ImgHandle.ButtonDownFcn = '';
                app.updateStateUI();
                app.setStatus('Pick mode cancelled.', 'idle');
                return;
            end

            app.PickMode = pt;
            app.updateStateUI();
            app.setStatus(sprintf( ...
                'PICK MODE: Click on the video to place %s.  Press Esc or click [Pick] again to cancel.', ...
                upper(pt)), 'warn');

            % Register click callback on the image
            if ~isempty(app.ImgHandle) && isvalid(app.ImgHandle)
                app.ImgHandle.ButtonDownFcn = @(~, evt) app.pickPointCb(evt);
            end

            % ESC key cancel
            app.UIFigure.KeyPressFcn = @(~, evt) app.escCancel(evt);
        end

        function pickPointCb(app, event)
            if isempty(app.PickMode), return; end

            % Position in axes data coords (= image pixel coords of displayed frame)
            pos = event.IntersectionPoint(1:2);
            cx  = round(pos(1));
            cy  = round(pos(2));

            % Convert displayed pixel → original video pixel space
            rsz = app.FldResize.Value;
            ox  = round(cx / rsz + app.FldCropX.Value);
            oy  = round(cy / rsz + app.FldCropY.Value);

            % Current frame index from timeline
            tCur = app.SliderTimeline.Value;
            if app.CacheValid && app.NCachedFrames > 0
                [~, fIdx] = min(abs(app.FrameTimestamps - tCur));
            else
                fIdx = 1;
            end

            switch app.PickMode
                case 'p1'
                    app.FldP1X.Value = ox; app.FldP1Y.Value = oy; app.FldP1Frame.Value = fIdx;
                    app.drawPickMarker(cx, cy, app.ColP1, 'P1');
                case 'p2'
                    app.FldP2X.Value = ox; app.FldP2Y.Value = oy; app.FldP2Frame.Value = fIdx;
                    app.drawPickMarker(cx, cy, app.ColP2, 'P2');
                case 'p2b'
                    app.FldP2bX.Value = ox; app.FldP2bY.Value = oy; app.FldP2bFrame.Value = fIdx;
                    app.drawPickMarker(cx, cy, app.ColP2, 'P2b');
                case 'p2c'
                    app.FldP2cX.Value = ox; app.FldP2cY.Value = oy; app.FldP2cFrame.Value = fIdx;
                    app.drawPickMarker(cx, cy, app.ColP2, 'P2c');
            end

            % Clear pick mode
            app.PickMode = '';
            app.ImgHandle.ButtonDownFcn = '';
            app.UIFigure.KeyPressFcn    = '';
            app.freezeDatum(false);  % re-enable datum dragging after picking
            app.updateStateUI();
            app.setStatus(sprintf('Point placed at (%d, %d) px original  |  frame %d', ...
                ox, oy, fIdx), 'ok');
        end

        function escCancel(app, event)
            if strcmp(event.Key, 'escape')
                app.PickMode = '';
                if ~isempty(app.ImgHandle) && isvalid(app.ImgHandle)
                    app.ImgHandle.ButtonDownFcn = '';
                end
                app.UIFigure.KeyPressFcn = '';
                app.freezeDatum(false);
                app.updateStateUI();
                app.setStatus('Pick mode cancelled.', 'idle');
            end
        end

        function drawPickMarker(app, cx, cy, color, lbl)
            % Remove any previous marker for this point so re-picking replaces it
            switch upper(lbl)
                case 'P1',  prev = app.hPickP1;
                case 'P2',  prev = app.hPickP2;
                case 'P2B', prev = app.hPickP2b;
                case 'P2C', prev = app.hPickP2c;
                otherwise,  prev = [];
            end
            if ~isempty(prev), delete(prev(isvalid(prev))); end
            hold(app.VideoAxes, 'on');
            h1 = plot(app.VideoAxes, cx, cy, 'o', 'Color', color, ...
                'MarkerSize', 11, 'LineWidth', 1.5, 'MarkerFaceColor', 'none');
            h2 = plot(app.VideoAxes, [cx-15 cx+15], [cy cy], '-', 'Color', color, 'LineWidth', 1);
            h3 = plot(app.VideoAxes, [cx cx],   [cy-15 cy+15], '-', 'Color', color, 'LineWidth', 1);
            h4 = text(app.VideoAxes, cx+13, cy-6, lbl, ...
                'Color', color, 'FontName', 'Courier New', 'FontSize', 9, 'FontWeight', 'bold');
            hold(app.VideoAxes, 'off');
            grp = [h1 h2 h3 h4];
            set(grp, 'PickableParts', 'none');   % never block a future re-pick click
            switch upper(lbl)
                case 'P1',  app.hPickP1  = grp;
                case 'P2',  app.hPickP2  = grp;
                case 'P2B', app.hPickP2b = grp;
                case 'P2C', app.hPickP2c = grp;
            end
        end

        % ════════════════════════════════════════════════════════════════════
        %  MAIN TRACKING LOOP
        % ════════════════════════════════════════════════════════════════════
        function runTrackingFcn(app)
            if ~app.CacheValid || app.NCachedFrames == 0
                uialert(app.UIFigure, 'Cache frames first.', 'No Cache');
                return;
            end

            if isnan(app.CalibWpx) && ~startsWith(app.CalibSource, 'manual')
                app.log(sprintf(['px/mm = %.3f is NOT calibrated for this video (%s). ' ...
                    'Positions/velocities scale as 1/(px/mm); use Calibrate (cuvette).'], ...
                    app.FldPx2mm.Value, app.CalibSource), 'warn');
            end

            % ── Gather parameters ─────────────────────────────────────────
            N      = app.NCachedFrames;
            kv     = app.FldKval.Value;
            rsz    = app.FldResize.Value;
            p2mm   = app.FldPx2mm.Value;
            dtNom  = kv / app.VideoFPS;   % nominal step (fallback only)

            % Circle
            doCirc = app.ChkCircleEnable.Value;
            cFrm0  = app.FldCircleFrame.Value;
            rRange = [app.FldCircleRMin.Value, app.FldCircleRMax.Value];
            cpol   = lower(app.DdCirclePol.Value);
            csens  = app.SldCircleSens.Value;

            % P1
            doP1    = app.ChkP1Enable.Value;
            p1Frm0  = app.FldP1Frame.Value;
            p1x0    = round((app.FldP1X.Value - app.FldCropX.Value) * rsz);
            p1y0    = round((app.FldP1Y.Value - app.FldCropY.Value) * rsz);
            p1pyr   = app.FldP1Pyr.Value;
            p1bde   = app.FldP1Bde.Value;
            p1blk   = [app.FldP1BlkH.Value, app.FldP1BlkW.Value];

            % P2
            doP2    = app.ChkP2Enable.Value;
            p2Frm0  = app.FldP2Frame.Value;
            p2x0    = round((app.FldP2X.Value - app.FldCropX.Value) * rsz);
            p2y0    = round((app.FldP2Y.Value - app.FldCropY.Value) * rsz);
            p2pyr   = app.FldP2Pyr.Value;
            p2bde   = app.FldP2Bde.Value;
            p2blk   = [app.FldP2BlkH.Value, app.FldP2BlkW.Value];

            % ── Compound P2: collect, convert, sort & validate anchors ─────
            compound = app.ChkP2Compound.Value;
            [Hd, Wd, ~] = size(app.FrameCache{1});      % displayed frame size
            mkAnc = @(X,Y,F) struct('frame', round(F), ...
                'xy', [max(1, min(Wd, round((X - app.FldCropX.Value) * rsz))), ...
                       max(1, min(Hd, round((Y - app.FldCropY.Value) * rsz)))]);
            p2Anchors = mkAnc(app.FldP2X.Value, app.FldP2Y.Value, app.FldP2Frame.Value);
            if compound
                if app.FldP2bFrame.Value >= 1
                    p2Anchors(end+1) = mkAnc(app.FldP2bX.Value, app.FldP2bY.Value, app.FldP2bFrame.Value);
                end
                if app.FldP2cFrame.Value >= 1
                    p2Anchors(end+1) = mkAnc(app.FldP2cX.Value, app.FldP2cY.Value, app.FldP2cFrame.Value);
                end
            end
            [~, ord] = sort([p2Anchors.frame]);  p2Anchors = p2Anchors(ord);
            keepA = true(1, numel(p2Anchors));  prevF = 0;
            for a = 1:numel(p2Anchors)
                f = p2Anchors(a).frame;
                if f < 1 || f > app.NCachedFrames || f <= prevF, keepA(a) = false; else, prevF = f; end
            end
            p2Anchors = p2Anchors(keepA);

            % ── State & pre-alloc ──────────────────────────────────────────
            app.setState('PROCESSING');
            app.StopRequested = false;
            app.resetAxesOverlays();   % start each run from a clean canvas (no stale marks)

            try   % recover gracefully from any error mid-run (don't strand the app)
            center_traj    = zeros(N, 2);
            center_traj_mm = zeros(N, 2);
            p1_traj        = zeros(N, 2);
            p1_traj_mm     = zeros(N, 2);
            p2_traj        = zeros(N, 2);
            p2_traj_mm     = zeros(N, 2);
            vel_cz         = zeros(N, 1);
            vel_cx         = zeros(N, 1);
            vel_p1x        = zeros(N, 1);
            vel_p1y        = zeros(N, 1);
            vel_p2x        = zeros(N, 1);
            vel_p2y        = zeros(N, 1);
            cFound         = false(N, 1);
            p1Valid        = false(N, 1);
            p2Valid        = false(N, 1);
            radius         = nan(N, 1);

            % ── Time base from actual cached-frame timestamps (ground truth) ──
            % Use the real video time recorded for each kept frame during caching,
            % NOT a synthesized constant step. Robust to variable frame rate,
            % dropped frames, and a misreported VideoFPS (e.g. 23.976 vs 24).
            tsmp = app.FrameTimestamps(:);
            if isempty(tsmp) || numel(tsmp) < N
                tsmp = (0:N-1).' * dtNom;        % fallback if stamps unavailable
            else
                tsmp = tsmp(1:N);
            end
            realtime = tsmp - tsmp(1);           % 0-based seconds

            % ── Initialize KLT trackers ────────────────────────────────────
            if doP1
                tracker1 = vision.PointTracker( ...
                    'NumPyramidLevels',    p1pyr, ...
                    'MaxBidirectionalError', p1bde, ...
                    'BlockSize',           p1blk);
            end
            if doP2
                tracker2 = vision.PointTracker( ...
                    'NumPyramidLevels',    p2pyr, ...
                    'MaxBidirectionalError', p2bde, ...
                    'BlockSize',           p2blk);
            end

            p1_init = false;
            p2_init = false;

            % ── Overlay handles ────────────────────────────────────────────
            app.initOverlayHandles();
            app.applyPixelRuler();
            app.placeScaleBar();

            % ── Compound P2 pre-pass (segment tracking computed up front) ───
            if doP2 && compound
                if isempty(p2Anchors)
                    app.log('Compound P2: no valid anchors (need frame >= 1, strictly increasing). Skipping P2.', 'warn');
                else
                    app.log(sprintf('Compound P2: tracking %d segment(s) from %d anchor(s).', ...
                        numel(p2Anchors), numel(p2Anchors)), 'info');
                    [p2_traj, p2_traj_mm, vel_p2x, vel_p2y, p2Valid] = ...
                        app.trackP2Compound(p2Anchors, N, p2mm, rsz, tsmp, dtNom, p2pyr, p2bde, p2blk);
                end
            end

            % ── Frame loop ─────────────────────────────────────────────────
            for i = 1:N
                if app.StopRequested, break; end

                gray = app.GrayCache{i};
                img  = app.FrameCache{i};

                % realtime(i) is precomputed from cached timestamps above.

                % Show frame
                app.ImgHandle.CData = img;
                hold(app.VideoAxes, 'on');

                % ── Circle detection ───────────────────────────────────────
                if doCirc && i >= cFrm0
                    [cc, cr] = imfindcircles(gray, rRange, ...
                        'ObjectPolarity', cpol, 'Sensitivity', csens);
                    if ~isempty(cc)
                        cFound(i)           = true;
                        center_traj(i,:)    = cc(1,:);
                        center_traj_mm(i,:) = cc(1,:) / (p2mm * rsz);
                        radius(i)           = cr(1);
                        if i > 1 && cFound(i-1)
                            dt = tsmp(i) - tsmp(i-1); if dt <= 0, dt = dtNom; end
                            vel_cz(i) = -(center_traj_mm(i,2) - center_traj_mm(i-1,2)) / dt;  % mm/s, z up-positive
                            vel_cx(i) =  (center_traj_mm(i,1) - center_traj_mm(i-1,1)) / dt;  % mm/s
                        end
                        % single thin outline on the currently tracked circle only
                        app.setCenterCircle(cc(1,:), cr(1));
                    else
                        app.setCenterCircle([], 0);   % nothing detected: hide outline
                        fprintf('[frame %d  t=%.3f s] droplet not detected\n', i, tsmp(i));
                    end
                end

                % ── Point 1 tracking ──────────────────────────────────────
                if doP1
                    if ~p1_init && i == p1Frm0
                        initialize(tracker1, [p1x0, p1y0], gray);
                        p1_traj(i,:)    = [p1x0, p1y0];
                        p1_traj_mm(i,:) = [p1x0, p1y0] / (p2mm * rsz);
                        p1_init = true;
                        p1Valid(i) = true;
                    elseif p1_init && i > p1Frm0
                        [pt1, v1] = step(tracker1, gray);
                        p1Valid(i) = v1;
                        if v1
                            p1_traj(i,:)    = pt1;
                            p1_traj_mm(i,:) = pt1 / (p2mm * rsz);
                            dt = tsmp(i) - tsmp(i-1); if dt <= 0, dt = dtNom; end
                            vel_p1x(i) =  (p1_traj_mm(i,1) - p1_traj_mm(i-1,1)) / dt;  % mm/s
                            vel_p1y(i) = -(p1_traj_mm(i,2) - p1_traj_mm(i-1,2)) / dt;  % mm/s, z up-positive
                        else
                            p1_traj(i,:)    = p1_traj(i-1,:);
                            p1_traj_mm(i,:) = p1_traj_mm(i-1,:);
                        end
                    end
                end

                % ── Point 2 tracking (single-anchor mode only) ────────────
                if doP2 && ~compound
                    if ~p2_init && i == p2Frm0
                        initialize(tracker2, [p2x0, p2y0], gray);
                        p2_traj(i,:)    = [p2x0, p2y0];
                        p2_traj_mm(i,:) = [p2x0, p2y0] / (p2mm * rsz);
                        p2_init = true;
                        p2Valid(i) = true;
                    elseif p2_init && i > p2Frm0
                        [pt2, v2] = step(tracker2, gray);
                        p2Valid(i) = v2;
                        if v2
                            p2_traj(i,:)    = pt2;
                            p2_traj_mm(i,:) = pt2 / (p2mm * rsz);
                            dt = tsmp(i) - tsmp(i-1); if dt <= 0, dt = dtNom; end
                            vel_p2x(i) =  (p2_traj_mm(i,1) - p2_traj_mm(i-1,1)) / dt;  % mm/s
                            vel_p2y(i) = -(p2_traj_mm(i,2) - p2_traj_mm(i-1,2)) / dt;  % mm/s, z up-positive
                        else
                            p2_traj(i,:)    = p2_traj(i-1,:);
                            p2_traj_mm(i,:) = p2_traj_mm(i-1,:);
                        end
                    end
                end

                % ── Update overlays & annotation boxes ────────────────────
                app.updateOverlays(i, center_traj, p1_traj, p2_traj, ...
                    center_traj_mm, p1_traj_mm, p2_traj_mm, vel_cz, vel_p1y, vel_p2y);

                hold(app.VideoAxes, 'off');

                % Update slider & time
                app.SnapGuard = true;
                app.SliderTimeline.Value = app.FrameTimestamps(i);
                app.SnapGuard = false;
                app.updateTimeLabel(app.FrameTimestamps(i));
                app.setStatus(sprintf('Frame %d / %d  (%.1f%%)', i, N, 100*i/N), 'warn');

                drawnow limitrate;   % keeps GUI responsive + allows Stop button
            end

            % ── Store results ──────────────────────────────────────────────
            app.RealTime       = realtime;
            app.CenterTraj     = center_traj;
            app.CenterTraj_mm  = center_traj_mm;
            app.P1Traj         = p1_traj;
            app.P1Traj_mm      = p1_traj_mm;
            app.P2Traj         = p2_traj;
            app.P2Traj_mm      = p2_traj_mm;
            app.VelCz          = vel_cz;
            app.VelCx          = vel_cx;
            app.VelP1x         = vel_p1x;
            app.VelP1y         = vel_p1y;
            app.VelP2x         = vel_p2x;
            app.VelP2y         = vel_p2y;
            app.CenterFound    = cFound;
            app.P1Valid        = p1Valid;
            app.P2Valid        = p2Valid;
            app.CenterRadius   = radius;
            app.N_proc         = N;

            app.log(sprintf('Tracking summary: %d frames | center detected %d, missed %d (%.1f%%)', ...
                N, sum(cFound), sum(~cFound), 100*sum(~cFound)/max(1,N)), 'info');

            if ~app.StopRequested
                app.setState('DONE');
                app.setStatus('Tracking complete. Exporting results...', 'ok');
                if app.ChkExportXls.Value, app.exportExcelFcn(); end
                if app.ChkExportVid.Value, app.exportVideoFcn(); end
                app.showResultPlots();
                app.setStatus('Done. Results exported.', 'ok');
            else
                app.setState('CACHED');
                app.setStatus('Processing stopped by user.', 'warn');
            end

            catch ME
                % An error mid-run would otherwise leave the app stuck in
                % PROCESSING with Stop dead. Recover to a usable state instead.
                app.log(['Tracking error: ' ME.message], 'error');
                app.setStatus(['Tracking error (recovered) - clear cache or load another video: ' ME.message], 'error');
                try, hold(app.VideoAxes, 'off'); catch, end %#ok<NOSEMI>
                app.StopRequested = false;
                if app.CacheValid
                    app.setState('CACHED');
                else
                    app.setState('VIDEO_LOADED');
                end
            end
        end

        function [p2t, p2tmm, vpx, vpy, valid] = trackP2Compound(app, anchors, N, p2mm, rsz, tsmp, dtNom, pyr, bde, blk)
            % Compound P2: hard-reset the KLT tracker at each anchor and track
            % forward to the next anchor (the last segment runs to frame N). On
            % loss of lock inside a segment, hold the last good position (causal:
            % never borrow a future anchor's position) and mark frames invalid
            % with NaN velocity. Anchor frames are forced to the user's exact points, and
            % the velocity at each re-seed (seam) frame is left NaN so the forced
            % position jump doesn't masquerade as a real velocity spike.
            p2t   = zeros(N, 2);  p2tmm = zeros(N, 2);
            vpx   = zeros(N, 1);  vpy   = zeros(N, 1);
            valid = false(N, 1);
            nA = numel(anchors);
            sc = p2mm * rsz;                 % displayed px per mm

            for s = 1:nA
                aF  = anchors(s).frame;
                aXY = anchors(s).xy;
                if s < nA, segEnd = anchors(s+1).frame - 1; else, segEnd = N; end
                if aF < 1 || aF > N, continue; end

                tr = vision.PointTracker('NumPyramidLevels', pyr, ...
                    'MaxBidirectionalError', bde, 'BlockSize', blk);
                initialize(tr, aXY, app.GrayCache{aF});

                % Anchor frame = forced seam (velocity undefined here)
                p2t(aF,:) = aXY;  p2tmm(aF,:) = aXY / sc;  valid(aF) = true;
                vpx(aF) = NaN;    vpy(aF) = NaN;

                lastXY = aXY;  lost = false;
                for i = aF+1 : segEnd
                    if ~lost
                        [pt, ok] = step(tr, app.GrayCache{i});
                        if ok
                            p2t(i,:) = pt;  valid(i) = true;
                            lastXY = pt;
                        else
                            lost = true;
                            app.log(sprintf(['Compound P2: lock lost at frame %d (segment %d). ' ...
                                'Holding last position until the next anchor — place an anchor ' ...
                                'near frame %d to re-seed.'], i, s, i), 'warn');
                        end
                    end
                    if lost
                        % Causal hold: never use a future anchor's position here.
                        % (Previously this glided toward the next anchor, so the
                        % marker moved "ahead" of the frames it was drawn on.)
                        p2t(i,:) = lastXY;
                        valid(i) = false;                                 % not a tracked sample
                    end
                    p2tmm(i,:) = p2t(i,:) / sc;
                    if valid(i) && valid(i-1)
                        dt = tsmp(i) - tsmp(i-1);  if dt <= 0, dt = dtNom; end
                        vpx(i) =  (p2tmm(i,1) - p2tmm(i-1,1)) / dt;       % mm/s
                        vpy(i) = -(p2tmm(i,2) - p2tmm(i-1,2)) / dt;       % mm/s, z up-positive
                    else
                        vpx(i) = NaN;  vpy(i) = NaN;                      % no real motion measured
                    end
                end
                release(tr);
            end
        end

        % ════════════════════════════════════════════════════════════════════
        %  OVERLAY MANAGEMENT
        % ════════════════════════════════════════════════════════════════════
        function initOverlayHandles(app)
            % Pre-create all overlay graphics objects once.
            % Update via XData/YData in the loop (much faster than re-plotting).
            hold(app.VideoAxes, 'on');

            % Trajectories
            app.hCenterLine = plot(app.VideoAxes, NaN, NaN, '-',  ...
                'Color', [app.ColCenter 0.55], 'LineWidth', 2.5);
            app.hCenterPt   = plot(app.VideoAxes, NaN, NaN, '*',  ...
                'Color', app.ColCenter, 'MarkerSize', 7, 'LineWidth', 1.5);
            app.hCenterCirc = plot(app.VideoAxes, NaN, NaN, '-', ...
                'Color', [app.ColCenter 0.95], 'LineWidth', 1.25);

            app.hP1Line = plot(app.VideoAxes, NaN, NaN, '--', ...
                'Color', [app.ColP1 0.55], 'LineWidth', 2);
            app.hP1Pt   = plot(app.VideoAxes, NaN, NaN, 'o',  ...
                'Color', app.ColP1, 'MarkerFaceColor', app.ColP1, 'MarkerSize', 6);

            app.hP2Line = plot(app.VideoAxes, NaN, NaN, '-.', ...
                'Color', [app.ColP2 0.55], 'LineWidth', 2);
            app.hP2Pt   = plot(app.VideoAxes, NaN, NaN, 's',  ...
                'Color', app.ColP2, 'MarkerFaceColor', app.ColP2, 'MarkerSize', 6);

            % Annotation text boxes (pinned to tracked point)
            boxOpts = {'FontName', 'Courier New', 'FontSize', 8, ...
                       'Margin', 3, 'Clipping', 'on'};
            app.hAnnCenter = text(app.VideoAxes, NaN, NaN, '', ...
                boxOpts{:}, 'Color', app.ColCenter, ...
                'BackgroundColor', [0.04 0.04 0.04 0.78], ...
                'EdgeColor', app.ColCenter, 'Visible', 'off');
            app.hAnnP1 = text(app.VideoAxes, NaN, NaN, '', ...
                boxOpts{:}, 'Color', app.ColP1, ...
                'BackgroundColor', [0.04 0.04 0.04 0.78], ...
                'EdgeColor', app.ColP1, 'Visible', 'off');
            app.hAnnP2 = text(app.VideoAxes, NaN, NaN, '', ...
                boxOpts{:}, 'Color', app.ColP2, ...
                'BackgroundColor', [0.04 0.04 0.04 0.78], ...
                'EdgeColor', app.ColP2, 'Visible', 'off');

            hold(app.VideoAxes, 'off');

            % Overlays must never intercept mouse clicks, or re-picking a seed
            % point becomes impossible once a marker/trajectory covers the image.
            set([app.hCenterLine app.hCenterPt app.hCenterCirc ...
                 app.hP1Line app.hP1Pt app.hP2Line app.hP2Pt], 'PickableParts', 'none');
            set([app.hAnnCenter app.hAnnP1 app.hAnnP2], 'PickableParts', 'none');
        end

        function setCenterCircle(app, c, r)
            % Refresh the single live outline on the currently tracked circle.
            % Updating one handle (instead of viscircles) means previous
            % frames' outlines never accumulate.
            if isempty(app.hCenterCirc) || ~isvalid(app.hCenterCirc), return; end
            if isempty(c) || numel(c) < 2 || any(~isfinite(c)) || isempty(r) || r <= 0
                app.hCenterCirc.XData = NaN; app.hCenterCirc.YData = NaN; return;
            end
            th = linspace(0, 2*pi, 80);
            app.hCenterCirc.XData = c(1) + r*cos(th);
            app.hCenterCirc.YData = c(2) + r*sin(th);
        end

        function applyPixelRuler(app)
            % Border ruler in DISPLAYED (cached) pixels — the axes' native
            % coordinates, same space as imfindcircles radius and overlays.
            % (original-video px = crop_origin + displayed/resize.)
            if isempty(app.ImgHandle) || ~isvalid(app.ImgHandle), return; end
            [fH, fW, ~] = size(app.ImgHandle.CData);
            xs = app.niceStep(fW/8); ys = app.niceStep(fH/8);
            app.VideoAxes.XTick = 0:xs:fW;
            app.VideoAxes.YTick = 0:ys:fH;
            app.VideoAxes.XTickLabelMode = 'auto';
            app.VideoAxes.YTickLabelMode = 'auto';
            app.VideoAxes.XColor = [0.62 0.66 0.70];
            app.VideoAxes.YColor = [0.62 0.66 0.70];
            app.VideoAxes.TickDir = 'out';
            app.VideoAxes.FontName = 'Courier New';
            app.VideoAxes.FontSize = 8;
            app.VideoAxes.Box = 'off';
            app.VideoAxes.Visible = 'on';   % imshow turns the axes off; re-enable so ticks/labels render
            xlabel(app.VideoAxes, 'x (px, displayed)');
            ylabel(app.VideoAxes, 'y (px, displayed)');
        end

        function s = niceStep(~, raw)
            % Round a raw spacing up to a 1/2/5 x 10^n "nice" value.
            if ~isfinite(raw) || raw <= 0, s = 1; return; end
            p = 10^floor(log10(raw)); m = raw/p;
            if     m < 1.5, s = 1*p;
            elseif m < 3.5, s = 2*p;
            elseif m < 7.5, s = 5*p;
            else            s = 10*p;
            end
        end

        function placeScaleBar(app)
            % Overlay an mm scale bar. Length in displayed px = mm * px2mm * resize
            % (px2mm is full-resolution px/mm; resize shrinks the cached frame).
            if isempty(app.ImgHandle) || ~isvalid(app.ImgHandle), return; end
            if isempty(app.hScaleBar) || ~isvalid(app.hScaleBar)
                hold(app.VideoAxes, 'on');
                app.hScaleBar = plot(app.VideoAxes, NaN, NaN, '-', ...
                    'Color', [1 1 1], 'LineWidth', 3);
                app.hScaleTxt = text(app.VideoAxes, NaN, NaN, '', ...
                    'Color', [1 1 1], 'FontName', 'Courier New', 'FontSize', 9, ...
                    'FontWeight', 'bold', 'BackgroundColor', [0 0 0 0.45], 'Margin', 2);
                hold(app.VideoAxes, 'off');
            end
            [fH, fW, ~] = size(app.ImgHandle.CData);
            pxPerMM = app.FldPx2mm.Value * app.FldResize.Value;
            if ~isfinite(pxPerMM) || pxPerMM <= 0
                app.hScaleBar.XData = NaN; app.hScaleBar.YData = NaN;
                app.hScaleTxt.String = ''; return;
            end
            spanMM = fW / pxPerMM;
            barMM  = app.niceStep(spanMM/5);
            barPx  = barMM * pxPerMM;
            x0 = round(0.04*fW); y0 = round(0.93*fH);
            app.hScaleBar.XData = [x0, x0+barPx];
            app.hScaleBar.YData = [y0, y0];
            app.hScaleTxt.Position = [x0, y0 - 0.035*fH, 0];
            app.hScaleTxt.String   = sprintf('%g mm', barMM);
        end

        function updateOverlays(app, i, ct, p1t, p2t, ctmm, p1tmm, p2tmm, vcz, vp1y, vp2y)
            ANN_OFFSET_X = 14;
            ANN_OFFSET_Y = -10;

            % ── Center ────────────────────────────────────────────────────
            if any(ct(i,:))
                cxv = ct(1:i,1); cyv = ct(1:i,2);
                bad = ~any(ct(1:i,:), 2);     % undetected frames are [0,0] -> break line
                cxv(bad) = NaN; cyv(bad) = NaN;
                app.hCenterLine.XData = cxv;
                app.hCenterLine.YData = cyv;
                app.hCenterPt.XData   = ct(i,1);
                app.hCenterPt.YData   = ct(i,2);
                app.hAnnCenter.Position = [ct(i,1)+ANN_OFFSET_X, ct(i,2)+ANN_OFFSET_Y, 0];
                app.hAnnCenter.String   = sprintf('CENTER\nx: %.3f mm\ny: %.3f mm\nvz: %.2f mm/s', ...
                    ctmm(i,1), ctmm(i,2), vcz(i));
                app.hAnnCenter.Visible  = 'on';
            end

            % ── P1 ────────────────────────────────────────────────────────
            if any(p1t(i,:))
                % Only draw trajectory from init frame
                nonz = find(any(p1t, 2), 1, 'first');
                app.hP1Line.XData = p1t(nonz:i,1);
                app.hP1Line.YData = p1t(nonz:i,2);
                app.hP1Pt.XData   = p1t(i,1);
                app.hP1Pt.YData   = p1t(i,2);
                app.hAnnP1.Position = [p1t(i,1)+ANN_OFFSET_X, p1t(i,2)+ANN_OFFSET_Y, 0];
                app.hAnnP1.String   = sprintf('P1\nx: %.3f mm\ny: %.3f mm\nvz: %.2f mm/s', ...
                    p1tmm(i,1), p1tmm(i,2), vp1y(i));
                app.hAnnP1.Visible  = 'on';
            end

            % ── P2 ────────────────────────────────────────────────────────
            if any(p2t(i,:))
                nonz = find(any(p2t, 2), 1, 'first');
                app.hP2Line.XData = p2t(nonz:i,1);
                app.hP2Line.YData = p2t(nonz:i,2);
                app.hP2Pt.XData   = p2t(i,1);
                app.hP2Pt.YData   = p2t(i,2);
                app.hAnnP2.Position = [p2t(i,1)+ANN_OFFSET_X, p2t(i,2)+ANN_OFFSET_Y, 0];
                app.hAnnP2.String   = sprintf('P2\nx: %.3f mm\ny: %.3f mm\nvz: %.2f mm/s', ...
                    p2tmm(i,1), p2tmm(i,2), vp2y(i));
                app.hAnnP2.Visible  = 'on';
            end
        end

        % ════════════════════════════════════════════════════════════════════
        %  RESULT PLOTS
        % ════════════════════════════════════════════════════════════════════
        function showResultPlots(app)
            figR = figure('Name', 'TrakLab — Results', 'NumberTitle', 'off', ...
                'Position', [150 150 860 580], 'Color', [0.12 0.14 0.17]);

            rt = app.RealTime;
            zc = -app.CenterTraj_mm(:,2);
            z1 = -app.P1Traj_mm(:,2);
            z2 = -app.P2Traj_mm(:,2);

            gsm = 20;
            vzc  = smoothdata(app.VelCz,  'gaussian', gsm);
            vz1  = smoothdata(app.VelP1y, 'gaussian', gsm);
            vz2  = smoothdata(app.VelP2y, 'gaussian', gsm);

            ax1 = subplot(2,1,1, 'Parent', figR);
            plot(ax1, rt, zc, '-',  'Color', app.ColCenter, 'LineWidth', 1.5); hold(ax1,'on');
            plot(ax1, rt, z1, '--', 'Color', app.ColP1,     'LineWidth', 1.5);
            plot(ax1, rt, z2, '-.', 'Color', app.ColP2,     'LineWidth', 1.5);
            xlabel(ax1, 'Time (s)'); ylabel(ax1, 'Position z (mm)');
            legend(ax1, 'Center_z', 'P1_z', 'P2_z', 'Location', 'best');
            title(ax1, 'Position vs Time'); grid(ax1, 'on');
            ax1.Color = [0.09 0.11 0.14]; ax1.XColor = [0.7 0.7 0.7];
            ax1.YColor = [0.7 0.7 0.7]; ax1.GridColor = [0.25 0.28 0.32];

            ax2 = subplot(2,1,2, 'Parent', figR);
            plot(ax2, rt, vzc, '-',  'Color', app.ColCenter, 'LineWidth', 1.5); hold(ax2,'on');
            plot(ax2, rt, vz1, '--', 'Color', app.ColP1,     'LineWidth', 1.5);
            plot(ax2, rt, vz2, '-.', 'Color', app.ColP2,     'LineWidth', 1.5);
            xlabel(ax2, 'Time (s)'); ylabel(ax2, 'Velocity v_z (mm/s)');
            legend(ax2, 'v_{z,center}', 'v_{z,P1}', 'v_{z,P2}', 'Location', 'best');
            title(ax2, 'Velocity vs Time'); grid(ax2, 'on');
            ax2.Color = [0.09 0.11 0.14]; ax2.XColor = [0.7 0.7 0.7];
            ax2.YColor = [0.7 0.7 0.7]; ax2.GridColor = [0.25 0.28 0.32];
        end

        % ════════════════════════════════════════════════════════════════════
        %  EXPORT — EXCEL
        % ════════════════════════════════════════════════════════════════════
        function b = baseName(app)
            % Base name derived from the loaded video file, for output names.
            if isempty(app.VideoFile), b = 'tracking'; return; end
            [~, b, ~] = fileparts(app.VideoFile);
            if isempty(b), b = 'tracking'; end
        end

        function f = padFlag(~, v, N)
            f = false(N,1);
            if ~isempty(v), n = min(N, numel(v)); f(1:n) = logical(v(1:n)); end
        end

        function f = padNum(~, v, N)
            f = nan(N,1);
            if ~isempty(v), n = min(N, numel(v)); f(1:n) = v(1:n); end
        end

        function styleExcelWindows(~, xlFile)
            % Light cosmetic pass via Excel COM (Windows only). Pure no-op if
            % automation is unavailable — the data is already written by then.
            if ~ispc, return; end
            ex = [];
            try
                ex = actxserver('Excel.Application');
                ex.Visible = false; ex.DisplayAlerts = false;
                wb = ex.Workbooks.Open(xlFile);
                for s = 1:wb.Sheets.Count
                    sh = wb.Sheets.Item(s);
                    sh.Rows.Item(1).Font.Bold      = true;
                    sh.Rows.Item(1).Interior.Color = 15921906;   % light grey-blue
                    sh.Columns.AutoFit();
                end
                wb.Save(); wb.Close(false); ex.Quit();
            catch
                try, if ~isempty(ex), ex.Quit(); end; catch, end %#ok<NOSEMI>
            end
        end

        function exportExcelFcn(app)
            % Full per-frame dump: every analysis variable + a detection log.
            outDir = app.FldOutFolder.Value;
            if ~exist(outDir, 'dir'), mkdir(outDir); end
            outFile = fullfile(outDir, [app.baseName() '_results.xlsx']);

            N = app.N_proc;
            if N < 1, app.setStatus('Nothing to export.', 'warn'); return; end

            idx = (1:N).';
            rt  = app.RealTime(:); rt = rt(1:N);

            cF  = app.padFlag(app.CenterFound, N);
            v1  = app.padFlag(app.P1Valid,     N);
            v2  = app.padFlag(app.P2Valid,     N);

            xc  =  app.CenterTraj_mm(1:N,1);  zc = -app.CenterTraj_mm(1:N,2);
            x1  =  app.P1Traj_mm(1:N,1);      z1 = -app.P1Traj_mm(1:N,2);
            x2  =  app.P2Traj_mm(1:N,1);      z2 = -app.P2Traj_mm(1:N,2);
            vxc = app.VelCx(1:N);  vzc = app.VelCz(1:N);
            vx1 = app.VelP1x(1:N); vz1 = app.VelP1y(1:N);
            vx2 = app.VelP2x(1:N); vz2 = app.VelP2y(1:N);
            rad = app.padNum(app.CenterRadius, N);

            % No fake zeros: blank out undetected center frames
            xc(~cF)=NaN; zc(~cF)=NaN; vxc(~cF)=NaN; vzc(~cF)=NaN; rad(~cF)=NaN;

            % Gap-filled center position (interior gaps only, linear in time)
            xc_i = fillmissing(xc, 'linear', 'EndValues', 'none');
            zc_i = fillmissing(zc, 'linear', 'EndValues', 'none');

            % Smoothed z-velocity (matches the result plots)
            vzc_s = smoothdata(vzc, 'gaussian', 20);
            vz1_s = smoothdata(vz1, 'gaussian', 20);
            vz2_s = smoothdata(vz2, 'gaussian', 20);

            status = repmat("OK", N, 1);
            status(~cF) = "droplet not detected";

            T = table(idx, rt, double(cF), status, ...
                xc, zc, xc_i, zc_i, vxc, vzc, vzc_s, rad, ...
                double(v1), x1, z1, vx1, vz1, vz1_s, ...
                double(v2), x2, z2, vx2, vz2, vz2_s, ...
                'VariableNames', {'frame_index','time_s','center_detected','center_status', ...
                'xc_mm','zc_mm','xc_mm_interp','zc_mm_interp','vxc_mms','vzc_mms','vzc_mms_smooth','center_radius_px', ...
                'p1_valid','x1_mm','z1_mm','vx1_mms','vz1_mms','vz1_mms_smooth', ...
                'p2_valid','x2_mm','z2_mm','vx2_mms','vz2_mms','vz2_mms_smooth'});

            meta = { ...
                'source_video',            char(string(app.VideoFile)); ...
                'export_time',             char(datetime('now')); ...
                'frames_processed',        N; ...
                'frames_center_detected',  sum(cF); ...
                'frames_center_missed',    sum(~cF); ...
                'crop_x_px',               app.FldCropX.Value; ...
                'crop_y_px',               app.FldCropY.Value; ...
                'crop_w_px',               app.FldCropW.Value; ...
                'crop_h_px',               app.FldCropH.Value; ...
                'resize_factor',           app.FldResize.Value; ...
                'px2mm_fullres',           app.FldPx2mm.Value; ...
                'px2mm_source',            app.CalibSource; ...
                'cuvette_outer_width_mm',  app.FldCuvMM.Value; ...
                'cuvette_width_px',        app.CalibWpx; ...
                'cuvette_calib_row_px',    app.CalibRow; ...
                'scale_note',              'px2mm = cuvette outer width (full-res px) / W0; one constant per video, keystone (~3 % top-bottom) not corrected'; ...
                'kval',                    app.FldKval.Value; ...
                'video_fps',               app.VideoFPS; ...
                't_start_s',               app.TStart; ...
                't_end_s',                 app.TEnd; ...
                'sign_convention',         'z = -y (up positive); velocities in mm/s'; ...
                'units_note',              'positions in mm; center_radius in displayed(resized) px'};

            try
                if exist(outFile, 'file'), delete(outFile); end   % clean overwrite
                writetable(T,    outFile, 'Sheet', 'Data');
                writecell(meta,  outFile, 'Sheet', 'Metadata');
                app.styleExcelWindows(outFile);                   % optional, Windows-only
                app.setStatus(sprintf('Excel saved (%d frames, %d missed) -> %s', ...
                    N, sum(~cF), outFile), 'ok');
            catch ME
                app.setStatus(['Excel export error: ' ME.message], 'error');
            end
        end

        % ════════════════════════════════════════════════════════════════════
        %  EXPORT — VIDEO OVERLAY
        % ════════════════════════════════════════════════════════════════════
        function exportVideoFcn(app)
            outDir  = app.FldOutFolder.Value;
            if ~exist(outDir, 'dir'), mkdir(outDir); end
            outFile = fullfile(outDir, [app.baseName() '_results.mp4']);

            app.setStatus('Exporting overlay video...', 'warn');

            try
                fps_out = max(1, round(app.VideoFPS / app.FldKval.Value));
                vw = VideoWriter(outFile, 'MPEG-4');
                vw.FrameRate = fps_out;
                vw.Quality   = 90;
                open(vw);

                N = app.N_proc;
                fig_exp = figure('Visible', 'off', 'Position', [0 0 900 600]);
                ax_exp  = axes(fig_exp, 'Position', [0 0 1 1]);

                d = uiprogressdlg(app.UIFigure, 'Title', 'Exporting Video', ...
                    'Message', 'Rendering frames...', 'Value', 0);

                pxPerMM = app.FldPx2mm.Value * app.FldResize.Value;

                for i = 1:N
                    d.Value   = i/N;
                    d.Message = sprintf('Frame %d / %d', i, N);

                    frame = app.FrameCache{i};
                    imshow(frame, 'Parent', ax_exp);
                    hold(ax_exp, 'on');
                    [fH, fW, ~] = size(frame);

                    % ── Center: gap-broken trajectory, thin circle, marker, box ──
                    if any(app.CenterTraj(i,:))
                        cx = app.CenterTraj(1:i,1); cy = app.CenterTraj(1:i,2);
                        bad = ~any(app.CenterTraj(1:i,:),2); cx(bad)=NaN; cy(bad)=NaN;
                        plot(ax_exp, cx, cy, '-', 'Color', [app.ColCenter 0.6], 'LineWidth', 2);
                        r = app.CenterRadius(min(i, numel(app.CenterRadius)));
                        if isfinite(r) && r > 0
                            th = linspace(0,2*pi,80);
                            plot(ax_exp, app.CenterTraj(i,1)+r*cos(th), app.CenterTraj(i,2)+r*sin(th), ...
                                '-', 'Color', [app.ColCenter 0.95], 'LineWidth', 1.25);
                        end
                        plot(ax_exp, app.CenterTraj(i,1), app.CenterTraj(i,2), '*', ...
                            'Color', app.ColCenter, 'MarkerSize', 8, 'LineWidth', 1.5);
                        text(ax_exp, app.CenterTraj(i,1)+14, app.CenterTraj(i,2)-10, ...
                            sprintf('C  x:%.2f z:%.2f mm\nvz:%.2f mm/s', ...
                                app.CenterTraj_mm(i,1), -app.CenterTraj_mm(i,2), app.VelCz(i)), ...
                            'Color', app.ColCenter, 'FontName','Courier New','FontSize',8, ...
                            'BackgroundColor',[0 0 0 0.6], 'Margin',2, 'Clipping','on');
                    end

                    % ── P1 ──
                    if any(app.P1Traj(i,:))
                        nz = find(any(app.P1Traj,2),1,'first');
                        plot(ax_exp, app.P1Traj(nz:i,1), app.P1Traj(nz:i,2), '--', ...
                            'Color', [app.ColP1 0.6], 'LineWidth', 2);
                        plot(ax_exp, app.P1Traj(i,1), app.P1Traj(i,2), 'o', ...
                            'Color', app.ColP1, 'MarkerFaceColor', app.ColP1, 'MarkerSize', 6);
                        text(ax_exp, app.P1Traj(i,1)+14, app.P1Traj(i,2)-10, ...
                            sprintf('P1 x:%.2f z:%.2f mm\nvz:%.2f mm/s', ...
                                app.P1Traj_mm(i,1), -app.P1Traj_mm(i,2), app.VelP1y(i)), ...
                            'Color', app.ColP1, 'FontName','Courier New','FontSize',8, ...
                            'BackgroundColor',[0 0 0 0.6], 'Margin',2, 'Clipping','on');
                    end

                    % ── P2 ──
                    if any(app.P2Traj(i,:))
                        nz = find(any(app.P2Traj,2),1,'first');
                        plot(ax_exp, app.P2Traj(nz:i,1), app.P2Traj(nz:i,2), '-.', ...
                            'Color', [app.ColP2 0.6], 'LineWidth', 2);
                        plot(ax_exp, app.P2Traj(i,1), app.P2Traj(i,2), 's', ...
                            'Color', app.ColP2, 'MarkerFaceColor', app.ColP2, 'MarkerSize', 6);
                        text(ax_exp, app.P2Traj(i,1)+14, app.P2Traj(i,2)-10, ...
                            sprintf('P2 x:%.2f z:%.2f mm\nvz:%.2f mm/s', ...
                                app.P2Traj_mm(i,1), -app.P2Traj_mm(i,2), app.VelP2y(i)), ...
                            'Color', app.ColP2, 'FontName','Courier New','FontSize',8, ...
                            'BackgroundColor',[0 0 0 0.6], 'Margin',2, 'Clipping','on');
                    end

                    % ── Baked-in mm scale bar ──
                    if isfinite(pxPerMM) && pxPerMM > 0
                        spanMM = fW / pxPerMM; barMM = app.niceStep(spanMM/5);
                        barPx = barMM * pxPerMM; x0 = round(0.04*fW); y0 = round(0.93*fH);
                        plot(ax_exp, [x0 x0+barPx], [y0 y0], '-', 'Color', [1 1 1], 'LineWidth', 3);
                        text(ax_exp, x0, y0 - 0.045*fH, sprintf('%g mm', barMM), ...
                            'Color', [1 1 1], 'FontName','Courier New','FontSize',9,'FontWeight','bold', ...
                            'BackgroundColor',[0 0 0 0.45], 'Margin',2);
                    end

                    % Timestamp watermark
                    text(ax_exp, 6, 16, sprintf('t = %.3f s', app.FrameTimestamps(i)), ...
                        'Color', 'w', 'FontName', 'Courier New', 'FontSize', 10, ...
                        'BackgroundColor', [0 0 0 0.55]);

                    hold(ax_exp, 'off');
                    fr = getframe(fig_exp);
                    writeVideo(vw, fr);
                end

                close(d);
                close(vw);
                close(fig_exp);
                app.setStatus(['Overlay video saved → ' outFile], 'ok');

            catch ME
                app.setStatus(['Video export error: ' ME.message], 'error');
            end
        end

        % ════════════════════════════════════════════════════════════════════
        %  UTILITY
        % ════════════════════════════════════════════════════════════════════
        function s = formatTime(~, t)
            m = floor(t / 60);
            s = sprintf('%d:%06.3f', m, mod(t, 60));   % M:SS.mmm (ms resolution)
        end

        function deleteFcn(app)
            % Clean up timer before closing
            app.pauseVideo();
            delete(app.UIFigure);
        end

        function toggleMaximize(app)
            if strcmp(app.UIFigure.WindowState, 'maximized')
                app.UIFigure.WindowState = 'normal';
            else
                app.UIFigure.WindowState = 'maximized';
            end
            % WindowState change fires SizeChangedFcn -> relayout automatically.
        end

        function relayout(app)
            % Option-(b) reflow: the right control column keeps a fixed width and
            % its natural height (pinned top-right); the left video region grows
            % to fill the rest of the window. Must stay in sync with the layout
            % constants in createComponents.
            if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end
            RIGHT_W  = 540;   HEADER_H = 38;
            TRANS_H  = 48;    TLINE_H  = 44;   STAT_H = 22;

            pos  = app.UIFigure.Position;
            figW = max(pos(3), RIGHT_W + 360);   % keep the left column usable
            figH = max(pos(4), 360);
            bodyH = figH - HEADER_H;
            LW    = figW - RIGHT_W;

            % Header (full width, top) + right-anchored buttons
            app.PnlHeader.Position     = [0, figH-HEADER_H, figW, HEADER_H];
            app.BtnMaximize.Position   = [figW-50,  6, 34, 26];
            app.BtnClearCache.Position = [figW-194, 6, 130, 26];
            app.BtnLoadVideo.Position  = [figW-334, 6, 130, 26];
            app.LblVideoPath.Position  = [175, 8, max(60, (figW-334)-185), 22];

            % Right control column — full window height, fixed width
            app.PnlRight.Position = [figW-RIGHT_W, 0, RIGHT_W, bodyH];

            % Left stack (status / timeline / transport / video), width = LW
            app.PnlStatus.Position    = [0, 0, LW, STAT_H];
            app.LblStatus.Position     = [8, 2, max(20, LW-16), 18];

            app.PnlTimeline.Position  = [0, STAT_H, LW, TLINE_H];
            app.SliderTimeline.Position(1) = 8;
            app.SliderTimeline.Position(3) = max(20, LW-18);
            app.LblTEnd.Position(1)    = LW-170;
            app.BtnSetTEnd.Position(1) = LW-100;

            app.PnlTransport.Position = [0, STAT_H+TLINE_H, LW, TRANS_H];
            app.BtnZoom.Position(1)    = LW-90;

            axY = STAT_H + TLINE_H + TRANS_H;
            app.VideoAxes.Position = [0, axY, LW, max(40, bodyH-axY)];

            % Keep ruler / scale bar correct for the current frame
            app.applyPixelRuler();
            app.placeScaleBar();
        end

        % ════════════════════════════════════════════════════════════════════
        %  UI CONSTRUCTION
        % ════════════════════════════════════════════════════════════════════
        function createComponents(app)
            % ── Colour constants for building UI ──────────────────────────
            BG_DARK   = [0.08 0.10 0.13];
            BG_MED    = [0.11 0.14 0.18];
            BG_PANEL  = [0.13 0.16 0.21];
            BG_CTRL   = [0.17 0.21 0.27];
            FG_TEXT   = [0.85 0.87 0.90];
            FG_MUTED  = [0.52 0.55 0.60];
            FONT_MONO = 'Courier New';
            FONT_SZ   = 9;

            FIG_W = 1280;
            FIG_H = 780;
            HEADER_H = 38;
            LEFT_W   = 740;
            RIGHT_W  = FIG_W - LEFT_W;
            BODY_H   = FIG_H - HEADER_H;
            TRANS_H  = 48;
            TLINE_H  = 44;
            STAT_H   = 22;
            AX_H     = BODY_H - TRANS_H - TLINE_H - STAT_H;

            % ── Figure ────────────────────────────────────────────────────
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Name     = 'TrakLab  v0.4  —  Point & Circle Tracking';
            app.UIFigure.Position = [80 60 FIG_W FIG_H];
            app.UIFigure.Color    = BG_DARK;
            app.UIFigure.CloseRequestFcn = @(~,~) app.deleteFcn();
            app.UIFigure.Resize = 'on';
            app.UIFigure.AutoResizeChildren = 'off';
            app.UIFigure.SizeChangedFcn = @(~,~) app.relayout();

            % ── Header bar ────────────────────────────────────────────────
            pHdr = uipanel(app.UIFigure, ...
                'Position', [0 FIG_H-HEADER_H FIG_W HEADER_H], ...
                'BackgroundColor', [0.06 0.08 0.10], ...
                'AutoResizeChildren', 'off', ...
                'BorderType', 'none');
            app.PnlHeader = pHdr;

            app.LblTitle = uilabel(pHdr, ...
                'Text', '◈ TrakLab', ...
                'Position', [10 6 130 26], ...
                'FontName', FONT_MONO, 'FontSize', 14, 'FontWeight', 'bold', ...
                'FontColor', app.ColCenter);

            uilabel(pHdr, 'Text', 'v0.4', ...
                'Position', [138 9 30 20], ...
                'FontName', FONT_MONO, 'FontSize', 9, ...
                'FontColor', FG_MUTED);

            app.LblVideoPath = uilabel(pHdr, ...
                'Text', 'no video loaded', ...
                'Position', [175 8 700 22], ...
                'FontName', FONT_MONO, 'FontSize', 9, ...
                'FontColor', FG_MUTED);

            app.BtnLoadVideo = uibutton(pHdr, ...
                'Text', 'Load Video', ...
                'Position', [920 6 130 26], ...
                'FontName', FONT_MONO, 'FontSize', 10, 'FontWeight', 'bold', ...
                'BackgroundColor', app.ColP1, 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) app.loadVideoFcn());

            app.BtnClearCache = uibutton(pHdr, ...
                'Text', 'Clear Cache', ...
                'Position', [1060 6 130 26], ...
                'FontName', FONT_MONO, 'FontSize', 10, ...
                'BackgroundColor', [0.45 0.15 0.15], 'FontColor', [1 0.6 0.6], ...
                'ButtonPushedFcn', @(~,~) app.clearCacheFcn());

            app.BtnMaximize = uibutton(pHdr, ...
                'Text', '⤢', ...
                'Position', [FIG_W-50 6 34 26], ...
                'FontName', FONT_MONO, 'FontSize', 14, ...
                'BackgroundColor', BG_CTRL, 'FontColor', FG_TEXT, ...
                'Tooltip', 'Maximize / restore window', ...
                'ButtonPushedFcn', @(~,~) app.toggleMaximize());

            % ── Video axes ────────────────────────────────────────────────
            axY = STAT_H + TLINE_H + TRANS_H;
            app.VideoAxes = uiaxes(app.UIFigure, ...
                'Position', [0 axY LEFT_W AX_H]);
            app.VideoAxes.XTick = []; app.VideoAxes.YTick = [];
            app.VideoAxes.Color = [0.04 0.05 0.07];
            app.VideoAxes.XColor = 'none'; app.VideoAxes.YColor = 'none';
            app.VideoAxes.Box = 'off';
            disableDefaultInteractivity(app.VideoAxes);

            % ── Transport bar ─────────────────────────────────────────────
            pTrans = uipanel(app.UIFigure, ...
                'Position', [0 STAT_H+TLINE_H LEFT_W TRANS_H], ...
                'AutoResizeChildren', 'off', ...
                'BackgroundColor', BG_MED, 'BorderType', 'none');
            app.PnlTransport = pTrans;

            bW=34; bH=28; bY=10; bX=6;
            mkBtn = @(txt,cb,bg,fc,pos) uibutton(pTrans,'Text',txt, ...
                'Position',pos,'FontName',FONT_MONO,'FontSize',12, ...
                'BackgroundColor',bg,'FontColor',fc,'ButtonPushedFcn',cb);

            app.BtnGoStart   = mkBtn('|◄', @(~,~)app.seekTo(app.TStart), BG_CTRL, FG_TEXT, [bX bY bW bH]);
            app.BtnStepBack  = mkBtn('◄',  @(~,~)app.stepFrame(-1),      BG_CTRL, FG_TEXT, [bX+38 bY bW bH]);
            app.BtnPlayPause = mkBtn('▶',  @(~,~)app.togglePlay(),       app.ColCenter, [1 1 1], [bX+76 bY 42 bH]);
            app.BtnStepFwd   = mkBtn('►',  @(~,~)app.stepFrame(1),       BG_CTRL, FG_TEXT, [bX+122 bY bW bH]);
            app.BtnGoEnd     = mkBtn('►|', @(~,~)app.seekTo(app.TEnd),   BG_CTRL, FG_TEXT, [bX+160 bY bW bH]);

            app.LblTime = uilabel(pTrans, 'Text', '0:00.000 / 0:00.000', ...
                'Position', [210 bY 140 bH], ...
                'FontName', FONT_MONO, 'FontSize', 10, 'FontColor', FG_MUTED);

            app.BtnZoom = uibutton(pTrans, 'Text', '⊕ Zoom', ...
                'Position', [LEFT_W-90 bY 82 bH], ...
                'FontName', FONT_MONO, 'FontSize', 9, ...
                'BackgroundColor', BG_CTRL, 'FontColor', FG_TEXT, ...
                'ButtonPushedFcn', @(~,~) app.toggleZoom());

            app.BtnCoords = uibutton(pTrans, 'Text', '⊹ Coords', ...
                'Position', [LEFT_W-262 bY 82 bH], ...
                'FontName', FONT_MONO, 'FontSize', 9, ...
                'BackgroundColor', BG_CTRL, 'FontColor', FG_TEXT, ...
                'ButtonPushedFcn', @(~,~) app.toggleCoordsMode());

            app.BtnDatum = uibutton(pTrans, 'Text', '─ Datum', ...
                'Position', [LEFT_W-176 bY 82 bH], ...
                'FontName', FONT_MONO, 'FontSize', 9, ...
                'BackgroundColor', BG_CTRL, 'FontColor', FG_TEXT, ...
                'ButtonPushedFcn', @(~,~) app.toggleDatumMode());

            app.LblDatum = uilabel(pTrans, 'Text', 'datum: —', ...
                'Position', [356 bY 150 14], 'Visible', 'off', ...
                'FontName', FONT_MONO, 'FontSize', 8, 'FontColor', FG_MUTED);

            % ── Timeline ──────────────────────────────────────────────────
            pTline = uipanel(app.UIFigure, ...
                'Position', [0 STAT_H LEFT_W TLINE_H], ...
                'AutoResizeChildren', 'off', ...
                'BackgroundColor', BG_MED, 'BorderType', 'none');
            app.PnlTimeline = pTline;

            app.SliderTimeline = uislider(pTline, ...
                'Limits', [0 100], 'Value', 0, ...
                'Position', [8 30 LEFT_W-18 3], ...
                'MajorTicksMode', 'auto', 'MinorTicks', [], ...
                'ValueChangingFcn', @(~,e) app.sliderChangingCb(e), ...
                'ValueChangedFcn',  @(~,e) app.sliderReleasedCb(e));

            % Live ms + frame readout (slider's own ticks stay coarse; this is exact)
            app.LblSeek = uilabel(pTline, 'Text', 't = 0:00.000', ...
                'Position', [LEFT_W-230 4 224 18], 'HorizontalAlignment', 'right', ...
                'FontName', FONT_MONO, 'FontSize', 9, 'FontColor', FG_TEXT);

            app.BtnSetTStart = uibutton(pTline, 'Text', '[  Set tStart', ...
                'Position', [6 4 100 20], ...
                'FontName', FONT_MONO, 'FontSize', 8, ...
                'BackgroundColor', BG_MED, 'FontColor', [0.20 0.82 0.42], ...
                'ButtonPushedFcn', @(~,~) app.setTStartNow());

            app.LblTStart = uilabel(pTline, 'Text', '0:00.0', ...
                'Position', [110 4 65 20], ...
                'FontName', FONT_MONO, 'FontSize', 8, 'FontColor', [0.20 0.82 0.42]);

            app.LblTEnd = uilabel(pTline, 'Text', '0:05.0', ...
                'Position', [LEFT_W-170 4 65 20], ...
                'FontName', FONT_MONO, 'FontSize', 8, ...
                'FontColor', app.ColCenter, 'HorizontalAlignment', 'right');

            app.BtnSetTEnd = uibutton(pTline, 'Text', 'Set tEnd  ]', ...
                'Position', [LEFT_W-100 4 96 20], ...
                'FontName', FONT_MONO, 'FontSize', 8, ...
                'BackgroundColor', BG_MED, 'FontColor', app.ColCenter, ...
                'ButtonPushedFcn', @(~,~) app.setTEndNow());

            % ── Status bar ────────────────────────────────────────────────
            pStat = uipanel(app.UIFigure, ...
                'Position', [0 0 LEFT_W STAT_H], ...
                'AutoResizeChildren', 'off', ...
                'BackgroundColor', [0.06 0.08 0.10], 'BorderType', 'none');
            app.PnlStatus = pStat;
            app.LblStatus = uilabel(pStat, 'Text', '', ...
                'Position', [8 2 LEFT_W-16 18], ...
                'FontName', FONT_MONO, 'FontSize', 8, 'FontColor', FG_MUTED);

            % ════════════════════════════════════════════════════════════════
            %  RIGHT PANEL — SETTINGS  (scrollable)
            % ════════════════════════════════════════════════════════════════
            pRight = uipanel(app.UIFigure, ...
                'Position', [LEFT_W 0 RIGHT_W BODY_H], ...
                'BackgroundColor', BG_DARK, 'BorderType', 'none', ...
                'Scrollable', 'on');
            app.PnlRight = pRight;

            % Y cursor — build bottom-up (low Y → high Y, since scrollable panel
            % shows top content first; sections are stacked upward from yy=20)
            pw  = RIGHT_W - 32;  % panel content width (leaves room for the vertical scrollbar)
            px  = 8;             % left margin
            yy  = 20;            % starting y (bottom margin)
            GAP = 8;             % gap between sections

            % NOTE: makeSectionPanel is called directly each time so that the
            % current value of yy is passed (anonymous closure would capture
            % yy by value at definition time — a common MATLAB gotcha).

            % ── PROCESS LOG (lowest section) ───────────────────────────────
            SEC_H = 150;
            pLog = app.makeSectionPanel(pRight, 'PROCESS LOG', [0.45 0.60 0.75], px, yy, pw, SEC_H);
            yy = yy + SEC_H + GAP;
            app.TxtLog = uitextarea(pLog, ...
                'Position', [6 34 pw-12 SEC_H-60], ...
                'Editable', 'off', 'Value', {''}, ...
                'FontName', FONT_MONO, 'FontSize', 8, ...
                'BackgroundColor', [0.06 0.08 0.10], 'FontColor', [0.70 0.85 0.95]);
            app.BtnSaveLog = uibutton(pLog, 'Text', 'Save Log', ...
                'Position', [6 6 (pw-20)/2 22], ...
                'FontName', FONT_MONO, 'FontSize', FONT_SZ, ...
                'BackgroundColor', BG_CTRL, 'FontColor', FG_TEXT, ...
                'ButtonPushedFcn', @(~,~) app.saveLogFcn());
            app.BtnClearLog = uibutton(pLog, 'Text', 'Clear', ...
                'Position', [(pw-20)/2+12 6 (pw-20)/2 22], ...
                'FontName', FONT_MONO, 'FontSize', FONT_SZ, ...
                'BackgroundColor', BG_CTRL, 'FontColor', FG_MUTED, ...
                'ButtonPushedFcn', @(~,~) app.clearLogFcn());

            % ── AGGREGATE VOLUME ───────────────────────────────────────────
            SEC_H = 122;
            pAgg = app.makeSectionPanel(pRight, 'AGGREGATE VOLUME', [0.55 0.35 0.20], px, yy, pw, SEC_H);
            yy = yy + SEC_H + GAP;
            ry = SEC_H - 36;
            uilabel(pAgg, 'Text', 'Box (px)', 'Position', [6 ry+2 56 16], ...
                'FontName', FONT_MONO, 'FontSize', FONT_SZ, 'FontColor', FG_MUTED);
            app.FldAggBox = uieditfield(pAgg, 'numeric', 'Value', 200, ...
                'Limits', [8 Inf], 'RoundFractionalValues', 'on', ...
                'Position', [64 ry 56 20], 'FontName', FONT_MONO, 'FontSize', FONT_SZ, ...
                'BackgroundColor', BG_CTRL, 'FontColor', FG_TEXT);
            uilabel(pAgg, 'Text', 'Axis', 'Position', [134 ry+2 34 16], ...
                'FontName', FONT_MONO, 'FontSize', FONT_SZ, 'FontColor', FG_MUTED);
            app.DdAggAxis = uidropdown(pAgg, 'Items', {'vertical','horizontal'}, ...
                'Value', 'vertical', 'Position', [168 ry pw-180 20], ...
                'FontName', FONT_MONO, 'FontSize', FONT_SZ, ...
                'BackgroundColor', BG_CTRL, 'FontColor', FG_TEXT);
            ry = ry - 30;
            app.BtnAggPick = uibutton(pAgg, 'Text', 'Pick box  ->  calc volume', ...
                'Position', [6 ry pw-12 24], ...
                'FontName', FONT_MONO, 'FontSize', FONT_SZ, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.55 0.35 0.20], 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) app.aggVolumeFcn());
            ry = ry - 24;
            app.LblAggResult = uilabel(pAgg, 'Text', 'volume: —', ...
                'Position', [6 ry pw-12 18], ...
                'FontName', FONT_MONO, 'FontSize', FONT_SZ, 'FontColor', FG_TEXT);

            % ── OUTPUT ─────────────────────────────────────────────────────
            SEC_H = 110;
            app.PnlOutput = app.makeSectionPanel(pRight, 'OUTPUT', [0.75 0.55 0.10], px, yy, pw, SEC_H);
            yy = yy + SEC_H + GAP;   % yy = 138

            ry = SEC_H - 30;  % y inside output panel

            uilabel(app.PnlOutput,'Text','Folder','Position',[6 ry-2 42 18],...
                'FontName',FONT_MONO,'FontSize',FONT_SZ,'FontColor',FG_MUTED);
            app.FldOutFolder = uieditfield(app.PnlOutput,'text',...
                'Value',fullfile(pwd,'TrakLab_results'),...
                'Position',[52 ry pw-108 20],...
                'FontName',FONT_MONO,'FontSize',FONT_SZ,...
                'BackgroundColor',BG_CTRL,'FontColor',FG_TEXT);
            app.BtnBrowseOut = uibutton(app.PnlOutput,'Text','Browse',...
                'Position',[pw-52 ry 48 20],...
                'FontName',FONT_MONO,'FontSize',FONT_SZ,...
                'BackgroundColor',BG_CTRL,'FontColor',FG_MUTED,...
                'ButtonPushedFcn',@(~,~) app.browseOutputFolder());
            ry = ry - 28;

            app.ChkExportVid = uicheckbox(app.PnlOutput,'Text','Export overlay video',...
                'Position',[6 ry 160 20],'Value',true,...
                'FontName',FONT_MONO,'FontSize',FONT_SZ,'FontColor',FG_TEXT);
            app.ChkExportXls = uicheckbox(app.PnlOutput,'Text','Export Excel',...
                'Position',[170 ry 110 20],'Value',true,...
                'FontName',FONT_MONO,'FontSize',FONT_SZ,'FontColor',FG_TEXT);
            ry = ry - 30;

            app.BtnRun = uibutton(app.PnlOutput,'Text','▶  RUN',...
                'Position',[6 ry (pw-20)/2 24],...
                'FontName',FONT_MONO,'FontSize',11,'FontWeight','bold',...
                'BackgroundColor',app.ColCenter,'FontColor',[1 1 1],...
                'ButtonPushedFcn',@(~,~) app.runTrackingFcn());
            app.BtnStop = uibutton(app.PnlOutput,'Text','⏹  STOP',...
                'Position',[(pw-20)/2+12 ry (pw-20)/2 24],...
                'FontName',FONT_MONO,'FontSize',11,'FontWeight','bold',...
                'BackgroundColor',[0.35 0.15 0.15],'FontColor',[1 0.5 0.5],...
                'ButtonPushedFcn',@(~,~) app.stopTracking());

            % ── POINT 2  (compound: up to 3 anchors) ──────────────────────
            SEC_H = 262;
            app.PnlP2 = app.makeSectionPanel(pRight, 'POINT 2  (compound)', app.ColP2, px, yy, pw, SEC_H);
            app.buildP2Panel(app.PnlP2, pw, BG_CTRL, FG_TEXT, FG_MUTED, FONT_MONO, FONT_SZ);
            yy = yy + SEC_H + GAP;

            % ── POINT 1 ───────────────────────────────────────────────────
            SEC_H = 200;
            app.PnlP1 = app.makeSectionPanel(pRight, 'POINT 1', app.ColP1, px, yy, pw, SEC_H);
            app.buildP1Panel(app.PnlP1, pw, BG_CTRL, FG_TEXT, FG_MUTED, FONT_MONO, FONT_SZ);
            yy = yy + SEC_H + GAP;   % yy = 554

            % ── CIRCLE DETECTOR ───────────────────────────────────────────
            SEC_H = 190;
            app.PnlCircle = app.makeSectionPanel(pRight, 'CIRCLE DETECTOR', app.ColCenter, px, yy, pw, SEC_H);
            app.buildCirclePanel(app.PnlCircle, pw, BG_CTRL, FG_TEXT, FG_MUTED, FONT_MONO, FONT_SZ);
            yy = yy + SEC_H + GAP;   % yy = 752

            % ── PREPROCESSING ─────────────────────────────────────────────
            SEC_H = 256;
            app.PnlPreproc = app.makeSectionPanel(pRight, 'PREPROCESSING', [0.4 0.45 0.55], px, yy, pw, SEC_H);
            app.buildPreprocPanel(app.PnlPreproc, pw, BG_CTRL, FG_TEXT, FG_MUTED, FONT_MONO, FONT_SZ);
            yy = yy + SEC_H + GAP;

            % ── CRITICAL REGION (variable kval) ────────────────────────────
            SEC_H = 104;
            pCrit = app.makeSectionPanel(pRight, 'CRITICAL REGION (dense kval)', [0.70 0.45 0.20], px, yy, pw, SEC_H);
            ry = SEC_H - 34;
            app.ChkCritEnable = uicheckbox(pCrit, 'Text', 'Enable dense region', ...
                'Position', [6 ry 180 20], 'Value', false, ...
                'FontName', FONT_MONO, 'FontSize', FONT_SZ, 'FontColor', FG_TEXT, ...
                'ValueChangedFcn', @(~,~) app.critParamChanged());
            uilabel(pCrit, 'Text', 'fine kval', 'Position', [196 ry+2 60 16], ...
                'FontName', FONT_MONO, 'FontSize', FONT_SZ, 'FontColor', FG_MUTED);
            app.FldCritKval = uieditfield(pCrit, 'numeric', 'Value', 1, ...
                'Limits', [1 Inf], 'RoundFractionalValues', true, ...
                'Position', [258 ry 50 20], 'FontName', FONT_MONO, 'FontSize', FONT_SZ, ...
                'BackgroundColor', BG_CTRL, 'FontColor', FG_TEXT, ...
                'ValueChangedFcn', @(~,~) app.critParamChanged());
            ry = ry - 30;
            app.BtnSetCritStart = uibutton(pCrit, 'Text', '[ Set start', ...
                'Position', [6 ry 90 22], 'FontName', FONT_MONO, 'FontSize', FONT_SZ, ...
                'BackgroundColor', [0.10 0.18 0.28], 'FontColor', [0.5 0.75 1.0], ...
                'ButtonPushedFcn', @(~,~) app.setCritStartNow());
            app.LblCritStart = uilabel(pCrit, 'Text', '0:00.0', 'Position', [100 ry+2 70 18], ...
                'FontName', FONT_MONO, 'FontSize', FONT_SZ, 'FontColor', FG_TEXT);
            app.LblCritEnd = uilabel(pCrit, 'Text', '0:00.0', 'Position', [pw-176 ry+2 70 18], ...
                'FontName', FONT_MONO, 'FontSize', FONT_SZ, 'FontColor', FG_TEXT, ...
                'HorizontalAlignment', 'right');
            app.BtnSetCritEnd = uibutton(pCrit, 'Text', 'Set end ]', ...
                'Position', [pw-100 ry 90 22], 'FontName', FONT_MONO, 'FontSize', FONT_SZ, ...
                'BackgroundColor', [0.10 0.18 0.28], 'FontColor', [0.5 0.75 1.0], ...
                'ButtonPushedFcn', @(~,~) app.setCritEndNow());

            app.relayout();
            app.UIFigure.Visible = 'on';
        end

        % ── Section panel factory ─────────────────────────────────────────
        function p = makeSectionPanel(~, parent, title, barColor, x, y, w, h)
            p = uipanel(parent, ...
                'Position', [x y w h], ...
                'BackgroundColor', [0.11 0.14 0.18], ...
                'BorderType', 'line', 'BorderWidth', 1, ...
                'HighlightColor', [0.18 0.22 0.28], ...
                'Title', title, ...
                'ForegroundColor', barColor, ...
                'FontName', 'Courier New', 'FontSize', 9, 'FontWeight', 'bold');
        end

        % ── Preprocessing controls ────────────────────────────────────────
        % NOTE: no nested functions here — MATLAB forbids nested functions
        %       inside classdef methods. Fields are created inline instead.
        function buildPreprocPanel(app, p, pw, bgC, fgT, fgM, fnt, fsz)
            LW = 68; FW = 62;
            C1L = 4;  C1F = 74;
            C2L = 152; C2F = 222;

            % Crop field callback: if preview is active, move the rectangle
            cropCb = @(~,~) app.updateRectFromCropFields();

            ry = 206;
            % Row 1 — Crop X / Crop Y
            uilabel(p,'Text','Crop X','Position',[C1L ry+2 LW 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldCropX = uieditfield(p,'numeric','Value',350,'Position',[C1F ry FW 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT,...
                'ValueChangedFcn', cropCb);
            uilabel(p,'Text','Crop Y','Position',[C2L ry+2 LW 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldCropY = uieditfield(p,'numeric','Value',0,'Position',[C2F ry FW 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT,...
                'ValueChangedFcn', cropCb);
            ry = ry - 26;

            % Row 2 — Crop W / Crop H
            uilabel(p,'Text','Crop W','Position',[C1L ry+2 LW 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldCropW = uieditfield(p,'numeric','Value',300,'Position',[C1F ry FW 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT,...
                'ValueChangedFcn', cropCb);
            uilabel(p,'Text','Crop H','Position',[C2L ry+2 LW 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldCropH = uieditfield(p,'numeric','Value',1080,'Position',[C2F ry FW 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT,...
                'ValueChangedFcn', cropCb);
            ry = ry - 26;

            % Row 3 — Resize
            uilabel(p,'Text','Resize','Position',[C1L ry+2 LW 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldResize = uieditfield(p,'numeric','Value',0.4,'Position',[C1F ry FW 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT,...
                'Limits',[0.05 1],'LowerLimitInclusive','off');
            ry = ry - 26;

            % Row 4 — px/mm (full-resolution px per mm) + cuvette calibration
            % Default 1.0 is a PLACEHOLDER (uncalibrated): with px/mm = 1 the
            % "mm" outputs are full-resolution pixels. Calibrate every video
            % (Calibrate button, or type a measured px/mm).
            uilabel(p,'Text','px / mm','Position',[C1L ry+2 LW 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldPx2mm = uieditfield(p,'numeric','Value',1,'Position',[C1F ry FW 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT,...
                'Limits',[0.1 Inf], 'ValueDisplayFormat', '%.3f', ...
                'ValueChangedFcn', @(~,~) app.px2mmEdited());
            uilabel(p,'Text','cuvette mm','Position',[C2L ry+2 LW 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldCuvMM = uieditfield(p,'numeric','Value',12,'Position',[C2F ry 44 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT,...
                'Limits',[0.1 Inf], 'ValueChangedFcn', @(~,~) app.cuvetteMMEdited());
            app.BtnCalib = uibutton(p, 'Text', '⟷ Calibrate', ...
                'Position', [C2F+50 ry pw-(C2F+56) 20], ...
                'FontName', fnt, 'FontSize', fsz, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.30 0.24 0.10], 'FontColor', [1.0 0.85 0.45], ...
                'Tooltip', 'Click the OUTER edge of the left, then the right cuvette wall (full frame)', ...
                'ButtonPushedFcn', @(~,~) app.toggleCalibration());
            ry = ry - 26;

            % Row 5 — kval
            uilabel(p,'Text','kval','Position',[C1L ry+2 LW 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldKval = uieditfield(p,'numeric','Value',3,'Position',[C1F ry FW 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT,...
                'Limits',[1 Inf],'RoundFractionalValues',true);
            app.LblCalib = uilabel(p,'Text','scale: not calibrated (default)', ...
                'Position',[C2L ry+2 pw-C2L-6 16],'FontName',fnt,'FontSize',fsz-1, ...
                'FontColor',[0.95 0.65 0.20]);
            ry = ry - 32;

            % Show Preview button (toggles to Confirm Crop when active)
            app.BtnShowCropPreview = uibutton(p, 'Text', '⊞  Show Crop Preview', ...
                'Position', [4 ry pw-10 26], ...
                'FontName', fnt, 'FontSize', 10, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.22 0.32 0.20], 'FontColor', [0.60 0.95 0.50], ...
                'ButtonPushedFcn', @(~,~) app.toggleCropPreview());
            ry = ry - 32;

            % Cache frames button
            app.BtnCacheFrames = uibutton(p, 'Text', '◉  Cache Frames', ...
                'Position', [4 ry pw-10 26], ...
                'FontName', fnt, 'FontSize', 10, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.18 0.28 0.40], 'FontColor', [0.65 0.85 1.0], ...
                'ButtonPushedFcn', @(~,~) app.cacheFramesFcn());
        end

        % ── Circle detector controls ──────────────────────────────────────
        function buildCirclePanel(app, p, pw, bgC, fgT, fgM, fnt, fsz)
            ry = 155;
            app.ChkCircleEnable = uicheckbox(p, 'Text', 'Enable circle detection', ...
                'Position', [4 ry pw-10 20], 'Value', true, ...
                'FontName', fnt, 'FontSize', fsz, 'FontColor', fgT);
            ry = ry - 28;

            uilabel(p,'Text','Start frame','Position',[4 ry+2 72 16],...
                'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldCircleFrame = uieditfield(p,'numeric','Value',1,...
                'Position',[78 ry 55 20],'FontName',fnt,'FontSize',fsz,...
                'BackgroundColor',bgC,'FontColor',fgT);
            app.BtnCircleFromT = uibutton(p,'Text','from ▶',...
                'Position',[138 ry 62 20],'FontName',fnt,'FontSize',fsz,...
                'BackgroundColor',[0.22 0.16 0.10],'FontColor',[1 0.6 0.3],...
                'ButtonPushedFcn',@(~,~) app.setFrameFromTimeline('circle'));
            ry = ry - 28;

            uilabel(p,'Text','Radius min','Position',[4 ry+2 70 16],...
                'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldCircleRMin = uieditfield(p,'numeric','Value',40,...
                'Position',[78 ry 55 20],'FontName',fnt,'FontSize',fsz,...
                'BackgroundColor',bgC,'FontColor',fgT);
            uilabel(p,'Text','max','Position',[138 ry+2 26 16],...
                'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldCircleRMax = uieditfield(p,'numeric','Value',140,...
                'Position',[166 ry 55 20],'FontName',fnt,'FontSize',fsz,...
                'BackgroundColor',bgC,'FontColor',fgT);
            ry = ry - 28;

            uilabel(p,'Text','Polarity','Position',[4 ry+2 56 16],...
                'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.DdCirclePol = uidropdown(p,'Items',{'dark','bright'},...
                'Position',[64 ry 90 20],'FontName',fnt,'FontSize',fsz,...
                'BackgroundColor',bgC,'FontColor',fgT);
            ry = ry - 28;

            uilabel(p,'Text','Sensitivity','Position',[4 ry+2 70 16],...
                'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.LblCircleSens = uilabel(p,'Text','0.90',...
                'Position',[pw-46 ry+2 40 16],...
                'FontName',fnt,'FontSize',fsz,'FontColor',app.ColCenter);
            app.SldCircleSens = uislider(p,...
                'Limits',[0.5 1.0],'Value',0.90,...
                'Position',[78 ry+8 pw-136 3],...
                'ValueChangedFcn', @(s,~) set(app.LblCircleSens,'Text',sprintf('%.2f',s.Value)));
        end

        % ── Point panel builders ──────────────────────────────────────────
        % Two explicit wrappers avoid dynamic property name indexing, which
        % can silently fail for typed class properties in some MATLAB versions.
        function buildP1Panel(app, p, pw, bgC, fgT, fgM, fnt, fsz)
            [app.ChkP1Enable, app.FldP1Frame, app.BtnP1FromT, ...
             app.FldP1X,      app.FldP1Y,     app.BtnPickP1,  ...
             app.FldP1Pyr,    app.FldP1Bde,   app.FldP1BlkW,  app.FldP1BlkH] = ...
             app.buildGenericPointPanel(p, 'p1', 1, 4, 4.0, pw, bgC, fgT, fgM, fnt, fsz);
        end

        function buildP2Panel(app, p, pw, bgC, fgT, fgM, fnt, fsz)
            % Compound P2: up to three (frame, x, y) anchors A/B/C. The tracker is
            % hard-reset to each anchor and tracked forward to the next (C runs to
            % the end). Anchor A reuses the original P2 field names.
            blue = [0.10 0.18 0.28]; blueF = [0.5 0.75 1.0];
            pickBg = [0.18 0.22 0.28];

            ry = 226;
            app.ChkP2Enable = uicheckbox(p, 'Text', 'Enable tracking', ...
                'Position', [4 ry 150 20], 'Value', true, ...
                'FontName', fnt, 'FontSize', fsz, 'FontColor', fgT);
            app.ChkP2Compound = uicheckbox(p, 'Text', 'Compound (A→B→C)', ...
                'Position', [176 ry 240 20], 'Value', true, ...
                'FontName', fnt, 'FontSize', fsz, 'FontColor', fgT);
            ry = ry - 28;

            % Anchor rows: label | fr | x | y | [from▶ (A only)] | Pick
            % --- Anchor A ---
            uilabel(p,'Text','A','Position',[4 ry+2 14 16],'FontName',fnt,'FontSize',fsz,'FontColor',app.ColP2);
            uilabel(p,'Text','fr','Position',[20 ry+2 16 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldP2Frame = uieditfield(p,'numeric','Value',1,'Limits',[1 Inf],'RoundFractionalValues',true,...
                'Position',[38 ry 52 20],'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT);
            uilabel(p,'Text','x','Position',[96 ry+2 10 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldP2X = uieditfield(p,'numeric','Value',0,'Position',[108 ry 58 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT);
            uilabel(p,'Text','y','Position',[172 ry+2 10 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldP2Y = uieditfield(p,'numeric','Value',0,'Position',[184 ry 58 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT);
            app.BtnP2FromT = uibutton(p,'Text','from ▶','Position',[248 ry 60 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',blue,'FontColor',blueF,...
                'ButtonPushedFcn',@(~,~) app.setFrameFromTimeline('p2'));
            app.BtnPickP2 = uibutton(p,'Text','✛ Pick','Position',[314 ry pw-320 20],...
                'FontName',fnt,'FontSize',fsz,'FontWeight','bold','BackgroundColor',pickBg,'FontColor',fgM,...
                'ButtonPushedFcn',@(~,~) app.enterPickMode('p2'));
            ry = ry - 28;

            % --- Anchor B ---
            uilabel(p,'Text','B','Position',[4 ry+2 14 16],'FontName',fnt,'FontSize',fsz,'FontColor',app.ColP2);
            uilabel(p,'Text','fr','Position',[20 ry+2 16 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldP2bFrame = uieditfield(p,'numeric','Value',0,'Limits',[0 Inf],'RoundFractionalValues',true,...
                'Position',[38 ry 52 20],'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT);
            uilabel(p,'Text','x','Position',[96 ry+2 10 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldP2bX = uieditfield(p,'numeric','Value',0,'Position',[108 ry 58 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT);
            uilabel(p,'Text','y','Position',[172 ry+2 10 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldP2bY = uieditfield(p,'numeric','Value',0,'Position',[184 ry 58 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT);
            app.BtnPickP2b = uibutton(p,'Text','✛ Pick','Position',[314 ry pw-320 20],...
                'FontName',fnt,'FontSize',fsz,'FontWeight','bold','BackgroundColor',pickBg,'FontColor',fgM,...
                'ButtonPushedFcn',@(~,~) app.enterPickMode('p2b'));
            ry = ry - 28;

            % --- Anchor C ---
            uilabel(p,'Text','C','Position',[4 ry+2 14 16],'FontName',fnt,'FontSize',fsz,'FontColor',app.ColP2);
            uilabel(p,'Text','fr','Position',[20 ry+2 16 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldP2cFrame = uieditfield(p,'numeric','Value',0,'Limits',[0 Inf],'RoundFractionalValues',true,...
                'Position',[38 ry 52 20],'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT);
            uilabel(p,'Text','x','Position',[96 ry+2 10 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldP2cX = uieditfield(p,'numeric','Value',0,'Position',[108 ry 58 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT);
            uilabel(p,'Text','y','Position',[172 ry+2 10 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldP2cY = uieditfield(p,'numeric','Value',0,'Position',[184 ry 58 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT);
            app.BtnPickP2c = uibutton(p,'Text','✛ Pick','Position',[314 ry pw-320 20],...
                'FontName',fnt,'FontSize',fsz,'FontWeight','bold','BackgroundColor',pickBg,'FontColor',fgM,...
                'ButtonPushedFcn',@(~,~) app.enterPickMode('p2c'));
            ry = ry - 30;

            % --- Shared KLT params (all 3 segments) ---
            uilabel(p,'Text','Pyramid','Position',[4 ry+2 60 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldP2Pyr = uieditfield(p,'numeric','Value',5,'Limits',[1 8],'RoundFractionalValues',true,...
                'Position',[66 ry 46 20],'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT);
            uilabel(p,'Text','Bidir','Position',[124 ry+2 36 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldP2Bde = uieditfield(p,'numeric','Value',5.0,'Limits',[0.1 20],...
                'Position',[162 ry 56 20],'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT);
            ry = ry - 28;
            uilabel(p,'Text','Block W','Position',[4 ry+2 56 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldP2BlkW = uieditfield(p,'numeric','Value',51,'Limits',[3 201],'RoundFractionalValues',true,...
                'Position',[62 ry 46 20],'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT);
            uilabel(p,'Text','H','Position',[114 ry+2 12 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldP2BlkH = uieditfield(p,'numeric','Value',51,'Limits',[3 201],'RoundFractionalValues',true,...
                'Position',[128 ry 46 20],'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT);
        end

        % Shared construction logic — returns all handles for the caller to assign
        function [chkEn, fldFr, btnFrT, fldX, fldY, btnPk, fldPyr, fldBde, fldBlkW, fldBlkH] = ...
                buildGenericPointPanel(app, p, pt, defFrm, defPyr, defBde, pw, bgC, fgT, fgM, fnt, fsz)

            if strcmp(pt, 'p1'), btnCol = app.ColP1; else, btnCol = app.ColP2; end

            ry = 165;

            % Enable checkbox
            chkEn = uicheckbox(p, 'Text', 'Enable tracking', ...
                'Position', [4 ry pw-10 20], 'Value', true, ...
                'FontName', fnt, 'FontSize', fsz, 'FontColor', fgT);
            ry = ry - 28;

            % Start frame + "from ▶"
            uilabel(p,'Text','Start frame','Position',[4 ry+2 72 16],...
                'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            fldFr = uieditfield(p,'numeric','Value',defFrm,...
                'Position',[78 ry 55 20],'FontName',fnt,'FontSize',fsz,...
                'BackgroundColor',bgC,'FontColor',fgT,'Limits',[1 Inf],'RoundFractionalValues',true);
            btnFrT = uibutton(p,'Text','from ▶',...
                'Position',[138 ry 62 20],'FontName',fnt,'FontSize',fsz,...
                'BackgroundColor',[0.10 0.18 0.28],'FontColor',[0.5 0.75 1.0],...
                'ButtonPushedFcn',@(~,~) app.setFrameFromTimeline(pt));
            ry = ry - 28;

            % x / y / Pick
            uilabel(p,'Text','x (orig px)','Position',[4 ry+2 72 16],...
                'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            fldX = uieditfield(p,'numeric','Value',0,...
                'Position',[78 ry 55 20],'FontName',fnt,'FontSize',fsz,...
                'BackgroundColor',bgC,'FontColor',fgT);
            uilabel(p,'Text','y','Position',[138 ry+2 12 16],...
                'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            fldY = uieditfield(p,'numeric','Value',0,...
                'Position',[152 ry 55 20],'FontName',fnt,'FontSize',fsz,...
                'BackgroundColor',bgC,'FontColor',fgT);
            btnPk = uibutton(p,'Text','✛ Pick',...
                'Position',[212 ry pw-218 20],...
                'FontName',fnt,'FontSize',fsz,'FontWeight','bold',...
                'BackgroundColor',[0.18 0.22 0.28],'FontColor',fgM,...
                'ButtonPushedFcn',@(~,~) app.enterPickMode(pt));
            ry = ry - 28;

            % Pyramid levels
            uilabel(p,'Text','Pyramid lvls','Position',[4 ry+2 80 16],...
                'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            fldPyr = uieditfield(p,'numeric','Value',defPyr,...
                'Position',[86 ry 46 20],'FontName',fnt,'FontSize',fsz,...
                'BackgroundColor',bgC,'FontColor',fgT,...
                'Limits',[1 8],'RoundFractionalValues',true);
            ry = ry - 28;

            % Bidirectional error
            uilabel(p,'Text','Bidir error','Position',[4 ry+2 72 16],...
                'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            fldBde = uieditfield(p,'numeric','Value',defBde,...
                'Position',[78 ry 55 20],'FontName',fnt,'FontSize',fsz,...
                'BackgroundColor',bgC,'FontColor',fgT,'Limits',[0.1 20]);
            ry = ry - 28;

            % Block size W / H
            uilabel(p,'Text','Block W','Position',[4 ry+2 52 16],...
                'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            fldBlkW = uieditfield(p,'numeric','Value',51,...
                'Position',[58 ry 46 20],'FontName',fnt,'FontSize',fsz,...
                'BackgroundColor',bgC,'FontColor',fgT,...
                'Limits',[3 201],'RoundFractionalValues',true);
            uilabel(p,'Text','H','Position',[112 ry+2 14 16],...
                'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            fldBlkH = uieditfield(p,'numeric','Value',51,...
                'Position',[128 ry 46 20],'FontName',fnt,'FontSize',fsz,...
                'BackgroundColor',bgC,'FontColor',fgT,...
                'Limits',[3 201],'RoundFractionalValues',true);
        end

        % ── Browse for output folder ──────────────────────────────────────
        function browseOutputFolder(app)
            d = uigetdir(app.FldOutFolder.Value, 'Select Output Folder');
            if isequal(d, 0), return; end
            app.FldOutFolder.Value = d;
        end

        % ════════════════════════════════════════════════════════════════════
        %  INTERACTIVE CROP PREVIEW
        % ════════════════════════════════════════════════════════════════════

        function toggleCropPreview(app)
            if app.InCropPreview
                app.confirmCropPreview();
            else
                app.showCropPreview();
            end
        end

        function showCropPreview(app)
            if isempty(app.VideoFile)
                uialert(app.UIFigure, 'Load a video first.', 'No Video');
                return;
            end

            % Pause playback — preview needs a static frame
            if app.IsPlaying, app.pauseVideo(); end

            % Show the FULL UNCROPPED frame at current timeline position
            % so the user can see the entire video frame and position the crop.
            try
                app.VidReader.CurrentTime = max(0, app.CurrentDisplayTime - 1/app.VideoFPS);
                if hasFrame(app.VidReader)
                    frame = readFrame(app.VidReader);
                else
                    app.VidReader.CurrentTime = 0;
                    frame = readFrame(app.VidReader);
                end
                app.displayVideoFrame(frame);
            catch ME
                app.setStatus(['Preview error: ' ME.message], 'error');
                return;
            end

            [fH, fW, ~] = size(frame);

            % Clamp current crop values to image bounds before drawing
            x = max(0,   min(app.FldCropX.Value, fW - 1));
            y = max(0,   min(app.FldCropY.Value, fH - 1));
            w = max(1,   min(app.FldCropW.Value, fW - x));
            h = max(1,   min(app.FldCropH.Value, fH - y));
            app.FldCropX.Value = x;
            app.FldCropY.Value = y;
            app.FldCropW.Value = w;
            app.FldCropH.Value = h;

            % Draw the draggable crop rectangle
            app.hCropRect = drawrectangle(app.VideoAxes, ...
                'Position',   [x, y, w, h], ...
                'Color',      [1.0, 0.85, 0.0], ...   % yellow
                'LineWidth',  2.0, ...
                'FaceAlpha',  0.10, ...
                'Label',      sprintf('Crop  %d × %d px', round(w), round(h)), ...
                'LabelAlpha', 0.75, ...
                'LabelTextColor', [1 1 1]);

            % Drag listener — updates fields in real time as rectangle moves
            addlistener(app.hCropRect, 'MovingROI', @(src,~) app.updateCropFromRect(src));
            addlistener(app.hCropRect, 'ROIMoved',  @(src,~) app.updateCropFromRect(src));

            % Shade the excluded region with 4 dark patches (top/bottom/left/right)
            app.drawExclusionOverlay(x, y, w, h, fW, fH);

            app.InCropPreview = true;
            app.BtnShowCropPreview.Text             = '✓  Confirm Crop';
            app.BtnShowCropPreview.BackgroundColor  = [0.15 0.45 0.22];
            app.BtnShowCropPreview.FontColor        = [0.70 1.00 0.60];
            app.BtnCacheFrames.Enable               = 'off';

            app.setStatus(sprintf( ...
                'CROP PREVIEW — drag rectangle or edit fields.  Size: %d × %d px  |  Click Confirm when done.', ...
                round(w), round(h)), 'warn');
        end

        % Draws 4 semi-transparent dark patches outside the crop rectangle.
        % They are tagged 'CropExclusion' so they can be bulk-deleted later.
        function drawExclusionOverlay(app, x, y, w, h, fW, fH)
            % Delete any stale exclusion patches from a previous preview
            delete(findobj(app.VideoAxes, 'Tag', 'CropExclusion'));

            patchColor = [0.05 0.05 0.05];
            alpha      = 0.50;

            % Regions: [x_start, y_start, width, height]
            regions = {
                [0,     0,     fW,   y    ];   % top
                [0,     y+h,   fW,   fH-y-h];  % bottom
                [0,     y,     x,    h    ];   % left
                [x+w,   y,     fW-x-w, h  ];   % right
            };

            for k = 1:4
                r = regions{k};
                if r(3) > 0 && r(4) > 0
                    patch(app.VideoAxes, ...
                        [r(1), r(1)+r(3), r(1)+r(3), r(1)], ...
                        [r(2), r(2),      r(2)+r(4), r(2)+r(4)], ...
                        patchColor, ...
                        'FaceAlpha',    alpha, ...
                        'EdgeColor',    'none', ...
                        'HitTest',      'off', ...
                        'PickableParts','none', ...
                        'Tag',          'CropExclusion');
                end
            end
        end

        % Called by drawrectangle listeners whenever the rectangle moves/resizes.
        function updateCropFromRect(app, roi)
            if ~app.InCropPreview, return; end
            pos = roi.Position;   % [x y width height] in axes data coords

            % Read full frame size from the displayed image
            if isempty(app.ImgHandle) || ~isvalid(app.ImgHandle), return; end
            [fH, fW, ~] = size(app.ImgHandle.CData);

            x = max(0,   round(pos(1)));
            y = max(0,   round(pos(2)));
            w = max(1,   round(pos(3)));
            h = max(1,   round(pos(4)));
            w = min(w, fW - x);
            h = min(h, fH - y);

            % Update fields
            app.FldCropX.Value = x;
            app.FldCropY.Value = y;
            app.FldCropW.Value = w;
            app.FldCropH.Value = h;

            % Update label on rectangle
            roi.Label = sprintf('Crop  %d × %d px', w, h);

            % Redraw exclusion overlay to follow the new rect position
            app.drawExclusionOverlay(x, y, w, h, fW, fH);

            app.setStatus(sprintf( ...
                'CROP PREVIEW — x:%d  y:%d  w:%d  h:%d  |  Click Confirm when done.', ...
                x, y, w, h), 'warn');
        end

        % Called when crop field values are typed manually during preview.
        function updateRectFromCropFields(app)
            if ~app.InCropPreview || isempty(app.hCropRect) || ~isvalid(app.hCropRect)
                return;
            end
            x = app.FldCropX.Value;
            y = app.FldCropY.Value;
            w = app.FldCropW.Value;
            h = app.FldCropH.Value;
            app.hCropRect.Position = [x, y, w, h];
            app.hCropRect.Label    = sprintf('Crop  %d × %d px', round(w), round(h));

            if ~isempty(app.ImgHandle) && isvalid(app.ImgHandle)
                [fH, fW, ~] = size(app.ImgHandle.CData);
                app.drawExclusionOverlay(x, y, w, h, fW, fH);
            end
        end

        % Confirms the crop selection and cleans up the overlay.
        function confirmCropPreview(app)
            % Remove the drawrectangle
            if ~isempty(app.hCropRect) && isvalid(app.hCropRect)
                delete(app.hCropRect);
                app.hCropRect = [];
            end
            % Remove exclusion patches
            delete(findobj(app.VideoAxes, 'Tag', 'CropExclusion'));

            app.InCropPreview = false;
            app.BtnShowCropPreview.Text            = '⊞  Show Crop Preview';
            app.BtnShowCropPreview.BackgroundColor = [0.22 0.32 0.20];
            app.BtnShowCropPreview.FontColor       = [0.60 0.95 0.50];
            app.BtnCacheFrames.Enable              = 'on';

            % Invalidate cache if crop changed
            if app.CacheValid && ~strcmp(app.buildCacheKey(), app.CacheKeyStr)
                app.clearCacheFcn();
                app.setStatus(sprintf( ...
                    'Crop confirmed: x=%d  y=%d  w=%d  h=%d  — re-cache frames.', ...
                    app.FldCropX.Value, app.FldCropY.Value, ...
                    app.FldCropW.Value, app.FldCropH.Value), 'warn');
            else
                app.setStatus(sprintf( ...
                    'Crop confirmed: x=%d  y=%d  w=%d  h=%d', ...
                    app.FldCropX.Value, app.FldCropY.Value, ...
                    app.FldCropW.Value, app.FldCropH.Value), 'ok');
            end

            % Switch back to showing the cached or video frame
            if app.CacheValid && app.NCachedFrames > 0
                [~, idx] = min(abs(app.FrameTimestamps - app.CurrentDisplayTime));
                app.displayCachedFrame(idx);
            end
        end

        % Cancel preview without confirming (called on new video load, app close).
        function cancelCropPreview(app)
            if ~app.InCropPreview, return; end
            if ~isempty(app.hCropRect) && isvalid(app.hCropRect)
                delete(app.hCropRect);
                app.hCropRect = [];
            end
            delete(findobj(app.VideoAxes, 'Tag', 'CropExclusion'));
            app.InCropPreview = false;
            app.BtnShowCropPreview.Text            = '⊞  Show Crop Preview';
            app.BtnShowCropPreview.BackgroundColor = [0.22 0.32 0.20];
            app.BtnShowCropPreview.FontColor       = [0.60 0.95 0.50];
            app.BtnCacheFrames.Enable              = 'on';
        end

        % ── Set start frame from timeline ─────────────────────────────────
        function setFrameFromTimeline(app, which)
            if ~app.CacheValid, return; end
            t = app.SliderTimeline.Value;
            [~, idx] = min(abs(app.FrameTimestamps - t));
            switch which
                case 'circle', app.FldCircleFrame.Value = idx;
                case 'p1',     app.FldP1Frame.Value     = idx;
                case 'p2',     app.FldP2Frame.Value     = idx;
            end
        end

        % ── Stop tracking ─────────────────────────────────────────────────
        function stopTracking(app)
            app.StopRequested = true;
        end

    end % private methods

    %% ── PUBLIC METHODS ────────────────────────────────────────────────────
    methods (Access = public)

        function app = TrakLab()
            app.createComponents();
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @startupFcn);
            if nargout == 0, clear app; end
        end

        function delete(app)
            app.pauseVideo();
            delete(app.UIFigure);
        end

    end

end

% ── Module-level helper ────────────────────────────────────────────────────
function s = onoff(tf)
    if tf, s = 'on'; else, s = 'off'; end
end
