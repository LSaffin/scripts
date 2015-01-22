! Subroutine BALNC
! Calculates Geopotential Height and Streamfunction by inverting an 
! input PV field using the Charney (1955) balance equation.
      SUBROUTINE balnc(fco, aps, ac, h, s, qe, tha, pe, part,           &
     &                 thrs, maxx, maxxt, omegs, omegh,                 &
     &                 nl, ny, nx)
      
      IMPLICIT NONE

      INTEGER nx,ny,nl
      REAL    fco(ny,nx),                                               &
              ! Coriolis Parameter
     &        aps(ny,nx),                                               &
              ! ap ! Cos(Latitude)
     &        ac(ny,5),                                                 &
              ! a  ! Coefficients for 2-D Laplacian operator
     &        h(ny,nx,nl),                                              &
              ! hz ! Geopotential Height
     &        s(ny,nx,nl),                                              &
              ! si ! Streamfunction
     &        qe(ny,nx,nl),                                             &
              ! q  ! PV (/0.01 PVU)
     &        tha(ny,nx,2),                                             &
!            THT(i,j,m)= Boundary theta, m=1 is lower boundary (midway
!            between k=1 and k=2) and m=2 is upper boundary
!            (between k=NL-1 and k=NL)
     &        pe(nl),                                                   &
              ! pi ! Exner Function
     &        part,                                                     &
              ! prt ! Relaxation Parameter
     &        thrs,                                                     &
              ! thr ! Threshold parameter
     &        maxx,                                                     &
              ! max ! Maximum Iterations
     &        maxxt,                                                    &
              ! maxt ! Maximum Cycles
     &        omegs,                                                    &
              ! OMEGAS ! Relaxation Parameter for 2-D Poisson Equation
     &        omegh
              ! OMEGAH ! Relaxation Parameter for 3-D Poisson Equation

CF2PY      INTEGER, INTENT(HIDE)    :: nl
CF2PY      INTEGER, INTENT(HIDE)    :: ny
CF2PY      INTEGER, INTENT(HIDE)    :: nx
CF2PY      REAL, INTENT(IN)         :: fco(ny,nx)
CF2PY      REAL, INTENT(IN)         :: aps(ny,nx)
CF2PY      REAL, INTENT(IN)         :: ac(ny,5)
CF2PY      REAL, INTENT(IN OUT)     :: h(ny,nx,nl)
CF2PY      REAL, INTENT(IN OUT)     :: s(ny,nx,nl)
CF2PY      REAL, INTENT(IN OUT)     :: qe(ny,nx,nl)
CF2PY      REAL, INTENT(IN OUT)     :: tha(ny,nx,2)
CF2PY      REAL, INTENT(IN)         :: pe(nl)
CF2PY      REAL, INTENT(IN)         :: part
CF2PY      REAL, INTENT(IN)         :: thrs
CF2PY      INTEGER, INTENT(IN)      :: maxx
CF2PY      INTEGER, INTENT(IN)      :: maxxt
CF2PY      REAL, INTENT(IN)         :: omegs
CF2PY      REAL, INTENT(IN)         :: omegh

!     Local Variables
      REAL :: mi,zm,rh(ny,nx,nl),zpl(ny,nx),zpp(ny),rs,gpts,            &
     &        stb(ny,nx,nl),asi(ny,nx,nl),bb(nl),bh(nl),bl(nl),         &
     &        vor,OLD(ny,nx,nl),dpi2(nl),nlco(ny,nx),coef(ny,nl),       &
     &        dh(ny,nx,nl),znl,rhs(ny,nx,nl),delh(ny,nx,nl),            &
     &        dsi(ny,nx,nl),vozro(nl),spzro(nl),maxhz(nl),              &
     &        minvor(nl),maxvor(nl),                                    &
     &        betas,dhmax,rha,rhst,sxx,sxy,syy,                         &
     &        zhl,zhp,zmrs,zl,zsl,zsp,zp

      INTEGER :: I,J,K,igtz,ihm,iitot,iltz,insq,                        &
     &           itc,itc1,itcm,itcold,itct,jhm,khm

      LOGICAL :: it,icon

!-----------------------------------------------------------------------!
!                          START OF SUBROUTINE                          !
!-----------------------------------------------------------------------!
      mi=9999.90
      gpts=FLOAT(ny*nx*(nl-2))

      iltz=0
      igtz=0
      insq=0
      itct=0
      itc1=0
      itc=0
      iitot=0
      itcold=0

      DO k=1,nl
        vozro(k)=0.
        minvor(k)=100000.
        maxvor(k)=-100000.
      END DO

      DO i=2,ny-1
        zpp(i)=1./16.
        DO  j=2,nx-1
          zpl(i,j)=1./(16.*aps(i,j)*aps(i,j))
          nlco(i,j)=2./( aps(i,j)*aps(i,j) )
        END DO
      END DO

      DO k=1,nl
        bb(k)=0.
        bh(k)=0.
        bl(k)=0.
      END DO

      DO k=2,nl-1
        bb(k)=-2./( (pe(k+1)-pe(k))*(pe(k)-pe(k-1)) )
        bh(k)=2./( (pe(k+1)-pe(k))*(pe(k+1)-pe(k-1)) )
        bl(k)=2./( (pe(k)-pe(k-1))*(pe(k+1)-pe(k-1)) )
        dpi2(k)=(pe(k+1) - pe(k-1))/2.
        DO i=1,ny
          coef(i,k)=ac(i,3)/bb(k)
        END DO
      END DO

      DO k=1,nl
        maxhz(k)=0
      END DO

      DO k=1,nl
        DO j=1,nx
          DO i=1,ny
            OLD(i,j,k)=h(i,j,k)
            IF (h(i,j,k)>maxhz(k)) THEN
              maxhz(k)=h(i,j,k)
            END IF
          END DO
        END DO
      END DO
!-----------------------------------------------------------------------!

  900 CONTINUE
      IF (iitot == 0) GO TO 700
      itcm=0
      itc1=0
      DO k=1,nl
        spzro(k)=0.
      END DO

      DO k=2,nl-1
        DO j=2,nx-1
          DO i=2,ny-1
            OLD(i,j,k)=s(i,j,k)
            IF (k == 2) THEN
              OLD(i,j,1)=s(i,j,1)
            ELSE IF (k == nl-1) THEN
              OLD(i,j,nl)=s(i,j,nl)
            END IF
            delh(i,j,k)= ac(i,1)*h(i-1,j,k) + ac(i,2)*h(i,j-1,k) +      &
     &                   ac(i,3)*h(i,j,k)   + ac(i,4)*h(i,j+1,k) +      &
     &                   ac(i,5)*h(i+1,j,k)

            stb(i,j,k)=bl(k)*h(i,j,k-1) + bh(k)*h(i,j,k+1) +            &
     &                 bb(k)*h(i,j,k)

            IF (stb(i,j,k) <= 0.0001) THEN
              stb(i,j,k)=0.0001
               
!     Modify boundary theta (k=2) or PV if static stability
!     becomes too small. Theta becomes smaller; PV becomes larger
!     by a small amount (0.2 nondimensionally, which works out to
!     be perhaps a tenth of a degree K.
               
              IF (k == 2) THEN
                tha(i,j,1)=tha(i,j,1)-0.2
              END IF
              qe(i,j,k)=qe(i,j,k) + 0.2/(pe(k)-pe(k+1))
              spzro(k)=spzro(k) + 1
            END IF
            sxx=s(i,j+1,k) + s(i,j-1,k) - 2.*s(i,j,k)
            syy=s(i-1,j,k) + s(i+1,j,k) - 2.*s(i,j,k)
            sxy=( s(i-1,j+1,k) - s(i-1,j-1,k) -                         &
     &            s(i+1,j+1,k) + s(i+1,j-1,k)  )/4.
            betas=0.25*((fco(i-1,j)-fco(i+1,j))*                        &
     &                  (s(i-1,j,k)-s(i+1,j,k)) +                       & 
     &                  (fco(i,j+1)-fco(i,j-1))*                        &
     &                  (s(i,j+1,k)-s(i,j-1,k)) )
            zhp=h(i-1,j,k+1)-h(i+1,j,k+1)-h(i-1,j,k-1)+h(i+1,j,k-1)
            zhl=h(i,j+1,k+1)-h(i,j-1,k+1)-h(i,j+1,k-1)+h(i,j-1,k-1)
            zsp=s(i-1,j,k+1)-s(i+1,j,k+1)-s(i-1,j,k-1)+s(i+1,j,k-1)
            zsl=s(i,j+1,k+1)-s(i,j-1,k+1)-s(i,j+1,k-1)+s(i,j-1,k-1)
            zl=zpl(i,j)*zhl*zsl/(dpi2(k)*dpi2(k))
            zp=zpp(i)*zhp*zsp/(dpi2(k)*dpi2(k))
            znl=nlco(i,j)*( sxx*syy - sxy*sxy ) + betas
            rhst = qe(i,j,k) - fco(i,j)*stb(i,j,k) + delh(i,j,k) -      &
     &             znl + zl + zp
            rhs(i,j,k)=rhst/(fco(i,j) + stb(i,j,k))

          END DO
        END DO
      END DO

  23  FORMAT(f6.0,' NEG STABILITIES.')
      DO k=1,nl
        spzro(k)=0.
      END DO

!*************ITERATION FOR PSI **********************
      DO k=2,nl-1
        itc=0
  800   CONTINUE
        it=.true.
        DO j=2,nx-1
          DO i=2,ny-1
            rs = ac(i,1)*s(i-1,j,k) + ac(i,2)*s(i,j-1,k) +              &
     &           ac(i,3)*s(i,j,k)   + ac(i,4)*s(i,j+1,k) +              &
     &           ac(i,5)*s(i+1,j,k) - rhs(i,j,k)
            dsi(i,j,k)=-omegs*rs/ac(i,3)
            s(i,j,k) = s(i,j,k) + dsi(i,j,k)
!*******Check accuracy criterion *******************************
            IF (ABS(dsi(i,j,k)) > thrs) THEN
              it=.false.
            END IF
          END DO
        END DO
      
        itc=itc+1
        IF (it) THEN
          icon=.true.
          IF (itc > itcm) itcm=itc
          IF (itc == 1) itc1=itc1 + 1
        ELSE
          IF (itc < maxx) THEN
            GO TO 800
          ELSE
            icon=.true.
          END IF
        END IF      
      END DO

      IF (iitot > 0) THEN
        itct=itct + itcm
        DO k=1,nl
          DO j=2,nx-1
            DO i=2,ny-1
              s(i,j,k)=part*s(i,j,k) + (1.-part)*OLD(i,j,k)
              OLD(i,j,k)=h(i,j,k)
            END DO
          END DO
        END DO
      END IF

!*************CALCULATE THE RHS OF BAL-PV EQUATION (PHI,H) ************

  700 CONTINUE
      DO k=2,nl-1
        DO j=2,nx-1
          DO i=2,ny-1
            vor = ac(i,1)*s(i-1,j,k) + ac(i,2)*s(i,j-1,k) +             &
     &            ac(i,3)*s(i,j,k)   + ac(i,4)*s(i,j+1,k) +             &
     &            ac(i,5)*s(i+1,j,k)
            IF (vor <= minvor(k)) THEN
              minvor(k)=vor
            END IF
            IF (vor >= maxvor(k)) THEN
              maxvor(k)=vor
            END IF
            IF (vor <= 0.0001-fco(i,j)) THEN
              vor = (0.0001 - fco(i,j))
!     Increase PV where absolute vorticity is too small. Similar to
!     case where stratification is too small.
              qe(i,j,k)=qe(i,j,k) + 0.01
              vozro(k)=vozro(k) + 1
            END IF
            asi(i,j,k)=fco(i,j) + vor
            sxx=s(i,j+1,k)+s(i,j-1,k)-2.*s(i,j,k)
            syy=s(i-1,j,k)+s(i+1,j,k)-2.*s(i,j,k)
            sxy=( s(i-1,j+1,k) - s(i-1,j-1,k) -                         &
     &            s(i+1,j+1,k) + s(i+1,j-1,k)  )/4.
            zhp=h(i-1,j,k+1)-h(i+1,j,k+1)-h(i-1,j,k-1)+h(i+1,j,k-1)
            zhl=h(i,j+1,k+1)-h(i,j-1,k+1)-h(i,j+1,k-1)+h(i,j-1,k-1)
            zsp=s(i-1,j,k+1)-s(i+1,j,k+1)-s(i-1,j,k-1)+s(i+1,j,k-1)
            zsl=s(i,j+1,k+1)-s(i,j-1,k+1)-s(i,j+1,k-1)+s(i,j-1,k-1)
            zl=zpl(i,j)*zhl*zsl/(dpi2(k)*dpi2(k))
            zp=zpp(i)*zhp*zsp/(dpi2(k)*dpi2(k))
            betas=0.25*(                                                &
     &                  ( fco(i-1,j) - fco(i+1,j) )*                    &
     &                  ( s(i-1,j,k) - s(i+1,j,k) ) +                   & 
     &                  ( fco(i,j+1) - fco(i,j-1) )*                    &
     &                  ( s(i,j+1,k) - s(i,j-1,k) ) )
            rha=fco(i,j)*vor + nlco(i,j)*(sxx*syy - sxy*sxy) + betas
            rh(i,j,k)=rha + qe(i,j,k) + zl + zp
               
          END DO
        END DO
      END DO

  24  FORMAT(i11,2F11.3,f6.0,' NEG ABS VORTICITIES IN PHI EQ.')
      DO k=1,nl
        vozro(k)=0.
      END DO

!*************SOLVE FOR H AT EACH LEVEL *****************

      itc=0
  701 it=.true.
      zmrs=0.
      DO k=2,nl-1
        DO j=2,nx-1
          DO i=2,ny-1
            IF (k == 2) THEN
              rs = ac(i,1)*h(i-1,j,k) +                                 &
     &             ac(i,2)*h(i,j-1,k) +                                 &
     &            (ac(i,3) + asi(i,j,k)*(bb(k)+bl(k)) )*h(i,j,k) +      &
     &             ac(i,4)*h(i,j+1,k) +                                 & 
     &             ac(i,5)*h(i+1,j,k) +                                 &
     &             asi(i,j,k)*(bh(k)*h(i,j,k+1) +                       &
     &             tha(i,j,1)/dpi2(k)) - rh(i,j,k)
              zm = h(i,j,k)
              h(i,j,k) = zm - omegh*rs/(ac(i,3) +                       &
     &                                  asi(i,j,k)*(bb(k)+bl(k)))
               
            ELSE IF (k == nl-1) THEN
              rs = ac(i,1)*h(i-1,j,k) +                                 & 
     &             ac(i,2)*h(i,j-1,k) +                                 &
     &            (ac(i,3) + asi(i,j,k)*(bb(k)+bh(k)) )*h(i,j,k) +      &
     &             ac(i,4)*h(i,j+1,k) +                                 &
     &             ac(i,5)*h(i+1,j,k) +                                 &
     &             asi(i,j,k)*(bl(k)*h(i,j,k-1) -                       &
     &             tha(i,j,2)/dpi2(k)) - rh(i,j,k)
              zm = h(i,j,k)
              h(i,j,k) = zm - omegh*rs/(ac(i,3) +                       &
     &                                  asi(i,j,k)*(bb(k)+bh(k)))
               
            ELSE
              rs = ac(i,1)*h(i-1,j,k) +                                 &
     &             ac(i,2)*h(i,j-1,k) +                                 &
     &            (ac(i,3) + asi(i,j,k)*bb(k) )*h(i,j,k) +              &
     &             ac(i,4)*h(i,j+1,k) +                                 &
     &             ac(i,5)*h(i+1,j,k) +                                 &
     &             asi(i,j,k)*( bh(k)*h(i,j,k+1) +                      &
     &                          bl(k)*h(i,j,k-1) ) -                    &
     &             rh(i,j,k)
              zm = h(i,j,k)
              h(i,j,k) = zm - omegh*rs/(ac(i,3) +                       &
     &                                  asi(i,j,k)*bb(k))
            END IF
            dh(i,j,k)=h(i,j,k) - zm
            zmrs=zmrs + ABS(dh(i,j,k))
            IF (ABS(dh(i,j,k)) > thrs) THEN
              it=.false.
            END IF

          END DO
        END DO
      END DO

      IF (AMOD(FLOAT(itc),5.) == 0) THEN
        dhmax=thrs/10.
        zmrs=zmrs/gpts
        DO k=2,nl-1
          DO j=2,nx-1
            DO i=2,ny-1
              IF (ABS(dh(i,j,k)) > dhmax) THEN
                dhmax=ABS(dh(i,j,k))
                ihm=i
                jhm=j
                khm=k
              END IF
            END DO
          END DO
        END DO

  716   FORMAT(2E9.2,3I5,f8.3)
      END IF
      zmrs=0.

      itc=itc+1
      IF (it) THEN
        itct=itct + itc
        DO j=1,nx
          DO i=1,ny
            h(i,j,1) = h(i,j,2) + tha(i,j,1)*(pe(2)-pe(1))
            s(i,j,1) = s(i,j,2) + tha(i,j,1)*(pe(2)-pe(1))
            h(i,j,nl) = h(i,j,nl-1) - tha(i,j,2)*(pe(nl)-pe(nl-1))
            s(i,j,nl) = s(i,j,nl-1) - tha(i,j,2)*(pe(nl)-pe(nl-1))
          END DO
        END DO
         
        IF (iitot > 0) THEN
          DO k=1,nl
            DO j=2,nx-1
              DO i=2,ny-1
                h(i,j,k)=part*h(i,j,k) + (1.-part)*OLD(i,j,k)
              END DO
            END DO
          END DO
        END IF
        IF ( (itc > itcold+10).AND.(iitot > 30) ) THEN
          PRINT*,'started diverging'
          GO TO 901
        END IF
        itcold=itc
        IF ((itc == 1).AND.(itc1 == nl-2)) THEN
          PRINT*,'TOTAL CONVERGENCE.'
        ELSE
          iitot=iitot + 1
  22      FORMAT(i4,' TOTAL ITERATION(S).')
          IF (iitot > maxxt) THEN
            PRINT*,'TOO MANY TOTAL ITERATIONS.'
            GO TO 901
          ELSE
            GO TO 900
          END IF
        END IF
      ELSE
        IF (itc < maxx) THEN
          GO TO 701
        ELSE
          PRINT*,'TOO MANY ITERATIONS FOR HGHT.'
          icon=.false.
          GO TO 901
        END IF
      END IF
!*******************************************************
 901  RETURN
      END SUBROUTINE balnc
