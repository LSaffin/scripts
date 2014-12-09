      PROGRAM caltra

C     ********************************************************************
C     *                                                                  *
C     * Calculates trajectories                                          *
C     *                                                                  *
C     *	Heini Wernli	   first version:       April 1993               *
C     * Michael Sprenger   major upgrade:       2008-2009                *
C     *                                                                  *
C     ********************************************************************

      implicit none
      
c     --------------------------------------------------------------------
c     Declaration of parameters
c     --------------------------------------------------------------------

c     Maximum number of levels for input files
      integer   nlevmax
      parameter	(nlevmax=100)

c     Maximum number of input files (dates, length of trajectories)
      integer   ndatmax
      parameter	(ndatmax=500)

c     Numerical epsilon (for float comparison)
      real      eps
      parameter (eps=0.001)

c     Distance in m between 2 lat circles 
      real	deltay
      parameter	(deltay=1.112E5)
      
c     Numerical method for the integration (0=iterative Euler, 1=Runge-Kutta)
      integer   imethod
      parameter (imethod=1)

c     Number of iterations for iterative Euler scheme
      integer   numit
      parameter (numit=3)

c     Input and output format for trajectories (see iotra.f)
      integer   inpmode
      integer   outmode

c     Filename prefix (typically 'P')
      character*1  prefix
      parameter   (prefix='P')

c     --------------------------------------------------------------------
c     Declaration of variables
c     --------------------------------------------------------------------

c     Input parameters
      integer                                fbflag         
      ! Flag for forward/backward mode
      integer                                numdat          
      ! Number of input files
      character*11                           dat(ndatmax)    
      ! Dates of input files
      real                                   timeinc         
      ! Time increment between input files
      real                                   per             
      ! Periodicity (=0 if none)
      integer                                ntra            
      ! Number of trajectories
      character*80                           cdfname         
      ! Name of output files
      real                                   ts              
      ! Time step
      real                                   tst,ten         
      ! Shift of start and end time relative to first data file
      integer                                deltout         
      ! Output time interval (in minutes)
      integer                                jflag           
      ! Jump flag (if =1 ground-touching trajectories reenter atmosphere)
      real                                   wfactor         
      ! Factor for vertical velocity field
      character*80                           strname         
      ! File with start positions
      character*80                           timecheck       
      ! Either 'yes' or 'no'

c     Trajectories
      integer                                ncol            
      ! Number of columns for insput trajectories
      real,allocatable, dimension (:,:,:) :: trainp          
      ! Input start coordinates (ntra,1,ncol)
      real,allocatable, dimension (:,:,:) :: traout          
      ! Output trajectories (ntra,ntim,4)
      integer                                reftime(6)      ! Reference date
      character*80                           vars(200)       ! Field names
      real,allocatable, dimension (:)     :: xx0,yy0,pp0     
      ! Position of air parcels
      integer,allocatable, dimension (:)  :: leftflag        
      ! Flag for domain-leaving
      real                                   xx1,yy1,pp1     
      ! Updated position of air parcel
      integer                                leftcount       
      ! Number of domain leaving trajectories
      integer                                ntim            
      ! Number of output time steps

c     Meteorological fields
      real,allocatable, dimension (:)     :: spt0,spt1       ! Surface pressure
      real,allocatable, dimension (:)     :: uut0,uut1       ! Zonal wind
      real,allocatable, dimension (:)     :: vvt0,vvt1       ! Meridional wind
      real,allocatable, dimension (:)     :: wwt0,wwt1       ! Vertical wind
      real,allocatable, dimension (:)     :: p3t0,p3t1       ! 3d-pressure 

c     Grid description
      real                                   pollon,pollat   
      ! Longitude/latitude of pole
      real                                   ak(nlevmax)     
      ! Vertical layers and levels
      real                                   bk(nlevmax) 
      real                                   xmin,xmax       
      ! Zonal grid extension
      real                                   ymin,ymax       
      ! Meridional grid extension
      integer                                nx,ny,nz        ! Grid dimensions
      real                                   dx,dy           
      ! Horizontal grid resolution
      integer                                hem             
      ! Flag for hemispheric domain
      real                                   mdv             
      ! Missing data value

c     Auxiliary variables                 
      real                                   delta,rd
      integer	                             itm,iloop,i,j,k,filo,lalo
      integer                                ierr,stat
      integer                                cdfid,fid
      real	                             tstart,time0,time1,time
      real                                   reltpos0,reltpos1
      real                                   xind,yind,pind,pp,sp,stagz
      character*80                           filename,varname
      integer                                reftmp(6)
      character                              ch
      real                                   frac,tload
      integer                                itim
      real                                   lon,lat,rlon,rlat

c     Externals 
      real                                   lmtolms        ! Grid rotation
      real                                   phtophs    
      real                                   lmstolm
      real                                   phstoph        
      external                               lmtolms,phtophs
      external                               lmstolm,phstoph

c     --------------------------------------------------------------------
c     Start of program, Read parameters
c     --------------------------------------------------------------------

c     ---- INPUT PARAMETERS -----------------------------------
c     fbflag = 1 or -1
c     numdat = number of input files
c     timeinc = 1.
c     ts = timestep in seconds
c     jflag = 0 or 1
c     wfactor = 1

c     Write some status information
c     ---- CONSTANT GRID PARAMETERS ---------------------------
c     xmin,xmax,ymin,ymax = grid corners in rotated coordinates
c     dx,dy = 0.11

c     --------------------------------------------------------------------
c     Initialize the trajectory calculation
c     --------------------------------------------------------------------

c     Read start coordinates
c     Rotate coordinates
      do i=1,ntra
         
         lon = xx0(i)
         lat = yy0(i)
         
         if ( abs(pollat-90.).gt.eps) then
            rlon = lmtolms(lat,lon,pollat,pollon)
            rlat = phtophs(lat,lon,pollat,pollon)
         else
            rlon = lon
            rlat = lat
         endif
         
         xx0(i) = rlon
         yy0(i) = rlat
         
      enddo

c     Set sign of time range
      reftime(6) = fbflag * reftime(6)

C     Save starting positions 
      itim = 1
      do i=1,ntra
         traout(i,itim,1) = 0.
         traout(i,itim,2) = xx0(i)
         traout(i,itim,3) = yy0(i)
         traout(i,itim,4) = pp0(i)
      enddo
      
c     Init the flag and the counter for trajectories leaving the domain
      leftcount=0
      do i=1,ntra
         leftflag(i)=0
      enddo

C     Convert time shifts <tst,ten> from <hh.mm> into fractional time
      call hhmm2frac(tst,frac)
      tst = frac
      call hhmm2frac(ten,frac)
      ten = frac

c     -----------------------------------------------------------------------
c     Loop to calculate trajectories
c     -----------------------------------------------------------------------   

c     Read wind fields and vertical grid from first file
      call frac2hhmm(tstart,tload)

c     Loop over all input files (time step is <timeinc>)
      do itm=1,numdat-1

c       Calculate actual and next time
        time0 = tstart+real(itm-1)*timeinc*fbflag
        time1 = time0+timeinc*fbflag

c       Copy old velocities and pressure fields to new ones       
        do i=1,nx*ny*nz
           uut0(i)=uut1(i)
           vvt0(i)=vvt1(i)
           wwt0(i)=wwt1(i)
           p3t0(i)=p3t1(i)
        enddo
        do i=1,nx*ny
           spt0(i)=spt1(i)
        enddo

c       Read wind fields and surface pressure at next time
        call frac2hhmm(time1,tload)
        
C       Determine the first and last loop indices
        if (numdat.eq.2) then
          filo = nint(tst/ts)+1
          lalo = nint((timeinc-ten)/ts) 
        elseif ( itm.eq.1 ) then
          filo = nint(tst/ts)+1
          lalo = nint(timeinc/ts)
        else if (itm.eq.numdat-1) then
          filo = 1
          lalo = nint((timeinc-ten)/ts)
        else
          filo = 1
          lalo = nint(timeinc/ts)
        endif

c       Split the interval <timeinc> into computational time steps <ts>
        do iloop=filo,lalo

C      Calculate relative time position in the interval timeinc 
c      (0=beginning, 1=end)
          reltpos0 = ((real(iloop)-1.)*ts)/timeinc
          reltpos1 = real(iloop)*ts/timeinc

C         Initialize counter for domain leaving trajectories
          leftcount=0

c         Timestep for all trajectories
          do i=1,ntra

C           Check if trajectory has already left the data domain
            if (leftflag(i).ne.1) then	

c             Iterative Euler timestep (x0,y0,p0 -> x1,y1,p1)
              if (imethod.eq.1) then
                 call euler(
     >               xx1,yy1,pp1,leftflag(i),
     >               xx0(i),yy0(i),pp0(i),reltpos0,reltpos1,
     >               ts*3600,numit,jflag,mdv,wfactor,fbflag,
     >               spt0,spt1,p3t0,p3t1,uut0,uut1,vvt0,vvt1,wwt0,wwt1,
     >               xmin,ymin,dx,dy,per,hem,nx,ny,nz)

c             Runge-Kutta timestep (x0,y0,p0 -> x1,y1,p1)
              else if (imethod.eq.2) then
                 call runge(
     >               xx1,yy1,pp1,leftflag(i),
     >               xx0(i),yy0(i),pp0(i),reltpos0,reltpos1,
     >               ts*3600,numit,jflag,mdv,wfactor,fbflag,
     >               spt0,spt1,p3t0,p3t1,uut0,uut1,vvt0,vvt1,wwt0,wwt1,
     >               xmin,ymin,dx,dy,per,hem,nx,ny,nz)

              endif

c             Update trajectory position, or increase number 
c             of trajectories leaving domain
              if (leftflag(i).eq.1) then
                leftcount=leftcount+1
              else
                xx0(i)=xx1      
                yy0(i)=yy1
                pp0(i)=pp1
              endif

c          Trajectory has already left data domain (mark as <mdv>)
           else
              xx0(i)=mdv
              yy0(i)=mdv
              pp0(i)=mdv
              
           endif

          enddo

C         Save positions only every deltout minutes
          delta = aint(iloop*60*ts/deltout)-iloop*60*ts/deltout
          if (abs(delta).lt.eps) then
            time = time0+reltpos1*timeinc*fbflag
            itim = itim + 1
            do i=1,ntra
               call frac2hhmm(time,tload)
               traout(i,itim,1) = tload
               traout(i,itim,2) = xx0(i)
               traout(i,itim,3) = yy0(i)
               traout(i,itim,4) = pp0(i)
            enddo
          endif

        enddo

      enddo

c     *******************************************************************
c     * Time step : either Euler or Runge-Kutta                         *
c     *******************************************************************

C     Time-step from (x0,y0,p0) to (x1,y1,p1)
C
C     (x0,y0,p0) input	coordinates (long,lat,p) for starting point
C     (x1,y1,p1) output	coordinates (long,lat,p) for end point
C     deltat	 input	timestep in seconds
C     numit	 input	number of iterations
C     jump	 input  flag (=1 trajectories don't enter the ground)
C     left	 output	flag (=1 if trajectory leaves data domain)

c     -------------------------------------------------------------------
c     Iterative Euler time step
c     -------------------------------------------------------------------

      subroutine euler(x1,y1,p1,left,x0,y0,p0,reltpos0,reltpos1,
     >                 deltat,numit,jump,mdv,wfactor,fbflag,
     >		       spt0,spt1,p3d0,p3d1,uut0,uut1,vvt0,vvt1,wwt0,wwt1,
     >                 xmin,ymin,dx,dy,per,hem,nx,ny,nz)

      implicit none

c     Declaration of subroutine parameters
      integer      nx,ny,nz
      real         x1,y1,p1
      integer      left
      real	   x0,y0,p0
      real         reltpos0,reltpos1
      real   	   deltat
      integer      numit
      integer      jump
      real         wfactor
      integer      fbflag
      real     	   spt0(nx*ny)   ,spt1(nx*ny)
      real         uut0(nx*ny*nz),uut1(nx*ny*nz)
      real 	   vvt0(nx*ny*nz),vvt1(nx*ny*nz)
      real         wwt0(nx*ny*nz),wwt1(nx*ny*nz)
      real         p3d0(nx*ny*nz),p3d1(nx*ny*nz)
      real         xmin,ymin,dx,dy
      real         per
      integer      hem
      real         mdv

c     Numerical and physical constants
      real         deltay
      parameter    (deltay=1.112E5)  ! Distance in m between 2 lat circles
      real         pi                       
      parameter    (pi=3.1415927)    ! Pi

c     Auxiliary variables
      real         xmax,ymax
      real	   xind,yind,pind
      real	   u0,v0,w0,u1,v1,w1,u,v,w,sp
      integer	   icount
      character    ch

c     Externals    
      real         int_index4
      external     int_index4

c     Reset the flag for domain-leaving
      left=0

c     Set the east-north boundary of the domain
      xmax = xmin+real(nx-1)*dx
      ymax = ymin+real(ny-1)*dy

C     Interpolate wind fields to starting position (x0,y0,p0)
      call get_index4 (xind,yind,pind,x0,y0,p0,reltpos0,
     >                 p3d0,p3d1,spt0,spt1,3,
     >                 nx,ny,nz,xmin,ymin,dx,dy,mdv)
      u0 = int_index4(uut0,uut1,nx,ny,nz,xind,yind,pind,reltpos0,mdv)
      v0 = int_index4(vvt0,vvt1,nx,ny,nz,xind,yind,pind,reltpos0,mdv)
      w0 = int_index4(wwt0,wwt1,nx,ny,nz,xind,yind,pind,reltpos0,mdv)

c     Force the near-surface wind to zero
      if (pind.lt.1.) w0=w0*pind

C     For first iteration take ending position equal to starting position
      x1=x0
      y1=y0
      p1=p0

C     Iterative calculation of new position
      do icount=1,numit

C        Calculate new winds for advection
         call get_index4 (xind,yind,pind,x1,y1,p1,reltpos1,
     >                    p3d0,p3d1,spt0,spt1,3,
     >                    nx,ny,nz,xmin,ymin,dx,dy,mdv)
         u1 = int_index4(uut0,uut1,nx,ny,nz,xind,yind,pind,reltpos1,mdv)
         v1 = int_index4(vvt0,vvt1,nx,ny,nz,xind,yind,pind,reltpos1,mdv)
         w1 = int_index4(wwt0,wwt1,nx,ny,nz,xind,yind,pind,reltpos1,mdv)

c        Force the near-surface wind to zero
         if (pind.lt.1.) w1=w1*pind
 
c        Get the new velocity in between
         u=(u0+u1)/2.
         v=(v0+v1)/2.
         w=(w0+w1)/2.
         
C        Calculate new positions
         x1 = x0 + fbflag*u*deltat/(deltay*cos(y0*pi/180.))
         y1 = y0 + fbflag*v*deltat/deltay
         p1 = p0 + fbflag*wfactor*w*deltat/100.

c       Handle pole problems (crossing and near pole trajectory)
        if ((hem.eq.1).and.(y1.gt.90.)) then
          y1=180.-y1
          x1=x1+per/2.
        endif
        if ((hem.eq.1).and.(y1.lt.-90.)) then
          y1=-180.-y1
          x1=x1+per/2.
        endif
        if (y1.gt.89.99) then
           y1=89.99
        endif

c       Handle crossings of the dateline
        if ((hem.eq.1).and.(x1.gt.xmin+per-dx)) then
           x1=xmin+amod(x1-xmin,per)
        endif
        if ((hem.eq.1).and.(x1.lt.xmin)) then
           x1=xmin+per+amod(x1-xmin,per)
        endif

C       Interpolate surface pressure to actual position
        call get_index4 (xind,yind,pind,x1,y1,1050.,reltpos1,
     >                   p3d0,p3d1,spt0,spt1,3,
     >                   nx,ny,nz,xmin,ymin,dx,dy,mdv)
        sp = int_index4 (spt0,spt1,nx,ny,1,xind,yind,1.,reltpos1,mdv)

c       Handle trajectories which cross the lower boundary (jump flag)
        if ((jump.eq.1).and.(p1.gt.sp)) p1=sp-10.
 
C       Check if trajectory leaves data domain
        if ( ( (hem.eq.0).and.(x1.lt.xmin)    ).or.
     >       ( (hem.eq.0).and.(x1.gt.xmax-dx) ).or.
     >         (y1.lt.ymin).or.(y1.gt.ymax).or.(p1.gt.sp) )
     >  then
          left=1
          goto 100
        endif

      enddo

c     Exit point for subroutine
 100  continue

      return

      end

c     -------------------------------------------------------------------
c     Runge-Kutta (4th order) time-step
c     -------------------------------------------------------------------

      subroutine runge(x1,y1,p1,left,x0,y0,p0,reltpos0,reltpos1,
     >                 deltat,numit,jump,mdv,wfactor,fbflag,
     >		       spt0,spt1,p3d0,p3d1,uut0,uut1,vvt0,vvt1,wwt0,wwt1,
     >                 xmin,ymin,dx,dy,per,hem,nx,ny,nz)

      implicit none

c     Declaration of subroutine parameters
      integer      nx,ny,nz
      real         x1,y1,p1
      integer      left
      real	   x0,y0,p0
      real         reltpos0,reltpos1
      real   	   deltat
      integer      numit
      integer      jump
      real         wfactor
      integer      fbflag
      real     	   spt0(nx*ny)   ,spt1(nx*ny)
      real         uut0(nx*ny*nz),uut1(nx*ny*nz)
      real 	   vvt0(nx*ny*nz),vvt1(nx*ny*nz)
      real         wwt0(nx*ny*nz),wwt1(nx*ny*nz)
      real         p3d0(nx*ny*nz),p3d1(nx*ny*nz)
      real         xmin,ymin,dx,dy
      real         per
      integer      hem
      real         mdv

c     Numerical and physical constants
      real         deltay
      parameter    (deltay=1.112E5)  ! Distance in m between 2 lat circles
      real         pi                       
      parameter    (pi=3.1415927)    ! Pi

c     Auxiliary variables
      real         xmax,ymax
      real	   xind,yind,pind
      real	   u0,v0,w0,u1,v1,w1,u,v,w,sp
      integer	   icount,n
      real         xs,ys,ps,xk(4),yk(4),pk(4)
      real         reltpos

c     Externals    
      real         int_index4
      external     int_index4

c     Reset the flag for domain-leaving
      left=0

c     Set the esat-north bounray of the domain
      xmax = xmin+real(nx-1)*dx
      ymax = ymin+real(ny-1)*dy

c     Apply the Runge Kutta scheme
      do n=1,4
 
c       Get intermediate position and relative time
        if (n.eq.1) then
          xs=0.
          ys=0.
          ps=0.
          reltpos=reltpos0
        else if (n.eq.4) then
          xs=xk(3)
          ys=yk(3)
          ps=pk(3)
          reltpos=reltpos1
        else
          xs=xk(n-1)/2.
          ys=yk(n-1)/2.
          ps=pk(n-1)/2.
          reltpos=(reltpos0+reltpos1)/2.
        endif
        
C       Calculate new winds for advection
        call get_index4 (xind,yind,pind,x0+xs,y0+ys,p0+ps,reltpos,
     >                   p3d0,p3d1,spt0,spt1,3,
     >                   nx,ny,nz,xmin,ymin,dx,dy,mdv)
        u = int_index4 (uut0,uut1,nx,ny,nz,xind,yind,pind,reltpos,mdv)
        v = int_index4 (vvt0,vvt1,nx,ny,nz,xind,yind,pind,reltpos,mdv)
        w = int_index4 (wwt0,wwt1,nx,ny,nz,xind,yind,pind,reltpos,mdv)
         
c       Force the near-surface wind to zero
        if (pind.lt.1.) w1=w1*pind
 
c       Update position and keep them
        xk(n)=fbflag*u*deltat/(deltay*cos(y0*pi/180.))
        yk(n)=fbflag*v*deltat/deltay
        pk(n)=fbflag*w*deltat*wfactor/100.

      enddo
 
C     Calculate new positions
      x1=x0+(1./6.)*(xk(1)+2.*xk(2)+2.*xk(3)+xk(4))
      y1=y0+(1./6.)*(yk(1)+2.*yk(2)+2.*yk(3)+yk(4))
      p1=p0+(1./6.)*(pk(1)+2.*pk(2)+2.*pk(3)+pk(4))

c     Handle pole problems (crossing and near pole trajectory)
      if ((hem.eq.1).and.(y1.gt.90.)) then
         y1=180.-y1
         x1=x1+per/2.
      endif
      if ((hem.eq.1).and.(y1.lt.-90.)) then
         y1=-180.-y1
         x1=x1+per/2.
      endif
      if (y1.gt.89.99) then
         y1=89.99
      endif
      
c     Handle crossings of the dateline
      if ((hem.eq.1).and.(x1.gt.xmin+per-dx)) then
         x1=xmin+amod(x1-xmin,per)
      endif
      if ((hem.eq.1).and.(x1.lt.xmin)) then
         x1=xmin+per+amod(x1-xmin,per)
      endif
      
C     Interpolate surface pressure to actual position
      call get_index4 (xind,yind,pind,x1,y1,1050.,reltpos1,
     >                 p3d0,p3d1,spt0,spt1,3,
     >                 nx,ny,nz,xmin,ymin,dx,dy,mdv)
      sp = int_index4 (spt0,spt1,nx,ny,1,xind,yind,1,reltpos,mdv)

c     Handle trajectories which cross the lower boundary (jump flag)
      if ((jump.eq.1).and.(p1.gt.sp)) p1=sp-10.
      
C     Check if trajectory leaves data domain
      if ( ( (hem.eq.0).and.(x1.lt.xmin)    ).or.
     >     ( (hem.eq.0).and.(x1.gt.xmax-dx) ).or.
     >       (y1.lt.ymin).or.(y1.gt.ymax).or.(p1.gt.sp) )
     >then
         left=1
         goto 100
      endif
      
c     Exit point fdor subroutine
 100  continue

      return
      end
