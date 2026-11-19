
function logSystemEvent(eventName)

logFile = 'D:\sim\response_log.csv';

timestamp = posixtime(datetime('now','TimeZone','UTC')) * 1000;

writeHeader = ~isfile(logFile);

fid = fopen(logFile,'a');

if fid == -1
    warning('Cannot open response log file.');
    return;
end

if writeHeader
    fprintf(fid,'Event,Timestamp_ms\n');
end

fprintf(fid,'%s,%.3f\n',eventName,timestamp);

fclose(fid);

end
