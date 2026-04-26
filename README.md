# SwarmFly— Drone Swarm Simulation & Test Platform

SwarmFly is a modular MATLAB GUI application for simulating, visualizing, and testing cooperative UAV swarm behavior. It provides a real-time 2D/3D operational map, four swarm coordination modes, simulated IMU telemetry, GPS geolocation, and a plugin architecture that allows researchers and developers to extend the platform with fault injection, performance metrics, energy modeling, collision avoidance, geofencing, and automated test scenarios — all without modifying the core application code.

The platform is designed as both a simulation tool and a test harness: you can run the swarm, inject faults mid-flight, measure KPIs, and evaluate algorithm resilience through repeatable automated scenarios.

---

## Table of Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [File Structure](#file-structure)
5. [Core Application](#core-application)
   - [GUI Tabs](#gui-tabs)
   - [Swarm Modes](#swarm-modes)
   - [UAV Specifications](#uav-specifications)
   - [GPS Integration](#gps-integration)
6. [Plugin System](#plugin-system)
   - [Architecture Overview](#architecture-overview)
   - [Enabling Plugins](#enabling-plugins)
   - [Plugin Lifecycle](#plugin-lifecycle)
   - [Plugin State API](#plugin-state-api)
7. [Shipped Plugins](#shipped-plugins)
   - [Fault Injection](#fault-injection)
   - [Metrics Dashboard](#metrics-dashboard)
   - [Battery Model](#battery-model)
   - [Collision Avoidance](#collision-avoidance)
   - [Scenario Runner](#scenario-runner)
   - [3D View](#3d-view)
   - [Geofencing](#geofencing)
   - [Map Polish](#map-polish)
8. [Programmatic API](#programmatic-api)
9. [Creating Custom Plugins](#creating-custom-plugins)
10. [Extending the Core](#extending-the-core)
11. [Simulation Engine Details](#simulation-engine-details)
12. [Telemetry Data Format](#telemetry-data-format)
13. [Troubleshooting](#troubleshooting)
14. [License](#license)

---

## Requirements

- **MATLAB R2020b** or later (requires `uifigure`, App Designer components, `uigridlayout`)
- **Internet connection** for IP-based GPS geolocation (optional; app works without it)
- No additional toolboxes required. The application uses only core MATLAB functionality.

---

## Installation

1. Download or clone the project files.
2. Ensure the following structure is preserved:

```
SwarmFly/
  SwarmFly.m
  run_SwarmFly.m
  README.md
  plugins/
    swf_plugin_template.m
    swf_fault_injection.m
    swf_metrics.m
    swf_battery.m
    swf_collision.m
    swf_scenario_runner.m
    swf_3d_view.m
    swf_geofence.m
    swf_map_polish.m
```

3. Open MATLAB and navigate to the `SwarmFly/` directory.
4. Run:

```matlab
run_SwarmFly
```

The application window will open, plugins will be discovered and enabled automatically, and GPS acquisition will be attempted.

---

## Quick Start

```matlab
% Launch with all plugins enabled
run_SwarmFly

% Or launch manually with selective plugins
app = SwarmFly();
app.enablePlugin('fault_injection');
app.enablePlugin('metrics');
app.onStart();  % Begin simulation
```

After launch:
1. The **Map & Control** tab shows the swarm in a diamond formation with 4 colored UAV triangles.
2. Select a swarm mode from the dropdown (Leader-Follower is the default).
3. Click **Start** to begin the simulation.
4. Switch to plugin tabs (Fault Injection, Metrics, etc.) to use test features.
5. Click **Add Waypoint** then click on the map to guide the swarm leader.
6. Adjust sliders for max swarm distance, altitude, speed, and wind.

---

## File Structure

| File | Lines | Purpose |
|------|-------|---------|
| `SwarmFly.m` | 1,324 | Core application: GUI, simulation engine, plugin infrastructure |
| `run_SwarmFly.m` | 47 | Launcher script with auto-enable and usage examples |
| `plugins/swf_plugin_template.m` | 97 | Reference template for creating new plugins |
| `plugins/swf_fault_injection.m` | 212 | Hardware/environmental fault injection with GUI |
| `plugins/swf_metrics.m` | 149 | Real-time KPI dashboard (6 metrics) |
| `plugins/swf_battery.m` | 175 | Per-UAV battery drain simulation |
| `plugins/swf_collision.m` | 139 | Collision detection and emergency separation |
| `plugins/swf_scenario_runner.m` | 310 | Automated test scenario execution |
| `plugins/swf_3d_view.m` | 185 | Interactive 3D altitude visualization |
| `plugins/swf_geofence.m` | 390 | No-fly zones and perimeter fencing |
| `plugins/swf_map_polish.m` | 178 | Compass rose, scale bar, and legend overlays |
| **Total** | **3,206** | |

---

## Core Application

### GUI Tabs

The core application provides four built-in tabs:

**Map & Control** — The primary operational view. Contains a 2D area map (UIAxes) with equal-axis scaling showing UAV positions as colored triangles, inter-UAV connection lines with distance labels (gray when healthy, red when exceeding max swarm distance), UAV trails, a base station marker, and waypoint markers. The control panel includes swarm mode dropdown, leader UAV selector, sliders for max swarm distance (10–200m), cruise altitude (5–120m), and cruise speed (1–25 m/s), Start/Stop/Reset buttons, GPS re-acquisition, waypoint placement, a status lamp, and a scrolling event log.

**Telemetry** — Six real-time rolling plots arranged in a 2x3 grid. Row 1 shows Position X, Position Y, Position Z (altitude) with one line per UAV, color-coded. Row 2 shows Accelerometer (3-axis), Gyroscope (3-axis), Magnetometer (3-axis) with solid/dashed/dotted lines for x/y/z components. Telemetry plots update only when the Telemetry tab is active (performance optimization). Rolling buffer of 500 samples per UAV.

**Settings** — Global simulation and display parameters including simulation update rate (1–30 Hz), communication range (50–1000m), wind speed (0–20 m/s) and wind direction (0–360 deg), visual toggles for trails, grid, and connection lines, and telemetry export to `.mat` file.

**Modules** — Plugin manager with a left panel listing discovered plugins with enable/disable checkboxes, name buttons, and version labels, and a right panel showing plugin name, version, description, capabilities (Tab / Per-Tick / Toolbar), and source file. Includes a rescan button to re-discover plugins after adding new files.

### Swarm Modes

| Mode | Behavior | Leader | Roles |
|------|----------|--------|-------|
| **Leader-Follower** | One UAV leads (follows waypoints or orbits); other 3 maintain a diamond formation offset with proportional tracking. Followers are constrained to max swarm distance. | Configurable via dropdown | leader, follower, follower, follower |
| **Decentralized** | All 4 UAVs wander autonomously using boids-style behaviors: randomized wander + inter-UAV separation (repulsion when < 10m) + centroid cohesion (attraction to swarm center). | None | autonomous x4 |
| **Hetero-Relay** | UAVs 1-3 operate in leader-follower formation. UAV-4 acts as a communication relay node, hovering at 40% of the distance between base and the active swarm centroid. Relay is speed-limited to 3 m/s. | UAV-1 | normal, normal, normal, relay |
| **Hetero-Speed** | UAV-1 is a fast scout (2x cruise speed). UAVs 2-4 are slow followers (0.6x cruise speed) maintaining a V-formation behind the scout. | UAV-1 (scout) | fast, slow, slow, slow |

### UAV Specifications

| Property | UAV-1 (Alpha) | UAV-2 (Bravo) | UAV-3 (Charlie) | UAV-4 (Delta) |
|----------|---------------|---------------|-----------------|---------------|
| Color | Blue | Red | Green | Orange |
| RGB | (0.18, 0.55, 0.94) | (0.90, 0.30, 0.24) | (0.20, 0.78, 0.35) | (0.95, 0.65, 0.10) |
| Default role | Leader | Follower | Follower | Follower |
| Map symbol | Triangle | Triangle | Triangle | Triangle (Diamond when relay) |
| Initial position | (0, 15, 30) | (-15, 0, 30) | (15, 0, 30) | (0, -15, 30) |

### GPS Integration

On startup, SwarmFly attempts to acquire the user's geographic coordinates via IP-based geolocation using the ip-api.com REST API. If successful, the base station latitude/longitude is displayed in the map title and stored in `app.MapOrigin`. If the request fails (no internet, API down), the app defaults to coordinates (37.0, -76.0) and continues operating in local frame mode. GPS can be re-acquired at any time via the "Re-acquire GPS" button.

---

## Plugin System

### Architecture Overview

SwarmFly's plugin system allows external `.m` files to integrate deeply into the core application without modifying `SwarmFly.m`. Plugins can create GUI tabs with buttons, sliders, tables, plots, and any UIFigure components. They can run code every simulation tick with full read/write access to UAV positions, headings, telemetry, and simulation parameters. They can store persistent state across ticks using a namespaced key-value store. They can access the event log to report warnings, errors, and status updates. They can modify UAV behavior by directly writing to `app.UAVPositions`, `app.UAVHeadings`, and `app.TelHistory`.

### Enabling Plugins

There are three ways to enable plugins:

```matlab
% 1. Automatic (in run_SwarmFly.m - enabled by default)
app.enableAllPlugins();

% 2. Selective
app.enablePlugin('fault_injection');
app.enablePlugin('metrics');

% 3. Via GUI
% Go to the Modules tab and check the box next to any plugin
```

### Plugin Lifecycle

```
Startup
  discoverPlugins()          Scans plugins/ for swf_*.m files
    For each file: calls the function, gets the plugin struct
    Registers in PluginRegistry, sets PluginEnabled.(id) = false

User enables plugin (checkbox or app.enablePlugin)
  PluginEnabled.(id) = true
  PluginStates.(id) = struct()      Empty state container
  onLoad(app)                       Plugin initializes its data
  buildTab(app, tab)                Plugin builds its GUI tab

Simulation running (every tick)
  simStep()
    Physics engine runs
    Telemetry recorded
    For each enabled plugin with hasStep:
      plugin.onStep(app)            Plugin reads/writes app state
    Map graphics updated
    drawnow limitrate

User disables plugin (uncheck or app.disablePlugin)
  PluginEnabled.(id) = false
  onUnload(app)                     Plugin cleans up
  Tab deleted
  PluginStates.(id) removed
```

### Plugin State API

Each plugin gets an isolated namespace for storing data between ticks:

```matlab
% Store a value
app.setState('my_plugin', 'key', value);

% Retrieve a value (returns [] if not found)
val = app.getState('my_plugin', 'key');
```

State is automatically cleared when a plugin is disabled. Plugins should use their own `id` as the namespace to avoid collisions.

---

## Shipped Plugins

### Fault Injection
**ID:** `fault_injection` | **Tab:** Yes | **Per-Tick:** Yes

Injects hardware and environmental faults into individual UAVs during simulation to test swarm resilience.

Supported fault types:

| Fault | Effect on UAV |
|-------|--------------|
| GPS Drift | Position accumulates sinusoidal drift proportional to elapsed time |
| GPS Denied | Position receives random walk noise (UAV flies blind) |
| Motor Failure | Altitude decays at 0.8 x intensity m/s |
| Comm Blackout | Position receives large random perturbation (no formation correction) |
| Sensor Noise Spike | Accelerometer telemetry gets +/-20g noise spikes |
| Frozen Actuator | UAV drifts in last known heading direction |
| Wind Gust | Random-direction impulse of 15 x intensity m/s |
| Battery Critical | Altitude decays at 1.5 x intensity m/s |

GUI controls include fault type dropdown, target UAV selector (individual or all), duration (1-600s), intensity slider (0.1-3.0x), inject/clear buttons, and a live table of active faults with remaining time.

### Metrics Dashboard
**ID:** `metrics` | **Tab:** Yes | **Per-Tick:** Yes

Six real-time KPI plots tracking swarm performance:

| Metric | Definition |
|--------|-----------|
| Swarm Spread | Maximum pairwise distance between any two UAVs (m) |
| Mean Inter-UAV Distance | Average of all 6 pairwise distances (m) |
| Centroid Drift | Distance from swarm centroid to base station (m) |
| Formation Error | Mean positional deviation from ideal formation offsets (m) |
| Altitude Deviation | Mean absolute altitude error from cruise altitude (m) |
| Link Quality | Percentage of UAV pairs within communication range (%) |

Rolling buffer of 1,000 samples. Each metric is plotted as a single colored line.

### Battery Model
**ID:** `battery` | **Tab:** Yes | **Per-Tick:** Yes

Simulates 4S LiPo battery drain per UAV based on flight dynamics. The energy model uses base hover current of 18A, speed load of 2.0A per m/s, altitude penalty of 0.05A per meter above 20m, wind load of 0.5A per m/s wind speed, battery capacity of 5,000 mAh per UAV, and linear voltage sag from 16.8V (full) to 12.0V (dead). GUI shows a status table (per-UAV remaining mAh, percentage, voltage, current draw, estimated flight time) and historical battery percentage plot with color-coded lines. Warnings are logged at 20% and 10% remaining.

### Collision Avoidance
**ID:** `collision` | **Tab:** Yes | **Per-Tick:** Yes

Safety layer that monitors pairwise distances and applies emergency separation maneuvers. When two UAVs are within the safe distance (default 5m), a repulsion force proportional to penetration depth is applied along the separation vector. Near-misses are logged when distance falls below the safe distance. Collisions are logged when distance drops below 40% of safe distance. GUI shows near-miss and collision counters, a safe distance slider (1-20m), and a minimum pairwise distance plot over time with safe-distance threshold line.

### Scenario Runner
**ID:** `scenarios` | **Tab:** Yes | **Per-Tick:** Yes

Defines and executes repeatable test scenarios with pass/fail evaluation.

Built-in scenarios:

| Scenario | Mode | Wind | Duration | Max Dist |
|----------|------|------|----------|----------|
| Formation Hold - Calm | Leader-Follower | 0 m/s | 30s | 50m |
| Formation Hold - Wind | Leader-Follower | 8 m/s @ 45 deg | 30s | 50m |
| Waypoint Nav - Square | Leader-Follower | 0 m/s | 60s | 50m |
| Decentralized Cohesion | Decentralized | 3 m/s @ 180 deg | 45s | 80m |
| Relay Endurance | Hetero-Relay | 5 m/s @ 270 deg | 60s | 60m |
| Fast Scout Sprint | Hetero-Speed | 0 m/s | 45s | 100m |

GUI includes scenario dropdown, Run Selected / Run All / Abort buttons, progress display with elapsed time and max spread, and a results table with pass/fail for each completed scenario. Run All executes scenarios sequentially with 2-second gaps.

### 3D View
**ID:** `view3d` | **Tab:** Yes | **Per-Tick:** Yes

Interactive 3D visualization of the swarm showing the altitude dimension. Features include UAV markers as colored triangles at actual (x, y, z) positions, dotted altitude stems from each UAV to the ground plane, gray shadow projections on the ground, 3D inter-UAV connection lines (blue healthy, red over-distance), a transparent mesh ground plane with base station marker, labels showing UAV number and altitude (e.g. `U2 [30m]`), MATLAB's built-in 3D rotation/zoom via mouse drag, and dynamic axis limits tracking the swarm.

### Geofencing
**ID:** `geofence` | **Tab:** Yes | **Per-Tick:** Yes

No-fly zone definition and enforcement with map overlays. Supports circular and rectangular no-fly zones drawn as red dashed shaded regions on the map. Ships with 2 demo zones (Tower circle at (80,60) r=25m and Building rect at (-100,-80) 40x50m). New zones can be placed by clicking the map. Includes a configurable perimeter fence (dashed blue circle, default 200m radius). Enforcement uses physics-based repulsion forces that push UAVs away from zone boundaries, with a soft boundary that begins gentle push 8m before the zone edge. GUI provides perimeter radius slider, repulsion strength slider, enforcement toggles, add circle/rect/clear buttons, violation counter, zone count, and zone list table.

### Map Polish
**ID:** `map_polish` | **Tab:** No | **Per-Tick:** Yes

Visual polish overlays on the main swarm map. No dedicated tab — elements are drawn directly on MapAxes and reposition each tick as the view zooms and pans. Elements include a compass rose (top-left) with a red north indicator triangle and N/S/E/W labels, a scale bar (bottom-left) with endcaps and auto-selected round-number distance label (snaps to 5/10/20/25/50/100/200/500m), a UAV legend (top-right) as a semi-transparent box showing each UAV's color triangle, number, and current role, and a "BASE" label below the base station marker. All elements scale proportionally to the current axis limits.

---

## Programmatic API

All public methods are accessible from the MATLAB Command Window via the `app` handle:

```matlab
% --- Simulation Control ---
app.onStart()                        % Start simulation
app.onStop()                         % Stop simulation
app.onReset()                        % Reset to initial formation

% --- Mode & Parameters ---
app.onModeChanged('Decentralized')   % Switch swarm mode
app.onLeaderChanged('UAV-2 (Bravo)') % Set leader (Leader-Follower mode)
app.MaxSwarmDist = 80;               % Set max swarm distance (m)
app.CruiseAlt = 50;                  % Set cruise altitude (m)
app.CruiseSpeed = 8;                 % Set cruise speed (m/s)
app.WindSpeed = 5;                   % Set wind speed (m/s)
app.WindDir = 90;                    % Set wind direction (degrees)

% --- UAV Access ---
pos = app.getUAVPosition(1);         % Get [x, y, z] of UAV-1
app.setUAVPosition(2, [50 30 40]);   % Override UAV-2 position
tel = app.getTelemetry(3);           % Get telemetry history struct for UAV-3

% --- Waypoints ---
app.setWaypoints([50 50; 100 0; 50 -50; 0 0]);

% --- Plugin Management ---
app.enablePlugin('fault_injection');  % Enable single plugin
app.disablePlugin('battery');         % Disable single plugin
app.enableAllPlugins();               % Enable all discovered plugins
app.discoverPlugins();                % Re-scan plugins/ folder

% --- Plugin State ---
app.setState('my_plugin', 'key', value);
val = app.getState('my_plugin', 'key');

% --- Custom Tabs ---
app.addCustomTab('My Tab', @(tab) uilabel(tab, 'Text', 'Hello'));

% --- Logging ---
app.logMsg('Custom log message');

% --- Data Export ---
app.exportTelemetry();                % Opens save dialog for .mat file
```

### Key Properties (Read/Write)

| Property | Type | Description |
|----------|------|-------------|
| `app.UAVPositions` | [4x3] double | Current x, y, z of each UAV |
| `app.UAVHeadings` | [4x1] double | Current heading in radians |
| `app.UAVRoles` | {4x1} cell | Role strings: leader, follower, relay, etc. |
| `app.TelHistory(k)` | struct | Per-UAV telemetry (see Telemetry Data Format) |
| `app.SimTime` | double | Current simulation clock (seconds) |
| `app.dt` | double | Current time step (seconds) |
| `app.SwarmMode` | char | Current mode string |
| `app.Waypoints` | [Nx2] double | Waypoint coordinates [x, y] |
| `app.WaypointIdx` | double | Index of next waypoint to reach |
| `app.IsRunning` | logical | Whether simulation is active |
| `app.GPSAcquired` | logical | Whether GPS lock was obtained |
| `app.MapOrigin` | [1x2] double | Base station [lat, lon] |
| `app.NumUAVs` | double | Number of UAVs (always 4) |

---

## Creating Custom Plugins

1. Copy `plugins/swf_plugin_template.m` to `plugins/swf_yourname.m`.
2. Edit the function to return a struct with your plugin's configuration.
3. Implement the callback functions.
4. Place the file in the `plugins/` folder.
5. Restart SwarmFly or click "Rescan Plugins Folder" in the Modules tab.

### Plugin Struct Fields

```matlab
function plugin = swf_yourname()
    % --- REQUIRED ---
    plugin.id          = 'yourname';         % Valid MATLAB field name (no leading digits)
    plugin.name        = 'Your Plugin';      % Display name in Modules tab

    % --- OPTIONAL ---
    plugin.description = 'What it does.';    % Shown in detail panel
    plugin.version     = '1.0';              % Version string
    plugin.hasTab      = true;               % Creates a GUI tab when enabled
    plugin.hasStep     = true;               % onStep called every sim tick
    plugin.hasToolbar  = false;              % Reserved for future use

    % --- CALLBACKS (function handles, or [] to skip) ---
    plugin.onLoad      = @(app) init(app);
    plugin.onUnload    = @(app) cleanup(app);
    plugin.buildTab    = @(app, tab) buildUI(app, tab);
    plugin.onStep      = @(app) update(app);
end
```

### Important Constraints

- Plugin ID must be a valid MATLAB struct field name. No spaces, no leading digits. Use snake_case: `my_plugin`, `view3d`, `nav_planner`.
- `onStep` must be fast. It runs at the simulation update rate (default 10 Hz). Avoid heavy computation or file I/O in onStep.
- Use `setState`/`getState` for persistence. Do not add properties to the app object.
- Use `findobj(app.Fig, 'Tag', 'your_tag')` for cross-tab UI access when onStep needs to update labels in the plugin's tab.
- Wrap UI updates in try-catch. Timer callbacks run on a separate thread; if the figure is closing or the tab was deleted, handle access will error.

---

## Extending the Core

To add a new swarm mode to SwarmFly.m:

1. Add the mode name to `ModeDropdown.Items` in `buildMapTab()`.
2. Add a `case` in `onModeChanged()` to assign UAV roles.
3. Create a new method `stepYourMode(app, windVec)` that computes position updates.
4. Add the `case` in `simStep()` to call your new method.

To add more UAVs, change `app.NumUAVs`, expand `UAVColors`, `UAVNames`, `UAVPositions`, `UAVHeadings`, and update the graphics initialization loops in `initMapGraphics` and `initTelemetryGraphics`.

---

## Simulation Engine Details

### Execution Order Per Tick

The timer fires `simStep()` at a fixed rate (default 10 Hz / 100ms period):

1. **Time advance**: `dt = 1/UpdateRate`, `SimTime += dt`
2. **Wind vector**: computed from `WindSpeed` and `WindDir` using `cosd`/`sind`
3. **Physics**: the active swarm mode function computes new UAV positions and headings based on waypoints, formation offsets, cohesion/separation rules, and wind
4. **Altitude convergence**: all UAVs are pulled toward `CruiseAlt` with a proportional controller (gain 0.3)
5. **Telemetry recording**: position and simulated IMU data appended to `TelHistory` with rolling buffer trim
6. **Plugin step loop**: every enabled plugin with `hasStep=true` has its `onStep(app)` called; plugins can read and modify `UAVPositions`, `TelHistory`, and any other public property
7. **Map graphics update**: persistent graphics handles have their XData/YData/Visible properties updated (no create/delete per frame)
8. **Telemetry plot update**: only runs when the Telemetry tab is the active tab
9. **Render**: `drawnow limitrate` flushes the graphics pipeline

### Performance Design

All map graphics (UAV patches, trails, connection lines, labels) are created once in `initMapGraphics()` and updated via property changes in `updateMapGraphics()`. No `delete`/`findobj`/`cla` per frame. Telemetry plots use persistent line handles with XData/YData updates. Telemetry plot updates are skipped when the Telemetry tab is not visible. `drawnow limitrate` throttles rendering to approximately 20 FPS regardless of timer rate. Plugin onStep errors are caught and logged without crashing the simulation.

### Formation Geometry

The default diamond formation offsets (relative to leader, at MaxSwarmDist = 50):

```
             Leader (0, 0)
            /              \
     (-20, -12)        (20, -12)
            \              /
             (0, -24)
```

Offsets scale linearly with `MaxSwarmDist / 50`. The leader's offset is always (0,0,0); other UAVs track `leader_position + offset` with proportional control (gain 2.0) and speed limiting at 1.5x cruise speed.

---

## Telemetry Data Format

Each UAV's telemetry is stored in `app.TelHistory(k)` as a struct with the following fields, all row vectors of equal length:

| Field | Unit | Description |
|-------|------|-------------|
| `t` | s | Simulation time |
| `x` | m | East position |
| `y` | m | North position |
| `z` | m | Altitude (AGL) |
| `ax` | m/s^2 | Accelerometer X (derived from position delta + noise) |
| `ay` | m/s^2 | Accelerometer Y |
| `az` | m/s^2 | Accelerometer Z (approx 9.81 + noise) |
| `gx` | deg/s | Gyroscope X (noise only) |
| `gy` | deg/s | Gyroscope Y (noise only) |
| `gz` | deg/s | Gyroscope Z (heading rate x 0.1 + noise) |
| `mx` | uT | Magnetometer X (approx 25 + noise) |
| `my` | uT | Magnetometer Y (approx 5 + noise) |
| `mz` | uT | Magnetometer Z (approx -40 + noise) |

Maximum buffer length: 500 samples (configurable via `app.MaxHistory`). Oldest samples are trimmed when the buffer is full.

### Exported .mat File Contents

When using Export Telemetry from the Settings tab:

| Variable | Type | Content |
|----------|------|---------|
| `TD` | struct array | Full TelHistory (4 elements) |
| `P` | [4x3] double | Final UAV positions |
| `M` | char | Current swarm mode |
| `Pr` | struct | Parameters: MaxSwarmDist, CruiseAlt, CruiseSpeed, CommRange, WindSpeed, WindDir, MapOrigin |

---

## Troubleshooting

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| Window goes off screen | Screen smaller than default window | Fixed in v2.0: auto-sizes to screen with margins and centers |
| `Unrecognized field name` on plugin load | Plugin ID starts with a digit (e.g. `3d_view`) | Rename to start with a letter (e.g. `view3d`). MATLAB struct fields cannot start with digits |
| `Invalid color, marker, or line style` | Using `'dx'` as a plot marker spec | Fixed in v2.0: waypoint markers use `'Marker', 'd'` name-value syntax |
| Plugins not found | `plugins/` folder not next to `SwarmFly.m` | Ensure `plugins/` is a direct subfolder of the directory containing `SwarmFly.m` |
| GPS acquisition fails | No internet or ip-api.com unreachable | App continues in local frame mode. Click "Re-acquire GPS" to retry |
| Timer error on close | Timer callback fires during figure deletion | All timer operations are wrapped in try-catch; errors are logged but harmless |
| `TextArea.Value` type error | Mixing MATLAB string type with char cell arrays | Fixed in v2.0: all logMsg calls use char() and sprintf() |
| `Property assignment not allowed when object is empty` | Timer not created due to earlier error | Fixed in v2.0: onStart checks isTimerValid() and recreates if needed |

### Performance Tips

- Set simulation update rate to 10 Hz for smooth visuals. Higher rates (20-30 Hz) increase CPU load.
- Disable trail rendering (Settings tab) if the map feels sluggish with many telemetry samples.
- Plugins with heavy onStep logic add overhead. Disable unused plugins during high-speed runs.
- The 3D View plugin adds rendering cost. Disable when not needed.

---

## License

MIT
