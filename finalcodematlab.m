clear
clc

port = "COM5";     % change if needed
baud = 115200;

s = serialport(port,baud);
configureTerminator(s,"LF");
flush(s);

xres = 160;
yres = 120;
expected = xres*yres*2;

figure

while true

    line = readline(s);

    if contains(line,"FRAME_START")

        frame = read(s, expected, "uint8");

        img = zeros(yres,xres,'uint16');

        for x = 0:xres-1
            for y = 0:yres-1

                i = bitshift((y*xres + x),1) + 1;

                pixel = frame(i) + bitshift(frame(i+1),8);

                img(y+1,x+1) = pixel;

            end
        end

        imshow(img,[])
        drawnow

        readline(s); % FRAME_END
    end
end
