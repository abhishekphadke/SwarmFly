function plugin = swf_3d_view()
    % SWF_3D_VIEW  3D swarm visualization with altitude and formation.
    %
    % Shows UAVs as 3D markers with:
    %   - Altitude stems to ground plane
    %   - Inter-UAV connection lines
    %   - Ground shadow projections
    %   - Color-coded by role
    %   - Interactive rotation via MATLAB's rotate3d

    plugin.id          = 'view3d';
    plugin.name        = '3D View';
    plugin.description = 'Interactive 3D visualization of the swarm showing altitude, formation geometry, ground shadows, and inter-UAV links. Rotate/zoom with mouse.';
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
    app.setState('view3d', 'initialized', false);
end

function onUnload(~)
end

function buildTab(app, tab)
    grid = uigridlayout(tab, [1, 1], 'Padding', [6 6 6 6]);

    ax = uiaxes(grid);
    ax.Layout.Row = 1; ax.Layout.Column = 1;
    ax.Title.String = '3D Swarm View';
    ax.XLabel.String = 'East (m)';
    ax.YLabel.String = 'North (m)';
    ax.ZLabel.String = 'Altitude (m)';
    ax.XGrid = 'on'; ax.YGrid = 'on'; ax.ZGrid = 'on';
    ax.Color = [0.96 0.97 0.98];
    ax.Box = 'on';
    hold(ax, 'on');
    view(ax, [-37.5, 30]);
    ax.Projection = 'perspective';

    N = app.NumUAVs;

    % Ground plane grid
    gx = -150:30:150; gy = -150:30:150;
    [GX, GY] = meshgrid(gx, gy);
    GZ = zeros(size(GX));
    mesh(ax, GX, GY, GZ, 'FaceAlpha', 0.05, 'EdgeColor', [0.6 0.6 0.6], ...
        'EdgeAlpha', 0.3, 'FaceColor', [0.85 0.9 0.85]);

    % Base station marker on ground
    plot3(ax, 0, 0, 0, 'p', 'MarkerSize', 16, ...
        'MarkerFaceColor', [0.5 0.1 0.6], 'MarkerEdgeColor', 'k');

    % UAV markers (3D spheres approximated with filled circle markers)
    uavMarkers = cell(N, 1);
    uavStems   = cell(N, 1);
    uavShadows = cell(N, 1);
    uavLabels  = cell(N, 1);
    connLines3D = cell(6, 1);

    for k = 1:N
        % Altitude stem (vertical line to ground)
        uavStems{k} = plot3(ax, [0 0], [0 0], [0 30], ':', ...
            'Color', [app.UAVColors(k,:), 0.5], 'LineWidth', 1);

        % Ground shadow
        uavShadows{k} = plot3(ax, 0, 0, 0, 'o', 'MarkerSize', 6, ...
            'MarkerFaceColor', [0.4 0.4 0.4], 'MarkerEdgeColor', 'none');

        % UAV marker in air
        uavMarkers{k} = plot3(ax, 0, 0, 30, '^', 'MarkerSize', 12, ...
            'MarkerFaceColor', app.UAVColors(k,:), ...
            'MarkerEdgeColor', app.UAVColors(k,:) * 0.6, ...
            'LineWidth', 1.5);

        % Label
        uavLabels{k} = text(ax, 0, 0, 35, sprintf('U%d', k), ...
            'FontSize', 9, 'FontWeight', 'bold', ...
            'Color', app.UAVColors(k,:) * 0.7, ...
            'HorizontalAlignment', 'center');
    end

    % Connection lines between UAVs in 3D
    idx = 0;
    for i = 1:N
        for j = (i+1):N
            idx = idx + 1;
            connLines3D{idx} = plot3(ax, [0 0], [0 0], [0 0], '-', ...
                'Color', [0.5 0.5 0.5, 0.4], 'LineWidth', 1);
        end
    end

    % Store handles
    app.setState('view3d', 'ax', ax);
    app.setState('view3d', 'uavMarkers', uavMarkers);
    app.setState('view3d', 'uavStems', uavStems);
    app.setState('view3d', 'uavShadows', uavShadows);
    app.setState('view3d', 'uavLabels', uavLabels);
    app.setState('view3d', 'connLines3D', connLines3D);
    app.setState('view3d', 'initialized', true);
end

function onStep(app)
    initialized = app.getState('view3d', 'initialized');
    if isempty(initialized) || ~initialized, return; end

    % Only update when 3D tab is visible (performance)
    ax = app.getState('view3d', 'ax');
    if isempty(ax) || ~isvalid(ax), return; end

    uavMarkers = app.getState('view3d', 'uavMarkers');
    uavStems   = app.getState('view3d', 'uavStems');
    uavShadows = app.getState('view3d', 'uavShadows');
    uavLabels  = app.getState('view3d', 'uavLabels');
    connLines3D = app.getState('view3d', 'connLines3D');

    N = app.NumUAVs;
    pos = app.UAVPositions;

    try
        for k = 1:N
            x = pos(k,1); y = pos(k,2); z = pos(k,3);

            % Update marker position
            uavMarkers{k}.XData = x;
            uavMarkers{k}.YData = y;
            uavMarkers{k}.ZData = z;

            % Update stem
            uavStems{k}.XData = [x, x];
            uavStems{k}.YData = [y, y];
            uavStems{k}.ZData = [0, z];

            % Update ground shadow
            uavShadows{k}.XData = x;
            uavShadows{k}.YData = y;
            uavShadows{k}.ZData = 0;

            % Update label
            uavLabels{k}.Position = [x, y, z + 5];
            uavLabels{k}.String = sprintf('U%d [%.0fm]', k, z);
        end

        % Update connection lines
        idx = 0;
        for i = 1:N
            for j = (i+1):N
                idx = idx + 1;
                d = norm(pos(i,:) - pos(j,:));
                if d < app.CommRange
                    connLines3D{idx}.XData = [pos(i,1), pos(j,1)];
                    connLines3D{idx}.YData = [pos(i,2), pos(j,2)];
                    connLines3D{idx}.ZData = [pos(i,3), pos(j,3)];
                    if d > app.MaxSwarmDist
                        connLines3D{idx}.Color = [0.9 0.2 0.1 0.6];
                    else
                        connLines3D{idx}.Color = [0.4 0.6 0.9, 0.5];
                    end
                    connLines3D{idx}.Visible = 'on';
                else
                    connLines3D{idx}.Visible = 'off';
                end
            end
        end

        % Dynamic axis limits
        margin = max(60, app.MaxSwarmDist * 1.2);
        allX = pos(:,1); allY = pos(:,2); allZ = pos(:,3);
        xlim(ax, [min(allX)-margin, max(allX)+margin]);
        ylim(ax, [min(allY)-margin, max(allY)+margin]);
        zlim(ax, [0, max(max(allZ)+20, app.CruiseAlt+30)]);

        % Title with altitude info
        ax.Title.String = sprintf('3D View | Alt: %.0f-%.0fm | T=%.1fs', ...
            min(allZ), max(allZ), app.SimTime);
    catch
    end
end
