tStart = cputime; i=0; compt(1)=0;
folderpath = 'sequences';
jpgfiles = dir(fullfile(folderpath,'*.jpg'));
%center_traj = zeros(1193,2);
realtime = zeros(239,1);
velz = zeros(239,1);
delt = 5/24;
figure(1);
subplot(1,3,1)
for k=1:5:length(jpgfiles)
    i=i+1;
    fillPath(i,:) = fullfile(folderpath,jpgfiles(k).name);
    seq_no = fullfile(folderpath,jpgfiles(k).name);
    disp(strcat('Image: ',seq_no,': '));
    img = imread(seq_no);
    
    img =  imresize(img,0.2);

    gray_img = im2gray(img);
    imshow(gray_img)

    [center,radius] = imfindcircles(gray_img,[40 140],'ObjectPolarity','dark');
    if isempty(center)==1
        disp('center not found');
        break;
    else
        center_traj(i,:) = center;
        disp('center found');
        if i>1
            realtime(i) = realtime(i-1) + delt; %in seconds
            velz(i) = (center_traj(i,2) - center_traj(i-1,2))/delt;
        end
    end

    viscircles(center,radius,'EdgeColor','b');
    rectangle('Position',[center 10 10])
    plot(center(1,1),center(1,2),'r*')
    hold on;
    line(center_traj(:,1),center_traj(:,2))
    pause(0.001)
    compt(i+1) = cputime - compt(i);
end
hold off
tEnd = cputime - tStart - 0.001*i;

fprintf('Computataion time: %d seconds \n',tEnd)


%% section2
te = k/24;
subplot(1,3,2);
plot(realtime,center_traj(:,2),'r')
xlim([0 te])
ylim([50 250])
xlabel('time')
ylabel('Height')
title("Height vs Time")

subplot(1,3,3);
plot(realtime,velz,'b')
xlim([0 te])
ylim([-20 30])
xlabel('time')
ylabel('Velocity')
title("Velocity vs Time")

%plot moving average of velocity


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