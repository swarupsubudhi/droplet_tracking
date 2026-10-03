function out = agg_vol_calc(imgInput, mmPerPx, varargin)
%AGG_VOL_CALC  Axisymmetric volume of a (dark-brown) aggregate from one image.
%
%   out = AGG_VOL_CALC(imgInput, mmPerPx, Name, Value, ...)
%
%   Segments a dark-brown aggregate in a (typically 200x200 px) image and
%   estimates its 3-D volume by treating the silhouette as a SOLID OF
%   REVOLUTION about a chosen axis (disk integration:  V = pi * sum r(z)^2 dz).
%   This is the same projection method used for pendant/sessile-drop volumetry.
%
%   ------------------------------------------------------------------------
%   READ THIS FIRST — the result is only as good as three assumptions:
%
%   1. AXISYMMETRY.  A 2-D image cannot determine a 3-D volume on its own.
%      The number returned is the volume of the solid you get by spinning the
%      silhouette about the axis. If the real aggregate is lumpy / not a body
%      of revolution, the estimate can be wrong by tens of percent. The output
%      field OUT.asymmetry (0 = perfectly symmetric) quantifies how shaky the
%      assumption is for THIS image — large values mean "treat as approximate".
%
%   2. CALIBRATION cubes.  Volume scales as mmPerPx^3, so a small scale error
%      becomes a large volume error. In TrakLab, px2mm is px-per-mm in the
%      FULL-RESOLUTION frame; a box cropped from the DISPLAYED (resized) frame
%      has mmPerPx = 1 / (px2mm * resize). Pass the correct value.
%
%   3. SEGMENTATION.  Brown is a dark, desaturated orange; thresholding is
%      done by colour distance in CIELAB to a reference brown. Save the ROI as
%      PNG, not JPEG — JPEG colour-bleeds at edges and corrupts the boundary.
%   ------------------------------------------------------------------------
%
%   INPUTS
%     imgInput  Path to an image file, OR an HxWx3 (RGB) / HxW (grayscale) array.
%     mmPerPx   Millimetres per pixel of THIS image. Pass [] for uncalibrated
%               output (volume_mm3 = NaN, px-based fields still filled).
%
%   NAME-VALUE OPTIONS
%     'Axis'        'vertical' (default) | 'horizontal'  — revolution axis.
%     'RadiusMode'  'extent' (default) — r = (max-min)/2 of the foreground in
%                   each slice (full silhouette width = diameter).
%                   'area'  — r = (foreground pixel count)/2 (differs only when
%                   slices have gaps / concavities).
%     'ColorSpace'  'lab' (default) | 'rgb'  — space for brown distance.
%     'BrownRef'    1x3 RGB in [0,1] of the aggregate colour. Default ~ dark
%                   brown [0.40 0.26 0.13]. Override per your lighting.
%     'PickColor'   false (default) | true  — click the aggregate to set BrownRef.
%     'Tol'         [] (default, Otsu auto) | scalar colour-distance threshold.
%     'FillHoles'   true (default)  — imfill the mask.
%     'LargestOnly' true (default)  — keep only the largest connected blob.
%     'MinAreaFrac' 0.001 (default) — drop blobs smaller than this * image area.
%     'Smooth'      [] (default = max(3,round(0.03*span))) — radius-profile
%                   moving-average window (px) to suppress single-pixel jitter.
%     'ShowPlots'   false (default) | true  — diagnostic figure.
%
%   OUTPUT (struct)
%     volume_mm3, volume_px3, area_mm2, area_px, height_mm, height_px,
%     maxRadius_mm, maxRadius_px, equivSphereDiam_mm, asymmetry,
%     radiusProfile_px, sliceCoord_px, mask, mmPerPx, opts
%
%   EXAMPLE (from TrakLab calibration)
%     mmPerPx = 1 / (px2mm * resize);      % e.g. 1 / (135.3 * 0.4)
%     out = agg_vol_calc('agg.png', mmPerPx, 'ShowPlots', true);
%     fprintf('V = %.4g mm^3 (asymmetry %.0f%%)\n', out.volume_mm3, 100*out.asymmetry);

% ----------------------------- parse inputs -----------------------------
p = inputParser;
p.addRequired('imgInput');
p.addRequired('mmPerPx', @(x) isempty(x) || (isscalar(x) && x > 0));
p.addParameter('Axis', 'vertical', @(s) any(strcmpi(s, {'vertical','horizontal'})));
p.addParameter('RadiusMode', 'extent', @(s) any(strcmpi(s, {'extent','area'})));
p.addParameter('ColorSpace', 'lab', @(s) any(strcmpi(s, {'lab','rgb'})));
p.addParameter('BrownRef', [0.40 0.26 0.13], @(v) isnumeric(v) && numel(v) == 3);
p.addParameter('PickColor', false, @(x) islogical(x) || ismember(x,[0 1]));
p.addParameter('Tol', [], @(x) isempty(x) || (isscalar(x) && x > 0));
p.addParameter('FillHoles', true, @(x) islogical(x) || ismember(x,[0 1]));
p.addParameter('LargestOnly', true, @(x) islogical(x) || ismember(x,[0 1]));
p.addParameter('MinAreaFrac', 0.001, @(x) isscalar(x) && x >= 0);
p.addParameter('Smooth', [], @(x) isempty(x) || (isscalar(x) && x >= 1));
p.addParameter('ShowPlots', false, @(x) islogical(x) || ismember(x,[0 1]));
p.parse(imgInput, mmPerPx, varargin{:});
o = p.Results;

% ----------------------------- load image -------------------------------
if ischar(imgInput) || isstring(imgInput)
    if exist(char(imgInput), 'file') ~= 2
        error('agg_vol_calc:fileNotFound', 'Image not found: %s', char(imgInput));
    end
    I = imread(char(imgInput));
else
    I = imgInput;
end
isColor = (ndims(I) == 3 && size(I,3) == 3);
Id = im2double(I);                       % [0,1]
[H, W, ~] = size(Id);
imArea = H * W;

% ----------------------------- segmentation -----------------------------
if o.PickColor && isColor
    f = figure('Name','Click the aggregate, then press Enter'); imshow(Id);
    title('Click a point on the aggregate (dark brown), then press Enter');
    [xc, yc] = ginput(1);
    if ~isempty(xc)
        xc = round(xc); yc = round(yc);
        xc = max(1,min(W,xc)); yc = max(1,min(H,yc));
        o.BrownRef = squeeze(Id(yc, xc, :))';
    end
    if isvalid(f), close(f); end
end

if isColor
    switch lower(o.ColorSpace)
        case 'lab'
            lab    = rgb2lab(Id);
            labRef = rgb2lab(reshape(o.BrownRef(:)',1,1,3));
            dist   = sqrt(sum((lab - labRef).^2, 3));
        case 'rgb'
            ref  = reshape(o.BrownRef(:)',1,1,3);
            dist = sqrt(sum((Id - ref).^2, 3));
    end
    colourNote = sprintf('%s distance to brown ref [%.2f %.2f %.2f]', ...
        upper(o.ColorSpace), o.BrownRef(1), o.BrownRef(2), o.BrownRef(3));
else
    % No colour information: fall back to "dark region" detection.
    warning('agg_vol_calc:grayscale', ...
        'Grayscale image: no colour info, segmenting the DARK region instead of brown.');
    dist = Id;                 % low intensity = aggregate; threshold picks dark
    colourNote = 'grayscale intensity (dark = aggregate)';
end

% distance -> binary mask (small distance / dark = aggregate)
dn = dist - min(dist(:));
if max(dn(:)) > 0, dn = dn / max(dn(:)); end
if isempty(o.Tol)
    thr  = graythresh(dn);     % Otsu split between "near brown" and "far"
    mask = dn <= thr;
else
    if isColor
        mask = dist <= o.Tol;
    else
        mask = dist <= o.Tol;
    end
end

% morphological cleanup
if o.MinAreaFrac > 0
    mask = bwareaopen(mask, max(1, round(o.MinAreaFrac * imArea)));
end
if o.FillHoles
    mask = imfill(mask, 'holes');
end
if o.LargestOnly
    cc = bwconncomp(mask);
    if cc.NumObjects > 1
        np = cellfun(@numel, cc.PixelIdxList);
        [~, kbig] = max(np);
        m2 = false(size(mask));
        m2(cc.PixelIdxList{kbig}) = true;
        mask = m2;
    end
end

if ~any(mask(:))
    error('agg_vol_calc:emptyMask', ...
        ['No aggregate found. Adjust BrownRef / Tol / ColorSpace, or check the ' ...
         'image is the right ROI. (segmentation: %s)'], colourNote);
end

% ----------------------------- radius profile ---------------------------
% Work in an orientation where we integrate row-by-row (axis is vertical),
% then transpose for the horizontal-axis case.
isVertical = strcmpi(o.Axis, 'vertical');
M = mask; if ~isVertical, M = mask'; end     % rows = integration slices
nSlices = size(M, 1);

r       = zeros(nSlices, 1);     % radius per slice (px)
leftw   = nan(nSlices, 1);       % half-width left of centroid
rightw  = nan(nSlices, 1);       % half-width right of centroid
% global axis = centroid column of the whole silhouette (best symmetric guess)
[~, cols] = find(M);
axisPos = mean(cols);
for s = 1:nSlices
    idx = find(M(s, :));
    if isempty(idx), continue; end
    switch lower(o.RadiusMode)
        case 'extent'
            r(s) = (max(idx) - min(idx) + 1) / 2;
        case 'area'
            r(s) = numel(idx) / 2;
    end
    leftw(s)  = axisPos - min(idx);
    rightw(s) = max(idx) - axisPos;
end

% smoothing of the radius profile (suppress single-pixel jitter)
span = nnz(r > 0);
sw = o.Smooth; if isempty(sw), sw = max(3, round(0.03 * max(span,1))); end
if sw >= 3 && span >= sw
    rsm = movmean(r, sw);
    rsm(r == 0) = 0;            % keep empty slices empty
else
    rsm = r;
end

% ----------------------------- volume + metrics -------------------------
dz_px      = 1;
volume_px3 = pi * sum(rsm.^2) * dz_px;        % disk integration
area_px    = nnz(mask);
height_px  = span;
maxR_px    = max(rsm);

% asymmetry: width-weighted mean |left-right| / (left+right) over filled slices
valid = ~isnan(leftw) & ~isnan(rightw) & (leftw + rightw) > 0;
if any(valid)
    a   = abs(leftw(valid) - rightw(valid)) ./ (leftw(valid) + rightw(valid));
    wts = (leftw(valid) + rightw(valid));
    asymmetry = sum(a .* wts) / sum(wts);
else
    asymmetry = NaN;
end

if isempty(o.mmPerPx)
    s1 = NaN;                                  % uncalibrated
else
    s1 = o.mmPerPx;
end
volume_mm3   = volume_px3 * s1^3;
area_mm2     = area_px    * s1^2;
height_mm    = height_px  * s1;
maxR_mm      = maxR_px    * s1;
if isfinite(volume_mm3) && volume_mm3 > 0
    equivSphereDiam_mm = 2 * (3 * volume_mm3 / (4*pi))^(1/3);
else
    equivSphereDiam_mm = NaN;
end

% ----------------------------- pack output ------------------------------
out = struct();
out.volume_mm3         = volume_mm3;
out.volume_px3         = volume_px3;
out.area_mm2           = area_mm2;
out.area_px            = area_px;
out.height_mm          = height_mm;
out.height_px          = height_px;
out.maxRadius_mm       = maxR_mm;
out.maxRadius_px       = maxR_px;
out.equivSphereDiam_mm = equivSphereDiam_mm;
out.asymmetry          = asymmetry;
out.radiusProfile_px   = rsm;
out.sliceCoord_px      = (1:nSlices)';
out.mask               = mask;
out.mmPerPx            = s1;
out.opts               = o;
out.segmentationNote   = colourNote;

if asymmetry > 0.15
    warning('agg_vol_calc:asymmetric', ...
        ['Silhouette asymmetry is %.0f%% — the axisymmetric assumption is weak; ' ...
         'treat the volume as approximate.'], 100*asymmetry);
end

% ----------------------------- diagnostics ------------------------------
if o.ShowPlots
    figure('Name', 'agg\_vol\_calc diagnostics', 'Color', 'w');

    subplot(2,2,1); imshow(Id); title('input ROI');

    subplot(2,2,2);
    imshow(Id); hold on;
    try
        visboundaries(mask, 'Color', [0.95 0.4 0.1], 'LineWidth', 1);
    catch
        b = bwperim(mask); [yb, xb] = find(b);
        plot(xb, yb, '.', 'Color', [0.95 0.4 0.1], 'MarkerSize', 2);
    end
    hold off; title(sprintf('mask boundary (%s)', o.RadiusMode));

    subplot(2,2,3);
    zc = out.sliceCoord_px;
    plot(rsm, zc, '-', 'LineWidth', 1.5); set(gca, 'YDir', 'reverse'); grid on;
    xlabel('radius (px)'); ylabel(sprintf('%s slice (px)', o.Axis));
    title('radius profile');

    subplot(2,2,4);
    % reconstructed symmetric silhouette (axis-centred) for visual sanity check
    rr = rsm; zc2 = zc;
    fill([ axisPos - rr; flipud(axisPos + rr)], [zc2; flipud(zc2)], ...
        [0.85 0.55 0.30], 'EdgeColor', [0.4 0.2 0.1], 'FaceAlpha', 0.6);
    set(gca, 'YDir', 'reverse'); axis equal tight; grid on;
    xlabel('x (px)'); ylabel('z (px)');
    if isfinite(volume_mm3)
        title(sprintf('revolved profile | V=%.3g mm^3, asym %.0f%%', volume_mm3, 100*asymmetry));
    else
        title(sprintf('revolved profile | V=%.3g px^3 (uncalibrated)', volume_px3));
    end
end

end % agg_vol_calc
