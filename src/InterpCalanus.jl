module InterpCalanus

using Dates
using Statistics
using DelimitedFiles 
using NCDatasets
using GeoArrays
using TOML

if isfile("../Manifest.toml")
    juliaversion = TOML.parsefile("../Manifest.toml")["julia_version"]
    DIVAndversion = TOML.parsefile("../Manifest.toml")["deps"]["DIVAnd"][1]["version"]
else
    juliaversion = "1.8.5"
    DIVAndversion = "2.7.9"
end


"""
    read_data_calanus(datafile)

Read the data from a CSV data file containing the CPR data


## Examples
```julia-repl
julia> lon, lat, dates, c_fin, c_helgo = read_data_calanus("CPRfile.csv)
```
"""
function read_data_calanus(datafile::String)
    data = readdlm(datafile, ',', skipstart=1);

    lon = data[:,3]
    lat = data[:,2]
    year = data[:,4]
    month = data[:,5]
    dates = Date.(year, month)
    c_fin = data[:,6]
    c_helgo = data[:,7];
    @info(extrema(lon));
    @info(extrema(lat));
    
    return lon, lat, dates, c_fin, c_helgo
end

"""
    count_years_months(datesarray)

Count the number of occurrences of each month and each year from the array dates,
starting with the 1st year appearing in the list

## Examples
```julia-repl
julia> testdates = [Date(2009, 6, 1), Date(2009, 6, 5), Date(2010, 6, 1)]
julia> yearcount, monthcount = count_years_months(testdates)
([2.0, 1.0], [0.0, 0.0, 0.0, 0.0, 0.0, 3.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
```
"""
function count_years_months(dates::Array)
    
    year = Dates.year.(dates)
    month = Dates.month.(dates)
    
    nyears = maximum(year) - minimum(year) + 1
    yearcount = zeros(nyears)
    monthcount = zeros(12)
    
    ii = 0
    for yyyy in minimum(year):maximum(year)
        ii += 1
        yearcount[ii] = sum(year .== yyyy)
    end
    
    for mm in 1:12
        monthcount[mm] = sum(month .== mm)
    end

    return yearcount, monthcount
end

"""
    create_nc_results(filename, lons, lats, field, L, epsilon2, speciesname)

Write a netCDF file `filename` with the coordinates `lons`, `lats` and the
heatmap `field`. `speciesname` is used for the 'title' attribute of the netCDF.

## Examples
```julia-repl
julia> create_nc_results("Bacteriastrum_interp.nc", lons, lats, field,
    "Bacteriastrum")
```
"""
function create_nc_results(filename::String, lons, lats, times, field, L, epsilon2,
                           speciesname::String="";
                           valex=-999.9,
                           varname::String = "heatmap",
                           long_name::String = "Heatmap",
						   domain::Array = [-180., 180., -90., 90.],
						   aphiaID::Int32 = 0
                           )
    NCDatasets.Dataset(filename, "c") do ds

        # Dimensions
        ds.dim["lon"] = length(lons)
        ds.dim["lat"] = length(lats)
        ds.dim["time"] = Inf # unlimited dimension

        # Declare variables
		nccrs = defVar(ds, "crs", Int64, ())
    	nccrs.attrib["grid_mapping_name"] = "latitude_longitude"
    	nccrs.attrib["semi_major_axis"] = 6371000.0 ;
    	nccrs.attrib["inverse_flattening"] = 0 ;

        ncfield = defVar(ds, varname, Float64, ("lon", "lat"))
        ncfield.attrib["missing_value"] = Float64(valex)
        ncfield.attrib["_FillValue"] = Float64(valex)
		ncfield.attrib["units"] = "1"
        ncfield.attrib["long_name"] = long_name
		# ncfield.attrib["coordinates"] = "lat lon"
		ncfield.attrib["grid_mapping"] = "crs" ;
        
        ncerror = defVar(ds, "$(varname)_error", Float64, ("lon", "lat"))
        ncerror.attrib["missing_value"] = Float64(valex)
        ncerror.attrib["_FillValue"] = Float64(valex)
		ncerror.attrib["units"] = "1"
        ncerror.attrib["long_name"] = "Relative error on $(long_name)"
		# ncerror.attrib["coordinates"] = "lat lon"
		ncerror.attrib["grid_mapping"] = "crs" ;
        
        nctime = defVar(ds, "time", Int64, ("time",))
        nctime.attrib["missing_value"] = Float32(valex)
        nctime.attrib["units"] = "days since 1950-01-01 00:00:00"
        nctime.attrib["long_name"] = "time"
        nctime.attrib["calendar"] = "gregorian"
        
        nclon = defVar(ds,"lon", Float32, ("lon",))
        # nclon.attrib["missing_value"] = Float32(valex)
        nclon.attrib["_FillValue"] = Float32(valex)
        nclon.attrib["units"] = "degrees_east"
        nclon.attrib["long_name"] = "Longitude"
		nclon.attrib["standard_name"] = "longitude"
		nclon.attrib["axis"] = "X"
		nclon.attrib["reference_datum"] = "geographical coordinates, WGS84 projection"
		nclon.attrib["valid_min"] = -180.0 ;
		nclon.attrib["valid_max"] = 180.0 ;

        nclat = defVar(ds,"lat", Float32, ("lat",))
        # nclat.attrib["missing_value"] = Float32(valex)
        nclat.attrib["_FillValue"] = Float32(valex)
        nclat.attrib["units"] = "degrees_north"
		nclat.attrib["long_name"] = "Latitude"
		nclat.attrib["standard_name"] = "latitude"
		nclat.attrib["axis"] = "Y"
		nclat.attrib["reference_datum"] = "geographical coordinates, WGS84 projection"
		nclat.attrib["valid_min"] = -90.0 ;
		nclat.attrib["valid_max"] = 90.0 ;

        # Global attributes
		ds.attrib["Species_scientific_name"] = speciesname
		ds.attrib["Species_aphiaID"] = aphiaID
		ds.attrib["title"] = "$(long_name) based on presence/absence of $(speciesname)"
		ds.attrib["institution"] = "GHER - University of Liege, MBA"
		ds.attrib["source"] = "Spatial interpolation of presence/absence data"
        ds.attrib["project"] = "EMODnet Biology Phase IV"
        ds.attrib["comment"] = "Original data prepared by P. Helaouet"
        ds.attrib["data_authors"] = "Pierre Helaouet <pihe@MBA.ac.uk>"
        ds.attrib["processing_authors"] = "C. Troupin <ctroupin@uliege>, A. Barth <a.barth@uliege.be>"
		ds.attrib["publisher_name"] = "VLIZ"
		ds.attrib["publisher_url"] = "http://www.vliz.be/"
		ds.attrib["publisher_email"] = "info@vliz.be"
        ds.attrib["created"] = Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS")
		ds.attrib["geospatial_lat_min"] = domain[3]
		ds.attrib["geospatial_lat_max"] = domain[4]
		ds.attrib["geospatial_lon_min"] = domain[1]
		ds.attrib["geospatial_lon_max"] = domain[2]
		ds.attrib["geospatial_lat_units"] = "degrees_north"
		ds.attrib["geospatial_lon_units"] = "degrees_east"
		ds.attrib["license"] = "GNU General Public License v2.0"
		ds.attrib["citation"] = "to be filled"
		ds.attrib["acknowledgement"] = "to be filled"
		ds.attrib["tool"] = "DIVAnd"
		ds.attrib["tool_version"] = DIVAndversion
		ds.attrib["tool_doi"] = "10.5281/zenodo.7016823"
		ds.attrib["language"] = "Julia $(juliaversion)"
		ds.attrib["Conventions"] = "CF-1.8"
		ds.attrib["netcdf_version"] = "4"
        ds.attrib["correlation_lengh"] = L
        ds.attrib["noise_to_signal_ratio"] = epsilon2

        # Define variables
        ncfield[:] = field
        nctime[:] = times
        nclon[:] = lons
        nclat[:] = lats;

    end
end

"""
    create_nc_results_time(filename, lons, lats, speciesname)

Create a new netCDF file `filename` with the coordinates `lons`, `lats` that will 
be filled with interpolated field and error field.

## Examples
```julia-repl
julia> create_nc_results_time("Bacteriastrum_interp.nc", lons, lats)
```
"""
function create_nc_results_time(filename::String, lons, lats, ntimes, speciesname::Array=["",];
    valex=-999.9,
    varname::String = "abundance",
    long_name::String = "Interpolated abundance",
	domain::Array = [-180., 180., -90., 90.],
	aphiaID::Array = [0, ],
    L, epsilon2
    )
    Dataset(filename, "c") do ds

        # Dimensions
        ds.dim["lon"] = length(lons)
        ds.dim["lat"] = length(lats)
        ds.dim["aphiaid"] = length(speciesname)
        ds.dim["stringlen"] = 80
        ds.dim["time"] = ntimes

        # Declare variables

        ncaphiaid = defVar(ds, "aphiaid", Int32, ("aphiaid",))
        ncaphiaid.attrib["long_name"] = "Life Science Identifier - World Register of Marine Species"
        # ncaphiaid.attrib["units"] = "level"

        nctaxonname = defVar(ds, "taxon_name", Char, ("stringlen", "aphiaid"))
        nctaxonname.attrib["long_name"] = "Scientific name of the taxa"
        nctaxonname.attrib["standard_name"] = "biological_taxon_name"
    
        nctaxon_lsid = defVar(ds, "taxon_lsid", Char, ("stringlen", "aphiaid"))
        nctaxon_lsid.attrib["standard_name"] = "biological_taxon_lsid"
        nctaxon_lsid.attrib["long_name"] = "Life Science Identifier - World Register of Marine Species"

		nccrs = defVar(ds, "crs", Int64, ())
        nccrs.attrib["long_name"] = "Coordinate Reference System" 
        nccrs.attrib["geographic_crs_name"] = "WGS 84"
        nccrs.attrib["grid_mapping_name"] = "latitude_longitude" 
        nccrs.attrib["reference_ellipsoid_name"] = "WGS 84" 
        nccrs.attrib["horizontal_datum_name"] = "WGS 84"
        nccrs.attrib["prime_meridian_name"] = "Greenwich" 
        nccrs.attrib["longitude_of_prime_meridian"] = 0.
        nccrs.attrib["semi_major_axis"] = 6378137.
        nccrs.attrib["semi_minor_axis"] = 6356752.31424518
        nccrs.attrib["inverse_flattening"] = 298.257223563
        nccrs.attrib["spatial_ref"] = "GEOGCS[\"WGS 84\",DATUM[\"WGS_1984\",SPHEROID[\"WGS 84\",6378137,298.257223563]],PRIMEM[\"Greenwich\",0],UNIT[\"degree\",0.0174532925199433,AUTHORITY[\"EPSG\",\"9122\"]],AXIS[\"Latitude\",NORTH],AXIS[\"Longitude\",EAST],AUTHORITY[\"EPSG\",\"4326\"]]" ;
        nccrs.attrib["GeoTransform"] = "-180 0.08333333333333333 0 90 0 -0.08333333333333333 "

                                                # "aphiaid", "time", "lat", "lon"
                                                # "lon", "lat", "time", "aphiaid"
        ncfield = defVar(ds, varname, Float64, ("lon", "lat", "time", "aphiaid"))
        ncfield.attrib["missing_value"] = Float64(valex)
        ncfield.attrib["_FillValue"] = Float64(valex)
		ncfield.attrib["units"] = "1"
        ncfield.attrib["long_name"] = long_name
		# ncfield.attrib["coordinates"] = "time lat lon"
		ncfield.attrib["grid_mapping"] = "crs" ;
        
        ncerror = defVar(ds, "error", Float64, ("lon", "lat", "time", "aphiaid"))
        ncerror.attrib["missing_value"] = Float64(valex)
        ncerror.attrib["_FillValue"] = Float64(valex)
		ncerror.attrib["units"] = "1"
        ncerror.attrib["long_name"] = "Relative error on $(long_name)"
		# ncerror.attrib["coordinates"] = "time lat lon"
		ncerror.attrib["grid_mapping"] = "crs" ;
        
        nclon = defVar(ds,"lon", Float64, ("lon",))
        # nclon.attrib["missing_value"] = Float32(valex)
        nclon.attrib["_FillValue"] = Float64(valex)
        nclon.attrib["units"] = "degrees_east"
        nclon.attrib["long_name"] = "Longitude"
		nclon.attrib["standard_name"] = "longitude"
		nclon.attrib["axis"] = "X"
		nclon.attrib["reference_datum"] = "geographical coordinates, WGS84 projection"
		nclon.attrib["valid_min"] = -180.0 ;
		nclon.attrib["valid_max"] = 180.0 ;

        nclat = defVar(ds,"lat", Float64, ("lat",))
        # nclat.attrib["missing_value"] = Float32(valex)
        nclat.attrib["_FillValue"] = Float64(valex)
        nclat.attrib["units"] = "degrees_north"
		nclat.attrib["long_name"] = "Latitude"
		nclat.attrib["standard_name"] = "latitude"
		nclat.attrib["axis"] = "Y"
		nclat.attrib["reference_datum"] = "geographical coordinates, WGS84 projection"
		nclat.attrib["valid_min"] = -90.0 ;
		nclat.attrib["valid_max"] = 90.0 ;
        
        nctime = defVar(ds,"time", Float64, ("time",))
        #nctime.attrib["_FillValue"] = Float32(valex)
        nctime.attrib["units"] = "degrees_north"
		nctime.attrib["long_name"] = "Time"
		nctime.attrib["standard_name"] = "time"
        nctime.attrib["units"] = "days since 1950-01-01 00:00:00"
		nctime.attrib["axis"] = "T"
        nctime.attrib["calendar"] = "gregorian"

        # Global attributes
		ds.attrib["Species_scientific_name"] = speciesname
		ds.attrib["Species_aphiaID"] = aphiaID
		ds.attrib["title"] = "$(long_name) based on presence/absence of $(speciesname[1]) and $(speciesname[2])"
		ds.attrib["institution"] = "University of Liege and Marine Biological Association"
		ds.attrib["source"] = "Spatial interpolation of presence/absence data"
        ds.attrib["project"] = "EMODnet Biology Phase IV"
        ds.attrib["comment"] = "Original data prepared by P. Helaouet (Marine Biological Association)"
        ds.attrib["data_authors"] = "Pierre Helaouet <pihe@MBA.ac.uk>"
        ds.attrib["processing_authors"] = "C. Troupin <ctroupin@uliege>, A. Barth <a.barth@uliege.be>"
		ds.attrib["publisher_name"] = "VLIZ"
		ds.attrib["publisher_url"] = "http://www.vliz.be/"
		ds.attrib["publisher_email"] = "info@vliz.be"
        ds.attrib["created"] = Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS")
		ds.attrib["geospatial_lat_min"] = domain[3]
		ds.attrib["geospatial_lat_max"] = domain[4]
		ds.attrib["geospatial_lon_min"] = domain[1]
		ds.attrib["geospatial_lon_max"] = domain[2]
		ds.attrib["geospatial_lat_units"] = "degrees_north"
		ds.attrib["geospatial_lon_units"] = "degrees_east"
		ds.attrib["license"] = "GNU General Public License v2.0"
		ds.attrib["citation"] = "Troupin, Charles; Barth, Alexander; Helaouet, Pierre (2023). Gridded maps of Calanus finmarchicus and Calanus helgolandicus"
		ds.attrib["acknowledgement"] = "European Marine Observation Data Network (EMODnet) Biology project (EMFF/2019/1.3.1.9/Lot 6/SI2.837974), funded by the European Union under Regulation (EU) No 508/2014 of the European Parliament and of the Council of 15 May 2014 on the European Maritime and Fisheries Fund"
		ds.attrib["tool"] = "DIVAnd"
		ds.attrib["tool_version"] = DIVAndversion
		ds.attrib["tool_doi"] = "10.5281/zenodo.7016823"
		ds.attrib["language"] = "Julia $(juliaversion)"
		ds.attrib["Conventions"] = "CF-1.8"
		ds.attrib["netcdf_version"] = "4"
        ds.attrib["correlation_length"] = L
        ds.attrib["correlation_length_units"] = "degrees"
        ds.attrib["noise_to_signal_ratio"] = epsilon2
        ds.attrib["noise_to_signal_ratio_units"] = ""

        # Define variables
        nclon[:] = collect(lons)
        nclat[:] = collect(lats);

        ncaphiaid[:] = aphiaID
        nctaxonname[1:length(speciesname[1]),1] = collect.(speciesname[1]);
        nctaxonname[1:length(speciesname[2]),2] = collect.(speciesname[2]);
        nctaxon_lsid[1:length(speciesname[1]),1] = collect.(speciesname[1]);
        nctaxon_lsid[1:length(speciesname[2]),2] = collect.(speciesname[2]);

    end
end;

"""
    write_nc_error(filename, error, valex=valex, varname=varname)

Write the error field `error` in the netCDF file `filename`

## Examples
```julia-repl
julia> write_nc_error("analysis.nc", cpme_error, valex=-99.9, varname="error")
```
"""
function write_nc_error(filename::String, error::Array, varname::String="abundance"; valex=-999.9)

    Dataset(filename, "a") do ds
        ds["$(varname)_error"][:] = error
    end
end

"""
    write_geotiff(filename, field, domain)

Write the field (analysis or error) in the geoTIFF file `filename`

## Examples
```julia-repl
julia> write_geotiff("f_finmarchicus.tif", f_finmarchicus, [-20.5, 11.75, 41.25, 67.0])
```
"""
function write_geotiff(filename::String, field::Array, domain::Vector)

    ga = GeoArray(field)
    bbox!(ga, (min_x=domain[1], min_y=domain[3], max_x=domain[2], max_y=domain[4]))
    epsg!(ga, 4326)  # in WGS84
    GeoArrays.write!(filename, ga)
end

"""
    read_results(resfile)

Read the results from a netCDF file created by the function `create_nc_results_time`
    
## Examples
```julia-repl
julia> lonyear_fid, lat_year_fid, times_year, field_year_fid, error_year = 
read_results(resfile_year_fidmarchicus)
```
"""
function read_results(resfile::String)
    NCDataset(resfile, "r") do ds
        lon = ds["lon"][:]
        lat = ds["lat"][:]
        times = ds["time"][:]
        field = ds["abundance"][:]
        error = ds["error"][:]
        
        return lon::Vector{Union{Missing, Float32}}, lat::Vector{Union{Missing, Float32}}, 
            times::Vector{DateTime}, 
            field::Array{Union{Missing, Float64}, 3}, 
            error::Array{Union{Missing, Float64}, 3}
    end
end

"""
    compute_time_mean(field)

Compute the mean of the field, discarding the NaN values

## Examples
```julia-repl
julia> fmean1 = compute_time_mean(field_year_fid)
```
"""
function compute_time_mean(field::Array{Union{Missing, Float64}, 3})
    nlon, nlat, ntimes = size(field)
    fieldmean = zeros(ntimes)
    for itt = 1:ntimes
        fieldmean[itt] = mean(filter(!isnan, field[:,:,itt]))
    end
    return fieldmean
end


end
