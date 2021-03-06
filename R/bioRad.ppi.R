#' Read a polar volume (pvol) from file
#'
#' @param filename A string containing the path to a vertical profile generated by \link[bioRad]{vol2bird}
#' @param sort logical. When \code{TRUE} sort scans ascending by elevation
#' @param param atomic vector of character strings, containing the names of scan parameters to read. To read all scan parameters use 'all'.
#' @param lat latitude in decimal degrees of the radar position. If not specified, value stored in file is used. If specified, value stored in file is overwritten.
#' @param lon longitude in decimal degrees of the radar position. If not specified, value stored in file is used. If specified, value stored in file is overwritten.
#' @param height height of the centre of the antenna in meters above sea level. If not specified, value stored in file is used. If specified, value stored in file is overwritten.
#' @param elangle.min Minimum scan elevation to read in degrees
#' @param elangle.max Maximum scan elevation to read in degrees
#' @param verbose logical. Whether to print messages to console
#' @param mount character string with the mount point (a directory path) for the Docker container
#' @export
#' @return an object of class \link[=summary.pvol]{pvol}, which is a list containing polar scans, i.e. objects of class \code{scan}
#' @details
#' Scan parameters are named according to the OPERA data information model (ODIM), see
#' Table 16 in the \href{https://github.com/adokter/vol2bird/blob/master/doc/OPERA2014_O4_ODIM_H5-v2.2.pdf}{ODIM specification}.
#' Commonly available parameters are:
#' \describe{
#'  \item{"\code{DBZH}", "\code{DBZ}"}{(Logged) reflectivity factor [dBZ]}
#'  \item{"\code{VRADH}", "\code{VRAD}"}{Radial velocity [m/s]. Radial velocities towards
#'   the radar are negative, while radial velocities away from the radar are positive}
#'  \item{"\code{RHOHV}"}{Correlation coefficient [unitless]. Correlation between vertically polarized and horizontally polarized reflectivity factor}
#'  \item{"\code{PHIDP}"}{Differential phase [degrees]}
#'  \item{"\code{ZDR}"}{(Logged) differential reflectivity [dB]}
#' }
#' @examples
#' # locate example volume file:
#' pvol <- system.file("extdata", "volume.h5", package="bioRad")
#' # print the local path of the volume file:
#' pvol
#' # load the file:
#' vol=read.pvol(pvol)
#' # print summary info for the loaded polar volume:
#' vol
#' # print summary info for the scans in the polar volume:
#' vol$scans
#' # copy the first scan to a new object 'scan'
#' scan=vol$scans[[1]]
#' # print summary info for the new object:
#' scan
read.pvol = function(filename,param=c("DBZH","VRADH","VRAD","RHOHV","ZDR","PHIDP","CELL"),sort=T,lat,lon,height,elangle.min=0,elangle.max=90,verbose=T,mount=dirname(filename)){
  if(!is.logical(sort)) stop("'sort' should be logical")
  if(!missing(lat)) if(!is.numeric(lat) || lat< -90 || lat>90) stop("'lat' should be numeric between -90 and 90 degrees")
  if(!missing(lon)) if(!is.numeric(lon) || lat< -360 || lat>360) stop("'lon' should be numeric between -360 and 360 degrees")
  if(!missing(height)) if(!is.numeric(height) || height<0) stop("'height' should be a positive number of meters above sea level")

  # check file type. If not ODIM hdf5, try to convert from RSL
  cleanup=F
  if(H5Fis_hdf5(filename)){
    if(!is.pvolfile(filename)) stop("failed to read hdf5 file")
  }
  else{
    if(verbose) cat("Converting using Docker ...\n")
    if(!docker) stop("Requires a running Docker daemon.\nTo enable, start your local Docker daemon, and run 'checkDocker()' in R\n")
    filename = rsl2odim_tempfile(filename,verbose=verbose,mount=mount)
    if(!is.pvolfile(filename)){
      file.remove(filename)
      stop("converted file contains errors")
    }
    cleanup=T
  }

  #extract scan groups
  scans=h5ls(filename,recursive=F)$name
  scans=scans[grep("dataset",scans)]

  #extract elevations, and make selection based on elevation
  elevs=sapply(scans,function(x) h5readAttributes(filename,paste(x,"/where",sep=""))$elangle)
  scans=scans[elevs>=elangle.min & elevs<=elangle.max]

  #extract attributes
  h5struct=h5ls(filename)
  h5struct=h5struct[h5struct$group=="/",]$name
  attribs.how=attribs.what=attribs.where=NULL
  if("how" %in% h5struct) attribs.how=h5readAttributes(filename,"how")
  if("what" %in% h5struct) attribs.what=h5readAttributes(filename,"what")
  if("where" %in% h5struct) attribs.where=h5readAttributes(filename,"where")

  vol.lat=attribs.where$lat
  vol.lon=attribs.where$lon
  vol.height=attribs.where$height
  if(is.null(vol.lat)){
    if(missing(lat)){
      if(cleanup) file.remove(filename)
      stop("latitude not found in file, provide 'lat' argument")
    } else vol.lat=lat
  }
  if(is.null(vol.lon)){
    if(missing(lon)){
      if(cleanup) file.remove(filename)
      stop("longitude not found in file, provide 'lon' argument")
    } else vol.lon=lon
  }
  if(is.null(vol.height)){
    if(missing(height)){
      if(cleanup) file.remove(filename)
      stop("antenna height not found in file, provide 'height' argument")
    } else vol.height=height
  }
  geo=list(lat=vol.lat,lon=vol.lon,height=vol.height)

  #convert some useful metadata
  datetime=as.POSIXct(paste(attribs.what$date, attribs.what$time), format = "%Y%m%d %H%M%S", tz='UTC')
  sources=strsplit(attribs.what$source,",")[[1]]
  radar=gsub("RAD:","",sources[which(grepl("RAD:",sources))])

  #read scan groups
  data=lapply(scans,function(x) read.scan(filename,x,param,geo))
  #order by elevation
  if(sort) data=data[order(sapply(data,elangle))]

  #prepare output
  output=list(radar=radar,datetime=datetime,scans=data,attributes=list(how=attribs.how,what=attribs.what,where=attribs.where),geo=geo)
  class(output) = "pvol"

  if(cleanup) file.remove(filename)

  output
}

read.scan=function(filename,scan,param,geo){
  h5struct=h5ls(filename)
  h5struct=h5struct[h5struct$group==paste("/",scan,sep=""),]$name
  groups=h5struct[grep("data",h5struct)]

  # select which scan parameters to read
  if(length(param)==1 && param=="all") allParam=T else allParam=F
  if(!allParam){
    quantityNames=sapply(groups,function(x) h5readAttributes(filename,paste(scan,"/",x,"/what",sep=""))$quantity)
    groups=groups[quantityNames %in% param]
    if(length(groups)==0) stop(paste("none of the requested scan parameters present in",filename))
  }

  # read attributes

  attribs.how=attribs.what=attribs.where=NULL
  if("how" %in% h5struct) attribs.how=h5readAttributes(filename,paste(scan,"/how",sep=""))
  if("what" %in% h5struct) attribs.what=h5readAttributes(filename,paste(scan,"/what",sep=""))
  if("where" %in% h5struct) attribs.where=h5readAttributes(filename,paste(scan,"/where",sep=""))

  # add attributes to geo list
  geo$elangle=attribs.where$elangle
  geo$rscale=attribs.where$rscale
  geo$ascale=360/attribs.where$nrays

  # read scan parameters
  quantities=lapply(groups,function(x) read.quantity(filename,paste(scan,"/",x,sep=""),geo))
  quantityNames=sapply(quantities,'[[',"quantityName")
  quantities=lapply(quantities,'[[',"quantity")
  names(quantities)=quantityNames

  output=list(params=quantities,attributes=list(how=attribs.how,what=attribs.what,where=attribs.where),geo=geo)
  class(output)="scan"
  output
}

read.quantity=function(filename,quantity,geo){
  data=h5read(filename,quantity)$data
  attr=h5readAttributes(filename,paste(quantity,"/what",sep=""))
  data=replace(data,data==as.numeric(attr$nodata),NA)
  data=replace(data,data==as.numeric(attr$undetect),NaN)
  data=as.numeric(attr$offset)+as.numeric(attr$gain)*data
  class(data)=c("param",class(data))
  attributes(data)$geo=geo
  attributes(data)$param=attr$quantity
  list(quantityName=attr$quantity,quantity=data)
}

#' print method for class \code{pvol}
#'
#' @param x An object of class \code{pvol}, a polar volume
#' @keywords internal
#' @export
print.pvol=function(x,digits = max(3L, getOption("digits") - 3L), ...){
  stopifnot(inherits(x, "pvol"))
  cat("               Polar volume (class pvol)\n\n")
  cat("     # scans: ",length(x$scans),"\n")
  cat("       radar: ",x$radar,"\n")
  cat("      source: ",x$attributes$what$source,"\n")
  cat("nominal time: ",as.character(x$datetime),"\n\n")
}

#' print method for class \code{scan}
#'
#' @param x An object of class \code{scan}, a polar scan
#' @keywords internal
#' @export
print.scan=function(x,digits = max(3L, getOption("digits") - 3L), ...){
  stopifnot(inherits(x, "scan"))
  cat("                  Polar scan (class scan)\n\n")
  cat("     parameters: ",names(x$params),"\n")
  cat("elevation angle: ",x$attributes$where$elangle,"deg\n")
  cat("           dims: ",x$attributes$where$nbins,"bins x",x$attributes$where$nrays,"rays\n")
}

#' print method for class \code{param}
#'
#' @param x An object of class \code{param}, a polar scan parameter
#' @keywords internal
#' @export
print.param=function(x,digits = max(3L, getOption("digits") - 3L), ...){
  stopifnot(inherits(x, "param"))
  cat("               Polar scan parameter (class param)\n\n")
  cat("    quantity: ",attributes(x)$param,"\n")
  cat("        dims: ",dim(x)[1],"bins x",dim(x)[2],"rays\n")
}

#' Class 'pvol': polar volume
#' @param object object of class 'pvol'
#' @param x object of class 'pvol'
#' @param ... additional arguments affecting the summary produced.
#' @export
#' @method summary pvol
#' @details
#' A polar scan object of class 'pvol' is a list containing:
#' \describe{
#'  \item{\code{radar}}{character string with the radar identifier}
#'  \item{\code{datetime}}{nominal time of the volume [UTC]}
#'  \item{\code{scans}}{a list with scan objects of class 'scan'}
#'  \item{\code{attributes}}{list with the volume's \code{\\what}, \code{\\where} and \code{\\how} attributes}
#'  \item{\code{geo}}{geographic data, a list with:
#'   \describe{
#'      \item{\code{lat}}{latitude of the radar [decimal degrees]}
#'      \item{\code{lon}}{longitude of the radar [decimal degrees]}
#'      \item{\code{height}}{height of the radar antenna [metres above sea level]}
#'   }
#'  }
#' }
#' @examples
#' # locate example volume file:
#' pvol <- system.file("extdata", "volume.h5", package="bioRad")
#' # print the local path of the volume file:
#' pvol
#' # load the file:
#' vol=read.pvol(pvol)
#' # print summary info for the loaded polar volume:
#' vol
#' # print summary info for the scans in the polar volume:
#' vol$scans
#' # copy the first scan to a new object 'scan'
#' scan=vol$scans[[1]]
summary.pvol = function(object, ...) print.pvol(object)

#' @rdname summary.pvol
#' @export
#' @return for \code{is.pvol}: \code{TRUE} if its argument is of class "\code{pvol}"
#' @examples
#' is.pvol("this is not a polar volume but a string")  #> FALSE
is.pvol <- function(x) inherits(x, "pvol")

#' Class 'scan': polar scan
#' @param object object of class 'scan'
#' @param x object of class 'scan'
#' @param ... additional arguments affecting the summary produced.
#' @export
#' @method summary scan
#' @details
#' A polar scan object of class 'scan' is a list containing:
#' \describe{
#'  \item{\code{params}}{a list with scan parameters}
#'  \item{\code{attributes}}{list with the scans's \code{\\what}, \code{\\where} and \code{\\how} attributes}
#'  \item{\code{geo}}{geographic data, a list with:
#'     \describe{
#'      \item{\code{lat}}{latitude of the radar [decimal degrees]}
#'      \item{\code{lon}}{longitude of the radar [decimal degrees]}
#'      \item{\code{height}}{height of the radar antenna [metres above sea level]}
#'      \item{\code{elangle}}{radar beam elevation [degrees]}
#'      \item{\code{rscale}}{range bin size [m]}
#'      \item{\code{ascale}}{azimuth bin size [deg]}
#'     }
#'     The \code{geo} element of a 'scan' object is a copy of the \code{geo} element of its parent polar volume of class 'pvol'.
#'   }
#' }
#' @examples
#' # load example scan object
#' data(SCAN)
#' # print the scan parameters contained in the scan:
#' SCAN$params
#' # extract the first scan parameter:
#' param=SCAN$params[1]
summary.scan=function(object, ...) print.scan(object)

#' @rdname summary.scan
#' @export
#' @return for \code{is.scan}: \code{TRUE} if its argument is of class "\code{scan}"
#' @examples
#' is.scan("this is not a polar scan but a string")  #> FALSE
is.scan <- function(x) inherits(x, "scan")

#' @rdname summary.scan
#' @export
#' @return for \code{dim.scan}: dimensions of the scan
dim.scan <- function(x) {
  stopifnot(inherits(x,"scan"))
  c(length(x$params),x$attributes$where$nbins,x$attributes$where$nrays)
}

#' Class 'param': polar scan parameter
#' @param object object of class 'param'
#' @param x object of class 'param'
#' @param ... additional arguments affecting the summary produced.
#' @export
#' @method summary param
#' @details
#' Scan parameters are simple matrices, with the following specific attributes:
#' \describe{
#'    \item{\code{lat}}{latitude of the radar [decimal degrees]}
#'    \item{\code{lon}}{longitude of the radar [decimal degrees]}
#'    \item{\code{height}}{height of the radar antenna [metres above sea level]}
#'    \item{\code{elangle}}{radar beam elevation [degrees]}
#'    \item{\code{param}}{string with the name of the polar scan parameter}
#' }
#' Scan parameters are named according to the OPERA data information model (ODIM), see
#' Table 16 in the \href{https://github.com/adokter/vol2bird/blob/master/doc/OPERA2014_O4_ODIM_H5-v2.2.pdf}{ODIM specification}.
#' Commonly available parameters are:
#' \describe{
#'  \item{"\code{DBZH}", "\code{DBZ}"}{(Logged) reflectivity factor [dBZ]}
#'  \item{"\code{VRADH}", "\code{VRAD}"}{Radial velocity [m/s]. Radial velocities towards
#'   the radar are negative, while radial velocities away from the radar are positive}
#'  \item{"\code{RHOHV}"}{Correlation coefficient [unitless]. Correlation between vertically polarized and horizontally polarized reflectivity factor}
#'  \item{"\code{PHIDP}"}{Differential phase [degrees]}
#'  \item{"\code{ZDR}"}{(Logged) differential reflectivity [dB]}
#' }
summary.param=function(object, ...) print.param(object)

#' @rdname summary.param
#' @export
#' @return for \code{is.scan}: \code{TRUE} if its argument is of class "\code{param}"
#' @examples
#' is.param("this is not a polar scan parameter but a string")  #> FALSE
is.param <- function(x) inherits(x, "param")

#' Elevation angle of scan(s)
#'
#' Gives the elevation angle of a scan, or the elevation angles within a polar volume
#' @param x a \code{pvol} or \code{scan} object
#' @export
#' @return elevation in degrees
#' @examples
#' # load a polar volume
#' pvol <- system.file("extdata", "volume.h5", package="bioRad")
#' vol=read.pvol(pvol)
#' # elevations for the scans in the volume
#' elangle(vol)
#' # extract the first scan:
#' scan=vol$scans[[1]]
#' # elevation angle of the scan:
#' elangle(scan)
elangle <- function (x) UseMethod("elangle", x)

#' @describeIn elangle elevation angle of a scan
#' @export
elangle.scan = function(x){
  stopifnot(inherits(x,"scan"))
  x$attributes$where$elangle
}

#' @describeIn elangle elevation angles of all scans in a polar volume
#' @export
elangle.pvol = function(x){
  stopifnot(inherits(x,"pvol"))
  sapply(x$scans,elangle.scan)
}

#' Extract a scan from a polar volume
#'
#' Extract a scan from a polar volume
#' @param x an object of class 'pvol'
#' @param angle elevation angle
#' @export
#' @return an object of class '\link[=summary.scan]{scan}'.
#' @details The function returns the scan with elevation angle closest to \code{angle}
#' @examples
#' # locate example volume file:
#' pvol <- system.file("extdata", "volume.h5", package="bioRad")
#' # load the file:
#' vol=read.pvol(pvol)
#' # extract the scan at 3 degree elevation:
#' myscan = getscan(vol,3)
getscan = function(x,angle){
  stopifnot(inherits(x,"pvol"))
  x$scans[[which.min(abs(elangle(x)-angle))]]
}

#' Make a plan position indicator (ppi)
#'
#' Make a plan position indicator (ppi)
#' @param x an object of class 'param' or 'scan'
#' @param cellsize cartesian grid size in m
#' @param range.max maximum range in m
#' @param latlim the range of latitudes to include
#' @param lonlim the range of longitudes to include
#' @param project whether to vertically project onto earth's surface
#' @param ... arguments passed to methods
#' @export
#' @return an object of class '\link[=summary.ppi]{ppi}'.
#' @details The returned PPI is in Azimuthal Equidistant Projection.
#' @examples
#' # load a polar scan example object
#' data(SCAN)
#' SCAN
#' # make PPIs for all scan parameters in the scan:
#' ppi=ppi(SCAN)
#' # print summary info for the ppi:
#' ppi
#' # copy the first scan parameter of the first scan in the volume to a new object 'param':
#' param=SCAN$params[[1]]
#' # make a ppi for the new 'param' object:
#' ppi=ppi(param)
#' # print summary info for this ppi:
#' ppi
ppi <- function (x,cellsize=500,range.max=50000,project=F,latlim=NULL,lonlim=NULL) UseMethod("ppi", x)

#' Subset `ppi`
#'
#' Extract by index from a ppi
#'
#' @param x an object of class 'param' or 'scan'
#' @param i indices specifying elements to extract
#'
#' @export
`[.ppi` <- function(x,i) {
  stopifnot(inherits(x,"ppi"))
  myppi=list(data=x$data[i],geo=x$geo)
  class(myppi)="ppi"
  return(myppi)
}

#' @describeIn ppi ppi for a single scan parameter
#' @export
ppi.param=function(x,cellsize=500,range.max=50000,project=F,latlim=NULL,lonlim=NULL){
  stopifnot(inherits(x,"param"))
  data=samplePolar(x,cellsize,range.max,project,latlim,lonlim)
  # copy the parameter's attributes
  geo=attributes(x)$geo
  geo$bbox=attributes(data)$bboxlatlon
  geo$merged=FALSE
  data=list(data=data, geo=geo)
  class(data)="ppi"
  data
}

#' @describeIn ppi multiple ppi's for all scan parameters in a scan
#' @export
ppi.scan=function(x,cellsize=500,range.max=50000,project=F,latlim=NULL,lonlim=NULL){
  stopifnot(inherits(x,"scan"))
  data=samplePolar(x$params[[1]],cellsize,range.max,project,latlim,lonlim)
  # copy the parameter's geo list to attributes
  geo=x$geo
  geo$bbox=attributes(data)$bboxlatlon
  geo$merged=FALSE
  if(length(x$params)>1){
    alldata=lapply(x$params,function(param) samplePolar(param,cellsize,range.max,project,latlim,lonlim))
    data=do.call(cbind,alldata)
  }
  data=list(data=data, geo=geo)
  class(data)="ppi"
  data
}

#' Make a composite of multiple plan position indicators (ppi objects)
#'
#' Merge multiple plan position indicators (ppi objects). Can be used to make a composite of ppi's from multiple radars
#' @param x a list of objects of class 'ppi'
#' @param param scan parameter to composite
#' @param cells.dim integer; vector with number of cells in each spatial dimension
#' @export
#' @return an object of class '\link[=summary.ppi]{ppi}'.
#' @details The returned PPI is in WGS84 projection (longitude, latitude)
#' @examples
#' # load a polar scan example object
#' data(SCAN)
#' # to be written ...
composite <- function(x,param="DBZH",cells.dim=c(100,100)){
  ppis=lapply(x,`[.ppi`,i=param)
  if (FALSE %in% sapply(ppis,is.ppi)) stop("'composite' expects objects of class ppi only")
  lons=sapply(ppis,function(x) x$geo$bbox["lon",])
  lats=sapply(ppis,function(x) x$geo$bbox["lat",])
  lons.radar=sapply(ppis,function(x) x$geo$lon)
  lats.radar=sapply(ppis,function(x) x$geo$lat)
  elangles=sapply(ppis,function(x) x$geo$elangle)
  bbox=matrix(c(min(lons),min(lats),max(lons),max(lats)),nrow=2,ncol=2,dimnames=dimnames(ppis[[1]]$geo$bbox))
  # define latlon grid
  wgs84=CRS("+proj=longlat +datum=WGS84")
  gridTopo=GridTopology(bbox[,"min"],(bbox[,"max"]-bbox[,"min"])/cells.dim,cells.dim)
  grid=SpatialGrid(grid=gridTopo,proj4string = wgs84)
  # initialize all values of the grid to NA
  spGrid <- SpatialGridDataFrame(grid=grid,data=data.frame(z=rep(1, cells.dim[1]*cells.dim[2])))
  names(spGrid@data)[1] <- names(ppis[[1]]$data)[1]
  # merge
  projs=suppressWarnings(sapply(ppis,function(x) over(spTransform(spGrid,CRS(proj4string(x$data))),x$data)))
  spGrid@data[,1]=do.call(function(...) pmax(...,na.rm=TRUE),projs)

  ppi.out=list(data=spGrid,geo=list(lat=lats.radar,lon=lons.radar,elangle=elangles,bbox=bbox,merged=TRUE))
  class(ppi.out)="ppi"
  ppi.out
}

samplePolar=function(param,cellsize,range.max,project,latlim,lonlim){
  #proj4string=CRS(paste("+proj=aeqd +lat_0=",attributes(param)$geo$lat," +lon_0=",attributes(param)$geo$lon," +ellps=WGS84 +datum=WGS84 +units=m +no_defs",sep=""))
  proj4string=CRS(paste("+proj=aeqd +lat_0=",attributes(param)$geo$lat," +lon_0=",attributes(param)$geo$lon," +units=m",sep=""))
  bboxlatlon=proj2wgs(c(-range.max,range.max),c(-range.max,range.max),proj4string)@bbox
  if(!missing(latlim) & !is.null(latlim)) bboxlatlon["lat",]=latlim
  if(!missing(lonlim) & !is.null(lonlim)) bboxlatlon["lon",]=lonlim
  if(missing(latlim) & missing(lonlim)){
    cellcentre.offset=-c(range.max,range.max)
    cells.dim=ceiling(rep(2*range.max/cellsize,2))
  }
  else{
    bbox=wgs2proj(bboxlatlon["lon",],bboxlatlon["lat",],proj4string)
    cellcentre.offset=c(min(bbox@coords[,"x"]),min(bbox@coords[,"y"]))
    cells.dim=c(ceiling((max(bbox@coords[,"x"])-min(bbox@coords[,"x"]))/cellsize),ceiling((max(bbox@coords[,"y"])-min(bbox@coords[,"y"]))/cellsize))
  }
  # define cartesian grid
  gridTopo=GridTopology(cellcentre.offset,c(cellsize,cellsize),cells.dim)
  # if projecting, account for elevation angle - not accounting for earths curvature
  if(project) elev=attributes(param)$geo$elangle*pi/180 else elev=0
  # get scan parameter indices, and extract data
  index=polar2index(cartesian2polar(coordinates(gridTopo),elev),attributes(param)$geo$rscale,attributes(param)$geo$ascale)
  data=data.frame(mapply(function(x,y) safeSubset(param,x,y),x=index$row,y=index$col))
  colnames(data)=attributes(param)$param
  output=SpatialGridDataFrame(grid=SpatialGrid(grid=gridTopo,proj4string=proj4string),data=data)
  attributes(output)$bboxlatlon=bboxlatlon
  output
}

# wgs2proj is a wrapper for spTransform
# proj4string should be an object of class 'CRS', as defined in package sp.
# returns an object of class SpatialPoints
wgs2proj<-function(lon,lat,proj4string){
  xy <- data.frame(x = lon, y = lat)
  coordinates(xy) <- c("x", "y")
  proj4string(xy) <- CRS("+proj=longlat +datum=WGS84")
  res <- spTransform(xy, proj4string)
  return(res)
}

# proj2wgs is a wrapper for spTransform
# proj4string should be an object of class 'CRS', as defined in package sp.
# returns an object of class SpatialPoints
proj2wgs<-function(x,y,proj4string){
  xy <- data.frame(lon=x, lat=y)
  coordinates(xy) <- c("lon", "lat")
  proj4string(xy) <- proj4string
  res <- spTransform(xy, CRS("+proj=longlat +datum=WGS84"))
  return(res)
}

cartesian2polar=function(coords,elev=0){
  range = sqrt(coords[,1]^2 + coords[,2]^2)/cos(elev)
  azim = (0.5*pi-atan2(coords[,2],coords[,1])) %% (2*pi)
  data.frame(range=range,azim=azim*180/pi)
}

safeSubset=function(data,indexx,indexy){
  datadim=dim(data)
  if(indexx<1 || indexx > datadim[1] || indexy<1 || indexy> datadim[2]) out=NA
  else out=data[indexx,indexy]
  out
}

polar2index=function(coords.polar,rangebin=1, azimbin=1){
  row=floor(1 + coords.polar$range/rangebin)
  col=floor(1 + coords.polar$azim/azimbin)
  data.frame(row=row,col=col)
}

get_colorscale=function(param,zlim){
  if(param %in% c("VRADH","VRADV","VRAD")) colorscale=scale_colour_gradient2(low="blue", high="red", mid="white",name=param,midpoint=0,limits=zlim)
  else colorscale=scale_colour_gradientn(colours=c("lightblue","darkblue","green","yellow","red","magenta"),name=param,limits=zlim)
  return(colorscale)
}

get_colorscale_fill=function(param,zlim){
  if(param %in% c("VRADH","VRADV","VRAD")) colorscale=scale_fill_gradient2(low="blue", high="red", mid="white",name=param,midpoint=0,limits=zlim)
  else colorscale=scale_fill_gradientn(colours=c("lightblue","darkblue","green","yellow","red","magenta"),name=param,limits=zlim)
  return(colorscale)
}


get_zlim=function(param){
  if(param %in% c("DBZH","DBZV","DBZ")) return(c(-20,30))
  if(param %in% c("VRADH","VRADV","VRAD")) return(c(-20,20))
  if(param == "RHOHV") return(c(0,1))
  if(param == "ZDR") return(c(-5,8))
  if(param == "PHIDP") return(c(-200,200))
}

#' Plot a plan position indicator (PPI)
#'
#' Plots a plan position indicator (PPI) generated with \link{ppi} using \link[ggplot2]{ggplot}
#' @param x an object of class 'ppi'
#' @param param the scan parameter to plot, see details below
#' @param xlim range of x values to plot
#' @param ylim range of y values to plot
#' @param ratio aspect ratio between x and y scale
#' @param zlim the range of parameter values to plot
#' @param ... arguments passed to low level \link[ggplot2]{ggplot} function
#' @export
#' @method plot ppi
#' @examples
#' # load an example scan:
#' data(SCAN)
#' # print to screen the available scan parameters:
#' summary(SCAN)
#' # make ppi for the scan
#' ppi=ppi(SCAN)
#' # plot the first scan parameter, which in this case is "VRADH":
#' plot(ppi)
#' # plot the reflectivity quantity:
#' plot(ppi,param="DBZH")
#' # change the range of reflectivities to plot to -30 to 50 dBZ:
#' plot(ppi,param="DBZH",zlim=c(-30,50))
#' @details
#' Available scan parameters for plotting can by printed to screen by \code{summary(x)}.
#' Commonly available parameters are:
#' \describe{
#'  \item{"\code{DBZH}", "\code{DBZ}"}{(Logged) reflectivity factor [dBZ]}
#'  \item{"\code{VRADH}", "\code{VRAD}"}{Radial velocity [m/s]. Radial velocities towards
#'   the radar are negative, while radial velocities away from the radar are positive}
#'  \item{"\code{RHOHV}"}{Correlation coefficient [unitless]. Correlation between vertically polarized and horizontally polarized reflectivity factor}
#'  \item{"\code{PHIDP}"}{Differential phase [degrees]}
#'  \item{"\code{ZDR}"}{(Logged) differential reflectivity [dB]}
#' }
#' The scan parameters are named according to the OPERA data information model (ODIM), see
#' Table 16 in the \href{https://github.com/adokter/vol2bird/blob/master/doc/OPERA2014_O4_ODIM_H5-v2.2.pdf}{ODIM specification}.
plot.ppi=function(x,param,xlim,ylim,zlim=c(-20,20),ratio=1,...){
  stopifnot(inherits(x,"ppi"))
  if(missing(param)){
    if("DBZH" %in% names(x$data)) param="DBZH"
    else param=names(x$data)[1]
  }
  else if(!is.character(param)) stop("'param' should be a character string with a valid scan parameter name")
  if(missing(zlim)) zlim=get_zlim(param)
  colorscale=get_colorscale_fill(param,zlim)
  # extract the scan parameter
  y=NULL #dummy asignment to suppress devtools check warning
  data=do.call(function(y) x$data[y],list(param))
  # convert to points
  data=data.frame(rasterToPoints(raster(data)))
  # plot
  if(missing(xlim)) xlim=x$data@bbox[1,]
  if(missing(ylim)) ylim=x$data@bbox[2,]
  bbox = coord_fixed(xlim=xlim,ylim=ylim,ratio=ratio)
  ggplot(data=data,...) + geom_raster(aes(x, y, fill=eval(parse(text=param)))) + colorscale + bbox
}

#' Grab a basemap for a ppi
#'
#' downloads a Google Maps, OpenStreetMap, Stamen Maps or Naver Map base layer map using \link[ggmap]{get_map}
#' @param x an object of class 'ppi'
#' @param zoom zoom level (optional), see \link[ggmap]{get_map}. An integer from 3 (continent) to 21 (building).
#' By default the zoom level matching the ppi extent is selected automatically.
#' @param alpha transparancy of the basemap (0-1)
#' @param verbose logical. whether to print information to console
#' @param ... arguments to pass to \link[ggmap]{get_map} function
#' @export
#' @examples
#' # load an example scan:
#' data(SCAN)
#' # print summary info for the scan:
#' SCAN
#' # make ppi for the scan
#' ppi=ppi(SCAN)
#' # grab a basemap that matches the extent of the ppi:
#' basemap=basemap(ppi)
#' # map the reflectivity quantity of the ppi onto the basemap:
#' map(ppi,map=basemap,param="DBZH")
#' # download a different type of basemap, e.g. satellite imagery:
#' # see get_map() in ggmap library for full documentation of options
#' basemap=basemap(ppi,maptype="satellite")
#' # map the radial velocities onto the satellite imagery:
#' map(ppi,map=basemap,param="VRADH")
basemap=function(x,verbose=TRUE,zoom,alpha=1,...){
  stopifnot(inherits(x,"ppi"))
  if(!missing(zoom)) if(!is.numeric(zoom)) stop("zoom should be a numeric integer")
  # check size of ppi and determine zoom
  if(missing(zoom)) use_zoom=calc_zoom(x$geo$bbox["lon",],x$geo$bbox["lat",])
  else use_zoom=zoom
  if(verbose) cat("downloading zoom =",use_zoom,"...\n")
  map=get_map(location=c(lon=mean(x$geo$bbox["lon",]),lat=mean(x$geo$bbox["lat",])),zoom=use_zoom,...)
  bboxmap=attributes(map)$bb
  if((x$geo$bbox["lon","max"]-x$geo$bbox["lon","min"] > bboxmap$ur.lon - bboxmap$ll.lon) ||
     (x$geo$bbox["lat","max"]-x$geo$bbox["lat","min"] > bboxmap$ur.lat - bboxmap$ll.lat)){
     if(missing(zoom)){
       if(verbose) cat("map too small, downloading zoom =",use_zoom-1,"...\n")
       map=get_map(location=c(lon=mean(x$geo$bbox["lon",]),lat=mean(x$geo$bbox["lat",])),zoom=use_zoom-1,...)
       bboxmap=attributes(map)$bb
       if((x$geo$bbox["lon","max"]-x$geo$bbox["lon","min"] > bboxmap$ur.lon - bboxmap$ll.lon) ||
          (x$geo$bbox["lat","max"]-x$geo$bbox["lat","min"] > bboxmap$ur.lat - bboxmap$ll.lat)){
         if(verbose) cat("map still too small, downloading zoom =",use_zoom-2,"...\n")
         map=get_map(location=c(lon=mean(x$geo$bbox["lon",]),lat=mean(x$geo$bbox["lat",])),zoom=use_zoom-2,...)
       }
     } else warning("map is smaller than ppi bounding box")
  }
  attributes(map)$geo=x$geo
  attributes(map)$ppi=T
  # add transparency
  add.alpha(map, alpha=alpha)
}

#' Map a plan position indicator (ppi)
#'
#' Plot a ppi on a Google Maps, OpenStreetMap, Stamen Maps or Naver Map base layer map using \link[ggmap]{ggmap}
#' @param x an object of class 'ppi'
#' @param map the basemap to use, result of a call to \link{basemap}
#' @param param the scan parameter to plot
#' @param alpha transparency of the data, value between 0 and 1
#' @param radar.size size of the symbol indicating the radar position
#' @param radar.color colour of the symbol indicating the radar position
#' @param n.color the number of colors (>=1) to be in the palette
#' @param xlim range of x values to plot
#' @param ylim range of y values to plot
#' @param zlim the range of values to plot
#' @param ratio aspect ratio between x and y scale, by default \eqn{1/cos(latitude radar * pi/180)}
#' @param ... arguments passed to low level \link[ggmap]{ggmap} function
#' @export
#' @return a ggmap object (a classed raster object with a bounding box attribute)
#' @details
#' Available scan parameters for mapping can by printed to screen by \code{summary(x)}.
#' Commonly available parameters are:
#' \describe{
#'  \item{"\code{DBZH}", "\code{DBZ}"}{(Logged) reflectivity factor [dBZ]}
#'  \item{"\code{VRADH}", "\code{VRAD}"}{Radial velocity [m/s]. Radial velocities towards
#'   the radar are negative, while radial velocities away from the radar are positive}
#'  \item{"\code{RHOHV}"}{Correlation coefficient [unitless]. Correlation between vertically polarized and horizontally polarized reflectivity factor}
#'  \item{"\code{PHIDP}"}{Differential phase [degrees]}
#'  \item{"\code{ZDR}"}{(Logged) differential reflectivity [dB]}
#' }
#' The scan parameters
#' are named according to the OPERA data information model (ODIM), see
#' Table 16 in the \href{https://github.com/adokter/vol2bird/blob/master/doc/OPERA2014_O4_ODIM_H5-v2.2.pdf}{ODIM specification}.
#' @examples
#' # load an example scan:
#' data(SCAN)
#' # make ppi's for all scan parameters in the scan
#' ppi=ppi(SCAN)
#' # grab a basemap that matches the extent of the ppi:
#' basemap=basemap(ppi)
#' # map the radial velocity scan parameter onto the basemap:
#' map(ppi,map=basemap,param="VRADH")
#' # extend the plotting range of velocities, from -50 to 50 m/s:
#' map(ppi,map=basemap,param="VRADH",zlim=c(-50,50))
#' # give the data less transparency:
#' map(ppi,map=basemap,alpha=0.9)
#' # change the appearance of the symbol indicating the radar location:
#' map(ppi,map=basemap,radar.size=5,radar.color="green")
#' # crop the map:
#' map(ppi,map=basemap,xlim=c(12.4,13.2),ylim=c(56,56.5))
map <- function (x, ...) UseMethod("map", x)

# helper function to add transparency
# class dispatching needs improvement
add.alpha <- function(col, alpha=1){
  if(missing(col)) stop("Please provide a vector or matrix of colours.")
  mycol=col2rgb(col)/255
  mycol=rgb(mycol[1,],mycol[2,],mycol[3,],alpha=alpha)
  if(inherits(col,"ggmap")){
    mycol=matrix(mycol,nrow=dim(col)[1],ncol=dim(col)[2])
    attributes(mycol)=attributes(col)
    class(mycol)=class(col)
    return(mycol)
  }
  else if(inherits(col,"raster")){
    col@data@values=mycol
    return(col)
  }
  else{
    return(mycol)
    #apply(sapply(col, col2rgb)/255, 2, function(x) rgb(x[1], x[2], x[3], alpha=alpha))
  }
}

#' @describeIn map plot a 'ppi' object on a map
#' @export
map.ppi=function(x,map,param,alpha=0.7,xlim,ylim,zlim=c(-20,20),ratio,radar.size=3,radar.color="red",n.color=1000,...){
  stopifnot(inherits(x,"ppi"))
  if(missing(param)){
    if("DBZH" %in% names(x$data)) param="DBZH"
    else param=names(x$data)[1]
  }
  else if(!is.character(param)) stop("'param' should be a character string with a valid scan parameter name")
  if(missing(zlim)) zlim=get_zlim(param)
  if(!(param %in% names(x$data))) stop(paste("no scan parameter '",param,"' in this ppi",sep=""))
  if(!attributes(map)$ppi) stop("not a ppi map, use basemap() to download a map")
  if(attributes(map)$geo$lat!=x$geo$lat || attributes(map)$geo$lon!=x$geo$lon) stop("not a basemap for this radar location")
  # extract the scan parameter
  data=do.call(function(y) x$data[y],list(param))
  wgs84=CRS("+proj=longlat +datum=WGS84")
  epsg3857=CRS("+init=epsg:3857") # this is the google mercator projection
  mybbox=suppressWarnings(spTransform(SpatialPoints(t(data@bbox),proj4string=data@proj4string),CRS("+init=epsg:3857")))
  mybbox.wgs=suppressWarnings(spTransform(SpatialPoints(t(data@bbox),proj4string=data@proj4string),wgs84))
  e=raster::extent(mybbox.wgs)
  r <- raster(raster::extent(mybbox), ncol=data@grid@cells.dim[1]*.9, nrow=data@grid@cells.dim[2]*.9,crs=CRS(proj4string(mybbox)))
  # convert to google earth mercator projection
  data=suppressWarnings(as.data.frame(spTransform(data,CRS("+init=epsg:3857"))))
  # bring z-values within plotting range
  index=which(data$z<zlim[1])
  if(length(index)>0) data[index,]$z=zlim[1]
  index=which(data$z>zlim[2])
  if(length(index)>0) data[index,]$z=zlim[2]
  # rasterize
  r<-raster::rasterize(data[,2:3], r, data[,1])
  # assign colors
  if(param %in% c("VRADH","VRADV","VRAD")) cols=add.alpha(colorRampPalette(colors=c("blue","white","red"),alpha=TRUE)(n.color),alpha=alpha)
  else cols=add.alpha(colorRampPalette(colors=c("lightblue","darkblue","green","yellow","red","magenta"),alpha=TRUE)(n.color),alpha=alpha)

  col.func=function(value,lim){
    output=rep(0,length(value))
    output=round((value-lim[1])/(lim[2]-lim[1])*n.color)
    output[output>n.color]=n.color
    output[output<1]=1
    return(cols[output])
  }
  r@data@values=col.func(r@data@values,zlim)
  # these declarations prevent generation of NOTE "no visible binding for global variable" during package Check
  lon=lat=y=z=NA
  # symbols for the radar position
  # dummy is a hack to be able to include the ggplot2 color scale, radarpoint is the actual plotting of radar positions.
  dummy=geom_point(aes(x = lon, y = lat, colour=z),size=0,data=data.frame(lon=x$geo$lon,lat=x$geo$lat,z=0))
  radarpoint=geom_point(aes(x = lon, y = lat),colour=radar.color,size=radar.size,data=data.frame(lon=x$geo$lon,lat=x$geo$lat))
  # colorscale
  colorscale=get_colorscale(param,zlim)
  # bounding box
  bboxlatlon=attributes(map)$geo$bbox
  # remove dimnames, otherwise ggmap will give a warning message below:
  dimnames(bboxlatlon)=NULL
  if(missing(xlim)) xlim=bboxlatlon[1,]
  if(missing(ylim)) ylim=bboxlatlon[2,]
  # plot the data on the map
  mymap = suppressMessages(ggmap(map)+inset_raster(raster::as.matrix(r),e@xmin,e@xmax,e@ymin,e@ymax) + dummy + colorscale + radarpoint + scale_x_continuous(limits = xlim, expand = c(0, 0)) + scale_y_continuous(limits = ylim, expand = c(0, 0)))
  suppressWarnings(mymap)
}

#' print method for ppi
#'
#' @param x An object of class \code{ppi}
#' @keywords internal
#' @export
print.ppi=function(x,digits = max(3L, getOption("digits") - 3L), ...){
  stopifnot(inherits(x, "ppi"))
  cat("               Plan position indicator (class ppi)\n\n")
  cat("  quantities: ",names(x$data),"\n")
  cat("        dims: ",x$data@grid@cells.dim[1],"x",x$data@grid@cells.dim[2],"pixels\n\n")
}

#' Class 'ppi': plan position indicator
#' @param object object of class 'ppi'
#' @param x object of class 'ppi'
#' @param ... additional arguments affecting the summary produced.
#' @export
#' @method summary ppi
#' @details
#' A PPI of class 'ppi' is a list containing:
#' \describe{
#'  \item{\code{data}}{an object of class \link[sp]{SpatialGridDataFrame} containing the georeferenced data. Commonly available parameters are:
#'     \describe{
#'      \item{"\code{DBZH}", "\code{DBZ}"}{(Logged) reflectivity factor [dBZ]}
#'      \item{"\code{VRADH}", "\code{VRAD}"}{Radial velocity [m/s]. Radial velocities towards the radar are negative, while radial velocities away from the radar are positive}
#'      \item{"\code{RHOHV}"}{Correlation coefficient [unitless]. Correlation between vertically polarized and horizontally polarized reflectivity factor}
#'      \item{"\code{PHIDP}"}{Differential phase [degrees]}
#'      \item{"\code{ZDR}"}{(Logged) differential reflectivity [dB]}
#'        }
#'  }
#'  \item{\code{geo}}{geographic data, a list with:
#'     \describe{
#'      \item{\code{lat}}{latitude of the radar [decimal degrees]}
#'      \item{\code{lon}}{longitude of the radar [decimal degrees]}
#'      \item{\code{height}}{height of the radar antenna [metres above sea level]}
#'      \item{\code{elangle}}{radar beam elevation [degrees]}
#'      \item{\code{rscale}}{range bin size [m]}
#'      \item{\code{ascale}}{azimuth bin size [deg]}
#'     }
#'     The \code{geo} element of a 'scan' object is a copy of the \code{geo} element of its parent scan or scan parameter.
#'   }
#' }
summary.ppi=function(object, ...) print.ppi(object)

#' @rdname summary.ppi
#' @export
#' @return for \code{is.ppi}: \code{TRUE} if its argument is of class "\code{ppi}"
is.ppi <- function(x) inherits(x, "ppi")

#' @rdname summary.ppi
#' @export
#' @return for \code{dim.ppi}: dimensions of the ppi
dim.ppi <- function(x) {
  stopifnot(inherits(x,"ppi"))
  c(dim(x$data)[2],x$data@grid@cells.dim)
}
