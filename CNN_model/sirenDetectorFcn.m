function sirenAlert = sirenDetectorFcn(audioBuffer)
    persistent net bestTh fsTarget winLen hopLen hpFilt
    if isempty(net)
        data = load('D:\project4\trainedSirenModel.mat');
        net = data.trainedNet;
        bestTh = data.bestTh;
        fsTarget = 22050;
        winLen = round(0.030 * fsTarget);
        hopLen = round(0.015 * fsTarget);
        hpFilt = designfilt('highpassiir', ...
                            'FilterOrder', 6, ...
                            'PassbandFrequency', 700, ...
                            'PassbandRipple', 0.5, ...
                            'SampleRate', fsTarget);
    end
    filteredBuffer = filter(hpFilt, audioBuffer);
    S = melSpectrogram(filteredBuffer, fsTarget, ...
                       'Window', hamming(winLen, 'periodic'), ...
                       'OverlapLength', winLen - hopLen, ...
                       'NumBands', 64, ...
                       'FrequencyRange', [50, 8000]);
    feat = single(10 * log10(S + eps));
    feat = reshape(feat, [64, size(feat, 2), 1]);
    scores = predict(net, feat);
    probSiren = scores(1);
    sirenAlert = double(probSiren >= bestTh);
end