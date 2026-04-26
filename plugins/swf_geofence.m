function plugin = swf_geofence()
    % SWF_GEOFENCE  No-fly zones and geofencing on the swarm map.
    %
    % Features:
    %   - Predefined circular and rectangular no-fly zones
    %   - Click-to-place custom zones
    %   - Visual overlays on the map (red shaded regions)
    %   - Enforcement: repulsion force when UAVs approach zone boundaries
    %   - Perimeter fence (max operating radius from base)
    %   - Violation counter and logging

    plugin.id          = 'geofence';
    plugin.name        = 'Geofencing';
    plugin.description = 'Define no-fly zones (circular/rectangular) on the map. UAVs are repelled from zone boundaries. Includes a perimeter fence for max operating radius.';
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
    % Zone format: struct array
    %   type: 'circle' or 'rect'
    %   cx, cy, radius (circle)  OR  x, y, w, h (rect)
    %   name: label string
    zones = struct('type',{},'cx',{},'cy',{},'radius',{}, ...
                   'x',{},'y',{},'w',{},'h',{},'name',{});

    % Default demo zones
    zones(1).type = 'circle'; zones(1).cx = 80; zones(1).cy = 60;
    zones(1).radius = 25; zones(1).name = 'Tower';
    zones(1).x = 0; zones(1).y = 0; zones(1).w = 0; zones(1).h = 0;

    zones(2).type = 'rect'; zones(2).x = -100; zones(2).y = -80;
    zones(2).w = 40; zones(2).h = 50; zones(2).name = 'Building';
    zones(2).cx = 0; zones(2).cy = 0; zones(2).radius = 0;

    app.setState('geofence', 'zones', zones);
    app.setState('geofence', 'perimeterRadius', 200);
    app.setState('geofence', 'enforcePerimeter', true);
    app.setState('geofence', 'enforceZones', true);
    app.setState('geofence', 'repulsionStrength', 5.0);
    app.setState('geofence', 'violations', 0);
    app.setState('geofence', 'gfxHandles', {});

    % Draw initial zones on map
    drawZonesOnMap(app);
end

function onUnload(app)
    % Remove graphics from map
    gfx = app.getState('geofence', 'gfxHandles');
    if ~isempty(gfx)
        for i = 1:length(gfx)
            try delete(gfx{i}); catch; end
        end
    end
end

function buildTab(app, tab)
    grid = uigridlayout(tab, [3, 1], ...
        'RowHeight', {160, 60, '1x'}, ...
        'Padding', [12 12 12 12], 'RowSpacing', 8);

    % --- Controls Panel ---
    ctrlPanel = uipanel(grid, 'Title', 'Geofence Controls', ...
        'FontWeight', 'bold', 'FontSize', 12);
    ctrlPanel.Layout.Row = 1; ctrlPanel.Layout.Column = 1;

    cg = uigridlayout(ctrlPanel, [5, 4], ...
        'RowHeight', {26, 26, 26, 26, 32}, ...
        'ColumnWidth', {140, '1x', 100, 100}, ...
        'Padding', [10 8 10 8], 'RowSpacing', 4);

    % Perimeter radius
    lbl = uilabel(cg, 'Text', 'Perimeter Radius (m):');
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;
    prSlider = uislider(cg, 'Limits', [50 500], 'Value', 200, ...
        'ValueChangedFcn', @(src,~) app.setState('geofence', 'perimeterRadius', round(src.Value)));
    prSlider.Layout.Row = 1; prSlider.Layout.Column = [2 3];
    prLbl = uilabel(cg, 'Text', '200 m');
    prLbl.Layout.Row = 1; prLbl.Layout.Column = 4;
    prSlider.ValueChangedFcn = @(src,~) onPerimeterChanged(app, src, prLbl);

    % Repulsion strength
    lbl = uilabel(cg, 'Text', 'Repulsion Strength:');
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    rsSlider = uislider(cg, 'Limits', [1 20], 'Value', 5, ...
        'ValueChangedFcn', @(src,~) app.setState('geofence', 'repulsionStrength', round(src.Value, 1)));
    rsSlider.Layout.Row = 2; rsSlider.Layout.Column = [2 3];

    % Toggles
    enfZone = uicheckbox(cg, 'Text', 'Enforce No-Fly Zones', 'Value', true, ...
        'ValueChangedFcn', @(src,~) app.setState('geofence', 'enforceZones', src.Value));
    enfZone.Layout.Row = 3; enfZone.Layout.Column = [1 2];

    enfPeri = uicheckbox(cg, 'Text', 'Enforce Perimeter', 'Value', true, ...
        'ValueChangedFcn', @(src,~) app.setState('geofence', 'enforcePerimeter', src.Value));
    enfPeri.Layout.Row = 3; enfPeri.Layout.Column = [3 4];

    % Add zone buttons
    addCircBtn = uibutton(cg, 'push', 'Text', 'Add Circle Zone', ...
        'BackgroundColor', [0.85 0.25 0.2], 'FontColor', 'w', ...
        'ButtonPushedFcn', @(~,~) startAddCircle(app));
    addCircBtn.Layout.Row = 5; addCircBtn.Layout.Column = [1 2];

    addRectBtn = uibutton(cg, 'push', 'Text', 'Add Rect Zone', ...
        'BackgroundColor', [0.85 0.25 0.2], 'FontColor', 'w', ...
        'ButtonPushedFcn', @(~,~) startAddRect(app));
    addRectBtn.Layout.Row = 5; addRectBtn.Layout.Column = 3;

    clearBtn = uibutton(cg, 'push', 'Text', 'Clear All', ...
        'ButtonPushedFcn', @(~,~) clearAllZones(app));
    clearBtn.Layout.Row = 5; clearBtn.Layout.Column = 4;

    % --- Status ---
    statusGrid = uigridlayout(grid, [1, 3], ...
        'ColumnWidth', {'1x', '1x', '1x'}, 'Padding', [0 0 0 0]);
    statusGrid.Layout.Row = 2; statusGrid.Layout.Column = 1;

    vLbl = uilabel(statusGrid, 'Text', 'Violations: 0', ...
        'FontSize', 14, 'FontWeight', 'bold', 'FontColor', [0.85 0.2 0.15], ...
        'Tag', 'gf_violations');
    vLbl.Layout.Row = 1; vLbl.Layout.Column = 1;

    zLbl = uilabel(statusGrid, 'Text', 'Zones: 2', ...
        'FontSize', 14, 'FontWeight', 'bold', ...
        'Tag', 'gf_zone_count');
    zLbl.Layout.Row = 1; zLbl.Layout.Column = 2;

    pLbl = uilabel(statusGrid, 'Text', 'Perimeter: 200m', ...
        'FontSize', 14, 'FontWeight', 'bold', 'FontColor', [0.2 0.5 0.8], ...
        'Tag', 'gf_perimeter_lbl');
    pLbl.Layout.Row = 1; pLbl.Layout.Column = 3;

    % --- Zone List Table ---
    tblPanel = uipanel(grid, 'Title', 'Defined Zones', ...
        'FontWeight', 'bold', 'FontSize', 12);
    tblPanel.Layout.Row = 3; tblPanel.Layout.Column = 1;

    tbl = uitable(tblPanel, ...
        'ColumnName', {'Name', 'Type', 'Position', 'Size'}, ...
        'ColumnWidth', {120, 80, 160, 100}, ...
        'Tag', 'gf_zone_table', ...
        'Position', [10 10 500 200]);
    updateZoneTable(app);
end

function onPerimeterChanged(app, src, lbl)
    val = round(src.Value);
    app.setState('geofence', 'perimeterRadius', val);
    lbl.Text = sprintf('%d m', val);
    drawZonesOnMap(app);
end

function startAddCircle(app)
    app.logMsg('Click on the map to place a circular no-fly zone...');
    app.MapAxes.ButtonDownFcn = @(~, evt) finishAddCircle(app, evt);
end

function finishAddCircle(app, evt)
    pt = evt.IntersectionPoint(1:2);
    zones = app.getState('geofence', 'zones');
    nz = length(zones) + 1;
    zones(nz).type = 'circle';
    zones(nz).cx = pt(1); zones(nz).cy = pt(2);
    zones(nz).radius = 20;
    zones(nz).name = sprintf('NFZ-%d', nz);
    zones(nz).x = 0; zones(nz).y = 0; zones(nz).w = 0; zones(nz).h = 0;
    app.setState('geofence', 'zones', zones);
    app.MapAxes.ButtonDownFcn = '';
    drawZonesOnMap(app);
    updateZoneTable(app);
    app.logMsg(sprintf('Circle NFZ added at (%.0f, %.0f) r=20m', pt(1), pt(2)));
end

function startAddRect(app)
    app.logMsg('Click on the map to place a rectangular no-fly zone...');
    app.MapAxes.ButtonDownFcn = @(~, evt) finishAddRect(app, evt);
end

function finishAddRect(app, evt)
    pt = evt.IntersectionPoint(1:2);
    zones = app.getState('geofence', 'zones');
    nz = length(zones) + 1;
    zones(nz).type = 'rect';
    zones(nz).x = pt(1) - 15; zones(nz).y = pt(2) - 15;
    zones(nz).w = 30; zones(nz).h = 30;
    zones(nz).name = sprintf('NFZ-%d', nz);
    zones(nz).cx = 0; zones(nz).cy = 0; zones(nz).radius = 0;
    app.setState('geofence', 'zones', zones);
    app.MapAxes.ButtonDownFcn = '';
    drawZonesOnMap(app);
    updateZoneTable(app);
    app.logMsg(sprintf('Rect NFZ added at (%.0f, %.0f) 30x30m', pt(1), pt(2)));
end

function clearAllZones(app)
    app.setState('geofence', 'zones', struct('type',{},'cx',{},'cy',{},'radius',{}, ...
        'x',{},'y',{},'w',{},'h',{},'name',{}));
    app.setState('geofence', 'violations', 0);
    drawZonesOnMap(app);
    updateZoneTable(app);
    app.logMsg('All geofence zones cleared.');
end

function drawZonesOnMap(app)
    % Clear old geofence graphics
    gfx = app.getState('geofence', 'gfxHandles');
    if ~isempty(gfx)
        for i = 1:length(gfx)
            try delete(gfx{i}); catch; end
        end
    end
    newGfx = {};

    ax = app.MapAxes;
    zones = app.getState('geofence', 'zones');

    % Draw no-fly zones
    for i = 1:length(zones)
        z = zones(i);
        if strcmp(z.type, 'circle')
            theta = linspace(0, 2*pi, 60);
            cx = z.cx + z.radius * cos(theta);
            cy = z.cy + z.radius * sin(theta);
            h1 = fill(ax, cx, cy, [0.9 0.15 0.1], ...
                'FaceAlpha', 0.15, 'EdgeColor', [0.8 0.1 0.1], ...
                'LineWidth', 1.5, 'LineStyle', '--');
            h2 = text(ax, z.cx, z.cy, z.name, ...
                'HorizontalAlignment', 'center', 'FontSize', 8, ...
                'FontWeight', 'bold', 'Color', [0.7 0.05 0.05]);
            newGfx{end+1} = h1; %#ok<AGROW>
            newGfx{end+1} = h2; %#ok<AGROW>
        elseif strcmp(z.type, 'rect')
            rx = [z.x, z.x+z.w, z.x+z.w, z.x];
            ry = [z.y, z.y, z.y+z.h, z.y+z.h];
            h1 = fill(ax, rx, ry, [0.9 0.15 0.1], ...
                'FaceAlpha', 0.15, 'EdgeColor', [0.8 0.1 0.1], ...
                'LineWidth', 1.5, 'LineStyle', '--');
            h2 = text(ax, z.x + z.w/2, z.y + z.h/2, z.name, ...
                'HorizontalAlignment', 'center', 'FontSize', 8, ...
                'FontWeight', 'bold', 'Color', [0.7 0.05 0.05]);
            newGfx{end+1} = h1; %#ok<AGROW>
            newGfx{end+1} = h2; %#ok<AGROW>
        end
    end

    % Draw perimeter fence
    pr = app.getState('geofence', 'perimeterRadius');
    if ~isempty(pr) && pr > 0
        theta = linspace(0, 2*pi, 80);
        px = pr * cos(theta);
        py = pr * sin(theta);
        h1 = plot(ax, px, py, '-.', 'Color', [0.2 0.5 0.85, 0.6], 'LineWidth', 1.5);
        h2 = text(ax, pr*0.7, pr*0.7, sprintf('Perimeter %dm', pr), ...
            'FontSize', 8, 'Color', [0.15 0.4 0.7]);
        newGfx{end+1} = h1;
        newGfx{end+1} = h2;
    end

    app.setState('geofence', 'gfxHandles', newGfx);
end

function updateZoneTable(app)
    try
        tbl = findobj(app.Fig, 'Tag', 'gf_zone_table');
        zones = app.getState('geofence', 'zones');
        zLbl = findobj(app.Fig, 'Tag', 'gf_zone_count');

        if ~isempty(tbl) && ~isempty(zones)
            data = cell(length(zones), 4);
            for i = 1:length(zones)
                z = zones(i);
                data{i,1} = z.name;
                data{i,2} = z.type;
                if strcmp(z.type, 'circle')
                    data{i,3} = sprintf('(%.0f, %.0f)', z.cx, z.cy);
                    data{i,4} = sprintf('r=%.0f', z.radius);
                else
                    data{i,3} = sprintf('(%.0f, %.0f)', z.x, z.y);
                    data{i,4} = sprintf('%.0fx%.0f', z.w, z.h);
                end
            end
            tbl.Data = data;
        elseif ~isempty(tbl)
            tbl.Data = cell(0, 4);
        end
        if ~isempty(zLbl)
            zLbl.Text = sprintf('Zones: %d', length(zones));
        end
    catch
    end
end

function onStep(app)
    zones = app.getState('geofence', 'zones');
    enfZones = app.getState('geofence', 'enforceZones');
    enfPeri  = app.getState('geofence', 'enforcePerimeter');
    repStr   = app.getState('geofence', 'repulsionStrength');
    periR    = app.getState('geofence', 'perimeterRadius');
    violations = app.getState('geofence', 'violations');

    if isempty(repStr), repStr = 5; end
    if isempty(violations), violations = 0; end

    N = app.NumUAVs;
    dt = app.dt;

    for k = 1:N
        px = app.UAVPositions(k,1);
        py = app.UAVPositions(k,2);

        % Check no-fly zones
        if ~isempty(enfZones) && enfZones && ~isempty(zones)
            for i = 1:length(zones)
                z = zones(i);
                if strcmp(z.type, 'circle')
                    d = sqrt((px - z.cx)^2 + (py - z.cy)^2);
                    if d < z.radius
                        % Inside zone — repel outward
                        violations = violations + 1;
                        dir = [px - z.cx, py - z.cy];
                        dir = dir / max(norm(dir), 0.01);
                        force = repStr * (z.radius - d) / z.radius;
                        app.UAVPositions(k,1:2) = app.UAVPositions(k,1:2) + dir * force * dt;
                    elseif d < z.radius + 8
                        % Near boundary — gentle push
                        dir = [px - z.cx, py - z.cy];
                        dir = dir / max(norm(dir), 0.01);
                        force = repStr * 0.3 * (z.radius + 8 - d) / 8;
                        app.UAVPositions(k,1:2) = app.UAVPositions(k,1:2) + dir * force * dt;
                    end
                elseif strcmp(z.type, 'rect')
                    if px > z.x && px < z.x + z.w && py > z.y && py < z.y + z.h
                        % Inside rect — find nearest edge and push out
                        violations = violations + 1;
                        dists = [px - z.x, z.x + z.w - px, py - z.y, z.y + z.h - py];
                        [~, edge] = min(dists);
                        pushDir = [0 0];
                        switch edge
                            case 1, pushDir = [-1, 0];
                            case 2, pushDir = [1, 0];
                            case 3, pushDir = [0, -1];
                            case 4, pushDir = [0, 1];
                        end
                        app.UAVPositions(k,1:2) = app.UAVPositions(k,1:2) + pushDir * repStr * dt;
                    end
                end
            end
        end

        % Check perimeter fence
        if ~isempty(enfPeri) && enfPeri && ~isempty(periR)
            distFromBase = norm([px, py]);
            if distFromBase > periR
                % Outside perimeter — push back toward base
                violations = violations + 1;
                dir = -[px, py] / max(distFromBase, 0.01);
                force = repStr * (distFromBase - periR) / periR * 2;
                app.UAVPositions(k,1:2) = app.UAVPositions(k,1:2) + dir * force * dt;
            elseif distFromBase > periR * 0.9
                % Near boundary — gentle push
                dir = -[px, py] / max(distFromBase, 0.01);
                force = repStr * 0.2;
                app.UAVPositions(k,1:2) = app.UAVPositions(k,1:2) + dir * force * dt;
            end
        end
    end

    app.setState('geofence', 'violations', violations);

    % Update violation label
    try
        vLbl = findobj(app.Fig, 'Tag', 'gf_violations');
        if ~isempty(vLbl)
            vLbl.Text = sprintf('Violations: %d', violations);
        end
        pLbl = findobj(app.Fig, 'Tag', 'gf_perimeter_lbl');
        if ~isempty(pLbl)
            pLbl.Text = sprintf('Perimeter: %dm', periR);
        end
    catch
    end
end
