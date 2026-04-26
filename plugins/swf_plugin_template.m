function plugin = swf_plugin_template()
    % SWF_PLUGIN_TEMPLATE  Reference template for SwarmFly plugins.
    %
    % To create a new plugin:
    %   1. Copy this file to plugins/swf_yourname.m
    %   2. Fill in the struct fields below
    %   3. Implement onLoad, buildTab, onStep, onUnload as needed
    %   4. Restart SwarmFly or click "Rescan Plugins Folder"
    %
    % The plugin struct MUST have 'id' and 'name'. All other fields are optional.
    %
    % Plugin State Storage:
    %   app.setState('your_id', 'key', value)   — store data
    %   app.getState('your_id', 'key')           — retrieve data
    %
    % Available App Properties (read in onStep):
    %   app.UAVPositions   — [4x3] current x,y,z
    %   app.UAVHeadings    — [4x1] radians
    %   app.UAVRoles       — {4x1} cell of role strings
    %   app.TelHistory     — struct array with .x .y .z .t .ax .ay .az etc.
    %   app.SimTime        — current sim clock (seconds)
    %   app.dt             — time step
    %   app.SwarmMode      — current mode string
    %   app.NumUAVs        — always 4
    %   app.CruiseSpeed, app.CruiseAlt, app.MaxSwarmDist, app.CommRange
    %   app.WindSpeed, app.WindDir
    %   app.Waypoints, app.WaypointIdx
    %
    % Available App Methods:
    %   app.logMsg('text')                  — write to event log
    %   app.getUAVPosition(k)               — [1x3]
    %   app.setUAVPosition(k, [x y z])      — override position
    %   app.getTelemetry(k)                  — full history struct
    %   app.setWaypoints([x1 y1; x2 y2])    — load waypoints
    %   app.setState(id, key, val)           — plugin state storage
    %   app.getState(id, key)                — plugin state retrieval

    plugin = struct();

    % --- REQUIRED ---
    plugin.id          = 'template';          % unique, valid MATLAB field name
    plugin.name        = 'Template Plugin';   % display name

    % --- OPTIONAL ---
    plugin.description = 'A reference plugin that does nothing. Copy and modify.';
    plugin.version     = '1.0';
    plugin.hasTab      = true;    % set true to get a GUI tab
    plugin.hasStep     = true;    % set true to run every simulation tick
    plugin.hasToolbar  = false;   % reserved for future toolbar integration

    % --- CALLBACKS ---
    plugin.onLoad    = @(app) onLoad(app);
    plugin.onUnload  = @(app) onUnload(app);
    plugin.buildTab  = @(app, tab) buildTab(app, tab);
    plugin.onStep    = @(app) onStep(app);
end

%% === IMPLEMENTATION =====================================================

function onLoad(app)
    % Called once when the plugin is enabled.
    % Initialize your state here.
    app.setState('template', 'counter', 0);
    app.logMsg('Template plugin loaded.');
end

function onUnload(app)
    % Called when the plugin is disabled.
    % Clean up any external resources here.
    app.logMsg('Template plugin unloaded.');
end

function buildTab(app, tab)
    % Build your plugin's GUI inside the provided tab.
    grid = uigridlayout(tab, [3, 1], ...
        'RowHeight', {30, 30, '1x'}, ...
        'Padding', [20 20 20 20]);

    lbl = uilabel(grid, 'Text', 'This is the template plugin tab.', ...
        'FontSize', 14, 'FontWeight', 'bold');
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;

    counterLbl = uilabel(grid, 'Text', 'Step count: 0', 'Tag', 'template_counter');
    counterLbl.Layout.Row = 2; counterLbl.Layout.Column = 1;
end

function onStep(app)
    % Called every simulation tick while plugin is enabled.
    % Keep this fast — it runs at the sim update rate.
    count = app.getState('template', 'counter');
    if isempty(count), count = 0; end
    count = count + 1;
    app.setState('template', 'counter', count);

    % Update UI (find by tag if needed)
    % Note: accessing UI from timer callback requires the handle to be valid
end
