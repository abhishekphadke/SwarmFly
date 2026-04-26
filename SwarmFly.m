classdef SwarmFly < handle
    % SWARMFLY - Drone Swarm Simulation & Test Platform
    % v2.0 — Integrated plugin architecture with GUI hooks.
    %
    % Plugins live in a 'plugins/' subfolder next to SwarmFly.m.
    % Each plugin is a function returning a struct (see swf_plugin_template.m).
    % The Modules tab discovers, loads, and manages plugins at runtime.
    %
    % Usage:
    %   app = SwarmFly();
    %
    % Author: SwarmFly Team    Version: 2.0.0    License: MIT

    %% ====================================================================
    %  PROPERTIES — CORE GUI
    %  ====================================================================
    properties (Access = public)
        Fig                 matlab.ui.Figure
        MainGrid            matlab.ui.container.GridLayout
        TabGroup            matlab.ui.container.TabGroup

        MapTab              matlab.ui.container.Tab
        TelemetryTab        matlab.ui.container.Tab
        SettingsTab         matlab.ui.container.Tab
        ModulesTab          matlab.ui.container.Tab

        % Map tab
        MapAxes             matlab.ui.control.UIAxes
        MapGrid             matlab.ui.container.GridLayout
        ControlPanel        matlab.ui.container.Panel
        ControlGrid         matlab.ui.container.GridLayout
        ModeDropdown        matlab.ui.control.DropDown
        ModeLabel           matlab.ui.control.Label
        MaxDistSlider       matlab.ui.control.Slider
        MaxDistLabel        matlab.ui.control.Label
        MaxDistValue        matlab.ui.control.Label
        AltSlider           matlab.ui.control.Slider
        AltLabel            matlab.ui.control.Label
        AltValue            matlab.ui.control.Label
        SpeedSlider         matlab.ui.control.Slider
        SpeedLabel          matlab.ui.control.Label
        SpeedValue          matlab.ui.control.Label
        StartBtn            matlab.ui.control.Button
        StopBtn             matlab.ui.control.Button
        ResetBtn            matlab.ui.control.Button
        GPSBtn              matlab.ui.control.Button
        StatusLamp          matlab.ui.control.Lamp
        StatusLabel         matlab.ui.control.Label
        LogArea             matlab.ui.control.TextArea
        LogLabel            matlab.ui.control.Label
        LeaderDropdown      matlab.ui.control.DropDown
        LeaderLabel         matlab.ui.control.Label
        WaypointBtn         matlab.ui.control.Button

        % Telemetry tab
        TelGrid             matlab.ui.container.GridLayout
        PosAxesX            matlab.ui.control.UIAxes
        PosAxesY            matlab.ui.control.UIAxes
        PosAxesZ            matlab.ui.control.UIAxes
        IMUAxesAccel        matlab.ui.control.UIAxes
        IMUAxesGyro         matlab.ui.control.UIAxes
        IMUAxesMag          matlab.ui.control.UIAxes

        % Settings tab
        SettingsGrid        matlab.ui.container.GridLayout
        UpdateRateSlider    matlab.ui.control.Slider
        UpdateRateValue     matlab.ui.control.Label
        TrailCheck          matlab.ui.control.CheckBox
        GridCheck           matlab.ui.control.CheckBox
        ConnLineCheck       matlab.ui.control.CheckBox
        CommRangeSlider     matlab.ui.control.Slider
        CommRangeValue      matlab.ui.control.Label
        WindSpeedSlider     matlab.ui.control.Slider
        WindSpeedValue      matlab.ui.control.Label
        WindDirSlider       matlab.ui.control.Slider
        WindDirValue        matlab.ui.control.Label
        ExportBtn           matlab.ui.control.Button

        % Modules tab
        ModGrid             matlab.ui.container.GridLayout
        ModListPanel        matlab.ui.container.Panel
        ModListGrid         matlab.ui.container.GridLayout
        ModDetailPanel      matlab.ui.container.Panel
        ModDetailGrid       matlab.ui.container.GridLayout
        ModRefreshBtn       matlab.ui.control.Button
    end

    %% ====================================================================
    %  PROPERTIES — SIMULATION STATE
    %  ====================================================================
    properties (Access = public)
        NumUAVs         (1,1) double = 4
        UAVPositions    (:,3) double
        UAVVelocities   (:,3) double
        UAVHeadings     (:,1) double
        UAVColors       (:,3) double
        UAVNames        cell
        UAVRoles        cell

        TelHistory      struct
        MaxHistory      (1,1) double = 500

        SwarmMode       char = 'Leader-Follower'
        MaxSwarmDist    (1,1) double = 50
        CruiseAlt       (1,1) double = 30
        CruiseSpeed     (1,1) double = 5
        LeaderIdx       (1,1) double = 1
        CommRange       (1,1) double = 200
        UpdateRate      (1,1) double = 10
        WindSpeed       (1,1) double = 0
        WindDir         (1,1) double = 0

        BaseLat         (1,1) double = 37.0
        BaseLon         (1,1) double = -76.0
        GPSAcquired     (1,1) logical = false
        MapOrigin       (1,2) double

        Waypoints       (:,2) double = []
        WaypointIdx     (1,1) double = 1

        SimTimer
        IsRunning       (1,1) logical = false
        SimTime         (1,1) double = 0
        dt              (1,1) double = 0.1
    end

    %% ====================================================================
    %  PROPERTIES — PERSISTENT GRAPHICS
    %  ====================================================================
    properties (Access = public)
        GFX_UAVPatches  cell
        GFX_UAVLabels   cell
        GFX_Trails      cell
        GFX_ConnLines   cell
        GFX_ConnLabels  cell
        GFX_RelayLine
        GFX_BaseMarker
        GFX_TelLines    cell
    end

    %% ====================================================================
    %  PROPERTIES — PLUGIN SYSTEM
    %  ====================================================================
    properties (Access = public)
        PluginDir       char = ''            % path to plugins/ folder
        PluginRegistry  struct               % discovered plugins (array of structs)
        PluginEnabled   struct               % id -> true/false
        PluginTabs      struct               % id -> tab handle
        PluginStates    struct               % id -> arbitrary state data
        PluginUIRows    struct               % id -> row handles in modules tab
    end

    %% ====================================================================
    %  CONSTRUCTOR
    %  ====================================================================
    methods (Access = public)
        function app = SwarmFly()
            app.initializeState();
            app.buildFigure();
            app.buildMapTab();
            app.buildTelemetryTab();
            app.buildSettingsTab();
            app.buildModulesTab();
            app.initMapGraphics();
            app.initTelemetryGraphics();

            timerPeriod = max(0.034, round(1/app.UpdateRate, 3));
            app.SimTimer = timer( ...
                'ExecutionMode', 'fixedRate', ...
                'Period', timerPeriod, ...
                'TimerFcn', @(~,~) app.simStep(), ...
                'ErrorFcn', @(~,e) app.logMsg(sprintf('Timer error: %s', e.Data.message)));

            app.updateMapGraphics();
            app.logMsg('SwarmFly v2.0 initialized.');

            % Discover and display plugins
            app.discoverPlugins();
            app.refreshModulesList();

            nPlugins = length(app.PluginRegistry);
            if nPlugins > 0
                app.logMsg(sprintf('Found %d plugins. Go to Modules tab to enable.', nPlugins));
            else
                app.logMsg(sprintf('No plugins found in: %s', app.PluginDir));
                app.logMsg('Create a "plugins" folder next to SwarmFly.m with swf_*.m files.');
            end

            app.logMsg('Attempting GPS acquisition...');
            app.acquireGPS();
        end
    end

    %% ====================================================================
    %  INITIALIZATION
    %  ====================================================================
    methods (Access = private)
        function initializeState(app)
            app.UAVColors = [
                0.18 0.55 0.94; 0.90 0.30 0.24;
                0.20 0.78 0.35; 0.95 0.65 0.10];
            app.UAVNames = {'UAV-1 (Alpha)', 'UAV-2 (Bravo)', ...
                            'UAV-3 (Charlie)', 'UAV-4 (Delta)'};
            app.UAVRoles = {'leader', 'follower', 'follower', 'follower'};
            app.UAVPositions = [0,15,30; -15,0,30; 15,0,30; 0,-15,30];
            app.UAVVelocities = zeros(4, 3);
            app.UAVHeadings = [pi/2; pi; 0; -pi/2];
            app.MapOrigin = [app.BaseLat, app.BaseLon];

            for k = 1:app.NumUAVs
                app.TelHistory(k).x=[]; app.TelHistory(k).y=[];
                app.TelHistory(k).z=[]; app.TelHistory(k).t=[];
                app.TelHistory(k).ax=[]; app.TelHistory(k).ay=[];
                app.TelHistory(k).az=[];
                app.TelHistory(k).gx=[]; app.TelHistory(k).gy=[];
                app.TelHistory(k).gz=[];
                app.TelHistory(k).mx=[]; app.TelHistory(k).my=[];
                app.TelHistory(k).mz=[];
            end

            app.PluginRegistry = struct('id',{},'name',{},'description',{}, ...
                'version',{},'hasTab',{},'hasStep',{},'hasToolbar',{}, ...
                'onLoad',{},'onUnload',{},'buildTab',{},'onStep',{}, ...
                'buildToolbar',{},'file',{});
            app.PluginEnabled = struct();
            app.PluginTabs    = struct();
            app.PluginStates  = struct();
            app.PluginUIRows  = struct();

            % Resolve plugin directory
            thisFile = mfilename('fullpath');
            if ~isempty(thisFile)
                app.PluginDir = fullfile(fileparts(thisFile), 'plugins');
            else
                app.PluginDir = fullfile(pwd, 'plugins');
            end
        end
    end

    %% ====================================================================
    %  GUI CONSTRUCTION — FIGURE + MAP TAB
    %  ====================================================================
    methods (Access = private)

        function buildFigure(app)
            % Detect screen size and fit window within it
            screenSz = get(0, 'ScreenSize');  % [1 1 width height]
            figW = min(1400, screenSz(3) - 80);
            figH = min(780, screenSz(4) - 120);
            figX = max(20, round((screenSz(3) - figW) / 2));
            figY = max(40, round((screenSz(4) - figH) / 2));

            app.Fig = uifigure( ...
                'Name', 'SwarmFly - Drone Swarm Test Platform', ...
                'Position', [figX figY figW figH], ...
                'Color', [0.12 0.12 0.14], ...
                'CloseRequestFcn', @(~,~) app.onClose(), ...
                'Resize', 'on');
            app.MainGrid = uigridlayout(app.Fig, [1,1], 'Padding', [0 0 0 0]);
            app.TabGroup = uitabgroup(app.MainGrid);
            app.MapTab       = uitab(app.TabGroup, 'Title', '  Map & Control  ');
            app.TelemetryTab = uitab(app.TabGroup, 'Title', '  Telemetry  ');
            app.SettingsTab  = uitab(app.TabGroup, 'Title', '  Settings  ');
            app.ModulesTab   = uitab(app.TabGroup, 'Title', '  Modules  ');
        end

        function buildMapTab(app)
            app.MapGrid = uigridlayout(app.MapTab, [1,2], ...
                'ColumnWidth', {'1x', 320}, 'Padding', [8 8 8 8], 'ColumnSpacing', 8);

            app.MapAxes = uiaxes(app.MapGrid);
            app.MapAxes.Layout.Row = 1; app.MapAxes.Layout.Column = 1;
            app.MapAxes.XLabel.String = 'East (m)';
            app.MapAxes.YLabel.String = 'North (m)';
            app.MapAxes.Title.String  = 'Swarm Area Map';
            app.MapAxes.XGrid = 'on'; app.MapAxes.YGrid = 'on';
            app.MapAxes.Color = [0.96 0.97 0.98]; app.MapAxes.Box = 'on';
            axis(app.MapAxes, 'equal');
            xlim(app.MapAxes, [-150 150]); ylim(app.MapAxes, [-150 150]);
            hold(app.MapAxes, 'on');

            app.ControlPanel = uipanel(app.MapGrid, ...
                'Title', 'Swarm Control', 'FontSize', 13, ...
                'FontWeight', 'bold', 'BackgroundColor', [0.95 0.95 0.97]);
            app.ControlPanel.Layout.Row = 1; app.ControlPanel.Layout.Column = 2;

            app.ControlGrid = uigridlayout(app.ControlPanel, [22,2], ...
                'RowHeight', repmat({26},1,22), 'ColumnWidth', {'1x','1x'}, ...
                'Padding', [10 10 10 6], 'RowSpacing', 4);

            r = 1;
            app.ModeLabel = uilabel(app.ControlGrid, 'Text', 'Swarm Mode:', 'FontWeight', 'bold');
            app.ModeLabel.Layout.Row = r; app.ModeLabel.Layout.Column = [1 2]; r=r+1;

            app.ModeDropdown = uidropdown(app.ControlGrid, ...
                'Items', {'Leader-Follower','Decentralized','Hetero-Relay','Hetero-Speed'}, ...
                'Value', 'Leader-Follower', ...
                'ValueChangedFcn', @(src,~) app.onModeChanged(src.Value));
            app.ModeDropdown.Layout.Row = r; app.ModeDropdown.Layout.Column = [1 2]; r=r+1;

            app.LeaderLabel = uilabel(app.ControlGrid, 'Text', 'Leader UAV:');
            app.LeaderLabel.Layout.Row = r; app.LeaderLabel.Layout.Column = 1;
            app.LeaderDropdown = uidropdown(app.ControlGrid, ...
                'Items', app.UAVNames, 'Value', app.UAVNames{1}, ...
                'ValueChangedFcn', @(src,~) app.onLeaderChanged(src.Value));
            app.LeaderDropdown.Layout.Row = r; app.LeaderDropdown.Layout.Column = 2; r=r+1;

            app.MaxDistLabel = uilabel(app.ControlGrid, 'Text', 'Max Swarm Dist (m):');
            app.MaxDistLabel.Layout.Row = r; app.MaxDistLabel.Layout.Column = 1;
            app.MaxDistValue = uilabel(app.ControlGrid, 'Text', '50');
            app.MaxDistValue.Layout.Row = r; app.MaxDistValue.Layout.Column = 2; r=r+1;
            app.MaxDistSlider = uislider(app.ControlGrid, 'Limits', [10 200], 'Value', 50, ...
                'ValueChangedFcn', @(src,~) app.onMaxDistChanged(src.Value));
            app.MaxDistSlider.Layout.Row = r; app.MaxDistSlider.Layout.Column = [1 2]; r=r+1;

            app.AltLabel = uilabel(app.ControlGrid, 'Text', 'Cruise Altitude (m):');
            app.AltLabel.Layout.Row = r; app.AltLabel.Layout.Column = 1;
            app.AltValue = uilabel(app.ControlGrid, 'Text', '30');
            app.AltValue.Layout.Row = r; app.AltValue.Layout.Column = 2; r=r+1;
            app.AltSlider = uislider(app.ControlGrid, 'Limits', [5 120], 'Value', 30, ...
                'ValueChangedFcn', @(src,~) app.onAltChanged(src.Value));
            app.AltSlider.Layout.Row = r; app.AltSlider.Layout.Column = [1 2]; r=r+1;

            app.SpeedLabel = uilabel(app.ControlGrid, 'Text', 'Cruise Speed (m/s):');
            app.SpeedLabel.Layout.Row = r; app.SpeedLabel.Layout.Column = 1;
            app.SpeedValue = uilabel(app.ControlGrid, 'Text', '5.0');
            app.SpeedValue.Layout.Row = r; app.SpeedValue.Layout.Column = 2; r=r+1;
            app.SpeedSlider = uislider(app.ControlGrid, 'Limits', [1 25], 'Value', 5, ...
                'ValueChangedFcn', @(src,~) app.onSpeedChanged(src.Value));
            app.SpeedSlider.Layout.Row = r; app.SpeedSlider.Layout.Column = [1 2]; r=r+1;

            app.StartBtn = uibutton(app.ControlGrid, 'push', 'Text', 'Start', ...
                'FontWeight', 'bold', 'BackgroundColor', [0.18 0.72 0.35], ...
                'FontColor', 'w', 'ButtonPushedFcn', @(~,~) app.onStart());
            app.StartBtn.Layout.Row = r; app.StartBtn.Layout.Column = 1;
            app.StopBtn = uibutton(app.ControlGrid, 'push', 'Text', 'Stop', ...
                'FontWeight', 'bold', 'BackgroundColor', [0.85 0.22 0.20], ...
                'FontColor', 'w', 'ButtonPushedFcn', @(~,~) app.onStop());
            app.StopBtn.Layout.Row = r; app.StopBtn.Layout.Column = 2; r=r+1;

            app.ResetBtn = uibutton(app.ControlGrid, 'push', 'Text', 'Reset Formation', ...
                'ButtonPushedFcn', @(~,~) app.onReset());
            app.ResetBtn.Layout.Row = r; app.ResetBtn.Layout.Column = 1;
            app.GPSBtn = uibutton(app.ControlGrid, 'push', 'Text', 'Re-acquire GPS', ...
                'ButtonPushedFcn', @(~,~) app.acquireGPS());
            app.GPSBtn.Layout.Row = r; app.GPSBtn.Layout.Column = 2; r=r+1;

            app.WaypointBtn = uibutton(app.ControlGrid, 'push', ...
                'Text', 'Add Waypoint (click map)', ...
                'ButtonPushedFcn', @(~,~) app.enableWaypointMode());
            app.WaypointBtn.Layout.Row = r; app.WaypointBtn.Layout.Column = [1 2]; r=r+1;

            app.StatusLabel = uilabel(app.ControlGrid, 'Text', 'Status: IDLE', 'FontWeight', 'bold');
            app.StatusLabel.Layout.Row = r; app.StatusLabel.Layout.Column = 1;
            app.StatusLamp = uilamp(app.ControlGrid);
            app.StatusLamp.Layout.Row = r; app.StatusLamp.Layout.Column = 2;
            app.StatusLamp.Color = [0.6 0.6 0.6]; r=r+1;

            app.LogLabel = uilabel(app.ControlGrid, 'Text', 'Event Log:', 'FontWeight', 'bold');
            app.LogLabel.Layout.Row = r; app.LogLabel.Layout.Column = [1 2]; r=r+1;

            app.LogArea = uitextarea(app.ControlGrid, 'Value', {''}, ...
                'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 10);
            app.LogArea.Layout.Row = [r 22]; app.LogArea.Layout.Column = [1 2];
        end

        function buildTelemetryTab(app)
            app.TelGrid = uigridlayout(app.TelemetryTab, [2,3], ...
                'Padding', [10 10 10 10], 'RowSpacing', 10, 'ColumnSpacing', 10);
            titles  = {'Position X (m)','Position Y (m)','Position Z / Alt (m)', ...
                       'Accel (m/s^2)','Gyro (deg/s)','Magnetometer (uT)'};
            ylabels = {'X (m)','Y (m)','Z (m)','m/s^2','deg/s','uT'};
            axH = cell(1,6);
            for k = 1:6
                r = ceil(k/3); c = mod(k-1,3)+1;
                ax = uiaxes(app.TelGrid);
                ax.Layout.Row = r; ax.Layout.Column = c;
                ax.Title.String = titles{k}; ax.XLabel.String = 'Time (s)';
                ax.YLabel.String = ylabels{k};
                ax.XGrid = 'on'; ax.YGrid = 'on';
                ax.Color = [0.98 0.98 1.0]; ax.Box = 'on'; hold(ax,'on');
                axH{k} = ax;
            end
            app.PosAxesX = axH{1}; app.PosAxesY = axH{2}; app.PosAxesZ = axH{3};
            app.IMUAxesAccel = axH{4}; app.IMUAxesGyro = axH{5}; app.IMUAxesMag = axH{6};
        end

        function buildSettingsTab(app)
            app.SettingsGrid = uigridlayout(app.SettingsTab, [12,3], ...
                'RowHeight', {48, 48, 48, 48, 30, 30, 30, 36, 30, 30, 30, 30}, ...
                'ColumnWidth', {200,'1x',80}, ...
                'Padding', [20 20 20 20], 'RowSpacing', 8);
            r = 1;
            lbl = uilabel(app.SettingsGrid, 'Text', 'Sim Update Rate (Hz):', 'FontWeight', 'bold');
            lbl.Layout.Row = r; lbl.Layout.Column = 1;
            app.UpdateRateSlider = uislider(app.SettingsGrid, 'Limits', [1 30], 'Value', 10, ...
                'ValueChangedFcn', @(src,~) app.onUpdateRateChanged(src.Value));
            app.UpdateRateSlider.Layout.Row = r; app.UpdateRateSlider.Layout.Column = 2;
            app.UpdateRateValue = uilabel(app.SettingsGrid, 'Text', '10');
            app.UpdateRateValue.Layout.Row = r; app.UpdateRateValue.Layout.Column = 3; r=r+1;

            lbl = uilabel(app.SettingsGrid, 'Text', 'Comm Range (m):', 'FontWeight', 'bold');
            lbl.Layout.Row = r; lbl.Layout.Column = 1;
            app.CommRangeSlider = uislider(app.SettingsGrid, 'Limits', [50 1000], 'Value', 200, ...
                'ValueChangedFcn', @(src,~) app.onCommRangeChanged(src.Value));
            app.CommRangeSlider.Layout.Row = r; app.CommRangeSlider.Layout.Column = 2;
            app.CommRangeValue = uilabel(app.SettingsGrid, 'Text', '200');
            app.CommRangeValue.Layout.Row = r; app.CommRangeValue.Layout.Column = 3; r=r+1;

            lbl = uilabel(app.SettingsGrid, 'Text', 'Wind Speed (m/s):', 'FontWeight', 'bold');
            lbl.Layout.Row = r; lbl.Layout.Column = 1;
            app.WindSpeedSlider = uislider(app.SettingsGrid, 'Limits', [0 20], 'Value', 0, ...
                'ValueChangedFcn', @(src,~) app.onWindSpeedChanged(src.Value));
            app.WindSpeedSlider.Layout.Row = r; app.WindSpeedSlider.Layout.Column = 2;
            app.WindSpeedValue = uilabel(app.SettingsGrid, 'Text', '0.0');
            app.WindSpeedValue.Layout.Row = r; app.WindSpeedValue.Layout.Column = 3; r=r+1;

            lbl = uilabel(app.SettingsGrid, 'Text', 'Wind Direction (deg):', 'FontWeight', 'bold');
            lbl.Layout.Row = r; lbl.Layout.Column = 1;
            app.WindDirSlider = uislider(app.SettingsGrid, 'Limits', [0 360], 'Value', 0, ...
                'ValueChangedFcn', @(src,~) app.onWindDirChanged(src.Value));
            app.WindDirSlider.Layout.Row = r; app.WindDirSlider.Layout.Column = 2;
            app.WindDirValue = uilabel(app.SettingsGrid, 'Text', '0');
            app.WindDirValue.Layout.Row = r; app.WindDirValue.Layout.Column = 3; r=r+1;

            app.TrailCheck = uicheckbox(app.SettingsGrid, 'Text', 'Show UAV Trails', 'Value', true, ...
                'ValueChangedFcn', @(src,~) app.onTrailToggle(src.Value));
            app.TrailCheck.Layout.Row = r; app.TrailCheck.Layout.Column = [1 2]; r=r+1;
            app.GridCheck = uicheckbox(app.SettingsGrid, 'Text', 'Show Grid', 'Value', true, ...
                'ValueChangedFcn', @(src,~) app.onGridToggle(src.Value));
            app.GridCheck.Layout.Row = r; app.GridCheck.Layout.Column = [1 2]; r=r+1;
            app.ConnLineCheck = uicheckbox(app.SettingsGrid, 'Text', 'Show Swarm Connections', 'Value', true);
            app.ConnLineCheck.Layout.Row = r; app.ConnLineCheck.Layout.Column = [1 2]; r=r+1;
            app.ExportBtn = uibutton(app.SettingsGrid, 'push', 'Text', 'Export Telemetry (.mat)', ...
                'ButtonPushedFcn', @(~,~) app.exportTelemetry());
            app.ExportBtn.Layout.Row = r; app.ExportBtn.Layout.Column = [1 2];
        end

        % -----------------------------------------------------------------
        %  MODULES TAB — Plugin Manager GUI
        % -----------------------------------------------------------------
        function buildModulesTab(app)
            app.ModGrid = uigridlayout(app.ModulesTab, [1,2], ...
                'ColumnWidth', {360, '1x'}, ...
                'Padding', [12 12 12 12], 'ColumnSpacing', 12);

            % --- Left: Plugin List ---
            app.ModListPanel = uipanel(app.ModGrid, 'Title', 'Available Modules', ...
                'FontSize', 13, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.95 0.95 0.97]);
            app.ModListPanel.Layout.Row = 1; app.ModListPanel.Layout.Column = 1;

            % Interior scrollable grid — 1 header row + 20 plugin rows + 1 button row
            app.ModListGrid = uigridlayout(app.ModListPanel, [22, 3], ...
                'RowHeight', [{30}, repmat({32}, 1, 20), {36}], ...
                'ColumnWidth', {50, '1x', 90}, ...
                'Padding', [8 8 8 8], 'RowSpacing', 3);

            % Header row
            hdr1 = uilabel(app.ModListGrid, 'Text', 'On', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            hdr1.Layout.Row = 1; hdr1.Layout.Column = 1;
            hdr2 = uilabel(app.ModListGrid, 'Text', 'Module Name', ...
                'FontWeight', 'bold');
            hdr2.Layout.Row = 1; hdr2.Layout.Column = 2;
            hdr3 = uilabel(app.ModListGrid, 'Text', 'Version', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            hdr3.Layout.Row = 1; hdr3.Layout.Column = 3;

            % Refresh button at bottom
            app.ModRefreshBtn = uibutton(app.ModListGrid, 'push', ...
                'Text', 'Rescan Plugins Folder', ...
                'ButtonPushedFcn', @(~,~) app.onRefreshPlugins());
            app.ModRefreshBtn.Layout.Row = 22; app.ModRefreshBtn.Layout.Column = [1 3];

            % --- Right: Detail / Info Panel ---
            app.ModDetailPanel = uipanel(app.ModGrid, 'Title', 'Module Details', ...
                'FontSize', 13, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.96 0.96 0.98]);
            app.ModDetailPanel.Layout.Row = 1; app.ModDetailPanel.Layout.Column = 2;

            app.ModDetailGrid = uigridlayout(app.ModDetailPanel, [6, 1], ...
                'RowHeight', {28, 50, 28, 28, '1x', 36}, ...
                'Padding', [12 12 12 12], 'RowSpacing', 6);

            dl1 = uilabel(app.ModDetailGrid, 'Text', 'Select a module to see details.', ...
                'FontAngle', 'italic', 'Tag', 'mod_detail_name');
            dl1.Layout.Row = 1; dl1.Layout.Column = 1;
            dl2 = uilabel(app.ModDetailGrid, 'Text', '', ...
                'WordWrap', 'on', 'Tag', 'mod_detail_desc');
            dl2.Layout.Row = 2; dl2.Layout.Column = 1;
            dl3 = uilabel(app.ModDetailGrid, 'Text', '', ...
                'Tag', 'mod_detail_caps');
            dl3.Layout.Row = 3; dl3.Layout.Column = 1;
            dl4 = uilabel(app.ModDetailGrid, 'Text', '', ...
                'Tag', 'mod_detail_file');
            dl4.Layout.Row = 4; dl4.Layout.Column = 1;
        end
    end

    %% ====================================================================
    %  PERSISTENT GRAPHICS
    %  ====================================================================
    methods (Access = private)
        function initMapGraphics(app)
            ax = app.MapAxes;
            app.GFX_BaseMarker = plot(ax, 0, 0, 'p', 'MarkerSize', 18, ...
                'MarkerFaceColor', [0.5 0.1 0.6], 'MarkerEdgeColor', 'k');
            app.GFX_ConnLines  = cell(6,1);
            app.GFX_ConnLabels = cell(6,1);
            idx = 0;
            for i = 1:4
                for j = (i+1):4
                    idx = idx+1;
                    app.GFX_ConnLines{idx} = plot(ax,[0 0],[0 0],'-', ...
                        'Color',[0.5 0.5 0.5 0.4],'LineWidth',1.2,'Visible','off');
                    app.GFX_ConnLabels{idx} = text(ax,0,0,'','FontSize',7, ...
                        'Color',[0.4 0.4 0.4],'HorizontalAlignment','center','Visible','off');
                end
            end
            app.GFX_RelayLine = plot(ax,[0 0],[0 0],'-.',...
                'Color',[0.6 0.1 0.8 0.6],'LineWidth',2,'Visible','off');
            app.GFX_Trails = cell(4,1);
            app.GFX_UAVPatches = cell(4,1);
            app.GFX_UAVLabels  = cell(4,1);
            for k = 1:4
                app.GFX_Trails{k} = plot(ax,NaN,NaN,'-',...
                    'Color',[app.UAVColors(k,:),0.35],'LineWidth',1);
                app.GFX_UAVPatches{k} = patch(ax,[0 0 0],[0 0 0],...
                    app.UAVColors(k,:),'EdgeColor','k','LineWidth',1.5,'FaceAlpha',0.9);
                app.GFX_UAVLabels{k} = text(ax,0,0,sprintf('U%d',k),...
                    'FontSize',8,'FontWeight','bold',...
                    'Color',app.UAVColors(k,:)*0.6,'HorizontalAlignment','center');
            end
        end

        function initTelemetryGraphics(app)
            axesList = {app.PosAxesX,app.PosAxesY,app.PosAxesZ,...
                        app.IMUAxesAccel,app.IMUAxesGyro,app.IMUAxesMag};
            nf = [1,1,1,3,3,3]; ls = {'-','--',':'};
            app.GFX_TelLines = cell(6,1);
            for p = 1:6
                lines = cell(4, nf(p));
                for k = 1:4
                    for fi = 1:nf(p)
                        lines{k,fi} = plot(axesList{p},NaN,NaN,ls{min(fi,3)},...
                            'Color',app.UAVColors(k,:),'LineWidth',1.1);
                    end
                end
                app.GFX_TelLines{p} = lines;
            end
        end
    end

    %% ====================================================================
    %  PLUGIN SYSTEM — DISCOVERY, LOAD, UNLOAD
    %  ====================================================================
    methods (Access = public)

        function discoverPlugins(app)
            % Scan plugins/ folder for swf_*.m files
            app.PluginRegistry = struct('id',{},'name',{},'description',{}, ...
                'version',{},'hasTab',{},'hasStep',{},'hasToolbar',{}, ...
                'onLoad',{},'onUnload',{},'buildTab',{},'onStep',{}, ...
                'buildToolbar',{},'file',{});

            if ~isfolder(app.PluginDir)
                app.logMsg(sprintf('Plugin folder not found: %s', app.PluginDir));
                app.logMsg('Create a "plugins/" folder next to SwarmFly.m');
                return;
            end

            files = dir(fullfile(app.PluginDir, 'swf_*.m'));
            for i = 1:length(files)
                try
                    [~, funcName] = fileparts(files(i).name);
                    % Add plugin dir to path temporarily
                    addpath(app.PluginDir);
                    fh = str2func(funcName);
                    pdef = fh();

                    % Validate required fields
                    if ~isfield(pdef,'id') || ~isfield(pdef,'name')
                        app.logMsg(sprintf('Skipping %s: missing id or name', funcName));
                        continue;
                    end

                    % Fill defaults for optional fields
                    defaults = struct('description','','version','1.0', ...
                        'hasTab',false,'hasStep',false,'hasToolbar',false, ...
                        'onLoad',[],'onUnload',[],'buildTab',[],...
                        'onStep',[],'buildToolbar',[]);
                    fnames = fieldnames(defaults);
                    for f = 1:length(fnames)
                        if ~isfield(pdef, fnames{f})
                            pdef.(fnames{f}) = defaults.(fnames{f});
                        end
                    end
                    pdef.file = files(i).name;

                    % Append to registry
                    app.PluginRegistry(end+1) = pdef;
                    app.PluginEnabled.(pdef.id) = false;
                    app.logMsg(sprintf('Discovered plugin: %s v%s', pdef.name, pdef.version));
                catch ME
                    app.logMsg(sprintf('Error loading %s: %s', files(i).name, ME.message));
                end
            end
        end

        function enablePlugin(app, pluginId)
            idx = app.findPluginIdx(pluginId);
            if isempty(idx), return; end
            if app.PluginEnabled.(pluginId), return; end  % already on

            pdef = app.PluginRegistry(idx);
            app.PluginEnabled.(pluginId) = true;

            % Initialize state storage
            app.PluginStates.(pluginId) = struct();

            % Call onLoad
            if ~isempty(pdef.onLoad)
                try
                    pdef.onLoad(app);
                catch ME
                    app.logMsg(sprintf('Plugin %s onLoad error: %s', pdef.name, ME.message));
                end
            end

            % Create tab if plugin declares one
            if pdef.hasTab && ~isempty(pdef.buildTab)
                newTab = uitab(app.TabGroup, 'Title', sprintf('  %s  ', pdef.name));
                app.PluginTabs.(pluginId) = newTab;
                try
                    pdef.buildTab(app, newTab);
                catch ME
                    app.logMsg(sprintf('Plugin %s buildTab error: %s', pdef.name, ME.message));
                end
            end

            app.logMsg(sprintf('Module enabled: %s', pdef.name));
        end

        function disablePlugin(app, pluginId)
            idx = app.findPluginIdx(pluginId);
            if isempty(idx), return; end
            if ~app.PluginEnabled.(pluginId), return; end

            pdef = app.PluginRegistry(idx);
            app.PluginEnabled.(pluginId) = false;

            % Call onUnload
            if ~isempty(pdef.onUnload)
                try
                    pdef.onUnload(app);
                catch ME
                    app.logMsg(sprintf('Plugin %s onUnload error: %s', pdef.name, ME.message));
                end
            end

            % Remove tab
            if isfield(app.PluginTabs, pluginId)
                try delete(app.PluginTabs.(pluginId)); catch; end
                app.PluginTabs = rmfield(app.PluginTabs, pluginId);
            end

            % Clear state
            if isfield(app.PluginStates, pluginId)
                app.PluginStates = rmfield(app.PluginStates, pluginId);
            end

            app.logMsg(sprintf('Module disabled: %s', pdef.name));
        end
    end

    methods (Access = private)

        function idx = findPluginIdx(app, pluginId)
            idx = [];
            for i = 1:length(app.PluginRegistry)
                if strcmp(app.PluginRegistry(i).id, pluginId)
                    idx = i; return;
                end
            end
        end

        function refreshModulesList(app)
            % Populate the Modules tab list with discovered plugins
            grid = app.ModListGrid;

            % Clear rows 2-21 (plugin slots)
            existing = findobj(grid, '-depth', 1);
            for h = 1:length(existing)
                tag = get(existing(h), 'Tag');
                if ~isempty(tag) && startsWith(tag, 'plugrow_')
                    delete(existing(h));
                end
            end

            for i = 1:min(length(app.PluginRegistry), 20)
                pdef = app.PluginRegistry(i);
                row = i + 1;  % offset for header

                % Enable checkbox
                cb = uicheckbox(grid, 'Text', '', ...
                    'Value', app.PluginEnabled.(pdef.id), ...
                    'Tag', sprintf('plugrow_cb_%s', pdef.id), ...
                    'ValueChangedFcn', @(src,~) app.onPluginToggle(pdef.id, src.Value));
                cb.Layout.Row = row; cb.Layout.Column = 1;

                % Name button (clickable for details)
                btn = uibutton(grid, 'push', 'Text', pdef.name, ...
                    'Tag', sprintf('plugrow_btn_%s', pdef.id), ...
                    'HorizontalAlignment', 'left', ...
                    'BackgroundColor', [0.96 0.96 0.98], ...
                    'ButtonPushedFcn', @(~,~) app.showPluginDetails(pdef.id));
                btn.Layout.Row = row; btn.Layout.Column = 2;

                % Version
                vlbl = uilabel(grid, 'Text', pdef.version, ...
                    'Tag', sprintf('plugrow_ver_%s', pdef.id), ...
                    'HorizontalAlignment', 'center');
                vlbl.Layout.Row = row; vlbl.Layout.Column = 3;
            end

            if isempty(app.PluginRegistry)
                noPlugLbl = uilabel(grid, 'Text', 'No plugins found. Place swf_*.m files in:', ...
                    'Tag', 'plugrow_empty', 'FontAngle', 'italic');
                noPlugLbl.Layout.Row = 2; noPlugLbl.Layout.Column = [1 3];
                pathLbl = uilabel(grid, 'Text', app.PluginDir, ...
                    'Tag', 'plugrow_path', 'FontName', 'Consolas', 'FontSize', 10);
                pathLbl.Layout.Row = 3; pathLbl.Layout.Column = [1 3];
            end
        end

        function onPluginToggle(app, pluginId, enabled)
            if enabled
                app.enablePlugin(pluginId);
            else
                app.disablePlugin(pluginId);
            end
        end

        function onRefreshPlugins(app)
            % Disable all active plugins first
            ids = fieldnames(app.PluginEnabled);
            for i = 1:length(ids)
                if app.PluginEnabled.(ids{i})
                    app.disablePlugin(ids{i});
                end
            end
            app.discoverPlugins();
            app.refreshModulesList();
        end

        function showPluginDetails(app, pluginId)
            idx = app.findPluginIdx(pluginId);
            if isempty(idx), return; end
            pdef = app.PluginRegistry(idx);

            % Update detail panel labels
            detGrid = app.ModDetailGrid;
            nameLbl = findobj(detGrid, 'Tag', 'mod_detail_name');
            descLbl = findobj(detGrid, 'Tag', 'mod_detail_desc');
            capsLbl = findobj(detGrid, 'Tag', 'mod_detail_caps');
            fileLbl = findobj(detGrid, 'Tag', 'mod_detail_file');

            if ~isempty(nameLbl)
                nameLbl.Text = sprintf('%s  (v%s)', pdef.name, pdef.version);
                nameLbl.FontWeight = 'bold';
                nameLbl.FontAngle = 'normal';
            end
            if ~isempty(descLbl), descLbl.Text = pdef.description; end
            if ~isempty(capsLbl)
                caps = {};
                if pdef.hasTab,     caps{end+1} = 'Tab'; end
                if pdef.hasStep,    caps{end+1} = 'Per-Tick'; end
                if pdef.hasToolbar, caps{end+1} = 'Toolbar'; end
                capsLbl.Text = sprintf('Capabilities: %s', strjoin(caps, ', '));
            end
            if ~isempty(fileLbl)
                fileLbl.Text = sprintf('File: %s', pdef.file);
            end
        end
    end

    %% ====================================================================
    %  CALLBACKS (public — plugins call onStart, onStop, onReset, onModeChanged)
    %  ====================================================================
    methods (Access = public)
        function onModeChanged(app, mode)
            app.SwarmMode = char(mode);
            switch app.SwarmMode
                case 'Leader-Follower'
                    app.UAVRoles = {'leader','follower','follower','follower'};
                    app.LeaderDropdown.Enable = 'on';
                case 'Decentralized'
                    app.UAVRoles = {'autonomous','autonomous','autonomous','autonomous'};
                    app.LeaderDropdown.Enable = 'off';
                case 'Hetero-Relay'
                    app.UAVRoles = {'normal','normal','normal','relay'};
                    app.LeaderDropdown.Enable = 'off';
                case 'Hetero-Speed'
                    app.UAVRoles = {'fast','slow','slow','slow'};
                    app.LeaderDropdown.Enable = 'off';
            end
            app.logMsg(sprintf('Mode: %s', app.SwarmMode));
        end
        function onLeaderChanged(app, name)
            idx = find(strcmp(app.UAVNames, name), 1);
            if ~isempty(idx)
                app.LeaderIdx = idx;
                roles = repmat({'follower'},1,4); roles{idx} = 'leader';
                app.UAVRoles = roles;
                app.logMsg(sprintf('Leader: %s', char(name)));
            end
        end
        function onMaxDistChanged(app, v)
            app.MaxSwarmDist = round(v); app.MaxDistValue.Text = num2str(app.MaxSwarmDist); end
        function onAltChanged(app, v)
            app.CruiseAlt = round(v); app.AltValue.Text = num2str(app.CruiseAlt); end
        function onSpeedChanged(app, v)
            app.CruiseSpeed = round(v,1); app.SpeedValue.Text = num2str(app.CruiseSpeed); end
        function onUpdateRateChanged(app, v)
            app.UpdateRate = max(1,round(v)); app.UpdateRateValue.Text = num2str(app.UpdateRate);
            if app.IsRunning, app.safeStopTimer();
                app.SimTimer.Period = max(0.034, round(1/app.UpdateRate,3));
                start(app.SimTimer); end
        end
        function onCommRangeChanged(app, v)
            app.CommRange = round(v); app.CommRangeValue.Text = num2str(app.CommRange); end
        function onWindSpeedChanged(app, v)
            app.WindSpeed = round(v,1); app.WindSpeedValue.Text = sprintf('%.1f', app.WindSpeed); end
        function onWindDirChanged(app, v)
            app.WindDir = round(v); app.WindDirValue.Text = num2str(app.WindDir); end
        function onTrailToggle(app, v)
            vis = app.boolVis(v);
            for k=1:4, app.GFX_Trails{k}.Visible = vis; end
        end
        function onGridToggle(app, v)
            vis = app.boolVis(v);
            app.MapAxes.XGrid = vis; app.MapAxes.YGrid = vis;
        end

        function onStart(app)
            if app.IsRunning, return; end
            app.IsRunning = true;
            np = max(0.034, round(1/app.UpdateRate,3));
            if ~app.isTimerValid()
                app.SimTimer = timer('ExecutionMode','fixedRate','Period',np,...
                    'TimerFcn',@(~,~) app.simStep(),...
                    'ErrorFcn',@(~,e) app.logMsg(sprintf('Timer: %s',e.Data.message)));
            elseif strcmp(app.SimTimer.Running,'off')
                app.SimTimer.Period = np;
            end
            start(app.SimTimer);
            app.StatusLamp.Color = [0.1 0.85 0.2];
            app.StatusLabel.Text = 'Status: RUNNING';
            app.logMsg('Simulation started.');
        end

        function onStop(app)
            if ~app.IsRunning, return; end
            app.safeStopTimer(); app.IsRunning = false;
            app.StatusLamp.Color = [0.9 0.7 0.1];
            app.StatusLabel.Text = 'Status: STOPPED';
            app.logMsg('Simulation stopped.');
        end

        function onReset(app)
            app.onStop();
            app.UAVPositions = [0,15,app.CruiseAlt; -15,0,app.CruiseAlt;
                                15,0,app.CruiseAlt; 0,-15,app.CruiseAlt];
            app.UAVVelocities = zeros(4,3);
            app.UAVHeadings = [pi/2;pi;0;-pi/2];
            app.SimTime = 0; app.WaypointIdx = 1;
            for k=1:4
                app.TelHistory(k).x=[]; app.TelHistory(k).y=[];
                app.TelHistory(k).z=[]; app.TelHistory(k).t=[];
                app.TelHistory(k).ax=[]; app.TelHistory(k).ay=[];
                app.TelHistory(k).az=[];
                app.TelHistory(k).gx=[]; app.TelHistory(k).gy=[];
                app.TelHistory(k).gz=[];
                app.TelHistory(k).mx=[]; app.TelHistory(k).my=[];
                app.TelHistory(k).mz=[];
            end
            for p=1:6
                lines = app.GFX_TelLines{p};
                for k=1:size(lines,1), for fi=1:size(lines,2)
                    lines{k,fi}.XData=NaN; lines{k,fi}.YData=NaN;
                end, end
            end
            app.updateMapGraphics();
            app.StatusLamp.Color = [0.6 0.6 0.6];
            app.StatusLabel.Text = 'Status: IDLE';
            app.logMsg('Formation reset.');
        end

        function enableWaypointMode(app)
            app.logMsg('Click on the map to add a waypoint...');
            app.MapAxes.ButtonDownFcn = @(~,evt) app.addWaypoint(evt);
        end
        function addWaypoint(app, evt)
            pt = evt.IntersectionPoint(1:2);
            app.Waypoints(end+1,:) = pt;
            plot(app.MapAxes, pt(1), pt(2), 'Marker', 'd', 'MarkerSize', 12, ...
                'LineStyle', 'none', 'MarkerFaceColor', [0.8 0.1 0.5], ...
                'MarkerEdgeColor', [0.5 0 0.3], 'LineWidth', 1.5);
            text(app.MapAxes, pt(1)+3, pt(2)+3, sprintf('WP%d', size(app.Waypoints,1)), ...
                'FontSize', 9, 'Color', [0.5 0 0.3]);
            app.logMsg(sprintf('Waypoint %d at (%.1f, %.1f)', size(app.Waypoints,1), pt(1), pt(2)));
            app.MapAxes.ButtonDownFcn = '';
        end
        function onClose(app)
            % Unload all plugins
            ids = fieldnames(app.PluginEnabled);
            for i=1:length(ids)
                if app.PluginEnabled.(ids{i})
                    app.disablePlugin(ids{i});
                end
            end
            if app.isTimerValid()
                try stop(app.SimTimer); catch; end
                try delete(app.SimTimer); catch; end
            end
            delete(app.Fig);
        end
    end

    %% ====================================================================
    %  SIMULATION ENGINE
    %  ====================================================================
    methods (Access = private)
        function simStep(app)
            app.dt = 1/app.UpdateRate;
            app.SimTime = app.SimTime + app.dt;
            windVec = app.WindSpeed * [cosd(app.WindDir), sind(app.WindDir), 0];

            switch app.SwarmMode
                case 'Leader-Follower', app.stepLeaderFollower(windVec);
                case 'Decentralized',   app.stepDecentralized(windVec);
                case 'Hetero-Relay',    app.stepHeteroRelay(windVec);
                case 'Hetero-Speed',    app.stepHeteroSpeed(windVec);
            end

            for k=1:4
                app.UAVPositions(k,3) = app.UAVPositions(k,3) + ...
                    0.3*(app.CruiseAlt - app.UAVPositions(k,3))*app.dt;
            end

            app.recordTelemetry();

            % --- Run all enabled plugin step functions ---
            for i = 1:length(app.PluginRegistry)
                pid = app.PluginRegistry(i).id;
                if app.PluginEnabled.(pid) && app.PluginRegistry(i).hasStep ...
                        && ~isempty(app.PluginRegistry(i).onStep)
                    try
                        app.PluginRegistry(i).onStep(app);
                    catch ME
                        app.logMsg(sprintf('Plugin %s step error: %s', pid, ME.message));
                    end
                end
            end

            app.updateMapGraphics();
            if app.TabGroup.SelectedTab == app.TelemetryTab
                app.updateTelemetryPlots();
            end
            drawnow limitrate;
        end

        function stepLeaderFollower(app, wv)
            li = app.LeaderIdx;
            if ~isempty(app.Waypoints) && app.WaypointIdx <= size(app.Waypoints,1)
                tgt = app.Waypoints(app.WaypointIdx,:);
                d = tgt - app.UAVPositions(li,1:2); dn = norm(d);
                if dn < 3, app.WaypointIdx = min(app.WaypointIdx+1,size(app.Waypoints,1));
                    app.logMsg(sprintf('WP%d reached.',app.WaypointIdx-1)); end
                vel = min(app.CruiseSpeed,dn)*[cos(atan2(d(2),d(1))),sin(atan2(d(2),d(1))),0];
            else
                t=app.SimTime; r=40;
                vel = app.CruiseSpeed*[-sin(t*0.3)*r*0.3,cos(t*0.3)*r*0.3,0];
                vel = vel/max(norm(vel),1e-6)*app.CruiseSpeed;
            end
            app.UAVPositions(li,:) = app.UAVPositions(li,:)+(vel+wv)*app.dt;
            app.UAVHeadings(li) = atan2(vel(2),vel(1));
            off = app.formationOffsets(li);
            for k=1:4
                if k==li, continue; end
                desired = app.UAVPositions(li,:)+off(k,:);
                df = desired-app.UAVPositions(k,:); dn=norm(df);
                if dn>app.MaxSwarmDist, df=df/dn*app.MaxSwarmDist; end
                fv = 2.0*df; sp=norm(fv(1:2));
                if sp>app.CruiseSpeed*1.5, fv=fv/sp*app.CruiseSpeed*1.5; end
                app.UAVPositions(k,:) = app.UAVPositions(k,:)+(fv+wv)*app.dt;
                if sp>0.1, app.UAVHeadings(k) = atan2(fv(2),fv(1)); end
            end
        end

        function stepDecentralized(app, wv)
            for k=1:4
                t=app.SimTime+k*1.7;
                wander=app.CruiseSpeed*[cos(t*0.2+k),sin(t*0.15+k*0.7),0];
                rep=[0 0 0];
                for j=1:4, if j==k,continue;end
                    d=app.UAVPositions(k,:)-app.UAVPositions(j,:); dn=norm(d);
                    if dn<10, rep=rep+5*d/max(dn^2,1); end
                end
                coh=0.3*(mean(app.UAVPositions,1)-app.UAVPositions(k,:));
                vel=wander+rep+coh; sp=norm(vel);
                if sp>app.CruiseSpeed, vel=vel/sp*app.CruiseSpeed; end
                app.UAVPositions(k,:)=app.UAVPositions(k,:)+(vel+wv)*app.dt;
                app.UAVHeadings(k)=atan2(vel(2),vel(1));
            end
        end

        function stepHeteroRelay(app, wv)
            ri=4; ai=setdiff(1:4,ri);
            ac=mean(app.UAVPositions(ai,:),1); rt=0.4*ac;
            d=rt-app.UAVPositions(ri,:); rv=1.5*d;
            if norm(rv)>3, rv=rv/norm(rv)*3; end
            app.UAVPositions(ri,:)=app.UAVPositions(ri,:)+(rv+wv*0.5)*app.dt;
            if norm(rv(1:2))>0.1, app.UAVHeadings(ri)=atan2(rv(2),rv(1)); end
            li=1;
            if ~isempty(app.Waypoints) && app.WaypointIdx<=size(app.Waypoints,1)
                tgt=app.Waypoints(app.WaypointIdx,:);
                d2=tgt-app.UAVPositions(li,1:2); dn=norm(d2);
                if dn<3, app.WaypointIdx=min(app.WaypointIdx+1,size(app.Waypoints,1)); end
                vel=min(app.CruiseSpeed,dn)*[cos(atan2(d2(2),d2(1))),sin(atan2(d2(2),d2(1))),0];
            else
                t=app.SimTime; vel=app.CruiseSpeed*[cos(t*0.25),sin(t*0.2),0];
            end
            app.UAVPositions(li,:)=app.UAVPositions(li,:)+(vel+wv)*app.dt;
            app.UAVHeadings(li)=atan2(vel(2),vel(1));
            off=app.formationOffsets(li);
            for k=ai, if k==li,continue;end
                desired=app.UAVPositions(li,:)+off(k,:);
                df=desired-app.UAVPositions(k,:); fv=2.0*df; sp=norm(fv);
                if sp>app.CruiseSpeed*1.3, fv=fv/sp*app.CruiseSpeed*1.3; end
                app.UAVPositions(k,:)=app.UAVPositions(k,:)+(fv+wv)*app.dt;
                if norm(fv(1:2))>0.1, app.UAVHeadings(k)=atan2(fv(2),fv(1)); end
            end
        end

        function stepHeteroSpeed(app, wv)
            fi=1; si=[2 3 4]; fs=app.CruiseSpeed*2; ss=app.CruiseSpeed*0.6;
            if ~isempty(app.Waypoints) && app.WaypointIdx<=size(app.Waypoints,1)
                tgt=app.Waypoints(app.WaypointIdx,:);
                d=tgt-app.UAVPositions(fi,1:2); dn=norm(d);
                if dn<5, app.WaypointIdx=min(app.WaypointIdx+1,size(app.Waypoints,1)); end
                vel=min(fs,dn)*[cos(atan2(d(2),d(1))),sin(atan2(d(2),d(1))),0];
            else
                t=app.SimTime; vel=fs*[cos(t*0.35),sin(t*0.25),0];
            end
            app.UAVPositions(fi,:)=app.UAVPositions(fi,:)+(vel+wv)*app.dt;
            app.UAVHeadings(fi)=atan2(vel(2),vel(1));
            for idx=1:3
                k=si(idx); ang=pi+(idx-2)*0.6;
                off=25*[cos(app.UAVHeadings(fi)+ang),sin(app.UAVHeadings(fi)+ang),0];
                desired=app.UAVPositions(fi,:)+off;
                df=desired-app.UAVPositions(k,:); fv=1.5*df; sp=norm(fv);
                if sp>ss, fv=fv/sp*ss; end
                app.UAVPositions(k,:)=app.UAVPositions(k,:)+(fv+wv)*app.dt;
                app.UAVHeadings(k)=atan2(fv(2),fv(1));
            end
        end

        function off = formationOffsets(app, li)
            base=[0,0,0;-20,-12,0;20,-12,0;0,-24,0];
            off=(base-base(li,:))*(app.MaxSwarmDist/50);
        end
    end

    %% ====================================================================
    %  TELEMETRY
    %  ====================================================================
    methods (Access = private)
        function recordTelemetry(app)
            for k=1:4
                app.TelHistory(k).t(end+1)=app.SimTime;
                app.TelHistory(k).x(end+1)=app.UAVPositions(k,1);
                app.TelHistory(k).y(end+1)=app.UAVPositions(k,2);
                app.TelHistory(k).z(end+1)=app.UAVPositions(k,3);
                n=length(app.TelHistory(k).x); nv=@(s) s*randn();
                if n>=2
                    dt_=app.dt;
                    ax=(app.TelHistory(k).x(n)-app.TelHistory(k).x(n-1))/dt_+nv(0.3);
                    ay=(app.TelHistory(k).y(n)-app.TelHistory(k).y(n-1))/dt_+nv(0.3);
                    az=9.81+nv(0.1);
                else, ax=nv(0.1); ay=nv(0.1); az=9.81;
                end
                app.TelHistory(k).ax(end+1)=ax;
                app.TelHistory(k).ay(end+1)=ay;
                app.TelHistory(k).az(end+1)=az;
                app.TelHistory(k).gx(end+1)=nv(2);
                app.TelHistory(k).gy(end+1)=nv(2);
                if n>=2
                    dx=app.TelHistory(k).x(n)-app.TelHistory(k).x(n-1);
                    dy=app.TelHistory(k).y(n)-app.TelHistory(k).y(n-1);
                    app.TelHistory(k).gz(end+1)=rad2deg(atan2(dy,dx))*0.1+nv(1);
                else, app.TelHistory(k).gz(end+1)=0;
                end
                app.TelHistory(k).mx(end+1)=25+nv(1);
                app.TelHistory(k).my(end+1)=5+nv(1);
                app.TelHistory(k).mz(end+1)=-40+nv(1);
                if n>app.MaxHistory
                    flds={'t','x','y','z','ax','ay','az','gx','gy','gz','mx','my','mz'};
                    for f=1:length(flds)
                        app.TelHistory(k).(flds{f})=app.TelHistory(k).(flds{f})(end-app.MaxHistory+1:end);
                    end
                end
            end
        end

        function updateTelemetryPlots(app)
            fs={{'x'},{'y'},{'z'},{'ax','ay','az'},{'gx','gy','gz'},{'mx','my','mz'}};
            for p=1:6
                lines=app.GFX_TelLines{p}; flds=fs{p};
                for k=1:4
                    t=app.TelHistory(k).t; if isempty(t),continue;end
                    for fi=1:length(flds)
                        lines{k,fi}.XData=t;
                        lines{k,fi}.YData=app.TelHistory(k).(flds{fi});
                    end
                end
            end
        end
    end

    %% ====================================================================
    %  GRAPHICS UPDATE
    %  ====================================================================
    methods (Access = private)
        function updateMapGraphics(app)
            ax=app.MapAxes; showC=app.ConnLineCheck.Value;
            pi_=0;
            for i=1:4, for j=(i+1):4, pi_=pi_+1;
                if ~showC
                    app.GFX_ConnLines{pi_}.Visible='off';
                    app.GFX_ConnLabels{pi_}.Visible='off'; continue;
                end
                d=norm(app.UAVPositions(i,1:2)-app.UAVPositions(j,1:2));
                if d<app.CommRange
                    app.GFX_ConnLines{pi_}.XData=[app.UAVPositions(i,1),app.UAVPositions(j,1)];
                    app.GFX_ConnLines{pi_}.YData=[app.UAVPositions(i,2),app.UAVPositions(j,2)];
                    if d>app.MaxSwarmDist
                        app.GFX_ConnLines{pi_}.Color=[0.9 0.2 0.1 0.7];
                    else
                        app.GFX_ConnLines{pi_}.Color=[0.5 0.5 0.5 max(0.15,1-d/app.CommRange)];
                    end
                    app.GFX_ConnLines{pi_}.Visible='on';
                    mx=(app.UAVPositions(i,1)+app.UAVPositions(j,1))/2;
                    my=(app.UAVPositions(i,2)+app.UAVPositions(j,2))/2;
                    app.GFX_ConnLabels{pi_}.Position=[mx,my,0];
                    app.GFX_ConnLabels{pi_}.String=sprintf('%.0fm',d);
                    app.GFX_ConnLabels{pi_}.Visible='on';
                else
                    app.GFX_ConnLines{pi_}.Visible='off';
                    app.GFX_ConnLabels{pi_}.Visible='off';
                end
            end, end

            if strcmp(app.SwarmMode,'Hetero-Relay')
                app.GFX_RelayLine.XData=[0,app.UAVPositions(4,1)];
                app.GFX_RelayLine.YData=[0,app.UAVPositions(4,2)];
                app.GFX_RelayLine.Visible='on';
            else, app.GFX_RelayLine.Visible='off';
            end

            st=app.TrailCheck.Value;
            for k=1:4
                if st && length(app.TelHistory(k).x)>1
                    app.GFX_Trails{k}.XData=app.TelHistory(k).x;
                    app.GFX_Trails{k}.YData=app.TelHistory(k).y;
                    app.GFX_Trails{k}.Visible='on';
                else, app.GFX_Trails{k}.Visible='off';
                end
            end

            for k=1:4
                pos=app.UAVPositions(k,1:2); hdg=app.UAVHeadings(k); sz=5;
                if strcmp(app.UAVRoles{k},'relay')
                    vx=sz*[cos(hdg),cos(hdg+pi/2),cos(hdg+pi),cos(hdg-pi/2)]+pos(1);
                    vy=sz*[sin(hdg),sin(hdg+pi/2),sin(hdg+pi),sin(hdg-pi/2)]+pos(2);
                else
                    a=[hdg,hdg+2.5,hdg-2.5];
                    vx=sz*cos(a)+pos(1); vy=sz*sin(a)+pos(2);
                end
                app.GFX_UAVPatches{k}.XData=vx; app.GFX_UAVPatches{k}.YData=vy;
                app.GFX_UAVLabels{k}.String=sprintf('U%d [%s]',k,app.UAVRoles{k});
                app.GFX_UAVLabels{k}.Position=[pos(1),pos(2)+7,0];
            end

            allX=app.UAVPositions(:,1); allY=app.UAVPositions(:,2);
            mg=max(50,app.MaxSwarmDist*1.5);
            xlim(ax,[min(allX)-mg,max(allX)+mg]);
            ylim(ax,[min(allY)-mg,max(allY)+mg]);

            if app.GPSAcquired
                ax.Title.String=sprintf('Swarm Map - %.4f N, %.4f E | T=%.1fs',...
                    app.MapOrigin(1),app.MapOrigin(2),app.SimTime);
            else
                ax.Title.String=sprintf('Swarm Map - Local Frame | T=%.1fs',app.SimTime);
            end
        end
    end

    %% ====================================================================
    %  GPS
    %  ====================================================================
    methods (Access = private)
        function acquireGPS(app)
            app.logMsg('Acquiring GPS via IP geolocation...');
            try
                data=webread('http://ip-api.com/json/?fields=lat,lon,city,regionName,status');
                if isfield(data,'status') && strcmp(data.status,'success')
                    app.BaseLat=data.lat; app.BaseLon=data.lon;
                    app.MapOrigin=[data.lat,data.lon]; app.GPSAcquired=true;
                    app.StatusLamp.Color=[0.1 0.8 0.9];
                    loc='';
                    if isfield(data,'city'), loc=char(data.city); end
                    if isfield(data,'regionName'), loc=[loc,', ',char(data.regionName)]; end
                    app.logMsg(sprintf('GPS: %.5f, %.5f (%s)',data.lat,data.lon,loc));
                else
                    app.logMsg('GPS: non-success status.'); app.GPSAcquired=false;
                end
            catch ME
                app.logMsg(sprintf('GPS failed: %s',ME.message)); app.GPSAcquired=false;
            end
        end
    end

    %% ====================================================================
    %  UTILITIES (public — plugins call logMsg)
    %  ====================================================================
    methods (Access = public)
        function logMsg(app, msg)
            ts=datestr(now,'HH:MM:SS'); %#ok<TNOW1,DATST>
            entry=sprintf('[%s] %s',ts,char(msg));
            cur=app.LogArea.Value;
            if length(cur)==1 && isempty(strtrim(cur{1}))
                app.LogArea.Value={entry};
            else, app.LogArea.Value=[cur;{entry}];
            end
            try scroll(app.LogArea,'bottom'); catch; end
        end
        function exportTelemetry(app)
            TD=app.TelHistory; P=app.UAVPositions; M=app.SwarmMode; %#ok<NASGU>
            Pr=struct('MaxSwarmDist',app.MaxSwarmDist,'CruiseAlt',app.CruiseAlt,...
                'CruiseSpeed',app.CruiseSpeed,'CommRange',app.CommRange,...
                'WindSpeed',app.WindSpeed,'WindDir',app.WindDir,...
                'MapOrigin',app.MapOrigin); %#ok<NASGU>
            [f,p]=uiputfile('SwarmFly_Telemetry.mat','Export');
            if f~=0, save(fullfile(p,f),'TD','P','M','Pr');
                app.logMsg(sprintf('Exported: %s',f)); end
        end
    end
    methods (Access = private)
        function v = isTimerValid(app)
            v = ~isempty(app.SimTimer) && isa(app.SimTimer,'timer') && isvalid(app.SimTimer);
        end
        function safeStopTimer(app)
            if app.isTimerValid(), try stop(app.SimTimer); catch; end, end
        end
    end

    methods (Static, Access = private)
        function s = boolVis(v), if v, s='on'; else, s='off'; end, end
    end

    %% ====================================================================
    %  PUBLIC API (for plugins and scripts)
    %  ====================================================================
    methods (Access = public)
        function setUAVPosition(app,idx,pos), app.UAVPositions(idx,:)=pos; end
        function pos = getUAVPosition(app,idx), pos=app.UAVPositions(idx,:); end
        function tel = getTelemetry(app,idx), tel=app.TelHistory(idx); end
        function setWaypoints(app, wps)
            app.Waypoints=wps; app.WaypointIdx=1;
            for w=1:size(wps,1)
                plot(app.MapAxes, wps(w,1), wps(w,2), 'Marker', 'd', ...
                    'MarkerSize', 12, 'LineStyle', 'none', ...
                    'MarkerFaceColor', [0.8 0.1 0.5], ...
                    'MarkerEdgeColor', [0.5 0 0.3], 'LineWidth', 1.5);
                text(app.MapAxes, wps(w,1)+3, wps(w,2)+3, sprintf('WP%d',w), ...
                    'FontSize', 9, 'Color', [0.5 0 0.3]);
            end
            app.logMsg(sprintf('Loaded %d waypoints.', size(wps,1)));
        end

        function setState(app, pluginId, key, value)
            % Store arbitrary data for a plugin: app.setState('battery', 'levels', [100 95 90 88])
            if ~isfield(app.PluginStates, pluginId)
                app.PluginStates.(pluginId) = struct();
            end
            app.PluginStates.(pluginId).(key) = value;
        end

        function val = getState(app, pluginId, key)
            % Retrieve plugin state: lvl = app.getState('battery', 'levels')
            val = [];
            if isfield(app.PluginStates, pluginId) && isfield(app.PluginStates.(pluginId), key)
                val = app.PluginStates.(pluginId).(key);
            end
        end

        function addCustomTab(app, tabTitle, buildFcn)
            newTab = uitab(app.TabGroup, 'Title', tabTitle);
            buildFcn(newTab);
            app.logMsg(sprintf('Custom tab added: %s', tabTitle));
        end

        function enableAllPlugins(app)
            % Enable every discovered plugin at once.
            %   app.enableAllPlugins()
            for i = 1:length(app.PluginRegistry)
                pid = app.PluginRegistry(i).id;
                if ~app.PluginEnabled.(pid)
                    app.enablePlugin(pid);
                end
            end
            app.refreshModulesList();
        end
    end
end
