
function isEmergency = detectSirenStep(newAudio)
% =========================================================
% LIVE SIREN DETECTION USING YAMNET + CUSTOM CNN
% Smooth Spectrogram Display + Reduced Inference Frequency
% =========================================================

    persistent trainedNet netYAM featLayer sirenCol ...
               detectionThreshold consecutiveRequired ...
               hpFilt audioBuffer consecutiveCount ...
               isInitialized hFig hImg hBar hStatus ...
               numFrames nBands processingCounter ...
               processingInterval lastProbability

    newAudio = double(newAudio(:));

    % =====================================================
    % 1. INITIALIZATION
    % =====================================================

    if isempty(isInitialized)

        modelPath = 'D:\sim\Model_YAMNet_NEWCNN\Model_YAMNet_NEWCNN.mat';

        if ~isfile(modelPath)
            error('Model file not found: %s', modelPath);
        end

        modelData = load(modelPath, 'trainedNet', 'classes', 'sirenCol');

        trainedNet = modelData.trainedNet;
        sirenCol = modelData.sirenCol;

        % Load YAMNet
        netYAM = audioPretrainedNetwork("yamnet");

        gapIdx = find(arrayfun(@(l) ...
            isa(l, 'nnet.cnn.layer.GlobalAveragePooling2DLayer'), ...
            netYAM.Layers), 1, 'last');

        featLayer = netYAM.Layers(gapIdx).Name;

        % Detection settings
        detectionThreshold = 0.55;
        consecutiveRequired = 2;

        fsTarget = 22050;
        winSamples = 3 * fsTarget;

        % High Pass Filter
        hpFilt = designfilt('highpassiir', ...
            'FilterOrder', 6, ...
            'PassbandFrequency', 400, ...
            'PassbandRipple', 0.5, ...
            'SampleRate', fsTarget);

        audioBuffer = zeros(winSamples, 1);
        consecutiveCount = 0;

        % Inference interval: 0.6 seconds
        processingInterval = round(0.6 * fsTarget);
        processingCounter = 0;

        lastProbability = 0;

        % =================================================
        % 2. INITIALIZE DISPLAY
        % =================================================

        dummyS = yamnetPreprocess(zeros(winSamples,1), fsTarget);

        [tFrames, nBands] = size(dummyS(:,:,1,1));

        numFrames = tFrames;

        hFig = figure( ...
            'Name', 'Live Siren Detection - YAMNet + CNN', ...
            'NumberTitle', 'off', ...
            'Color', [0.12 0.12 0.12], ...
            'Position', [100 100 1000 650]);

        % Spectrogram Display
        ax1 = subplot(2,1,1);

        hImg = imagesc(ax1, ...
            linspace(0,3,numFrames), ...
            1:nBands, ...
            repmat(-7, nBands, numFrames));

        axis(ax1, 'xy');

        set(hImg, 'Interpolation', 'bilinear');

        colormap(ax1, turbo(256));
        colorbar(ax1);

        caxis(ax1, [-7 3]);

        title(ax1, 'Live YAMNet Mel Spectrogram', ...
            'Color', 'w', 'FontSize', 13);

        xlabel(ax1, 'Time (Seconds)', 'Color', 'w');
        ylabel(ax1, 'Mel Bands', 'Color', 'w');

        set(ax1, ...
            'Color', [0.1 0.1 0.1], ...
            'XColor', 'w', ...
            'YColor', 'w');

        xlim(ax1, [0 3]);
        ylim(ax1, [1 nBands]);

        % Probability Bar
        ax2 = subplot(2,1,2);

        hBar = bar(ax2, 1, 0, 0.35);

        hBar.FaceColor = [0.2 0.6 0.2];

        hold(ax2, 'on');

        yline(ax2, detectionThreshold * 100, ...
            '--y', ...
            sprintf('Threshold = %.0f%%', ...
            detectionThreshold * 100), ...
            'LineWidth', 2);

        hold(ax2, 'off');

        ylim(ax2, [0 100]);
        xlim(ax2, [0.5 1.5]);

        ylabel(ax2, 'Siren Probability (%)', 'Color', 'w');

        set(ax2, ...
            'Color', [0.1 0.1 0.1], ...
            'XColor', 'w', ...
            'YColor', 'w');

        hStatus = title(ax2, ...
            'Initializing AI Detection...', ...
            'Color', 'w', ...
            'FontSize', 13);

        isInitialized = true;

        fprintf('\nYAMNet + CNN Initialized Successfully!\n');
        fprintf('High Pass Filter: 400 Hz\n');
        fprintf('Detection Threshold: %.2f\n', detectionThreshold);
        fprintf('Inference Interval: 0.6 seconds\n\n');

    end

    % =====================================================
    % 3. HIGH PASS FILTER
    % =====================================================

    filteredAudio = filter(hpFilt, newAudio);
    filteredAudio = filteredAudio(:);

    % =====================================================
    % 4. UPDATE AUDIO BUFFER
    % =====================================================

    frameLen = length(filteredAudio);

    if frameLen >= length(audioBuffer)

        audioBuffer = filteredAudio(end-length(audioBuffer)+1:end);

    else

        audioBuffer = [audioBuffer(frameLen+1:end); filteredAudio];

    end

    processingCounter = processingCounter + frameLen;

    % =====================================================
    % 5. FRAME ENERGY / SILENCE DETECTION
    % =====================================================

    minEnergyThreshold = 0.001;

    signalEnergy = rms(filteredAudio);

    % Wait for inference interval
    if processingCounter < processingInterval

        isEmergency = double(consecutiveCount >= consecutiveRequired);
        return;

    end

    processingCounter = 0;

    % Silence handling
    if signalEnergy < minEnergyThreshold

        consecutiveCount = max(0, consecutiveCount - 1);
        lastProbability = 0;

        isEmergency = double(0);

        if isgraphics(hBar)
            set(hBar, 'YData', 0);
            set(hBar, 'FaceColor', [0.2 0.6 0.2]);
        end

        if isgraphics(hImg)
            set(hImg, 'CData', repmat(-7, nBands, numFrames));
        end

        set(hStatus, ...
            'String', sprintf('SILENCE - RMS: %.5f', signalEnergy), ...
            'Color', [0.2 0.8 0.2]);

        drawnow limitrate;

        fprintf('Silence | RMS: %.5f | Counter: %d\n', ...
            signalEnergy, consecutiveCount);

        return;

    end

    % =====================================================
    % 6. AUDIO NORMALIZATION
    % =====================================================

    pkBuffer = max(abs(audioBuffer));

    if pkBuffer < 1e-8

        lastProbability = 0;
        consecutiveCount = max(0, consecutiveCount - 1);
        isEmergency = double(0);
        return;

    end

    audioNorm = audioBuffer / pkBuffer;

    % =====================================================
    % 7. YAMNET PREPROCESSING
    % =====================================================

    S = yamnetPreprocess(audioNorm, 22050);

    if ndims(S) < 4

        S = reshape(S, size(S,1), size(S,2), 1, []);

    end

    % =====================================================
    % 8. YAMNET EMBEDDING EXTRACTION
    % =====================================================

    emb = extractdata(predict(netYAM, ...
        dlarray(single(S), 'SSCB'), ...
        'Outputs', featLayer));

    emb = reshape(emb, 1024, []);

    % =====================================================
    % 9. FEATURE VECTOR
    % =====================================================

    featVec = single([ ...
        mean(emb, 2)', ...
        max(emb, [], 2)' ]);

    % =====================================================
    % 10. CUSTOM CNN PREDICTION
    % =====================================================

    scores = predict(trainedNet, featVec);

    pSiren = double(scores(sirenCol));

    lastProbability = pSiren;

    % =====================================================
    % 11. LEAKY COUNTER
    % =====================================================

    if pSiren >= detectionThreshold

        consecutiveCount = min(consecutiveRequired + 1, ...
            consecutiveCount + 1);

    else

        consecutiveCount = max(0, consecutiveCount - 1);

    end

    % =====================================================
    % 12. EMERGENCY DECISION
    % =====================================================

    isEmergency = double(consecutiveCount >= consecutiveRequired);

    if isEmergency

        fprintf('SIREN DETECTED! | Probability: %.2f%% | Counter: %d\n', ...
            pSiren * 100, consecutiveCount);

    else

        fprintf('Normal / Noise | Probability: %.2f%% | Counter: %d\n', ...
            pSiren * 100, consecutiveCount);

    end

    % =====================================================
    % 13. MEL SPECTROGRAM UPDATE
    % =====================================================

    specData = double(S(:,:,1,end))';

    set(hImg, 'CData', specData);
    set(hImg, 'Interpolation', 'bilinear');

    % =====================================================
    % 14. PROBABILITY BAR UPDATE
    % =====================================================

    pct = pSiren * 100;

    set(hBar, 'YData', pct);

    % =====================================================
    % 15. STATUS UPDATE
    % =====================================================

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

    drawnow limitrate;

end
