%% Siren_Traffic_Response_Analysis.m
% Single-file MATLAB implementation:
% 1) Initializes the response log.
% 2) Contains the live siren detector (detectSirenStep).
% 3) Contains event logging and response-time analysis.
%
% IMPORTANT:
% - Keep this file named Siren_Traffic_Response_Analysis.m.
% - In the Simulink MATLAB Function block, call:
%       isEmergency = Siren_Traffic_Response_Analysis('detect', newAudio);
% - At the exact point where MATLAB sends the traffic command, call:
%       Siren_Traffic_Response_Analysis('event','COMMAND_SENT');
% - SUMO_GREEN must be logged by the Python bridge only AFTER TraCI confirms
%   that the traffic-light state is actually green:
%       (from Python) append: SUMO_GREEN,<UTC timestamp in milliseconds>
%   A MATLAB-side guess cannot measure the actual SUMO application time.

clear; clc;

MODEL_PATH = 'D:\project4\trainedSirenModel.mat';
LOG_FILE   = 'D:\sim\response_log.csv';

if ~isfile(MODEL_PATH)
    error('Model file not found: %s', MODEL_PATH);
end

if ~isfolder(fileparts(LOG_FILE))
    mkdir(fileparts(LOG_FILE));
end

% Start a fresh measurement session.
if isfile(LOG_FILE)
    delete(LOG_FILE);
end
fid = fopen(LOG_FILE, 'w');
if fid < 0
    error('Cannot create response log: %s', LOG_FILE);
end
fprintf(fid, 'Event,Timestamp_ms\n');
fclose(fid);

fprintf('\nResponse logging initialized.\n');
fprintf('Log file: %s\n', LOG_FILE);
fprintf('Model: %s\n\n', MODEL_PATH);

% To analyze the log later, run:
% Siren_Traffic_Response_Analysis('analyze')

%% ====================== MAIN FUNCTION ======================
function varargout = Siren_Traffic_Response_Analysis(action, varargin)
% Supported actions:
%   'detect', audioFrame  -> returns 0/1 emergency decision
%   'event', eventName    -> logs COMMAND_SENT or SUMO_GREEN
%   'analyze'             -> plots response delays from the CSV

    if nargin < 1
        error('Specify action: detect, event, or analyze.');
    end

    action = lower(string(action));

    switch action
        case "detect"
            if numel(varargin) ~= 1
                error('Use: Siren_Traffic_Response_Analysis(''detect'', audioFrame)');
            end
            varargout{1} = localDetectSirenStep(varargin{1});

        case "event"
            if numel(varargin) ~= 1
                error('Use: Siren_Traffic_Response_Analysis(''event'', eventName)');
            end
            eventName = upper(string(varargin{1}));
            if ~any(eventName == ["COMMAND_SENT", "SUMO_GREEN"])
                error('Event must be COMMAND_SENT or SUMO_GREEN.');
            end
            localLogEvent(char(eventName));

        case "analyze"
            localAnalyzeLog();

        otherwise
            error('Unknown action. Use detect, event, or analyze.');
    end
end

%% ====================== LIVE SIREN DETECTOR ======================
function isEmergency = localDetectSirenStep(newAudio)

    persistent trainedNet detectionThreshold consecutiveRequired ...
        hpFilt audioBuffer consecutiveCount isInitialized ...
        hFig hImg hBar hStatus numFrames previousEmergency

    newAudio = double(newAudio(:));

    if isempty(isInitialized)
        modelPath = 'D:\project4\trainedSirenModel.mat';

        if ~isfile(modelPath)
            error('Model file not found: %s', modelPath);
        end

        modelData = load(modelPath);
        trainedNet = modelData.trainedNet;

        detectionThreshold = 0.050;
        consecutiveRequired = 3;

        fsTarget = 22050;
        winSamples = 66150;

        hpFilt = designfilt('highpassiir', ...
            'FilterOrder', 6, ...
            'PassbandFrequency', 400, ...
            'PassbandRipple', 0.5, ...
            'SampleRate', fsTarget);

        audioBuffer = zeros(winSamples, 1);
        consecutiveCount = 0;
        previousEmergency = false;

        % Live monitor
        numFrames = 319;
        hFig = figure( ...
            'Name', 'AI Ambulance Siren Detection - Live Monitor', ...
            'NumberTitle', 'off', ...
            'Color', [0.12 0.12 0.12], ...
            'Position', [100 100 1000 650]);

        ax1 = subplot(2,1,1);
        initialSpec = zeros(64, numFrames);
        hImg = imagesc(ax1, initialSpec);
        axis(ax1, 'xy');
        colormap(ax1, turbo);
        colorbar(ax1);
        title(ax1, 'Live Mel Spectrogram', 'Color', 'w', 'FontSize', 13);
        xlabel(ax1, 'Time Frames', 'Color', 'w');
        ylabel(ax1, 'Mel Bands', 'Color', 'w');
        set(ax1, 'Color', [0.1 0.1 0.1], 'XColor', 'w', 'YColor', 'w');
        caxis(ax1, [-80 20]);

        ax2 = subplot(2,1,2);
        hBar = bar(ax2, 0, 0.8);
        hBar.FaceColor = [0.2 0.6 0.2];
        hold(ax2, 'on');
        yline(ax2, detectionThreshold * 100, '--y', ...
            sprintf('Threshold = %.1f%%', detectionThreshold * 100), ...
            'LineWidth', 2, ...
            'LabelHorizontalAlignment', 'right', ...
            'LabelVerticalAlignment', 'bottom');
        hold(ax2, 'off');
        ylim(ax2, [0 100]);
        xlim(ax2, [-1 1]);
        ylabel(ax2, 'Siren Probability (%)', 'Color', 'w');
        title(ax2, 'AI Detection Confidence', 'Color', 'w', 'FontSize', 13);
        set(ax2, 'Color', [0.1 0.1 0.1], 'XColor', 'w', 'YColor', 'w');
        hStatus = title(ax2, 'Initializing AI Detection...', 'Color', 'w');

        isInitialized = true;
        fprintf('\nAI System Initialized Successfully!\n');
        fprintf('High Pass Filter: 400 Hz\n');
        fprintf('Detection Threshold: %.3f\n\n', detectionThreshold);
    end

    % Filtering
    filteredAudio = filter(hpFilt, newAudio);
    filteredAudio = filteredAudio(:);

    % FIFO buffer
    frameLen = length(filteredAudio);
    if frameLen >= length(audioBuffer)
        audioBuffer = filteredAudio(end-length(audioBuffer)+1:end);
    else
        audioBuffer = [audioBuffer(frameLen+1:end); filteredAudio];
    end

    % Energy gate
    minEnergyThreshold = 0.008;
    signalEnergy = rms(audioBuffer);

    if signalEnergy < minEnergyThreshold
        consecutiveCount = max(0, consecutiveCount - 1);
        isEmergency = 0;

        % Reset edge detector after the siren has ended.
        previousEmergency = false;

        if ~isempty(hBar) && isgraphics(hBar)
            set(hBar, 'YData', 0, 'FaceColor', [0.2 0.6 0.2]);
        end
        if ~isempty(hStatus) && isgraphics(hStatus)
            set(hStatus, 'String', sprintf('SILENCE - Energy: %.4f', signalEnergy), ...
                'Color', [0.2 0.8 0.2]);
        end
        drawnow limitrate;
        fprintf('Silence | Energy: %.4f | Counter: %d\n', ...
            signalEnergy, consecutiveCount);
        return;
    end

    % Mel spectrogram
    fsTarget = 22050;
    S = melSpectrogram(audioBuffer, fsTarget, ...
        'Window', hamming(round(0.030 * fsTarget), 'periodic'), ...
        'OverlapLength', round(0.015 * fsTarget), ...
        'NumBands', 64, ...
        'FrequencyRange', [50 8000]);

    feat = single(10 * log10(S + eps));
    featInput = reshape(feat, [64, size(feat, 2), 1]);

    % CNN prediction
    scores = predict(trainedNet, featInput);
    pSiren = double(scores(1));

    % Leaky counter
    if pSiren >= detectionThreshold
        consecutiveCount = min(5, consecutiveCount + 1);
    else
        consecutiveCount = max(0, consecutiveCount - 1);
    end

    % Final decision
    if consecutiveCount >= consecutiveRequired
        isEmergency = 1;
        fprintf('SIREN DETECTED! | Probability: %.1f%% | Counter: %d\n', ...
            pSiren * 100, consecutiveCount);
    else
        isEmergency = 0;
        fprintf('Normal / Noise | Probability: %.1f%% | Counter: %d\n', ...
            pSiren * 100, consecutiveCount);
    end

    % Log only the transition from normal to detected.
    if isEmergency == 1 && ~previousEmergency
        localLogEvent('SIREN_DETECTED');
        fprintf('>>> SIREN EVENT LOGGED <<<\n');
    end
    previousEmergency = logical(isEmergency);

    % Live graph update
    pct = pSiren * 100;
    featDisp = feat(:, 1:min(size(feat, 2), numFrames));
    if size(featDisp, 2) < numFrames
        featDisp = [featDisp, ...
            zeros(64, numFrames-size(featDisp,2), 'single')];
    end

    if isgraphics(hImg)
        set(hImg, 'CData', featDisp);
    end
    if isgraphics(hBar)
        set(hBar, 'YData', pct);
    end

    if consecutiveCount >= consecutiveRequired
        if isgraphics(hBar), set(hBar, 'FaceColor', [0.85 0.1 0.1]); end
        if isgraphics(hStatus)
            set(hStatus, 'String', sprintf('SIREN DETECTED! (%.1f%%)', pct), ...
                'Color', [0.85 0.0 0.0]);
        end
    elseif pSiren >= detectionThreshold
        if isgraphics(hBar), set(hBar, 'FaceColor', [0.95 0.6 0.1]); end
        if isgraphics(hStatus)
            set(hStatus, 'String', sprintf('SUSPECTED (%.1f%%) - Counter: %d/%d', ...
                pct, consecutiveCount, consecutiveRequired), ...
                'Color', [0.8 0.4 0.0]);
        end
    else
        if isgraphics(hBar), set(hBar, 'FaceColor', [0.2 0.6 0.2]); end
        if isgraphics(hStatus)
            set(hStatus, 'String', sprintf('NORMAL / NOISE (%.1f%%)', pct), ...
                'Color', [0.1 0.5 0.1]);
        end
    end
    drawnow limitrate;
end

%% ====================== EVENT LOGGER ======================
function localLogEvent(eventName)
    logFile = 'D:\sim\response_log.csv';

    if ~isfolder(fileparts(logFile))
        mkdir(fileparts(logFile));
    end

    writeHeader = ~isfile(logFile);
    fid = fopen(logFile, 'a');
    if fid == -1
        warning('Cannot open response log: %s', logFile);
        return;
    end

    if writeHeader
        fprintf(fid, 'Event,Timestamp_ms\n');
    end

    % UTC Unix timestamp in milliseconds.
    timestamp = posixtime(datetime('now', 'TimeZone', 'UTC')) * 1000;
    fprintf(fid, '%s,%.3f\n', eventName, timestamp);
    fclose(fid);
end

%% ====================== RESPONSE ANALYSIS ======================
function localAnalyzeLog()
    logFile = 'D:\sim\response_log.csv';

    if ~isfile(logFile)
        error('Response log not found: %s', logFile);
    end

    T = readtable(logFile, 'TextType', 'string');
    requiredEvents = ["SIREN_DETECTED", "COMMAND_SENT", "SUMO_GREEN"];

    for k = 1:numel(requiredEvents)
        if ~any(T.Event == requiredEvents(k))
            error('Missing event %s. Check the Simulink/Python event hook.', ...
                requiredEvents(k));
        end
    end

    % Pair each detection with the first subsequent command and green event.
    sirenTimes = T.Timestamp_ms(T.Event == "SIREN_DETECTED");
    commandTimes = T.Timestamp_ms(T.Event == "COMMAND_SENT");
    greenTimes = T.Timestamp_ms(T.Event == "SUMO_GREEN");

    detectionToCommand = [];
    commandToGreen = [];
    totalResponse = [];
    usedCommand = false(size(commandTimes));
    usedGreen = false(size(greenTimes));

    for i = 1:numel(sirenTimes)
        c = find(~usedCommand & commandTimes >= sirenTimes(i), 1, 'first');
        if isempty(c), continue; end

        g = find(~usedGreen & greenTimes >= commandTimes(c), 1, 'first');
        if isempty(g), continue; end

        usedCommand(c) = true;
        usedGreen(g) = true;

        detectionToCommand(end+1,1) = commandTimes(c) - sirenTimes(i); %#ok<AGROW>
        commandToGreen(end+1,1) = greenTimes(g) - commandTimes(c); %#ok<AGROW>
        totalResponse(end+1,1) = greenTimes(g) - sirenTimes(i); %#ok<AGROW>
    end

    if isempty(totalResponse)
        error('No complete SIREN_DETECTED -> COMMAND_SENT -> SUMO_GREEN event sequence found.');
    end

    Results = table((1:numel(totalResponse))', detectionToCommand, ...
        commandToGreen, totalResponse, ...
        'VariableNames', {'Trial','Detection_to_Command_ms', ...
        'Command_to_Green_ms','Total_Response_ms'});

    disp(Results);
    fprintf('\nAverage Detection-to-Command: %.3f ms\n', mean(detectionToCommand));
    fprintf('Average Command-to-Green:     %.3f ms\n', mean(commandToGreen));
    fprintf('Average Total Response:       %.3f ms\n', mean(totalResponse));

    figure('Name', 'Ambulance Traffic Response Time', ...
        'Color', 'w', 'Position', [150 150 1000 500]);

    bar([detectionToCommand, commandToGreen, totalResponse], 'grouped');
    grid on;
    xlabel('Test Number');
    ylabel('Time (ms)');
    title('Ambulance Siren Detection and Traffic-Light Response');
    legend('Detection to Command', 'Command to Green', ...
        'Total Response', 'Location', 'best');

    writetable(Results, 'D:\sim\response_analysis.csv');
    fprintf('\nAnalysis saved to D:\\sim\\response_analysis.csv\n');
end
