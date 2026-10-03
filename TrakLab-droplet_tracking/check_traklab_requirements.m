function ok = check_traklab_requirements()
%CHECK_TRAKLAB_REQUIREMENTS  Verify MATLAB release, toolboxes and platform for TrakLab v0.4.
%
%   ok = CHECK_TRAKLAB_REQUIREMENTS() prints a report and returns true if
%   every REQUIRED item passes. Optional items (Excel styling, MP4 export)
%   only print warnings.
%
%   Required : MATLAB R2021a+, Image Processing Toolbox, Computer Vision Toolbox,
%              TrakLab.m and agg_vol_calc.m on the path.
%   Optional : Windows + Excel (cosmetic workbook styling via COM),
%              VideoWriter 'MPEG-4' profile (overlay video export; Windows/macOS).

    ok = true;
    fprintf('\nTrakLab v0.4 — requirements check\n');
    fprintf('%s\n', repmat('-', 1, 60));

    % ── MATLAB release ────────────────────────────────────────────────
    rel = version('-release');
    try
        tooOld = isMATLABReleaseOlderThan('R2021a');      % R2020b+
    catch
        tooOld = true;                                    % function absent => older than R2020b
    end
    ok = report('MATLAB release R2021a or later', ~tooOld, true, ...
        sprintf('found R%s', rel)) && ok;

    % ── Toolboxes: installed AND licensed ─────────────────────────────
    ok = report('Image Processing Toolbox', ...
        hasToolbox('images', 'Image_Toolbox') && exist('imfindcircles', 'file') > 0, true, ...
        'imfindcircles, im2gray, drawrectangle, rgb2lab') && ok;
    ok = report('Computer Vision Toolbox', ...
        hasToolbox('vision', 'Video_and_Image_Blockset') && exist('vision.PointTracker', 'class') == 8, true, ...
        'vision.PointTracker (KLT)') && ok;

    % ── Project files on the path ─────────────────────────────────────
    ok = report('TrakLab.m on path',      exist('TrakLab', 'file') == 2,      true, which('TrakLab'))      && ok;
    ok = report('agg_vol_calc.m on path', exist('agg_vol_calc', 'file') == 2, true, 'aggregate volume tool') && ok;

    % ── Optional: platform features ───────────────────────────────────
    profiles = {};
    try
        p = VideoWriter.getProfiles();
        profiles = {p.Name};
    catch
    end
    report('VideoWriter MPEG-4 (overlay MP4 export)', any(strcmp(profiles, 'MPEG-4')), false, ...
        'not available on Linux; Excel export still works');

    excelOK = false;
    if ispc
        try
            ex = actxserver('Excel.Application');
            ex.Quit(); delete(ex);
            excelOK = true;
        catch
        end
    end
    report('Excel COM (cosmetic workbook styling)', excelOK, false, 'Windows + Excel only; data export does not need it');

    fprintf('%s\n', repmat('-', 1, 60));
    if ok
        fprintf('All required items found. Launch with:  app = TrakLab;\n\n');
    else
        fprintf('Some REQUIRED items are missing — see [FAIL] lines above.\n\n');
    end
    if nargout == 0, clear ok; end
end

% ──────────────────────────────────────────────────────────────────────
function tf = hasToolbox(verName, licName)
    tf = ~isempty(ver(verName)) && license('test', licName);
end

function pass = report(name, pass, required, note)
    if pass
        tag = '[ OK ]';
    elseif required
        tag = '[FAIL]';
    else
        tag = '[warn]';
    end
    fprintf('%s %-42s %s\n', tag, name, note);
end
