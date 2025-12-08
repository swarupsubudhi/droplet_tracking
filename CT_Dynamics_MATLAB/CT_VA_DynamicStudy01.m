tStart = cputime; i=0; compt(1)=0;
folderpath = 'sequences';
jpgfiles = dir(fullfile(folderpath,'Sequence *.jpg'));
center_traj = zeros(239,2); center_traj_mm = zeros(239,2);
realtime = zeros(239,1);
velz = zeros(239,1); velx = zeros(239,1);
delt = 5/24;
px2mm = 113; % 113 pixels per mm for an 600x2160 px image
resize = 0.2;

figure(1);
for k=1:5:length(jpgfiles)
    i=i+1;
    fillPath(i,:) = fullfile(folderpath,jpgfiles(k).name);
    seq_no = fullfile(folderpath,jpgfiles(k).name);
    disp(strcat('Image: ',seq_no,': '));
    img = imread(seq_no);
    
    img =  imresize(img,0.2);

    gray_img = im2gray(img);
    imshow(gray_img)

    [center,radius] = imfindcircles(gray_img,[40 170],'ObjectPolarity','dark',...
        'Sensitivity',0.9);
    if isempty(center)==1
        disp('center not found');
        %center_traj(i,:) = 0;
        break;
    else
        center_traj(i,:) = center;
        center_traj_mm(i,:) = center/(px2mm*0.2);
        disp('center found');
        if i>1
            realtime(i) = realtime(i-1) + delt; %in seconds
            velz(i) = (center_traj(i,2) - center_traj(i-1,2))/delt;
            velx(i) = (center_traj(i,1) - center_traj(i-1,1))/delt;
        end
    end

    viscircles(center,radius,'Color',[1 0 0 0.5],'LineWidth',1);
    rectangle('Position',[center 10 10]);
    plot(center(1,1),center(1,2),'r*')
    hold on
    line(center_traj(:,1),center_traj(:,2),'Color',[1 0 0 0.5],'LineWidth',1)
    pause(0.0001)
    compt(i+1) = cputime - compt(i);
end
hold off
tEnd = cputime - tStart - 0.001*i;

fprintf('Computataion time: %d seconds \n',tEnd)


%% section2
figure(2);
zcoord = -1*center_traj_mm(:,2);
xcoord = center_traj_mm(:,1);
te = k/24;
subplot(2,1,1);
plot(realtime,zcoord,'r')
hold on
plot(realtime,xcoord,'b')
xlim([0 te])
ylim([-20 5])
xlabel('time')
ylabel('Position (mm)')
%title("Height vs Time")
legend("z-coordinate", "x-coordinate")

velz_smooth = smoothdata(velz,'gaussian',20);
velx_smooth = smoothdata(velx,'gaussian',20);
subplot(2,1,2);
plot(realtime,velz,'r')
hold on
plot(realtime,velx,'b')
plot(realtime,velz_smooth,'r--')
plot(realtime,velx_smooth,'b--')
hold off
xlim([0 te])
%ylim([-20 30])
xlabel('time')
ylabel('Velocity (mm/s)')
%title("Velocity vs Time")
legend("v_{z}"," v_{x}","smooth v_{z}","smooth v_{x}")

%% image

%f = figure;
%ax = axes;
%show_img = imresize(imread("sequences/Sequence 010000.jpg"),0.2);
%[rows, columns, numberOfColorChannels] = size(gray_img);
%imshow(show_img)
%hold on;
%for row = 1 : 20 : rows
%    line([1, columns], [row, row], 'Color', 'r', 'LineWidth', 0.5);
%end
%for col = 1 : 20 : columns
%    line([col, col], [1, rows], 'Color', 'r', 'LineWidth', 0.5);
%end