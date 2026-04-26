function plugin = swf_scenario_runner()
    % SWF_SCENARIO_RUNNER  Define and run automated test scenarios.
    %
    % Scenarios are predefined test configurations with:
    %   - Swarm mode, waypoints, wind conditions
    %   - Duration and pass/fail criteria
    %   - Optional fault injection scheduling
    %
    % Results are logged and can be exported.

    plugin.id          = 'scenarios';
    plugin.name        = 'Scenario Runner';
    plugin.description = 'Automated test scenario runner. Define flight profiles with pass/fail criteria, run them sequentially, and review results.';
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
    % Define built-in scenarios
    s = struct('name',{},'mode',{},'waypoints',{},'windSpeed',{},...
               'windDir',{},'duration',{},'maxDist',{});

    s(1).name = 'Formation Hold - Calm';
    s(1).mode = 'Leader-Follower';
    s(1).waypoints = [];
    s(1).windSpeed = 0;
    s(1).windDir = 0;
    s(1).duration = 30;
    s(1).maxDist = 50;

    s(2).name = 'Formation Hold - Wind 8m/s';
    s(2).mode = 'Leader-Follower';
    s(2).waypoints = [];
    s(2).windSpeed = 8;
    s(2).windDir = 45;
    s(2).duration = 30;
    s(2).maxDist = 50;

    s(3).name = 'Waypoint Nav - Square';
    s(3).mode = 'Leader-Follower';
    s(3).waypoints = [60 60; 60 -60; -60 -60; -60 60; 0 0];
    s(3).windSpeed = 0;
    s(3).windDir = 0;
    s(3).duration = 60;
    s(3).maxDist = 50;

    s(4).name = 'Decentralized Cohesion';
    s(4).mode = 'Decentralized';
    s(4).waypoints = [];
    s(4).windSpeed = 3;
    s(4).windDir = 180;
    s(4).duration = 45;
    s(4).maxDist = 80;

    s(5).name = 'Relay Endurance';
    s(5).mode = 'Hetero-Relay';
    s(5).waypoints = [80 0; 80 80; 0 80];
    s(5).windSpeed = 5;
    s(5).windDir = 270;
    s(5).duration = 60;
    s(5).maxDist = 60;

    s(6).name = 'Fast Scout Sprint';
    s(6).mode = 'Hetero-Speed';
    s(6).waypoints = [150 0; 150 100; 0 100];
    s(6).windSpeed = 0;
    s(6).windDir = 0;
    s(6).duration = 45;
    s(6).maxDist = 100;

    app.setState('scenarios', 'definitions', s);
    app.setState('scenarios', 'running', false);
    app.setState('scenarios', 'currentIdx', 0);
    app.setState('scenarios', 'startTime', 0);
    app.setState('scenarios', 'results', {});
    app.setState('scenarios', 'maxSpread', 0);
end

function onUnload(~)
end

function buildTab(app, tab)
    grid = uigridlayout(tab, [3, 1], ...
        'RowHeight', {155, 38, '1x'}, ...
        'Padding', [12 12 12 12], 'RowSpacing', 8);

    % --- Scenario Selector ---
    topPanel = uipanel(grid, 'Title', 'Scenario', ...
        'FontWeight', 'bold', 'FontSize', 12);
    topPanel.Layout.Row = 1; topPanel.Layout.Column = 1;

    tg = uigridlayout(topPanel, [3, 3], ...
        'RowHeight', {30, 36, 28}, ...
        'ColumnWidth', {120, '1x', 120}, ...
        'Padding', [10 8 10 8], 'RowSpacing', 4);

    lbl = uilabel(tg, 'Text', 'Select Scenario:');
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;

    sdefs = app.getState('scenarios', 'definitions');
    names = {};
    for i = 1:length(sdefs), names{end+1} = sdefs(i).name; end %#ok<AGROW>

    scDrop = uidropdown(tg, 'Items', names, 'Tag', 'sc_dropdown');
    scDrop.Layout.Row = 1; scDrop.Layout.Column = [2 3];

    runBtn = uibutton(tg, 'push', 'Text', 'Run Selected', ...
        'BackgroundColor', [0.18 0.72 0.35], 'FontColor', 'w', 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) runSelected(app, tab));
    runBtn.Layout.Row = 2; runBtn.Layout.Column = 1;

    runAllBtn = uibutton(tg, 'push', 'Text', 'Run All Scenarios', ...
        'BackgroundColor', [0.15 0.35 0.75], 'FontColor', 'w', 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) runAll(app, tab));
    runAllBtn.Layout.Row = 2; runAllBtn.Layout.Column = 2;

    stopBtn = uibutton(tg, 'push', 'Text', 'Abort', ...
        'BackgroundColor', [0.85 0.22 0.20], 'FontColor', 'w', ...
        'ButtonPushedFcn', @(~,~) abortScenario(app));
    stopBtn.Layout.Row = 2; stopBtn.Layout.Column = 3;

    statusLbl = uilabel(tg, 'Text', 'Status: Idle', 'FontWeight', 'bold', ...
        'Tag', 'sc_status');
    statusLbl.Layout.Row = 3; statusLbl.Layout.Column = [1 3];

    % --- Progress ---
    progLbl = uilabel(grid, 'Text', '', 'Tag', 'sc_progress', ...
        'FontSize', 12, 'FontWeight', 'bold');
    progLbl.Layout.Row = 2; progLbl.Layout.Column = 1;

    % --- Results Table ---
    resPanel = uipanel(grid, 'Title', 'Results', ...
        'FontWeight', 'bold', 'FontSize', 12);
    resPanel.Layout.Row = 3; resPanel.Layout.Column = 1;

    resTbl = uitable(resPanel, ...
        'ColumnName', {'Scenario', 'Mode', 'Duration', 'Max Spread (m)', 'Result'}, ...
        'ColumnWidth', {200, 130, 80, 120, 80}, ...
        'Data', cell(0, 5), ...
        'Tag', 'sc_results_table', ...
        'Position', [10 10 650 300]);
end

function runSelected(app, tab)
    scDrop = findobj(tab, 'Tag', 'sc_dropdown');
    sdefs = app.getState('scenarios', 'definitions');
    idx = find(strcmp({sdefs.name}, scDrop.Value));
    if isempty(idx), return; end
    startScenario(app, idx);
end

function runAll(app, ~)
    % Start with first scenario; onStep will chain to next
    app.setState('scenarios', 'runAllMode', true);
    app.setState('scenarios', 'results', {});
    startScenario(app, 1);
end

function startScenario(app, idx)
    sdefs = app.getState('scenarios', 'definitions');
    if idx < 1 || idx > length(sdefs), return; end

    sc = sdefs(idx);
    app.logMsg(sprintf('=== SCENARIO: %s ===', sc.name));

    % Configure app
    app.onStop();
    app.onReset();
    app.onModeChanged(sc.mode);
    app.WindSpeed = sc.windSpeed;
    app.WindDir = sc.windDir;
    app.MaxSwarmDist = sc.maxDist;
    if ~isempty(sc.waypoints)
        app.setWaypoints(sc.waypoints);
    end

    app.setState('scenarios', 'running', true);
    app.setState('scenarios', 'currentIdx', idx);
    app.setState('scenarios', 'startTime', app.SimTime);
    app.setState('scenarios', 'maxSpread', 0);

    app.onStart();

    % Update status
    try
        stLbl = findobj(app.Fig, 'Tag', 'sc_status');
        if ~isempty(stLbl)
            stLbl.Text = sprintf('Running: %s (%.0fs)', sc.name, sc.duration);
        end
    catch
    end
end

function abortScenario(app)
    app.setState('scenarios', 'running', false);
    app.setState('scenarios', 'runAllMode', false);
    app.onStop();
    app.logMsg('Scenario aborted.');
    try
        stLbl = findobj(app.Fig, 'Tag', 'sc_status');
        if ~isempty(stLbl), stLbl.Text = 'Status: Aborted'; end
    catch
    end
end

function onStep(app)
    running = app.getState('scenarios', 'running');
    if isempty(running) || ~running, return; end

    idx = app.getState('scenarios', 'currentIdx');
    sdefs = app.getState('scenarios', 'definitions');
    sc = sdefs(idx);
    startT = app.getState('scenarios', 'startTime');
    elapsed = app.SimTime - startT;

    % Track max spread
    maxSp = app.getState('scenarios', 'maxSpread');
    for i = 1:app.NumUAVs
        for j = (i+1):app.NumUAVs
            d = norm(app.UAVPositions(i,1:2) - app.UAVPositions(j,1:2));
            if d > maxSp, maxSp = d; end
        end
    end
    app.setState('scenarios', 'maxSpread', maxSp);

    % Update progress
    try
        pLbl = findobj(app.Fig, 'Tag', 'sc_progress');
        if ~isempty(pLbl)
            pLbl.Text = sprintf('Time: %.0f / %.0f s  |  Max Spread: %.1f m', ...
                elapsed, sc.duration, maxSp);
        end
    catch
    end

    % Check completion
    if elapsed >= sc.duration
        app.onStop();
        app.setState('scenarios', 'running', false);

        % Evaluate result
        passed = maxSp < (sc.maxDist * 2);
        resultStr = 'PASS';
        if ~passed, resultStr = 'FAIL'; end

        app.logMsg(sprintf('Scenario %s: %s (max spread %.1fm)', sc.name, resultStr, maxSp));

        % Store result
        results = app.getState('scenarios', 'results');
        if isempty(results), results = {}; end
        results{end+1} = struct('name', sc.name, 'mode', sc.mode, ...
            'duration', sc.duration, 'maxSpread', maxSp, 'result', resultStr);
        app.setState('scenarios', 'results', results);

        % Update results table
        try
            tbl = findobj(app.Fig, 'Tag', 'sc_results_table');
            if ~isempty(tbl)
                data = cell(length(results), 5);
                for r = 1:length(results)
                    res = results{r};
                    data{r,1} = res.name;
                    data{r,2} = res.mode;
                    data{r,3} = sprintf('%.0fs', res.duration);
                    data{r,4} = sprintf('%.1f', res.maxSpread);
                    data{r,5} = res.result;
                end
                tbl.Data = data;
            end
        catch
        end

        % Update status
        try
            stLbl = findobj(app.Fig, 'Tag', 'sc_status');
            if ~isempty(stLbl)
                stLbl.Text = sprintf('Completed: %s - %s', sc.name, resultStr);
            end
        catch
        end

        % Chain to next if running all
        runAllMode = app.getState('scenarios', 'runAllMode');
        if ~isempty(runAllMode) && runAllMode
            nextIdx = idx + 1;
            if nextIdx <= length(sdefs)
                % Small pause before next
                app.logMsg(sprintf('Next scenario in 2s: %s', sdefs(nextIdx).name));
                t = timer('StartDelay', 2, 'TimerFcn', ...
                    @(~,~) startScenario(app, nextIdx));
                start(t);
            else
                app.setState('scenarios', 'runAllMode', false);
                app.logMsg('=== ALL SCENARIOS COMPLETE ===');
                try
                    stLbl = findobj(app.Fig, 'Tag', 'sc_status');
                    if ~isempty(stLbl), stLbl.Text = 'Status: All scenarios complete'; end
                catch
                end
            end
        end
    end
end
