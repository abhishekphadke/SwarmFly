# SwarmFly — Drone Swarm Simulation & Test Platform

SwarmFly is a modular MATLAB GUI application for simulating, visualizing, and testing cooperative UAV swarm behavior. It provides a real-time 2D/3D operational map, four swarm coordination modes, simulated IMU telemetry, GPS geolocation, and a plugin architecture for extending the platform with fault injection, performance metrics, energy modeling, collision avoidance, geofencing, automated test scenarios, and 3D visualization — all without modifying the core application code.


## Requirements

- MATLAB R2020b or later (requires uifigure, App Designer components, uigridlayout)
- Internet connection for IP-based GPS geolocation (optional; app works without it)
- No additional toolboxes required


## Quick Start

```matlab
cd SwarmFly/        % navigate to the project folder
run_SwarmFly        % launches app and enables all plugins
```

After launch:
1. The Map & Control tab shows 4 colored UAV triangles in diamond formation.
2. Click **Start** to begin simulation.
3. Switch between tabs to access plugin features (Fault Injection, Metrics, 3D View, etc.).
4. Click **Add Waypoint** then click the map to guide the leader.


## Project Structure

```
SwarmFly/
├── SwarmFly.m                        Core application (1,324 lines)
├── run_SwarmFly.m                    Launcher script with auto-enable
├── README.md                         This file
├── plugins/                          Plugin directory (auto-scanned)
│   ├── swf_plugin_template.m         Reference template for new plugins
│   ├── swf_fault_injection.m         Hardware/environmental fault injection
│   ├── swf_metrics.m                 Real-time KPI dashboard (6 metrics)
│   ├── swf_battery.m                 Per-UAV battery drain simulation
│   ├── swf_collision.m               Collision detection + emergency separation
│   ├── swf_scenario_runner.m         Automated test scenario execution
│   ├── swf_3d_view.m                 Interactive 3D altitude visualization
│   ├── swf_geofence.m                No-fly zones and perimeter fencing
│   └── swf_map_polish.m              Compass rose, scale bar, legend overlays
└── paper/                            Research paper materials (optional)
    ├── appendix_equations.tex         57 numbered equations with \labels
    ├── paper_sections.tex             Sections 3-4 (Framework + Features)
    ├── paper_sections.docx            Same sections as Word document
    ├── future_work.tex                Future Work section (8 directions)
    └── experiments_results.tex        8 experiments with 9 results tables
```

Total codebase: ~3,200 lines of MATLAB across 11 files.


## Core Application

### GUI Tabs

| Tab | Purpose |
|-----|---------|
| Map & Control | Live 2D swarm map, mode selection, sliders, waypoints, event log |
| Telemetry | 6 real-time rolling plots: XYZ position + accel/gyro/magnetometer |
| Settings | Sim rate, comm range, wind, visual toggles, telemetry export |
| Modules | Plugin manager: discover, enable/disable, view details |

The window auto-sizes to fit the host screen and centers itself. All layout is responsive.

### Swarm Modes

| Mode | Behavior |
|------|----------|
| Leader-Follower | Configurable leader; others maintain diamond formation with proportional tracking |
| Decentralized | All UAVs wander autonomously with boids-style cohesion + separation |
| Hetero-Relay | UAV-4 acts as comm relay between swarm and base station |
| Hetero-Speed | UAV-1 scouts at 2x speed; UAVs 2-4 follow at 0.6x speed |

### UAV Configuration

| UAV | Color | Default Role | Initial Position |
|-----|-------|-------------|-----------------|
| UAV-1 (Alpha) | Blue | Leader | (0, 15, 30) |
| UAV-2 (Bravo) | Red | Follower | (-15, 0, 30) |
| UAV-3 (Charlie) | Green | Follower | (15, 0, 30) |
| UAV-4 (Delta) | Orange | Follower | (0, -15, 30) |

### GPS

Acquires location via ip-api.com on startup. Displays lat/lon in map title. Falls back to local-frame mode (37.0 N, 76.0 W) if offline. Re-acquire anytime via button.


## Plugins

### Enabling Plugins

```matlab
app.enableAllPlugins();            % enable everything
app.enablePlugin('fault_injection'); % enable one by id
app.disablePlugin('battery');      % disable one
```

Or check/uncheck boxes in the Modules tab.

### Plugin Summary

| Plugin | ID | Tab | Per-Tick | Purpose |
|--------|----|-----|---------|---------|
| Fault Injection | fault_injection | Yes | Yes | Inject 8 fault types with configurable intensity/duration |
| Metrics Dashboard | metrics | Yes | Yes | 6 real-time KPI plots (spread, formation error, link quality, etc.) |
| Battery Model | battery | Yes | Yes | 4S LiPo drain per UAV with voltage sag and endurance estimate |
| Collision Avoidance | collision | Yes | Yes | Emergency separation forces, near-miss/collision counters |
| Scenario Runner | scenarios | Yes | Yes | 6 automated test scenarios with pass/fail evaluation |
| 3D View | view3d | Yes | Yes | 3D visualization with altitude stems, ground shadows, connections |
| Geofencing | geofence | Yes | Yes | Circular/rectangular no-fly zones, perimeter fence, repulsion forces |
| Map Polish | map_polish | No | Yes | Compass rose, scale bar, legend, base label on main map |

### Fault Types

GPS Drift, GPS Denied, Motor Failure, Comm Blackout, Sensor Noise Spike, Frozen Actuator, Wind Gust, Battery Critical. Each has intensity (0.1-3.0x) and duration (1-600s) controls.

### Built-in Test Scenarios

| Scenario | Mode | Wind | Duration |
|----------|------|------|----------|
| Formation Hold - Calm | Leader-Follower | 0 m/s | 30s |
| Formation Hold - Wind | Leader-Follower | 8 m/s @ 45 deg | 30s |
| Waypoint Nav - Square | Leader-Follower | 0 m/s | 60s |
| Decentralized Cohesion | Decentralized | 3 m/s @ 180 deg | 45s |
| Relay Endurance | Hetero-Relay | 5 m/s @ 270 deg | 60s |
| Fast Scout Sprint | Hetero-Speed | 0 m/s | 45s |


## Programmatic API

```matlab
% Simulation control
app.onStart();  app.onStop();  app.onReset();

% Parameters (read/write)
app.MaxSwarmDist = 80;     % meters
app.CruiseAlt = 50;        % meters
app.CruiseSpeed = 8;       % m/s
app.WindSpeed = 5;          % m/s
app.WindDir = 90;           % degrees

% Mode
app.onModeChanged('Decentralized');
app.onLeaderChanged('UAV-2 (Bravo)');

% UAV access
pos = app.getUAVPosition(1);           % [x, y, z]
app.setUAVPosition(2, [50 30 40]);     % override position
tel = app.getTelemetry(3);             % full history struct

% Waypoints
app.setWaypoints([50 50; 100 0; 50 -50; 0 0]);

% Plugins
app.enablePlugin('metrics');
app.enableAllPlugins();
app.setState('my_plugin', 'key', value);
val = app.getState('my_plugin', 'key');

% Logging and export
app.logMsg('Custom message');
app.exportTelemetry();                 % save dialog for .mat
```

### Key Properties

| Property | Type | Description |
|----------|------|-------------|
| app.UAVPositions | [4x3] double | Current x, y, z of each UAV |
| app.UAVHeadings | [4x1] double | Heading in radians |
| app.UAVRoles | {4x1} cell | Role strings |
| app.TelHistory(k) | struct | .x .y .z .t .ax .ay .az .gx .gy .gz .mx .my .mz |
| app.SimTime | double | Simulation clock (seconds) |
| app.dt | double | Time step (seconds) |
| app.SwarmMode | char | Current mode string |
| app.IsRunning | logical | Simulation active flag |
| app.Waypoints | [Nx2] double | Waypoint coordinates |
| app.MapOrigin | [1x2] double | Base station [lat, lon] |


## Creating Custom Plugins

1. Copy `plugins/swf_plugin_template.m` to `plugins/swf_yourname.m`
2. Set `plugin.id` and `plugin.name` (id must be a valid MATLAB field name — no leading digits)
3. Implement callbacks: `onLoad`, `buildTab`, `onStep`, `onUnload`
4. Drop file in `plugins/` and click Rescan or restart

```matlab
function plugin = swf_yourname()
    plugin.id       = 'yourname';
    plugin.name     = 'Your Plugin';
    plugin.version  = '1.0';
    plugin.hasTab   = true;
    plugin.hasStep  = true;
    plugin.onLoad   = @(app) app.setState('yourname', 'count', 0);
    plugin.onUnload = @(app) [];
    plugin.buildTab = @(app, tab) uilabel(tab, 'Text', 'Hello');
    plugin.onStep   = @(app) myUpdate(app);
end

function myUpdate(app)
    % runs every tick, read/write app.UAVPositions, app.TelHistory, etc.
end
```

## Adding a New Swarm Mode

1. Add mode name to `ModeDropdown.Items` in `buildMapTab()`
2. Add `case` in `onModeChanged()` for role assignment
3. Create `stepYourMode(app, windVec)` method
4. Add `case` in `simStep()` to call it

## Simulation Engine

### Execution Order Per Tick

1. Advance time: t += dt
2. Compute wind vector
3. Run active swarm mode physics
4. Altitude convergence (proportional controller, gain 0.3)
5. Record telemetry (13 channels per UAV, 500-sample rolling buffer)
6. Run all enabled plugin onStep callbacks
7. Update map graphics (property updates only, no create/delete)
8. Update telemetry plots (only when Telemetry tab is visible)
9. drawnow limitrate

Plugins at step 6 can modify UAV positions written by physics at step 3. The renderer at step 7 sees the final combined result.

### Performance Design

All graphics objects created once at startup. Per-tick updates modify XData/YData/Visible properties only. Telemetry plots skipped when not visible. drawnow limitrate throttles to ~20 FPS.

## Telemetry Data Format

| Field | Unit | Description |
|-------|------|-------------|
| t | s | Simulation time |
| x, y, z | m | Position (East, North, Altitude) |
| ax, ay, az | m/s^2 | Accelerometer (finite-diff + noise) |
| gx, gy, gz | deg/s | Gyroscope (noise-dominated) |
| mx, my, mz | uT | Magnetometer (Earth field + noise) |

Exported .mat file contains: `TD` (telemetry), `P` (positions), `M` (mode), `Pr` (parameters).


## Research Paper Materials

The `paper/` folder contains LaTeX sources for the accompanying research paper:

| File | Contents |
|------|----------|
| appendix_equations.tex | 57 numbered equations across 11 categories, each with `\label{eq:...}` for `\eqref{}` cross-referencing |
| paper_sections.tex | Section 3 (Simulator Framework) and Section 4 (Features and Use Cases), ~3,500 words |
| paper_sections.docx | Same content as Word document (Times New Roman, headers, page numbers) |
| future_work.tex | Section: Future Work — 8 subsections covering HIL, scalability, RL, multi-swarm, etc. |
| experiments_results.tex | Section: Experiments and Results — 8 experiments, 9 tables, 29 equation references |

To use in your paper:
```latex
\input{appendix_equations}     % before \end{document}
\input{paper_sections}          % in the body
\input{experiments_results}     % in the body
\input{future_work}             % in the body
```

### Equation Categories (57 total)

| Category | Count |
|----------|-------|
| Kinematics | 7 |
| Control Laws | 6 |
| Swarm Coordination | 5 |
| Mode-Specific | 5 |
| Sensor Models | 5 |
| Fault Injection | 6 |
| Performance Metrics | 6 |
| Energy Model | 4 |
| Collision Avoidance | 3 |
| Geofencing | 5 |
| Rendering Geometry | 5 |


## Troubleshooting

| Problem | Fix |
|---------|-----|
| Window off screen | Fixed: auto-sizes to `min(1400, screenWidth-80)` x `min(780, screenHeight-120)` |
| `Unrecognized field name` on plugin | Plugin ID starts with a digit. Rename to start with letter (e.g. `view3d` not `3d_view`) |
| `Invalid color, marker, or line style` | Fixed: waypoints use `'Marker', 'd'` name-value syntax instead of `'dx'` |
| Plugins not found | Ensure `plugins/` folder is next to `SwarmFly.m` |
| GPS fails | App continues in local-frame mode. Click Re-acquire GPS to retry |
| TextArea.Value type error | Fixed: all logMsg calls use `char()` and `sprintf()` |
| Timer empty on Start | Fixed: `onStart` checks `isTimerValid()` and recreates if needed |
| `.Layout = struct(...)` error | Fixed: all layout assignments use explicit `.Layout.Row` / `.Layout.Column` |

### Performance Tips

- 10 Hz update rate gives smooth visuals with low CPU load
- Disable trails in Settings if map feels sluggish
- 3D View adds rendering cost; disable when not needed
- Unused plugins can be disabled to reduce per-tick overhead


## Version History

| Version | Changes |
|---------|---------|
| 1.0 | Initial release: 4 swarm modes, telemetry, GPS, map |
| 1.1 | Persistent graphics (no create/delete per frame), timer safety, char/string fixes |
| 2.0 | Plugin architecture, Modules tab, 9 shipped plugins, screen auto-sizing, waypoint marker fix, enableAllPlugins API |


## License

MIT
