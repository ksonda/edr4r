# Getting started with edr4r

`edr4r` is a thin, tidy client for OGC API - EDR services. This vignette
walks through a typical session against the Western Water Datahub
(WWDH).

## 1. Create a client

``` r

library(edr4r)

# Local pygeoapi dev server; swap for the hosted URL in production.
wwdh <- edr_client("http://localhost:5005")
wwdh
```

The client just stores connection settings (base URL, user agent,
timeout, retry policy). Pass `verbose = TRUE` to echo every request URL,
or `headers =` to attach auth tokens.

## 2. Discover what’s available

``` r

collections <- edr_collections(wwdh)
collections[, c("id", "title", "data_queries")]
```

`data_queries` tells you which EDR query types each collection supports.
To see the parameters a collection accepts:

``` r

q <- edr_queryables(wwdh, "snotel-edr")
names(q$properties)
```

## 3. Find locations

With no filters, `locations` returns a GeoJSON `FeatureCollection`,
which `edr4r` promotes to an `sf` object (if `sf` is installed):

``` r

rise_locs <- edr_locations(wwdh, "rise-edr")
rise_locs

library(sf)
plot(st_geometry(rise_locs), pch = 19, cex = 0.4)
```

You can pre-filter the list spatially:

``` r

edr_locations(wwdh, "snotel-edr", bbox = c(-120, 39, -118, 41))
```

## 4. Retrieve data for a location

Add a `location_id` and a `datetime` to get CoverageJSON, then flatten
it:

``` r

resp <- edr_location(
  wwdh, "rise-edr",
  location_id    = 247,
  datetime       = "2020-01-01/2020-12-31",
  parameter_name = c("storage", "elevation")
)

df <- covjson_to_tibble(resp)
head(df)
```

The tibble is long and tidy — ready for `dplyr`/`ggplot2`:

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
  wwdh, "snotel-edr",
  bbox           = c(-120, 39, -118, 41),
  datetime       = "2023-01-01/2023-03-31",
  parameter_name = "WTEQ"
)
covjson_to_tibble(cube)

ring <- matrix(c(-109, 47, -104, 47, -104, 49, -109, 49), ncol = 2, byrow = TRUE)
area <- edr_area(wwdh, "rise-edr", coords = ring, datetime = "2022-01-01/..")
covjson_to_tibble(area)
```

## 6. Other formats and the escape hatch

``` r

# CSV straight from the server
edr_location(wwdh, "snotel-edr", "1175", datetime = "2010-01-01/..", format = "csv")

# Anything not wrapped by a helper:
edr_request(wwdh, "collections/rise-edr", format = "json")
```

## Notes

- `datetime` accepts `"start/end"`, open intervals (`"2020-01-01/.."`),
  or a length-2 character vector.
- `parameter_name` is a character vector; it is sent as a single
  comma-separated `parameter-name` query parameter.
- Station identifiers with reserved characters (e.g. AWDB triplets like
  `"1185:CO:SNTL"`) are handled for you.
- WWDH implements `locations`, `cube`, and `area`. The `position`,
  `radius`, `trajectory`, and `corridor` verbs exist in this client for
  spec completeness and other servers, but will error against
  collections that do not implement them. \`\`\`
