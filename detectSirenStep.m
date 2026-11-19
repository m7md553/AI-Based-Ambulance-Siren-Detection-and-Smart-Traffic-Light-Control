
function isEmergency = detectSirenStep(newAudio)
% =========================================================
%clear detectSirenStep
%bdclose all
%close all
%clc
% =========================================================
    % Persistent Variables
    persistent trainedNet detectionThreshold consecutiveRequired ...
               hpFilt audioBuffer consecutiveCount isInitialized ...
               hFig hImg hBar hStatus numFrames

    % Convert audio to double column
    newAudio = double(newAudio(:));
    

    % =========================================================
    % 1. INITIALIZATION
    % =========================================================
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

        % =====================================================
        % 2. CREATE LIVE GRAPH WINDOW (ONCE)
        % =====================================================

        numFrames = 319;

        hFig = figure( ...
            'Name', 'AI Ambulance Siren Detection - Live Monitor', ...
            'NumberTitle', 'off', ...
            'Color', [0.12 0.12 0.12], ...
            'Position', [100 100 1000 650]);

        % Spectrogram Axes
        ax1 = subplot(2,1,1);

        initialSpec = zeros(64, numFrames);

        hImg = imagesc(ax1, initialSpec);

        axis(ax1, 'xy');

        colormap(ax1, turbo);

        colorbar(ax1);

        title(ax1, 'Live Mel Spectrogram', ...
            'Color', 'w', 'FontSize', 13);

        xlabel(ax1, 'Time Frames', 'Color', 'w');
        ylabel(ax1, 'Mel Bands', 'Color', 'w');

        set(ax1, ...
            'Color', [0.1 0.1 0.1], ...
            'XColor', 'w', ...
            'YColor', 'w');

        caxis(ax1, [-80 20]);

        % Probability Bar Axes
        ax2 = subplot(2,1,2);

        hBar = bar(ax2, 0, 0.8);

        hBar.FaceColor = [0.2 0.6 0.2];
        hold(ax2, 'on');
        hThreshold = yline(ax2, detectionThreshold * 100, ...
             '--y', ...
             sprintf('Threshold = %.1f%%', detectionThreshold * 100), ...
             'LineWidth', 2, ...
             'LabelHorizontalAlignment', 'right', ...
             'LabelVerticalAlignment', 'bottom');
        hold(ax2, 'off');

        ylim(ax2, [0 100]);
        xlim(ax2, [-1 1]);

        ylabel(ax2, 'Siren Probability (%)', 'Color', 'w');

        title(ax2, 'AI Detection Confidence', ...
            'Color', 'w', 'FontSize', 13);

        set(ax2, ...
            'Color', [0.1 0.1 0.1], ...
            'XColor', 'w', ...
            'YColor', 'w');

        % Status Text
        hStatus = title(ax2, ...
            'Initializing AI Detection...', ...
            'Color', 'w');

        isInitialized = true;

        fprintf('\nAI System Initialized Successfully!\n');
        fprintf('High Pass Filter: 400 Hz\n');
        fprintf('Detection Threshold: %.3f\n\n', detectionThreshold);

    end

    % =========================================================
    % 3. AUDIO FILTERING
    % =========================================================

    filteredAudio = filter(hpFilt, newAudio);
    filteredAudio = filteredAudio(:);

    % =========================================================
    % 4. FIFO BUFFER UPDATE
    % =========================================================

    frameLen = length(filteredAudio);

    if frameLen >= length(audioBuffer)
        audioBuffer = filteredAudio(end-length(audioBuffer)+1:end);
    else
        audioBuffer = [audioBuffer(frameLen+1:end); filteredAudio];
    end

    % =========================================================
    % 5. VOICE ACTIVITY DETECTION
    % =========================================================

    minEnergyThreshold = 0.008;

    signalEnergy = rms(audioBuffer);

    if signalEnergy < minEnergyThreshold

        consecutiveCount = max(0, consecutiveCount - 1);

        isEmergency = double(0);

        % Update graph during silence
        if ~isempty(hBar) && isgraphics(hBar)
            set(hBar, 'YData', 0);
        end    

        if ~isempty(hBar) && isgraphics(hBar)
            set(hBar, 'FaceColor', [0.2 0.6 0.2]);
        end

        set(hStatus, ...
            'String', sprintf('SILENCE - Energy: %.4f', signalEnergy), ...
            'Color', [0.2 0.8 0.2]);

        drawnow limitrate;

        fprintf('Silence | Energy: %.4f | Counter: %d\n', ...
            signalEnergy, consecutiveCount);

        return;

    end

    % =========================================================
    % 6. MEL SPECTROGRAM FEATURE EXTRACTION
    % =========================================================

    fsTarget = 22050;

    S = melSpectrogram(audioBuffer, fsTarget, ...
        'Window', hamming(round(0.030 * fsTarget), 'periodic'), ...
        'OverlapLength', round(0.015 * fsTarget), ...
        'NumBands', 64, ...
        'FrequencyRange', [50 8000]);

    feat = single(10 * log10(S + eps));

    featInput = reshape(feat, [64, size(feat, 2), 1]);

    % =========================================================
    % 7. CNN PREDICTION
    % =========================================================

    scores = predict(trainedNet, featInput);

    pSiren = double(scores(1));

    % =========================================================
    % 8. LEAKY COUNTER
    % =========================================================

    if pSiren >= detectionThreshold

        consecutiveCount = min(5, consecutiveCount + 1);

    else

        consecutiveCount = max(0, consecutiveCount - 1);

    end

    % =========================================================
    % 9. FINAL EMERGENCY DECISION
    % =========================================================

    if consecutiveCount >= consecutiveRequired

        isEmergency = double(1);

        fprintf(['SIREN DETECTED! | Probability: %.1f%% ' ...
                 '| Counter: %d\n'], ...
                 pSiren * 100, consecutiveCount);

    else

        isEmergency = double(0);

        fprintf(['Normal / Noise | Probability: %.1f%% ' ...
                 '| Counter: %d\n'], ...
                 pSiren * 100, consecutiveCount);

    end

    % =========================================================
    % 10. LIVE GRAPH UPDATE
    % =========================================================

    pct = pSiren * 100;

    % Update Spectrogram
    featDisp = feat(:, 1:min(size(feat, 2), numFrames));

    if size(featDisp, 2) < numFrames

        featDisp = [featDisp, ...
            zeros(64, numFrames-size(featDisp,2), 'single')];

    end

    set(hImg, 'CData', featDisp);

    % Update Probability Bar
    set(hBar, 'YData', pct);

    % Update Status and Colors
    if consecutiveCount >= consecutiveRequired

        set(hBar, 'FaceColor', [0.85 0.1 0.1]);

        set(hStatus, ...
            'String', sprintf('SIREN DETECTED! (%.1f%%)', pct), ...
            'Color', [0.85 0.0 0.0]);

    elseif pSiren >= detectionThreshold

        set(hBar, 'FaceColor', [0.95 0.6 0.1]);

        set(hStatus, ...
            'String', sprintf('SUSPECTED (%.1f%%) - Counter: %d/%d', ...
            pct, consecutiveCount, consecutiveRequired), ...
            'Color', [0.8 0.4 0.0]);

    else

        set(hBar, 'FaceColor', [0.2 0.6 0.2]);

        set(hStatus, ...
            'String', sprintf('NORMAL / NOISE (%.1f%%)', pct), ...
            'Color', [0.1 0.5 0.1]);

    end

    % Fast Graph Refresh
    drawnow limitrate;

end
