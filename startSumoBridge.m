
function startSumoBridge()

projectDir = 'D:\sim';
pythonExe = 'C:\Users\ma945\AppData\Local\Programs\Python\Python311\python.exe';
bridgeFile = fullfile(projectDir, 'run_sumo_bridge.py');
cmdFile = fullfile(projectDir, 'tls_cmd.txt');

% تجهيز حالة الإشارة الطبيعية
f = fopen(cmdFile, 'w');
if f ~= -1
    fprintf(f, 'R');
    fclose(f);
end

% التأكد من وجود الملفات
assert(isfile(bridgeFile), 'Python Bridge file not found.');
assert(isfile(pythonExe), 'Python executable not found.');

% تشغيل SUMO Bridge في نافذة منفصلة
cmd = sprintf('start "SUMO Bridge" "%s" "%s"', ...
              pythonExe, bridgeFile);
system(cmd);

end
