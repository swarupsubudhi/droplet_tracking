function nSaved = vid2frames(videoFile, outFolder, tStart, tEnd, cropRect, varargin)
% video_to_frames  Read frames between tStart and tEnd, crop and save.
%
% Inputs
%   videoPathOrFile  - file name or full/partial path. If a folder is given,
%                      the function finds the first video file in that folder.
%   outFolder        - output folder (created if missing)
%   tStart, tEnd     - start and end times in seconds (0 <= tStart < tEnd <= Duration)
%   cropRect         - [x y width height] in pixels (1-based origin)
% Optional name-value pairs:
%   'Extension'      - image extension (default '.png')
%   'MaxFrames'      - max frames to save (default Inf)
%   'Verbose'        - true/false (default true)
%
% Output
%   nSaved           - number of saved frames

v = VideoReader(videoFile);
v.CurrentTime = tStart;

nSaved = 0;
frameIdx = 0;

while hasFrame(v) && v.CurrentTime < tEnd
    frame = readFrame(v);
    frameIdx = frameIdx + 1;

    %app.log(sprintf( ...
    %    'Read frame %d @ t=%.4f s', ...
    %    frameIdx, v.CurrentTime));

    % Crop validation (same as your original)
    H=size(frame,1); W=size(frame,2);
    x=max(1,round(cropRect(1)));
    y=max(1,round(cropRect(2)));
    w=min(round(cropRect(3)),W-x+1);
    h=min(round(cropRect(4)),H-y+1);

    %if w<=0 || h<=0
    %    app.log('Frame skipped (invalid crop)');
    %    continue
    %end

    cropped = frame(y:y+h-1, x:x+w-1, :);
  
    %cropped = imresize(cropped, 1/5, 'bicubic');  % downscale by 5x (use 'bilinear' or 'nearest' if preferred)

    nSaved = nSaved + 1;

    fname = fullfile(outFolder, ...
        sprintf('Sequence_%05d.jpg',nSaved));
    imwrite(cropped,fname);

    %app.log(['Saved ' fname]);
end

end