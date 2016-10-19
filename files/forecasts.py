import iris
from mymodule import convert
import files
from files import stash_maps


# Filename parameters
path = '/projects/diamet/lsaffi/'
strlen = 3
inpath = path + 'xkcqa/xkcqa_p'
outpath = path + 'iop8/'
time = 'hours since 2011-12-07 12:00:00'
nt = 36

# Surface altitude file
surf = '/projects/diamet/lsaffi/nae_orography.nc'

# Define which area of grid to subset
slices = slice(0, 50), slice(15, 345), slice(15, 585)

# Load basis cube
basis_cube = iris.load_cube(path + 'temp/prognostics_001.nc',
                            'air_potential_temperature')

# NDDiag names to extract
nddiag_names = ['x_wind', 'y_wind', 'upward_air_velocity',
                'specific_humidity',
                'mass_fraction_of_cloud_liquid_water_in_air',
                'mass_fraction_of_cloud_ice_in_air']

# Single level diagnostic names to extract
diag_names = ['boundary_layer_type', 'air_pressure_at_sea_level',
              'atmosphere_boundary_layer_thickness',
              'convective_rainfall_amount', 'stratiform_rainfall_amount']


def main():
    for n in range(nt):
        print n
        # Tracers
        infile = inpath + 'a' + str(n).zfill(strlen)
        outfile = outpath + 'pv_tracers_' + str(n + 1).zfill(strlen)
        tracers(infile, outfile, stash_maps=[stash_maps.pv_tracers],
                slices=slices, time=time)

        # Prognostics
        nddiag_name = inpath + 'b' + str(n).zfill(strlen)
        progs_name = inpath + 'c' + str(n).zfill(strlen)
        outfile = outpath + 'prognostics_' + str(n + 1).zfill(strlen)
        prognostics(nddiag_name, progs_name, outfile, slices=slices, time=time)

        # Diagnostics
        infile = inpath + 'd' + str(n).zfill(strlen)
        outfile = outpath + 'diagnostics_' + str(n + 1).zfill(strlen)
        diagnostics(infile, outfile, slices=slices[1:], time=time)


def tracers(infile, outfile, **kwargs):
    cubes = iris.load(infile)
    cubes = files.redo_cubes(cubes, basis_cube, **kwargs)
    iris.save(cubes, outfile + '.nc')


def prognostics(nddiag_name, progs_name, outfile, **kwargs):
    # Extract u, v, w, q, q_cl and q_cf from the NDdiag file
    cubes_all = iris.load(nddiag_name)
    cubes = convert.calc(nddiag_names, cubes_all)

    # Extract rho, theta and exner on theta levels from prognostics file
    _prognostics(cubes, progs_name)

    # Calculate derived diagnostics
    # Add altitude to prognostic variables
    P = cubes_all.extract('air_pressure')
    z_rho = P[0].coord('altitude')
    z_theta = P[1].coord('altitude')
    files.derived(cubes, z_rho, z_theta)

    cubes = files.redo_cubes(cubes, basis_cube, **kwargs)

    iris.save(cubes, outfile + '.nc')


def diagnostics(infile, outfile, **kwargs):
    cubes = files.load_cubes(infile, diag_names)
    cubes = files.redo_cubes(cubes, basis_cube, **kwargs)

    # Remove names from bl type
    bl_type = cubes.extract('boundary_layer_type')[0]
    del bl_type.attributes['names']

    iris.save(cubes, outfile + '.nc')


def _prognostics(newcubes, filename):
    # Load the cubes
    cubes = iris.load(filename)

    # Extract theta
    theta = convert.calc('air_potential_temperature', cubes)

    # Remap rho to theta-levels
    rho = convert.calc('unknown', cubes)
    rho.rename('air_density')
    rho.units = 'kg m-3'

    # Extract exner on theta levels (ignore on rho levels)
    exner = cubes.extract('dimensionless_exner_function')[1]

    # Add the prognostics to the newcubelist
    [newcubes.append(cube) for cube in [rho, theta, exner]]

    return


if __name__ == '__main__':
    main()
