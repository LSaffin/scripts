import numpy as np
import iris
import fgrid
from math import pi

a = 6378100 # Radius of Earth (m)

# Get spherical polar coordinates from cartesian cube
def polar_coords(cube):
    rho = a + cube.coord('altitude').points
    try:
        theta = cube.coord('longitude').points*(np.pi/180)
        phi = (90 - cube.coord('latitude').points)*(np.pi/180)
    except iris.exceptions.CoordinateNotFoundError:
        theta = cube.coord('grid_longitude').points*(np.pi/180)
        phi = (90 - cube.coord('grid_latitude').points)*(np.pi/180)
    return[rho,theta,phi]

# Calculate the volume of grid boxes
def volume(cube):
    bounds = a + cube.coord('altitude').bounds
    [rho,theta,phi] = polar_coords(cube)
    return fgrid.volume(rho,bounds,theta,phi)

# Calculate the magnitude of the vector gradient of a field
def grad(cube):
    [rho,theta,phi] = polar_coords(cube)
    return fgrid.grad(cube.data,rho,theta,phi)

# Calculate latitude and longitue in rotated system
def rotate(x,y,polelon,polelat):
    # Convert to Radians
    factor = pi/180
    x = factor*x
    y = factor*y
    polelon = factor*polelon
    polelat = factor*polelat
    sin_phi_pole = np.sin(polelat)
    cos_phi_pole = np.cos(polelat)
    if x>pi: 
        x = x - 2*pi

    # Calculate Rotated Latitude
    yr = np.arcsin(cos_phi_pole*np.cos(y)*np.cos(x-polelon) + 
                   sin_phi_pole*np.sin(y))/factor

    # Calculate Rotated Longitude
    arg1 = -np.sin(x-polelon)*np.cos(y)
    arg2 = -sin_phi_pole*np.cos(y)*np.cos(x-polelon) + cos_phi_pole*np.sin(y)
    if np.abs(arg2) < 1e-30:
        if np.abs(arg1) < 1e-30:
            xr = 0.0
        elif arg1>0:
            xr = 90.0
        else:
            xr = -90.0
    else:
        xr = np.arctan2(arg1,arg2)/factor
    return [xr,yr]

#Calculate actual Latitude and Longitude of rotated gridpoints
def unrotate(x,y,polelon,polelat):
    if (polelat>=0):
        sin_phi_pole = np.sin(pi/180*polelat)
        cos_phi_pole = np.cos(pi/180*polelat)
    else:
        sin_phi_pole = -np.sin(pi/180*polelat)
        cos_phi_pole = -np.cos(pi/180*polelat)

    Nx = np.size(x)
    Ny = np.size(y)
    x_p = np.zeros((Nx,Ny))
    y_p = np.zeros((Nx,Ny))

    #convert to radians
    x=(pi/180)*x
    y=(pi/180)*y
    sign = np.sign(x-2*pi)

    #Scale between +/- pi
    x = ((x + pi)%(2*pi)) - pi

    for i in xrange(0,Nx):
        for j in xrange(0,Ny):
    #Compute latitude using equation (4.7)
            arg = (np.cos(x[i])*np.cos(y[j])*cos_phi_pole +
                                np.sin(y[j])*sin_phi_pole)
            np.clip(arg,-1,1)
            a_phi = np.arcsin(arg)
            y_p[i,j] = (180/pi)*a_phi
                                                                            
    #Compute longitude using equation (4.8)
            term1 = (np.cos(x[i])*np.cos(y[j])*sin_phi_pole -
                                  np.sin(y[j])*cos_phi_pole)
            term2 = np.cos(a_phi)
            a_lambda = np.zeros((Nx,Ny))
            if abs(term2)<1e-5:
                a_lambda[i,j]=0.0
            else:
                arg = term1/term2
                arg = np.clip(arg,-1,1)
                a_lambda = (180/pi)*np.arccos(arg)
                a_lambda = a_lambda*sign[i]
            x_p[i,j] = a_lambda + polelon - 180
    return [x_p,y_p]

#Specify heights of theta points for terrain following coordinates 
def true_height(h,zp,k_flat):
    nz = np.size(zp)
    size = h.shape
    z = np.zeros(((nz,size[0],size[1])))
    eta = zp/zp[nz-1]
    eta_i = eta[k_flat]
    for k in xrange(0,nz):
        z[k,:,:] = eta[k] * zp[nz-1]
    for k in xrange(0,k_flat):
        z[k,:,:] += h*((1-(eta[k]/eta_i))**2)
    return z

