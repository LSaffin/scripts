"""
Similar to the first plot but with lines for individual physics schemes in
reduced precision. Show error vs time for one precision and error vs precision
for one time. Repeat for SPPT off and on.
"""

import matplotlib.pyplot as plt
import iris
import iris.plot as iplt
from irise.plot.util import legend, multilabel
from myscripts.statistics import ensemble_std_dev
from myscripts.models.speedy import datadir, physics_schemes
from myscripts.projects.ithaca.precision_errors import decode_name


def main():
    # Specify which files and variable to compare
    path = datadir
    factor = 0.01
    variable = 'geopotential_height'

    time_cs = iris.Constraint(forecast_period=14)
    precision_cs = iris.Constraint(precision=10)

    # Create a one by two grid with shared x and y axes along rows and columns
    fig, axes = plt.subplots(nrows=1, ncols=2, sharex='col', sharey='all',
                             figsize=[16, 5])
    filename = 'precision_errors_{}_500hpa_adjusted.nc'.format(variable)
    make_plot_pair(path + filename, time_cs, precision_cs, axes, factor)

    # Add ensemble spread to the panels
    path = datadir + 'stochastic/ensembles/'
    name = variable.replace('_', ' ').title()
    cs = iris.Constraint(name=name, pressure=500)
    ensemble = iris.load_cube(path + 'rp_physics_52b.nc', cs)
    ensemble.coord('forecast_period').convert_units('days')
    ensemble_spread = ensemble_std_dev(ensemble)

    plt.axes(axes[0])
    iplt.plot(ensemble_spread, ':k', alpha=0.5)

    plt.axes(axes[1])
    spread_at_time = ensemble_spread.extract(time_cs)
    plt.axhline(spread_at_time.data, linestyle=':', color='k', alpha=0.5)

    plt.xlim(5, 23)
    plt.ylim(0, 110)

    axes[0].set_title('10 sbits')
    axes[1].set_title('14 Days')
    plt.show()

    return


def make_plot_pair(filename, time_cs, precision_cs, axes, factor):
    cubes = iris.load(filename)
    for cube in cubes:
        cube.coord('forecast_period').convert_units('days')

    plt.axes(axes[0])
    multilabel(axes[0], 0, factor=factor)
    make_plot(cubes, precision_cs)

    legend(key=lambda x: physics_schemes[x[0]].idx,
           ncol=2, title='Parametrization Schemes')
    plt.xlabel('Forecast Lead Time [days]')
    plt.ylabel('RMS Error in Geopotential Height [m]')

    plt.axes(axes[1])
    multilabel(axes[1], 1, factor=factor)
    make_plot(cubes, time_cs)

    plt.xlabel('Precision [sbits]')

    return


def make_plot(cubes, cs):
    subcubes = cubes.extract(cs)
    for cube in subcubes:
        variable, scheme = decode_name(cube.name())
        plp = physics_schemes[scheme]
        plp.plot(cube, label=scheme)
    return


if __name__ == '__main__':
    main()
