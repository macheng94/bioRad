% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/bioRad.R
\name{regularize}
\alias{regularize}
\title{Regularize a time series}
\usage{
regularize(ts, interval = "auto", t.min = ts$daterange[1],
  t.max = ts$daterange[2], units = "mins", fill = F, verbose = T)
}
\arguments{
\item{ts}{an object inhereting from class \code{vpts}, see \link{vpts} for details.}

\item{interval}{time interval grid to project on. When '\code{auto}' the median interval in the time series is used.}

\item{t.min}{start time of the projected time series, as a POSIXct object. Taken from \code{ts} when '\code{auto}'.}

\item{t.max}{end time of the projected time series, as a POSIXct object. Taken from \code{ts} when '\code{auto}'.}

\item{units}{optional units of \code{interval}, one of 'secs', 'mins', 'hours','days', 'weeks'. Defaults to 'mins'.}

\item{fill}{logical. Whether to fill missing timesteps with the values of the closest neighbouring profile.}

\item{verbose}{logical. When \code{TRUE} prints text to console.}
}
\value{
an object of class \code{vpts} with regular time steps
}
\description{
Projects objects of class \code{vpts} on a regular time grid
}
\examples{
# locate example file:
VPtable <- system.file("extdata", "VPtable.txt", package="bioRad")
# load time series:
ts=readvp.table(VPtable,radar="KBGM", wavelength='S')
# regularize the time series on a 5 minute interval grid
tsRegular=regularize(ts, interval=5)
}
