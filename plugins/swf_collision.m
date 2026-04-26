function plugin = swf_collision()
    % SWF_COLLISION  Collision avoidance safety layer.
    %
    % Monitors pairwise distances and applies emergency separation
    % maneuvers when UAVs get within the minimum safe distance.
    % Logs near-miss and collision events.

    plugin.id          = 'collision';
    plugin.name        = 'Collision Avoidance';
    plugin.description = 'Safety layer that detects near-miss events and applies emergency separation forces. Configurable safe distance. No tab needed — runs silently and logs alerts.';
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
    app.setState('collision', 'safeDist', 5);       % meters
    app.setState('collision', 'nearMissCount', 0);
    app.setState('collision', 'collisionCount', 0);
    app.setState('collision', 'events', {});         % log of events
    app.setState('collision', 'minDist_hist', []);
    app.setState('collision', 't_hist', []);
    app.logMsg('Collision avoidance active (safe dist = 5m).');
end

function onUnload(~)
end

function buildTab(app, tab)
    grid = uigridlayout(tab, [3, 2], ...
        'RowHeight', {60, 48, '1x'}, ...
        'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [15 15 15 15], 'RowSpacing', 10);

    % Status counters
    nmLbl = uilabel(grid, 'Text', 'Near-Misses: 0', ...
        'FontSize', 16, 'FontWeight', 'bold', 'FontColor', [0.9 0.6 0.0], ...
        'Tag', 'col_nearmiss_lbl');
    nmLbl.Layout.Row = 1; nmLbl.Layout.Column = 1;

    colLbl = uilabel(grid, 'Text', 'Collisions: 0', ...
        'FontSize', 16, 'FontWeight', 'bold', 'FontColor', [0.9 0.1 0.1], ...
        'Tag', 'col_collision_lbl');
    colLbl.Layout.Row = 1; colLbl.Layout.Column = 2;

    % Safe distance control
    lbl = uilabel(grid, 'Text', 'Safe Distance (m):');
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    sdSlider = uislider(grid, 'Limits', [1 20], 'Value', 5, ...
        'ValueChangedFcn', @(src,~) app.setState('collision', 'safeDist', round(src.Value)));
    sdSlider.Layout.Row = 2; sdSlider.Layout.Column = 2;

    % Minimum distance plot
    plotPanel = uipanel(grid, 'Title', 'Minimum Pairwise Distance', ...
        'FontWeight', 'bold');
    plotPanel.Layout.Row = 3; plotPanel.Layout.Column = [1 2];
    pg = uigridlayout(plotPanel, [1,1], 'Padding', [5 5 5 5]);
    ax = uiaxes(pg);
    ax.Layout.Row = 1; ax.Layout.Column = 1;
    ax.XLabel.String = 'Time (s)'; ax.YLabel.String = 'Min Dist (m)';
    ax.XGrid = 'on'; ax.YGrid = 'on'; ax.Box = 'on';
    hold(ax, 'on');

    mainLine = plot(ax, NaN, NaN, '-b', 'LineWidth', 1.5);
    safeLine = yline(ax, 5, '--r', 'LineWidth', 1, 'Label', 'Safe Dist');
    app.setState('collision', 'plot_line', mainLine);
    app.setState('collision', 'safe_line', safeLine);
end

function onStep(app)
    safeDist = app.getState('collision', 'safeDist');
    if isempty(safeDist), safeDist = 5; end

    N = app.NumUAVs;
    minDist = inf;

    for i = 1:N
        for j = (i+1):N
            d = norm(app.UAVPositions(i,:) - app.UAVPositions(j,:));
            if d < minDist, minDist = d; end

            if d < safeDist
                % Emergency separation
                sepVec = app.UAVPositions(i,:) - app.UAVPositions(j,:);
                sepVec = sepVec / max(norm(sepVec), 0.01);
                force = (safeDist - d) * 3;
                app.UAVPositions(i,:) = app.UAVPositions(i,:) + sepVec * force * app.dt;
                app.UAVPositions(j,:) = app.UAVPositions(j,:) - sepVec * force * app.dt;

                if d < safeDist * 0.4
                    % Collision
                    cc = app.getState('collision', 'collisionCount');
                    app.setState('collision', 'collisionCount', cc + 1);
                    app.logMsg(sprintf('COLLISION: UAV-%d <-> UAV-%d (%.1fm)', i, j, d));
                elseif d < safeDist
                    % Near miss
                    nm = app.getState('collision', 'nearMissCount');
                    app.setState('collision', 'nearMissCount', nm + 1);
                end
            end
        end
    end

    % History
    mh = app.getState('collision', 'minDist_hist');
    th = app.getState('collision', 't_hist');
    mh(end+1) = minDist;
    th(end+1) = app.SimTime;
    if length(th) > 1000
        mh = mh(end-999:end); th = th(end-999:end);
    end
    app.setState('collision', 'minDist_hist', mh);
    app.setState('collision', 't_hist', th);

    % Update UI
    try
        nmLbl = findobj(app.Fig, 'Tag', 'col_nearmiss_lbl');
        colLbl = findobj(app.Fig, 'Tag', 'col_collision_lbl');
        nm = app.getState('collision', 'nearMissCount');
        cc = app.getState('collision', 'collisionCount');
        if ~isempty(nmLbl), nmLbl.Text = sprintf('Near-Misses: %d', nm); end
        if ~isempty(colLbl), colLbl.Text = sprintf('Collisions: %d', cc); end

        pl = app.getState('collision', 'plot_line');
        if ~isempty(pl) && length(th) > 1
            pl.XData = th; pl.YData = mh;
        end

        sl = app.getState('collision', 'safe_line');
        if ~isempty(sl), sl.Value = safeDist; end
    catch
    end
end
