%% Droplet + point tracking program

clear all
tStart = cputime; i=0; compt(1)=0; %calculate computation time
% folderpath defines the output location
folderpath = 'D:\R11 - Cargo Transfer\CT_TrajectoryTracking_v0.2\sequences\CT_Clip';
% inoutfile defines the input video location
inputfile = 'D:\R11 - Cargo Transfer\Video_Analysis\CargoTransfer_Clip.mp4';

if ~exist(folderpath, 'dir')
    mkdir(folderpath);
end

% settings for input video
% check for total video resolution
cropsettings = [350 0 300 1080]; % cropping [xmin, ymin, width, height]
tvStart = 16; tvEnd = 19; % video start & end time in seconds
% function to extract frames from video as per settings
N = vid2frames(inputfile,folderpath,tvStart,tvEnd,cropsettings);
% structure to collect all extracted frames
jpgfiles = dir(fullfile(folderpath,'Sequence_*.jpg'));

%% Circle Detection & Tracking

% Preallocate arrays
%N = round(N/5); % adjust to number of frames processed
%N = 961;
center_traj      = zeros(N,2); 
center_traj_mm   = zeros(N,2);
realtime         = zeros(N,1);
velz             = zeros(N,1); 
velx             = zeros(N,1);

point1_traj      = zeros(N,2);
point1_traj_mm   = zeros(N,2);
vel_point1_x     = zeros(N,1);
vel_point1_y     = zeros(N,1);

point2_traj      = zeros(N,2);
point2_traj_mm   = zeros(N,2);
vel_point2_x     = zeros(N,1);
vel_point2_y     = zeros(N,1);

% Parameters
kval = 3;              % compute for every kth frame
delt   = kval/24;         % seconds between processed frames
px2mm  = 113/2;          % pixels per mm for 600x2160 px image <- check this
resize = 0.4;          % resize factor

% -------------------------------
% Initialize first point tracker
% -------------------------------
if ~isempty(jpgfiles)
    first_path = fullfile(folderpath, jpgfiles(1).name);
    first_img  = imread(first_path);
    first_img  = imresize(first_img, resize);
    first_gray = im2gray(first_img);

    % Given point in ORIGINAL pixels (origin top-left).
    given_pt = [168, 257]; % (x,y) with y negative meaning "upward"
    x0 = given_pt(1) * resize;
    y0 = (given_pt(2)) * resize; % flip sign for MATLAB image coords

    % Clamp to image bounds
    H = size(first_gray,1); W = size(first_gray,2);
    x0 = max(1, min(W, round(x0)));
    y0 = max(1, min(H, round(y0)));

    % Initialize tracker
    tracker1 = vision.PointTracker('NumPyramidLevels',4,'MaxBidirectionalError', 4.0,...
    'BlockSize',[51 51]);
    initialize(tracker1, [x0, y0], first_gray);

    % Seed buffers
    point1_traj(1,:)    = [x0, y0];
    point1_traj_mm(1,:) = [x0, y0] / (px2mm * resize);
else
    error('No sequence images found.');
end

% -------------------------------
% Prepare second tracker (delayed init)
% -------------------------------
tracker2 = vision.PointTracker('NumPyramidLevels',5,'MaxBidirectionalError', 5.0,...
    'BlockSize',[51 51]);
point2_initialized = false;

% -------------------------------
% Main loop
% -------------------------------
figure(1);
% k=1:5:len... reads every 5 frames. change the value of 5 to use other
% values of every kth frame
for k = 1:kval:length(jpgfiles)
    i = i + 1;
    seq_no = fullfile(folderpath,jpgfiles(k).name);
    disp(strcat('Image: ', seq_no, ': '));

    img      = imread(seq_no);
    img      = imresize(img, resize);
    gray_img = im2gray(img);
    imshow(gray_img); hold on;

    % --- Droplet center detection ---
    [center, radius] = imfindcircles(gray_img,[40 140], ...
        'ObjectPolarity','dark','Sensitivity',0.9);

    if isempty(center)
        disp('center not found');
        %break;
        center = [0, 0];
        radius = 0;

    else
        center_traj(i,:)    = center;
        center_traj_mm(i,:) = center / (px2mm * resize);
        disp('center found');

        if i > 1
            realtime(i) = realtime(i-1) + delt;
            velz(i)     = (center_traj(i,2) - center_traj(i-1,2)) / delt;
            velx(i)     = (center_traj(i,1) - center_traj(i-1,1)) / delt;
        end
    end

    viscircles(center,radius,'Color',[1 0 0 0.5],'LineWidth',1);
    plot(center(1,1),center(1,2),'r*');
    line(center_traj(:,1),center_traj(:,2),'Color',[1 0 0 0.5],'LineWidth',3);

    % --- Point 1 tracking ---
    if i > 1
        [pt1, valid1] = step(tracker1, gray_img);
        if valid1
            point1_traj(i,:)    = pt1;
            point1_traj_mm(i,:) = pt1 / (px2mm * resize);
            vel_point1_x(i)     = (point1_traj(i,1) - point1_traj(i-1,1)) / delt;
            vel_point1_y(i)     = (point1_traj(i,2) - point1_traj(i-1,2)) / delt;
        else
            point1_traj(i,:) = point1_traj(i-1,:);
        end
    end
    plot(point1_traj(i,1),point1_traj(i,2),'o','Color',[0 0.6 1], ...
        'MarkerFaceColor',[0 0.6 1]);
    line(point1_traj(1:i,1),point1_traj(1:i,2),'Color',[0 0.6 1 0.5],'LineWidth',3);

    % --- Point 2 tracking (initialize at frame 390) ---
    if ~point2_initialized && i == 390
        % Define initial coordinates for point 2 at t=390
        x2 = 151*resize; % example pixel coordinate
        y2 = 698*resize; % example pixel coordinate
        x2 = max(1, min(W, round(x2)));
        y2 = max(1, min(H, round(y2)));
        initialize(tracker2, [x2, y2], gray_img);
        point2_traj(i,:)    = [x2, y2];
        point2_traj_mm(i,:) = [x2, y2] / (px2mm * resize);
        point2_initialized  = true;
    elseif point2_initialized
        [pt2, valid2] = step(tracker2, gray_img);
        if valid2
            point2_traj(i,:)    = pt2;
            point2_traj_mm(i,:) = pt2 / (px2mm * resize);
            vel_point2_x(i)     = (point2_traj(i,1) - point2_traj(i-1,1)) / delt;
            vel_point2_y(i)     = (point2_traj(i,2) - point2_traj(i-1,2)) / delt;
        else
            point2_traj(i,:) = point2_traj(i-1,:);
        end
        plot(point2_traj(i,1),point2_traj(i,2),'s','Color',[0.2 0.8 0.2], ...
            'MarkerFaceColor',[0.2 0.8 0.2]);
        line(point2_traj(1:i,1),point2_traj(1:i,2),'Color',[0.2 0.8 0.2 0.5],'LineWidth',3);
    end

    pause(0.0001);
    compt(i+1) = cputime - compt(i);
end
hold off

tEnd = cputime - tStart - 0.001*i;
fprintf('Computation time: %d seconds \n', tEnd);

% Final stats
if i >= 2
    fprintf('Point1 final (px): (%.2f, %.2f)\n', point1_traj(i,1), point1_traj(i,2));
    fprintf('Point1 final (mm): (%.4f, %.4f)\n', point1_traj_mm(i,1), point1_traj_mm(i,2));
    fprintf('Point1 last velocity (px/s): vx=%.3f, vy=%.3f\n', vel_point1_x(i), vel_point1_y(i));

    if point2_initialized
        fprintf('Point2 final (px): (%.2f, %.2f)\n', point2_traj(i,1), point2_traj(i,2));
        fprintf('Point2 final (mm): (%.4f, %.4f)\n', point2_traj_mm(i,1), point2_traj_mm(i,2));
        fprintf('Point2 last velocity (px/s): vx=%.3f, vy=%.3f\n', vel_point2_x(i), vel_point2_y(i));
    end
end

%% section2 - Graphing
figure(2);
zcoord_0 = -1*center_traj_mm(:,2);
xcoord_0 = center_traj_mm(:,1);
zcoord_1 = -1*point1_traj_mm(:,2);
xcoord_1 = point1_traj_mm(:,1);
zcoord_2 = -1*point2_traj_mm(:,2);
xcoord_2 = point2_traj_mm(:,1);
te = tvEnd;
subplot(2,1,1);
plot(realtime,zcoord_0,'r')
hold on
%plot(realtime,xcoord_0,'b')
plot(realtime,zcoord_1,'b--')
%plot(realtime,xcoord_0,'b--')
plot(realtime,zcoord_2,'g-.')
%plot(realtime,xcoord_0,'b-.')
xlim([0 te])
%ylim([-20 5])
xlabel('time')
ylabel('Position (mm)')
%title("Height vs Time")
%legend("Center_{z}", "Center_{x}","P1_{z}","P1_{x}","P2_{z}","P2_{x}")
legend("Center_{z}","P1_{z}","P2_{z}")

velz_p0_smooth = smoothdata(velz,'gaussian',20);
velx_p0_smooth = smoothdata(velx,'gaussian',20);
velz_p1_smooth = smoothdata(vel_point1_y,'gaussian',20);
velx_p1_smooth = smoothdata(vel_point1_x,'gaussian',20);
velz_p2_smooth = smoothdata(vel_point2_y,'gaussian',20);
velx_p2_smooth = smoothdata(vel_point2_x,'gaussian',20);
subplot(2,1,2);
%plot(realtime,velz,'r')
%hold on
%plot(realtime,velx,'b')
plot(realtime,velz_p0_smooth,'r')
hold on
%plot(realtime,velx_p0_smooth,'b')

plot(realtime,velz_p1_smooth,'b--')
%plot(realtime,velx_p1_smooth,'b--')
plot(realtime,velz_p2_smooth,'g-.')
%plot(realtime,velx_p2_smooth,'b-.')
hold off
xlim([0 te])
%ylim([-20 30])
xlabel('time')
ylabel('Velocity (mm/s)')
%title("Velocity vs Time")
%legend("v_{z}"," v_{x}","v_{z,1}","v_{x,1}","v_{z,2}","v_{x,2}")
legend("v_{z}","v_{z,1}","v_{z,2}")

%% Data collection

% Save z-coordinate vectors to Excel
outFilename = fullfile(folderpath, 'results.xlsx');

% Concatenate into an Nx6 matrix (each column is one variable), padding with NaN to equal length
arrays = {realtime(:), zcoord_0(:), zcoord_1(:), zcoord_2(:), velz_p0_smooth(:), velz_p1_smooth(:), velz_p2_smooth(:)};
maxlen = max(cellfun(@numel, arrays));
M = NaN(maxlen, 7);
for c = 1:7
    vals = arrays{c};
    M(1:numel(vals), c) = vals;
end

% Write matrix M to Excel (each column -> Excel column)
headers = {'time','zcoord_center_mm','zcoord_p1_mm','zcoord_p2_mm','velz_center_mm/s','velz_p1_mm/s','velz_p2_mm/s'};
% Write headers in first row, then data starting from second row
writecell(headers, outFilename, 'Sheet', 1, 'Range', 'A1');
writematrix(M, outFilename, 'Sheet', 1, 'Range', 'A2');
fprintf('Saved data to %s\n', outFilename);