% Add path containing the pretrained models.
addpath('models');

% Load YOLOv8 model
modelName = 'yolov8s';
data = load([modelName, '.mat']);
detector = data.yolov8Net;
classNames = helper.getCOCOClassNames;
numClasses = size(classNames, 1);

% Define robot position and ROI 1
robotCenter = [1024 / 2, 640 / 2]; % Assuming image size of 1024x640, adjust based on your camera resolution
robotWidth = 200; % Fixed width of the robot region
robotHeight = 400; % Fixed height of the robot region
robotROI1 = [robotCenter(1) - robotWidth / 2, robotCenter(2) - robotHeight / 2, robotWidth, robotHeight];

% Calculate ROI 2 based on max arm length
marginWidth = 100; % Margin for width
marginHeight = 50; % Margin for height
robotROI2Width = robotWidth + marginWidth * 2; % Include margin on both sides
robotROI2Height = robotHeight + marginHeight * 2; % Include margin on top and bottom
robotROI2Center = robotCenter; % Use the same center as ROI 1

% Calculate the top-left corner of ROI 2 based on its center
robotROI2TopLeft = robotROI2Center - [robotROI2Width / 2, robotROI2Height / 2];

% Define ROI 2 using its top-left corner and calculated width and height
robotROI2 = [robotROI2TopLeft, robotROI2Width, robotROI2Height];

% Initialize webcam
cam = webcam;

% Load sound for alert
alertSound = audioread('alert.wav'); % Replace 'alert.wav' with your sound file
player = audioplayer(alertSound, 44100);

% Open a figure for displaying the results
figure;

% Main loop for real-time detection
while true
    % Capture a frame from the camera
    frame = snapshot(cam);
    
    % Clear previous bounding boxes and labels
    hold off;
    
    % Perform object detection on the captured frame
    executionEnvironment = 'auto';
    [bboxes, scores, labelIds] = detectYOLOv8(detector, frame, numClasses, executionEnvironment);
    labels = classNames(labelIds);

    % Filter out "person" class detections with score > 0.90
    personIdx = find(strcmp(classNames, 'person'));
    personBboxes = bboxes(labelIds == personIdx & scores > 0.90, :);
    personScores = scores(labelIds == personIdx & scores > 0.90);

    % Calculate distance from camera to person
    H_robot = 400; % Height of robot in image in pixels
    D_robot = 5; % Distance from camera to robot in meters
    D = zeros(size(personBboxes, 1), 1);
    for i = 1:size(personBboxes, 1)
        H_person = personBboxes(i, 4); % Height of person in image in pixels
        D(i) = (H_robot * D_robot) / H_person; % Distance from camera to person
    end

    % Draw ROI 1 on the frame
    detectedImg = insertShape(frame, 'Rectangle', robotROI1, 'Color', 'red', 'LineWidth', 3);

    % Draw ROI 2 on the frame
    detectedImg = insertShape(detectedImg, 'Rectangle', robotROI2, 'Color', 'blue', 'LineWidth', 3);

    % Add text for ROI 1
    detectedImg = insertText(detectedImg, [robotROI1(1), robotROI1(2)-30], 'Vung nguy hiem', 'TextColor', 'white', 'FontSize', 18, 'BoxColor', 'red', 'AnchorPoint', 'LeftTop');

    % Add text for ROI 2
    detectedImg = insertText(detectedImg, [robotROI2(1), robotROI2(2)-30], 'Vung an toan', 'TextColor', 'white', 'FontSize', 18, 'BoxColor', 'blue', 'AnchorPoint', 'LeftTop');

    % Initialize alert flag
    playAlert = false;
    for i = 1:size(personBboxes, 1)
        bbox = personBboxes(i, :);
        bboxBottomLeft = bbox(1:2);
        bboxTopRight = [bbox(1) + bbox(3), bbox(2)];
        
        % Check if the person is inside ROI 1 first (more restrictive)
        if bboxOverlapRatio(bbox, robotROI1) > 0
            % Person bbox intersects with ROI 1 (red)
            detectedImg = insertObjectAnnotation(detectedImg, 'rectangle', bbox, ...
                strcat('person: ', compose('%.2f', personScores(i))), 'Color', 'red');
            detectedImg = insertText(detectedImg, bboxBottomLeft, 'Dangerous zone', 'TextColor', 'red', 'FontSize', 18, 'BoxColor', 'red', 'AnchorPoint', 'LeftTop');
            detectedImg = insertText(detectedImg, bboxTopRight, sprintf('Distance: %.2f m', D(i)), 'TextColor', 'yellow', 'FontSize', 18, 'BoxColor', 'black', 'AnchorPoint', 'RightTop');
            playAlert = true;
        elseif bboxOverlapRatio(bbox, robotROI2) > 0
            % Person bbox intersects with ROI 2 but not ROI 1 (blue)
            detectedImg = insertObjectAnnotation(detectedImg, 'rectangle', bbox, ...
                strcat('person: ', compose('%.2f', personScores(i))), 'Color', 'blue');
            detectedImg = insertText(detectedImg, bboxBottomLeft, 'Unsafe zone', 'TextColor', 'blue', 'FontSize', 18, 'BoxColor', 'blue', 'AnchorPoint', 'LeftTop');
            detectedImg = insertText(detectedImg, bboxTopRight, sprintf('Distance: %.2f m', D(i)), 'TextColor', 'yellow', 'FontSize', 18, 'BoxColor', 'black', 'AnchorPoint', 'RightTop');
            playAlert = true;

        else
            % Person bbox does not intersect with either ROI (green)
            detectedImg = insertObjectAnnotation(detectedImg, 'rectangle', bbox, ...
                strcat('person: ', compose('%.2f', personScores(i))), 'Color', 'green');
            detectedImg = insertText(detectedImg, bboxBottomLeft, 'Safety zone', 'TextColor', 'green', 'FontSize', 18, 'BoxColor', 'green', 'AnchorPoint', 'LeftTop');
            detectedImg = insertText(detectedImg, bboxTopRight, sprintf('Distance: %.2f m', D(i)), 'TextColor', 'yellow', 'FontSize', 18, 'BoxColor', 'black', 'AnchorPoint', 'RightTop');
        end
    end

    % Play alert sound if in dangerous or unsafe zone
    if playAlert
        play(player);
    end

    % Display the annotated frame
    imshow(detectedImg);

    % Exit the loop if 'q' is pressed
    if strcmpi(get(gcf, 'currentcharacter'), 'q')
        break;
    end
end

% Clean up
clear cam;
