function [nSaved, filePaths] = vid2frames_v2(videoFile, outFolder, tStart, tEnd, cropRect, varargin)
% VID2FRAMES_V2  Extract, crop, and save frames from a video file.
%
%  Used by TrakLab's optional "save-to-disk" cache mode. For in-memory
%  caching (default), TrakLab reads frames directly — this function is
%  only called when the user explicitly requests a disk cache.
%
%  Syntax:
%    [nSaved, filePaths] = vid2frames_v2(videoFile, outFolder, ...
%                              tStart, tEnd, cropRect)
%    [nSaved, filePaths] = vid2frames_v2(..., Name, Value)
%
%  Required inputs:
%    videoFile  – full path to the source video
%    outFolder  – folder where frames are saved (created if absent)
%    tStart     – start time in seconds
%    tEnd       – end time in seconds
%    cropRect   – [x, y, width, height] in original video pixels (1-based)
%
%  Optional name-value pairs:
%    'Resize'     – scale factor applied after cropping (default: 1.0)
%    'Kval'       – save every Kval-th frame (default: 1 = every frame)
%    'Extension'  – image file extension: 'jpg' | 'png' (default: 'jpg')
%    'Quality'    – JPEG quality 1-100 (default: 90; ignored for PNG)
%    'Verbose'    – print progress to command window (default: true)
%    'Prefix'     – filename prefix (default: 'Sequence_')
%
%  Outputs:
%    nSaved    – number of frames saved
%    filePaths – cell array of saved file paths
%
%  Example:
%    vid2frames_v2('cargo.mp4', './frames', 16, 19, [350 0 300 1080], ...
%                  'Resize', 0.4, 'Kval', 3, 'Verbose', true);
% -------------------------------------------------------------------------

    %% ── Parse inputs ─────────────────────────────────────────────────────
    p = inputParser();
    p.addParameter('Resize',    1.0,    @(x) isnumeric(x) && x>0 && x<=1);
    p.addParameter('Kval',      1,      @(x) isnumeric(x) && x>=1);
    p.addParameter('Extension', 'jpg',  @(x) ismember(x, {'jpg','png'}));
    p.addParameter('Quality',   90,     @(x) isnumeric(x) && x>=1 && x<=100);
    p.addParameter('Verbose',   true,   @islogical);
    p.addParameter('Prefix',    'Sequence_', @ischar);
    p.parse(varargin{:});

    rsz   = p.Results.Resize;
    kv    = round(p.Results.Kval);
    ext   = p.Results.Extension;
    qual  = p.Results.Quality;
    verb  = p.Results.Verbose;
    pfx   = p.Results.Prefix;

    %% ── Validate inputs ──────────────────────────────────────────────────
    if ~isfile(videoFile)
        error('vid2frames_v2:fileNotFound', 'Video file not found: %s', videoFile);
    end
    if tStart < 0
        warning('vid2frames_v2:clampTStart', 'tStart < 0; clamping to 0.');
        tStart = 0;
    end
    if tEnd <= tStart
        error('vid2frames_v2:badTRange', 'tEnd must be > tStart.');
    end

    %% ── Create output folder ─────────────────────────────────────────────
    if ~exist(outFolder, 'dir')
        mkdir(outFolder);
        if verb, fprintf('Created output folder: %s\n', outFolder); end
    end

    %% ── Open video ───────────────────────────────────────────────────────
    vr = VideoReader(videoFile);
    fps = vr.FrameRate;

    % Clamp tEnd to video duration
    if tEnd > vr.Duration
        warning('vid2frames_v2:clampTEnd', ...
            'tEnd (%.2f s) > video duration (%.2f s). Clamping.', tEnd, vr.Duration);
        tEnd = vr.Duration;
    end

    vr.CurrentTime = max(0, tStart);

    %% ── Main loop ────────────────────────────────────────────────────────
    nSaved    = 0;
    filePaths = {};
    frameRead = 0;            % total frames read since tStart
    frameStep = kv / fps;     % target time between saved frames
    nextKeep  = tStart;       % timestamp of next frame to save

    tTotal = tEnd - tStart;
    tLast  = -1;              % for Verbose throttling

    if verb
        fprintf('vid2frames_v2: extracting frames from %.2f → %.2f s  (kval=%d, resize=%.2f)\n', ...
            tStart, tEnd, kv, rsz);
    end

    while hasFrame(vr) && vr.CurrentTime <= tEnd + 1/(2*fps)

        raw  = readFrame(vr);
        tNow = vr.CurrentTime;
        frameRead = frameRead + 1;

        % Skip frames that fall before the next keep timestamp
        if tNow < nextKeep - 1/(2*fps), continue; end
        nextKeep = tNow + frameStep;

        %% ── Crop ─────────────────────────────────────────────────────────
        [H, W, ~] = size(raw);
        cx = max(1, round(cropRect(1)));
        cy = max(1, round(cropRect(2)));
        cw = min(round(cropRect(3)), W - cx + 1);
        ch = min(round(cropRect(4)), H - cy + 1);

        if cw <= 0 || ch <= 0
            warning('vid2frames_v2:invalidCrop', ...
                'Frame %d: crop region is invalid. Skipping.', frameRead);
            continue;
        end

        cropped = raw(cy : cy+ch-1, cx : cx+cw-1, :);

        %% ── Resize ───────────────────────────────────────────────────────
        if rsz ~= 1.0
            cropped = imresize(cropped, rsz, 'bicubic');
        end

        %% ── Save ─────────────────────────────────────────────────────────
        nSaved = nSaved + 1;
        fname  = fullfile(outFolder, sprintf('%s%05d.%s', pfx, nSaved, ext));

        switch ext
            case 'jpg'
                imwrite(cropped, fname, 'jpg', 'Quality', qual);
            case 'png'
                imwrite(cropped, fname, 'png');
        end

        filePaths{end+1} = fname; %#ok<AGROW>

        %% ── Verbose progress ─────────────────────────────────────────────
        if verb
            pct = (tNow - tStart) / tTotal * 100;
            if tNow - tLast >= 0.5   % print at most every 0.5 s of video time
                fprintf('  [%5.1f%%]  frame %4d  |  t = %.3f s  →  %s\n', ...
                    pct, nSaved, tNow, fname);
                tLast = tNow;
            end
        end

    end % while

    if verb
        fprintf('vid2frames_v2: saved %d frames to %s\n', nSaved, outFolder);
    end

end
