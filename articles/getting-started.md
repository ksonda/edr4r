# Getting started with edr4r

`edr4r` is a small, tidy client for any service that speaks [OGC API -
Environmental Data Retrieval](https://ogcapi.ogc.org/edr/). Most of the
real-world use to date has been against in-situ monitoring networks –
stream gauges, weather stations, snow telemetry, reservoir telemetry –
but the package itself is generic.

Two example endpoints you can point it at right now:

- [USGS waterdata OGC API](https://api.waterdata.usgs.gov/ogcapi/beta/)
- [Western Water Datahub](https://api.wwdh.internetofwater.app)

This vignette walks through a typical session. The collection IDs and
parameter names below (`monitoring-locations`, `daily-values`,
`discharge`, …) are placeholders – every server advertises its own. The
first thing to do against a new service is run
[`edr_collections()`](https://ksonda.github.io/edr4r/reference/edr_collections.md)
and look at what it returns.

## 1. Create a client

``` r

library(edr4r)

# Pick any EDR-compliant base URL. A trailing slash is optional.
client <- edr_client("https://api.waterdata.usgs.gov/ogcapi/beta")
client
```

The client just stores connection settings (base URL, user agent,
timeout, retry policy). Pass `verbose = TRUE` to echo every request URL,
or `headers =` to attach auth tokens.

## 2. Discover what’s available

``` r

collections <- edr_collections(client)
collections[, c("id", "title", "data_queries")]
```

`data_queries` tells you which EDR query types each collection supports.
To see the parameters a collection accepts:

``` r

q <- edr_queryables(client, "daily-values")
names(q$properties)
```

## 3. Find locations

With no filters, `locations` returns a GeoJSON `FeatureCollection`,
which `edr4r` promotes to an `sf` object (if `sf` is installed):

``` r

stations <- edr_locations(client, "monitoring-locations")
stations

library(sf)
plot(st_geometry(stations), pch = 19, cex = 0.4)
```

You can pre-filter the list spatially:

``` r

edr_locations(client, "monitoring-locations", bbox = c(-120, 39, -118, 41))
```

## 4. Retrieve data for a location

Add a `location_id` and a `datetime` to get CoverageJSON, then flatten
it:

``` r

resp <- edr_location(
  client, "daily-values",
  location_id    = "08313000",
  datetime       = "2020-01-01/2020-12-31",
  parameter_name = c("discharge", "gage_height")
)

df <- covjson_to_tibble(resp)
head(df)
```

The tibble is long and tidy – ready for `dplyr`/`ggplot2`:

``` r

library(ggplot2)
ggplot(df, aes(datetime, value, colour = parameter)) +
  geom_line() +
  facet_wrap(~ parameter, scales = "free_y")
```

## 5. Spatial queries: cube and area

`cube` takes a bounding box; `area` takes a polygon (WKT, an lon/lat
matrix, or an `sf` polygon):

``` r

cube <- edr_cube(
  client, "daily-values",
  bbox           = c(-120, 39, -118, 41),
  datetime       = "2023-01-01/2023-03-31",
  parameter_name = "discharge"
)
covjson_to_tibble(cube)

ring <- matrix(c(-109, 47, -104, 47, -104, 49, -109, 49), ncol = 2, byrow = TRUE)
area <- edr_area(client, "monitoring-locations", coords = ring,
                 datetime = "2022-01-01/..")
covjson_to_tibble(area)
```

## 6. Other formats and the escape hatch

``` r

# CSV straight from the server (if the server advertises it)
edr_location(client, "daily-values", "08313000",
             datetime = "2010-01-01/..", format = "csv")

# Anything not wrapped by a helper:
edr_request(client, "collections/daily-values", format = "json")
```

## A few things worth knowing

- `datetime` is forgiving: pass `"start/end"`, an open interval like
  `"2020-01-01/.."`, or a length-2 character vector. It gets normalised
  into the ISO-8601 form the server expects.
- `parameter_name` is a character vector. It’s sent as one
  comma-separated `parameter-name` query parameter.
- Some monitoring networks use compound station IDs (colon-separated
  triplets like `"1185:CO:SNTL"` show up in snow and forecast networks).
  Those work as-is – reserved characters get URL-encoded for you. A
  literal `/` in an ID is rejected, because it can’t survive a round
  trip through HTTP path segments no matter how you encode it.
- Not every server implements every EDR verb. `locations`, `position`,
  `cube`, and `area` are common; `radius`, `trajectory`, and `corridor`
  less so. The client supports them all per the
  [spec](https://ogcapi.ogc.org/edr/), but a call against a collection
  that doesn’t implement a given verb returns an HTTP error. \`\`\`
