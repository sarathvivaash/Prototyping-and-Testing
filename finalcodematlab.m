clear
clc

port = "COM5";     % change if needed
baud = 921600;      % Must match Arduino Serial.begin(921600)

s = serialport(port,baud);
configureTerminator(s,"LF");
flush(s);

xres = 160;
yres = 120;
expected = xres*yres*2;

% ===== RED LASER DETECTION PARAMETERS (MANUAL CALIBRATION) =====
RED_MIN_THRESHOLD = 220;        % Minimum red intensity (0-255)
GREEN_MAX_THRESHOLD = 50;       % Maximum green intensity (0-255)
BLUE_MAX_THRESHOLD = 50;        % Maximum blue intensity (0-255)
% ================================================================

% Increase timeout for serial communication
s.Timeout = 5; % seconds

figure
frame_count = 0;

while true
    try
        % Stage 1: Wait for FRAME_START marker
        fprintf('[WAITING] Listening for FRAME_START...\n');
        line = readline(s);
        
        % Check if line is valid text
        if ~isstring(line) && ~ischar(line)
            fprintf('[ERROR] Invalid line type received\n');
            continue;
        end
        
        line = string(line); % Convert to string for contains check
        
        if ~contains(line,"FRAME_START")
            fprintf('[DEBUG] Received: %s\n', line);
            continue;
        end
        
        frame_count = frame_count + 1;
        fprintf('\n=== FRAME %d START ===\n', frame_count);
        fprintf('[STAGE 1] FRAME_START marker detected\n');
        
        % Stage 2: Read raw frame data
        fprintf('[STAGE 2] Reading %d bytes of frame data...\n', expected);
        frame = read(s, expected, "uint8");
        fprintf('[STAGE 2] ✓ Received %d bytes\n', length(frame));
        
        % Stage 3: Convert raw data to image matrix
        fprintf('[STAGE 3] Converting raw data to image matrix...\n');
        img = zeros(yres,xres,'uint16');

        for x = 0:xres-1
            for y = 0:yres-1
                i = bitshift((y*xres + x),1) + 1;
                pixel = frame(i) + bitshift(frame(i+1),8);
                img(y+1,x+1) = pixel;
            end
        end
        fprintf('[STAGE 3] ✓ Image matrix created (%d x %d)\n', yres, xres);
        
        % Stage 4: Convert RGB565 to RGB channels
        fprintf('[STAGE 4] Converting RGB565 to RGB channels...\n');
        red_channel = bitshift(bitand(img, 0xF800), -11) * 255 / 31;
        green_channel = bitshift(bitand(img, 0x07E0), -5) * 255 / 63;
        blue_channel = bitand(img, 0x001F) * 255 / 31;
        fprintf('[STAGE 4] ✓ RGB channels extracted\n');
        fprintf('          Red range: [%.1f - %.1f]\n', min(red_channel(:)), max(red_channel(:)));
        fprintf('          Green range: [%.1f - %.1f]\n', min(green_channel(:)), max(green_channel(:)));
        fprintf('          Blue range: [%.1f - %.1f]\n', min(blue_channel(:)), max(blue_channel(:)));

        % Stage 4.5: Plot pipeline visualization
        fprintf('[STAGE 4.5] Creating pipeline visualization...\n');
        figure('Name', sprintf('Frame %d - Pipeline Analysis', frame_count));
        
        % Plot RGB channels
        subplot(2, 3, 1);
        imshow(uint8(red_channel), []);
        title(sprintf('Red Channel\n(Range: %.0f - %.0f)', min(red_channel(:)), max(red_channel(:))));
        
        subplot(2, 3, 2);
        imshow(uint8(green_channel), []);
        title(sprintf('Green Channel\n(Range: %.0f - %.0f)', min(green_channel(:)), max(green_channel(:))));
        
        subplot(2, 3, 3);
        imshow(uint8(blue_channel), []);
        title(sprintf('Blue Channel\n(Range: %.0f - %.0f)', min(blue_channel(:)), max(blue_channel(:))));
        
        % Stage 5: Create red color mask
        fprintf('[STAGE 5] Applying red color thresholds (R>%.0f, G<%.0f, B<%.0f)...\n', ...
            RED_MIN_THRESHOLD, GREEN_MAX_THRESHOLD, BLUE_MAX_THRESHOLD);
        red_mask = (red_channel >= RED_MIN_THRESHOLD) & ...
                   (green_channel >= GREEN_MAX_THRESHOLD) & ...
                   (blue_channel >= BLUE_MAX_THRESHOLD);
        red_pixel_count = sum(red_mask(:));
        fprintf('[STAGE 5] ✓ Red mask created with %d red pixels detected\n', red_pixel_count);
        
        % Plot thresholds and final mask
        subplot(2, 3, 4);
        imshow(uint8(red_channel >= RED_MIN_THRESHOLD), []);
        title(sprintf('R >= %.0f\n(%d pixels)', RED_MIN_THRESHOLD, sum(red_channel(:) >= RED_MIN_THRESHOLD)));
        
        subplot(2, 3, 5);
        imshow(uint8(green_channel <= GREEN_MAX_THRESHOLD & blue_channel <= BLUE_MAX_THRESHOLD), []);
        title(sprintf('G <= %.0f & B <= %.0f', GREEN_MAX_THRESHOLD, BLUE_MAX_THRESHOLD));
        
        subplot(2, 3, 6);
        imshow(uint8(red_mask), []);
        title(sprintf('FINAL MASK\n(%d red pixels)', red_pixel_count));
        
        drawnow;

        % Stage 6: Calculate centroid
        fprintf('[STAGE 6] Calculating centroid of red pixels...\n');
        [rows, cols] = find(red_mask);
        
        if ~isempty(rows)
            centroid_y = mean(rows);
            centroid_x = mean(cols);
            
            % Image center
            center_x = xres / 2;
            center_y = yres / 2;
            
            % Pixel distance from center
            pixel_distance = sqrt((centroid_x - center_x)^2 + (centroid_y - center_y)^2);
            
            fprintf('[STAGE 6] ✓ Centroid found at (%.2f, %.2f)\n', centroid_x, centroid_y);
            fprintf('[STAGE 7] Distance from center: %.2f pixels\n', pixel_distance);
            
            % Stage 8: Display image
            fprintf('[STAGE 8] Rendering image with overlays...\n');
            img_display = uint8(red_channel);
            imshow(img_display, [])
            hold on
            
            % Plot centroid
            plot(centroid_x, centroid_y, 'y+', 'MarkerSize', 15, 'LineWidth', 2)
            
            % Plot image center
            plot(center_x, center_y, 'g*', 'MarkerSize', 15, 'LineWidth', 2)
            
            % Plot line from center to centroid
            line([center_x centroid_x], [center_y centroid_y], 'Color', 'cyan', 'LineWidth', 1)
            
            hold off
            
            % Display info
            title(sprintf('Red Centroid: (%.1f, %.1f) | Distance: %.2f px | Pixels: %d', ...
                centroid_x, centroid_y, pixel_distance, red_pixel_count))
            
            fprintf('[STAGE 8] ✓ Display updated\n');
        else
            fprintf('[STAGE 6] ✗ No red pixels detected - adjust thresholds\n');
            imshow(uint8(red_channel), [])
            title('No red laser detected - adjust thresholds')
        end
        
        % Stage 9: Read FRAME_END marker
        fprintf('[STAGE 9] Reading FRAME_END marker...\n');
        frame_end = readline(s);
        fprintf('[STAGE 9] ✓ Frame complete\n');
        fprintf('=== FRAME %d END ===\n\n', frame_count);
        
        drawnow
        
    catch ME
        fprintf('[ERROR] %s\n', ME.message);
        fprintf('[ERROR] Attempting to recover...\n\n');
        pause(0.5);
    end
end
