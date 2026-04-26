%% SwarmFly v2.0 — Launcher
%
%  File structure required:
%    SwarmFly.m            (this folder)
%    run_SwarmFly.m        (this file)
%    plugins/              (subfolder)
%      swf_fault_injection.m
%      swf_metrics.m
%      swf_battery.m
%      swf_collision.m
%      swf_scenario_runner.m
%      swf_plugin_template.m
%
%  Requirements: MATLAB R2020b+

clc; clear;
fprintf('=== SwarmFly v2.0 ===\n\n');

% Launch the app
app = SwarmFly();

%% --- Enable all plugins automatically ---
%  Uncomment ONE of the following options:

% OPTION A: Enable ALL discovered plugins at once
app.enableAllPlugins();

% OPTION B: Enable specific plugins only (comment out Option A first)
% app.enablePlugin('fault_injection');
% app.enablePlugin('metrics');
% app.enablePlugin('battery');
% app.enablePlugin('collision');
% app.enablePlugin('scenarios');

%% --- Optional: Load demo waypoints ---
% app.setWaypoints([30 40; 70 20; 90 -30; 40 -60; -20 -40; 0 50]);

fprintf('\nApp launched. Handle stored in "app".\n');
fprintf('Plugin tabs should now be visible.\n');
fprintf('Press Start to begin simulation, then use plugin tabs.\n\n');
fprintf('Quick commands:\n');
fprintf('  app.onStart()            - Start simulation\n');
fprintf('  app.onStop()             - Stop simulation\n');
fprintf('  app.onReset()            - Reset formation\n');
fprintf('  app.enableAllPlugins()   - Enable all plugins\n');
fprintf('  app.enablePlugin(id)     - Enable one plugin by id\n');
fprintf('  app.disablePlugin(id)    - Disable one plugin\n');
