
function updateSumoStep(red, yellow, green)

cmdFile = 'D:\sim\tls_cmd.txt';

if green == 1
    command = 'G';
else
    command = 'R';
end

f = fopen(cmdFile, 'w');

if f ~= -1
    fprintf(f, '%s', command);
    fclose(f);
end

end
