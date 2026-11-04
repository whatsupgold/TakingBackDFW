#!/usr/bin/env python3
"""Taking Back Texas: the map builder.

Turns real map data into the game's 1:3 Texas:
  - OpenStreetMap for all of Texas (texas-latest.osm.pbf from Geofabrik): roads, buildings,
    water, the coastline, railways, airfields, cities and the state border
  - NOAA ETOPO 2022 elevation (elevation.nc): the land and the sea floor

Distances are a third of real (1 game metre = 3 real metres) but buildings, roads and runways
keep their real size, so cities are thinned: the biggest and tallest buildings go in first and
the rest only where there is still room.

Usage:
    python tools/texas_build.py                     (reads data/texas/, writes data/texas/build/)
    python tools/texas_build.py --osm X.osm.pbf --elev elevation.nc --out data/texas/build
    python tools/texas_build.py --stage bake        (re-bake from the last extract, skipping OSM)

Needs: pip install osmium shapely mapbox-earcut numpy scipy pillow

What it writes (see scripts/texas/texas_data.gd for the reader):
    meta.json           cities, airfields, ports, the state outline, counts
    map.png             the strategic map: relief, sea, lakes, roads, the border
    roads.bin           the highway network as a graph, for units to drive on
    regions/r_X_Z.bin   per 32 km region: heights every 64 m, ground flags, and per 2 km tile
                        the roads, buildings, water, rivers, railways and runways in it
"""

import argparse
import json
import math
import os
import pickle
import struct
import sys
import time
import zlib
from array import array

import numpy as np

# --- The projection: must match TexasGeo -----------------------------------------------------
SCALE = 3.0
LAT0 = 31.0
LON0 = -99.9
MLAT = 110950.0
MLON = 95420.0
MIN_LAT, MAX_LAT, MIN_LON, MAX_LON = 25.5, 36.8, -106.9, -93.2

TILE = 2048.0
RT = 16                                  # tiles a side per region
REGION = TILE * RT                       # 32768 m
HSTEP = 64.0                             # height samples every 64 game metres
HN = int(REGION / HSTEP) + 1             # 513 samples a side per region
OCC = 4.0                                # building placement grid, game metres
VERSION = 1


def to_xz(lat, lon):
    return (lon - LON0) * MLON / SCALE, (LAT0 - lat) * MLAT / SCALE


def to_latlon(x, z):
    return LAT0 - z * SCALE / MLAT, LON0 + x * SCALE / MLON


GX0, GZ0 = to_xz(MAX_LAT, MIN_LON)
GX1, GZ1 = to_xz(MIN_LAT, MAX_LON)
RX0 = math.floor(GX0 / REGION)
RX1 = math.floor(GX1 / REGION)
RZ0 = math.floor(GZ0 / REGION)
RZ1 = math.floor(GZ1 / REGION)
NRX = RX1 - RX0 + 1
NRZ = RZ1 - RZ0 + 1
# The global height grid, aligned with the regions
HX0 = RX0 * REGION
HZ0 = RZ0 * REGION
HNX = NRX * (HN - 1) + 1
HNZ = NRZ * (HN - 1) + 1

# --- What we keep from OpenStreetMap ---------------------------------------------------------
ROAD_CLASS = {"motorway": 0, "trunk": 1, "primary": 2, "secondary": 3, "tertiary": 4,
              "motorway_link": 5, "trunk_link": 6, "primary_link": 7, "secondary_link": 8}
ROAD_WIDTH = {0: 11.0, 1: 10.0, 2: 9.0, 3: 8.0, 4: 7.0, 5: 5.0, 6: 5.0, 7: 5.0, 8: 5.0}
ROUTE_CLASSES = {0, 1, 2, 3, 5, 6, 7, 8}   # what units route over (tertiary is drawn only)

BUILDING_KIND = {
    "house": 1, "detached": 1, "residential": 1, "semidetached_house": 1, "terrace": 1,
    "bungalow": 1, "static_caravan": 1, "duplex": 1,
    "apartments": 2, "dormitory": 2, "hotel": 2,
    "commercial": 3, "retail": 3, "office": 3, "supermarket": 3, "kiosk": 3,
    "industrial": 4, "warehouse": 4, "manufacture": 4, "hangar": 4, "storage_tank": 4,
    "silo": 4, "service": 4,
    "barn": 5, "farm_auxiliary": 5, "farm": 5, "stable": 5, "cowshed": 5,
    "church": 6, "cathedral": 6, "mosque": 6, "temple": 6, "synagogue": 6, "school": 6,
    "university": 6, "college": 6, "hospital": 6, "public": 6, "civic": 6, "government": 6,
    "fire_station": 6, "train_station": 6, "stadium": 6, "sports_hall": 6, "transportation": 6,
    "military": 7, "bunker": 7,
}
BUILDING_SKIP = {"garage", "garages", "shed", "carport", "roof", "hut", "construction", "ruins",
                 "no", "greenhouse", "tent", "collapsed", "destroyed", "abandoned", "proposed"}
DEFAULT_HEIGHT = {0: 6.0, 1: 5.0, 2: 12.0, 3: 7.0, 4: 9.0, 5: 6.0, 6: 10.0, 7: 5.0}
MIN_BUILDING_AREA = 25.0                 # real square metres

MIN_WATER_AREA = 15000.0                 # real square metres; smaller ponds are left out
FLAT_WATER = {"lake", "reservoir", "pond", "basin", "lagoon", "oxbow", "", "yes"}

# Ports the navy can take (lat, lon): the deep-water ports along the coast
PORTS = [
    ["Port of Houston (Barbours Cut)", 29.683, -95.000],
    ["Port of Houston (Turning Basin)", 29.733, -95.270],
    ["Galveston", 29.310, -94.795],
    ["Texas City", 29.370, -94.895],
    ["Freeport", 28.945, -95.310],
    ["Port Lavaca / Point Comfort", 28.655, -96.560],
    ["Corpus Christi", 27.812, -97.400],
    ["Port Arthur", 29.868, -93.930],
    ["Beaumont", 30.080, -94.090],
    ["Orange", 30.090, -93.730],
    ["Brownsville", 25.950, -97.400],
]

MILITARY_WORDS = ("air force base", "afb", "naval air station", "nas ", "army airfield",
                  "army air field", "aaf", "joint base", "air reserve", "jrb", "military",
                  "fort hood", "fort cavazos", "fort bliss")


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def parse_len(v):
    """'12', '12 m', '40\\'', '40 ft' -> metres, or None"""
    if v is None:
        return None
    s = v.strip().lower().replace(",", ".")
    feet = s.endswith("'") or s.endswith("ft") or "feet" in s
    num = ""
    for ch in s:
        if ch.isdigit() or ch == ".":
            num += ch
        elif num:
            break
    try:
        f = float(num)
    except ValueError:
        return None
    return f * 0.3048 if feet else f


# =============================================================================================
# Stage 1: extract what we need from the OSM file into compact arrays
# =============================================================================================

def extract(osm_path, work):
    import osmium

    size = os.path.getsize(osm_path)
    big = size > 200e6
    if big:
        store = "sparse_file_array," + os.path.join(work, "nodes.idx")
    else:
        store = "flex_mem"
    log("reading %s (%.0f MB), node cache %s" % (osm_path, size / 1e6, store.split(",")[0]))
    keys = ("building", "highway", "railway", "natural", "water", "waterway", "aeroway",
            "place", "boundary", "landuse", "military")
    area_keys = osmium.filter.KeyFilter("building", "natural", "water", "waterway", "boundary",
                                        "landuse", "aeroway")
    fp = (osmium.FileProcessor(osm_path)
          .with_locations(store)
          .with_areas(area_keys)
          .with_filter(osmium.filter.KeyFilter(*keys)))

    b_lon = array("d")
    b_lat = array("d")
    b_off = array("q", [0])
    b_h = array("f")
    b_kind = array("b")
    r_lon = array("d")
    r_lat = array("d")
    r_ids = array("q")
    r_off = array("q", [0])
    r_cls = array("b")
    r_width = array("f")
    r_bridge = array("b")
    r_ref = []
    water = []          # [kind, flat, [outer ring [(lon, lat)...], inner rings...]]
    rivers = []         # [width, [(lon, lat)...]]
    coast = []          # [(lon, lat)...]
    rail = []           # [(lon, lat)...]
    aerodromes = []     # dicts
    runways = []        # dicts
    places = []         # [name, kind, population, lat, lon]
    texas = []          # rings of the state border: [outer, [inners]]
    counts = {"objects": 0}
    t0 = time.time()

    def way_coords(w):
        pts = []
        for n in w.nodes:
            if n.location.valid():
                pts.append((n.lon, n.lat))
        return pts

    for o in fp:
        counts["objects"] += 1
        if counts["objects"] % 2000000 == 0:
            log("  %d M objects, %d buildings, %d road ways, %.0f s" % (
                counts["objects"] // 1000000, len(b_h), len(r_cls), time.time() - t0))
        tags = o.tags
        t = o.type_str()
        if t == "n":
            pl = tags.get("place")
            if pl in ("city", "town") and "name" in tags:
                pop = 0
                try:
                    pop = int(float(tags.get("population", "0").replace(",", "").split(";")[0]))
                except ValueError:
                    pass
                places.append([tags["name"], pl, pop, o.location.lat, o.location.lon])
            elif tags.get("aeroway") == "aerodrome":
                aerodromes.append(_aerodrome(tags, o.location.lat, o.location.lon))
            continue
        if t == "w":
            hw = tags.get("highway")
            if hw in ROAD_CLASS:
                n0 = len(r_ids)
                for n in o.nodes:
                    if n.location.valid():
                        r_ids.append(n.ref)
                        r_lon.append(n.lon)
                        r_lat.append(n.lat)
                if len(r_ids) - n0 < 2:
                    del r_ids[n0:]
                    del r_lon[n0:]
                    del r_lat[n0:]
                    continue
                r_off.append(len(r_ids))
                c = ROAD_CLASS[hw]
                r_cls.append(c)
                width = parse_len(tags.get("width"))
                lanes = parse_len(tags.get("lanes"))
                if width is None:
                    width = lanes * 3.6 if lanes else ROAD_WIDTH[c]
                r_width.append(min(max(width, 4.0), 30.0))
                r_bridge.append(1 if tags.get("bridge", "no") not in ("no", "") else 0)
                r_ref.append(tags.get("ref", ""))
                continue
            if tags.get("natural") == "coastline":
                pts = way_coords(o)
                if len(pts) >= 2:
                    coast.append(pts)
                continue
            ww = tags.get("waterway")
            if ww in ("river", "canal"):
                pts = way_coords(o)
                if len(pts) >= 2:
                    width = parse_len(tags.get("width")) or (30.0 if ww == "river" else 15.0)
                    rivers.append([min(width, 120.0), pts])
                continue
            if tags.get("railway") == "rail" and "service" not in tags:
                pts = way_coords(o)
                if len(pts) >= 2:
                    rail.append(pts)
                continue
            if tags.get("aeroway") == "runway":
                pts = way_coords(o)
                if len(pts) >= 2:
                    runways.append({"pts": pts, "width": parse_len(tags.get("width")),
                                    "surface": tags.get("surface", ""), "ref": tags.get("ref", "")})
                continue
            continue
        if t == "a":
            if "building" in tags:
                bv = tags.get("building")
                if bv in BUILDING_SKIP:
                    continue
                rings = list(o.outer_rings())
                if not rings:
                    continue
                ring = rings[0]
                n = len(ring) - 1
                if n < 3:
                    continue
                ok = True
                for i in range(n):
                    nd = ring[i]
                    if not nd.location.valid():
                        ok = False
                        break
                    b_lon.append(nd.lon)
                    b_lat.append(nd.lat)
                if not ok:
                    del b_lon[b_off[-1]:]
                    del b_lat[b_off[-1]:]
                    continue
                b_off.append(len(b_lon))
                kind = BUILDING_KIND.get(bv, 0)
                if tags.get("amenity") in ("school", "hospital", "place_of_worship", "university"):
                    kind = 6
                h = parse_len(tags.get("height"))
                if h is None:
                    lv = parse_len(tags.get("building:levels"))
                    if lv:
                        h = lv * 3.3 + 1.0
                if h is None:
                    h = DEFAULT_HEIGHT[kind]
                b_h.append(min(max(h, 2.5), 400.0))
                b_kind.append(kind)
                continue
            if (tags.get("boundary") == "administrative" and tags.get("admin_level") == "4"
                    and tags.get("name") == "Texas"):
                for outer in o.outer_rings():
                    texas.append([[(n.lon, n.lat) for n in outer],
                                  [[(n.lon, n.lat) for n in inner] for inner in o.inner_rings(outer)]])
                log("  found the Texas border (%d rings)" % len(texas))
                continue
            if tags.get("aeroway") == "aerodrome":
                pts = [(n.lon, n.lat) for r in o.outer_rings() for n in r]
                if pts:
                    lat = sum(p[1] for p in pts) / len(pts)
                    lon = sum(p[0] for p in pts) / len(pts)
                    aerodromes.append(_aerodrome(tags, lat, lon))
                continue
            nat = tags.get("natural")
            wt = tags.get("water", "")
            lu = tags.get("landuse")
            if nat == "water" or lu in ("reservoir", "basin") or tags.get("waterway") == "riverbank":
                if wt in ("wastewater", "reflecting_pool", "fountain") or lu == "basin" and nat != "water":
                    continue
                kind = "river" if (wt in ("river", "canal", "stream") or tags.get("waterway") == "riverbank") else (wt or "lake")
                for outer in o.outer_rings():
                    ring = [(n.lon, n.lat) for n in outer]
                    if _approx_area(ring) < MIN_WATER_AREA:
                        continue
                    inners = [[(n.lon, n.lat) for n in inner] for inner in o.inner_rings(outer)]
                    water.append([kind, kind in FLAT_WATER and kind != "river", ring, inners])
                continue
    log("read %d objects in %.0f s: %d buildings, %d road ways, %d water areas, %d rivers, "
        "%d coastline ways, %d railways, %d aerodromes, %d runways, %d places" % (
            counts["objects"], time.time() - t0, len(b_h), len(r_cls), len(water), len(rivers),
            len(coast), len(rail), len(aerodromes), len(runways), len(places)))
    np.savez(os.path.join(work, "buildings.npz"), lon=np.frombuffer(b_lon, np.float64),
             lat=np.frombuffer(b_lat, np.float64), off=np.frombuffer(b_off, np.int64),
             h=np.frombuffer(b_h, np.float32), kind=np.frombuffer(b_kind, np.int8))
    np.savez(os.path.join(work, "roads.npz"), lon=np.frombuffer(r_lon, np.float64),
             lat=np.frombuffer(r_lat, np.float64), ids=np.frombuffer(r_ids, np.int64),
             off=np.frombuffer(r_off, np.int64), cls=np.frombuffer(r_cls, np.int8),
             width=np.frombuffer(r_width, np.float32), bridge=np.frombuffer(r_bridge, np.int8))
    with open(os.path.join(work, "features.pkl"), "wb") as f:
        pickle.dump({"water": water, "rivers": rivers, "coast": coast, "rail": rail,
                     "aerodromes": aerodromes, "runways": runways, "places": places,
                     "texas": texas, "road_ref": r_ref}, f, protocol=4)
    idx = os.path.join(work, "nodes.idx")
    if os.path.exists(idx):
        os.remove(idx)


def _aerodrome(tags, lat, lon):
    name = tags.get("name", "") or tags.get("icao", "") or "Airfield"
    low = (" " + name.lower() + " ")
    military = ("military" in tags or tags.get("landuse") == "military"
                or tags.get("aerodrome:type") == "military" or tags.get("aerodrome") == "military"
                or any(w in low for w in MILITARY_WORDS))
    return {"name": name, "icao": tags.get("icao", ""), "iata": tags.get("iata", ""),
            "military": bool(military), "lat": lat, "lon": lon}


def _approx_area(ring):
    """Real square metres of a (lon, lat) ring, roughly"""
    if len(ring) < 3:
        return 0.0
    lat0 = ring[0][1]
    kx = 111320.0 * math.cos(math.radians(lat0))
    ky = 110950.0
    s = 0.0
    for i in range(len(ring) - 1):
        x0 = ring[i][0] * kx
        y0 = ring[i][1] * ky
        x1 = ring[i + 1][0] * kx
        y1 = ring[i + 1][1] * ky
        s += x0 * y1 - x1 * y0
    return abs(s) * 0.5


# =============================================================================================
# Stage 2: bake the game data
# =============================================================================================

def load_elevation(path):
    """ETOPO 2022 from ERDDAP: (lat ascending, lon ascending, z[lat, lon]) in metres"""
    if not path or not os.path.exists(path):
        return None
    try:
        from scipy.io import netcdf_file
        f = netcdf_file(path, "r", mmap=False)
        lat = np.array(f.variables["latitude"][:], np.float64)
        lon = np.array(f.variables["longitude"][:], np.float64)
        z = np.array(f.variables["z"][:], np.float32)
        f.close()
    except Exception as e:  # NetCDF-4 files are HDF5 inside
        log("  (reading as NetCDF-4: %s)" % e)
        import h5py
        with h5py.File(path, "r") as f:
            lat = np.array(f["latitude"][:], np.float64)
            lon = np.array(f["longitude"][:], np.float64)
            z = np.array(f["z"][:], np.float32)
    if lat[0] > lat[-1]:
        lat = lat[::-1]
        z = z[::-1, :]
    log("elevation: %d x %d samples, %.2f..%.2f N, %.2f..%.2f E, %.0f..%.0f m" % (
        z.shape[1], z.shape[0], lat[0], lat[-1], lon[0], lon[-1], z.min(), z.max()))
    return lat, lon, z


def sample_grid(elev, xs, zs):
    """Bilinear elevation on the grid of game x (columns) and z (rows)"""
    lat_e, lon_e, z_e = elev
    lats, _ = to_latlon(0.0, zs)
    _, lons = to_latlon(xs, 0.0)
    fx = np.clip((lons - lon_e[0]) / (lon_e[1] - lon_e[0]), 0, len(lon_e) - 1.001)
    fy = np.clip((lats - lat_e[0]) / (lat_e[1] - lat_e[0]), 0, len(lat_e) - 1.001)
    i0 = fx.astype(np.int64)
    tx = (fx - i0).astype(np.float32)
    j0 = fy.astype(np.int64)
    ty = (fy - j0).astype(np.float32)
    rows = np.unique(np.concatenate([j0, j0 + 1]))
    sub = z_e[rows]
    e1 = sub[:, i0] * (1 - tx) + sub[:, i0 + 1] * tx            # [rows, nx]
    pos = {r: k for k, r in enumerate(rows)}
    a = np.array([pos[j] for j in j0])
    b = np.array([pos[j + 1] for j in j0])
    return e1[a] * (1 - ty)[:, None] + e1[b] * ty[:, None]


def fallback_elevation(xs, zs):
    """No elevation file: a gentle rise from the coast to the west, like the stand-in"""
    lats, _ = to_latlon(0.0, zs)
    _, lons = to_latlon(xs, 0.0)
    e = np.clip((-94.0 - lons[None, :]) * 120.0 + (lats[:, None] - 28.0) * 40.0, 2.0, 1500.0)
    return e.astype(np.float32)


def project_ring(ring):
    a = np.asarray(ring, np.float64)
    x, z = to_xz(a[:, 1], a[:, 0])
    return np.stack([x, z], 1)


def bake(work, out, elev_path):
    from PIL import Image, ImageDraw
    from scipy import ndimage
    import shapely
    from shapely.geometry import Polygon, LineString, box
    import mapbox_earcut as earcut

    t_all = time.time()
    os.makedirs(os.path.join(out, "regions"), exist_ok=True)
    with open(os.path.join(work, "features.pkl"), "rb") as f:
        feat = pickle.load(f)
    rng = np.random.default_rng(1836)

    # --- The state border -----------------------------------------------------------------
    texas_polys = []
    for outer, inners in feat["texas"]:
        try:
            p = Polygon(project_ring(outer), [project_ring(i) for i in inners if len(i) >= 4])
            texas_polys.append(shapely.make_valid(p))
        except Exception:
            pass
    if texas_polys:
        texas = shapely.unary_union(texas_polys)
        log("state border from OpenStreetMap: %.0f km² of game area" % (texas.area / 1e6))
    else:
        from_geo = _fallback_outline()
        texas = Polygon(project_ring([(p[1], p[0]) for p in from_geo]))
        log("no Texas border in the data: using the built-in outline")
    texas_land = texas

    # --- Heights on the global 64 m grid ----------------------------------------------------
    xs = HX0 + np.arange(HNX) * HSTEP
    zs = HZ0 + np.arange(HNZ) * HSTEP
    elev = load_elevation(elev_path)
    if elev is None:
        log("no elevation file: using a stand-in slope")
        H = fallback_elevation(xs, zs)
    else:
        H = sample_grid(elev, xs, zs)
    log("height grid %d x %d (%.0f MB)" % (HNX, HNZ, H.nbytes / 1e6))

    def px(x, z):
        return (x - HX0) / HSTEP, (z - HZ0) / HSTEP

    # In Texas (with a 1 km fringe so the beaches count)
    img = Image.new("L", (HNX, HNZ), 0)
    dr = ImageDraw.Draw(img)
    for g in getattr(texas.buffer(1000.0), "geoms", [texas.buffer(1000.0)]):
        dr.polygon([px(x, z) for x, z in g.exterior.coords], fill=1)
    in_texas = np.array(img, dtype=bool)
    del img

    # --- The sea: flood from the open Gulf, walled in by the OSM coastline ------------------
    sea = H < 0.0
    if feat["coast"]:
        sea = _coast_flood(feat["coast"], elev, H, texas.buffer(1000.0), sea)
    H = np.where(sea, np.minimum(H, -2.0), np.maximum(H, 0.6)).astype(np.float32)

    # --- Lakes: flat water at one level, the ground under them carved down -----------------
    lakes = []          # [Polygon, level (real m) or None for river water, kind]
    for kind, flat, ring, inners in feat["water"]:
        try:
            p = Polygon(project_ring(ring), [project_ring(i) for i in inners if len(i) >= 4])
            if not p.is_valid:
                p = shapely.make_valid(p)
            if p.is_empty or p.area * 9.0 < MIN_WATER_AREA:
                continue
            p = p.simplify(2.0)
        except Exception:
            continue
        level = None
        if flat:
            c = np.asarray(_outer_coords(p))
            hx, hz = px(c[:, 0], c[:, 1])
            vals = ndimage.map_coordinates(H, [hz, hx], order=1, mode="nearest")
            level = float(np.percentile(vals, 20))
            if level <= 0.5:
                # at sea level: a lagoon or bay drawn as water (the Laguna Madre): it's sea
                m = _carve(H, p, -2.0, px)
                if m is not None:
                    sea[m[0]:m[1], m[2]:m[3]] |= m[4]
                continue
            _carve(H, p, level - 2.0, px)
        lakes.append([p, level, kind])
    log("water areas: %d (%d flat lakes)" % (len(lakes), sum(1 for l in lakes if l[1] is not None)))

    rivers = []
    for width, pts in feat["rivers"]:
        a = project_ring(pts)
        if len(a) >= 2:
            rivers.append([width, LineString(a).simplify(3.0)])
    rail = [LineString(project_ring(p)).simplify(3.0) for p in feat["rail"] if len(p) >= 2]

    # --- Roads ------------------------------------------------------------------------------
    rd = np.load(os.path.join(work, "roads.npz"))
    rx_, rz_ = to_xz(rd["lat"], rd["lon"])
    r_off = rd["off"]
    r_cls = rd["cls"]
    r_width = rd["width"]
    r_bridge = rd["bridge"]
    road_lines = []
    for i in range(len(r_cls)):
        a, b = r_off[i], r_off[i + 1]
        road_lines.append(LineString(np.stack([rx_[a:b], rz_[a:b]], 1)).simplify(1.5))
    road_keep = _thin_roads(road_lines, r_cls)
    log("roads: %d ways, %d kept after thinning the side streets for 1:3" % (len(road_lines), int(road_keep.sum())))

    # --- Airfields and runways --------------------------------------------------------------
    airfields, runway_list = _airfields(feat["aerodromes"], feat["runways"])
    log("airfields with a usable runway: %d (%d military)" % (
        len(airfields), sum(1 for a in airfields if a["military"])))

    # --- Buildings: real size, centred on their scaled positions ----------------------------
    bd = np.load(os.path.join(work, "buildings.npz"))
    cx, cz, bw, bdp, ang = _building_boxes(bd["lon"], bd["lat"], bd["off"])
    del bd
    bd = np.load(os.path.join(work, "buildings.npz"))
    bh = bd["h"]
    bkind = bd["kind"]
    keep_area = bw * bdp >= MIN_BUILDING_AREA
    log("buildings: %d in the data, %d big enough to keep" % (len(cx), int(keep_area.sum())))
    score = bh * np.sqrt(bw * bdp) * rng.uniform(0.7, 1.3, len(cx)).astype(np.float32)
    score[~keep_area] = -1.0

    # Which region each building is in
    b_rx = np.floor(cx / REGION).astype(np.int64)
    b_rz = np.floor(cz / REGION).astype(np.int64)

    # Spatial index of the line features by region
    def by_region(geoms, pad):
        out = {}
        for i, g in enumerate(geoms):
            if g.is_empty:
                continue
            x0, z0, x1, z1 = g.bounds
            for ry in range(math.floor((z0 - pad) / REGION), math.floor((z1 + pad) / REGION) + 1):
                for rxx in range(math.floor((x0 - pad) / REGION), math.floor((x1 + pad) / REGION) + 1):
                    out.setdefault((rxx, ry), []).append(i)
        return out

    roads_in = by_region([g if road_keep[i] else LineString() for i, g in enumerate(road_lines)], 40.0)
    for k in list(roads_in):
        roads_in[k] = [i for i in roads_in[k] if road_keep[i]]
    lakes_in = by_region([l[0] for l in lakes], 40.0)
    rivers_in = by_region([r[1] for r in rivers], 80.0)
    rail_in = by_region(rail, 20.0)
    runways_in = {}
    for i, r in enumerate(runway_list):
        runways_in.setdefault((math.floor(r["x"] / REGION), math.floor(r["z"] / REGION)), []).append(i)

    # --- Each region ------------------------------------------------------------------------
    order = np.argsort(-score, kind="stable")
    region_of = (b_rz[order] - RZ0) * NRX + (b_rx[order] - RX0)
    ok = (b_rx[order] >= RX0) & (b_rx[order] <= RX1) & (b_rz[order] >= RZ0) & (b_rz[order] <= RZ1) & (score[order] > 0)
    order = order[ok]
    region_of = region_of[ok]
    # buildings by region, each list still sorted by score
    sort2 = np.argsort(region_of, kind="stable")
    order = order[sort2]
    region_of = region_of[sort2]
    starts = np.searchsorted(region_of, np.arange(NRX * NRZ + 1))

    kept_total = 0
    urban = np.zeros((HNZ, HNX), np.float32)
    flags_all = np.zeros((HNZ, HNX), np.uint8)
    flags_all |= in_texas.astype(np.uint8)
    flags_all |= (sea.astype(np.uint8) << 1)
    tiles_with_data = 0
    region_tiles = {}
    t_reg = time.time()
    for rz in range(RZ0, RZ1 + 1):
        for rx in range(RX0, RX1 + 1):
            ri = (rz - RZ0) * NRX + (rx - RX0)
            bsel = order[starts[ri]:starts[ri + 1]]
            ox = rx * REGION
            oz = rz * REGION
            key = (rx, rz)
            tiles = {}
            if (len(bsel) or key in roads_in or key in lakes_in or key in rivers_in
                    or key in rail_in or key in runways_in):
                tiles, kept = _bake_region(
                    key, ox, oz, bsel, cx, cz, bw, bdp, ang, bh, bkind, sea, px,
                    [road_lines[i] for i in roads_in.get(key, [])],
                    [(r_cls[i], r_width[i], r_bridge[i]) for i in roads_in.get(key, [])],
                    [lakes[i] for i in lakes_in.get(key, [])],
                    [rivers[i] for i in rivers_in.get(key, [])],
                    [rail[i] for i in rail_in.get(key, [])],
                    [runway_list[i] for i in runways_in.get(key, [])],
                    earcut, box)
                kept_total += len(kept)
                if len(kept):
                    kx, kz = px(cx[kept], cz[kept])
                    np.add.at(urban, (np.clip(kz.astype(np.int64), 0, HNZ - 1),
                                      np.clip(kx.astype(np.int64), 0, HNX - 1)), bw[kept] * bdp[kept])
            region_tiles[key] = tiles
            tiles_with_data += len(tiles)
        log("  regions row %d/%d done, %d buildings kept so far (%.0f s)" % (
            rz - RZ0 + 1, NRZ, kept_total, time.time() - t_reg))
    # Built-up ground: where kept buildings cover enough of the land around
    urban = ndimage.uniform_filter(urban, size=5) / (HSTEP * HSTEP)
    flags_all |= ((urban > 0.04).astype(np.uint8) << 2)
    log("buildings kept: %d of %d (%.0f%%)" % (kept_total, int(keep_area.sum()),
                                               100.0 * kept_total / max(1, int(keep_area.sum()))))

    # --- Write the regions ------------------------------------------------------------------
    region_list = []
    total_bytes = 0
    for rz in range(RZ0, RZ1 + 1):
        for rx in range(RX0, RX1 + 1):
            j0 = (rz - RZ0) * (HN - 1)
            i0 = (rx - RX0) * (HN - 1)
            hreg = H[j0:j0 + HN, i0:i0 + HN]
            freg = flags_all[j0:j0 + HN, i0:i0 + HN]
            q = np.clip(np.round(hreg * 4.0), -32767, 32767).astype("<i2")
            blob = _region_file(rx, rz, q, freg, region_tiles[(rx, rz)])
            path = os.path.join(out, "regions", "r_%d_%d.bin" % (rx, rz))
            with open(path, "wb") as f:
                f.write(blob)
            total_bytes += len(blob)
            region_list.append([rx, rz, len(region_tiles[(rx, rz)])])
    log("wrote %d regions, %.1f MB, %d tiles with map data" % (len(region_list), total_bytes / 1e6, tiles_with_data))

    # --- The road network for units ---------------------------------------------------------
    net = _road_graph(rd, rx_, rz_, road_keep)
    with open(os.path.join(out, "roads.bin"), "wb") as f:
        f.write(net["blob"])
    log("road network: %d junctions, %d stretches, %d points, %.0f km (largest connected part)" % (
        net["junctions"], net["chains"], net["points"], net["km"]))

    # --- Cities -----------------------------------------------------------------------------
    cities = _cities(feat["places"], H, px, texas_land)
    log("cities and towns: %d" % len(cities))

    # --- The strategic map ------------------------------------------------------------------
    _draw_map(os.path.join(out, "map.png"), H, sea, flags_all, lakes, road_lines, r_cls, rail,
              texas, airfields)

    outline = texas_land
    if hasattr(outline, "geoms"):
        outline = max(outline.geoms, key=lambda g: g.area)
    outline = outline.simplify(300.0)
    meta = {
        "version": VERSION,
        "built": time.strftime("%Y-%m-%d %H:%M"),
        "projection": {"scale": SCALE, "lat0": LAT0, "lon0": LON0, "m_per_deg_lat": MLAT,
                       "m_per_deg_lon": MLON},
        "tile": TILE, "region": REGION, "height_step": HSTEP, "height_samples": HN,
        "regions": {"x0": RX0, "x1": RX1, "z0": RZ0, "z1": RZ1},
        "map_bounds": [GX0, GZ0, GX1 - GX0, GZ1 - GZ0],
        "outline": [[round(x, 1), round(z, 1)] for x, z in list(outline.exterior.coords)[:-1]],
        "cities": cities,
        "airfields": airfields,
        "ports": [[n, round(to_xz(la, lo)[0], 1), round(to_xz(la, lo)[1], 1)] for n, la, lo in PORTS],
        "counts": {"buildings_kept": int(kept_total), "buildings_in_data": int(len(cx)),
                   "road_ways": len(road_lines), "water_areas": len(lakes), "rivers": len(rivers),
                   "railways": len(rail), "tiles_with_data": tiles_with_data},
        "credit": "Map data © OpenStreetMap contributors (ODbL). Elevation: NOAA ETOPO 2022.",
    }
    with open(os.path.join(out, "meta.json"), "w") as f:
        json.dump(meta, f, indent=1)
    log("done in %.0f s" % (time.time() - t_all))


def _thin_roads(lines, cls):
    """At 1:3 a city's streets would be three times as close together, at full width: the city
    would be all road. Keep the main roads, and a side street only where it's not running right
    alongside a road already kept (about 80 m apart in game, every second or third street)."""
    n = len(lines)
    keep = np.ones(n, bool)
    cell = 40.0
    occ = set()
    main = {0, 1, 2, 5, 6, 7}
    order = sorted(range(n), key=lambda i: (0 if int(cls[i]) in main else int(cls[i]), -lines[i].length))
    for i in order:
        g = lines[i]
        L = g.length
        if L <= 0:
            keep[i] = False
            continue
        k = max(2, int(L / 15.0))
        pts = [g.interpolate(t * L / (k - 1)) for t in range(k)]
        cells = {(math.floor(p.x / cell), math.floor(p.y / cell)) for p in pts}
        if int(cls[i]) not in main:
            hit = sum(1 for c in cells if c in occ)
            if hit > 0.5 * len(cells):
                keep[i] = False
                continue
        for cx_, cz_ in cells:
            for dz in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    occ.add((cx_ + dx, cz_ + dz))
    return keep


def _outer_coords(p):
    if hasattr(p, "geoms"):
        return [c for g in p.geoms if hasattr(g, "exterior") for c in g.exterior.coords]
    return list(p.exterior.coords)


def _carve(H, poly, level, px):
    from PIL import Image, ImageDraw
    x0, z0, x1, z1 = poly.bounds
    i0 = max(int(math.floor((x0 - HX0) / HSTEP)) - 1, 0)
    j0 = max(int(math.floor((z0 - HZ0) / HSTEP)) - 1, 0)
    i1 = min(int(math.ceil((x1 - HX0) / HSTEP)) + 2, HNX)
    j1 = min(int(math.ceil((z1 - HZ0) / HSTEP)) + 2, HNZ)
    if i1 <= i0 or j1 <= j0:
        return None
    img = Image.new("L", (i1 - i0, j1 - j0), 0)
    dr = ImageDraw.Draw(img)
    for g in getattr(poly, "geoms", [poly]):
        if not hasattr(g, "exterior"):
            continue
        dr.polygon([((x - HX0) / HSTEP - i0, (z - HZ0) / HSTEP - j0) for x, z in g.exterior.coords], fill=1)
        for hole in g.interiors:
            dr.polygon([((x - HX0) / HSTEP - i0, (z - HZ0) / HSTEP - j0) for x, z in hole.coords], fill=0)
    m = np.array(img, dtype=bool)
    win = H[j0:j1, i0:i1]
    win[m] = np.minimum(win[m], level)
    return j0, j1, i0, i1, m


def _coast_flood(coast, elev, H, texas_buf, sea_default):
    """The sea along the Gulf coast, at 16 m: flood from the deep Gulf over everything that's not
    behind the OSM coastline. Narrow passes (Port Aransas, Bolivar Roads) stay open at this size."""
    from PIL import Image, ImageDraw
    from scipy import ndimage
    from shapely.geometry import box as sbox
    step = 16.0
    bx0, bz0 = to_xz(30.25, -97.95)
    bx1, bz1 = to_xz(25.75, -93.45)
    bx0 = HX0 + math.floor((bx0 - HX0) / HSTEP) * HSTEP
    bz0 = HZ0 + math.floor((bz0 - HZ0) / HSTEP) * HSTEP
    nx = int((bx1 - bx0) / step) // 4 * 4
    nz = int((bz1 - bz0) / step) // 4 * 4
    log("coast: flooding the Gulf on a %d x %d grid (16 m)" % (nx, nz))
    xs = bx0 + (np.arange(nx) + 0.5) * step
    zs = bz0 + (np.arange(nz) + 0.5) * step
    if elev is not None:
        E = sample_grid(elev, xs, zs)
    else:
        E = fallback_elevation(xs, zs)
    tex = Image.new("L", (nx, nz), 0)
    dr = ImageDraw.Draw(tex)
    clip = texas_buf.intersection(sbox(bx0, bz0, bx0 + nx * step, bz0 + nz * step))
    for g in getattr(clip, "geoms", [clip]):
        if hasattr(g, "exterior"):
            dr.polygon([((x - bx0) / step, (z - bz0) / step) for x, z in g.exterior.coords], fill=1)
    tex = np.array(tex, dtype=bool)
    # The coastline as land shapes: OSM draws it with the land on the left, so closed rings
    # going anticlockwise (on the map, north up) are islands and the one open chain is the
    # mainland coast, closed off well inland
    import shapely
    from shapely.geometry import LineString, Polygon
    from shapely.ops import linemerge
    lines = [LineString(project_ring(p)) for p in coast if len(p) >= 2]
    merged = linemerge(lines)
    parts = list(getattr(merged, "geoms", [merged]))
    land_img = Image.new("L", (nx, nz), 0)
    dr = ImageDraw.Draw(land_img)

    def pix(coords):
        return [((x - bx0) / step, (z - bz0) / step) for x, z in coords]

    rings = []
    mainland = None
    for g in parts:
        c = list(g.coords)
        if g.is_ring or (len(c) > 3 and c[0] == c[-1]):
            poly = Polygon(c)
            # game z points south, so the map's anticlockwise is clockwise here
            land = not shapely.is_ccw(poly.exterior)
            rings.append((abs(poly.area), land, c))
        elif mainland is None or g.length > mainland.length:
            mainland = g
    if mainland is not None:
        c = list(mainland.coords)
        a_ll = to_latlon(*c[0])
        b_ll = to_latlon(*c[-1])
        # close it through points far inland (north of the coast), whichever end is which
        inland = [to_xz(33.0, -93.3), to_xz(33.0, -100.5), to_xz(25.6, -100.5)]
        if a_ll[1] < b_ll[1]:        # the chain runs west to east: close east, north, west
            inland = inland
        else:
            inland = inland[::-1]
        dr.polygon(pix(c + inland), fill=1)
    for area, land, c in sorted(rings, key=lambda r: -r[0]):
        dr.polygon(pix(c), fill=1 if land else 0)
    land = np.array(land_img, dtype=bool)
    # beyond the ends of the OSM coastline (Louisiana, Mexico) the elevation data decides
    flood = ~land & (tex | (E < 0.0))
    log("coast: mainland coast %.0f km, %d islands, %d enclosed waters" % (
        (mainland.length if mainland is not None else 0) * SCALE / 1000.0,
        sum(1 for r in rings if r[1]), sum(1 for r in rings if not r[1])))
    # Down to the 64 m grid: sea where most of the 4 x 4 block is sea
    s64 = flood.reshape(nz // 4, 4, nx // 4, 4).mean(axis=(1, 3)) >= 0.5
    i0 = int(round((bx0 - HX0) / HSTEP))
    j0 = int(round((bz0 - HZ0) / HSTEP))
    sea = sea_default.copy()
    sub = sea[j0:j0 + s64.shape[0], i0:i0 + s64.shape[1]]
    sea[j0:j0 + s64.shape[0], i0:i0 + s64.shape[1]] = s64[:sub.shape[0], :sub.shape[1]]
    log("coast: %.0f km² of sea in the coastal box" % (s64.sum() * HSTEP * HSTEP / 1e6))
    return sea


def _building_boxes(lon, lat, off, chunk=400000):
    """Each footprint as an oriented box, a chunk of buildings at a time to keep memory down"""
    parts = [[], [], [], [], []]
    nb = len(off) - 1
    for s in range(0, nb, chunk):
        e = min(s + chunk, nb)
        a, b = int(off[s]), int(off[e])
        r = _building_boxes_chunk(lon[a:b], lat[a:b], off[s:e + 1] - a)
        for k in range(5):
            parts[k].append(r[k])
    return tuple(np.concatenate(p) if p else np.zeros(0, np.float32) for p in parts)


def _building_boxes_chunk(lon, lat, off):
    """Each footprint as an oriented box: centre (game m), width and depth (real m), angle"""
    x, z = to_xz(lat, lon)
    xr = x * SCALE                      # real metres for the footprint shape
    zr = z * SCALE
    n = np.diff(off)
    idx = np.repeat(np.arange(len(n)), n)
    cnt = n.astype(np.float64)
    mx = np.bincount(idx, xr, len(n)) / cnt
    mz = np.bincount(idx, zr, len(n)) / cnt
    dx = xr - mx[idx]
    dz = zr - mz[idx]
    cxx = np.bincount(idx, dx * dx, len(n))
    czz = np.bincount(idx, dz * dz, len(n))
    cxz = np.bincount(idx, dx * dz, len(n))
    ang = 0.5 * np.arctan2(2.0 * cxz, cxx - czz)
    ca = np.cos(ang)[idx]
    sa = np.sin(ang)[idx]
    u = dx * ca + dz * sa
    v = -dx * sa + dz * ca
    starts = off[:-1]
    umax = np.maximum.reduceat(u, starts)
    umin = np.minimum.reduceat(u, starts)
    vmax = np.maximum.reduceat(v, starts)
    vmin = np.minimum.reduceat(v, starts)
    w = (umax - umin).astype(np.float32)
    d = (vmax - vmin).astype(np.float32)
    # the box centre, not the vertex mean
    uc = (umax + umin) * 0.5
    vc = (vmax + vmin) * 0.5
    ccx = (mx + uc * np.cos(ang) - vc * np.sin(ang)) / SCALE
    ccz = (mz + uc * np.sin(ang) + vc * np.cos(ang)) / SCALE
    del u, v, dx, dz, ca, sa
    # a footprint's area is less than its box (L shapes): shrink the box to match it
    nxt = np.arange(len(xr)) + 1
    nxt[off[1:] - 1] = off[:-1]
    area = np.abs(np.bincount(idx, xr * zr[nxt] - xr[nxt] * zr, len(n))) * 0.5
    boxa = np.maximum(w * d, 1e-3)
    k = np.sqrt(np.clip(area / boxa, 0.55, 1.0)).astype(np.float32)
    return ccx, ccz, w * k, d * k, ang.astype(np.float32)


def _airfields(aerodromes, runways):
    """Airfields with a runway long enough for fixed-wing aircraft, with their runways"""
    out = []
    rws = []
    if not aerodromes:
        return out, rws
    # the same airport mapped as a point and as an area: keep one
    uniq = []
    for a in aerodromes:
        dup = False
        for u in uniq:
            if u["name"] == a["name"] and abs(u["lat"] - a["lat"]) < 0.05 and abs(u["lon"] - a["lon"]) < 0.05:
                u["military"] = u["military"] or a["military"]
                u["icao"] = u["icao"] or a["icao"]
                dup = True
                break
        if not dup:
            uniq.append(a)
    aerodromes = uniq
    ax = np.array([to_xz(a["lat"], a["lon"])[0] for a in aerodromes])
    az = np.array([to_xz(a["lat"], a["lon"])[1] for a in aerodromes])
    best = {}
    for r in runways:
        a = project_ring(r["pts"]) * SCALE        # real metres
        if len(a) > 2 and np.allclose(a[0], a[-1]):
            # mapped as an area: its long axis
            c = a[:-1].mean(0)
            d = a[:-1] - c
            cov = d.T @ d
            w, v = np.linalg.eigh(cov)
            ax_ = v[:, 1]
            proj = d @ ax_
            p0 = c + ax_ * proj.min()
            p1 = c + ax_ * proj.max()
            perp = d @ np.array([-ax_[1], ax_[0]])
            width = float(perp.max() - perp.min())
        else:
            p0 = a[0]
            p1 = a[-1]
            width = r["width"] or 45.0
        length = float(np.linalg.norm(p1 - p0))
        if length < 600.0:
            continue
        surf = r["surface"].lower()
        paved = surf in ("", "asphalt", "concrete", "paved", "concrete:plates", "concrete:lanes")
        if not paved and length < 1500.0:
            continue
        c = (p0 + p1) * 0.5 / SCALE
        d2 = (ax - c[0]) ** 2 + (az - c[1]) ** 2
        k = int(np.argmin(d2))
        if d2[k] > (4000.0 / SCALE) ** 2:
            continue
        angle = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
        rws.append({"x": float(c[0]), "z": float(c[1]), "length": length,
                    "width": float(min(max(width, 18.0), 90.0)), "angle": angle,
                    "paved": paved, "airfield": k, "ref": r["ref"]})
        best[k] = max(best.get(k, 0.0), length)
    index = {}
    for k, longest in sorted(best.items(), key=lambda kv: -kv[1]):
        a = aerodromes[k]
        if longest < 900.0 and not a["military"]:
            continue
        index[k] = len(out)
        x, z = to_xz(a["lat"], a["lon"])
        out.append({"name": a["name"], "icao": a["icao"], "iata": a["iata"],
                    "military": a["military"], "x": round(float(x), 1), "z": round(float(z), 1),
                    "longest_runway": round(longest), "jets": longest >= 2400.0,
                    "runways": 0})
    keep = []
    for r in rws:
        if r["airfield"] in index:
            r["airfield"] = index[r["airfield"]]
            out[r["airfield"]]["runways"] += 1
            keep.append(r)
    return out, keep


def _bake_region(key, ox, oz, bsel, cx, cz, bw, bdp, ang, bh, bkind, sea, px,
                 roads, road_info, lakes, rivers, rail, runways, earcut, box):
    """Thin the buildings into the region, then cut everything into its 2 km tiles"""
    from PIL import Image, ImageDraw
    import shapely
    nocc = int(REGION / OCC)
    occ_img = Image.new("L", (nocc, nocc), 0)
    dr = ImageDraw.Draw(occ_img)

    def to_occ(c):
        return [((x - ox) / OCC, (z - oz) / OCC) for x, z in c]

    for g, (cls, width, bridge) in zip(roads, road_info):
        for part in getattr(g, "geoms", [g]):
            dr.line(to_occ(part.coords), fill=1, width=max(1, int(math.ceil((width + 6.0) / OCC))))
    for p, level, kind in lakes:
        for g in getattr(p, "geoms", [p]):
            if hasattr(g, "exterior"):
                dr.polygon(to_occ(g.exterior.coords), fill=1)
    for width, g in rivers:
        for part in getattr(g, "geoms", [g]):
            dr.line(to_occ(part.coords), fill=1, width=max(1, int(math.ceil((width + 6.0) / OCC))))
    for g in rail:
        for part in getattr(g, "geoms", [g]):
            dr.line(to_occ(part.coords), fill=1, width=max(1, int(math.ceil(12.0 / OCC))))
    for r in runways:
        # the runway and its strip: 150 m each side, 300 m off each end, kept clear
        ca, sa = math.cos(r["angle"]), math.sin(r["angle"])
        hl = r["length"] * 0.5 + 300.0
        hw = r["width"] * 0.5 + 150.0
        pts = [(r["x"] + ca * u - sa * v, r["z"] + sa * u + ca * v)
               for u, v in ((-hl, -hw), (hl, -hw), (hl, hw), (-hl, hw))]
        dr.polygon(to_occ(pts), fill=1)
    occ = np.array(occ_img, dtype=bool)
    del occ_img

    # Buildings, best first, wherever there's still room (3 m between buildings)
    kept = []
    if len(bsel):
        c = np.cos(ang[bsel])
        s = np.sin(ang[bsel])
        ex = np.abs(bw[bsel] * 0.5 * c) + np.abs(bdp[bsel] * 0.5 * s) + 1.5
        ez = np.abs(bw[bsel] * 0.5 * s) + np.abs(bdp[bsel] * 0.5 * c) + 1.5
        i0 = np.floor((cx[bsel] - ex - ox) / OCC).astype(np.int64)
        i1 = np.ceil((cx[bsel] + ex - ox) / OCC).astype(np.int64)
        j0 = np.floor((cz[bsel] - ez - oz) / OCC).astype(np.int64)
        j1 = np.ceil((cz[bsel] + ez - oz) / OCC).astype(np.int64)
        hx, hz = px(cx[bsel], cz[bsel])
        on_sea = sea[np.clip(np.round(hz).astype(np.int64), 0, HNZ - 1),
                     np.clip(np.round(hx).astype(np.int64), 0, HNX - 1)]
        i0l = i0.tolist(); i1l = i1.tolist(); j0l = j0.tolist(); j1l = j1.tolist()
        seal = on_sea.tolist()
        for k in range(len(bsel)):
            a, b, cc, d = i0l[k], i1l[k], j0l[k], j1l[k]
            if a < 0 or cc < 0 or b > nocc or d > nocc or seal[k]:
                continue
            win = occ[cc:d, a:b]
            if win.any():
                continue
            win[:] = True
            kept.append(bsel[k])
    kept = np.array(kept, dtype=np.int64)

    # Into tiles
    tiles = {}

    def tile(ti, tj):
        k = (ti, tj)
        if k not in tiles:
            tiles[k] = {1: [], 2: [], 3: [], 4: [], 5: [], 6: []}
        return tiles[k]

    if len(kept):
        ti = np.floor((cx[kept] - ox) / TILE).astype(np.int64)
        tj = np.floor((cz[kept] - oz) / TILE).astype(np.int64)
        lx = cx[kept] - (ox + ti * TILE)
        lz = cz[kept] - (oz + tj * TILE)
        rec = np.stack([lx, lz, bw[kept], bdp[kept], ang[kept], bh[kept],
                        bkind[kept].astype(np.float32),
                        (kept % 997).astype(np.float32) / 997.0], 1).astype(np.float32)
        for k in range(len(kept)):
            tile(int(ti[k]), int(tj[k]))[1].append(rec[k])

    def clip_lines(g, extra, sec, fn):
        x0, z0, x1, z1 = g.bounds
        for tj in range(max(0, math.floor((z0 - oz) / TILE)), min(RT - 1, math.floor((z1 - oz) / TILE)) + 1):
            for ti in range(max(0, math.floor((x0 - ox) / TILE)), min(RT - 1, math.floor((x1 - ox) / TILE)) + 1):
                tx = ox + ti * TILE
                tz = oz + tj * TILE
                part = shapely.clip_by_rect(g, tx - 2.0, tz - 2.0, tx + TILE + 2.0, tz + TILE + 2.0)
                if part.is_empty:
                    continue
                for line in getattr(part, "geoms", [part]):
                    if line.geom_type != "LineString" or len(line.coords) < 2:
                        continue
                    pts = np.asarray(line.coords) - (tx, tz)
                    tile(ti, tj)[sec].append(fn(pts, extra))

    for g, (cls, width, bridge) in zip(roads, road_info):
        clip_lines(g, (cls, width, bridge), 2,
                   lambda p, e: np.concatenate([[len(p), e[0], e[1], e[2]], p.ravel()]).astype(np.float32))
    for width, g in rivers:
        clip_lines(g, width, 4, lambda p, e: np.concatenate([[len(p), e], p.ravel()]).astype(np.float32))
    for g in rail:
        clip_lines(g, 0, 5, lambda p, e: np.concatenate([[len(p)], p.ravel()]).astype(np.float32))

    # Water areas, cut to the tiles and triangulated
    for p, level, kind in lakes:
        x0, z0, x1, z1 = p.bounds
        for tj in range(max(0, math.floor((z0 - oz) / TILE)), min(RT - 1, math.floor((z1 - oz) / TILE)) + 1):
            for ti in range(max(0, math.floor((x0 - ox) / TILE)), min(RT - 1, math.floor((x1 - ox) / TILE)) + 1):
                tx = ox + ti * TILE
                tz = oz + tj * TILE
                part = shapely.clip_by_rect(p, tx, tz, tx + TILE, tz + TILE)
                if part.is_empty:
                    continue
                for poly in getattr(part, "geoms", [part]):
                    if poly.geom_type != "Polygon" or poly.area < 1.0:
                        continue
                    rings = [np.asarray(poly.exterior.coords)[:-1]] + [np.asarray(r.coords)[:-1] for r in poly.interiors]
                    verts = np.concatenate(rings) - (tx, tz)
                    ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
                    try:
                        tri = earcut.triangulate_float64(verts, ends)
                    except Exception:
                        continue
                    if len(tri) < 3:
                        continue
                    tv = verts[np.asarray(tri, dtype=np.int64)]
                    lv = -9999.0 if level is None else level
                    tile(ti, tj)[3].append(np.concatenate([[len(tri) // 3, lv], tv.ravel()]).astype(np.float32))

    for r in runways:
        ti = math.floor((r["x"] - ox) / TILE)
        tj = math.floor((r["z"] - oz) / TILE)
        if 0 <= ti < RT and 0 <= tj < RT:
            tile(ti, tj)[6].append(np.array([r["x"] - ox - ti * TILE, r["z"] - oz - tj * TILE,
                                             r["length"], r["width"], r["angle"],
                                             1.0 if r["paved"] else 0.0, r["airfield"]], np.float32))
    return tiles, kept


def _region_file(rx, rz, heights_q, flags, tiles):
    """TXR1: header, heights (int16, quarter metres), flags (uint8), then a 16 x 16 table of
    zlib-packed tiles, each a list of sections [tag u32, float count u32, floats...]"""
    out = bytearray()
    out += b"TXR1"
    out += struct.pack("<iiif", rx, rz, HN, HSTEP)
    hb = heights_q.tobytes()
    hz = zlib.compress(hb, 6)
    out += struct.pack("<II", len(hb), len(hz)) + hz
    fb = np.ascontiguousarray(flags).tobytes()
    fz = zlib.compress(fb, 6)
    out += struct.pack("<II", len(fb), len(fz)) + fz
    table_at = len(out)
    out += b"\0" * (RT * RT * 12)
    for (ti, tj), secs in sorted(tiles.items()):
        if not (0 <= ti < RT and 0 <= tj < RT):
            continue
        body = bytearray()
        for tag in (1, 2, 3, 4, 5, 6):
            items = secs[tag]
            if not items:
                continue
            data = np.concatenate(items).astype("<f4")
            body += struct.pack("<II", tag, len(data)) + data.tobytes()
        if not body:
            continue
        z = zlib.compress(bytes(body), 6)
        at = len(out)
        out += z
        struct.pack_into("<III", out, table_at + (tj * RT + ti) * 12, at, len(z), len(body))
    return bytes(out)


def _road_graph(rd, xs, zs, keep):
    """The roads units drive on: junctions where ways meet or end, stretches between them with
    their shape, joined up where two ways just continue each other, largest connected part only"""
    import shapely
    from shapely.geometry import LineString
    off = rd["off"]
    cls = rd["cls"]
    ids = rd["ids"]
    use = np.array([c in ROUTE_CLASSES for c in cls]) & keep
    # how many times each node id is used by a routing way (ends count twice: they're junctions)
    sel_ranges = [(i, off[i], off[i + 1]) for i in range(len(cls)) if use[i]]
    all_ids = np.concatenate([ids[a:b] for _, a, b in sel_ranges]) if sel_ranges else np.zeros(0, np.int64)
    ends = np.array([[ids[a], ids[b - 1]] for _, a, b in sel_ranges], np.int64).ravel()
    uniq, counts = np.unique(np.concatenate([all_ids, ends]), return_counts=True)
    junction_ids = set(uniq[counts >= 2].tolist())
    # split ways at junctions
    jindex = {}
    jpos = []
    chains = []      # [a, b, cls, [(x, z)...]]
    for wi, a, b in sel_ranges:
        way_cls = int(cls[wi])
        start = a
        for k in range(a + 1, b):
            nid = int(ids[k])
            if nid in junction_ids or k == b - 1:
                ja = _jid(int(ids[start]), xs[start], zs[start], jindex, jpos)
                jb = _jid(nid, xs[k], zs[k], jindex, jpos)
                if ja != jb:
                    chains.append([ja, jb, way_cls, list(zip(xs[start:k + 1].tolist(), zs[start:k + 1].tolist()))])
                start = k
    # merge through junctions that only join two stretches
    adj = {}
    for ci, ch in enumerate(chains):
        adj.setdefault(ch[0], []).append(ci)
        adj.setdefault(ch[1], []).append(ci)
    alive = [True] * len(chains)
    for j, lst in list(adj.items()):
        live = [c for c in lst if alive[c]]
        if len(live) != 2 or live[0] == live[1]:
            continue
        c1, c2 = chains[live[0]], chains[live[1]]
        # orient c1 to end at j and c2 to start at j
        p1 = c1[3] if c1[1] == j else c1[3][::-1]
        a1 = c1[0] if c1[1] == j else c1[1]
        p2 = c2[3] if c2[0] == j else c2[3][::-1]
        b2 = c2[1] if c2[0] == j else c2[0]
        if a1 == b2:
            continue
        merged = [a1, b2, min(c1[2], c2[2]), p1 + p2[1:]]
        alive[live[1]] = False
        chains[live[0]] = merged
        for end in (a1, b2):
            lst2 = adj[end]
            if live[1] in lst2:
                lst2[lst2.index(live[1])] = live[0]
        adj[j] = []
    chains = [c for c, ok in zip(chains, alive) if ok]
    # largest connected part
    parent = list(range(len(jpos)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for ch in chains:
        ra, rb = find(ch[0]), find(ch[1])
        if ra != rb:
            parent[ra] = rb
    roots = {}
    for ch in chains:
        r = find(ch[0])
        roots[r] = roots.get(r, 0) + 1
    if not roots:
        return {"blob": b"TXN1" + struct.pack("<iii", 0, 0, 0), "junctions": 0, "chains": 0, "points": 0, "km": 0}
    main = max(roots, key=roots.get)
    chains = [c for c in chains if find(c[0]) == main]
    used = sorted(set([c[0] for c in chains] + [c[1] for c in chains]))
    renum = {j: k for k, j in enumerate(used)}
    pts = [jpos[j] for j in used]
    rec = []
    lengths = []
    total = 0.0
    for a, b, c, shape in chains:
        inner = shape[1:-1]
        if len(inner) > 2:
            inner = list(LineString(shape).simplify(8.0).coords)[1:-1]
        start = len(pts)
        pts.extend(inner)
        line = [shape[0]] + inner + [shape[-1]]
        L = float(np.sum(np.hypot(np.diff([p[0] for p in line]), np.diff([p[1] for p in line]))))
        total += L
        rec.append((renum[a], renum[b], c, start, len(inner)))
        lengths.append(L)
    P = np.asarray(pts, np.float64)
    payload = (P.astype("<f8").tobytes() + np.asarray(rec, "<i4").tobytes()
               + np.asarray(lengths, "<f4").tobytes())
    z = zlib.compress(payload, 6)
    head = b"TXN1" + struct.pack("<iiiII", len(used), len(pts), len(rec), len(payload), len(z))
    return {"blob": head + z, "junctions": len(used), "chains": len(rec), "points": len(pts),
            "km": total * SCALE / 1000.0}


def _jid(nid, x, z, jindex, jpos):
    k = jindex.get(nid)
    if k is None:
        k = len(jpos)
        jindex[nid] = k
        jpos.append((float(x), float(z)))
    return k


def _cities(places, H, px, texas):
    from scipy import ndimage
    from shapely.geometry import Point
    out = []
    seen = set()
    for name, kind, pop, lat, lon in sorted(places, key=lambda p: -p[2]):
        x, z = to_xz(lat, lon)
        if name in seen:
            continue
        if pop >= 1000000:
            tier = 5
        elif pop >= 300000:
            tier = 4
        elif pop >= 100000:
            tier = 3
        elif pop >= 30000:
            tier = 2
        elif pop >= 5000 or kind == "city":
            tier = 1
        else:
            tier = 0
        inside = texas.contains(Point(x, z))
        if not inside and tier < 3:
            continue
        seen.add(name)
        hx, hz = px(np.array([x]), np.array([z]))
        e = float(ndimage.map_coordinates(H, [hz, hx], order=1, mode="nearest")[0])
        out.append([name, round(float(x), 1), round(float(z), 1), tier, pop, round(e), inside])
    return out


def _draw_map(path, H, sea, flags, lakes, roads, r_cls, rail, texas, airfields):
    """The strategic map: 4096 x 4096 over the map bounds"""
    from PIL import Image, ImageDraw
    from scipy import ndimage
    N = 4096
    xs = GX0 + (np.arange(N) + 0.5) / N * (GX1 - GX0)
    zs = GZ0 + (np.arange(N) + 0.5) / N * (GZ1 - GZ0)
    fx = (xs - HX0) / HSTEP
    fz = (zs - HZ0) / HSTEP
    ZZ, XX = np.meshgrid(fz, fx, indexing="ij")
    e = ndimage.map_coordinates(H, [ZZ, XX], order=1, mode="nearest").astype(np.float32)
    s = ndimage.map_coordinates(sea.astype(np.float32), [ZZ, XX], order=1, mode="nearest") > 0.5
    fl = ndimage.map_coordinates(flags, [ZZ, XX], order=0, mode="nearest")
    del ZZ, XX
    inside = (fl & 1) > 0
    urban = (fl & 4) > 0
    # relief: light from the north-west
    px_m = (GX1 - GX0) / N * SCALE
    gy, gx = np.gradient(e, px_m)
    shade = np.clip(1.0 - (gx + gy) * 6.0, 0.72, 1.25)
    lon = LON0 + xs * SCALE / MLON
    west = np.array([0.62, 0.54, 0.40])
    plains = np.array([0.60, 0.57, 0.40])
    middle = np.array([0.48, 0.50, 0.32])
    east = np.array([0.30, 0.42, 0.24])
    t1 = np.clip((lon + 104.0) / 1.5, 0, 1)[:, None]
    t2 = np.clip((lon + 102.5) / 3.5, 0, 1)[:, None]
    t3 = np.clip((lon + 99.0) / 4.0, 0, 1)[:, None]
    base = np.where((lon < -102.5)[:, None], west * (1 - t1) + plains * t1,
                    np.where((lon < -99.0)[:, None], plains * (1 - t2) + middle * t2, middle * (1 - t3) + east * t3))
    col = np.broadcast_to(base[None, :, :], (N, N, 3)).copy()
    low = (e < 25.0)[..., None]
    col = np.where(low, col * 0.5 + np.array([0.44, 0.52, 0.34]) * 0.5, col)
    col = np.where(urban[..., None], col * 0.45 + np.array([0.62, 0.60, 0.56]) * 0.55, col)
    col = col * shade[..., None]
    grey = col.mean(axis=2, keepdims=True)
    col = np.where(inside[..., None], col, grey * 0.75 + 0.08)
    depth = np.clip(-e / 60.0, 0, 1)[..., None]
    seac = np.array([0.24, 0.42, 0.58]) * (1 - depth) + np.array([0.12, 0.25, 0.42]) * depth
    col = np.where(s[..., None], seac, col)
    img = Image.fromarray(np.clip(col * 255, 0, 255).astype(np.uint8), "RGB")
    dr = ImageDraw.Draw(img)

    def p(x, z):
        return ((x - GX0) / (GX1 - GX0) * N, (z - GZ0) / (GZ1 - GZ0) * N)

    for poly, level, kind in lakes:
        if poly.area < 2.0e5:
            continue
        for g in getattr(poly, "geoms", [poly]):
            if hasattr(g, "exterior"):
                dr.polygon([p(x, z) for x, z in g.exterior.coords], fill=(58, 104, 140))
    for g in rail:
        for part in getattr(g, "geoms", [g]):
            dr.line([p(x, z) for x, z in part.coords], fill=(70, 62, 58), width=1)
    order = sorted(range(len(roads)), key=lambda i: -int(r_cls[i]))
    style = {0: ((236, 200, 110), 4), 1: ((226, 196, 120), 3), 2: ((216, 206, 168), 2),
             3: ((196, 190, 160), 1), 5: ((236, 200, 110), 2), 6: ((226, 196, 120), 2)}
    for i in order:
        c = int(r_cls[i])
        if c not in style:
            continue
        fill, w = style[c]
        g = roads[i]
        for part in getattr(g, "geoms", [g]):
            dr.line([p(x, z) for x, z in part.coords], fill=fill, width=w)
    for g in getattr(texas, "geoms", [texas]):
        if hasattr(g, "exterior"):
            dr.line([p(x, z) for x, z in g.exterior.coords], fill=(25, 25, 25), width=5)
    for a in airfields:
        x, z = p(a["x"], a["z"])
        r = 9 if a["jets"] else 6
        dr.rectangle([x - r, z - r, x + r, z + r], outline=(20, 20, 20), width=3,
                     fill=(120, 150, 210) if a["military"] else (225, 225, 230))
    img.save(path, optimize=True)
    log("map.png written (%.1f MB)" % (os.path.getsize(path) / 1e6))


def _fallback_outline():
    # TexasGeo.OUTLINE (lat, lon), for data without the state boundary
    return [
        [36.50, -103.04], [36.50, -100.00], [34.56, -100.00], [34.42, -99.70], [34.20, -99.20], [34.10, -98.60],
        [33.90, -98.00], [33.83, -97.40], [33.73, -96.60], [33.86, -96.10], [33.83, -95.50], [33.64, -94.90],
        [33.55, -94.04], [31.99, -94.04], [31.50, -93.82], [31.00, -93.55], [30.40, -93.70], [30.05, -93.72],
        [29.70, -93.84], [29.55, -94.35], [29.30, -94.80], [29.05, -95.10], [28.95, -95.36], [28.75, -95.70],
        [28.60, -96.00], [28.43, -96.40], [28.20, -96.75], [28.00, -97.05], [27.80, -97.25], [27.60, -97.30],
        [27.20, -97.38], [26.80, -97.37], [26.55, -97.30], [26.20, -97.18], [25.96, -97.15], [25.90, -97.50],
        [26.05, -97.80], [26.10, -98.20], [26.40, -98.95], [26.80, -99.25], [27.50, -99.50], [28.00, -99.95],
        [28.70, -100.50], [29.35, -100.90], [29.77, -101.40], [29.80, -101.80], [29.60, -102.40], [29.20, -102.80],
        [28.97, -103.20], [29.20, -103.70], [29.55, -104.40], [30.10, -104.70], [30.60, -104.95], [31.00, -105.50],
        [31.40, -106.10], [31.75, -106.45], [32.00, -106.62], [32.00, -103.06]]


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--osm", default=os.path.join(root, "data", "texas", "texas-latest.osm.pbf"))
    ap.add_argument("--elev", default=os.path.join(root, "data", "texas", "elevation.nc"))
    ap.add_argument("--out", default=os.path.join(root, "data", "texas", "build"))
    ap.add_argument("--work", default=None, help="where the extract goes (default: <out>/../work)")
    ap.add_argument("--stage", choices=["all", "extract", "bake"], default="all")
    args = ap.parse_args()
    work = args.work or os.path.join(os.path.dirname(os.path.abspath(args.out)), "work")
    os.makedirs(work, exist_ok=True)
    os.makedirs(args.out, exist_ok=True)
    if args.stage in ("all", "extract"):
        if not os.path.exists(args.osm):
            # Geofabrik's dated downloads (texas-261027.osm.pbf) work too
            import glob
            found = sorted(glob.glob(os.path.join(os.path.dirname(args.osm), "*.osm.pbf")))
            if found:
                args.osm = found[-1]
        if not os.path.exists(args.osm):
            sys.exit("No OSM file at %s: download texas-latest.osm.pbf from Geofabrik first." % args.osm)
        extract(args.osm, work)
    if args.stage in ("all", "bake"):
        bake(work, args.out, args.elev)


if __name__ == "__main__":
    main()
