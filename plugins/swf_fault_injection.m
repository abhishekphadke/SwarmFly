function plugin = swf_fault_injection()
    % SWF_FAULT_INJECTION  Inject faults into UAVs during simulation.
    %
    % Supported faults:
    %   GPS Drift, GPS Denied, Motor Failure, Comm Blackout,
    %   Sensor Noise Spike, Frozen Actuator, Wind Gust, Battery Critical

    plugin.id          = 'fault_injection';
    plugin.name        = 'Fault Injection';
    plugin.description = 'Inject hardware and environmental faults into individual UAVs to test swarm resilience. Supports 8 fault types with configurable duration.';
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
    % Active faults list: each entry is struct(type, targets, startTime, duration)
    app.setState('fault_injection', 'active_faults', {});
    app.setState('fault_injection', 'fault_log', {});
end

function onUnload(app)
    app.logMsg('All faults cleared on unload.');
end

function buildTab(app, tab)
    grid = uigridlayout(tab, [2, 1], ...
        'RowHeight', {260, '1x'}, 'Padding', [12 12 12 12], 'RowSpacing', 10);

    % --- Top: Injection Controls ---
    ctrlPanel = uipanel(grid, 'Title', 'Inject Fault', ...
        'FontWeight', 'bold', 'FontSize', 12, 'BackgroundColor', [0.97 0.94 0.94]);
    ctrlPanel.Layout.Row = 1; ctrlPanel.Layout.Column = 1;

    cg = uigridlayout(ctrlPanel, [5, 4], ...
        'RowHeight', {30, 30, 50, 30, 40}, ...
        'ColumnWidth', {120, '1x', 120, '1x'}, ...
        'Padding', [10 10 10 10], 'RowSpacing', 6);

    % Fault type
    lbl = uilabel(cg, 'Text', 'Fault Type:', 'FontWeight', 'bold');
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;
    faultDrop = uidropdown(cg, 'Items', { ...
        'GPS Drift', 'GPS Denied', 'Motor Failure', ...
        'Comm Blackout', 'Sensor Noise Spike', 'Frozen Actuator', ...
        'Wind Gust', 'Battery Critical'}, ...
        'Tag', 'fi_fault_type');
    faultDrop.Layout.Row = 1; faultDrop.Layout.Column = [2 4];

    % Target UAV
    lbl = uilabel(cg, 'Text', 'Target UAV:');
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    uavDrop = uidropdown(cg, 'Items', [{'All UAVs'}, app.UAVNames], ...
        'Tag', 'fi_target');
    uavDrop.Layout.Row = 2; uavDrop.Layout.Column = 2;

    % Duration
    lbl = uilabel(cg, 'Text', 'Duration (s):');
    lbl.Layout.Row = 2; lbl.Layout.Column = 3;
    durField = uieditfield(cg, 'numeric', 'Value', 10, 'Limits', [1 600], ...
        'Tag', 'fi_duration');
    durField.Layout.Row = 2; durField.Layout.Column = 4;

    % Intensity
    lbl = uilabel(cg, 'Text', 'Intensity:');
    lbl.Layout.Row = 3; lbl.Layout.Column = 1;
    intSlider = uislider(cg, 'Limits', [0.1 3.0], 'Value', 1.0, ...
        'Tag', 'fi_intensity');
    intSlider.Layout.Row = 3; intSlider.Layout.Column = [2 4];

    % Buttons
    injBtn = uibutton(cg, 'push', 'Text', 'INJECT FAULT', ...
        'BackgroundColor', [0.85 0.18 0.15], 'FontColor', 'w', ...
        'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) doInject(app, tab));
    injBtn.Layout.Row = 5; injBtn.Layout.Column = [1 2];

    clrBtn = uibutton(cg, 'push', 'Text', 'Clear All Faults', ...
        'BackgroundColor', [0.3 0.3 0.3], 'FontColor', 'w', ...
        'ButtonPushedFcn', @(~,~) doClearAll(app, tab));
    clrBtn.Layout.Row = 5; clrBtn.Layout.Column = [3 4];

    % --- Bottom: Active Faults Table ---
    botPanel = uipanel(grid, 'Title', 'Active Faults', ...
        'FontWeight', 'bold', 'FontSize', 12, 'BackgroundColor', [0.96 0.96 0.98]);
    botPanel.Layout.Row = 2; botPanel.Layout.Column = 1;

    tbl = uitable(botPanel, 'ColumnName', {'Fault Type', 'Target', 'Remaining (s)', 'Intensity'}, ...
        'ColumnWidth', {180, 120, 100, 80}, ...
        'Data', cell(0, 4), ...
        'Tag', 'fi_active_table', ...
        'Position', [10 10 500 300]);
end

function doInject(app, tab)
    faultDrop = findobj(tab, 'Tag', 'fi_fault_type');
    uavDrop   = findobj(tab, 'Tag', 'fi_target');
    durField  = findobj(tab, 'Tag', 'fi_duration');
    intSlider = findobj(tab, 'Tag', 'fi_intensity');

    faultType = char(faultDrop.Value);
    targetStr = char(uavDrop.Value);
    duration  = durField.Value;
    intensity = intSlider.Value;

    % Resolve targets
    if strcmp(targetStr, 'All UAVs')
        targets = 1:app.NumUAVs;
    else
        targets = find(strcmp(app.UAVNames, targetStr));
    end

    % Create fault entry
    fault = struct('type', faultType, 'targets', targets, ...
        'startTime', app.SimTime, 'duration', duration, 'intensity', intensity);

    active = app.getState('fault_injection', 'active_faults');
    if isempty(active), active = {}; end
    active{end+1} = fault;
    app.setState('fault_injection', 'active_faults', active);

    app.logMsg(sprintf('FAULT: %s on [%s] for %.0fs (x%.1f)', ...
        faultType, num2str(targets), duration, intensity));
end

function doClearAll(app, tab)
    app.setState('fault_injection', 'active_faults', {});
    app.logMsg('All faults cleared.');
    tbl = findobj(tab, 'Tag', 'fi_active_table');
    if ~isempty(tbl), tbl.Data = cell(0, 4); end
end

function onStep(app)
    active = app.getState('fault_injection', 'active_faults');
    if isempty(active), return; end

    keep = {};
    for i = 1:length(active)
        f = active{i};
        elapsed = app.SimTime - f.startTime;
        if elapsed > f.duration
            app.logMsg(sprintf('Fault expired: %s', f.type));
            continue;  % don't keep
        end
        keep{end+1} = f; %#ok<AGROW>

        % Apply fault effects
        for k = f.targets
            switch f.type
                case 'GPS Drift'
                    drift = f.intensity * 0.3 * elapsed * [sin(elapsed*0.5), cos(elapsed*0.5)];
                    app.UAVPositions(k,1:2) = app.UAVPositions(k,1:2) + drift * app.dt;

                case 'GPS Denied'
                    app.UAVPositions(k,1:2) = app.UAVPositions(k,1:2) + ...
                        f.intensity * randn(1,2) * 0.5 * app.dt;

                case 'Motor Failure'
                    app.UAVPositions(k,3) = app.UAVPositions(k,3) - f.intensity * 0.8 * app.dt;

                case 'Comm Blackout'
                    app.UAVPositions(k,1:2) = app.UAVPositions(k,1:2) + ...
                        f.intensity * randn(1,2) * 2 * app.dt;

                case 'Sensor Noise Spike'
                    if ~isempty(app.TelHistory(k).ax)
                        app.TelHistory(k).ax(end) = app.TelHistory(k).ax(end) + randn()*20*f.intensity;
                        app.TelHistory(k).ay(end) = app.TelHistory(k).ay(end) + randn()*20*f.intensity;
                    end

                case 'Frozen Actuator'
                    app.UAVPositions(k,1:2) = app.UAVPositions(k,1:2) + ...
                        f.intensity * 2 * [cos(app.UAVHeadings(k)), sin(app.UAVHeadings(k))] * app.dt;

                case 'Wind Gust'
                    gust = f.intensity * 15 * [cosd(rand()*360), sind(rand()*360), 0];
                    app.UAVPositions(k,:) = app.UAVPositions(k,:) + gust * app.dt;

                case 'Battery Critical'
                    app.UAVPositions(k,3) = app.UAVPositions(k,3) - f.intensity * 1.5 * app.dt;
            end
        end
    end

    app.setState('fault_injection', 'active_faults', keep);

    % Update table (find by tag — works across tabs)
    try
        tbl = findobj(app.Fig, 'Tag', 'fi_active_table');
        if ~isempty(tbl) && ~isempty(keep)
            data = cell(length(keep), 4);
            for i = 1:length(keep)
                f = keep{i};
                remaining = f.duration - (app.SimTime - f.startTime);
                data{i,1} = f.type;
                data{i,2} = num2str(f.targets);
                data{i,3} = sprintf('%.1f', remaining);
                data{i,4} = sprintf('%.1f', f.intensity);
            end
            tbl.Data = data;
        elseif ~isempty(tbl)
            tbl.Data = cell(0, 4);
        end
    catch
    end
end
