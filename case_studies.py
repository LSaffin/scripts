"""Forecast objects for
"""
from datetime import datetime, timedelta
from mymodule.forecast import Forecast


def iop5():
    job_name = 'xjjhq'
    start_time = datetime(2011, 11, 28, 12)
    mapping = {start_time + timedelta(hours=lead_time):
               'datadir/' + job_name + '/' + job_name + 'a_' +
               str(lead_time).zfill(3) + '.pp'
               for lead_time in xrange(1, 37)}
    return Forecast(start_time, mapping)


def iop5b():
    job_name = 'xjjhq'
    start_time = datetime(2011, 11, 28, 12)
    mapping = {}
    for lead_time in xrange(1, 37):
        tracers_file = ('datadir/' + job_name + '/' + job_name + 'b_' +
                        str(lead_time).zfill(3) + '.pp')
        prognostics_file = ('datadir/' + job_name + '/' + job_name +
                            'b_nddiag_' + str(lead_time).zfill(3) + '.pp')
        mapping[start_time + timedelta(hours=lead_time)] = [tracers_file,
                                                            prognostics_file]

    return Forecast(start_time, mapping)


def iop8():
    job_name = 'xkcqa'
    start_time = datetime(2011, 12, 7, 12)
    mapping = {start_time + timedelta(hours=lead_time):
               'datadir/' + job_name + '/' + job_name + 'a*' +
               str(lead_time).zfill(3) + '.pp'
               for lead_time in xrange(1, 37)}

    return Forecast(start_time, mapping)
