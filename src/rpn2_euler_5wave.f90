


!     =====================================================
    subroutine rpn2(ixy,maxm,meqn,mwaves,mbc,mx,ql,qr,auxl,auxr, &
                    wave,s,amdq,apdq,num_aux)
!     =====================================================

!     # Roe-solver for the Euler equations with a tracer variable
!     # and separate shear and entropy waves.

!     # solve Riemann problems along one slice of data.

!     # On input, ql contains the state vector at the left edge of each cell
!     #           qr contains the state vector at the right edge of each cell

!     # This data is along a slice in the x-direction if ixy=1
!     #                            or the y-direction if ixy=2.
!     # On output, wave contains the waves, s the speeds,
!     # and amdq, apdq the decomposition of the flux difference
!     #   f(qr(i-1)) - f(ql(i))
!     # into leftgoing and rightgoing parts respectively.
!     # With the Roe solver we have
!     #    amdq  =  A^- \Delta q    and    apdq  =  A^+ \Delta q
!     # where A is the Roe matrix.  An entropy fix can also be incorporated
!     # into the flux differences.

!     # Note that the i'th Riemann problem has left state qr(:,i-1)
!     #                                    and right state ql(:,i)
!     # From the basic clawpack routines, this routine is called with ql = qr


    implicit double precision (a-h,o-z)

    dimension wave(meqn, mwaves, 1-mbc:maxm+mbc)
    dimension    s(mwaves, 1-mbc:maxm+mbc)
    dimension   ql(meqn, 1-mbc:maxm+mbc)
    dimension   qr(meqn, 1-mbc:maxm+mbc)
    dimension  apdq(meqn, 1-mbc:maxm+mbc)
    dimension  amdq(meqn, 1-mbc:maxm+mbc)

!     local arrays -- common block comroe is passed to rpt2eu
!     ------------
    parameter (maxm2 = 25000)
    dimension delta(4)
    logical :: efix
    common /cparam/  gamma,gamma1
!     # assumes at most maxm2 * maxm2 grid with mbc<=7
    common /comroe/ u2v2(-6:maxm2+7), &
    u(-6:maxm2+7),v(-6:maxm2+7), &
    enth(-6:maxm2+7),a(-6:maxm2+7), &
    g1a2(-6:maxm2+7),euv(-6:maxm2+7)

    if (mbc > 7 .OR. maxm2 < maxm) then
        write(6,*) 'need to increase maxm2 or 7 in rpn'
        write(6,*) mbc, maxm
        stop
    endif

    data efix /.true./    !# use entropy fix for transonic rarefactions


!     # set mu to point to  the component of the system that corresponds
!     # to momentum in the direction of this slice, mv to the orthogonal
!     # momentum:

    if (ixy == 1) then
        mu = 2
        mv = 3
    else
        mu = 3
        mv = 2
    endif

!     # note that notation for u and v reflects assumption that the
!     # Riemann problems are in the x-direction with u in the normal
!     # direciton and v in the orthogonal direcion, but with the above
!     # definitions of mu and mv the routine also works with ixy=2
!     # and returns, for example, f0 as the Godunov flux g0 for the
!     # Riemann problems u_t + g(u)_y = 0 in the y-direction.


!     # compute the Roe-averaged variables needed in the Roe solver.
!     # These are stored in the common block comroe since they are
!     # later used in routine rpt2eu to do the transverse wave splitting.

    do 10 i = 2-mbc, mx+mbc
        rhsqrtl = dsqrt(qr(1,i-1))
        rhsqrtr = dsqrt(ql(1,i))
        pl = gamma1*(qr(4,i-1) - 0.5d0*(qr(2,i-1)**2 + &
        qr(3,i-1)**2)/qr(1,i-1))
        pr = gamma1*(ql(4,i) - 0.5d0*(ql(2,i)**2 + &
        ql(3,i)**2)/ql(1,i))
        rhsq2 = rhsqrtl + rhsqrtr
        u(i) = (qr(mu,i-1)/rhsqrtl + ql(mu,i)/rhsqrtr) / rhsq2
        v(i) = (qr(mv,i-1)/rhsqrtl + ql(mv,i)/rhsqrtr) / rhsq2
        enth(i) = (((qr(4,i-1)+pl)/rhsqrtl &
        + (ql(4,i)+pr)/rhsqrtr)) / rhsq2
        u2v2(i) = u(i)**2 + v(i)**2
        a2 = gamma1*(enth(i) - .5d0*u2v2(i))
        a(i) = dsqrt(a2)
        g1a2(i) = gamma1 / a2
        euv(i) = enth(i) - u2v2(i)
    10 END DO


!     # now split the jump in q at each interface into waves

!     # find a1 thru a4, the coefficients of the 4 eigenvectors:
    do 20 i = 2-mbc, mx+mbc
        delta(1) = ql(1,i) - qr(1,i-1)
        delta(2) = ql(mu,i) - qr(mu,i-1)
        delta(3) = ql(mv,i) - qr(mv,i-1)
        delta(4) = ql(4,i) - qr(4,i-1)
        a3 = g1a2(i) * (euv(i)*delta(1) &
        + u(i)*delta(2) + v(i)*delta(3) - delta(4))
        a2 = delta(3) - v(i)*delta(1)
        a4 = (delta(2) + (a(i)-u(i))*delta(1) - a(i)*a3) / (2.d0*a(i))
        a1 = delta(1) - a3 - a4
    
    !        # Compute the waves.
    
    !        # acoustic:
        wave(1,1,i) = a1
        wave(mu,1,i) = a1*(u(i)-a(i))
        wave(mv,1,i) = a1*v(i)
        wave(4,1,i) = a1*(enth(i) - u(i)*a(i))
        wave(5,1,i) = 0.d0
        s(1,i) = u(i)-a(i)
    
    !        # shear:
        wave(1,2,i) = 0.d0
        wave(mu,2,i) = 0.d0
        wave(mv,2,i) = a2
        wave(4,2,i) = a2*v(i)
        wave(5,2,i) = 0.d0
        s(2,i) = u(i)
    
    !        # entropy:
        wave(1,3,i) = a3
        wave(mu,3,i) = a3*u(i)
        wave(mv,3,i) = a3*v(i)
        wave(4,3,i) = a3*0.5d0*u2v2(i)
        wave(5,3,i) = 0.d0
        s(3,i) = u(i)
    
    !        # acoustic:
        wave(1,4,i) = a4
        wave(mu,4,i) = a4*(u(i)+a(i))
        wave(mv,4,i) = a4*v(i)
        wave(4,4,i) = a4*(enth(i)+u(i)*a(i))
        wave(5,4,i) = 0.d0
        s(4,i) = u(i)+a(i)
    
    !        # Another wave added for tracer concentration:
    
    !        # tracer:
        wave(1,5,i) = 0.d0
        wave(mu,5,i) = 0.d0
        wave(mv,5,i) = 0.d0
        wave(4,5,i) = 0.d0
        wave(5,5,i) = ql(5,i) - qr(5,i-1)
        s(5,i) = u(i)
    
    20 END DO


!    # compute flux differences amdq and apdq.
!    ---------------------------------------

    if (efix) go to 110

!     # no entropy fix
!     ----------------

!     # amdq = SUM s*wave   over left-going waves
!     # apdq = SUM s*wave   over right-going waves

    do 100 m=1,meqn
        do 100 i=2-mbc, mx+mbc
            amdq(m,i) = 0.d0
            apdq(m,i) = 0.d0
            do 90 mw=1,mwaves
                if (s(mw,i) < 0.d0) then
                    amdq(m,i) = amdq(m,i) + s(mw,i)*wave(m,mw,i)
                else
                    apdq(m,i) = apdq(m,i) + s(mw,i)*wave(m,mw,i)
                endif
            90 END DO
    100 END DO
    go to 900

!-----------------------------------------------------

    110 continue

!     # With entropy fix
!     ------------------

!    # compute flux differences amdq and apdq.
!    # First compute amdq as sum of s*wave for left going waves.
!    # Incorporate entropy fix by adding a modified fraction of wave
!    # if s should change sign.

    do 200 i = 2-mbc, mx+mbc
    
    !        # check 1-wave:
    !        ---------------
    
        rhoim1 = qr(1,i-1)
        pim1 = gamma1*(qr(4,i-1) - 0.5d0*(qr(mu,i-1)**2 &
        + qr(mv,i-1)**2) / rhoim1)
        cim1 = dsqrt(gamma*pim1/rhoim1)
        s0 = qr(mu,i-1)/rhoim1 - cim1     !# u-c in left state (cell i-1)

    !        # check for fully supersonic case:
        if (s0 >= 0.d0 .AND. s(1,i) > 0.d0)  then
        !            # everything is right-going
            do 60 m=1,meqn
                amdq(m,i) = 0.d0
            60 END DO
            go to 200
        endif
    
        rho1 = qr(1,i-1) + wave(1,1,i)
        rhou1 = qr(mu,i-1) + wave(mu,1,i)
        rhov1 = qr(mv,i-1) + wave(mv,1,i)
        en1 = qr(4,i-1) + wave(4,1,i)
        p1 = gamma1*(en1 - 0.5d0*(rhou1**2 + rhov1**2)/rho1)
        c1 = dsqrt(gamma*p1/rho1)
        s1 = rhou1/rho1 - c1  !# u-c to right of 1-wave
        if (s0 < 0.d0 .AND. s1 > 0.d0) then
        !            # transonic rarefaction in the 1-wave
            sfract = s0 * (s1-s(1,i)) / (s1-s0)
        else if (s(1,i) < 0.d0) then
        !            # 1-wave is leftgoing
            sfract = s(1,i)
        else
        !            # 1-wave is rightgoing
            sfract = 0.d0   !# this shouldn't happen since s0 < 0
        endif
        do 120 m=1,meqn
            amdq(m,i) = sfract*wave(m,1,i)
        120 END DO
    
    !        # check contact discontinuity:
    !        ------------------------------
    
        if (s(2,i) >= 0.d0) go to 200  !# 2- 3- and 5-waves are rightgoing
        do 140 m=1,meqn
            amdq(m,i) = amdq(m,i) + s(2,i)*wave(m,2,i)
            amdq(m,i) = amdq(m,i) + s(3,i)*wave(m,3,i)
            amdq(m,i) = amdq(m,i) + s(5,i)*wave(m,5,i)
        140 END DO
    
    !        # check 4-wave:
    !        ---------------
    
        rhoi = ql(1,i)
        pi = gamma1*(ql(4,i) - 0.5d0*(ql(mu,i)**2 &
        + ql(mv,i)**2) / rhoi)
        ci = dsqrt(gamma*pi/rhoi)
        s3 = ql(mu,i)/rhoi + ci     !# u+c in right state  (cell i)
    
        rho2 = ql(1,i) - wave(1,4,i)
        rhou2 = ql(mu,i) - wave(mu,4,i)
        rhov2 = ql(mv,i) - wave(mv,4,i)
        en2 = ql(4,i) - wave(4,4,i)
        p2 = gamma1*(en2 - 0.5d0*(rhou2**2 + rhov2**2)/rho2)
        c2 = dsqrt(gamma*p2/rho2)
        s2 = rhou2/rho2 + c2   !# u+c to left of 4-wave
        if (s2 < 0.d0 .AND. s3 > 0.d0) then
        !            # transonic rarefaction in the 4-wave
            sfract = s2 * (s3-s(4,i)) / (s3-s2)
        else if (s(4,i) < 0.d0) then
        !            # 4-wave is leftgoing
            sfract = s(4,i)
        else
        !            # 4-wave is rightgoing
            go to 200
        endif
    
        do 160 m=1,meqn
            amdq(m,i) = amdq(m,i) + sfract*wave(m,4,i)
        160 END DO
    200 END DO

!     # compute the rightgoing flux differences:
!     # df = SUM s*wave   is the total flux difference and apdq = df - amdq

    do 220 m=1,meqn
        do 220 i = 2-mbc, mx+mbc
            df = 0.d0
            do 210 mw=1,mwaves
                df = df + s(mw,i)*wave(m,mw,i)
            210 END DO
            apdq(m,i) = df - amdq(m,i)
    220 END DO

    900 continue
    return
    end subroutine rpn2
