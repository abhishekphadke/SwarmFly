function plugin = swf_metrics()
    % SWF_METRICS  Real-time KPI dashboard for swarm performance.
    %
    % Tracks: Swarm Spread, Mean Inter-UAV Distance, Centroid Drift,
    %         Formation Error, Altitude Deviation, Link Quality

    plugin.id          = 'metrics';
    plugin.name        = 'Metrics Dashboard';
    plugin.description = 'Real-time KPI plots: swarm spread, inter-UAV distance, centroid drift, formation error, altitude deviation, and communication link quality.';
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
    app.setState('metrics', 'spread',   []);
    app.setState('metrics', 'meanDist', []);
    app.setState('metrics', 'drift',    []);
    app.setState('metrics', 'formErr',  []);
    app.setState('metrics', 'altDev',   []);
    app.setState('metrics', 'linkQ',    []);
    app.setState('metrics', 't',        []);
    app.setState('metrics', 'lines',    {});
end

function onUnload(~)
end

function buildTab(app, tab)
    grid = uigridlayout(tab, [2, 3], ...
        'Padding', [10 10 10 10], 'RowSpacing', 10, 'ColumnSpacing', 10);

    titles = {'Swarm Spread (m)', 'Mean Inter-UAV Dist (m)', ...
              'Centroid Drift from Base (m)', ...
              'Formation Error (m)', 'Altitude Deviation (m)', ...
              'Link Quality (%)'};
    colors = {[0.2 0.4 0.9], [0.9 0.3 0.2], [0.1 0.7 0.3], ...
              [0.8 0.5 0.1], [0.6 0.2 0.8], [0.1 0.6 0.6]};

    lineHandles = cell(1, 6);
    for k = 1:6
        r = ceil(k/3); c = mod(k-1,3)+1;
        ax = uiaxes(grid);
        ax.Layout.Row = r; ax.Layout.Column = c;
        ax.Title.String = titles{k};
        ax.XLabel.String = 'Time (s)';
        ax.XGrid = 'on'; ax.YGrid = 'on';
        ax.Color = [0.98 0.98 1.0]; ax.Box = 'on';
        hold(ax, 'on');
        lineHandles{k} = plot(ax, NaN, NaN, '-', 'Color', colors{k}, 'LineWidth', 1.8);
    end

    app.setState('metrics', 'lines', lineHandles);
end

function onStep(app)
    pos = app.UAVPositions;
    N = app.NumUAVs;

    % Compute pairwise distances
    dists = zeros(N*(N-1)/2, 1);
    idx = 0;
    for i = 1:N
        for j = (i+1):N
            idx = idx + 1;
            dists(idx) = norm(pos(i,1:2) - pos(j,1:2));
        end
    end

    % 1. Swarm spread
    spread = app.getState('metrics', 'spread');
    spread(end+1) = max(dists);
    app.setState('metrics', 'spread', spread);

    % 2. Mean inter-UAV distance
    md = app.getState('metrics', 'meanDist');
    md(end+1) = mean(dists);
    app.setState('metrics', 'meanDist', md);

    % 3. Centroid drift from base
    dr = app.getState('metrics', 'drift');
    centroid = mean(pos(:,1:2), 1);
    dr(end+1) = norm(centroid);
    app.setState('metrics', 'drift', dr);

    % 4. Formation error
    fe = app.getState('metrics', 'formErr');
    li = app.LeaderIdx;
    base = [0,0,0; -20,-12,0; 20,-12,0; 0,-24,0];
    offsets = (base - base(li,:)) * (app.MaxSwarmDist/50);
    err = 0;
    cnt = 0;
    for k = 1:N
        if k == li, continue; end
        ideal = pos(li,:) + offsets(k,:);
        err = err + norm(pos(k,:) - ideal);
        cnt = cnt + 1;
    end
    fe(end+1) = err / max(cnt, 1);
    app.setState('metrics', 'formErr', fe);

    % 5. Altitude deviation
    ad = app.getState('metrics', 'altDev');
    ad(end+1) = mean(abs(pos(:,3) - app.CruiseAlt));
    app.setState('metrics', 'altDev', ad);

    % 6. Link quality
    lq = app.getState('metrics', 'linkQ');
    withinRange = sum(dists < app.CommRange);
    totalPairs = N*(N-1)/2;
    lq(end+1) = 100 * withinRange / totalPairs;
    app.setState('metrics', 'linkQ', lq);

    % Time
    t = app.getState('metrics', 't');
    t(end+1) = app.SimTime;
    app.setState('metrics', 't', t);

    % Trim to 1000 samples
    maxLen = 1000;
    if length(t) > maxLen
        trim = length(t) - maxLen + 1;
        t = t(trim:end);       app.setState('metrics', 't', t);
        spread = spread(trim:end); app.setState('metrics', 'spread', spread);
        md = md(trim:end);     app.setState('metrics', 'meanDist', md);
        dr = dr(trim:end);     app.setState('metrics', 'drift', dr);
        fe = fe(trim:end);     app.setState('metrics', 'formErr', fe);
        ad = ad(trim:end);     app.setState('metrics', 'altDev', ad);
        lq = lq(trim:end);     app.setState('metrics', 'linkQ', lq);
    end

    % Update line graphics
    lineHandles = app.getState('metrics', 'lines');
    if isempty(lineHandles), return; end
    allData = {spread, md, dr, fe, ad, lq};
    for k = 1:6
        try
            lineHandles{k}.XData = t;
            lineHandles{k}.YData = allData{k};
        catch
        end
    end
end
