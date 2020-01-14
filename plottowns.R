library(lubridate)
library(sf)
library(dplyr)
library(tidyr)
library(ggplot2)
library(viridis)

# ---------------------------------
# User Controls and Initializations
# ---------------------------------

# Longitude / latitude of lower left / upper right corners of zoomed window
# around Boston
loleft <- c(-71.5, 42.15)
upright <- c(-70.85, 42.65)
# Width of additional border strip around zoom window (in meters) inside of
# which the underlying data itself should be cropped.  This extra step is
# necessary because some very inexpensive locations in western MA have houses
# that cost in the range of $100000 - $150000, and if we do not crop these
# out of the data itself, then the false color legend will reserve colors
# for this price range even though no data in this range actually appears in
# the zoom window.
cropborder <- 10000
# Start and stop dates for price averaging
startprice <- decimal_date(as.Date("2019-05-01"))
stopprice <- decimal_date(as.Date("2019-11-01"))
# Start and stop dates for the regression region used to estimate fitted
# annually compouneded growth rate
startgrowth <- decimal_date(as.Date("2012-03-01"))
stopgrowth <- decimal_date(as.Date("2019-11-01"))
# Date grid lines for time series plots
datebreaks <- seq(2008, 2022, 2)
# Output plot directory
plotdir <- "output_plots"
ifelse(!dir.exists(plotdir), dir.create(plotdir), FALSE)
# Convert text size in pts to text size in mm
pts_to_mm = 0.352777

# ----------
# Data Files
# ----------

# Directory containing an unzipped archive of GIS files that I downloaded from
# https://docs.digital.mass.gov/dataset/massgis-data-community-boundaries-towns-survey-points
shpdir <- "data/townssurvey_shp"
# A particular batch of GIS files in the archive (there were 4 "layers"
# within the overall archive, as described on the downloads page)
layer <- "TOWNSSURVEY_POLY"
# Table of median sales prices vs. cities vs. time, downloaded from Zillow
# Research: https://www.zillow.com/research/data/
fsales <- "data/Sale_Prices_City.csv"

# ---------
# Load Data
# ---------

# Load a "simple feature" data frame (special type of data frame for holding
# GIS data, with native support for plotting in ggplot2 using geom_sf).
# Note that in order to avoid R warnings at later stages in proceessing,
# the st_buffer() method adds a zero-width buffer, following advice
# offered here: https://gis.stackexchange.com/a/163480
dfsf <- st_buffer(st_read(dsn=shpdir, layer=layer), 0)
# Make town character instead of factor, to avoid warnings about unequal
# factor levels when we join to the sales data set using this as our primary key
dfsf$TOWN <- as.character(dfsf$TOWN)

# Load the sales price data
dfsales <- read.table(fsales, header=TRUE, sep=",", fill=TRUE)
# Throw away all sales data that's not from Massachusetts, and then take
# all of the monthly sales date (everthing to the right of the first four
# columns named "RegionID", etc.) and transpose it from columns to rows.
# Finally, sort by SizeRank.
dfsales <- filter(dfsales, StateName == "Massachusetts") %>%
           gather("year", "median_sales_price", -RegionID, -RegionName,
                  -StateName, -SizeRank) %>%
           mutate(year = decimal_date(as.Date(paste0(year, ".15"),
                                              format("X%Y.%m.%d")))) %>%
           filter(!is.na(median_sales_price)) %>%
           arrange(SizeRank)
# Clean up factor representation
dfsales <- droplevels(dfsales)
# Convert RegionName to all caps in order to match the TOWN names in dfsf
dfsales$RegionName <- as.character(toupper(dfsales$RegionName))
# Make hand correction to spelling, so that the name for NORTH ATTLEBOROUGH
# will match the convention used in the spatial features data frame
idx <- which(dfsales$RegionName == "NORTH ATTLEBORO")
dfsales$RegionName[idx] <- "NORTH ATTLEBOROUGH"

# ----------------------
# Process and Merge Data
# ----------------------

# Many towns, especially ones near the coast that may have small islands
# associated with them, comprise several polygons.  Save the largest
# polygon from each town in a special data frame that we will use as a
# basis for further calculations: e.g., distance to Cambridge, or for
# printing just a single text label with the town's name.  (If we omit
# this step, then some towns will have their name printed like 20 times;
# once per polygon)
dfname <- dfsf %>%
          group_by(TOWN) %>%
          filter(SHAPE_Area == max(SHAPE_Area))
ctrd <- st_centroid(dfname$geometry)
idx <- which(dfname$TOWN == "CAMBRIDGE")
dst_to_cmbg <- st_distance(ctrd, ctrd[idx]) / 1000
dfname$dst_to_cmbg <- dst_to_cmbg

# Summarize sales price over the time interval (startprice, stopprice);
# approximately the past 6 months
dfpricesumm <- filter(dfsales, year > startprice & year < stopprice) %>%
               group_by(RegionName) %>%
               summarize(RegionID=first(RegionID),
                         StateName=first(StateName),
                         SizeRank=first(SizeRank),
                         median_sales_price=median(median_sales_price)) %>%
               arrange(SizeRank)
# Create extra columns that will be used to assign false color values to
# specific price ranges
saturation_price <- c(600000, 1000000)
colnam <- c("pr_brks_mass", "pr_brks_boston")
for (ii in seq(2)) {
  brks <- seq(0, saturation_price[ii], 50000)
  lbls <- paste(format(brks[1:length(brks)-1], scientific=FALSE, big.mark=","),
                format(brks[2:length(brks)], scientific=FALSE, big.mark=","),
                sep=" - ")
  spchar <- format(saturation_price[ii], scientific=FALSE, big.mark=",")
  dfpricesumm[colnam[ii]] <- cut(dfpricesumm$median_sales_price,
                                 breaks=append(brks, 1e9),
                                 labels=append(lbls, paste(">", spchar)))
}

# Formula to estimate "starting price" at time startgrowth, and annual
# percentage growth rate (i.e., compounded annually) thereafter
expgrowth_form <- (median_sales_price ~ sp * (1+apr/100)**(year-startgrowth))
# For simplicity, use the same starting coefficients for all towns
initcoef <- c(sp=500000, apr=8)
fitfunc <- function(df) {
  nls(formula=expgrowth_form, data=df, start=initcoef)
}
# Perform an implicit loop over "RegionName", estimating sp and apr values
# for each town
models <- plyr::dlply(.data=filter(dfsales, year > startgrowth &
                                   year < stopgrowth),
                      .variables="RegionName", .fun=fitfunc)
# Gather estimated formula parameters for each town into a single data frame
dfregress <- plyr::ldply(.data=models, .fun=coef)
# For graphing purposes, divide APR into buckets from -2% to +13% annual growth
brks <- seq(-2, 13)
lbls <- paste(brks[1:length(brks)-1], brks[2:length(brks)], sep=" - ")
dfregress["gr_brks"] <- cut(dfregress$apr, breaks=brks, labels=lbls)
dfspan <- filter(dfsales, year > startgrowth & year < stopgrowth) %>%
          group_by(RegionName) %>%
          summarize(span=max(year)-min(year)+1/12)
dfregress <- full_join(dfregress, dfspan, by="RegionName")
dfregress["text_statement"] <- paste0("Annual increase: ",
                                      format(dfregress$apr, digits=3), "%\n",
                                      "Time span: ",
                                      format(dfregress$span, digits=3), " years")

# Merge three data frames: median price, estimated price growth, and town
# geography.  Filtering out unrecognized town IDs is necessary because the
# sales price data contained one additional sub-region, East Falmouth",
# which is not officially recognized as a separate town by the state of
# MAssachusetts
dfpricesumm <- full_join(dfpricesumm, dfregress, by="RegionName")
dfpricemap <- st_as_sf(full_join(dfpricesumm, dfsf,
                                 by=c("RegionName" = "TOWN"))) %>%
              filter(!is.na(TOWN_ID))

# ------------------------
# Map Support Calculations
# ------------------------

# Standard industry code for WGS84 (see, e.g.:
# https://spatialreference.org/ref/epsg/wgs-84/)
epsg_wgs84 = 4326
# The GIS data has been supplied as a Lambert conformal conic projection.
# WHen zooming in on projections, the zoom window has to be specified in
# projection coordinates, not geodetic (longitude and latitude) coordinates.
# But it's easier to think in terms of geodetic coordinates, so calculate
# a conversion between these two.
zoomlglt <- st_sfc(st_point(loleft), st_point(upright), crs=epsg_wgs84)
zoomlcc <- st_coordinates(st_transform(zoomlglt, crs=st_crs(dfpricemap)))
# Crop data.  Note this results in a warning due to the issue described here:
# https://cran.r-project.org/web/packages/sf/vignettes/sf1.html#how-attributes-relate-to-geometries
# The st_crop() method seems to have no way to suppress this warning; the
# only way to fix it would be to set the "attribute-geometry relationship"
# for every column in the data frame, using st_agr()
dfcrop <- st_crop(dfpricemap,
                  xmin=zoomlcc[1,'X']-cropborder,
                  ymin=zoomlcc[1,'Y']-cropborder,
                  xmax=zoomlcc[2,'X']+cropborder,
                  ymax=zoomlcc[2,'Y']+cropborder)

# -----------
# Create Maps
# -----------

# Creates a series of 4 choropleths: 
#  1: Sale price vs. town (all of MA)
#  2: Sale price vs. town (zoomed region around Boston)
#  3: Sale price annual percentage growth rate (all of MA)
#  4: Sale price annual percentage growth rate (zoomed region around Boston)

# Data items to be looped over:
#   input data frames
#   columns in data frame to use as fill values
#   fill legend text
#   font size for town labels
#   font size for legend title
#   font size for legend text
#   figure output file name
#   figure width (inches)
#   figure height (inches)
pricemap <- list(dfpricemap, dfcrop, dfpricemap, dfcrop)
brk_var <- c("pr_brks_mass", "pr_brks_boston", "gr_brks", "gr_brks")
lgd_ttl <- c("Zillow Median Sales Price ($)", "Zillow Median Sales Price ($)",
             "Annual Appreciation Rate (%)", "Annual Appreciation Rate (%)")
tsiz <- c(5,11,5,11) * pts_to_mm
lgttlsz <- c(16,18,16,18)
lgtxtsz <- c(12,14,12,14)
fname_maps <- c("Mass_house_sale_prices.svg", "Boston_house_sale_prices.svg",
                "Mass_house_price_growth.svg", "Boston_house_price_growth.svg")
wd <- c(16, 12, 16, 12)
ht <- c(9, 9, 9, 9)
choromap <- list()
for (ii in seq(4)) {
  choromap[[ii]] <- ggplot(pricemap[[ii]]) +
                    geom_sf(aes_string(fill=brk_var[ii])) +
                    scale_fill_viridis(name=lgd_ttl[ii],
                                       discrete=TRUE,
                                       guide=guide_legend(reverse=TRUE)) +
                    geom_sf_text(aes(label=TOWN), data=dfname, color="red",
                                 size=tsiz[ii]) +
                    xlab("") + ylab("") +
                    theme(axis.text=element_text(size=12),
                    legend.title=element_text(size=lgttlsz[ii]),
                    legend.text=element_text(size=lgtxtsz[ii]))
  # Even numbered plots are zoomed versions, so amend them by zooming
  if (! ii %% 2) {
    choromap[[ii]] <- choromap[[ii]] +
                      coord_sf(xlim=zoomlcc[,'X'], ylim=zoomlcc[,'Y'])
  }
  
  svg(filename=paste(plotdir, fname_maps[ii], sep="/"),
      width=wd[ii], height=ht[ii])
  print(choromap[[ii]])
  dev.off()
}

# -----------------
# Show Example Fits
# -----------------

# For each town, at each time point between startgrowth and stopgrowth,
# estimate a "predicted" sales price using the fitted values for sp and apr
# obtained previously for that town.
idx <- dfsales$year > startgrowth & dfsales$year < stopgrowth
predyear <- sort(unique(dfsales$year[idx]))
dftmp <- plyr::ldply(.data=models, .fun=predict,
                     newdata=data.frame(year=predyear))
ntown <- nrow(dftmp)
dfpredict <- gather(dftmp, "time_point", "fitted_sales_price", -RegionName)
dfpredict$year <- rep(predyear, each=ntown)
dfpredict <- arrange(dfpredict, RegionName, year)
# Add sales price prediction as a set of additional columns in the basic
# sales price data frame
dfsalepred <- left_join(dfsales, dfpredict, by=c("RegionName", "year"))

# Plot example data with smoothed prediction superimposed
ybrk <- seq(0,2000000,200000)
allowed_towns <- c("ARLINGTON", "NORTH READING", "LEXINGTON")
pltfit <- ggplot(filter(dfsalepred, RegionName %in% allowed_towns)) +
          geom_point(aes(x=year, y=median_sales_price, color=RegionName),
                     size=1.5) +
          geom_line(aes(x=year, y=fitted_sales_price, color=RegionName),
                    size=1.5) +
          scale_x_continuous(breaks=datebreaks) +
          scale_y_continuous(breaks=ybrk,
                             labels=format(ybrk, scientific=FALSE,
                                           big.mark=",")) +
          xlab("Year") + ylab("Median Sales Price ($)") +
          labs(color="Town") +
          theme(axis.text=element_text(size=14),
                axis.title=element_text(size=20),
                legend.title=element_text(size=18),
                legend.text=element_text(size=14))

svg(filename=paste(plotdir, "fit_examples.svg", sep="/"), width=14, height=8)
print(pltfit)
dev.off()

# Control variables specific to next pair of plots
expensive_towns <- c("BELMONT", "BROOKLINE", "CONCORD", "LEXINGTON", "NEEDHAM",
                     "NEWTON", "WELLESLEY", "WESTON", "WINCHESTER")
#nexptown <- length(expensive_towns)
# Number of figure columns
ncfg <- 4
# Base dimension size for figure axes, in inches, assuming 72 dpi
basesize <-3

# Display fit results for all towns.  Items to be looped over:
#   sales data frames (inexpensive vs. expensive towns)
#   regression data frames (inexpensive vs. expensive towns)
#   figure output file name
#   number of rows of figure panels
salesdata <- list(filter(dfsalepred, !(RegionName %in% expensive_towns)),
                  filter(dfsalepred, (RegionName %in% expensive_towns)))
regressresults <- list(filter(dfregress, !(RegionName %in% expensive_towns)),
                       filter(dfregress, (RegionName %in% expensive_towns)))
fname_fits <- c("allfits_typical.svg", "allfits_expensive.svg")
nrfg <- c(ceiling(nrow(regressresults[[1]])/ncfg),
          ceiling(nrow(regressresults[[2]])/ncfg))
pltallfit <- list()
for (ii in seq(2)) {
  pltallfit[[ii]] <- ggplot(salesdata[[ii]]) +
                     geom_point(aes(x=year, y=median_sales_price), size=0.5,
                                color="blue") +
                     geom_line(aes(x=year, y=fitted_sales_price), size=1) +
                     geom_text(mapping=aes(x=-Inf, y=Inf, label=text_statement,
                                           hjust=-0.05, vjust=1.25),
                               data=regressresults[[ii]]) +
                     scale_x_continuous(breaks=datebreaks) +
                     scale_y_continuous(breaks=ybrk,
                                        labels=format(ybrk, scientific=FALSE,
                                                      big.mark=",")) +
                     xlab("Year") + ylab("Median Sales Price ($)") +
                     facet_wrap(~RegionName, ncol=ncfg) +
                     theme(legend.position = "none",
                           panel.spacing.x=unit(18, "bigpts"),
                           axis.text=element_text(size=10),
                           axis.title=element_text(size=14),
                           strip.text.x=element_text(size=11))
  
  svg(filename=paste(plotdir, fname_fits[ii], sep="/"),
      width=ncfg*basesize, height=nrfg[ii]*basesize)
  print(pltallfit[ii])
  dev.off()
}
