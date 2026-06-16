classdef TrakLab < matlab.apps.AppBase
% TrakLab v0.3  —  Point & Circle Tracking GUI
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

        % ── Settings: Output ───────────────────────────────────────────
        PnlOutput       matlab.ui.container.Panel
        FldOutFolder    matlab.ui.control.EditField
        BtnBrowseOut    matlab.ui.control.Button
        ChkExportVid    matlab.ui.control.CheckBox
        ChkExportXls    matlab.ui.control.CheckBox
        BtnRun          matlab.ui.control.Button
        BtnStop         matlab.ui.control.Button
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

        % Image/axes handle
        ImgHandle               % handle to imshow image object

        % Overlay handles (pre-allocated for speed)
        hCenterLine, hCenterPt, hCenterCirc
        hP1Line, hP1Pt
        hP2Line, hP2Pt
        hAnnCenter, hAnnP1, hAnnP2

        % Processing
        StopRequested = false

        % Results storage
        RealTime
        CenterTraj, CenterTraj_mm
        P1Traj, P1Traj_mm
        P2Traj, P2Traj_mm
        VelCz, VelCx
        VelP1x, VelP1y
        VelP2x, VelP2y
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

            % "From ▶" buttons (need video, not necessarily cache)
            app.BtnCircleFromT.Enable = onoff(hasVid);
            app.BtnP1FromT.Enable     = onoff(hasVid);
            app.BtnP2FromT.Enable     = onoff(hasVid);

            % Point picking (needs cache)
            app.BtnPickP1.Enable = onoff(cached && ~isProc);
            app.BtnPickP2.Enable = onoff(cached && ~isProc);

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
        end

        function setStatus(app, msg, level)
            app.LblStatus.Text = msg;
            switch level
                case 'ok',    app.LblStatus.FontColor = [0.15 0.72 0.38];
                case 'warn',  app.LblStatus.FontColor = [0.90 0.62 0.05];
                case 'error', app.LblStatus.FontColor = [0.85 0.23 0.23];
                otherwise,    app.LblStatus.FontColor = [0.50 0.53 0.58];
            end
            drawnow limitrate;
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

                % Timeline slider range
                app.SliderTimeline.Limits = [0, app.VideoDuration];
                app.SliderTimeline.Value  = 0;
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
        end

        % ── Display a cached (cropped+resized) frame ──────────────────────
        function displayCachedFrame(app, idx)
            if ~app.CacheValid || idx < 1 || idx > app.NCachedFrames, return; end
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
        end

        % ════════════════════════════════════════════════════════════════════
        %  CACHE SYSTEM
        % ════════════════════════════════════════════════════════════════════
        function key = buildCacheKey(app)
            key = sprintf('%s_t%.3f_%.3f_cx%d_cy%d_cw%d_ch%d_r%.3f_k%d', ...
                app.VideoFile, app.TStart, app.TEnd, ...
                app.FldCropX.Value, app.FldCropY.Value, ...
                app.FldCropW.Value, app.FldCropH.Value, ...
                app.FldResize.Value, app.FldKval.Value);
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

            app.setStatus('Caching frames — please wait...', 'warn');

            try
                vr = VideoReader(app.VideoFile);
                vr.CurrentTime = max(0, t0);

                frames    = {};
                grays     = {};
                stamps    = [];
                frameStep = kv / vr.FrameRate;   % time between kept frames
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
                    app.SliderTimeline.Limits = [stamps(1), stamps(end)];
                    app.SliderTimeline.Value  = stamps(1);
                    app.CurrentDisplayTime    = stamps(1);
                end

                app.setState('CACHED');
                app.setStatus(sprintf('Cached %d frames  |  t = %.2f → %.2f s', ...
                    fIdx, t0, t1), 'ok');

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

        function clearCacheFcn(app)
            app.clearCacheData();
            % Restore slider to full video range (cache was constraining it)
            if app.VideoDuration > 0
                app.SliderTimeline.Limits = [0, app.VideoDuration];
                app.SliderTimeline.Value  = app.CurrentDisplayTime;
            end
            if ~isempty(app.VideoFile)
                app.setState('VIDEO_LOADED');
            else
                app.setState('IDLE');
            end
            app.setStatus('Cache cleared.', 'idle');
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
                    sliderT = max(app.SliderTimeline.Limits(1), ...
                                  min(t, app.SliderTimeline.Limits(2)));
                    app.SliderTimeline.Value = sliderT;
                    app.updateTimeLabel(t);
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

            % Always update the authoritative display time first
            app.CurrentDisplayTime = t;

            % Display the frame -------------------------------------------
            if app.CacheValid && app.NCachedFrames > 0
                % Fast path: index into RAM cache
                [~, idx] = min(abs(app.FrameTimestamps - t));
                app.displayCachedFrame(idx);
                % Keep VidReader loosely in sync so playback can resume here
                try
                    app.VidReader.CurrentTime = max(0, app.FrameTimestamps(idx) - 1/app.VideoFPS);
                catch; end
            else
                % Slow path: seek in VideoReader (keyframe-limited for H.264)
                try
                    app.VidReader.CurrentTime = max(0, t - 0.001);
                    if hasFrame(app.VidReader)
                        app.displayVideoFrame(readFrame(app.VidReader));
                    end
                catch; end
            end
            % ---------------------------------------------------------------
            % Do NOT write back to SliderTimeline here.
            % The slider is already at position t because the user dragged it,
            % or because the caller (playbackTick) set it. Writing back causes
            % a re-entrant ValueChangedFcn → seekTo loop and the snap-back bug.
            app.updateTimeLabel(t);
        end

        function stepFrame(app, direction)
            if isempty(app.VidReader), return; end
            dt  = app.FldKval.Value / app.VideoFPS;
            app.seekTo(app.SliderTimeline.Value + direction * dt);
        end

        % Called continuously while the user is dragging (ValueChangingFcn)
        function sliderChangingCb(app, event)
            app.IsDragging = true;     % block timer from overwriting slider
            app.seekTo(event.Value);
        end

        % Called once when the user releases the slider (ValueChangedFcn)
        function sliderReleasedCb(app, event)
            app.IsDragging = false;
            app.seekTo(event.Value);   % ensure final position is honoured
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
        %  POINT PICKING
        % ════════════════════════════════════════════════════════════════════
        function enterPickMode(app, pt)
            % Disable zoom while picking
            app.VideoAxes.Interactions = [];
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

            if strcmp(app.PickMode, 'p1')
                app.FldP1X.Value     = ox;
                app.FldP1Y.Value     = oy;
                app.FldP1Frame.Value = fIdx;
                app.drawPickMarker(cx, cy, app.ColP1, 'P1');
            else
                app.FldP2X.Value     = ox;
                app.FldP2Y.Value     = oy;
                app.FldP2Frame.Value = fIdx;
                app.drawPickMarker(cx, cy, app.ColP2, 'P2');
            end

            % Clear pick mode
            app.PickMode = '';
            app.ImgHandle.ButtonDownFcn = '';
            app.UIFigure.KeyPressFcn    = '';
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
                app.updateStateUI();
                app.setStatus('Pick mode cancelled.', 'idle');
            end
        end

        function drawPickMarker(app, cx, cy, color, lbl)
            hold(app.VideoAxes, 'on');
            plot(app.VideoAxes, cx, cy, 'o', 'Color', color, ...
                'MarkerSize', 11, 'LineWidth', 1.5, 'MarkerFaceColor', 'none');
            plot(app.VideoAxes, [cx-15 cx+15], [cy cy], '-', 'Color', color, 'LineWidth', 1);
            plot(app.VideoAxes, [cx cx],   [cy-15 cy+15], '-', 'Color', color, 'LineWidth', 1);
            text(app.VideoAxes, cx+13, cy-6, lbl, ...
                'Color', color, 'FontName', 'Courier New', 'FontSize', 9, 'FontWeight', 'bold');
            hold(app.VideoAxes, 'off');
        end

        % ════════════════════════════════════════════════════════════════════
        %  MAIN TRACKING LOOP
        % ════════════════════════════════════════════════════════════════════
        function runTrackingFcn(app)
            if ~app.CacheValid || app.NCachedFrames == 0
                uialert(app.UIFigure, 'Cache frames first.', 'No Cache');
                return;
            end

            % ── Gather parameters ─────────────────────────────────────────
            N      = app.NCachedFrames;
            kv     = app.FldKval.Value;
            rsz    = app.FldResize.Value;
            p2mm   = app.FldPx2mm.Value;
            delt   = kv / app.VideoFPS;

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

            % ── State & pre-alloc ──────────────────────────────────────────
            app.setState('PROCESSING');
            app.StopRequested = false;

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
            realtime       = zeros(N, 1);

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

            % ── Frame loop ─────────────────────────────────────────────────
            for i = 1:N
                if app.StopRequested, break; end

                gray = app.GrayCache{i};
                img  = app.FrameCache{i};

                % Realtime accumulation
                if i > 1
                    realtime(i) = realtime(i-1) + delt;
                end

                % Show frame
                app.ImgHandle.CData = img;
                hold(app.VideoAxes, 'on');

                % ── Circle detection ───────────────────────────────────────
                if doCirc && i >= cFrm0
                    [cc, cr] = imfindcircles(gray, rRange, ...
                        'ObjectPolarity', cpol, 'Sensitivity', csens);
                    if ~isempty(cc)
                        center_traj(i,:)    = cc(1,:);
                        center_traj_mm(i,:) = cc(1,:) / (p2mm * rsz);
                        if i > 1 && any(center_traj(i-1,:))
                            vel_cz(i) = (center_traj(i,2) - center_traj(i-1,2)) / delt;
                            vel_cx(i) = (center_traj(i,1) - center_traj(i-1,1)) / delt;
                        end
                        viscircles(app.VideoAxes, cc(1,:), cr(1), ...
                            'Color', [app.ColCenter 0.55], 'LineWidth', 1);
                    end
                end

                % ── Point 1 tracking ──────────────────────────────────────
                if doP1
                    if ~p1_init && i == p1Frm0
                        initialize(tracker1, [p1x0, p1y0], gray);
                        p1_traj(i,:)    = [p1x0, p1y0];
                        p1_traj_mm(i,:) = [p1x0, p1y0] / (p2mm * rsz);
                        p1_init = true;
                    elseif p1_init && i > p1Frm0
                        [pt1, v1] = step(tracker1, gray);
                        if v1
                            p1_traj(i,:)    = pt1;
                            p1_traj_mm(i,:) = pt1 / (p2mm * rsz);
                            vel_p1x(i) = (p1_traj(i,1) - p1_traj(i-1,1)) / delt;
                            vel_p1y(i) = (p1_traj(i,2) - p1_traj(i-1,2)) / delt;
                        else
                            p1_traj(i,:)    = p1_traj(i-1,:);
                            p1_traj_mm(i,:) = p1_traj_mm(i-1,:);
                        end
                    end
                end

                % ── Point 2 tracking ──────────────────────────────────────
                if doP2
                    if ~p2_init && i == p2Frm0
                        initialize(tracker2, [p2x0, p2y0], gray);
                        p2_traj(i,:)    = [p2x0, p2y0];
                        p2_traj_mm(i,:) = [p2x0, p2y0] / (p2mm * rsz);
                        p2_init = true;
                    elseif p2_init && i > p2Frm0
                        [pt2, v2] = step(tracker2, gray);
                        if v2
                            p2_traj(i,:)    = pt2;
                            p2_traj_mm(i,:) = pt2 / (p2mm * rsz);
                            vel_p2x(i) = (p2_traj(i,1) - p2_traj(i-1,1)) / delt;
                            vel_p2y(i) = (p2_traj(i,2) - p2_traj(i-1,2)) / delt;
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
                app.SliderTimeline.Value = app.FrameTimestamps(i);
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
            app.N_proc         = N;

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
        end

        function updateOverlays(app, i, ct, p1t, p2t, ctmm, p1tmm, p2tmm, vcz, vp1y, vp2y)
            ANN_OFFSET_X = 14;
            ANN_OFFSET_Y = -10;

            % ── Center ────────────────────────────────────────────────────
            if any(ct(i,:))
                app.hCenterLine.XData = ct(1:i,1);
                app.hCenterLine.YData = ct(1:i,2);
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
        function exportExcelFcn(app)
            outDir = app.FldOutFolder.Value;
            if ~exist(outDir, 'dir'), mkdir(outDir); end
            outFile = fullfile(outDir, 'results.xlsx');

            rt  = app.RealTime;
            zc  = -app.CenterTraj_mm(:,2);
            z1  = -app.P1Traj_mm(:,2);
            z2  = -app.P2Traj_mm(:,2);
            xc  =  app.CenterTraj_mm(:,1);
            x1  =  app.P1Traj_mm(:,1);
            x2  =  app.P2Traj_mm(:,1);
            vzc = smoothdata(app.VelCz,  'gaussian', 20);
            vz1 = smoothdata(app.VelP1y, 'gaussian', 20);
            vz2 = smoothdata(app.VelP2y, 'gaussian', 20);

            headers = {'time_s', 'xcoord_center_mm', 'zcoord_center_mm', ...
                'xcoord_p1_mm', 'zcoord_p1_mm', ...
                'xcoord_p2_mm', 'zcoord_p2_mm', ...
                'velz_center_mm/s', 'velz_p1_mm/s', 'velz_p2_mm/s'};
            M = [rt, xc, zc, x1, z1, x2, z2, vzc, vz1, vz2];

            try
                writecell(headers, outFile, 'Sheet', 1, 'Range', 'A1');
                writematrix(M,       outFile, 'Sheet', 1, 'Range', 'A2');
                app.setStatus(['Excel saved → ' outFile], 'ok');
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
            outFile = fullfile(outDir, 'tracking_overlay.mp4');

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

                for i = 1:N
                    d.Value   = i/N;
                    d.Message = sprintf('Frame %d / %d', i, N);

                    imshow(app.FrameCache{i}, 'Parent', ax_exp);
                    hold(ax_exp, 'on');

                    % Trajectories
                    if any(app.CenterTraj(i,:))
                        nz = find(any(app.CenterTraj,2),1,'first');
                        plot(ax_exp, app.CenterTraj(nz:i,1), app.CenterTraj(nz:i,2), ...
                            '-', 'Color', [app.ColCenter 0.6], 'LineWidth', 2);
                        plot(ax_exp, app.CenterTraj(i,1), app.CenterTraj(i,2), ...
                            'r*', 'MarkerSize', 7);
                    end
                    if any(app.P1Traj(i,:))
                        nz = find(any(app.P1Traj,2),1,'first');
                        plot(ax_exp, app.P1Traj(nz:i,1), app.P1Traj(nz:i,2), ...
                            '--', 'Color', [app.ColP1 0.6], 'LineWidth', 2);
                        plot(ax_exp, app.P1Traj(i,1), app.P1Traj(i,2), ...
                            'o', 'Color', app.ColP1, 'MarkerFaceColor', app.ColP1);
                    end
                    if any(app.P2Traj(i,:))
                        nz = find(any(app.P2Traj,2),1,'first');
                        plot(ax_exp, app.P2Traj(nz:i,1), app.P2Traj(nz:i,2), ...
                            '-.', 'Color', [app.ColP2 0.6], 'LineWidth', 2);
                        plot(ax_exp, app.P2Traj(i,1), app.P2Traj(i,2), ...
                            's', 'Color', app.ColP2, 'MarkerFaceColor', app.ColP2);
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
            s = sprintf('%d:%04.1f', m, mod(t, 60));
        end

        function deleteFcn(app)
            % Clean up timer before closing
            app.pauseVideo();
            delete(app.UIFigure);
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
            app.UIFigure.Name     = 'TrakLab  v0.3  —  Point & Circle Tracking';
            app.UIFigure.Position = [80 60 FIG_W FIG_H];
            app.UIFigure.Color    = BG_DARK;
            app.UIFigure.CloseRequestFcn = @(~,~) app.deleteFcn();
            app.UIFigure.Resize = 'off';

            % ── Header bar ────────────────────────────────────────────────
            pHdr = uipanel(app.UIFigure, ...
                'Position', [0 FIG_H-HEADER_H FIG_W HEADER_H], ...
                'BackgroundColor', [0.06 0.08 0.10], ...
                'BorderType', 'none');

            app.LblTitle = uilabel(pHdr, ...
                'Text', '◈ TrakLab', ...
                'Position', [10 6 130 26], ...
                'FontName', FONT_MONO, 'FontSize', 14, 'FontWeight', 'bold', ...
                'FontColor', app.ColCenter);

            uilabel(pHdr, 'Text', 'v0.3', ...
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
                'BackgroundColor', BG_MED, 'BorderType', 'none');

            bW=34; bH=28; bY=10; bX=6;
            mkBtn = @(txt,cb,bg,fc,pos) uibutton(pTrans,'Text',txt, ...
                'Position',pos,'FontName',FONT_MONO,'FontSize',12, ...
                'BackgroundColor',bg,'FontColor',fc,'ButtonPushedFcn',cb);

            app.BtnGoStart   = mkBtn('|◄', @(~,~)app.seekTo(app.TStart), BG_CTRL, FG_TEXT, [bX bY bW bH]);
            app.BtnStepBack  = mkBtn('◄',  @(~,~)app.stepFrame(-1),      BG_CTRL, FG_TEXT, [bX+38 bY bW bH]);
            app.BtnPlayPause = mkBtn('▶',  @(~,~)app.togglePlay(),       app.ColCenter, [1 1 1], [bX+76 bY 42 bH]);
            app.BtnStepFwd   = mkBtn('►',  @(~,~)app.stepFrame(1),       BG_CTRL, FG_TEXT, [bX+122 bY bW bH]);
            app.BtnGoEnd     = mkBtn('►|', @(~,~)app.seekTo(app.TEnd),   BG_CTRL, FG_TEXT, [bX+160 bY bW bH]);

            app.LblTime = uilabel(pTrans, 'Text', '0:00.0 / 0:00.0', ...
                'Position', [210 bY 140 bH], ...
                'FontName', FONT_MONO, 'FontSize', 10, 'FontColor', FG_MUTED);

            app.BtnZoom = uibutton(pTrans, 'Text', '⊕ Zoom', ...
                'Position', [LEFT_W-90 bY 82 bH], ...
                'FontName', FONT_MONO, 'FontSize', 9, ...
                'BackgroundColor', BG_CTRL, 'FontColor', FG_TEXT, ...
                'ButtonPushedFcn', @(~,~) app.toggleZoom());

            % ── Timeline ──────────────────────────────────────────────────
            pTline = uipanel(app.UIFigure, ...
                'Position', [0 STAT_H LEFT_W TLINE_H], ...
                'BackgroundColor', BG_MED, 'BorderType', 'none');

            app.SliderTimeline = uislider(pTline, ...
                'Limits', [0 100], 'Value', 0, ...
                'Position', [8 30 LEFT_W-18 3], ...
                'ValueChangingFcn', @(~,e) app.sliderChangingCb(e), ...
                'ValueChangedFcn',  @(~,e) app.sliderReleasedCb(e));

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
                'BackgroundColor', [0.06 0.08 0.10], 'BorderType', 'none');
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

            % Y cursor — build bottom-up (low Y → high Y, since scrollable panel
            % shows top content first; sections are stacked upward from yy=20)
            pw  = RIGHT_W - 20;  % panel content width
            px  = 8;             % left margin
            yy  = 20;            % starting y (bottom margin)
            GAP = 8;             % gap between sections

            % NOTE: makeSectionPanel is called directly each time so that the
            % current value of yy is passed (anonymous closure would capture
            % yy by value at definition time — a common MATLAB gotcha).

            % ── OUTPUT (lowest section) ────────────────────────────────────
            SEC_H = 110;
            app.PnlOutput = app.makeSectionPanel(pRight, 'OUTPUT', [0.75 0.55 0.10], px, yy, pw, SEC_H);
            yy = yy + SEC_H + GAP;   % yy = 138

            ry = SEC_H - 30;  % y inside output panel

            uilabel(app.PnlOutput,'Text','Folder','Position',[6 ry-2 42 18],...
                'FontName',FONT_MONO,'FontSize',FONT_SZ,'FontColor',FG_MUTED);
            app.FldOutFolder = uieditfield(app.PnlOutput,'text',...
                'Value','D:\TrakLab\results',...
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

            % ── POINT 2 ───────────────────────────────────────────────────
            SEC_H = 200;
            app.PnlP2 = app.makeSectionPanel(pRight, 'POINT 2', app.ColP2, px, yy, pw, SEC_H);
            app.buildP2Panel(app.PnlP2, pw, BG_CTRL, FG_TEXT, FG_MUTED, FONT_MONO, FONT_SZ);
            yy = yy + SEC_H + GAP;   % yy = 346

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

            % Row 4 — px/mm
            uilabel(p,'Text','px / mm','Position',[C1L ry+2 LW 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldPx2mm = uieditfield(p,'numeric','Value',56.5,'Position',[C1F ry FW 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT,...
                'Limits',[0.1 Inf]);
            ry = ry - 26;

            % Row 5 — kval
            uilabel(p,'Text','kval','Position',[C1L ry+2 LW 16],'FontName',fnt,'FontSize',fsz,'FontColor',fgM);
            app.FldKval = uieditfield(p,'numeric','Value',3,'Position',[C1F ry FW 20],...
                'FontName',fnt,'FontSize',fsz,'BackgroundColor',bgC,'FontColor',fgT,...
                'Limits',[1 Inf],'RoundFractionalValues',true);
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
            [app.ChkP2Enable, app.FldP2Frame, app.BtnP2FromT, ...
             app.FldP2X,      app.FldP2Y,     app.BtnPickP2,  ...
             app.FldP2Pyr,    app.FldP2Bde,   app.FldP2BlkW,  app.FldP2BlkH] = ...
             app.buildGenericPointPanel(p, 'p2', 390, 5, 5.0, pw, bgC, fgT, fgM, fnt, fsz);
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
