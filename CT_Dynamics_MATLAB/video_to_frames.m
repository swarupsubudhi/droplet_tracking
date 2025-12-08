% Video to Frame Extraction Script
% Author: Swarup
% Description: Extracts frames from a video and saves them as images

% --- User Inputs ---
videoPath = 'C:\Research_Files_Swarup\R11-DropsCT\Expt_Data\Raw_Data_Videos\output_droplet.mp4';  % Full path to the video file
outputFolder = 'C:\Research_Files_Swarup\R11-DropsCT\Expt_Data\Output\test_sequence\';         % Folder to save extracted frames

% --- Create output folder if it doesn't exist ---
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

% --- Read video ---
videoObj = VideoReader(videoPath);
frameCount = 0;

while hasFrame(videoObj)
    frame = readFrame(videoObj);
    frameCount = frameCount + 1;
    
    % Construct filename
    filename = fullfile(outputFolder, sprintf('frame_%04d.jpg', frameCount));
    
    % Save frame as image
    imwrite(frame, filename);
end

fprintf('Extraction complete. %d frames saved to %s\n', frameCount, outputFolder);