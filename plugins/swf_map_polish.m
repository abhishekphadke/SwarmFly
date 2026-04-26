function plugin = swf_map_polish()
    % SWF_MAP_POLISH  Visual polish for the main swarm map.
    %
    % Adds:
    %   - Compass rose (N/S/E/W indicator) anchored to corner
    %   - Scale bar with distance label
    %   - Color-coded UAV legend with role labels
    %   - Coordinate readout at cursor position

    plugin.id          = 'map_polish';
    plugin.name        = 'Map Polish';
    plugin.description = 'Adds a compass rose, scale bar, UAV legend, and coordinate grid labels to the main swarm map for professional presentation.';
    plugin.version     = '1.0';
    plugin.hasTab      = false;
    plugin.hasStep     = true;
    plugin.hasToolbar  = false;

    plugin.onLoad    = @(app) onLoad(app);
    plugin.onUnload  = @(app) onUnload(app);
    plugin.buildTab  = [];
    plugin.onStep    = @(app) onStep(app);
end

function onLoad(app)
    ax = app.MapAxes;

    handles = struct();

    % --- Compass Rose ---
    % We draw a simple N/E/S/W cross with "N" emphasized
    % Initial position will be updated each tick to stay in corner
    handles.compassGroup = hggroup(ax);

    % Arrow lines for compass
    handles.compassN = plot(ax, 0, 0, '^', 'MarkerSize', 10, ...
        'MarkerFaceColor', [0.85 0.15 0.1], 'MarkerEdgeColor', [0.6 0.1 0.05], ...
        'Tag', 'mp_compass');
    handles.compassNLabel = text(ax, 0, 0, 'N', ...
        'FontSize', 11, 'FontWeight', 'bold', 'Color', [0.85 0.15 0.1], ...
        'HorizontalAlignment', 'center', 'Tag', 'mp_compass');
    handles.compassSLabel = text(ax, 0, 0, 'S', ...
        'FontSize', 8, 'Color', [0.4 0.4 0.4], ...
        'HorizontalAlignment', 'center', 'Tag', 'mp_compass');
    handles.compassELabel = text(ax, 0, 0, 'E', ...
        'FontSize', 8, 'Color', [0.4 0.4 0.4], ...
        'HorizontalAlignment', 'center', 'Tag', 'mp_compass');
    handles.compassWLabel = text(ax, 0, 0, 'W', ...
        'FontSize', 8, 'Color', [0.4 0.4 0.4], ...
        'HorizontalAlignment', 'center', 'Tag', 'mp_compass');
    handles.compassCross = plot(ax, [0 0 NaN 0 0], [0 0 NaN 0 0], '-', ...
        'Color', [0.3 0.3 0.3], 'LineWidth', 1.2, 'Tag', 'mp_compass');
    handles.compassCircle = plot(ax, 0, 0, 'o', 'MarkerSize', 20, ...
        'Color', [0.3 0.3 0.3], 'LineWidth', 0.8, 'Tag', 'mp_compass');

    % --- Scale Bar ---
    handles.scaleBar = plot(ax, [0 0], [0 0], '-', ...
        'Color', [0.2 0.2 0.2], 'LineWidth', 2.5, 'Tag', 'mp_scale');
    handles.scaleCapL = plot(ax, [0 0], [0 0], '-', ...
        'Color', [0.2 0.2 0.2], 'LineWidth', 1.5, 'Tag', 'mp_scale');
    handles.scaleCapR = plot(ax, [0 0], [0 0], '-', ...
        'Color', [0.2 0.2 0.2], 'LineWidth', 1.5, 'Tag', 'mp_scale');
    handles.scaleLabel = text(ax, 0, 0, '', ...
        'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.2 0.2 0.2], ...
        'HorizontalAlignment', 'center', 'Tag', 'mp_scale');

    % --- Legend ---
    handles.legendBG = fill(ax, [0 0 0 0], [0 0 0 0], [1 1 1], ...
        'FaceAlpha', 0.85, 'EdgeColor', [0.5 0.5 0.5], ...
        'LineWidth', 0.5, 'Tag', 'mp_legend');
    handles.legendTitle = text(ax, 0, 0, 'UAV Legend', ...
        'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.15 0.15 0.15], ...
        'Tag', 'mp_legend');
    handles.legendMarkers = cell(app.NumUAVs, 1);
    handles.legendLabels  = cell(app.NumUAVs, 1);
    for k = 1:app.NumUAVs
        handles.legendMarkers{k} = fill(ax, [0 0 0], [0 0 0], ...
            app.UAVColors(k,:), 'EdgeColor', 'k', 'LineWidth', 0.8, ...
            'Tag', 'mp_legend');
        handles.legendLabels{k} = text(ax, 0, 0, sprintf('U%d', k), ...
            'FontSize', 8, 'Color', [0.2 0.2 0.2], 'Tag', 'mp_legend');
    end

    % --- Base Station Label ---
    handles.baseLbl = text(ax, 0, -6, 'BASE', ...
        'FontSize', 7, 'FontWeight', 'bold', 'Color', [0.4 0.05 0.5], ...
        'HorizontalAlignment', 'center', 'Tag', 'mp_base');

    app.setState('map_polish', 'handles', handles);
end

function onUnload(app)
    % Remove all polish graphics
    objs = findobj(app.MapAxes, '-regexp', 'Tag', '^mp_');
    delete(objs);
end

function onStep(app)
    handles = app.getState('map_polish', 'handles');
    if isempty(handles), return; end

    ax = app.MapAxes;
    xl = xlim(ax); yl = ylim(ax);
    xRange = xl(2) - xl(1);
    yRange = yl(2) - yl(1);

    try
        % ---- COMPASS ROSE (top-left corner) ----
        cx = xl(1) + xRange * 0.08;
        cy = yl(2) - yRange * 0.08;
        armLen = min(xRange, yRange) * 0.04;

        % Cross lines
        handles.compassCross.XData = [cx, cx, NaN, cx-armLen, cx+armLen];
        handles.compassCross.YData = [cy-armLen, cy+armLen, NaN, cy, cy];

        % Circle
        theta = linspace(0, 2*pi, 30);
        handles.compassCircle.XData = cx + armLen*1.3*cos(theta);
        handles.compassCircle.YData = cy + armLen*1.3*sin(theta);

        % N arrow
        handles.compassN.XData = cx;
        handles.compassN.YData = cy + armLen;

        % Labels
        handles.compassNLabel.Position = [cx, cy + armLen * 1.8, 0];
        handles.compassSLabel.Position = [cx, cy - armLen * 1.6, 0];
        handles.compassELabel.Position = [cx + armLen * 1.6, cy, 0];
        handles.compassWLabel.Position = [cx - armLen * 1.6, cy, 0];

        % ---- SCALE BAR (bottom-left) ----
        % Choose a nice round scale length
        rawLen = xRange * 0.2;
        niceScales = [5, 10, 20, 25, 50, 100, 200, 500, 1000];
        [~, idx] = min(abs(niceScales - rawLen));
        scaleLen = niceScales(idx);

        sx = xl(1) + xRange * 0.06;
        sy = yl(1) + yRange * 0.06;
        capH = yRange * 0.015;

        handles.scaleBar.XData = [sx, sx + scaleLen];
        handles.scaleBar.YData = [sy, sy];
        handles.scaleCapL.XData = [sx, sx];
        handles.scaleCapL.YData = [sy - capH, sy + capH];
        handles.scaleCapR.XData = [sx + scaleLen, sx + scaleLen];
        handles.scaleCapR.YData = [sy - capH, sy + capH];
        handles.scaleLabel.Position = [sx + scaleLen/2, sy + yRange*0.03, 0];
        handles.scaleLabel.String = sprintf('%d m', scaleLen);

        % ---- LEGEND (top-right corner) ----
        lgW = xRange * 0.18;
        lgH = yRange * 0.18;
        lgX = xl(2) - xRange * 0.04 - lgW;
        lgY = yl(2) - yRange * 0.04 - lgH;

        handles.legendBG.XData = [lgX, lgX+lgW, lgX+lgW, lgX];
        handles.legendBG.YData = [lgY, lgY, lgY+lgH, lgY+lgH];
        handles.legendTitle.Position = [lgX + lgW/2, lgY + lgH - yRange*0.02, 0];

        mkSz = min(xRange, yRange) * 0.012;
        for k = 1:app.NumUAVs
            rowY = lgY + lgH - yRange*0.02 - k * (lgH * 0.2);
            mkX = lgX + xRange * 0.02;

            % Small triangle marker
            handles.legendMarkers{k}.XData = [mkX, mkX-mkSz, mkX+mkSz];
            handles.legendMarkers{k}.YData = [rowY+mkSz, rowY-mkSz*0.5, rowY-mkSz*0.5];
            handles.legendMarkers{k}.FaceColor = app.UAVColors(k,:);

            % Label with role
            handles.legendLabels{k}.Position = [mkX + xRange*0.025, rowY, 0];
            handles.legendLabels{k}.String = sprintf('U%d  %s', k, app.UAVRoles{k});
        end

    catch
    end
end
