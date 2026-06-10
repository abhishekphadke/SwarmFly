function plugin = swf_realmap()
    % SWF_REALMAP  Real-world map background using OpenStreetMap tiles.
    %
    % Downloads map tiles centered on the GPS-acquired base station
    % coordinates and displays them as a background image on the main
    % map axes. The image is positioned in the local ENU coordinate
    % frame so that UAV positions overlay correctly.
    %
    % Requires: Internet connection, GPS acquired (or default coords).
    % Tile source: OpenStreetMap (https://tile.openstreetmap.org)
    %
    % Note: Tiles are cached in a temp folder to avoid re-downloading
    %       on reset. Respects OSM usage policy with a User-Agent header.

    plugin.id          = 'realmap';
    plugin.name        = 'Real Map';
    plugin.description = 'Displays OpenStreetMap satellite/street tiles as the map background. Auto-downloads tiles based on GPS coordinates. Refresh button to re-fetch at different zoom.';
    plugin.version     = '1.0';
    plugin.hasTab      = true;
    plugin.hasStep     = true;
    plugin.hasToolbar  = false;

    plugin.onLoad    = @(app) onLoad(app);
    plugin.onUnload  = @(app) onUnload(app);
    plugin.buildTab  = @(app, tab) buildTab(app, tab);
    plugin.onStep    = @(app) onStep(app);
end

%% ========================================================================
%  CONSTANTS
%  ========================================================================

function mPerDeg = metersPerDegreeLat()
    mPerDeg = 111320;  % approximate meters per degree of latitude
end

function mPerDeg = metersPerDegreeLon(lat)
    mPerDeg = 111320 * cosd(lat);
end

%% ========================================================================
%  LIFECYCLE
%  ========================================================================

function onLoad(app)
    app.setState('realmap', 'imageHandle', []);
    app.setState('realmap', 'loaded', false);
    app.setState('realmap', 'zoom', 16);
    app.setState('realmap', 'tileGridSize', 5);  % 5x5 tiles
    app.setState('realmap', 'cacheDir', fullfile(tempdir, 'swarmfly_tiles'));
    app.setState('realmap', 'mapBounds', []);  % [xmin xmax ymin ymax] in local meters
    app.setState('realmap', 'opacity', 0.6);

    % Create cache directory
    cacheDir = fullfile(tempdir, 'swarmfly_tiles');
    if ~isfolder(cacheDir)
        mkdir(cacheDir);
    end

    % Attempt to load map immediately
    loadMapTiles(app);
end

function onUnload(app)
    % Remove the background image from the map
    ih = app.getState('realmap', 'imageHandle');
    if ~isempty(ih) && isvalid(ih)
        delete(ih);
    end
end

function buildTab(app, tab)
    grid = uigridlayout(tab, [5, 3], ...
        'RowHeight', {36, 50, 50, 36, '1x'}, ...
        'ColumnWidth', {180, '1x', 120}, ...
        'Padding', [15 15 15 15], 'RowSpacing', 8);

    % --- Status ---
    statusLbl = uilabel(grid, 'Text', 'Map Status: Checking...', ...
        'FontSize', 13, 'FontWeight', 'bold', 'Tag', 'rm_status');
    statusLbl.Layout.Row = 1; statusLbl.Layout.Column = [1 3];

    % --- Zoom level ---
    lbl = uilabel(grid, 'Text', 'Zoom Level (14-18):');
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    zoomSlider = uislider(grid, 'Limits', [14 18], 'Value', 16, ...
        'MajorTicks', 14:18, 'MinorTicks', [], ...
        'Tag', 'rm_zoom_slider');
    zoomSlider.Layout.Row = 2; zoomSlider.Layout.Column = 2;
    zoomLbl = uilabel(grid, 'Text', '16', 'Tag', 'rm_zoom_lbl', ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    zoomLbl.Layout.Row = 2; zoomLbl.Layout.Column = 3;
    zoomSlider.ValueChangedFcn = @(src,~) onZoomChanged(app, src, zoomLbl);

    % --- Opacity ---
    lbl = uilabel(grid, 'Text', 'Map Opacity:');
    lbl.Layout.Row = 3; lbl.Layout.Column = 1;
    opSlider = uislider(grid, 'Limits', [0.1 1.0], 'Value', 0.6, ...
        'Tag', 'rm_opacity_slider');
    opSlider.Layout.Row = 3; opSlider.Layout.Column = 2;
    opLbl = uilabel(grid, 'Text', '0.6', 'Tag', 'rm_opacity_lbl', ...
        'HorizontalAlignment', 'center');
    opLbl.Layout.Row = 3; opLbl.Layout.Column = 3;
    opSlider.ValueChangedFcn = @(src,~) onOpacityChanged(app, src, opLbl);

    % --- Buttons ---
    refreshBtn = uibutton(grid, 'push', 'Text', 'Reload Map Tiles', ...
        'BackgroundColor', [0.2 0.5 0.8], 'FontColor', 'w', ...
        'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) loadMapTiles(app));
    refreshBtn.Layout.Row = 4; refreshBtn.Layout.Column = [1 2];

    clearBtn = uibutton(grid, 'push', 'Text', 'Clear Cache', ...
        'ButtonPushedFcn', @(~,~) clearCache(app));
    clearBtn.Layout.Row = 4; clearBtn.Layout.Column = 3;

    % --- Info ---
    infoArea = uitextarea(grid, 'Editable', 'off', ...
        'FontName', 'Consolas', 'FontSize', 10, ...
        'Tag', 'rm_info', ...
        'Value', {'Real Map plugin uses OpenStreetMap tiles.'; ...
                  'Tiles are downloaded based on GPS coordinates.'; ...
                  ''; ...
                  'Higher zoom = more detail, smaller coverage area.'; ...
                  'Lower zoom  = less detail, larger coverage area.'; ...
                  ''; ...
                  'Zoom 14: ~2.4 km coverage'; ...
                  'Zoom 15: ~1.2 km coverage'; ...
                  'Zoom 16: ~600 m coverage  (default)'; ...
                  'Zoom 17: ~300 m coverage'; ...
                  'Zoom 18: ~150 m coverage'; ...
                  ''; ...
                  'Tiles (c) OpenStreetMap contributors.'});
    infoArea.Layout.Row = 5; infoArea.Layout.Column = [1 3];

    % Update status
    updateStatus(app);
end

%% ========================================================================
%  TILE MATH
%  ========================================================================

function [xtile, ytile] = latlon2tile(lat, lon, zoom)
    % Convert lat/lon to OSM tile coordinates
    n = 2^zoom;
    xtile = floor((lon + 180) / 360 * n);
    latRad = deg2rad(lat);
    ytile = floor((1 - log(tan(latRad) + sec(latRad)) / pi) / 2 * n);
end

function [lat, lon] = tile2latlon(xtile, ytile, zoom)
    % Convert tile coordinates to lat/lon of the tile's NW corner
    n = 2^zoom;
    lon = xtile / n * 360 - 180;
    latRad = atan(sinh(pi * (1 - 2 * ytile / n)));
    lat = rad2deg(latRad);
end

function [xm, ym] = latlon2local(lat, lon, lat0, lon0)
    % Convert lat/lon to local ENU meters relative to origin
    xm = (lon - lon0) * metersPerDegreeLon(lat0);
    ym = (lat - lat0) * metersPerDegreeLat();
end

%% ========================================================================
%  TILE DOWNLOAD AND STITCHING
%  ========================================================================

function loadMapTiles(app)
    lat0 = app.MapOrigin(1);
    lon0 = app.MapOrigin(2);
    zoom = app.getState('realmap', 'zoom');
    gridSz = app.getState('realmap', 'tileGridSize');
    cacheDir = app.getState('realmap', 'cacheDir');

    if isempty(zoom), zoom = 16; end
    if isempty(gridSz), gridSz = 5; end

    app.logMsg(sprintf('Loading map tiles (zoom=%d, %dx%d grid)...', zoom, gridSz, gridSz));
    updateStatusText(app, 'Downloading tiles...');

    % Find center tile
    [cx, cy] = latlon2tile(lat0, lon0, zoom);

    % Calculate tile range (centered grid)
    half = floor(gridSz / 2);
    xStart = cx - half;
    yStart = cy - half;

    % Download and stitch tiles
    tileSize = 256;
    bigImg = zeros(gridSz * tileSize, gridSz * tileSize, 3, 'uint8');
    tilesOK = 0;
    tilesFailed = 0;

    opts = weboptions('Timeout', 10, 'HeaderFields', ...
        {'User-Agent', 'SwarmFly/2.0 MATLAB UAV Simulator'});

    for row = 1:gridSz
        for col = 1:gridSz
            tx = xStart + col - 1;
            ty = yStart + row - 1;

            % Check cache first
            cacheFile = fullfile(cacheDir, sprintf('tile_%d_%d_%d.png', zoom, tx, ty));

            if isfile(cacheFile)
                try
                    tileImg = imread(cacheFile);
                    tilesOK = tilesOK + 1;
                catch
                    tileImg = ones(tileSize, tileSize, 3, 'uint8') * 230;
                    tilesFailed = tilesFailed + 1;
                end
            else
                % Download from OSM
                url = sprintf('https://tile.openstreetmap.org/%d/%d/%d.png', zoom, tx, ty);
                try
                    websave(cacheFile, url, opts);
                    tileImg = imread(cacheFile);
                    tilesOK = tilesOK + 1;
                catch
                    % Gray placeholder on failure
                    tileImg = ones(tileSize, tileSize, 3, 'uint8') * 230;
                    tilesFailed = tilesFailed + 1;
                end
            end

            % Ensure 3-channel RGB
            if size(tileImg, 3) == 1
                tileImg = repmat(tileImg, 1, 1, 3);
            end
            % Resize if needed
            if size(tileImg, 1) ~= tileSize || size(tileImg, 2) ~= tileSize
                tileImg = imresize(tileImg, [tileSize tileSize]);
            end

            % Place in mosaic
            rStart = (row - 1) * tileSize + 1;
            cStart = (col - 1) * tileSize + 1;
            bigImg(rStart:rStart+tileSize-1, cStart:cStart+tileSize-1, :) = tileImg;
        end
    end

    % Calculate geographic bounds of the stitched image
    % NW corner of first tile
    [latNW, lonNW] = tile2latlon(xStart, yStart, zoom);
    % SE corner of last tile (NW corner of tile one beyond)
    [latSE, lonSE] = tile2latlon(xStart + gridSz, yStart + gridSz, zoom);

    % Convert to local meters
    [xNW, yNW] = latlon2local(latNW, lonNW, lat0, lon0);
    [xSE, ySE] = latlon2local(latSE, lonSE, lat0, lon0);

    % Store bounds
    mapBounds = [xNW, xSE, ySE, yNW];  % [xmin, xmax, ymin, ymax]
    app.setState('realmap', 'mapBounds', mapBounds);

    % Display on map axes
    ax = app.MapAxes;

    % Remove old image if exists
    ih = app.getState('realmap', 'imageHandle');
    if ~isempty(ih) && isvalid(ih)
        delete(ih);
    end

    % Create image object
    % image() in MATLAB: XData = [left, right], YData = [top, bottom]
    % Our image: top-left is NW (high lat = high y), bottom-right is SE (low lat = low y)
    opacity = app.getState('realmap', 'opacity');
    if isempty(opacity), opacity = 0.6; end

    imgH = image(ax, 'CData', bigImg, ...
        'XData', [xNW, xSE], ...
        'YData', [yNW, ySE], ...
        'AlphaData', opacity);

    % Push image to back so UAVs render on top
    uistack(imgH, 'bottom');

    app.setState('realmap', 'imageHandle', imgH);
    app.setState('realmap', 'loaded', true);

    app.logMsg(sprintf('Map loaded: %d tiles OK, %d failed.', tilesOK, tilesFailed));
    app.logMsg(sprintf('Coverage: %.0fm x %.0fm centered on (%.4f, %.4f)', ...
        abs(xSE - xNW), abs(yNW - ySE), lat0, lon0));

    updateStatus(app);
end

%% ========================================================================
%  CALLBACKS
%  ========================================================================

function onZoomChanged(app, src, lbl)
    val = round(src.Value);
    src.Value = val;
    lbl.Text = num2str(val);
    app.setState('realmap', 'zoom', val);
end

function onOpacityChanged(app, src, lbl)
    val = round(src.Value, 2);
    lbl.Text = sprintf('%.2f', val);
    app.setState('realmap', 'opacity', val);

    % Update existing image opacity
    ih = app.getState('realmap', 'imageHandle');
    if ~isempty(ih) && isvalid(ih)
        ih.AlphaData = val;
    end
end

function clearCache(app)
    cacheDir = app.getState('realmap', 'cacheDir');
    if isfolder(cacheDir)
        delete(fullfile(cacheDir, '*.png'));
        app.logMsg('Tile cache cleared.');
    end

    % Remove image
    ih = app.getState('realmap', 'imageHandle');
    if ~isempty(ih) && isvalid(ih)
        delete(ih);
    end
    app.setState('realmap', 'loaded', false);
    app.setState('realmap', 'imageHandle', []);
    updateStatus(app);
end

function updateStatus(app)
    loaded = app.getState('realmap', 'loaded');
    if ~isempty(loaded) && loaded
        bounds = app.getState('realmap', 'mapBounds');
        zoom = app.getState('realmap', 'zoom');
        if ~isempty(bounds)
            covX = abs(bounds(2) - bounds(1));
            covY = abs(bounds(4) - bounds(3));
            updateStatusText(app, sprintf('Map loaded (zoom %d, %.0f x %.0f m)', zoom, covX, covY));
        else
            updateStatusText(app, 'Map loaded.');
        end
    else
        if app.GPSAcquired
            updateStatusText(app, 'GPS acquired. Click Reload to fetch tiles.');
        else
            updateStatusText(app, 'No GPS. Using default coordinates.');
        end
    end
end

function updateStatusText(app, txt)
    try
        lbl = findobj(app.Fig, 'Tag', 'rm_status');
        if ~isempty(lbl)
            lbl.Text = sprintf('Map Status: %s', txt);
        end
    catch
    end
end

%% ========================================================================
%  PER-TICK (keep image behind everything)
%  ========================================================================

function onStep(app)
    ih = app.getState('realmap', 'imageHandle');
    if isempty(ih) || ~isvalid(ih), return; end

    % Ensure image stays at the bottom of the render stack
    % (other plugins may add graphics that push it up)
    children = app.MapAxes.Children;
    if ~isempty(children) && children(end) ~= ih
        try
            uistack(ih, 'bottom');
        catch
        end
    end
end
