function realtimeSumoMonitor()
    % 1. إيقاف أي تايمر قديم لنفس المراقب فقط
    oldTimers = timerfindall('Tag', 'SumoRealtimeMonitorTimer');
    if ~isempty(oldTimers)
        stop(oldTimers);
        delete(oldTimers);
    end

    % 2. حماية تلقائية ضد خطأ hStatus إذا لم يكن سيمولينك يعمل
    try
        models = find_system('Type', 'block_diagram');
        simRunning = false;
        for i = 1:numel(models)
            if strcmp(get_param(models{i}, 'SimulationStatus'), 'running')
                simRunning = true;
                break;
            end
        end
        if ~simRunning
            clear('detectSirenStep');
        end
    catch
    end

    cmdFile = 'D:\sim\tls_cmd.txt';
    bridgePollMs = 50; % زمن دورة القراءة في run_sumo_bridge.py (0.05 ثانية)
    windowSec = 15;    % عرض نافذة الزمن على الشاشة (بالثواني)

    % 3. نافذة واحدة نظيفة ومعزولة تماماً عن بقية رسومات Simulink
    fig = figure('Name', 'Simulink vs. SUMO Real-Time Response', ...
                 'Color', 'w', 'Position', [120, 140, 1020, 520], ...
                 'NumberTitle', 'off', 'HandleVisibility', 'off');

    % محور واحد بهوامش مضبوطة حتى لا يُقص أي نص
    ax = axes('Parent', fig, 'Position', [0.16 0.15 0.79 0.71]);
    hold(ax, 'on');

    % الخط الأحمر: Simulink | الخط الأخضر: SUMO
    hCmd  = animatedline(ax, 'Color', [0.85 0.10 0.10], 'LineWidth', 2.5, ...
                         'DisplayName', 'Simulink Command (Red)');
    hSumo = animatedline(ax, 'Color', [0.10 0.65 0.25], 'LineWidth', 2.2, ...
                         'LineStyle', '--', 'DisplayName', 'SUMO Response (Green)');

    ylim(ax, [-0.25 1.35]);
    yticks(ax, [0 1]);
    yticklabels(ax, {'Normal (R)', 'Emergency (G)'});
    xlabel(ax, 'Time (s)', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel(ax, 'Traffic State', 'FontSize', 11, 'FontWeight', 'bold');
    title(ax, 'Simulink vs. SUMO Response | Waiting for switch...', ...
          'FontSize', 12, 'FontWeight', 'bold');
    legend(ax, [hCmd, hSumo], 'Location', 'northwest', 'FontSize', 10);
    grid(ax, 'on');
    ax.FontSize = 10;

    % زر حفظ الصورة بعرض كافٍ حتى لا يُقص النص
    btnSave = uicontrol('Parent', fig, 'Style', 'pushbutton', ...
                        'String', 'Save PNG', ...
                        'Units', 'normalized', ...
                        'Position', [0.85 0.91 0.10 0.06], ...
                        'FontWeight', 'bold', ...
                        'BackgroundColor', [0.94 0.94 0.94], ...
                        'Callback', @saveSnapshot);

    % متغيرات المتابعة الداخلية
    state.tStart = tic;
    state.lastCmd = -1;
    state.sumoState = 0;
    state.pendingChange = false;
    state.changeDetectedAt = 0;
    state.switchTime = 0;
    state.targetState = 0;
    state.estimatedDelayMs = 0;
    state.delays = [];

    % تشغيل المراقبة في الخلفية بـ Timer بدون تعطيل Simulink
    t = timer('ExecutionMode', 'fixedSpacing', ...
              'Period', 0.02, ...
              'Tag', 'SumoRealtimeMonitorTimer', ...
              'TimerFcn', @updatePlot);

    fig.CloseRequestFcn = @onClose;
    start(t);
    fprintf('Real-Time Response Monitor started.\n');

    function updatePlot(~, ~)
        if ~isvalid(fig)
            return;
        end

        try
            tNow = toc(state.tStart);
            cmdVal = 0;
            ioLatencyMs = 0;

            % قراءة الإشارة من ملف tls_cmd.txt
            if isfile(cmdFile)
                tReadStart = tic;
                f = fopen(cmdFile, 'r');
                if f ~= -1
                    txt = strtrim(fscanf(f, '%s'));
                    fclose(f);
                    if strcmp(txt, 'G')
                        cmdVal = 1;
                    end
                end
                ioLatencyMs = toc(tReadStart) * 1000;
            end

            % أول قراءة عند بداية التشغيل
            if state.lastCmd == -1
                state.lastCmd = cmdVal;
                state.sumoState = cmdVal;
                addpoints(hCmd, tNow, cmdVal);
                addpoints(hSumo, tNow, cmdVal + 0.025);
                return;
            end

            % تطبيق استجابة SUMO عند حلول وقتها الدقيق
            if state.pendingChange && tNow >= state.switchTime
                tS = state.switchTime;
                oldS = state.sumoState;
                newS = state.targetState;
                d = state.estimatedDelayMs;

                % رسم حافة انتقال حادة (90 درجة) للخط الأخضر
                addpoints(hSumo, tS, oldS + 0.025);
                addpoints(hSumo, tS, newS + 0.025);
                state.sumoState = newS;
                state.pendingChange = false;

                % تظليل فجوة الديلاي باللون الأصفر الفاتح (تظهر بوضوح عند عمل Zoom)
                patch(ax, [state.changeDetectedAt, tS, tS, state.changeDetectedAt], ...
                      [-0.25, -0.25, 1.35, 1.35], [1.0 0.88 0.3], ...
                      'FaceAlpha', 0.45, 'EdgeColor', 'none', 'HandleVisibility', 'off');

                % كتابة قيمة الديلاي مباشرة بجانب النقلة
                if newS == 1
                    lbl = sprintf('R\\rightarrowG: %.1f ms', d);
                    yPos = 0.60;
                else
                    lbl = sprintf('G\\rightarrowR: %.1f ms', d);
                    yPos = 0.40;
                end
                text(ax, tS + 0.15, yPos, lbl, ...
                     'FontWeight', 'bold', 'FontSize', 9.5, ...
                     'Color', [0.1 0.1 0.1], ...
                     'BackgroundColor', [1.0 0.98 0.82], ...
                     'EdgeColor', [0.2 0.2 0.2], 'Margin', 2);

                % تحديث العنوان بآخر ديلاي ومتوسط الديلاي
                state.delays(end+1) = d;
                avgD = mean(state.delays);
                title(ax, sprintf('Simulink (Red) vs. SUMO (Green)  |  Last Delay: %.1f ms  |  Avg Delay: %.1f ms', ...
                      d, avgD), 'FontSize', 11.5, 'FontWeight', 'bold');
            end

            % رصد تغير أمر Simulink (الخط الأحمر)
            if cmdVal ~= state.lastCmd
                addpoints(hCmd, tNow, state.lastCmd);
                addpoints(hCmd, tNow, cmdVal);

                phaseOffsetMs = mod(tNow * 1000, bridgePollMs);
                d = (bridgePollMs - phaseOffsetMs) + ioLatencyMs;

                state.pendingChange = true;
                state.changeDetectedAt = tNow;
                state.switchTime = tNow + (d / 1000);
                state.targetState = cmdVal;
                state.estimatedDelayMs = d;
                state.lastCmd = cmdVal;
            else
                addpoints(hCmd, tNow, cmdVal);
            end

            % تمديد الخط الأخضر للحظة الحالية
            if ~state.pendingChange || tNow < state.switchTime
                addpoints(hSumo, tNow, state.sumoState + 0.025);
            end

            % تحريك محور الزمن تلقائياً
            if tNow > windowSec
                xlim(ax, [tNow - windowSec, tNow + 1.5]);
            else
                xlim(ax, [0, windowSec + 1.5]);
            end

            drawnow limitrate;
        catch
        end
    end

    function saveSnapshot(~, ~)
        outFile = fullfile('D:\sim', sprintf('SUMO_Response_%s.png', datestr(now, 'yyyymmdd_HHMMSS')));
        btnSave.Visible = 'off';
        drawnow;
        try
            exportgraphics(fig, outFile, 'Resolution', 300);
        catch
            print(fig, outFile, '-dpng', '-r300');
        end
        btnSave.Visible = 'on';
        fprintf('Saved graph to: %s\n', outFile);
    end

    function onClose(~, ~)
        if isvalid(t)
            stop(t);
            delete(t);
        end
        delete(fig);
    end
end