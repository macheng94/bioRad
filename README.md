# bioRad
R package for extracting and visualising biological signals from weather radar data

# installation
First install the rhdf5 dependency:

### rhdf5
bioRad requires the rhdf5 library to read [hdf5](https://support.hdfgroup.org/HDF5/) files. This library is available through bioconductor (not CRAN). To install:
``` 
source("http://bioconductor.org/biocLite.R")
biocLite("rhdf5")
```

### bioRad 
To install the bioRad package in R use the devtools package:
```
install.packages("devtools")
library(devtools)
install_github("adokter/bioRad")
```

### Docker
The functionality of [vol2bird](https://github.com/adokter/vol2bird) is available in bioRad through Docker.

Go to the [Docker](https://www.docker.com/) webpage for instructions on how to install Docker on your local system. On 8 Dec 2016 Docker is available for Windows 10 Professional or Enterprise 64-bit, MacOS Yosemite 10.10.3 or above, or any linux/unix distribution.

Without a Docker installation, the bioRad package disables volbird automatically. All the other tools will still work.

### ggplot2 and ggmap
bioRad requires the ggplot2 and ggmap packages to be installed in R. While these are both available throught CRAN, on MacOS I found that I ran into this error when using bioRad's function `map`:
```
Error: GeomRasterAnn was built with an incompatible version of ggproto.
Please reinstall the package that provides this extension.
```
This issue is fixed when installing the latest versions from Github (8 Dec 2016)
```
install_github("dkahle/ggmap")
install_github("hadley/ggplot2")
```

### rgdal
bioRad requires an installation of rgdal, which can be fetched from CRAN. When you want to compile rgdal using a non-default installation directory of the proj.4 library that rgdal depends on, install from source using the following command (example here with `/opt/local/lib/proj47` as the proj4 path):
```
install.packages('rgdal',configure.args=c('--with-proj-include=/opt/local/lib/proj47/include', '--with-proj-lib=/opt/local/lib/proj47/lib'),type="source")
```


