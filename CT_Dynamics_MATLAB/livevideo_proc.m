webcamlist
cam = webcam(2);
preview(cam);
cam.Resolution = '640x480';

% Create video input object
vidobj = videoinput('winvideo', 2, 'YUY2_640x480');  % Change format if needed
src = getselectedsource(vidobj);
vidobj.FramesPerTrigger = 1;
triggerconfig(vidobj, 'manual');

% Start video input
start(vidobj);

% Processing loop: take 1 frame per second for 10 seconds
for k = 1:10
    trigger(vidobj);                        % Trigger image capture
    data = getdata(vidobj, 1);              % Get one frame
    
    % Step 1: Resize to half
    frame_small = imresize(data, 0.5);

    % Step 2: Convert to grayscale
    gray = rgb2gray(frame_small);

    % Step 3: Convert to black & white (binarize)
    bw = imbinarize(gray);

    % Step 4: Detect circles
    [centers, radii] = imfindcircles(bw, [10 100], 'Sensitivity', 0.92);

    % Show result
    imshow(bw);
    viscircles(centers, radii, 'Color', 'r');
    title(['Frame ', num2str(k), ' - Circles Detected: ', num2str(size(centers,1))]);
    
    pause(1);  % Wait for 1 second
end

% Cleanup
stop(vidobj);
delete(vidobj);
clear vidobj;
