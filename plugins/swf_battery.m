function plugin = swf_battery()
    % SWF_BATTERY  Simulated battery / energy model for each UAV.
    %
    % Models current draw based on speed, altitude, and wind.
    % Shows per-UAV battery percentage, voltage, and estimated flight time.

    plugin.id          = 'battery';
    plugin.name        = 'Battery Model';
    plugin.description = 'Simulates LiPo battery drain per UAV based on flight dynamics. Shows remaining capacity, voltage sag, and estimated endurance.';
    plugin.version     = '1.0';
    plugin.hasTab      = true;
    plugin.hasStep     = true;
    plugin.hasToolbar  = false;

    plugin.onLoad    = @(app) onLoad(app);
    plugin.onUnload  = @(app) onUnload(app);
    plugin.buildTab  = @(app, tab) buildTab(app, tab);
    plugin.onStep    = @(app) onStep(app);
end

function onLoad(app)
    N = app.NumUAVs;
    app.setState('battery', 'capacity',  ones(1,N) * 5000);   % mAh
    app.setState('battery', 'remaining', ones(1,N) * 5000);
    app.setState('battery', 'voltage',   ones(1,N) * 16.8);   % 4S LiPo
    app.setState('battery', 'current',   zeros(1,N));
    app.setState('battery', 'pct_hist',  []);
    app.setState('battery', 't_hist',    []);
    app.setState('battery', 'warned',    false(1,N));
end

function onUnload(~)
end

function buildTab(app, tab)
    grid = uigridlayout(tab, [2, 1], ...
        'RowHeight', {200, '1x'}, 'Padding', [12 12 12 12], 'RowSpacing', 10);

    % --- Top: Status Table ---
    topPanel = uipanel(grid, 'Title', 'Battery Status', ...
        'FontWeight', 'bold', 'FontSize', 12);
    topPanel.Layout.Row = 1; topPanel.Layout.Column = 1;

    tbl = uitable(topPanel, ...
        'ColumnName', {'UAV', 'Remaining (mAh)', 'Percent', 'Voltage (V)', 'Current (A)', 'Est. Time'}, ...
        'ColumnWidth', {100, 120, 80, 100, 100, 100}, ...
        'Tag', 'bat_status_table', ...
        'Position', [10 10 640 150]);
    % Init data
    data = cell(app.NumUAVs, 6);
    for k = 1:app.NumUAVs
        data{k,1} = app.UAVNames{k};
        data{k,2} = '5000';
        data{k,3} = '100%';
        data{k,4} = '16.8';
        data{k,5} = '0.0';
        data{k,6} = '--';
    end
    tbl.Data = data;

    % --- Bottom: Battery History Plot ---
    botPanel = uipanel(grid, 'Title', 'Battery Level Over Time', ...
        'FontWeight', 'bold', 'FontSize', 12);
    botPanel.Layout.Row = 2; botPanel.Layout.Column = 1;

    bg = uigridlayout(botPanel, [1, 1], 'Padding', [5 5 5 5]);
    ax = uiaxes(bg);
    ax.Layout.Row = 1; ax.Layout.Column = 1;
    ax.Title.String = 'Battery %'; ax.XLabel.String = 'Time (s)';
    ax.YLabel.String = '%'; ax.YLim = [0 105];
    ax.XGrid = 'on'; ax.YGrid = 'on'; ax.Box = 'on';
    hold(ax, 'on');

    batLines = cell(1, app.NumUAVs);
    for k = 1:app.NumUAVs
        batLines{k} = plot(ax, NaN, NaN, '-', 'Color', app.UAVColors(k,:), 'LineWidth', 1.5);
    end
    app.setState('battery', 'plot_lines', batLines);
end

function onStep(app)
    N = app.NumUAVs;
    cap  = app.getState('battery', 'capacity');
    rem  = app.getState('battery', 'remaining');
    volt = app.getState('battery', 'voltage');
    curr = app.getState('battery', 'current');
    warned = app.getState('battery', 'warned');
    pHist = app.getState('battery', 'pct_hist');
    tHist = app.getState('battery', 't_hist');
    dt = app.dt;

    pctRow = zeros(1, N);
    for k = 1:N
        % Estimate speed from position delta
        speed = 0;
        n = length(app.TelHistory(k).x);
        if n >= 2
            dx = app.TelHistory(k).x(n) - app.TelHistory(k).x(n-1);
            dy = app.TelHistory(k).y(n) - app.TelHistory(k).y(n-1);
            speed = norm([dx dy]) / dt;
        end

        % Current draw model: hover base + speed load + altitude penalty
        alt = app.UAVPositions(k, 3);
        baseCurrent = 18;  % Amps (hover)
        speedLoad   = 2.0 * speed;
        altPenalty   = 0.05 * max(0, alt - 20);
        windLoad    = 0.5 * app.WindSpeed;
        totalCurrent = baseCurrent + speedLoad + altPenalty + windLoad;

        curr(k) = totalCurrent;
        rem(k)  = rem(k) - (totalCurrent * dt / 3.6);  % mAh consumed
        rem(k)  = max(0, rem(k));

        % Voltage sag (linear model)
        pct = rem(k) / cap(k);
        volt(k) = 12.0 + 4.8 * pct;  % 12V dead -> 16.8V full
        pctRow(k) = pct * 100;

        % Warning at 20% and 10%
        if pct < 0.10 && ~warned(k)
            app.logMsg(sprintf('BATTERY CRITICAL: UAV-%d at %.0f%%!', k, pct*100));
            warned(k) = true;
        elseif pct < 0.20 && ~warned(k)
            app.logMsg(sprintf('Battery low: UAV-%d at %.0f%%', k, pct*100));
        end
    end

    app.setState('battery', 'remaining', rem);
    app.setState('battery', 'voltage',   volt);
    app.setState('battery', 'current',   curr);
    app.setState('battery', 'warned',    warned);

    % History
    tHist(end+1) = app.SimTime;
    pHist(end+1, :) = pctRow;
    if size(pHist, 1) > 1000
        pHist = pHist(end-999:end, :);
        tHist = tHist(end-999:end);
    end
    app.setState('battery', 'pct_hist', pHist);
    app.setState('battery', 't_hist',   tHist);

    % Update table
    try
        tbl = findobj(app.Fig, 'Tag', 'bat_status_table');
        if ~isempty(tbl)
            data = cell(N, 6);
            for k = 1:N
                pct = rem(k) / cap(k);
                estMin = rem(k) / max(curr(k), 0.1) * 60 / 1000;
                data{k,1} = app.UAVNames{k};
                data{k,2} = sprintf('%.0f', rem(k));
                data{k,3} = sprintf('%.0f%%', pct*100);
                data{k,4} = sprintf('%.1f', volt(k));
                data{k,5} = sprintf('%.1f', curr(k));
                data{k,6} = sprintf('%.1f min', estMin);
            end
            tbl.Data = data;
        end
    catch
    end

    % Update plot lines
    try
        batLines = app.getState('battery', 'plot_lines');
        if ~isempty(batLines) && size(pHist, 1) > 1
            for k = 1:N
                batLines{k}.XData = tHist;
                batLines{k}.YData = pHist(:, k)';
            end
        end
    catch
    end
end
