% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/bioRad.ppi.R
\name{plot.ppi}
\alias{plot.ppi}
\title{Plot a plan position indicator (PPI)}
\usage{
\method{plot}{ppi}(x, param, xlim, ylim, zlim = c(-20, 20), ratio = 1, ...)
}
\arguments{
\item{x}{an object of class 'ppi'}

\item{param}{the scan parameter to plot}

\item{xlim}{range of x values to plot}

\item{ylim}{range of y values to plot}

\item{zlim}{the range of parameter values to plot}

\item{ratio}{aspect ratio between x and y scale}

\item{...}{arguments passed to low level \link[ggplot2]{ggplot} function}
}
\description{
Plots a plan position indicator (PPI) generated with \link{ppi} using \link[ggplot2]{ggplot}
}
\examples{
# load an example scan:
data(SCAN)
SCAN
# make ppi for the scan
ppi=ppi(SCAN)
# plot the first scan parameter, which in this case is "VRADH":
plot(ppi)
# plot the reflectivity quantity:
plot(ppi,param="DBZH")
# change the range of reflectivities to plot to -30 to 50 dBZ:
plot(ppi,param="DBZH",zlim=c(-30,50))
}
