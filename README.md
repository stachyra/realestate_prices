# Purpose and Scope

This repository contains an R script to analyze Zillow house price data vs. time in the Boston, MA metropolitan area, and plot results as both choropleths and time series graphs.

# Dependencies

This repository requires the following software and data dependencies to be installed:

## Software

* Basic unix/linux tools: bash, awk, unzip, etc.
* [R](https://www.r-project.org/) and/or [RStudio](https://rstudio.com/): R language interpreter (required for executing main script)
* [Tidyverse Core](https://www.tidyverse.org/):
    - [tidyr](https://tidyr.tidyverse.org/): Tidies (i.e., reorganizes) messy tables
    - [dplyr](https://dplyr.tidyverse.org/): Manipulates tidy data tables
    - [ggplot2](https://ggplot2.tidyverse.org/): Plots data
* Other tidyverse-affiliated R packages:
    - [lubridate](https://lubridate.tidyverse.org/): Facilitates working with dates in time series data
    - [sf](https://r-spatial.github.io/sf/index.html): Simple Features package for GIS data sets (aims to be a successor to [sp](https://www.rdocumentation.org/packages/sp/versions/1.3-2))
    - [plyr](https://www.rdocumentation.org/packages/plyr/versions/1.8.5): Predecessor to dplyr, which still contains some functionality not yet fully replicated in its successor 
    - [viridis](https://cran.r-project.org/web/packages/viridis/vignettes/intro-to-viridis.html): Provides evenly scaled viridis color palette

## Data

* MassGIS [town boundary](https://docs.digital.mass.gov/dataset/massgis-data-community-boundaries-towns-survey-points) GIS shapefiles
* Zillow seasonally adjusted [house sale prices](https://www.zillow.com/research/data/), aggreagated by city

# Semi-Reproducible Processing Instructions

Zillow appears to update their house sale price data roughly every few weeks, however, due to a pair of bugs and/or design flaws in their data publishing workflow, it's very difficult for an end user to reproduce identical plots using data which was downloaded at a later point in time--even if the analysis period is limited to only the set of time points available from the earlier download.  The two causes of this are:

- A significant bug results in roughly 10-12 towns or cities being dropped or reinstated, apparently at random, every few weeks with each new data release from Zillow.  So the actual set of towns for which data is available changes slightly with each new data release.

- A feature (or perhaps a less significant bug?) is that the seasonal adjustment calculation performed by Zillow is based upon the entire time series, so each time a new month's worth of data is added, all of the other previous months end up being adjusted just slightly, relative to their earlier released values.

Because Zillow does not publish non-seasonally-adjusted sale prices, the latter problem has no solution.  As a partial workaround to the first problem, the data download script for the sale price data, `download_pricefiles.sh`, has been designed to save price data from previous downloads, and when a town or city has temporarily gone missing from a more recent update, the script attempts to re-merge the older data into the newly downloaded version of the file.  As a result, the set of towns for which data is available should somewhat stabilize, after multiple re-downloads re-executed periodically over several weeks.  Obviously this situation is kind of stupid and annoying, but there's not much that can be done about it.

After the software dependencies are installed, the data can be downloaded and the plots reproduced (at least approximately) via the following series of steps:

1. Run the download script for the town boundary data:

        ./download_shapefiles.sh

    This will create and populate a subdirectory called `./data/townssurvey_shp/`

2. Run the download script for the house sale price data:

        ./download_pricefiles.sh

    This will create (if it doesn't exist already) a subdirectory called `./data/` and populate it with a file named `Sale_Prices_City.csv`.

3. Run the analysis script:

        Rscript plottowns.R

    Or simply execute as `source("plottowns.R")` within an R interpreter environment such as RStudio.  Output plots will be saved as `.svg` image files in a directory called `./output_plots/`.
