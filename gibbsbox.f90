MODULE gibbsbox

  USE blaspack, only : eye, vec, symmetric, symkronecker, XprimeX, xxprime, xxprime, invsym, choleski, maxroot
  USE statespacebox, only : samplerA3B3C3noise, dlyap
  USE densitybox, only : vslBetaDraws, SVOgridspace
  USE embox, only : savemat, savevec, savearray3 ! debugging
  USE timerbox
  USE vslbox

  IMPLICIT NONE


CONTAINS


  ! @\newpage\subsection{ineffbatch}@
  function ineffbatch(x,Nbatches) result(f)

    integer, optional :: Nbatches
    integer :: Kbatch, Nbatch


    double precision, dimension(:,:) :: x ! Nx x Ndraws
    double precision, dimension(size(x,1)) :: f
    double precision, dimension(size(x,1)) :: acf0, mean0, betweenmeansVariance
    double precision, allocatable, dimension(:,:) :: batchmeans
    integer :: Nx, Ndraws
    integer :: ii

    Nx     = size(x,1)
    Ndraws = size(x,2)

    if (PRESENT(Nbatches)) then
       Nbatch = Nbatches
    else
       Nbatch = 20
    end if


    ! compute sample mean and variance
    mean0 = sum(x,2) / Ndraws
    acf0  = sum(x ** 2,2) / Ndraws - mean0 ** 2

    ! compute batch means
    Kbatch = int(Ndraws / Nbatch)
    allocate (batchmeans(Nx,Nbatch))
    do ii=1,Nbatch
       batchmeans(:,ii) = sum(x(:,(ii-1)*Kbatch+1:ii*Kbatch), 2) / Kbatch 
       batchmeans(:,ii) = batchmeans(:,ii) - mean0
    end do
    
    betweenmeansVariance = sum(batchmeans ** 2,2) / (Nbatch - 1)

    ! compute ineff factor
    f = (betweenmeansVariance / Nbatch) / (acf0 / Ndraws) 

    deallocate (batchmeans)

  end function ineffbatch

  ! @\newpage\subsection{ineffparzen}@
  function ineffparzen(x,bandwidth) result(f)

    integer, optional :: bandwidth
    integer :: K


    double precision, dimension(:,:), intent(in) :: x ! Nx x Ndraws
    double precision, dimension(size(x,1),size(x,2)) :: xdev ! Nx x Ndraws
    double precision, dimension(size(x,1)) :: f
    double precision, dimension(size(x,1)) :: acf0, mean0
    double precision, allocatable, dimension(:,:) :: acc 
    double precision, allocatable, dimension(:) :: kernel
    double precision  :: kw
    integer :: Nx, Ndraws
    integer :: ii, jj

    Nx     = size(x,1)
    Ndraws = size(x,2)

    if (PRESENT(bandwidth)) then
       K = bandwidth
    else
       K = min(Ndraws,int(100/sqrt(5000.0d0)*sqrt(dble(Ndraws)))) ! from bayesem R package
    end if

    mean0 = sum(x,2) / Ndraws
    forall(ii=1:Nx,jj=1:Ndraws) xdev(ii,jj) = x(ii,jj) - mean0(ii)

    allocate (acc(Nx,K), kernel(K))
    ! compute kernel weights (here: Parzen)
    ! kernel(0) = 1.0d0
    do ii=1,int(K / 2) 
       kw         = dble(ii) / dble(K)
       kernel(ii) = 1.0d0 - 6.0d0 * (kw ** 2) + 6.0d0 * kw ** 3
    end do
    do ii=int(K / 2) + 1, K
       kw = dble(ii) / dble(K)
       kernel(ii) = 2.0d0 * ((1.0d0 - kw)  ** 3)
    end do


    ! compute acf
    acf0 = sum(xdev ** 2,2) / Ndraws
    do ii=1,K
       acc(:,ii) = sum(xdev(:,ii+1:Ndraws) * xdev(:,1:Ndraws-ii),2) / Ndraws 
    end do

    ! transform acf into acc
    forall (ii=1:K,jj=1:Nx) acc(jj,ii) = acc(jj,ii) / acf0(jj)
    ! kernel-weighted acf
    forall(ii=1:K,jj=1:Nx) acc(jj,ii) = acc(jj,ii) * kernel(ii)

    ! compute ineff factor
    f = 1.0d0 + 2.0d0 * sum(acc,2)

    deallocate (acc, kernel)

  end function ineffparzen

  ! @\newpage\subsection{ineffbrtltt}@
  function ineffbrtltt(x,bandwidth) result(f)

    integer, optional :: bandwidth
    integer :: K

    double precision, dimension(:,:), intent(in) :: x ! Nx x Ndraws
    double precision, dimension(size(x,1),size(x,2)) :: xdev ! Nx x Ndraws
    double precision, dimension(size(x,1)) :: f
    double precision, dimension(size(x,1)) :: acf0, mean0
    double precision, allocatable, dimension(:,:) :: acc 
    double precision, allocatable, dimension(:) :: kernel
    double precision  :: kw
    integer :: Nx, Ndraws

    integer :: ii, jj

    Nx     = size(x,1)
    Ndraws = size(x,2)

    if (PRESENT(bandwidth)) then
       K = bandwidth
    else
       K = min(Ndraws,int(100/sqrt(5000.0d0)*sqrt(dble(Ndraws)))) ! from bayesem R package
    end if

    mean0 = sum(x,2) / Ndraws
    forall(ii=1:Nx,jj=1:Ndraws) xdev(ii,jj) = x(ii,jj) - mean0(ii)

    allocate (acc(Nx,K), kernel(K))

    ! compute kernel weights (here: Bartlett)
    ! kernel(0) = 1.0d0
    do ii=1,K
       kw = dble(ii) / dble(K)
       kernel(ii) = 1.0d0 - kw
    end do


    ! compute acf
    acf0 = sum(xdev ** 2,2) / Ndraws
    do ii=1,K
       acc(:,ii) = sum(xdev(:,ii+1:Ndraws) * xdev(:,1:Ndraws-ii),2) / Ndraws 
    end do

    ! transform acf into acc
    forall (ii=1:K,jj=1:Nx) acc(jj,ii) = acc(jj,ii) / acf0(jj)
    ! kernel-weighted acf
    forall(ii=1:K,jj=1:Nx) acc(jj,ii) = acc(jj,ii) * kernel(ii)

    ! compute ineff factor
    f = 1.0d0 + 2.0d0 * sum(acc,2)

    deallocate (acc, kernel)

  end function ineffbrtltt

  ! @\newpage\subsection{olsdraw}@
  SUBROUTINE olsdraw(bdraw, Nobs, Ny, Nx, Y, X, VSLstream)

    integer, intent(in) :: Nobs, Ny, Nx
    double precision, intent(out), dimension(Nx,Ny) :: bdraw
    double precision, intent(in) :: y(Nobs, Ny), x(Nobs, Nx)
    double precision :: xx(Nx, Nx), xy(Nx,Ny), yresid(Nobs,Ny), ssr(ny,ny), sqrtSSRdraw(ny,ny), bhat(Nx,Ny)
    integer :: errcode

    TYPE (vsl_stream_state) :: VSLstream

    ! X'X
    XX = 0.0d0 ! to clean out lower triangular part of XX
    call DSYRK('U','T',Nx,Nobs,1.0d0,X,Nobs,0.0d0,XX,Nx)
    call DPOTRF('U',Nx,xx,Nx,errcode)
    if (errcode .ne. 0) then
       print *,'dpotrf error in ols'
       stop 1
    end if

    ! x'y
    call DGEMM('t','n',Nx,Ny,Nobs,1.0d0,x,Nobs,y,Nobs,0.0d0,xy,Nx)

    ! solve xx * bhat = xy for bhat
    bhat = xy
    call DPOTRS('u', Nx, Ny, xx, Nx, bhat, Nx, errcode)
    if (errcode .ne. 0) then
       print *,'dpotrs error in ols'
       stop 1
    end if

    ! compute yresid = y - x * b
    yresid = y
    call DGEMM('N','N',Nobs,Ny,Nx,-1.0d0,X,Nobs,bhat,Nx,1.0d0,yresid,Nobs)

    ! compute ssr = resid' * resid
    call DSYRK('u','t',Ny,Nobs,1.0d0,yresid,Nobs,0.0d0,ssr,Ny)

    ! draw S sim IW(ssr, Nobs-Nx), returns upper choleski-left
    call iwishcholDraw(sqrtSSRdraw, ssr, Nobs-Nx, Ny, VSLstream)

    ! draw normal, scale and shift
    errcode  = vdrnggaussian(VSLmethodGaussian, VSLstream, Ny * Nx, bdraw, 0.0d0, 1.0d0)

    ! bdraw = bdraw * transpose(sqrtSSR)
    call DTRMM('r','u','t','n',Nx,Ny,1.0d0,sqrtSSRdraw,Ny,bdraw,Nx)
    ! bdraw = transpose(xx) \ bdraw
    call DTRTRS('u', 't', 'n', Nx, Ny, xx, Nx, bdraw, Nx, errcode)

    bdraw = bhat + bdraw

  END SUBROUTINE olsdraw

  ! @\newpage\subsection{bayesSURSV}@
  SUBROUTINE bayesSURSV(bdraw, residuals, Ydata, Xdata, Ny, Nx, MaxNx, T, k, iSigmaResid, b0, V0i, VSLstream)
    INTENT(IN) :: Ydata, Ny, k, T, iSigmaResid, Xdata, Nx, MaxNx, b0, V0i
    INTENT(OUT) :: residuals, bdraw
    INTENT(INOUT) :: VSLstream
    INTEGER :: MaxNx, T, Ny, Nx(Ny), status, j, k, ii, tt
    DOUBLE PRECISION, DIMENSION(k, k) :: Vi, V0i
    DOUBLE PRECISION, DIMENSION(k) ::    b, bdraw, b0
    DOUBLE PRECISION :: iSigmaResid(Ny,Ny,T), residuals(T,Ny), Ytilde(Ny), Ydata(T,Ny), Xdata(T,MaxNx,Ny), X(Ny,k), work(Ny, k), Y(Ny) !  XY(k),
    TYPE (vsl_stream_state) :: VSLstream
    Ytilde = 0.0d0
    ! set up the priors
    call DSYMV('U', k, 1.0d0, V0i, k, b0, 1, 0.0d0, b, 1)
    Vi = V0i
    DO tt = 1, T
       ! Construct Ytilde(t) = iSigmaResid(t) * Y(t)
       Y = Ydata(tt,:)
       call dsymv('U', Ny, 1.0d0, iSigmaResid(:,:,tt), Ny, Y, 1, 0.0d0, Ytilde, 1)
       ! Construct X(t)
       X = 0.0d0
       ii = 0
       DO j = 1, Ny
          X(j, (ii+1):(ii+Nx(j))) = Xdata(tt, 1:Nx(j), j)
          ii = ii + Nx(j)
       END DO
       ! Construct XY(t)' = Sum_t X(t) * iSigmaResid(t) * Y(t)
       call dgemv('T',Ny,k,1.0d0,X,Ny,Ytilde,1,1.0d0,b,1)

       ! Construct iSigmaResid(t) * X(t)
       call dsymm('L','U',Ny,k,1.0d0,iSigmaResid(:,:,tt),Ny,X,Ny,0.0d0,work,Ny)
       ! Construct Sum_t X(t)' * iSigmaResid(t) * X(t)
       call dgemm('T','N',k,k,Ny,1.0d0,X,Ny,work,Ny,1.0d0,Vi,k)

    END DO

    ! Solve for posterior mean
    ! solve: Vi * b = ...
    ! 1) Choleski factorization
    call dpotrf('u', k, Vi, k, status)
    if (status /= 0) then
       write(*,*) 'CHOLESKI ERROR:', status, ' [BAYESSUR]'
       stop 1
    end if

    ! zero out lower triangular
    forall (j = 1 : k-1) Vi(j+1:k,j) = 0.0d0

    ! 2) solve Vi * b = z
    call DPOTRS('U', k, 1, Vi, k, b, k, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, ' [BAYESSUR]'
       stop 1
    end if

    ! DRAW FROM POSTERIOR with mean b and inverse variance Vi 
    ! notice: I am not scaling the draw)' * chol(Vi), i.e. chol is upper triangular)
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, k, bdraw, 0.0d0, 1.0d0)
    call DTRSV('U', 'N', 'N', k, Vi, k, bdraw, 1)

    ! add posterior mean
    bdraw = bdraw + b

    DO tt = 1, T
       ! Construct X(t)
       X = 0.0d0
       ii = 0
       DO j = 1, Ny
          X(j, (ii+1):(ii+Nx(j))) = Xdata(tt, 1:Nx(j), j)
          ii = ii + Nx(j)
       END DO
       ! Calculate Y - X * b
       Y = Ydata(tt,:)
       call dgemv('N',Ny,k,-1.0d0,X,Ny,bdraw,1,1.0d0,Y,1)
       residuals(tt,:) = Y

    END DO

  END SUBROUTINE bayesSURSV
  ! @\newpage\subsection{drawRW}@
  SUBROUTINE drawRW (h,T,sigma,Eh0,Vh0,VSLstream)
    IMPLICIT NONE
    INTEGER, INTENT(IN) :: T
    DOUBLE PRECISION, DIMENSION(0:T), INTENT(OUT) :: h
    DOUBLE PRECISION, INTENT(IN)  :: sigma, Eh0, Vh0
    DOUBLE PRECISION, DIMENSION(0:T) :: z
    TYPE (vsl_stream_state), INTENT(INOUT) :: VSLstream
    INTEGER :: j, errcode


    errcode = vdrnggaussian(VSLmethodGaussian, VSLstream, T + 1, z, 0.0d0, sigma)

    h(0)    = Eh0 + sqrt(Vh0) / sigma * z(0)
    DO j=1,T
       h(j) = h(j-1) + z(j)
    END DO

  END SUBROUTINE drawRW
  ! @\newpage\subsection{drawRWcorrelated}@
  SUBROUTINE drawRWcorrelated (h,N,T,sqrtVh,Eh0,sqrtVh0,VSLstream)
    IMPLICIT NONE

    INTENT(IN) :: N,T,sqrtVh,Eh0,sqrtVh0
    INTENT(OUT) :: h
    INTENT(INOUT) :: VSLstream

    INTEGER :: T,N, j, errcode
    DOUBLE PRECISION, DIMENSION(N,0:T) :: h, z
    DOUBLE PRECISION :: sqrtVh(N,N), Eh0(N), sqrtVh0(N,N)
    TYPE (vsl_stream_state) :: VSLstream

    ! draw random numbers
    errcode    = vdrnggaussian(VSLmethodGaussian, VSLstream, (T + 1) * N, z, 0.0d0, 1.0d0)
    ! construct h0
    h(:,0) = Eh0
    call DGEMV('N',N,N,1.0d0,sqrtVh0,N,z(:,0),1,1.0d0,h(:,0),1)
    ! scale shocks and accumulate
    DO j=1,T
       h(:,j) = h(:,j-1) 
       call DGEMV('N',N,N,1.0d0,sqrtVh,N,z(:,j),1,1.0d0,h(:,j),1)
    END DO

  END SUBROUTINE drawRWcorrelated

  ! @\newpage\subsection{drawAR1}@
  SUBROUTINE drawAR1(z,rho,T,sigma,VSLstream)
    IMPLICIT NONE

    INTENT(IN) rho,T,sigma
    INTENT(INOUT) VSLstream
    INTENT(OUT) z

    INTEGER :: T, j, errcode
    DOUBLE PRECISION, DIMENSION(0:T) :: z
    DOUBLE PRECISION :: rho, sigma, vary
    TYPE (vsl_stream_state) :: VSLstream

    errcode = vdrnggaussian(VSLmethodGaussian, VSLstream, T + 1, z, 0.0d0, 1.0d0)

    vary = (sigma ** 2) / (1 - rho ** 2)
    z(0)    = sqrt(vary) * z(0)
    DO j=1,T
       z(j) = rho * z(j-1) + sigma * z(j)
    END DO

  END SUBROUTINE drawAR1

  ! @\newpage\subsection{drawAR1correlated}@
  SUBROUTINE drawAR1correlated(h,N,T,rho,sqrtSigma,VSLstream)
    IMPLICIT NONE

    ! mean zero draws

    INTENT(IN) rho,T,N,sqrtSigma
    INTENT(INOUT) VSLstream
    INTENT(OUT) h

    INTEGER :: T, N, j, i, errcode
    DOUBLE PRECISION, DIMENSION(N,0:T) :: z, h
    DOUBLE PRECISION, DIMENSION(N)   :: rho
    DOUBLE PRECISION, DIMENSION(N,N) :: sqrtSigma, sqrtSigma0, A
    TYPE (vsl_stream_state) :: VSLstream

    errcode = vdrnggaussian(VSLmethodGaussian, VSLstream, N * (T + 1), z, 0.0d0, 1.0d0)

    h = 0.0d0

    ! t = 0
    ! construct transition matrix
    A = 0.0d0
    forall (i=1:N) A(i,i) = rho(i)
    CALL DLYAP(sqrtSigma0, A, sqrtSigma, N, N, errcode) 
    if (errcode /= 0) then
       write (*,*) 'DLYAP error (sqrtSigma0 in drawAR1correlated)', errcode
       stop 1
    end if
    ! Factorize the unconditional variance
    CALL DPOTRF('L', N, sqrtSigma0, N, errcode)
    if (errcode /= 0) then
       write (*,*) 'DPOTRF error  (sqrtSigma0 in drawAR1correlated)', errcode
       stop 1
    end if
    ! zero out the upper triangular
    FORALL (i=2:N) sqrtSigma0(1:i-1,i) = 0.0d0
    call DGEMV('N',N,N,1.0d0,sqrtSigma0,N,z(:,0),1,0.0d0,h(:,0),1)

    ! loop over t=1:T
    Do j=1,T
       h(:,j) = rho * h(:,j-1)
       call DGEMV('N',N,N,1.0d0,sqrtSigma,N,z(:,j),1,1.0d0,h(:,j),1)
    END DO

  END SUBROUTINE drawAR1correlated

  ! @\newpage\subsection{smoothingsamplerLocalLevel}@
  SUBROUTINE smoothingsamplerLocalLevel (tau,y,T,vartrend,varnoise,X0,V0, VSLstream)
    IMPLICIT NONE
    INTENT (IN) :: T, y, vartrend, varnoise, X0, V0
    INTENT (OUT) :: tau
    INTENT(INOUT) :: VSLstream
    INTEGER j, errcode, T
    DOUBLE PRECISION, DIMENSION(0:T) :: tautT, tau, tauplus, SigmaStar, z
    DOUBLE PRECISION, DIMENSION(T) :: y, yplus, vartrend, varnoise, Sigma, e
    DOUBLE PRECISION :: X0, V0, gain
    TYPE (vsl_stream_state)  :: VSLstream


    ! draw plus data
    errcode = vdrnggaussian(VSLmethodGaussian, VSLstream, T+1, z, 0.0d0, 1.0d0)
    tauplus(0) = X0 + sqrt(V0) * z(0)
    DO j=1,T
       tauplus(j) = tauplus(j-1) + sqrt(vartrend(j)) * z(j)
    END DO
    errcode = vdrnggaussian(VSLmethodGaussian, VSLstream, T, e, 0.0d0, 1.0d0)

    ! Prepare filter for "pseudo" observables
    yplus = tauplus(1:T) + sqrt(varnoise) * e
    yplus = yplus - y

    SigmaStar(0)  = V0
    tautT(0)      = 0.0d0 ! adjust for yplus minus y

    ! forward filter
    DO j=1,T

       Sigma(j)       = SigmaStar(j-1) + vartrend(j)
       gain           = Sigma(j) / (Sigma(j) + varnoise(j))

       SigmaStar(j)   = ((1 - gain)**2) * Sigma(j) + (gain**2) * varnoise(j)

       tautT(j)       = (1 - gain) * tautT(j-1) + gain * yplus(j)

    END DO

    ! backward filter
    DO j=T-1,0,-1 
       gain     = SigmaStar(j) / Sigma(j+1)
       tautT(j) = (1 - gain) * tautT(j) + gain * tautT(j+1)
    END DO

    ! put draws together
    tau = tauplus - tautT

    ! DEBUG
    ! OPEN (UNIT=4, FILE='debug.smoothingsamplerSettings.dat', STATUS='REPLACE', ACTION='WRITE')
    ! WRITE(4,'(2ES30.16,I10)') X0,V0,T
    ! CLOSE(UNIT=4)
    ! OPEN (UNIT=4, FILE='debug.smoothingsamplerT.dat', STATUS='REPLACE', ACTION='WRITE')
    ! WRITE(4,'(6ES30.16)') (y(j), yplus(j), varnoise(j), vartrend(j), Sigma(j), e(j), j=1,T)
    ! CLOSE(UNIT=4)
    ! OPEN (UNIT=4, FILE='debug.smoothingsamplerTp1.dat', STATUS='REPLACE', ACTION='WRITE')
    ! WRITE(4,'(5ES30.16)') (tau(j), tauplus(j), tautT(j), SigmaStar(j), z(j), j=0,T)
    ! CLOSE(UNIT=4)

  END SUBROUTINE smoothingsamplerLocalLevel

  ! @\newpage\subsection{tvpRegressionSlope}@
  SUBROUTINE tvpRegressionSlope(beta,T,y,x,varbeta,varnoise,beta0,beta0V,VSLstream)
    ! univarate regression with tvp slope 
    ! y(t) = beta(t) * x(t) + sqrt(varnoise(t)) * e(t)
    ! beta(t) = beta(t-1) + sqrt(varbeta(t)) * z(t)

    IMPLICIT NONE
    INTENT (IN) :: T, y, x, varbeta, varnoise, beta0, beta0V
    INTENT (OUT) :: beta
    INTENT(INOUT) :: VSLstream
    INTEGER j, errcode, T
    DOUBLE PRECISION, DIMENSION(0:T) :: betatT, beta, betaplus, SigmaStar, z
    DOUBLE PRECISION, DIMENSION(T) :: y, yplus, x, Sigma, e
    DOUBLE PRECISION :: beta0, beta0V, gain, omxgain, varbeta, varnoise
    TYPE (vsl_stream_state)  :: VSLstream


    ! draw plus data
    errcode = vdrnggaussian(VSLmethodGaussian, VSLstream, T+1, z, 0.0d0, sqrt(varbeta))
    betaplus(0) = beta0 + sqrt(beta0V  / varbeta) * z(0)
    DO j=1,T
       betaplus(j) = betaplus(j-1) + z(j)
    END DO

    errcode = vdrnggaussian(VSLmethodGaussian, VSLstream, T, e, 0.0d0, sqrt(varnoise))
    ! Prepare filter for "pseudo" observables
    yplus = x * betaplus(1:T) + e
    yplus = yplus - y

    SigmaStar(0)  = beta0V
    betatT(0)     = 0.0d0 ! adjust for yplus minus y

    ! forward filter
    DO j=1,T

       Sigma(j)       = SigmaStar(j-1) + varbeta
       gain           = x(j) * Sigma(j) / (Sigma(j) * (x(j) ** 2) + varnoise)
       omxgain        = 1 - gain * x(j)

       SigmaStar(j)   = omxgain * Sigma(j) 
       betatT(j)      = omxgain * betatT(j-1) + gain * yplus(j)

    END DO

    ! backward filter
    DO j=T-1,0,-1 
       gain     = SigmaStar(j) / Sigma(j+1)
       betatT(j) = (1 - gain) * betatT(j) + gain * betatT(j+1)
    END DO

    ! put draws together
    beta = betaplus - betatT

    ! DEBUG
    ! call savevec(beta, 'tvpdebug.beta.dat')
    ! call savevec(y, 'tvpdebug.y.dat')
    ! call savevec(x, 'tvpdebug.x.dat')
    ! call savevec(varbeta, 'tvpdebug.varbeta.dat')
    ! call savevec(varnoise, 'tvpdebug.varnoise.dat')
    ! call savevec(z, 'tvpdebug.z.dat')
    ! call savevec(e, 'tvpdebug.e.dat')

  END SUBROUTINE tvpRegressionSlope

  ! @\newpage\subsection{GelmanTest1}@
  SUBROUTINE GelmanTest1(SRstat,draws,Nsims,Nstreams)
    IMPLICIT NONE

    INTENT(OUT) :: SRstat
    INTENT(IN) :: Nsims, Nstreams
    INTENT(IN) :: draws

    INTEGER :: Nsims, Nstreams
    DOUBLE PRECISION, DIMENSION(Nsims,Nstreams) :: draws
    DOUBLE PRECISION, DIMENSION(Nsims,Nstreams) :: edraws
    DOUBLE PRECISION :: SRstat, W, B, psibar
    DOUBLE PRECISION, DIMENSION(Nstreams) :: psi, s2 ! mean and variance within stream
    INTEGER :: j

    ! within stream means
    psi    = sum(draws,1) / Nsims
    psibar = sum(psi) / Nstreams

    ! variance between means
    B  = sum((psi - psibar) ** 2) / (Nstreams - 1) ! note: this is B/n of Gelman-Rubin


    ! within stream variances
    FORALL (j=1:Nstreams)
       edraws(:,j) = draws(:,j) - psi(j)
    END FORALL
    s2 = sum(edraws ** 2, 1) / (Nsims - 1)
    ! average of within-stream-variances
    W  = sum(s2) / Nstreams

    SRstat = sqrt(dble(Nsims - 1) / dble(Nsims)  + B / W)

  END SUBROUTINE GelmanTest1

  ! @\newpage\subsection{GelmanTest}@
  PURE FUNCTION GelmanTest(draws) RESULT(SRstat)
    IMPLICIT NONE

    INTENT(IN) :: draws

    INTEGER :: Nsims, Nstreams
    DOUBLE PRECISION, DIMENSION(:,:) :: draws
    DOUBLE PRECISION, DIMENSION(size(draws,1),size(draws,2)) :: edraws
    DOUBLE PRECISION :: SRstat, W, B, psibar
    DOUBLE PRECISION, DIMENSION(size(draws,2)) :: psi, s2 ! mean and variance within stream
    INTEGER :: j

    Nsims    = size(draws,1)
    Nstreams = size(draws,2)

    ! within stream means
    psi    = sum(draws,1) / Nsims
    psibar = sum(psi) / Nstreams

    ! variance between means
    B  = sum((psi - psibar) ** 2) / (Nstreams - 1)


    ! within stream variances
    FORALL (j=1:Nstreams)
       edraws(:,j) = draws(:,j) - psi(j)
    END FORALL
    s2 = sum(edraws ** 2, 1) / (Nsims - 1)
    ! average of within-stream-variances
    W  = sum(s2) / Nstreams

    SRstat = sqrt(dble(Nsims - 1) / dble(Nsims)  + B / W)

  END FUNCTION GelmanTest

  ! @\newpage\subsection{GelmanTestVec}@
  PURE FUNCTION GelmanTestVec(draws) RESULT(SRstat)

    ! operates over vectors of parameters (elementwise SRstats)
    ! draws(Nvar,Nsims,Nstreams)

    IMPLICIT NONE

    INTENT(IN) :: draws

    INTEGER :: Nsims, Nstreams, Nvar
    DOUBLE PRECISION, DIMENSION(:,:,:) :: draws
    DOUBLE PRECISION, DIMENSION(size(draws,1),size(draws,2),size(draws,3)) :: edraws
    DOUBLE PRECISION, DIMENSION(size(draws,1)) :: SRstat, W, B, psibar
    DOUBLE PRECISION, DIMENSION(size(draws,1),size(draws,3)) :: psi, s2 ! mean and variance within stream
    INTEGER :: ii,jj,nn

    Nvar     = size(draws,1)
    Nsims    = size(draws,2)
    Nstreams = size(draws,3)

    ! within stream means
    psi    = sum(draws,2) / Nsims
    psibar = sum(psi,2) / Nstreams
    ! deviations of psi from common mean
    forall(ii=1:Nvar,jj=1:Nstreams) psi(ii,jj) = psi(ii,jj) - psibar(ii)

    ! variance between means
    B  = sum(psi ** 2, 2) / (Nstreams - 1) ! note: this is B/n of Gelman-Rubin


    ! within stream variances
    FORALL (ii=1:Nvar,nn=1:Nsims,jj=1:Nstreams)
       edraws(ii,nn,jj) = draws(ii,nn,jj) - psi(ii,jj) - psibar(ii)
    END FORALL
    s2 = sum(edraws ** 2, 2) / (Nsims - 1)
    ! average of within-stream-variances
    W  = sum(s2,2) / Nstreams

    SRstat = sqrt(dble(Nsims - 1) / dble(Nsims)  + B / W)

  END FUNCTION GelmanTestVec

  ! @\newpage\subsection{GelmanEffVec}@
  PURE FUNCTION GelmanEffVec(draws) RESULT(EFFstat)

    ! computes Gelman-Rubing nmber of effective draws

    ! todo: merge with GelmanTestVec

    ! operates over vectors of parameters (elementwise SRstats)
    ! draws(Nvar,Nsims,Nstreams)

    IMPLICIT NONE

    INTENT(IN) :: draws

    INTEGER :: Nsims, Nstreams, Nvar
    DOUBLE PRECISION, DIMENSION(:,:,:) :: draws
    DOUBLE PRECISION, DIMENSION(size(draws,1),size(draws,2),size(draws,3)) :: edraws
    DOUBLE PRECISION, DIMENSION(size(draws,1)) :: EFFstat, W, B, psibar
    DOUBLE PRECISION, DIMENSION(size(draws,1),size(draws,3)) :: psi, s2 ! mean and variance within stream
    INTEGER :: ii,jj,nn

    Nvar     = size(draws,1)
    Nsims    = size(draws,2)
    Nstreams = size(draws,3)

    ! within stream means
    psi    = sum(draws,2) / Nsims
    psibar = sum(psi,2) / Nstreams
    ! deviations of psi from common mean
    forall(ii=1:Nvar,jj=1:Nstreams) psi(ii,jj) = psi(ii,jj) - psibar(ii)

    ! variance between means
    B  = sum(psi ** 2, 2) / (Nstreams - 1) ! note: this is B/n of Gelman-Rubin


    ! within stream variances
    FORALL (ii=1:Nvar,nn=1:Nsims,jj=1:Nstreams)
       edraws(ii,nn,jj) = draws(ii,nn,jj) - psi(ii,jj) - psibar(ii)
    END FORALL
    s2 = sum(edraws ** 2, 2) / (Nsims - 1)
    ! average of within-stream-variances
    W  = sum(s2,2) / Nstreams

    EFFstat = dble(Nstreams) * ((dble(Nsims) - 1.0d0) / dble(Nsims) * W / B + 1.0d0)
    where (EFFstat .gt. Nsims * Nstreams) 
       EFFstat = dble(Nsims * Nstreams)
    end where
    

  END FUNCTION GelmanEffVec

  ! @\newpage\subsection{drawNDXudisc}@
  SUBROUTINE drawNDXudisc(ndx, Ndraws, N, VSLstream)
    ! draw discrete uniform over elements 1 : T
    ! (like randi in matlab)

    IMPLICIT NONE
    INTENT(OUT) :: ndx
    INTENT(IN) :: Ndraws, N
    INTENT(INOUT) :: VSLstream

    INTEGER :: Ndraws, N, errcode, j
    DOUBLE PRECISION, DIMENSION(Ndraws) :: u
    DOUBLE PRECISION, DIMENSION(N) :: cdf
    INTEGER, DIMENSION(Ndraws) :: ndx
    TYPE (vsl_stream_state) :: VSLstream


    forall (j=1:N) cdf(j) = dble(j) / dble(N)

    ! draw uniforms
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, Ndraws, u, 0.0d0, 1.0d0)

    ! sort the uniforms (in order to obtain sorted ndx)
    ! CALL dlasrt('I', Ndraws, u, errcode)

    !$OMP PARALLEL DO SHARED(ndx, u, cdf)
    DO j=1,Ndraws
       ndx(j) = COUNT(u(j) > cdf) + 1
    END DO
    !$OMP END PARALLEL DO 
  END SUBROUTINE drawNDXudisc

  ! @\newpage\subsection{drawNDXpdf}@
  SUBROUTINE drawNDXpdf(ndx, Ndraws, pdf, N, VSLstream)
    ! draw indices of multinominal distribution (given pdf)
    IMPLICIT NONE
    INTENT(OUT) :: ndx
    INTENT(IN) :: Ndraws, N, pdf
    INTENT(INOUT) :: VSLstream

    INTEGER :: Ndraws, N, errcode, j
    DOUBLE PRECISION, DIMENSION(Ndraws) :: u
    INTEGER, DIMENSION(Ndraws) :: ndx
    DOUBLE PRECISION, DIMENSION(N) :: pdf, cdf
    TYPE (vsl_stream_state) :: VSLstream


    ! cumulate pdf into cdf
    cdf(1) = pdf(1)
    DO j=2,N
       cdf(j) = pdf(j) + cdf(j-1)
    END DO

    ! draw uniforms
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, Ndraws, u, 0.0d0, 1.0d0)

    !$OMP PARALLEL DO SHARED(ndx, u, cdf)
    DO j=1,Ndraws
       ndx(j) = COUNT(u(j) > cdf) + 1
    END DO
    !$OMP END PARALLEL DO 


    ! slower code:
    ! DO j=1,Ndraws
    !    cdf = 0.0d0
    !    i   = 0
    !    DO WHILE (cdf < u(j))
    !       i      = i + 1
    !       cdf    = cdf + pdf(i)
    !    END DO
    !    ndx(j) = i
    ! END DO

    ! maybe, the commented code could be sped up by sorting the uniforms firts:
    ! sort the uniforms (in order to obtain sorted ndx)
    ! CALL dlasrt('I', Ndraws, u, errcode)

  END SUBROUTINE drawNDXpdf

  ! @\newpage\subsection{drawNDXsysresample}@
  SUBROUTINE drawNDXsysresample(ndx, Ndraws, pdf, N, u)
    ! draw indices of multinominal distribution (given pdf)
    IMPLICIT NONE
    INTENT(OUT) :: ndx
    INTENT(IN) :: Ndraws, N, pdf, u

    INTEGER :: Ndraws, N, i, j
    DOUBLE PRECISION :: u, udraw(Ndraws)
    INTEGER, DIMENSION(Ndraws) :: ndx !, ndx2
    DOUBLE PRECISION, DIMENSION(N) :: pdf, cdf

    ! cumulate pdf into cdf
    cdf(1) = pdf(1)
    DO j=2,N
       cdf(j) = pdf(j) + cdf(j-1)
    END DO

    ! construct udraw
    udraw = (u - 1.0d0 + dble((/ (i, i=1,Ndraws) /))) / dble(Ndraws)

    ! create ndx
    j = 1
    DO  i=1,Ndraws
       ! search bin in cdf
       do while (udraw(i) > cdf(j))
          j = j + 1
       end do

       ndx(i) = j

    END DO
  END SUBROUTINE drawNDXsysresample

  ! @\newpage\subsection{drawKSCstates}@
  SUBROUTINE drawKSCstates(kai2states, T, N, VSLstream)
    ! unconditional states draws of KSC7 mixture probability
    ! this is a vectorized version of drawKai2statesKSC7
    IMPLICIT NONE
    INTENT(OUT) :: kai2states
    INTENT(IN) :: T, N
    INTENT(INOUT) :: VSLstream

    INTEGER :: T, N, errcode, j, i
    INTEGER, PARAMETER :: KSCmix = 7, VSLmethodGaussian = 0, VSLmethodUniform = 0
    DOUBLE PRECISION, DIMENSION(T,N) :: u
    INTEGER, DIMENSION(T,N) :: kai2states
    DOUBLE PRECISION, DIMENSION(KSCmix) :: KSCcdf
    TYPE (vsl_stream_state) :: VSLstream


    KSCcdf = (/ 7.3d-3, 112.86d-3, 112.88d-3, 156.83d-3, 496.84d-3, 742.5d-3, 1.0d0 /)

    ! KSCcdf     = (/ .0073d0, .10556d0, .00002d0, .04395d0, .34001d0, .24566d0, .25750d0 /)
    ! DO j=2,KSCmix
    !    KSCcdf(j) = KSCcdf(j) + KSCcdf(j-1)
    ! END DO

    errcode = vdrnguniform(VSLmethodUniform, VSLstream, T * N, u, 0.0d0, 1.0d0)
    FORALL (j=1:T, i =1:N)
       kai2states(j,i) = COUNT(u(j,i) > KSCcdf) + 1
    END FORALL

  END SUBROUTINE drawKSCstates

  ! @\newpage\subsection{stochvolKSC0}@
  SUBROUTINE stochvolKSC0(h, y, T, hInno, Eh0, Vh0, VSLstream)

    ! uses corrected MCMC order as per DelNegro and Primiceri (2013)
    ! same as stochvolKSC, except that kai2states are not used/stored as argument anymore
    ! ... and slight change in the order of arguments ...

    IMPLICIT NONE

    INTENT(IN) :: y, hInno, Eh0, Vh0, T
    INTENT(INOUT) :: VSLstream
    INTENT(INOUT) :: h

    INTEGER :: T, errcode, j, s
    INTEGER, PARAMETER :: KSCmix = 7
    DOUBLE PRECISION, DIMENSION(KSCmix), PARAMETER :: KSCmean = - 1.2704d0 + (/ -10.12999d0, -3.97281d0, -8.56686d0, 2.77786d0, .61942d0, 1.79518d0, -1.08819d0 /), KSCvar     = (/ 5.79596d0, 2.61369d0, 5.1795d0, .16735d0, .64009d0, .34023d0, 1.26261d0 /), KSCpdf= (/ .0073d0, .10556d0, .00002d0, .04395d0, .34001d0, .24566d0, .25750d0 /), KSCvol = sqrt(KSCvar)

    DOUBLE PRECISION, DIMENSION(T) :: y, logy2, logy2star, varnoisemix, varh, u
    DOUBLE PRECISION, DIMENSION(T,KSCmix) :: kai2CDF
    INTEGER, DIMENSION(T) :: kai2states
    DOUBLE PRECISION, DIMENSION(0:T) :: h
    DOUBLE PRECISION  :: hInno, Eh0, Vh0

    TYPE (vsl_stream_state) :: VSLstream

    ! log-linear observer
    logy2 = log(y ** 2 + 0.001d0)

    ! STEP 1 DRAW KAI2STATES
    ! a) construct PDF for draws (stored in kai2CDF)
    FORALL (s=1:KSCmix,j=1:T)
       kai2CDF(j,s) = exp(-0.5d0 * ((logy2(j) - h(j) - KSCmean(s)) / KSCvol(s))** 2) / KSCvol(s) * KSCpdf(s)
    END FORALL

    ! b) convert PDF into CDF for draws
    DO s=2,KSCmix
       kai2CDF(:,s) = kai2CDF(:,s-1) + kai2CDF(:,s)
    END DO
    DO s=1,KSCmix-1
       kai2CDF(:,s) = kai2CDF(:,s) / kai2CDF(:,KSCmix)
    END DO
    kai2CDF(:,KSCmix) = 1.0d0


    ! c) draw kai2states
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, T, u, 0.0d0, 1.0d0 )
    FORALL (j=1:T)
       kai2states(j) = COUNT(u(j) > kai2CDF(j,:)) + 1
    END FORALL


    ! STEP 2: KALMAN FILTER FOR h

    ! construct trend variance and noise variance
    varh = hInno ** 2
    FORALL (j=1:T)
       varnoisemix(j) = KSCvar(kai2states(j))
    END FORALL

    ! demeaned observables 
    FORALL(j=1:T)
       logy2star(j) = logy2(j) - KSCmean(kai2states(j))
    END FORALL
    CALL smoothingsamplerLocalLevel(h,logy2star,T,varh,varnoisemix,Eh0,Vh0,VSLstream)

  END SUBROUTINE stochvolKSC0

  ! @\newpage\subsection{stochvolKSCjprwrap}@
  SUBROUTINE stochvolKSCjprwrap(SVol, h, y, T, hInno, Eh0, Vh0, VSLstream)

    ! uses corrected MCMC order as per DelNegro and Primiceri (2013)
    ! same as stochvolKSC, except that kai2states are not used/stored as argument anymore
    ! ... and slight change in the order of arguments ...
    ! this version works with same inputs/outputs as jpr0

    IMPLICIT NONE

    INTENT(IN) :: y, hInno, Eh0, Vh0, T
    INTENT(INOUT) :: VSLstream, SVol
    INTENT(OUT) :: h

    INTEGER :: T, errcode, j, s
    INTEGER, PARAMETER :: KSCmix = 7
    DOUBLE PRECISION, DIMENSION(KSCmix), PARAMETER :: KSCmean = - 1.2704d0 + (/ -10.12999d0, -3.97281d0, -8.56686d0, 2.77786d0, .61942d0, 1.79518d0, -1.08819d0 /), KSCvar     = (/ 5.79596d0, 2.61369d0, 5.1795d0, .16735d0, .64009d0, .34023d0, 1.26261d0 /), KSCpdf= (/ .0073d0, .10556d0, .00002d0, .04395d0, .34001d0, .24566d0, .25750d0 /), KSCvol = sqrt(KSCvar)

    DOUBLE PRECISION, DIMENSION(T) :: y, logy2, logy2star, varnoisemix, varh, u
    DOUBLE PRECISION, DIMENSION(T,KSCmix) :: kai2CDF
    INTEGER, DIMENSION(T) :: kai2states
    DOUBLE PRECISION, DIMENSION(0:T) :: h, SVol
    DOUBLE PRECISION  :: hInno, Eh0, Vh0

    TYPE (vsl_stream_state) :: VSLstream

    ! log-linear observer
    h = 2.0d0 * log(SVol)

    logy2 = log(y ** 2 + 0.001d0)

    ! STEP 1 DRAW KAI2STATES
    ! a) construct PDF for draws (stored in kai2CDF)
    FORALL (s=1:KSCmix,j=1:T)
       kai2CDF(j,s) = exp(-0.5d0 * ((logy2(j) - h(j) - KSCmean(s)) / KSCvol(s))** 2) / KSCvol(s) * KSCpdf(s)
    END FORALL

    ! b) convert PDF into CDF for draws
    DO s=2,KSCmix
       kai2CDF(:,s) = kai2CDF(:,s-1) + kai2CDF(:,s)
    END DO
    DO s=1,KSCmix-1
       kai2CDF(:,s) = kai2CDF(:,s) / kai2CDF(:,KSCmix)
    END DO
    kai2CDF(:,KSCmix) = 1.0d0


    ! c) draw kai2states
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, T, u, 0.0d0, 1.0d0 )
    FORALL (j=1:T)
       kai2states(j) = COUNT(u(j) > kai2CDF(j,:)) + 1
    END FORALL


    ! STEP 2: KALMAN FILTER FOR h

    ! construct trend variance and noise variance
    varh = hInno ** 2
    FORALL (j=1:T)
       varnoisemix(j) = KSCvar(kai2states(j))
    END FORALL

    ! demeaned observables 
    FORALL(j=1:T)
       logy2star(j) = logy2(j) - KSCmean(kai2states(j))
    END FORALL
    CALL smoothingsamplerLocalLevel(h,logy2star,T,varh,varnoisemix,Eh0,Vh0,VSLstream)

    SVol = exp(h * 0.5d0)

  END SUBROUTINE stochvolKSCjprwrap

  ! @\newpage\subsection{stochvolKSCar1}@
  SUBROUTINE stochvolKSCar1(SVol, h, hshock, y, T, hInno, rho, Eh0, Vh0, VSLstream)

    ! uses corrected MCMC order as per DelNegro and Primiceri (2013)
    ! same as stochvolKSC, except that kai2states are not used/stored as argument anymore
    ! ... and slight change in the order of arguments ...
    ! this version works with same inputs/outputs as jpr0

    IMPLICIT NONE

    INTENT(IN) :: y, hInno, rho, Eh0, Vh0, T
    INTENT(INOUT) :: VSLstream, SVol
    INTENT(OUT) :: h, hshock

    INTEGER :: T, errcode, j, s
    INTEGER, PARAMETER :: KSCmix = 7
    DOUBLE PRECISION, DIMENSION(KSCmix), PARAMETER :: KSCmean = - 1.2704d0 + (/ -10.12999d0, -3.97281d0, -8.56686d0, 2.77786d0, .61942d0, 1.79518d0, -1.08819d0 /), KSCvar     = (/ 5.79596d0, 2.61369d0, 5.1795d0, .16735d0, .64009d0, .34023d0, 1.26261d0 /), KSCpdf= (/ .0073d0, .10556d0, .00002d0, .04395d0, .34001d0, .24566d0, .25750d0 /), KSCvol = sqrt(KSCvar)

    DOUBLE PRECISION, DIMENSION(T) :: y, logy2, logy2star, volnoisemix, varh, u
    DOUBLE PRECISION, DIMENSION(T,KSCmix) :: kai2CDF
    INTEGER, DIMENSION(T) :: kai2states
    DOUBLE PRECISION, DIMENSION(0:T) :: h, SVol
    DOUBLE PRECISION  :: hInno, rho, Eh0, Vh0, State0(2), sqrtState0V(2,2), State(2,0:T), StateShock(2,1:T)

    ! state space matrices
    DOUBLE PRECISION :: A(2,2,T), B(2,1,T), C(1,2,T), y2noise(T), hshock(T)


    TYPE (vsl_stream_state) :: VSLstream

    ! log-linear observer
    h = 2.0d0 * log(SVol)

    logy2 = log(y ** 2 + 0.001d0)

    ! STEP 1 DRAW KAI2STATES
    ! a) construct PDF for draws (stored in kai2CDF)
    FORALL (s=1:KSCmix,j=1:T)
       kai2CDF(j,s) = exp(-0.5d0 * ((logy2(j) - h(j) - KSCmean(s)) / KSCvol(s))** 2) / KSCvol(s) * KSCpdf(s)
    END FORALL

    ! b) convert PDF into CDF for draws
    DO s=2,KSCmix
       kai2CDF(:,s) = kai2CDF(:,s-1) + kai2CDF(:,s)
    END DO
    DO s=1,KSCmix-1
       kai2CDF(:,s) = kai2CDF(:,s) / kai2CDF(:,KSCmix)
    END DO
    kai2CDF(:,KSCmix) = 1.0d0


    ! c) draw kai2states
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, T, u, 0.0d0, 1.0d0 )
    FORALL (j=1:T)
       kai2states(j) = COUNT(u(j) > kai2CDF(j,:)) + 1
    END FORALL


    ! STEP 2: KALMAN FILTER FOR h

    ! construct trend variance and noise variance
    varh = hInno ** 2
    FORALL (j=1:T)
       volnoisemix(j) = KSCvol(kai2states(j))
    END FORALL

    ! demeaned observables 
    FORALL(j=1:T)
       logy2star(j) = logy2(j) - KSCmean(kai2states(j))
    END FORALL
    ! CALL smoothingsamplerLocalLevel(h,logy2star,T,varh,varnoisemix,Eh0,Vh0,VSLstream)

    ! state space matrices
    A        = 0.0d0
    B        = 0.0d0
    A(1,1,:) = rho
    A(2,2,:) = 1.0d0
    C(1,1,:) = 1.0d0
    C(1,2,:) = 1.0d0
    B(1,1,:) = hInno

    State0(1)        = 0.0d0
    State0(2)        = Eh0
    sqrtState0V      = 0.0d0
    sqrtState0V(1,1) = 0.0d0 ! hInno / sqrt(1 - rho ** 2)
    sqrtState0V(2,2) = sqrt(Vh0)

    CALL samplerA3B3C3noise(State,StateShock,y2noise,logy2star,T,1,2,1,A,B,C,volnoisemix,State0,sqrtState0V,VSLstream,errcode)
    if (errcode /= 0) then
       print *, 'something off with KSCAR1 sampler', errcode
       stop 1
    end if
    ! y2noise is just a dummy

    ! debug
    ! call savemat(A(:,:,1), 'A.debug')
    ! call savemat(B(:,:,1), 'B.debug')
    ! call savemat(C(:,:,1), 'C.debug')
    ! call savemat(State, 'State.debug')
    ! call savemat(StateShock, 'StateShock.debug')
    ! call savevec(State0, 'State0.debug')
    ! call savemat(sqrtState0V, 'sqrtState0V.debug')
    ! stop 33

    h      = State(1,:) + State(2,:)
    hshock = StateShock(1,:)

    SVol = exp(h * 0.5d0)

  END SUBROUTINE stochvolKSCar1
  ! @\newpage\subsection{stochvolKSCar1plus}@
  SUBROUTINE stochvolKSCar1plus(SVol, h, hbar, hshock, y, T, hInno, rho, Eh0, Vh0, VSLstream)

    ! uses corrected MCMC order as per DelNegro and Primiceri (2013)
    ! same as stochvolKSC, except that kai2states are not used/stored as argument anymore
    ! same as stochvolKSCar1 but with extra output for hbar
    ! ... and slight change in the order of arguments ...
    ! this version works with same inputs/outputs as jpr0

    IMPLICIT NONE

    INTENT(IN) :: y, hInno, rho, Eh0, Vh0, T
    INTENT(INOUT) :: VSLstream, SVol
    INTENT(OUT) :: h, hshock, hbar

    INTEGER :: T, errcode, j, s
    INTEGER, PARAMETER :: KSCmix = 7
    DOUBLE PRECISION, DIMENSION(KSCmix), PARAMETER :: KSCmean = - 1.2704d0 + (/ -10.12999d0, -3.97281d0, -8.56686d0, 2.77786d0, .61942d0, 1.79518d0, -1.08819d0 /), KSCvar     = (/ 5.79596d0, 2.61369d0, 5.1795d0, .16735d0, .64009d0, .34023d0, 1.26261d0 /), KSCpdf= (/ .0073d0, .10556d0, .00002d0, .04395d0, .34001d0, .24566d0, .25750d0 /), KSCvol = sqrt(KSCvar)

    DOUBLE PRECISION, DIMENSION(T) :: y, logy2, logy2star, volnoisemix, varh, u
    DOUBLE PRECISION, DIMENSION(T,KSCmix) :: kai2CDF
    INTEGER, DIMENSION(T) :: kai2states
    DOUBLE PRECISION, DIMENSION(0:T) :: h, SVol
    DOUBLE PRECISION  :: hInno, rho, hbar, Eh0, Vh0, State0(2), sqrtState0V(2,2), State(2,0:T), StateShock(2,1:T)

    ! state space matrices
    DOUBLE PRECISION :: A(2,2,T), B(2,1,T), C(1,2,T), y2noise(T), hshock(T)


    TYPE (vsl_stream_state) :: VSLstream

    ! log-linear observer
    h = 2.0d0 * log(SVol)

    logy2 = log(y ** 2 + 0.001d0)

    ! STEP 1 DRAW KAI2STATES
    ! a) construct PDF for draws (stored in kai2CDF)
    FORALL (s=1:KSCmix,j=1:T)
       kai2CDF(j,s) = exp(-0.5d0 * ((logy2(j) - h(j) - KSCmean(s)) / KSCvol(s))** 2) / KSCvol(s) * KSCpdf(s)
    END FORALL

    ! b) convert PDF into CDF for draws
    DO s=2,KSCmix
       kai2CDF(:,s) = kai2CDF(:,s-1) + kai2CDF(:,s)
    END DO
    DO s=1,KSCmix-1
       kai2CDF(:,s) = kai2CDF(:,s) / kai2CDF(:,KSCmix)
    END DO
    kai2CDF(:,KSCmix) = 1.0d0


    ! c) draw kai2states
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, T, u, 0.0d0, 1.0d0 )
    FORALL (j=1:T)
       kai2states(j) = COUNT(u(j) > kai2CDF(j,:)) + 1
    END FORALL


    ! STEP 2: KALMAN FILTER FOR h

    ! construct trend variance and noise variance
    varh = hInno ** 2
    FORALL (j=1:T)
       volnoisemix(j) = KSCvol(kai2states(j))
    END FORALL

    ! demeaned observables 
    FORALL(j=1:T)
       logy2star(j) = logy2(j) - KSCmean(kai2states(j))
    END FORALL
    ! CALL smoothingsamplerLocalLevel(h,logy2star,T,varh,varnoisemix,Eh0,Vh0,VSLstream)

    ! state space matrices
    A        = 0.0d0
    B        = 0.0d0
    A(1,1,:) = rho
    A(2,2,:) = 1.0d0
    C(1,1,:) = 1.0d0
    C(1,2,:) = 1.0d0
    B(1,1,:) = hInno

    State0(1)        = 0.0d0
    State0(2)        = Eh0
    sqrtState0V      = 0.0d0
    sqrtState0V(1,1) = 0.0d0 ! hInno / sqrt(1 - rho ** 2)
    sqrtState0V(2,2) = sqrt(Vh0)

    CALL samplerA3B3C3noise(State,StateShock,y2noise,logy2star,T,1,2,1,A,B,C,volnoisemix,State0,sqrtState0V,VSLstream,errcode)
    if (errcode /= 0) then
       print *, 'something off with KSCAR1 sampler', errcode
       stop 1
    end if
    ! y2noise is just a dummy

    ! debug
    ! call savemat(A(:,:,1), 'A.debug')
    ! call savemat(B(:,:,1), 'B.debug')
    ! call savemat(C(:,:,1), 'C.debug')
    ! call savemat(State, 'State.debug')
    ! call savemat(StateShock, 'StateShock.debug')
    ! call savevec(State0, 'State0.debug')
    ! call savemat(sqrtState0V, 'sqrtState0V.debug')
    ! stop 33

    h      = State(1,:) + State(2,:)
    hshock = StateShock(1,:)
    hbar   = State(2,0)

    SVol = exp(h * 0.5d0)

  END SUBROUTINE stochvolKSCar1plus

  ! @\newpage\subsection{igammaDraw}@
  SUBROUTINE igammaDraw(draw, sigma0T, dof0, VSLstream)

    INTENT(INOUT) :: draw, VSLstream
    INTENT(IN)    :: sigma0T, dof0

    INTEGER :: dof0, errcode
    type (vsl_stream_state) :: VSLstream

    ! DOUBLE PRECISION, DIMENSION(dof0) :: z
    DOUBLE PRECISION :: sigma0T, draw 
    double precision :: thisdraw(1)


    ! draw
    ! errcode    = vdrnggaussian(VSLmethodGaussian, VSLstream, dof0, z, 0.0d0, 1.0d0)
    ! draw = sigma0T / sum(z ** 2)

    ! faster: 
    errcode    = vdrngchisquare(VSLmethodChisquare, VSLstream, 1, thisdraw, dof0)
    draw       = sigma0T / thisdraw(1)

  END SUBROUTINE igammaDraw

  ! @\newpage\subsection{igammaDraws}@ 
  SUBROUTINE igammaDrawN(draw, N, sigma0T, dof0, VSLstream)
    ! assumes sigma0T is 1-dimensional
    ! new implementation by calling VSL-chisquare RNG (instead of homemade sim)

    INTENT(INOUT) :: draw, VSLstream
    INTENT(IN)    :: N, sigma0T, dof0

    INTEGER :: dof0, errcode
    type (vsl_stream_state) :: VSLstream

    INTEGER :: N

    DOUBLE PRECISION, DIMENSION(N) :: chisquares
    DOUBLE PRECISION :: sigma0T
    DOUBLE PRECISION, DIMENSION(N) :: draw

    ! errcode    = vdrnggaussian(VSLmethodGaussian, VSLstream, dof0 * N, z, 0.0d0, 1.0d0)
    ! draw       = sigma0T / sum(z ** 2,1)

    errcode    = vdrngchisquare(VSLmethodChisquare, VSLstream, N, chisquares, dof0)
    draw       = sigma0T / chisquares


  END SUBROUTINE igammaDrawN

  ! @\newpage\subsection{igammaDraws}@ 
  SUBROUTINE igammaDraws(draw, N, sigma0T, dof0, VSLstream)
    ! assumes sigma0T is N-dimensional
    ! new implementation by calling VSL-chisquare RNG (instead of homemade sim)

    INTENT(INOUT) :: draw, VSLstream
    INTENT(IN)    :: N, sigma0T, dof0

    INTEGER :: dof0, errcode
    type (vsl_stream_state) :: VSLstream

    INTEGER :: N

    DOUBLE PRECISION, DIMENSION(N) :: chisquares
    DOUBLE PRECISION, DIMENSION(N) :: sigma0T
    DOUBLE PRECISION, DIMENSION(N) :: draw

    ! errcode    = vdrnggaussian(VSLmethodGaussian, VSLstream, dof0 * N, z, 0.0d0, 1.0d0)
    ! draw       = sigma0T / sum(z ** 2,1)

    errcode    = vdrngchisquare(VSLmethodChisquare, VSLstream, N, chisquares, dof0)
    draw       = sigma0T / chisquares


  END SUBROUTINE igammaDraws

  ! @\newpage\subsection{varianceDraw}@
  SUBROUTINE varianceDraw(igammadraw, sigma0T, dof0, resid, Nobs, VSLstream)

    INTENT(INOUT) :: igammadraw, VSLstream
    INTENT(IN)    :: resid, Nobs, sigma0T, dof0

    INTEGER :: Nobs, dof, dof0, errcode
    type (vsl_stream_state) :: VSLstream

    DOUBLE PRECISION, DIMENSION(Nobs) :: resid
    DOUBLE PRECISION, DIMENSION(dof0 + Nobs) :: z
    DOUBLE PRECISION :: sigmaT, sigma0T, igammadraw


    ! compute posterior
    dof     = dof0 + Nobs
    sigmaT  = sigma0T + sum(resid ** 2)

    ! draw
    errcode    = vdrnggaussian(VSLmethodGaussian, VSLstream, dof, z, 0.0d0, 1.0d0)
    igammadraw = sigmaT / sum(z ** 2)

    ! if (igammadraw < 0.0d0) then 
    !    print *, 'houston'
    !    print *, sigma0T
    !    print *, sigmaT
    !    print *, dof
    !    print *, sum(z ** 2)
    !    stop 33
    ! end if

  END SUBROUTINE varianceDraw

  ! @\newpage\subsection{iwishDraw}@
  SUBROUTINE iwishDraw(iwdraw, SigmaT, dof, Ny, VSLstream)

    ! SigmaT is supposed to be in upper triangular storage 

    INTENT(INOUT) :: iwdraw, VSLstream
    INTENT(IN)    :: SigmaT, dof, Ny

    INTEGER :: dof, errcode, Ny
    type (vsl_stream_state) :: VSLstream

    DOUBLE PRECISION, DIMENSION(Ny, dof) :: z
    DOUBLE PRECISION, DIMENSION(Ny,Ny) :: SigmaT, work, iwdraw
    ! INTEGER, DIMENSION(Ny) :: ipiv ! helper variable for dgetrs 


    ! ztilde = SigmaT^{-.5}' z
    work = SigmaT
    ! choleski of SigmaT
    call DPOTRF('U', Ny, work, Ny, errcode)
    ! zero out lower triangular portion of the choleski --should not be necessary though
    ! FORALL (ii = 1 : Ny-1) work(ii+1:Ny,ii) = 0 

    ! draw z
    errcode    = vdrnggaussian(VSLmethodGaussian, VSLstream, Ny * dof, z, 0.0d0, 1.0d0)

    ! compute ztilde
    ! FORALL (ii = 1 : Ny) ipiv(ii) = ii
    ! dummy = z
    ! call DGETRS('N', Ny, dof, work, Ny, IPIV, dummy, Ny, errcode) 
    ! call savemat(dummy, 'dummy.debug')
    call DTRTRS('U', 'N', 'N', Ny, dof, work, Ny, z, Ny, errcode)
    IF (errcode /= 0)  THEN
       WRITE(*,*) "DTRTRS error:", errcode, '[iwishdraw]'
       STOP 1
    END IF


    ! wishdraw = ztilde * ztilde'
    call XXprime(iwdraw, z) ! recall: upper triangular storage
    call invsym(iwdraw)

  END SUBROUTINE iwishDraw
  ! @\newpage\subsection{iwishcholDraw}@
  SUBROUTINE iwishcholDraw(iwcdraw, SigmaT, dof, Ny, VSLstream)

    ! returns choleski of iwishdraw (however: chol is LHS-upper triangular)

    ! SigmaT is supposed to be in upper triangular storage 

    INTENT(INOUT) :: iwcdraw, VSLstream
    INTENT(IN)    :: SigmaT, dof, Ny

    INTEGER :: dof, errcode, Ny
    type (vsl_stream_state) :: VSLstream

    DOUBLE PRECISION, DIMENSION(Ny, dof) :: z
    DOUBLE PRECISION, DIMENSION(Ny,Ny) :: SigmaT, iwcdraw
    ! INTEGER, DIMENSION(Ny) :: ipiv ! helper variable for dgetrs 


    IF (dof < Ny) THEN
       WRITE(*,*) "IWISHCHOLDRAW: need dof at least as large as Ny"
       STOP 1
    END IF


    ! ztilde = SigmaT^{-.5}' z
    iwcdraw = SigmaT
    ! choleski of SigmaT
    call DPOTRF('U', Ny, iwcdraw, Ny, errcode)
    ! zero out lower triangular portion of the choleski --should not be necessary though
    ! FORALL (ii = 1 : Ny-1) iwcdraw(ii+1:Ny,ii) = 0 

    ! draw z
    errcode    = vdrnggaussian(VSLmethodGaussian, VSLstream, Ny * dof, z, 0.0d0, 1.0d0)

    ! compute ztilde
    ! FORALL (ii = 1 : Ny) ipiv(ii) = ii
    ! call DGETRS('N', Ny, dof, work, Ny, IPIV, z, Ny, errcode) 
    call DTRTRS('U', 'N', 'N', Ny, dof, iwcdraw, Ny, z, Ny, errcode)
    IF (errcode /= 0)  THEN
       WRITE(*,*) "DTRTRS error:", errcode, '[iwishcholdraw]'
       STOP 1
    END IF

    ! work = ztilde * ztilde' (wishart draw)
    iwcdraw = 0.0d0 ! ensures that matrix remains lower triangular
    call DSYRK('U','N',Ny,dof,1.0d0,z,Ny,0.0d0,iwcdraw,Ny)

    ! chol(wishdraw)
    call DPOTRF('U', Ny, iwcdraw, Ny, errcode)
    IF (errcode /= 0) THEN
       write(*,*) "DPOTRF ERROR:", errcode, "[iwishcholDRAW]"
       STOP 1
    END IF

    call DTRTRI('U', 'N', Ny, iwcdraw, Ny, errcode)
    IF (errcode /= 0) THEN
       write(*,*) "DTRTRI ERROR:", errcode, "[iwishcholDRAW]"
       STOP 1
    END IF

    ! call savemat(iwcdraw, 'iwc1.debug')
    ! FORALL (ii = 1 : Ny-1) work(ii+1:Ny,ii) = 0
    ! FORALL (ii = 1 : Ny) ipiv(ii) = ii
    ! call eye(iwcdraw)
    ! call DGETRS ('N', Ny, Ny, work, Ny, IPIV, iwcdraw, Ny,errcode) 
    ! call savemat(iwcdraw, 'iwc2.debug')
    ! stop 22

  END SUBROUTINE iwishcholDraw

  ! @\newpage\subsection{vcvcholDrawTR}@
  SUBROUTINE vcvcholDrawTR(iwishcholdraw, Sigma0T, dof0, resid, T, Ny, VSLstream)

    ! SigmaT is supposed to be in upper triangular storage
    ! same as vcvcholdraw, except for better exploiting triangular storage

    ! NOTE: returns upper LEFT choleski factor!!!

    INTENT(OUT)   :: iwishcholdraw
    INTENT(INOUT) :: VSLstream
    INTENT(IN)    :: resid, T, Ny, Sigma0T, dof0

    INTEGER :: T, dof, dof0, errcode, Ny
    type (vsl_stream_state) :: VSLstream

    DOUBLE PRECISION, DIMENSION(T,Ny) :: resid
    DOUBLE PRECISION, DIMENSION(Ny, dof0 + T) :: z
    DOUBLE PRECISION, DIMENSION(Ny,Ny) :: Sigma0T, SigmaT, iwishcholdraw
    ! INTEGER, DIMENSION(Ny) :: ipiv


    ! compute posterior
    dof     = dof0 + T

    ! SigmaT = resid' * resid + Sigma0T 
    SigmaT = Sigma0T
    call DSYRK('U','T',Ny,T,1.0d0,resid,T,1.0d0,SigmaT,Ny) 

    ! choleski of SigmaT
    call DPOTRF('U', Ny, SigmaT, Ny, errcode)
    IF (errcode /= 0) THEN
       write(*,*) "DPOTRF ERROR:", errcode, "[VCVCHOLDRAW: SIGMAT]"
       STOP 1
    END IF
    ! FORALL (ii = 1 : Ny-1) SigmaT(ii+1:Ny,ii) = 0

    ! ztilde = SigmaT^{-.5}' z
    errcode    = vdrnggaussian(VSLmethodGaussian, VSLstream, Ny * dof, z, 0.0d0, 1.0d0)
    ! FORALL (ii = 1 : Ny) ipiv(ii) = ii
    ! call DGETRS('N', Ny, dof, SigmaT, Ny, IPIV, z, Ny, errcode)
    call DTRTRS('U', 'N', 'N', Ny, dof, SigmaT, Ny, z, Ny, errcode)
    IF (errcode /= 0)  THEN
       WRITE(*,*) "DTRTRS error:", errcode
       STOP 1
    END IF

    ! wishdraw = ztilde * ztilde'
    iwishcholdraw = 0.0d0 ! this ensure that iwishcholdraw is properly lower triangular
    call DSYRK('U','N',Ny,dof,1.0d0,z,Ny,0.0d0,iwishcholdraw,Ny)
    ! chol(wishdraw)
    call DPOTRF('U', Ny, iwishcholdraw, Ny, errcode)
    IF (errcode /= 0) THEN
       write(*,*) "DPOTRF ERROR:", errcode, "[VCVCHOLDRAW: iwishcholdraw]"
       call savemat(resid, 'resid.debug')
       STOP 1
    END IF

    ! invert chol(wishdraw)
    call DTRTRI('U', 'N', Ny, iwishcholdraw, Ny, errcode)
    IF (errcode /= 0) THEN
       write(*,*) "DTRTRI ERROR:", errcode, "[VCVCHOLDRAW]"
       STOP 1
    END IF

  END SUBROUTINE vcvcholDrawTR


  ! @\newpage\subsection{bayesregcholeski}@
  SUBROUTINE bayesregcholeski(T, Ny, SVol, shockslopes, Nslopes, y, E0slopes, iV0slopes, VSLstream)

    ! h = log(SVol ** 2)

    INTENT(INOUT) ::VSLstream, y
    INTENT(IN) :: T, Ny, E0slopes, iV0slopes, SVOL
    INTENT(OUT) :: shockslopes

    INTEGER :: i, k, T, Ny, Nslopes, offset, these
    DOUBLE PRECISION :: SVol(Ny,0:T), y(Ny,T), E0slopes(Nslopes), iV0slopes(Nslopes, Nslopes), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream


    DOUBLE PRECISION :: lhs(T), rhs(T,Ny-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    offset = 0
    DO i=2,Ny
       these = i - 1

       FORALL (k=1:T) lhs(k)       = y(i,k) / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:i-1) = y(1:i-1,k) / SVol(i,k)

       ! slope indices are offset+1:offset+these
       call bayesRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, E0slopes(offset+1:offset+these), iV0slopes(offset+1:offset+these,offset+1:offset+these), VSLstream)

       FORALL (k=1:T) y(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO

  END SUBROUTINE bayesregcholeski

  ! @\newpage\subsection{bayesregcholeskidiffuseNorth}@
  SUBROUTINE bayesregcholeskidiffuseNorth(T, Ny, North, SVol, shockslopes, Nslopes, y, VSLstream)
    ! treats first North elements of y as orthogonal to each others, but with possible spillovers to the remaining Ny-North elements
    ! shocklopes and Nslopes is still Ny * (Ny-1) / 2 and the first North * (North -1) / 2 elements are set to zero
    ! h = log(SVol ** 2)

    INTENT(INOUT) :: VSLstream, y
    INTENT(IN) :: T, Ny, North, SVOL
    INTENT(OUT) :: shockslopes

    INTEGER :: i, k, T, Ny, North, Nslopes, offset, these
    DOUBLE PRECISION :: SVol(Ny,0:T), y(Ny,T), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream


    DOUBLE PRECISION :: lhs(T), rhs(T,Ny-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    offset = North * (North - 1) / 2
    shockslopes(1:offset) = 0.0d0
    DO i=North+2,Ny
       these = i - 1

       FORALL (k=1:T) lhs(k)       = y(i,k) / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:i-1) = y(1:i-1,k) / SVol(i,k)

       ! slope indices are offset+1:offset+thesed
       call bayesDiffuseRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, VSLstream)

       FORALL (k=1:T) y(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO

  END SUBROUTINE bayesregcholeskidiffuseNorth

  ! @\newpage\subsection{bayesregcholeskidiffuse}@
  SUBROUTINE bayesregcholeskidiffuse(T, Ny, SVol, shockslopes, Nslopes, y, VSLstream)

    ! h = log(SVol ** 2)

    INTENT(INOUT) :: VSLstream, y
    INTENT(IN) :: T, Ny, SVOL
    INTENT(OUT) :: shockslopes

    INTEGER :: i, k, T, Ny, Nslopes, offset, these
    DOUBLE PRECISION :: SVol(Ny,0:T), y(Ny,T), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream


    DOUBLE PRECISION :: lhs(T), rhs(T,Ny-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    offset = 0
    DO i=2,Ny
       these = i - 1

       FORALL (k=1:T) lhs(k)       = y(i,k) / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:i-1) = y(1:i-1,k) / SVol(i,k)

       ! slope indices are offset+1:offset+thesed
       call bayesDiffuseRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, VSLstream)

       FORALL (k=1:T) y(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO

  END SUBROUTINE bayesregcholeskidiffuse


  ! @\newpage\subsection{commonstochvolRW}@
  SUBROUTINE commonstochvolRW(h, hshock, y, Ny, T, hInno, VSLstream)

    ! uses corrected MCMC order as per DelNegro and Primiceri (2013)
    ! same as stochvolKSC, except that kai2states are not used/stored as argument anymore
    ! ... and slight change in the order of arguments ...

    IMPLICIT NONE

    INTENT(IN) :: y, hInno, T, Ny
    INTENT(INOUT) :: VSLstream
    INTENT(INOUT) :: h, hshock

    INTEGER :: Ny, T, errcode, j, s, k
    INTEGER, PARAMETER :: KSCmix = 7
    DOUBLE PRECISION, DIMENSION(KSCmix), PARAMETER :: KSCmean = - 1.2704d0 + (/ -10.12999d0, -3.97281d0, -8.56686d0, 2.77786d0, .61942d0, 1.79518d0, -1.08819d0 /), KSCvar     = (/ 5.79596d0, 2.61369d0, 5.1795d0, .16735d0, .64009d0, .34023d0, 1.26261d0 /), KSCpdf= (/ .0073d0, .10556d0, .00002d0, .04395d0, .34001d0, .24566d0, .25750d0 /), KSCvol = sqrt(KSCvar)
    DOUBLE PRECISION, DIMENSION(Ny,T,KSCmix) :: kai2CDF
    INTEGER, DIMENSION(Ny,T) :: kai2states

    DOUBLE PRECISION, DIMENSION(Ny,T) :: y, logy2, logy2star, volnoisemix, u

    DOUBLE PRECISION, DIMENSION(0:T) :: h
    DOUBLE PRECISION, DIMENSION(T) :: hshock
    DOUBLE PRECISION, DIMENSION(Ny,T) :: dummynoise
    DOUBLE PRECISION  :: hInno
    DOUBLE PRECISION, PARAMETER  :: State0(1) = 0.0d0, sqrtV0(1) = 0.0d0

    ! KSC state space
    DOUBLE PRECISION :: a(T), b(T), c(Ny,1,T)

    TYPE (vsl_stream_state) :: VSLstream

    ! log-linear observer
    logy2 = log(y ** 2 + 0.001d0)

    ! STEP 1 DRAW KAI2STATES
      ! a) construct PDF for draws (stored in kai2CDF)
    FORALL (s=1:KSCmix,k=1:Ny,j=1:T)
       kai2CDF(k,j,s) = exp(-0.5d0 * ((logy2(k,j) - h(j) - KSCmean(s)) / KSCvol(s))** 2) / KSCvol(s) * KSCpdf(s)
    END FORALL

    ! b) convert PDF into CDF for draws
    DO s=2,KSCmix
       kai2CDF(:,:,s) = kai2CDF(:,:,s-1) + kai2CDF(:,:,s)
    END DO
    DO s=1,KSCmix-1
       kai2CDF(:,:,s) = kai2CDF(:,:,s) / kai2CDF(:,:,KSCmix)
    END DO
    kai2CDF(:,:,KSCmix) = 1.0d0


    ! c) draw kai2states
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, Ny * T, u, 0.0d0, 1.0d0 )
    FORALL (k=1:Ny,j=1:T)
       kai2states(k,j) = COUNT(u(k,j) > kai2CDF(k,j,:)) + 1
    END FORALL
    ! prepare initial trend variance and noise variance
    FORALL (k=1:Ny,j=1:T)
       volnoisemix(k,j) = KSCvol(kai2states(k,j))
    END FORALL
    ! demeaned observables 
    FORALL(k=1:Ny,j=1:T)
       logy2star(k,j) = logy2(k,j) - KSCmean(kai2states(k,j))
    END FORALL

    ! STEP 2: KALMAN FILTER FOR h
    ! state space matrices
    a = 1.0d0
    b = hInno
    C = 0.0d0
    FORALL(k=1:Ny,j=1:T) C(k,1,j) = 1.0d0
    
  
    CALL samplerA3B3C3noise(h,hshock,dummynoise,logy2star,T,Ny,1,1,a,b,c,volnoisemix,State0,sqrtV0,VSLstream,errcode)
    if (errcode /= 0) then
       print *, 'something off with KSC sampler', errcode
       stop 1
    end if


  END SUBROUTINE commonstochvolRW

  ! @\newpage\subsection{SVHrwcor}@
  SUBROUTINE SVHrwcor(T, Nsv, SVol, h, hshock, y, sqrtVhshock, Eh0, sqrtVh0, VSLstream)

    ! h = log(SVol ** 2)

    INTENT(INOUT) :: SVol, VSLstream, y
    INTENT(IN) :: T,Nsv, sqrtVhshock, Eh0, sqrtVh0
    INTENT(OUT) :: hshock, h

    INTEGER :: s, j, k, T, Nsv,  errcode
    DOUBLE PRECISION :: sqrtVhshock(Nsv,Nsv), Eh0(Nsv), sqrtVh0(Nsv,Nsv)
    TYPE (vsl_stream_state) :: VSLstream

    ! KSC mixture
    INTEGER, PARAMETER :: KSCmix = 7
    DOUBLE PRECISION, DIMENSION(KSCmix), PARAMETER :: KSCmean = - 1.2704d0 + (/ -10.12999d0, -3.97281d0, -8.56686d0, 2.77786d0, .61942d0, 1.79518d0, -1.08819d0 /), KSCvar     = (/ 5.79596d0, 2.61369d0, 5.1795d0, .16735d0, .64009d0, .34023d0, 1.26261d0 /), KSCpdf= (/ .0073d0, .10556d0, .00002d0, .04395d0, .34001d0, .24566d0, .25750d0 /), KSCvol = sqrt(KSCvar)
    DOUBLE PRECISION, DIMENSION(Nsv,T,KSCmix) :: kai2CDF
    INTEGER, DIMENSION(Nsv,T) :: kai2states


    DOUBLE PRECISION, DIMENSION(Nsv,T) :: y, logy2, logy2star, volnoisemix, u
    DOUBLE PRECISION, DIMENSION(Nsv,0:T) :: h, SVol
    DOUBLE PRECISION, DIMENSION(Nsv,1:T) :: hshock

    ! state space matrices
    DOUBLE PRECISION :: A(Nsv,Nsv,T), B(Nsv,Nsv,T), C(Nsv,Nsv,T), y2noise(Nsv,T), State(Nsv,0:T), StateShock(Nsv,1:T), sqrtState0V(Nsv,Nsv), State0(Nsv)

    ! log-linear observer
    logy2 = log(y ** 2 + 0.001d0)
    h     = 2.0d0 * log(SVol) 

    ! PART 2, STEP 1: DRAW KAI2STATES
    ! a) construct PDF for draws (stored in kai2CDF)
    FORALL (s=1:KSCmix,k=1:Nsv,j=1:T)
       kai2CDF(k,j,s) = exp(-0.5d0 * ((logy2(k,j) - h(k,j) - KSCmean(s)) / KSCvol(s))** 2) / KSCvol(s) * KSCpdf(s)
    END FORALL

    ! b) convert PDF into CDF for draws
    DO s=2,KSCmix
       kai2CDF(:,:,s) = kai2CDF(:,:,s-1) + kai2CDF(:,:,s)
    END DO
    DO s=1,KSCmix-1
       kai2CDF(:,:,s) = kai2CDF(:,:,s) / kai2CDF(:,:,KSCmix)
    END DO
    kai2CDF(:,:,KSCmix) = 1.0d0


    ! c) draw kai2states
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, Nsv * T, u, 0.0d0, 1.0d0 )
    FORALL (k=1:Nsv,j=1:T)
       kai2states(k,j) = COUNT(u(k,j) > kai2CDF(k,j,:)) + 1
    END FORALL


    ! PART 2, STEP 2: KALMAN FILTER FOR h

    ! prepare initial trend variance and noise variance
    FORALL (k=1:Nsv,j=1:T)
       volnoisemix(k,j) = KSCvol(kai2states(k,j))
    END FORALL

    ! demeaned observables 
    FORALL(k=1:Nsv,j=1:T)
       logy2star(k,j) = logy2(k,j) - KSCmean(kai2states(k,j))
    END FORALL

    ! state space matrices
    A = 0.0d0
    FORALL(k=1:Nsv,j=1:T) A(k,k,j) = 1.0d0

    B = 0.0d0
    FORALL(j=1:T) B(1:Nsv,1:Nsv,j) = sqrtVhshock

    C = 0.0d0
    FORALL(k=1:Nsv,j=1:T) C(k,k,j) = 1.0d0

    ! note: redundancy with State0 sqrtState0V
    State0 = Eh0
    sqrtState0V = sqrtVh0

    CALL samplerA3B3C3noise(State,StateShock,y2noise,logy2star,T,Nsv,Nsv,Nsv,A,B,C,volnoisemix,State0,sqrtState0V,VSLstream,errcode)
    if (errcode /= 0) then
       print *, 'something off with KSCvec sampler', errcode
       stop 1
    end if

    ! again: get rid of redundancy
    h      = State(1:Nsv,:)
    hshock = StateShock(1:Nsv,:) 

    SVol   = exp(h * 0.5d0)



  END SUBROUTINE SVHrwcor


  ! @\newpage\subsection{SVHdiffusecholeskiKSC}@
  SUBROUTINE SVHdiffusecholeskiKSC(T, Ny, SVol, h, shockslopes, Nslopes, y, hInno, E0h, V0h, VSLstream)

    INTENT(INOUT) :: SVol, VSLstream, y
    INTENT(IN) :: T,Ny, hInno, E0h, V0h
    INTENT(OUT) :: shockslopes, h

    INTEGER :: i, k, T, Ny, Nslopes, offset, these
    DOUBLE PRECISION :: h(Ny,0:T), SVol(Ny,0:T), y(Ny,T), hInno(Ny), E0h(Ny), V0h(Ny), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream


    DOUBLE PRECISION :: lhs(T), rhs(T,Ny-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    ! PART 1: Shockslopes
    offset = 0
    DO i=2,Ny
       these = i - 1

       FORALL (k=1:T) lhs(k)       = y(i,k) / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:i-1) = y(1:i-1,k) / SVol(i,k)

       ! slope indices are offset+1:offset+these
       ! call bayesRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, E0slopes(offset+1:offset+these), iV0slopes(offset+1:offset+these,offset+1:offset+these), VSLstream)
       call bayesdiffuseRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, VSLstream)

       FORALL (k=1:T) y(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO


    ! PART 2: SV
    DO i = 1,Ny
       CALL stochvolKSCjprwrap(SVol(i,:), h(i,:), y(i,:), T, hInno(i), E0h(i), V0h(i), VSLstream)
    END DO

  END SUBROUTINE SVHdiffusecholeskiKSC

  ! @\newpage\subsection{SVHcholeskiKSC}@
  SUBROUTINE SVHcholeskiKSC(T, Ny, SVol, h, shockslopes, Nslopes, y, E0slopes, iV0slopes, hInno, E0h, V0h, VSLstream)

    ! h = log(SVol ** 2)

    INTENT(INOUT) :: SVol, VSLstream, h
    INTENT(IN) :: T,Ny, E0slopes, iV0slopes, hInno, E0h, V0h, y
    INTENT(OUT) :: shockslopes

    INTEGER :: i, k, T, Ny, Nslopes, offset, these
    DOUBLE PRECISION :: h(Ny,0:T), SVol(Ny,0:T), resid(Ny,T), y(Ny,T), E0slopes(Nslopes), iV0slopes(Nslopes, Nslopes), hInno(Ny), E0h(Ny), V0h(Ny), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream


    DOUBLE PRECISION :: lhs(T), rhs(T,Ny-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    resid = y

    ! PART 1: Shockslopes
    offset = 0
    DO i=2,Ny
       these = i - 1

       FORALL (k=1:T) lhs(k)       = resid(i,k) / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:i-1) = resid(1:i-1,k) / SVol(i,k)

       ! slope indices are offset+1:offset+these
       call bayesRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, E0slopes(offset+1:offset+these), iV0slopes(offset+1:offset+these,offset+1:offset+these), VSLstream)

       FORALL (k=1:T) resid(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO


    ! PART 2: SV
    DO i = 1,Ny
       CALL stochvolKSCjprwrap(SVol(i,:), h(i,:), resid(i,:), T, hInno(i), E0h(i), V0h(i), VSLstream)
    END DO

  END SUBROUTINE SVHcholeskiKSC

  ! @\newpage\subsection{SVHcholeskiKSCAR1}@
  SUBROUTINE SVHcholeskiKSCAR1(T, Ny, SVol, h, hshock, shockslopes, Nslopes, y, E0slopes, iV0slopes, hInno, hrho, E0h, V0h, VSLstream)

    ! note: adding hrho breaks backwards comptatibility with older code ...

    ! h = log(SVol ** 2)

    INTENT(INOUT) :: SVol, VSLstream, h
    INTENT(IN) :: T,Ny, E0slopes, iV0slopes, hrho, hInno, E0h, V0h, y
    INTENT(OUT) :: shockslopes, hshock

    INTEGER :: i, k, T, Ny, Nslopes, offset, these
    DOUBLE PRECISION :: h(Ny,0:T), hshock(Ny,T), SVol(Ny,0:T), y(Ny,T), resid(Ny,T), E0slopes(Nslopes), iV0slopes(Nslopes, Nslopes), hrho(Ny), hInno(Ny), E0h(Ny), V0h(Ny), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream


    DOUBLE PRECISION :: lhs(T), rhs(T,Ny-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    resid = y
    ! PART 1: Shockslopes
    offset = 0
    DO i=2,Ny
       these = i - 1

       FORALL (k=1:T) lhs(k)       = resid(i,k) / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:i-1) = resid(1:i-1,k) / SVol(i,k)

       ! slope indices are offset+1:offset+these
       call bayesRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, E0slopes(offset+1:offset+these), iV0slopes(offset+1:offset+these,offset+1:offset+these), VSLstream)

       FORALL (k=1:T) resid(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO


    ! PART 2: SV
    DO i = 1,Ny
       CALL stochvolKSCar1(SVol(i,:), h(i,:), hshock(i,:), resid(i,:), T, hInno(i), hrho(i), E0h(i), V0h(i), VSLstream)
    END DO

  END SUBROUTINE SVHcholeskiKSCAR1

  ! @\newpage\subsection{SVHcholeskiAR1diffuseslopes}@
  SUBROUTINE SVHcholeskiAR1diffuseslopes(T, Ny, SVol, h, hshock, shockslopes, Nslopes, y, hInno, hrho, E0h, V0h, VSLstream)

    ! note: adding hrho breaks backwards comptatibility with older code ...

    ! h = log(SVol ** 2)

    INTENT(INOUT) :: SVol, VSLstream, h
    INTENT(IN) :: T,Ny, hrho, hInno, E0h, V0h, y
    INTENT(OUT) :: shockslopes, hshock

    INTEGER :: i, k, T, Ny, Nslopes, offset, these
    DOUBLE PRECISION :: h(Ny,0:T), hshock(Ny,T), SVol(Ny,0:T), y(Ny,T), resid(Ny,T), hrho(Ny), hInno(Ny), E0h(Ny), V0h(Ny), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream


    DOUBLE PRECISION :: lhs(T), rhs(T,Ny-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    resid = y
    ! PART 1: Shockslopes
    offset = 0
    DO i=2,Ny
       these = i - 1

       FORALL (k=1:T) lhs(k)       = resid(i,k) / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:i-1) = resid(1:i-1,k) / SVol(i,k)

       ! slope indices are offset+1:offset+these
       call bayesdiffuseRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, VSLstream)

       FORALL (k=1:T) resid(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO


    ! PART 2: SV
    DO i = 1,Ny
       CALL stochvolKSCar1(SVol(i,:), h(i,:), hshock(i,:), resid(i,:), T, hInno(i), hrho(i), E0h(i), V0h(i), VSLstream)
    END DO

  END SUBROUTINE SVHcholeskiAR1diffuseslopes

  ! @\newpage\subsection{SVHcholeskiKSCAR1plus}@
  SUBROUTINE SVHcholeskiKSCAR1plus(T, Ny, SVol, h, hbar, hshock, shockslopes, Nslopes, y, E0slopes, iV0slopes, hInno, hrho, E0h, V0h, VSLstream)

    ! note: adding hrho breaks backwards comptatibility with older code ...

    ! h = log(SVol ** 2)

    INTENT(INOUT) :: SVol, VSLstream, h
    INTENT(IN) :: T,Ny, E0slopes, iV0slopes, hrho, hInno, E0h, V0h, y
    INTENT(OUT) :: shockslopes, hshock, hbar

    INTEGER :: i, k, T, Ny, Nslopes, offset, these
    DOUBLE PRECISION :: h(Ny,0:T), hbar(Ny), hshock(Ny,T), SVol(Ny,0:T), y(Ny,T), resid(Ny,T), E0slopes(Nslopes), iV0slopes(Nslopes, Nslopes), hrho(Ny), hInno(Ny), E0h(Ny), V0h(Ny), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream


    DOUBLE PRECISION :: lhs(T), rhs(T,Ny-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    resid = y
    ! PART 1: Shockslopes
    offset = 0
    DO i=2,Ny
       these = i - 1

       FORALL (k=1:T) lhs(k)       = resid(i,k) / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:i-1) = resid(1:i-1,k) / SVol(i,k)

       ! slope indices are offset+1:offset+these
       call bayesRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, E0slopes(offset+1:offset+these), iV0slopes(offset+1:offset+these,offset+1:offset+these), VSLstream)

       FORALL (k=1:T) resid(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO


    ! PART 2: SV
    DO i = 1,Ny
       CALL stochvolKSCar1plus(SVol(i,:), h(i,:), hbar(i), hshock(i,:), resid(i,:), T, hInno(i), hrho(i), E0h(i), V0h(i), VSLstream)
    END DO

  END SUBROUTINE SVHcholeskiKSCAR1plus

  ! @\newpage\subsection{SVHcholeskiAR1diffuseslopesplus}@
  SUBROUTINE SVHcholeskiAR1diffuseslopesplus(T, Ny, SVol, h, hbar, hshock, shockslopes, Nslopes, y, hInno, hrho, E0h, V0h, VSLstream)

    ! note: adding hrho breaks backwards comptatibility with older code ...

    ! h = log(SVol ** 2)

    INTENT(INOUT) :: SVol, VSLstream, h
    INTENT(IN) :: T,Ny, hrho, hInno, E0h, V0h, y
    INTENT(OUT) :: shockslopes, hshock, hbar

    INTEGER :: i, k, T, Ny, Nslopes, offset, these
    DOUBLE PRECISION :: h(Ny,0:T), hshock(Ny,T), SVol(Ny,0:T), y(Ny,T), resid(Ny,T), hrho(Ny), hInno(Ny), hbar(Ny), E0h(Ny), V0h(Ny), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream


    DOUBLE PRECISION :: lhs(T), rhs(T,Ny-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    resid = y
    ! PART 1: Shockslopes
    offset = 0
    DO i=2,Ny
       these = i - 1

       FORALL (k=1:T) lhs(k)       = resid(i,k) / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:i-1) = resid(1:i-1,k) / SVol(i,k)

       ! slope indices are offset+1:offset+these
       call bayesdiffuseRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, VSLstream)

       FORALL (k=1:T) resid(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO


    ! PART 2: SV
    DO i = 1,Ny
       CALL stochvolKSCar1plus(SVol(i,:), h(i,:), hbar(i), hshock(i,:), resid(i,:), T, hInno(i), hrho(i), E0h(i), V0h(i), VSLstream)
    END DO

  END SUBROUTINE SVHcholeskiAR1diffuseslopesplus

  ! @\newpage\subsection{SVHcholeskiKSCAR1corplus}@
  SUBROUTINE SVHcholeskiKSCAR1corplus(T, Nsv, SVol, h, hshock, hbar, rho, shockslopes, Nslopes, y, E0slopes, iV0slopes, sqrtVhshock, Eh0, sqrtVh0, VSLstream)

    ! h = log(SVol ** 2)

    INTENT(INOUT) :: SVol, VSLstream, y, h
    INTENT(IN) :: T,Nsv, E0slopes, iV0slopes, sqrtVhshock, Eh0, sqrtVh0, rho
    INTENT(OUT) :: shockslopes, hshock, hbar

    DOUBLE PRECISION :: rho 

    INTEGER :: i, s, j, k, T, Nsv, Nslopes, offset, these, errcode
    DOUBLE PRECISION :: E0slopes(Nslopes), iV0slopes(Nslopes, Nslopes), sqrtVhshock(Nsv,Nsv), Eh0(Nsv), sqrtVh0(Nsv,Nsv), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream

    ! KSC mixture
    INTEGER, PARAMETER :: KSCmix = 7
    DOUBLE PRECISION, DIMENSION(KSCmix), PARAMETER :: KSCmean = - 1.2704d0 + (/ -10.12999d0, -3.97281d0, -8.56686d0, 2.77786d0, .61942d0, 1.79518d0, -1.08819d0 /), KSCvar     = (/ 5.79596d0, 2.61369d0, 5.1795d0, .16735d0, .64009d0, .34023d0, 1.26261d0 /), KSCpdf= (/ .0073d0, .10556d0, .00002d0, .04395d0, .34001d0, .24566d0, .25750d0 /), KSCvol = sqrt(KSCvar)
    DOUBLE PRECISION, DIMENSION(Nsv,T,KSCmix) :: kai2CDF
    INTEGER, DIMENSION(Nsv,T) :: kai2states


    DOUBLE PRECISION, DIMENSION(Nsv,T) :: y, logy2, logy2star, volnoisemix, u
    DOUBLE PRECISION, DIMENSION(Nsv,0:T) :: h, SVol
    DOUBLE PRECISION, DIMENSION(Nsv,1:T) :: hshock
    DOUBLE PRECISION, DIMENSION(Nsv) :: hbar

    ! state space matrices
    DOUBLE PRECISION :: A(Nsv*2,Nsv*2,T), B(Nsv*2,Nsv,T), C(Nsv,Nsv*2,T), y2noise(Nsv,T), State(Nsv*2,0:T), StateShock(Nsv*2,1:T), sqrtState0V(2*Nsv,2*Nsv), State0(Nsv*2)
    DOUBLE PRECISION :: lhs(T), rhs(T,Nsv-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    ! PART 1: Shockslopes
    offset = 0
    DO i=2,Nsv
       these = i - 1

       FORALL (k=1:T) lhs(k)       = y(i,k) / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:i-1) = y(1:i-1,k) / SVol(i,k)

       ! slope indices are offset+1:offset+these
       call bayesRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, E0slopes(offset+1:offset+these), iV0slopes(offset+1:offset+these,offset+1:offset+these), VSLstream)

       FORALL (k=1:T) y(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO


    ! PART 2: SV

    ! log-linear observer
    logy2 = log(y ** 2 + 0.001d0)

    ! PART 2, STEP 1: DRAW KAI2STATES
    ! a) construct PDF for draws (stored in kai2CDF)
    FORALL (s=1:KSCmix,k=1:Nsv,j=1:T)
       kai2CDF(k,j,s) = exp(-0.5d0 * ((logy2(k,j) - h(k,j) - KSCmean(s)) / KSCvol(s))** 2) / KSCvol(s) * KSCpdf(s)
    END FORALL

    ! b) convert PDF into CDF for draws
    DO s=2,KSCmix
       kai2CDF(:,:,s) = kai2CDF(:,:,s-1) + kai2CDF(:,:,s)
    END DO
    DO s=1,KSCmix-1
       kai2CDF(:,:,s) = kai2CDF(:,:,s) / kai2CDF(:,:,KSCmix)
    END DO
    kai2CDF(:,:,KSCmix) = 1.0d0


    ! c) draw kai2states
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, Nsv * T, u, 0.0d0, 1.0d0 )
    FORALL (k=1:Nsv,j=1:T)
       kai2states(k,j) = COUNT(u(k,j) > kai2CDF(k,j,:)) + 1
    END FORALL


    ! PART 2, STEP 2: KALMAN FILTER FOR h

    ! prepare initial trend variance and noise variance
    FORALL (k=1:Nsv,j=1:T)
       volnoisemix(k,j) = KSCvol(kai2states(k,j))
    END FORALL

    ! demeaned observables 
    FORALL(k=1:Nsv,j=1:T)
       logy2star(k,j) = logy2(k,j) - KSCmean(kai2states(k,j))
    END FORALL

    ! state space matrices
    A = 0.0d0
    FORALL(k=1:Nsv,j=1:T) A(k,k,j) = rho
    FORALL(k=Nsv+1:Nsv*2,j=1:T) A(k,k,j) = 1.0d0

    B = 0.0d0
    FORALL(j=1:T) B(1:Nsv,1:Nsv,j) = sqrtVhshock

    C = 0.0d0
    FORALL(k=1:Nsv,j=1:T) C(k,k,j) = 1.0d0
    FORALL(k=1:Nsv,j=1:T) C(k,Nsv+k,j) = 1.0d0

    State0 = 0.0d0
    State0(Nsv+1:2*Nsv) = Eh0

    sqrtState0V = 0.0d0
    ! call eye(sqrtState0V, 10.0d0)
    sqrtState0V(Nsv+1:2*Nsv,Nsv+1:2*Nsv) = sqrtVh0

    CALL DLYAP(sqrtState0V(1:Nsv,1:Nsv), A(1:Nsv,1:Nsv,1), sqrtVhshock, Nsv, Nsv, errcode) 
    if (errcode /= 0) then
       write (*,*) 'DLYAP error (sqrtState0V)', errcode
       stop 1
    end if
    ! Factorize 
    CALL DPOTRF('L', Nsv, sqrtState0V(1:Nsv,1:Nsv), Nsv, errcode) ! recall: DLYAP returns fully symmetric matrix
    if (errcode /= 0) then
       write (*,*) 'DPOTRF error (sqrtState0V)', errcode
       stop 1
    end if
    ! zero out the upper triangular
    FORALL (i=1:Nsv-1) sqrtState0V(i,i+1:Nsv) = 0.0d0

    CALL samplerA3B3C3noise(State,StateShock,y2noise,logy2star,T,Nsv,Nsv*2,Nsv,A,B,C,volnoisemix,State0,sqrtState0V,VSLstream,errcode)
    if (errcode /= 0) then
       print *, 'something off with KSCvec sampler', errcode
       stop 1
    end if

    h      = State(1:Nsv,:) + State(Nsv+1:Nsv*2,:)
    hshock = StateShock(1:Nsv,:) 
    hbar   = State(Nsv+1:Nsv*2,0)

    SVol   = exp(h * 0.5d0)



  END SUBROUTINE SVHcholeskiKSCAR1corplus

  ! @\newpage\subsection{SVHcholKSCRWcor}@
  SUBROUTINE SVHcholKSCRWcor(T, Nsv, SVol, h, hshock, shockslopes, Nslopes, y, E0slopes, iV0slopes, sqrtVhshock, Eh0, sqrtVh0, VSLstream)

    ! h = log(SVol ** 2)

    INTENT(INOUT) :: SVol, VSLstream, y
    INTENT(IN) :: T,Nsv, E0slopes, iV0slopes, sqrtVhshock, Eh0, sqrtVh0
    INTENT(OUT) :: shockslopes, hshock, h

    INTEGER :: i, s, j, k, T, Nsv, Nslopes, offset, these, errcode
    DOUBLE PRECISION :: E0slopes(Nslopes), iV0slopes(Nslopes, Nslopes), sqrtVhshock(Nsv,Nsv), Eh0(Nsv), sqrtVh0(Nsv,Nsv), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream

    ! KSC mixture
    INTEGER, PARAMETER :: KSCmix = 7
    DOUBLE PRECISION, DIMENSION(KSCmix), PARAMETER :: KSCmean = - 1.2704d0 + (/ -10.12999d0, -3.97281d0, -8.56686d0, 2.77786d0, .61942d0, 1.79518d0, -1.08819d0 /), KSCvar     = (/ 5.79596d0, 2.61369d0, 5.1795d0, .16735d0, .64009d0, .34023d0, 1.26261d0 /), KSCpdf= (/ .0073d0, .10556d0, .00002d0, .04395d0, .34001d0, .24566d0, .25750d0 /), KSCvol = sqrt(KSCvar)
    DOUBLE PRECISION, DIMENSION(Nsv,T,KSCmix) :: kai2CDF
    INTEGER, DIMENSION(Nsv,T) :: kai2states


    DOUBLE PRECISION, DIMENSION(Nsv,T) :: y, logy2, logy2star, volnoisemix, u
    DOUBLE PRECISION, DIMENSION(Nsv,0:T) :: h, SVol
    DOUBLE PRECISION, DIMENSION(Nsv,1:T) :: hshock

    ! state space matrices
    DOUBLE PRECISION :: A(Nsv,Nsv,T), B(Nsv,Nsv,T), C(Nsv,Nsv,T), y2noise(Nsv,T), State(Nsv,0:T), StateShock(Nsv,1:T), sqrtState0V(Nsv,Nsv), State0(Nsv)
    DOUBLE PRECISION :: lhs(T), rhs(T,Nsv-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    ! PART 1: Shockslopes
    offset = 0
    DO i=2,Nsv
       these = i - 1

       FORALL (k=1:T) lhs(k)       = y(i,k) / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:i-1) = y(1:i-1,k) / SVol(i,k)

       ! slope indices are offset+1:offset+these
       call bayesRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, E0slopes(offset+1:offset+these), iV0slopes(offset+1:offset+these,offset+1:offset+these), VSLstream)

       FORALL (k=1:T) y(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO


    ! PART 2: SV

    ! log-linear observer
    logy2 = log(y ** 2 + 0.001d0)
    h     = 2.0d0 * log(SVol) 

    ! PART 2, STEP 1: DRAW KAI2STATES
    ! a) construct PDF for draws (stored in kai2CDF)
    FORALL (s=1:KSCmix,k=1:Nsv,j=1:T)
       kai2CDF(k,j,s) = exp(-0.5d0 * ((logy2(k,j) - h(k,j) - KSCmean(s)) / KSCvol(s))** 2) / KSCvol(s) * KSCpdf(s)
    END FORALL

    ! b) convert PDF into CDF for draws
    DO s=2,KSCmix
       kai2CDF(:,:,s) = kai2CDF(:,:,s-1) + kai2CDF(:,:,s)
    END DO
    DO s=1,KSCmix-1
       kai2CDF(:,:,s) = kai2CDF(:,:,s) / kai2CDF(:,:,KSCmix)
    END DO
    kai2CDF(:,:,KSCmix) = 1.0d0


    ! c) draw kai2states
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, Nsv * T, u, 0.0d0, 1.0d0 )
    FORALL (k=1:Nsv,j=1:T)
       kai2states(k,j) = COUNT(u(k,j) > kai2CDF(k,j,:)) + 1
    END FORALL


    ! PART 2, STEP 2: KALMAN FILTER FOR h

    ! prepare initial trend variance and noise variance
    FORALL (k=1:Nsv,j=1:T)
       volnoisemix(k,j) = KSCvol(kai2states(k,j))
    END FORALL

    ! demeaned observables 
    FORALL(k=1:Nsv,j=1:T)
       logy2star(k,j) = logy2(k,j) - KSCmean(kai2states(k,j))
    END FORALL

    ! state space matrices
    A = 0.0d0
    FORALL(k=1:Nsv,j=1:T) A(k,k,j) = 1.0d0

    B = 0.0d0
    FORALL(j=1:T) B(1:Nsv,1:Nsv,j) = sqrtVhshock

    C = 0.0d0
    FORALL(k=1:Nsv,j=1:T) C(k,k,j) = 1.0d0

    ! note: redundancy with State0 sqrtState0V
    State0 = Eh0
    sqrtState0V = sqrtVh0

    CALL samplerA3B3C3noise(State,StateShock,y2noise,logy2star,T,Nsv,Nsv,Nsv,A,B,C,volnoisemix,State0,sqrtState0V,VSLstream,errcode)
    if (errcode /= 0) then
       print *, 'something off with KSCvec sampler', errcode
       stop 1
    end if

    ! again: get rid of redundancy
    h      = State(1:Nsv,:)
    hshock = StateShock(1:Nsv,:) 

    SVol   = exp(h * 0.5d0)



  END SUBROUTINE SVHcholKSCRWcor

  ! @\newpage\subsection{SVHinvcholRWcor}@
  SUBROUTINE SVHinvcholRWcor(T, Nsv, SVol, h, hshock, shockslopes, Nslopes, y, E0slopes, iV0slopes, sqrtVhshock, Eh0, sqrtVh0, VSLstream)

    ! CCM style inverse choleski, A * resid = SV * z where A is unit-lowert-triangular

    ! h = log(SVol ** 2)

    INTENT(INOUT) :: SVol, VSLstream, y, h
    INTENT(IN) :: T,Nsv, E0slopes, iV0slopes, sqrtVhshock, Eh0, sqrtVh0
    INTENT(OUT) :: shockslopes, hshock

    INTEGER :: i, s, j, k, T, Nsv, Nslopes, offset, these, errcode
    DOUBLE PRECISION :: E0slopes(Nslopes), iV0slopes(Nslopes, Nslopes), sqrtVhshock(Nsv,Nsv), Eh0(Nsv), sqrtVh0(Nsv,Nsv), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream

    ! KSC mixture
    INTEGER, PARAMETER :: KSCmix = 7
    DOUBLE PRECISION, DIMENSION(KSCmix), PARAMETER :: KSCmean = - 1.2704d0 + (/ -10.12999d0, -3.97281d0, -8.56686d0, 2.77786d0, .61942d0, 1.79518d0, -1.08819d0 /), KSCvar     = (/ 5.79596d0, 2.61369d0, 5.1795d0, .16735d0, .64009d0, .34023d0, 1.26261d0 /), KSCpdf= (/ .0073d0, .10556d0, .00002d0, .04395d0, .34001d0, .24566d0, .25750d0 /), KSCvol = sqrt(KSCvar)
    DOUBLE PRECISION, DIMENSION(Nsv,T,KSCmix) :: kai2CDF
    INTEGER, DIMENSION(Nsv,T) :: kai2states


    DOUBLE PRECISION, DIMENSION(T,Nsv) :: y
    DOUBLE PRECISION, DIMENSION(Nsv,T) :: yresid, logy2, logy2star, volnoisemix, u
    DOUBLE PRECISION, DIMENSION(Nsv,0:T) :: h
    DOUBLE PRECISION, DIMENSION(Nsv,1:T) :: SVol
    DOUBLE PRECISION, DIMENSION(Nsv,1:T) :: hshock

    ! state space matrices
    DOUBLE PRECISION :: A(Nsv,Nsv,T), B(Nsv,Nsv,T), C(Nsv,Nsv,T), y2noise(Nsv,T), State(Nsv,0:T), StateShock(Nsv,1:T), sqrtState0V(Nsv,Nsv), State0(Nsv)
    DOUBLE PRECISION :: lhs(T), rhs(T,Nsv-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    yresid = 0
    yresid(1,:) = y(:,1)

    ! PART 1: Shockslopes
    offset = 0
    DO i=2,Nsv
       these = i - 1

       FORALL (k=1:T) lhs(k)       = y(k,i) / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:i-1) = - y(k,1:these) / SVol(i,k) ! note the minus sign; this is on eof two differences with the "regular" choleski

       ! slope indices are offset+1:offset+these
       call bayesRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, E0slopes(offset+1:offset+these), iV0slopes(offset+1:offset+these,offset+1:offset+these), VSLstream)

       FORALL (k=1:T) yresid(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO


    ! PART 2: SV

    ! log-linear observer
    logy2 = log(yresid ** 2 + 0.001d0)

    ! PART 2, STEP 1: DRAW KAI2STATES
    ! a) construct PDF for draws (stored in kai2CDF)
    FORALL (s=1:KSCmix,k=1:Nsv,j=1:T)
       kai2CDF(k,j,s) = exp(-0.5d0 * ((logy2(k,j) - h(k,j) - KSCmean(s)) / KSCvol(s))** 2) / KSCvol(s) * KSCpdf(s)
    END FORALL

    ! b) convert PDF into CDF for draws
    DO s=2,KSCmix
       kai2CDF(:,:,s) = kai2CDF(:,:,s-1) + kai2CDF(:,:,s)
    END DO
    DO s=1,KSCmix-1
       kai2CDF(:,:,s) = kai2CDF(:,:,s) / kai2CDF(:,:,KSCmix)
    END DO
    kai2CDF(:,:,KSCmix) = 1.0d0


    ! c) draw kai2states
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, Nsv * T, u, 0.0d0, 1.0d0 )
    FORALL (k=1:Nsv,j=1:T)
       kai2states(k,j) = COUNT(u(k,j) > kai2CDF(k,j,:)) + 1
    END FORALL


    ! PART 2, STEP 2: KALMAN FILTER FOR h

    ! prepare initial trend variance and noise variance
    FORALL (k=1:Nsv,j=1:T)
       volnoisemix(k,j) = KSCvol(kai2states(k,j))
    END FORALL

    ! demeaned observables 
    FORALL(k=1:Nsv,j=1:T)
       logy2star(k,j) = logy2(k,j) - KSCmean(kai2states(k,j))
    END FORALL

    ! state space matrices
    A = 0.0d0
    FORALL(k=1:Nsv,j=1:T) A(k,k,j) = 1.0d0

    B = 0.0d0
    FORALL(j=1:T) B(1:Nsv,1:Nsv,j) = sqrtVhshock

    C = 0.0d0
    FORALL(k=1:Nsv,j=1:T) C(k,k,j) = 1.0d0

    ! note: redundancy with State0 sqrtState0V
    State0      = Eh0
    sqrtState0V = sqrtVh0

    CALL samplerA3B3C3noise(State,StateShock,y2noise,logy2star,T,Nsv,Nsv,Nsv,A,B,C,volnoisemix,State0,sqrtState0V,VSLstream,errcode)
    if (errcode /= 0) then
       print *, 'something off with KSCvec sampler', errcode
       stop 1
    end if

    ! ! debug
    ! call savemat(A(:,:,1), 'A.debug')
    ! call savemat(B(:,:,1), 'B.debug')
    ! call savemat(C(:,:,1), 'C.debug')
    ! call savemat(State, 'State.debug')
    ! call savemat(StateShock, 'StateShock.debug')
    ! call savevec(State0, 'State0.debug')
    ! call savemat(sqrtState0V, 'sqrtState0V.debug')
    ! call savemat(logy2star, 'logy2star.debug')
    ! call savemat(volnoisemix, 'volnoisemix.debug')
    ! print *, 'rho', rho
    ! stop 33

    ! again: get rid of redundancy
    h      = State(1:Nsv,:)
    hshock = StateShock(1:Nsv,:) 

    SVol   = exp(h(:,1:T) * 0.5d0)



  END SUBROUTINE SVHinvcholRWcor

  ! @\newpage\subsection{SVOinvcholRWcor}@
  SUBROUTINE SVOinvcholRWcor(T, Nsv, SVol, h, hshock, shockslopes, Nslopes, svolog2scale, svoprob, y, E0slopes, iV0slopes, sqrtVhshock, Eh0, sqrtVh0, SVOprioralpha, SVOpriorbeta, SVOngrid, SVOgrid, VSLstream)

    ! CCM style inverse choleski, A * resid = SV * z where A is unit-lowert-triangular

    INTENT(INOUT) :: SVol, h, VSLstream
    INTENT(IN) :: y
    INTENT(IN) :: T,Nsv, E0slopes, iV0slopes, sqrtVhshock, Eh0, sqrtVh0
    INTENT(OUT) :: shockslopes, hshock

    INTEGER :: i, s, j, k, T, Nsv, Nslopes, offset, these, errcode

    double precision, intent(in), dimension(Nsv) :: SVOprioralpha, SVOpriorbeta
    double precision, intent(inout), dimension(Nsv) :: SVOprob
    double precision, intent(inout), dimension(Nsv,T) :: SVOlog2scale ! log2values
    integer, intent(in) :: SVOngrid
    type(SVOgridspace(SVOngrid)), intent(in) :: SVOgrid




    DOUBLE PRECISION :: E0slopes(Nslopes), iV0slopes(Nslopes, Nslopes), sqrtVhshock(Nsv,Nsv), Eh0(Nsv), sqrtVh0(Nsv,Nsv), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream

    ! KSC mixture
    INTEGER, PARAMETER :: KSCmix = 7
    DOUBLE PRECISION, DIMENSION(KSCmix), PARAMETER :: KSCmean = - 1.2704d0 + (/ -10.12999d0, -3.97281d0, -8.56686d0, 2.77786d0, .61942d0, 1.79518d0, -1.08819d0 /), KSCvar     = (/ 5.79596d0, 2.61369d0, 5.1795d0, .16735d0, .64009d0, .34023d0, 1.26261d0 /), KSCpdf= (/ .0073d0, .10556d0, .00002d0, .04395d0, .34001d0, .24566d0, .25750d0 /), KSCvol = sqrt(KSCvar)
    DOUBLE PRECISION, DIMENSION(Nsv,T,KSCmix) :: kai2CDF
    INTEGER, DIMENSION(Nsv,T) :: kai2states

    ! outlier
    double precision, dimension(Nsv, T, SVOngrid) :: SVOkernel
    double precision, dimension(Nsv, SVOngrid) :: outlierpdf
    integer, dimension(Nsv, T) :: SVOndx 
    integer, dimension(Nsv)    :: Noutlier
    double precision, dimension(Nsv) :: posterioralpha, posteriorbeta

    ! other
    DOUBLE PRECISION, DIMENSION(T,Nsv) :: y
    DOUBLE PRECISION, DIMENSION(Nsv,T) :: yresid, logy2, logy2star, volnoisemix, meannoisemix, u
    DOUBLE PRECISION, DIMENSION(Nsv,0:T) :: h
    DOUBLE PRECISION, DIMENSION(Nsv,1:T) :: SVol
    DOUBLE PRECISION, DIMENSION(Nsv,1:T) :: hshock

    ! state space matrices
    DOUBLE PRECISION :: A(Nsv,Nsv,T), B(Nsv,Nsv,T), C(Nsv,Nsv,T), y2noise(Nsv,T) !, State(Nsv,0:T), StateShock(Nsv,1:T) ! , sqrtState0V(Nsv,Nsv), State0(Nsv)
    DOUBLE PRECISION :: lhs(T), rhs(T,Nsv-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    yresid = 0
    yresid(1,:) = y(:,1)

    ! PART 1: Shockslopes
    offset = 0
    DO i=2,Nsv
       these = i - 1

       FORALL (k=1:T) lhs(k)         =   y(k,i)       / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:these) = - y(k,1:these) / SVol(i,k) ! note the minus sign; this is one of two differences with the "regular" choleski

       ! slope indices are offset+1:offset+these
       call bayesRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:these), these, T, 1.0d0, E0slopes(offset+1:offset+these), iV0slopes(offset+1:offset+these,offset+1:offset+these), VSLstream)
       ! call bayesDiffuseRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:these), these, T, 1.0d0, VSLstream)

       FORALL (k=1:T) yresid(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO

    ! PART 2: SV

    ! log-linear observer
    logy2 = log(yresid ** 2 + 0.001d0)

    ! PART 2, STEP 1: DRAW KAI2STATES
    ! a) construct PDF for draws (stored in kai2CDF)
    FORALL (s=1:KSCmix,k=1:Nsv,j=1:T)
       kai2CDF(k,j,s) = exp(-0.5d0 * ((logy2(k,j) - h(k,j) - SVOlog2scale(k,j) - KSCmean(s)) / KSCvol(s))** 2) / KSCvol(s) * KSCpdf(s)
    END FORALL

    ! b) convert PDF into CDF for draws
    DO s=2,KSCmix
       kai2CDF(:,:,s) = kai2CDF(:,:,s-1) + kai2CDF(:,:,s)
    END DO
    DO s=1,KSCmix-1
       kai2CDF(:,:,s) = kai2CDF(:,:,s) / kai2CDF(:,:,KSCmix)
    END DO
    kai2CDF(:,:,KSCmix) = 1.0d0


    ! c) draw kai2states
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, Nsv * T, u, 0.0d0, 1.0d0 )
    FORALL (k=1:Nsv,j=1:T)
       kai2states(k,j) = COUNT(u(k,j) > kai2CDF(k,j,:)) + 1
    END FORALL


    ! PART 2, STEP 2: KALMAN FILTER FOR h

    ! prepare noise variance
    FORALL (k=1:Nsv,j=1:T)
       volnoisemix(k,j) = KSCvol(kai2states(k,j))
    END FORALL
    FORALL (k=1:Nsv,j=1:T)
       meannoisemix(k,j) = KSCmean(kai2states(k,j))
    END FORALL

    ! demeaned observables 
    FORALL(k=1:Nsv,j=1:T)
       logy2star(k,j) = logy2(k,j) - meannoisemix(k,j) - SVOlog2scale(k,j)
    END FORALL

    ! state space matrices
    A = 0.0d0
    FORALL(k=1:Nsv,j=1:T) A(k,k,j) = 1.0d0

    B = 0.0d0
    FORALL(j=1:T) B(:,:,j) = sqrtVhshock

    C = 0.0d0
    FORALL(k=1:Nsv,j=1:T) C(k,k,j) = 1.0d0

    CALL samplerA3B3C3noise(h,hshock,y2noise,logy2star,T,Nsv,Nsv,Nsv,A,B,C,volnoisemix,Eh0,sqrtVh0,VSLstream,errcode)
    if (errcode /= 0) then
       print *, 'something off with samplerA3B3C3noise output', errcode
       stop 1
    end if
    ! note: y2noise is just a dummy

    ! PART 3: outliers
    ! probability of each outlier state
    s = 1
    FORALL (k=1:Nsv)               outlierPdf(k,s) = 1.0d0 - SVOprob(k)
    FORALL (k=1:Nsv,s=2:SVOngrid)  outlierPdf(k,s) = SVOprob(k) / dble(SVOngrid - 1)

    ! construct PDFkernel
    FORALL (k=1:Nsv,j=1:T,s=1:SVOngrid)
       SVOkernel(k,j,s) = exp(-0.5d0 * ((logy2(k,j) - meannoisemix(k,j) - h(k,j) - SVOgrid%log2values(s)) / volnoisemix(k,j))** 2) * outlierPdf(k,s) ! note:  division " / volnoisemix(k,j) " is irrelevant for Kernel since independent of s
    END FORALL
    ! convert into CDF
    DO s=2,SVOngrid
       SVOkernel(:,:,s) = SVOkernel(:,:,s-1) + SVOkernel(:,:,s)
    END DO
    DO s=1,SVOngrid-1
       SVOkernel(:,:,s) = SVOkernel(:,:,s) / SVOkernel(:,:,SVOngrid)
    END DO
    SVOkernel(:,:,SVOngrid) = 1.0d0
    ! draw outlier states
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, Nsv * T, u, 0.0d0, 1.0d0 )
    FORALL (k=1:Nsv,j=1:T)
       SVOndx(k,j)       = COUNT(u(k,j) > SVOkernel(k,j,:)) + 1
       SVOlog2scale(k,j) = SVOgrid%log2values(SVOndx(k,j))
    END FORALL

    !  update outlierProb
    Noutlier       = count(SVOndx .gt. 1, 2)
    posterioralpha = SVOprioralpha + dble(Noutlier)
    posteriorbeta  = SVOpriorbeta  + dble(T - Noutlier)

    if (any(Noutlier .gt. T)) then
       call savemat(dble(SVOndx), 'SVOndx.debug')
       call savevec(dble(Noutlier), 'Noutlier.debug')
       call savevec(posterioralpha, 'alpha.debug')
       call savevec(posteriorbeta, 'beta.debug')
       call savevec(SVOprioralpha, 'alphaprior.debug')
       call savevec(SVOpriorbeta, 'betaprior.debug')
       print *, 'houston'
       stop 11
    end if

    ! posterior draws from beta
    SVOprob = vslBetaDraws(posterioralpha, posteriorbeta, Nsv, VSLstream)

    ! FINISH: putting it all together
    SVol = exp(0.5d0 * (h(:,1:T) + SVOlog2scale))

  END SUBROUTINE SVOinvcholRWcor

  ! @\newpage\subsection{SVtinvcholRWcor}@
  SUBROUTINE SVtinvcholRWcor(T, Nsv, SVol, h, hshock, shockslopes, Nslopes, svtscalelog2, svtdof, y, E0slopes, iV0slopes, sqrtVhshock, Eh0, sqrtVh0, tdofMin, tdofMax, tdoflogprior, tdofloglike0, VSLstream)

    ! CCM style inverse choleski, A * resid = SV * z where A is unit-lowert-triangular

    INTENT(INOUT) :: SVol, h, VSLstream
    INTENT(IN) :: y
    INTENT(IN) :: T,Nsv, E0slopes, iV0slopes, sqrtVhshock, Eh0, sqrtVh0
    INTENT(OUT) :: shockslopes, hshock

    INTEGER :: i, s, j, k, T, Nsv, Nslopes, offset, these, errcode

    DOUBLE PRECISION :: E0slopes(Nslopes), iV0slopes(Nslopes, Nslopes), sqrtVhshock(Nsv,Nsv), Eh0(Nsv), sqrtVh0(Nsv,Nsv), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream

    ! KSC mixture
    INTEGER, PARAMETER :: KSCmix = 7
    DOUBLE PRECISION, DIMENSION(KSCmix), PARAMETER :: KSCmean = - 1.2704d0 + (/ -10.12999d0, -3.97281d0, -8.56686d0, 2.77786d0, .61942d0, 1.79518d0, -1.08819d0 /), KSCvar     = (/ 5.79596d0, 2.61369d0, 5.1795d0, .16735d0, .64009d0, .34023d0, 1.26261d0 /), KSCpdf= (/ .0073d0, .10556d0, .00002d0, .04395d0, .34001d0, .24566d0, .25750d0 /), KSCvol = sqrt(KSCvar)
    DOUBLE PRECISION, DIMENSION(Nsv,T,KSCmix) :: kai2CDF
    INTEGER, DIMENSION(Nsv,T) :: kai2states

    ! t-scale
    integer, intent(in) :: tdofMin, tdofMax
    double precision, dimension(tdofMin:tdofMax), intent(in) :: tdoflogprior, tdofloglike0 ! note: could also pass sum of both, done this way for better redability
    double precision, dimension(Nsv,T), intent(inout) :: svtscalelog2
    double precision, dimension(Nsv), intent(inout)   :: svtdof
    double precision, dimension(T,Nsv) :: chi2draws ! mind the transpose for better call to rng
    double precision, dimension(Nsv,tdofMin:tdofMax) :: tdoflike
    double precision, dimension(Nsv) :: maxllf
    double precision, dimension(Nsv) :: utdof
    integer :: Ntdofgrid

    ! other
    DOUBLE PRECISION, DIMENSION(T,Nsv) :: y
    DOUBLE PRECISION, DIMENSION(Nsv,T) :: yresid, logy2, y2scaled, logy2star, volnoisemix, meannoisemix, u
    DOUBLE PRECISION, DIMENSION(Nsv,0:T) :: h
    DOUBLE PRECISION, DIMENSION(Nsv,1:T) :: SVol
    DOUBLE PRECISION, DIMENSION(Nsv,1:T) :: hshock

    ! state space matrices
    DOUBLE PRECISION :: A(Nsv,Nsv,T), B(Nsv,Nsv,T), C(Nsv,Nsv,T), y2noise(Nsv,T) 
    DOUBLE PRECISION :: lhs(T), rhs(T,Nsv-1)

    yresid = 0
    yresid(1,:) = y(:,1)

    ! PART 1: Shockslopes
    offset = 0
    DO i=2,Nsv
       these = i - 1

       FORALL (k=1:T) lhs(k)         =   y(k,i)       / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:these) = - y(k,1:these) / SVol(i,k) ! note the minus sign; this is one of two differences with the "regular" choleski

       ! slope indices are offset+1:offset+these
       call bayesRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:these), these, T, 1.0d0, E0slopes(offset+1:offset+these), iV0slopes(offset+1:offset+these,offset+1:offset+these), VSLstream)
       ! call bayesDiffuseRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:these), these, T, 1.0d0, VSLstream)

       FORALL (k=1:T) yresid(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO

    ! PART 2: tdof and tscale
    y2scaled = (yresid ** 2) * exp(-h(:,1:T))

    ! tdof inference
    Ntdofgrid = tdofMax - tdofMin + 1
    do i=tdofMin,tdofMax
          tdoflike(:,i) = tdofLogprior(i) + tdofloglike0(i) - 0.5d0 * dble(i + 1) * sum(log(y2scaled + dble(i)), 2)
    end do
    ! normalize
    maxllf = maxval(tdoflike, 2)
    forall (k=1:Nsv,i=tdofMin:tdofMax) tdoflike(k,i) = tdoflike(k,i) - maxllf(k)
    ! convert into cdf
    tdoflike = exp(tdoflike)
    do i=tdofMin+1,tdofMax
       tdoflike(:,i) = tdoflike(:,i) + tdoflike(:,i - 1)
    end do
    forall (k=1:Nsv,i=tdofMin:tdofMax-1) tdoflike(k,i) = tdoflike(k,i) / tdoflike(k,tdofMax) 
    tdoflike(:,tdofMax) = 1.0d0

    ! draw tdof 
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, Nsv, utdof, 0.0d0, 1.0d0 )
    FORALL (k=1:Nsv)
       svtdof(k) = (COUNT(utdof(k) > tdoflike(k,:)) + 1) + (tdofMin - 1)
    END FORALL


    ! draw posterior of IG/Chi2 draws
    forall (k=1:Nsv,j=1:T)  y2scaled(k,j) = svtdof(k) + 1.0d0 + y2scaled(k,j)
    do k=1,Nsv
       errcode    = vdrngchisquare(VSLmethodChisquare, VSLstream, T, chi2draws(:,k), int(svtdof(k)) + 1) ! note: conversion to integer
    end do
    svtscalelog2 = log(y2scaled) - log(transpose(chi2draws)) ! note transpose of chi2draws    


    ! PART 3: SV

    ! log-linear observer
    logy2 = log(yresid ** 2 + 0.001d0)

    ! PART 2, STEP 1: DRAW KAI2STATES
    ! a) construct PDF for draws (stored in kai2CDF)
    FORALL (s=1:KSCmix,k=1:Nsv,j=1:T)
       kai2CDF(k,j,s) = exp(-0.5d0 * ((logy2(k,j) - h(k,j) - svtscalelog2(k,j) - KSCmean(s)) / KSCvol(s))** 2) / KSCvol(s) * KSCpdf(s)
    END FORALL

    ! b) convert PDF into CDF for draws
    DO s=2,KSCmix
       kai2CDF(:,:,s) = kai2CDF(:,:,s-1) + kai2CDF(:,:,s)
    END DO
    DO s=1,KSCmix-1
       kai2CDF(:,:,s) = kai2CDF(:,:,s) / kai2CDF(:,:,KSCmix)
    END DO
    kai2CDF(:,:,KSCmix) = 1.0d0


    ! c) draw kai2states
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, Nsv * T, u, 0.0d0, 1.0d0 )
    FORALL (k=1:Nsv,j=1:T)
       kai2states(k,j) = COUNT(u(k,j) > kai2CDF(k,j,:)) + 1
    END FORALL


    ! PART 2, STEP 2: KALMAN FILTER FOR h

    ! prepare noise variance
    FORALL (k=1:Nsv,j=1:T)
       volnoisemix(k,j) = KSCvol(kai2states(k,j))
    END FORALL
    FORALL (k=1:Nsv,j=1:T)
       meannoisemix(k,j) = KSCmean(kai2states(k,j))
    END FORALL

    ! demeaned observables 
    FORALL(k=1:Nsv,j=1:T)
       logy2star(k,j) = logy2(k,j) - meannoisemix(k,j) - svtscalelog2(k,j)
    END FORALL

    ! state space matrices
    A = 0.0d0
    FORALL(k=1:Nsv,j=1:T) A(k,k,j) = 1.0d0

    B = 0.0d0
    FORALL(j=1:T) B(:,:,j) = sqrtVhshock

    C = 0.0d0
    FORALL(k=1:Nsv,j=1:T) C(k,k,j) = 1.0d0

    CALL samplerA3B3C3noise(h,hshock,y2noise,logy2star,T,Nsv,Nsv,Nsv,A,B,C,volnoisemix,Eh0,sqrtVh0,VSLstream,errcode)
    if (errcode /= 0) then
       print *, 'something off with samplerA3B3C3noise output', errcode
       stop 1
    end if
    ! note: y2noise is just a dummy

    ! FINISH: putting it all together
    SVol = exp(0.5d0 * (h(:,1:T) + svtscalelog2))

  END SUBROUTINE SVtinvcholRWcor


  ! @\newpage\subsection{SVHcholKSCAR1cor}@
  SUBROUTINE SVHcholKSCAR1cor(T, Nsv, SVol, h, hshock, hbar, rho, shockslopes, Nslopes, y, E0slopes, iV0slopes, sqrtVhshock, Eh0, sqrtVh0, VSLstream)

    ! same as SVHcholeskiKSCAR1corplus; but allows for vector of rho rather than a scalar

    ! h = log(SVol ** 2)

    INTENT(INOUT) :: SVol, VSLstream, y
    INTENT(IN) :: T,Nsv, E0slopes, iV0slopes, sqrtVhshock, Eh0, sqrtVh0, rho
    INTENT(OUT) :: shockslopes, hshock, h, hbar

    INTEGER :: i, s, j, k, T, Nsv, Nslopes, offset, these, errcode
    DOUBLE PRECISION :: rho(Nsv)
    DOUBLE PRECISION :: E0slopes(Nslopes), iV0slopes(Nslopes, Nslopes), sqrtVhshock(Nsv,Nsv), Eh0(Nsv), sqrtVh0(Nsv,Nsv), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream

    ! KSC mixture
    INTEGER, PARAMETER :: KSCmix = 7
    DOUBLE PRECISION, DIMENSION(KSCmix), PARAMETER :: KSCmean = - 1.2704d0 + (/ -10.12999d0, -3.97281d0, -8.56686d0, 2.77786d0, .61942d0, 1.79518d0, -1.08819d0 /), KSCvar     = (/ 5.79596d0, 2.61369d0, 5.1795d0, .16735d0, .64009d0, .34023d0, 1.26261d0 /), KSCpdf= (/ .0073d0, .10556d0, .00002d0, .04395d0, .34001d0, .24566d0, .25750d0 /), KSCvol = sqrt(KSCvar)
    DOUBLE PRECISION, DIMENSION(Nsv,T,KSCmix) :: kai2CDF
    INTEGER, DIMENSION(Nsv,T) :: kai2states


    DOUBLE PRECISION, DIMENSION(Nsv,T) :: y, logy2, logy2star, volnoisemix, u
    DOUBLE PRECISION, DIMENSION(Nsv,0:T) :: h, SVol
    DOUBLE PRECISION, DIMENSION(Nsv,1:T) :: hshock
    DOUBLE PRECISION, DIMENSION(Nsv) :: hbar

    ! state space matrices
    DOUBLE PRECISION :: A(Nsv*2,Nsv*2,T), B(Nsv*2,Nsv,T), C(Nsv,Nsv*2,T), y2noise(Nsv,T), State(Nsv*2,0:T), StateShock(Nsv*2,1:T), sqrtState0V(2*Nsv,2*Nsv), State0(Nsv*2)
    DOUBLE PRECISION :: lhs(T), rhs(T,Nsv-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    ! PART 1: Shockslopes
    offset = 0
    DO i=2,Nsv
       these = i - 1

       FORALL (k=1:T) lhs(k)       = y(i,k) / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:i-1) = y(1:i-1,k) / SVol(i,k)

       ! slope indices are offset+1:offset+these
       call bayesRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, E0slopes(offset+1:offset+these), iV0slopes(offset+1:offset+these,offset+1:offset+these), VSLstream)

       FORALL (k=1:T) y(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO


    ! PART 2: SV

    ! log-linear observer
    logy2 = log(y ** 2 + 0.001d0)
    h     = 2.0d0 * log(SVol) 

    ! PART 2, STEP 1: DRAW KAI2STATES
    ! a) construct PDF for draws (stored in kai2CDF)
    FORALL (s=1:KSCmix,k=1:Nsv,j=1:T)
       kai2CDF(k,j,s) = exp(-0.5d0 * ((logy2(k,j) - h(k,j) - KSCmean(s)) / KSCvol(s))** 2) / KSCvol(s) * KSCpdf(s)
    END FORALL

    ! b) convert PDF into CDF for draws
    DO s=2,KSCmix
       kai2CDF(:,:,s) = kai2CDF(:,:,s-1) + kai2CDF(:,:,s)
    END DO
    DO s=1,KSCmix-1
       kai2CDF(:,:,s) = kai2CDF(:,:,s) / kai2CDF(:,:,KSCmix)
    END DO
    kai2CDF(:,:,KSCmix) = 1.0d0


    ! c) draw kai2states
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, Nsv * T, u, 0.0d0, 1.0d0 )
    FORALL (k=1:Nsv,j=1:T)
       kai2states(k,j) = COUNT(u(k,j) > kai2CDF(k,j,:)) + 1
    END FORALL


    ! PART 2, STEP 2: KALMAN FILTER FOR h

    ! prepare initial trend variance and noise variance
    FORALL (k=1:Nsv,j=1:T)
       volnoisemix(k,j) = KSCvol(kai2states(k,j))
    END FORALL

    ! demeaned observables 
    FORALL(k=1:Nsv,j=1:T)
       logy2star(k,j) = logy2(k,j) - KSCmean(kai2states(k,j))
    END FORALL

    ! state space matrices
    A = 0.0d0
    FORALL(k=1:Nsv,j=1:T) A(k,k,j) = rho(k)
    FORALL(k=Nsv+1:Nsv*2,j=1:T) A(k,k,j) = 1.0d0

    B = 0.0d0
    FORALL(j=1:T) B(1:Nsv,1:Nsv,j) = sqrtVhshock

    C = 0.0d0
    FORALL(k=1:Nsv,j=1:T) C(k,k,j) = 1.0d0
    FORALL(k=1:Nsv,j=1:T) C(k,Nsv+k,j) = 1.0d0

    State0 = 0.0d0
    State0(Nsv+1:2*Nsv) = Eh0

    sqrtState0V = 0.0d0
    ! call eye(sqrtState0V, 10.0d0)
    sqrtState0V(Nsv+1:2*Nsv,Nsv+1:2*Nsv) = sqrtVh0

    ! CALL DLYAP(sqrtState0V(1:Nsv,1:Nsv), A(1:Nsv,1:Nsv,1), sqrtVhshock, Nsv, Nsv, errcode) 
    ! if (errcode /= 0) then
    !    write (*,*) 'DLYAP error (sqrtState0V)', errcode
    !    stop 1
    ! end if
    ! ! Factorize 
    ! CALL DPOTRF('L', Nsv, sqrtState0V(1:Nsv,1:Nsv), Nsv, errcode) ! recall: DLYAP returns fully symmetric matrix
    ! if (errcode /= 0) then
    !    write (*,*) 'DPOTRF error (sqrtState0V)', errcode
    !    stop 1
    ! end if
    ! ! zero out the upper triangular
    ! FORALL (i=1:Nsv-1) sqrtState0V(i,i+1:Nsv) = 0.0d0

    CALL samplerA3B3C3noise(State,StateShock,y2noise,logy2star,T,Nsv,Nsv*2,Nsv,A,B,C,volnoisemix,State0,sqrtState0V,VSLstream,errcode)
    if (errcode /= 0) then
       print *, 'something off with KSCvec sampler', errcode
       stop 1
    end if

    ! ! debug
    ! call savemat(A(:,:,1), 'A.debug')
    ! call savemat(B(:,:,1), 'B.debug')
    ! call savemat(C(:,:,1), 'C.debug')
    ! call savemat(State, 'State.debug')
    ! call savemat(StateShock, 'StateShock.debug')
    ! call savevec(State0, 'State0.debug')
    ! call savemat(sqrtState0V, 'sqrtState0V.debug')
    ! call savemat(logy2star, 'logy2star.debug')
    ! call savemat(volnoisemix, 'volnoisemix.debug')
    ! print *, 'rho', rho
    ! stop 33

    h      = State(1:Nsv,:) + State(Nsv+1:Nsv*2,:)
    hshock = StateShock(1:Nsv,:) 
    hbar   = State(Nsv+1:Nsv*2,0)

    SVol   = exp(h * 0.5d0)



  END SUBROUTINE SVHcholKSCAR1cor

  ! @\newpage\subsection{SVHdiffusecholeskiKSCAR1}@
  SUBROUTINE SVHdiffusecholeskiKSCAR1(T, Nsv, SVol, h, hshock, hbar, rho, shockslopes, Nslopes, y, sqrtVhshock, Eh0, sqrtVh0, VSLstream)

    ! h = log(SVol ** 2)

    INTENT(INOUT) :: SVol, VSLstream, y, h
    INTENT(IN) :: T,Nsv, sqrtVhshock, Eh0, sqrtVh0, rho
    INTENT(OUT) :: shockslopes, hshock, hbar

    DOUBLE PRECISION :: rho 

    INTEGER :: i, s, j, k, T, Nsv, Nslopes, offset, these, errcode
    DOUBLE PRECISION :: sqrtVhshock(Nsv,Nsv), Eh0(Nsv), sqrtVh0(Nsv,Nsv), shockslopes(Nslopes)
    TYPE (vsl_stream_state) :: VSLstream

    ! KSC mixture
    INTEGER, PARAMETER :: KSCmix = 7
    DOUBLE PRECISION, DIMENSION(KSCmix), PARAMETER :: KSCmean = - 1.2704d0 + (/ -10.12999d0, -3.97281d0, -8.56686d0, 2.77786d0, .61942d0, 1.79518d0, -1.08819d0 /), KSCvar     = (/ 5.79596d0, 2.61369d0, 5.1795d0, .16735d0, .64009d0, .34023d0, 1.26261d0 /), KSCpdf= (/ .0073d0, .10556d0, .00002d0, .04395d0, .34001d0, .24566d0, .25750d0 /), KSCvol = sqrt(KSCvar)
    DOUBLE PRECISION, DIMENSION(Nsv,T,KSCmix) :: kai2CDF
    INTEGER, DIMENSION(Nsv,T) :: kai2states


    DOUBLE PRECISION, DIMENSION(Nsv,T) :: y, logy2, logy2star, volnoisemix, u
    DOUBLE PRECISION, DIMENSION(Nsv,0:T) :: h, SVol
    DOUBLE PRECISION, DIMENSION(Nsv,1:T) :: hshock
    DOUBLE PRECISION, DIMENSION(Nsv) :: hbar

    ! state space matrices
    DOUBLE PRECISION :: A(Nsv*2,Nsv*2,T), B(Nsv*2,Nsv,T), C(Nsv,Nsv*2,T), y2noise(Nsv,T), State(Nsv*2,0:T), StateShock(Nsv*2,1:T), sqrtState0V(2*Nsv,2*Nsv), State0(Nsv*2)
    DOUBLE PRECISION :: lhs(T), rhs(T,Nsv-1)

    ! NOTE: V0slopes (and thus also iV0slopes) is assumed to be block-diagonal, with separate blocks for each regression

    ! PART 1: Shockslopes
    offset = 0
    DO i=2,Nsv
       these = i - 1

       FORALL (k=1:T) lhs(k)       = y(i,k) / SVol(i,k)
       FORALL (k=1:T) rhs(k,1:i-1) = y(1:i-1,k) / SVol(i,k)

       ! slope indices are offset+1:offset+these
       call bayesdiffuseRegressionSlope(shockslopes(offset+1:offset+these), lhs, rhs(:,1:i-1), these, T, 1.0d0, VSLstream)

       FORALL (k=1:T) y(i,k) = lhs(k) * SVol(i,k)

       offset = offset + these

    END DO


    ! PART 2: SV

    ! log-linear observer
    logy2 = log(y ** 2 + 0.001d0)

    ! PART 2, STEP 1: DRAW KAI2STATES
    ! a) construct PDF for draws (stored in kai2CDF)
    FORALL (s=1:KSCmix,k=1:Nsv,j=1:T)
       kai2CDF(k,j,s) = exp(-0.5d0 * ((logy2(k,j) - h(k,j) - KSCmean(s)) / KSCvol(s))** 2) / KSCvol(s) * KSCpdf(s)
    END FORALL

    ! b) convert PDF into CDF for draws
    DO s=2,KSCmix
       kai2CDF(:,:,s) = kai2CDF(:,:,s-1) + kai2CDF(:,:,s)
    END DO
    DO s=1,KSCmix-1
       kai2CDF(:,:,s) = kai2CDF(:,:,s) / kai2CDF(:,:,KSCmix)
    END DO
    kai2CDF(:,:,KSCmix) = 1.0d0


    ! c) draw kai2states
    errcode = vdrnguniform(VSLmethodUniform, VSLstream, Nsv * T, u, 0.0d0, 1.0d0 )
    FORALL (k=1:Nsv,j=1:T)
       kai2states(k,j) = COUNT(u(k,j) > kai2CDF(k,j,:)) + 1
    END FORALL


    ! PART 2, STEP 2: KALMAN FILTER FOR h

    ! prepare initial trend variance and noise variance
    FORALL (k=1:Nsv,j=1:T)
       volnoisemix(k,j) = KSCvol(kai2states(k,j))
    END FORALL

    ! demeaned observables 
    FORALL(k=1:Nsv,j=1:T)
       logy2star(k,j) = logy2(k,j) - KSCmean(kai2states(k,j))
    END FORALL

    ! state space matrices
    A = 0.0d0
    FORALL(k=1:Nsv,j=1:T) A(k,k,j) = rho
    FORALL(k=Nsv+1:Nsv*2,j=1:T) A(k,k,j) = 1.0d0

    B = 0.0d0
    FORALL(j=1:T) B(1:Nsv,1:Nsv,j) = sqrtVhshock

    C = 0.0d0
    FORALL(k=1:Nsv,j=1:T) C(k,k,j) = 1.0d0
    FORALL(k=1:Nsv,j=1:T) C(k,Nsv+k,j) = 1.0d0

    State0 = 0.0d0
    State0(Nsv+1:2*Nsv) = Eh0

    sqrtState0V = 0.0d0
    ! call eye(sqrtState0V, 10.0d0)
    sqrtState0V(Nsv+1:2*Nsv,Nsv+1:2*Nsv) = sqrtVh0

    CALL DLYAP(sqrtState0V(1:Nsv,1:Nsv), A(1:Nsv,1:Nsv,1), sqrtVhshock, Nsv, Nsv, errcode) 
    if (errcode /= 0) then
       write (*,*) 'DLYAP error (sqrtState0V)', errcode
       stop 1
    end if
    ! Factorize 
    CALL DPOTRF('L', Nsv, sqrtState0V(1:Nsv,1:Nsv), Nsv, errcode) ! recall: DLYAP returns fully symmetric matrix
    if (errcode /= 0) then
       write (*,*) 'DPOTRF error (sqrtState0V)', errcode
       stop 1
    end if
    ! zero out the upper triangular
    FORALL (i=1:Nsv-1) sqrtState0V(i,i+1:Nsv) = 0.0d0

    CALL samplerA3B3C3noise(State,StateShock,y2noise,logy2star,T,Nsv,Nsv*2,Nsv,A,B,C,volnoisemix,State0,sqrtState0V,VSLstream,errcode)
    if (errcode /= 0) then
       print *, 'something off with KSCvec sampler', errcode
       stop 1
    end if

    ! ! debug
    ! call savemat(A(:,:,1), 'A.debug')
    ! call savemat(B(:,:,1), 'B.debug')
    ! call savemat(C(:,:,1), 'C.debug')
    ! call savemat(State, 'State.debug')
    ! call savemat(StateShock, 'StateShock.debug')
    ! call savevec(State0, 'State0.debug')
    ! call savemat(sqrtState0V, 'sqrtState0V.debug')
    ! call savemat(logy2star, 'logy2star.debug')
    ! call savemat(volnoisemix, 'volnoisemix.debug')
    ! print *, 'rho', rho
    ! stop 33

    h      = State(1:Nsv,:) + State(Nsv+1:Nsv*2,:)
    hshock = StateShock(1:Nsv,:) 
    hbar   = State(Nsv+1:Nsv*2,0)

    SVol   = exp(h * 0.5d0)


  END SUBROUTINE SVHdiffusecholeskiKSCAR1

  ! @\newpage\subsection{bayesUnivariateRegressionSlope}@
  SUBROUTINE bayesUnivariateRegressionSlope(bdraw, y, x, T, h, b0, V0i, VSLstream)
    ! draws vestor of regression slopes from Bayesian Regression 
    ! of scalar y on Vector X
    ! on exit, y return residuals

    INTENT(INOUT) :: y
    INTENT(IN) :: X, h, b0, V0i, T
    INTENT(OUT) :: bdraw
    INTENT(INOUT) :: VSLstream
    INTEGER :: T, status
    DOUBLE PRECISION :: V0i, Vi
    DOUBLE PRECISION ::    b, b0, bdraw, edraw(1)
    DOUBLE PRECISION :: h, y(T), x(T)
    TYPE (vsl_stream_state) :: VSLstream


    ! prior/posterior

    ! Vi = inv(V0) + X'X * h
    Vi = V0i + sum(x * x) * h

    ! solve: Vi * b = inv(V0) * b0 + X'y * h
    b = (V0i * b0 + sum(x * y) * h) / Vi

    ! draw from posterior with mean b and inverse variance Vi 
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, 1, edraw, 0.0d0, 1.0d0)

    bdraw = b + edraw(1) / sqrt(Vi)

    ! residual 
    y = y - x * bdraw

  END SUBROUTINE bayesUnivariateRegressionSlope

  ! @\newpage\subsection{bayesUnivariateRegressionNormalGamma}@
  SUBROUTINE bayesUnivariateRegressionNormalGamma(bdraw, variancedraw, y, x, T, b0, hV0i, sigmaT0, dof0, VSLstream)
    ! draws vestor of regression slopes from Bayesian Regression 
    ! of scalar y on Vector X
    ! on exit, y return residuals
    ! joint normal-inverse-gamma prior-posterior (See e.g. Hamilton); specialized to the scalar case

    INTENT(INOUT) :: y
    INTENT(IN) :: X, b0, hV0i, dof0, sigmaT0, T
    INTENT(OUT) :: bdraw, variancedraw
    INTENT(INOUT) :: VSLstream
    INTEGER :: T, dof0, dof, status
    DOUBLE PRECISION :: hV0i, scaledV, V
    DOUBLE PRECISION :: b, b0, bOLS, bdraw
    DOUBLE PRECISION :: variancedraw, sigmaT0, sigmaT
    DOUBLE PRECISION :: z(1+T+dof0)
    DOUBLE PRECISION :: y(T), x(T), sxx2
    TYPE (vsl_stream_state) :: VSLstream


    ! prior/posterior: Normal slopes
    sxx2    =  sum(x * x)
    scaledV = 1.0d0 / (hV0i + sxx2)
    ! solve: Vi * b = inv(V0) * b0 + X'y * h
    b = (hV0i * b0 + sum(x * y)) * scaledV
    bOLS = sum(x * y) / sxx2

    ! prior posterior: inverse gamma
    dof    = T + dof0
    sigmaT = sigmaT0 + sum((y - x * bOLS) ** 2) + ((b0 - bOLS) ** 2) * hV0i * scaledV * sxx2

    ! draw from posterior with mean b and inverse variance Vi 
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, 1 + dof, z, 0.0d0, 1.0d0) ! one slope draw and dof IG draws

    ! construct IG draw
    variancedraw = sigmaT / sum(z(1:dof) ** 2)
    ! slope draw
    V     = variancedraw * scaledV
    bdraw = b + sqrt(V) * z(1 + dof) 

    ! residual 
    y = y - x * bdraw

    ! print *, 'hrho:', bdraw

  END SUBROUTINE bayesUnivariateRegressionNormalGamma

  ! @\newpage\subsection{bayesRegressionSlope}@
  SUBROUTINE bayesRegressionSlope(bdraw, y, X, Nx, T, h, b0, V0i, VSLstream)
    ! draws vestor of regression slopes from Bayesian Regression 
    ! of scalar y on Vector X
    ! on exit, y return residuals

    INTENT(INOUT) :: y
    INTENT(IN) :: X, h, b0, V0i, Nx, T
    INTENT(OUT) :: bdraw
    INTENT(INOUT) :: VSLstream
    INTEGER :: T, Nx, status
    DOUBLE PRECISION, DIMENSION(Nx,Nx) :: V0i, Vi
    DOUBLE PRECISION, DIMENSION(Nx) ::    b, b0, bdraw
    DOUBLE PRECISION :: h, y(T), X(T,Nx)
    TYPE (vsl_stream_state) :: VSLstream


    ! prior/posterior

    ! b = inv(V0) * b0 + X'y * h
    call DSYMV('U', Nx, 1.0d0, V0i, Nx, b0, 1, 0.0d0, b, 1)
    call DGEMV('T', T, Nx, h, X, T, y, 1, 1.0d0, b, 1)

    ! Vi = inv(V0) + X'X * h
    Vi = V0i
    call DSYRK('U', 'T', Nx, T, h, X, T, 1.0d0, Vi, Nx)

    ! solve: Vi * b = b
    ! call choleski(Vi) ! needed for inverting Vi as well as for draws, see below
    ! factorize
    call dpotrf('U', Nx, Vi, Nx, status)
    if (status /= 0) then
       write(*,*) 'DPOTRF error: ', status, ' [BAYESREGRESSIONSLOPE]'
       call savemat(Vi, 'Vi.debug')
       stop 1
    end if
    ! invert to solve for posterior
    call DPOTRS('U', Nx, 1, Vi, Nx, b, Nx, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, ' [BAYESREGRESSIONSLOPE]'
       stop 1
    end if

    ! draw from posterior with mean b and inverse variance Vi 
    ! notice: I am not scaling the draws by the choleski; using another factorization instead
    ! specifically: chol(Vi) * draws = z 
    ! (where V'= chol(Vl)' * chol(Vi), i.e. chol is upper triangular)
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, Nx, bdraw, 0.0d0, 1.0d0)
    call DTRSV('U', 'N', 'N', Nx, Vi, Nx, bdraw, 1)

    ! add posterior mean
    bdraw = bdraw + b 

    ! resid = y - X * bdraw
    call dgemv('N', T, Nx, -1.0d0, X, T, bdraw, 1, 1.0d0, y, 1)

  END SUBROUTINE bayesRegressionSlope

  ! @\newpage\subsection{bayesDiffuseRegressionSlope}@
  SUBROUTINE bayesDiffuseRegressionSlope(bdraw, y, X, Nx, T, h, VSLstream)
    ! draws vector of regression slopes from Bayesian Regression 
    ! of scalar y on Vector X
    ! on exit, y return residuals

    INTENT(INOUT) :: y
    INTENT(IN) :: X, h, Nx, T
    INTENT(OUT) :: bdraw
    INTENT(INOUT) :: VSLstream
    INTEGER :: T, Nx, status
    DOUBLE PRECISION, DIMENSION(Nx,Nx) :: Vi
    DOUBLE PRECISION, DIMENSION(Nx) ::    b, bdraw
    DOUBLE PRECISION :: h, y(T), X(T,Nx)
    TYPE (vsl_stream_state) :: VSLstream


    ! prior/posterior

    ! b = X'y * h
    ! call DSYMV('U', Nx, 1.0d0, V0i, Nx, b0, 1, 0.0d0, b, 1)
    b = 0.0d0
    call DGEMV('T', T, Nx, h, X, T, y, 1, 0.0d0, b, 1)

    ! Vi = X'X * h
    Vi = 0.0d0
    call DSYRK('U', 'T', Nx, T, h, X, T, 0.0d0, Vi, Nx)

    ! solve: Vi * b = inv(V0) * b0 + X'y * h
    call choleski(Vi) ! needed for inverting Vi as well as for draws, see below
    call DPOTRS('U', Nx, 1, Vi, Nx, b, Nx, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, ' [BAYESREGRESSIONSLOPE]'
       stop 1
    end if

    ! draw from posterior with mean b and inverse variance Vi 
    ! notice: I am not scaling the draws by the choleski; using another factorization instead
    ! specifically: chol(Vi) * draws = z 
    ! (where V'= chol(Vl)' * chol(Vi), i.e. chol is upper triangular)
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, Nx, bdraw, 0.0d0, 1.0d0)
    call DTRSV('U', 'N', 'N', Nx, Vi, Nx, bdraw, 1)

    ! add posterior mean
    bdraw = bdraw + b 

    ! resid = y - X * bdraw
    call dgemv('N', T, Nx, -1.0d0, X, T, bdraw, 1, 1.0d0, y, 1)

  END SUBROUTINE bayesDiffuseRegressionSlope

  ! @\newpage\subsection{bayesAR1SUR}@
  SUBROUTINE bayesAR1SUR(N, T, rhodraw, y, ylag, sqrtVshock, rho0, rhoV0i, VSLstream)

    ! draws vector of AR1 coefficients in SUR system of otherwise univariate AR1s

    INTENT(INOUT) :: y ! returns residual
    INTENT(OUT) :: rhodraw
    INTENT(IN) :: N, T, ylag, sqrtVshock, rho0, rhoV0i
    INTENT(INOUT) :: VSLstream

    INTEGER :: T, N, i, k, status
    DOUBLE PRECISION, DIMENSION(N,N) :: rhoV0i, rhoVi, sqrtVshock, H, Hchol, XX
    DOUBLE PRECISION, DIMENSION(N) ::   rho, rhodraw, rho0
    DOUBLE PRECISION, DIMENSION(N,T) :: y, ylag, ytilde
    TYPE (vsl_stream_state) :: VSLstream

    ! NOTE: sqrtVshock is assumed to be UPPER triangular-right Choleski
    ! hence, cannot use DPOTRS but a se

    ! Hchol = inv(sqrtVshock) ; note that Hchol is upper triangular
    Hchol = sqrtVshock
    call dtrtri('U', 'N', N, Hchol, N, status)
    if (status /= 0) then
       write(*,*) 'DTRTRI error: ', status, ' [bayesAR1SUR]'
       stop 1
    end if
    ! zero out the lower triangular part
    forall (i=2:N) Hchol(i,1:i-2) = 0.0d0

    ! H = Hchol' * Hchol
    H = 0.0d0
    call dsyrk('u','t', n, n, 1.0d0, Hchol, N, 0.0d0, H, N)
    ! call savemat(sqrtVshock, 'sqrtVshock.debug')
    ! call savemat(H, 'H.debug')
    ! call savemat(Hchol, 'Hchol.debug')

    ! ytilde = H y
    call dsymm('l','u',n,T,1.0d0,H,n,y,N,0.0d0,ytilde,N)
    ! call savemat(ytilde, 'ytilde.debug')
    ! call savemat(y, 'y.debug')

    ! XX = ylag * ylag'
    XX = 0.0d0 ! to clean out lower triangular part of XX
    call DSYRK('U','N',N,T,1.0d0,ylag,N,0.0d0,XX,N)
    ! call savemat(ylag, 'ylag.debug')
    ! call savemat(xx, 'xx.debug')

    ! prior/posterior
    ! iV = iV0 + XX .* H; exploiting special case where each equation has a separate, scalar regressor
    rhoVi = rhoV0i + xx * H
    ! call savemat(rhoVi, 'rhoVi.debug')

    ! posterior mean, step 1
    ! rho = inv(V0) * rho0 + sum(ylag * ytilde)
    rho = sum(ylag * ytilde, 2)
    call DSYMV('U', N, 1.0d0, rhoV0i, N, rho0, 1, 1.0d0, rho, 1)
    ! posterior mean, step 2
    ! rho = inv(iV) rho
    ! first: choleski of VI
    call dpotrf('u', n, rhoVi, n, status)
    if (status /= 0) then
       write(*,*) 'DPOTRF error: ', status, ' [bayesAR1SUR]'
       stop 1
    end if
    ! second: inversion
    call DPOTRS('U', N, 1, rhoVi, N, rho, N, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, ' [bayesAR1SUR]'
       stop 1
    end if

    ! call savevec(rho, 'rho.debug')
    ! stop 11

    ! draw from posterior with mean rho and inverse variance Vi 
    ! as usual, using right-upper choleski factor (constructed already above)
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, N, rhodraw, 0.0d0, 1.0d0)
    call DTRSV('U', 'N', 'N', N, rhoVi, N, rhodraw, 1)

    ! add posterior mean
    rhodraw = rhodraw + rho

    ! resid = y - ylag * rhodraw
    forall (i=1:N,k=1:T) y(i,k) = y(i,k) - ylag(i,k) * rhodraw(i)

  END SUBROUTINE bayesAR1SUR

  SUBROUTINE minnesotaVCVsqrt(sqrtVf0, N, p, lambda1, lambda2)

    integer, intent(in) :: N, p
    double precision, intent(inout), dimension(N*N*p,N*N*p) :: sqrtVf0
    double precision, intent(in) :: lambda1, lambda2

    integer :: ndxVec, ndxLHS = 1, ndxLag = 1, ndxRHS = 1
    integer :: Nf

    Nf = N * N * p
    sqrtVf0 = 0.0d0

    ndxVec = 0
    do ndxLHS = 1,N
       do ndxLag = 1,p
          do ndxRHS = 1,N

             ndxVec = ndxVec + 1

             if (ndxLHS == ndxRHS) then
                sqrtVf0(ndxVec,ndxVec) = lambda1 / dble(ndxLag)
             else
                sqrtVf0(ndxVec,ndxVec) = lambda1 * lambda2 / dble(ndxLag)
             end if

          end do
       end do
    end do

  END SUBROUTINE minnesotaVCVsqrt

  ! @\newpage\subsection{bayesVARbarshock}@
  SUBROUTINE bayesVARbarshock(bdraw, Y, p, Ydata, Ny, T, ebar, iSigmaResid, b0, V0i, VSLstream)
    ! Bayesian VAR (assuming no constant)
    ! on exit, Y returns residuals Y - X * reshape(bdraw, Nx, Ny)
    ! notice: top rows of companion have transpose(reshape(bdraw,Nx,Ny)) 
    ! only upper triangular part of iSigmaResid will be used

    ! ebar is an exogenous shock term, to be subtracted from the LHS for the estimation (and will be added back afterwards


    INTENT(IN) :: Ydata, Ny, p, T, ebar, iSigmaResid, b0, V0i
    INTENT(OUT) :: Y, bdraw
    INTENT(INOUT) :: VSLstream
    INTEGER :: T, Nx, Ny, status, Nb, j, p
    DOUBLE PRECISION, DIMENSION(Ny * Ny * p,Ny * Ny * p) :: V0i, Vi
    DOUBLE PRECISION, DIMENSION(Ny * Ny * p) ::    b, b0, bdraw
    DOUBLE PRECISION :: iSigmaResid(Ny,Ny), Y(T,Ny), ebar(T,Ny), Ydata(-(p-1):T,Ny), X(T,Ny * p), XX(Ny * p, Ny * p), Xy(Ny * p, Ny), tmp(Ny * p, Ny)
    TYPE (vsl_stream_state) :: VSLstream

    ! STEP 1: construct regressors

    Y  = Ydata(1:T,:) - ebar

    Nx = Ny * p
    Nb = Ny * Nx
    FORALL (j = 1:p) X(:, ((j-1) * Ny + 1) : ((j-1) * Ny + Ny) ) = Ydata(-(j-1):T-j,:)

    ! STEP 2: estimate VAR coefficients: beta = inv(XX) * Xy


    ! XY = X'Y * iSigmaResid
    call DGEMM('T', 'N', Nx, Ny, T, 1.0d0, X, T, Y, T, 0.0d0, tmp, Nx)
    call DSYMM('R', 'U', Nx, Ny, 1.0d0, iSigmaResid, Ny, tmp, Nx, 0.0d0, XY, Nx)

    ! store vec(XY) in b
    call vec(b,XY)

    ! b = V0i * b0 + b 
    ! (not yet complete, need to multiply by posterior Variance, see below)
    call DSYMV('U', Nb, 1.0d0, V0i, Nb, b0, 1, 1.0d0, b, 1)

    ! POSTERIOR VARIANCE
    ! Vi = V0i + kron(iSigmaResid, X'X)

    call XprimeX(XX,X)
    call symmetric(XX) ! important for symkronecker
    Vi = V0i
    call symkronecker(1.0d0,iSigmaResid,Ny,XX,Nx,1.0d0,Vi)

    ! Solve for posterior mean
    ! solve: Vi * b = ...
    ! 1) Choleski factorization
    call dpotrf('u', Nb, Vi, Nb, status)
    if (status /= 0) then
       write(*,*) 'CHOLESKI ERROR:', status, ' [BAYESVAR]'

       call savemat(iSigmaResid, 'iSigmaResid.dat.debug') ! debug
       call savemat(V0i, 'V0i.dat.debug') ! debug
       call savemat(Vi, 'Vi.dat.debug') ! debug
       call savevec(b0, 'b0.dat.debug') ! debug
       call savevec(b, 'b.dat.debug') ! debug
       call savemat(X, 'X.dat.debug') ! debug
       call savemat(Y, 'Y.dat.debug') ! debug


       stop 1
    end if

    ! zero out lower triangular
    forall (j = 1 : Nb-1) Vi(j+1:Nb,j) = 0.0d0

    ! 2) solve Vi * b = z
    call DPOTRS('U', Nb, 1, Vi, Nb, b, Nb, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, ' [BAYESVAR]'
       stop 1
    end if

    ! DRAW FROM POSTERIOR with mean b and inverse variance Vi 
    ! notice: I am not scaling the draw)' * chol(Vi), i.e. chol is upper triangular)
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, Nb, bdraw, 0.0d0, 1.0d0)
    call DTRSV('U', 'N', 'N', Nb, Vi, Nb, bdraw, 1)

    ! add posterior mean
    bdraw = bdraw + b 

    ! resid = Y - X * reshape(beta, Nx, Ny)
    ! note: DGEMM does not care about explicitly reshaping beta
    call DGEMM('N','N',T,Ny,Nx,-1.0d0,X,T,bdraw,Nx,1.0d0,Y,T)

    Y = Y + ebar

  END SUBROUTINE bayesVARbarshock

  ! @\newpage\subsection{bayesVARSVbarshock}@
  SUBROUTINE bayesVARSVbarshock(bdraw, Y, p, Ydata, Ny, T, ebar, iSigmaResid, b0, V0i, VSLstream)
    ! Bayesian VAR with (known) Time-varying Volatility
    ! note: iSigmaResid is (Ny,Ny,T) and assumed upper triangular
    ! (assuming no constant)
    ! on exit, Y returns residuals Y  - X * reshape(bdraw, Nx, Ny)
    ! notice: top rows of companion have transpose(reshape(bdraw,Nx,Ny)) 
    !
    ! ebar is an exogenous shock term, to be subtracted from the LHS for the estimation (and will be added back afterwards)

    INTENT(IN) :: ebar, Ydata, Ny, p, T, iSigmaResid, b0, V0i
    INTENT(OUT) :: Y, bdraw
    INTENT(INOUT) :: VSLstream
    INTEGER :: T, Nx, Ny, status, Nb, j, p
    DOUBLE PRECISION, DIMENSION(Ny * Ny * p,Ny * Ny * p) :: V0i, Vi
    DOUBLE PRECISION, DIMENSION(Ny * Ny * p) ::    b, b0, bdraw
    DOUBLE PRECISION :: iSigmaResid(Ny,Ny,T), Y(T,Ny), Ytilde(T,Ny), Ydata(-(p-1):T,Ny), X(T,Ny * p), XX(Ny * p, Ny * p), XY(Ny * p, Ny)
    DOUBLE PRECISION :: ebar(T,Ny)
    TYPE (vsl_stream_state) :: VSLstream

    ! STEP 1: construct regressors


    Y  = Ydata(1:T,:) - ebar
    Nx = Ny * p
    Nb = Ny * Nx
    FORALL (j = 1:p) X(:, ((j-1) * Ny + 1) : ((j-1) * Ny + Ny) ) = Ydata(-(j-1):T-j,:)

    ! STEP 2: estimate VAR coefficients: beta = inv(XX) * Xy
    ! construct Ytilde(t) = iSigmaResid(t) Y(t)
    Ytilde = 0.0d0
    DO j = 1, T
       call dsymv('U', Ny, 1.0d0, iSigmaResid(:,:,j), Ny, Y(j,:), 1, 0.0d0, Ytilde(j,:), 1)
    END DO

    ! XY = sum_t {X(t) Ytilde(t)'}
    call DGEMM('T', 'N', Nx, Ny, T, 1.0d0, X, T, Ytilde, T, 0.0d0, XY, Nx)
    ! store vec(XY) in b
    call vec(b,XY)

    ! b = V0i * b0 + b 
    ! (b is not yet complete, need to multiply by posterior Variance, see below)
    call DSYMV('U', Nb, 1.0d0, V0i, Nb, b0, 1, 1.0d0, b, 1)

    ! POSTERIOR VARIANCE
    ! Vi = V0i + sum_t kron(iSigmaResid(t), X(t) X(t)')

    Vi = V0i
    DO j = 1, T

       XX = 0.0d0
       call DSYR('U',Nx,1.0d0,X(j,:),1,XX,Nx)
       call symmetric(XX) ! important for symkronecker
       call symkronecker(1.0d0,iSigmaResid(:,:,j),Ny,XX,Nx,1.0d0,Vi)
    END DO




    ! Solve for posterior mean
    ! solve: Vi * b = ...
    ! 1) Choleski factorization
    call dpotrf('u', Nb, Vi, Nb, status)
    if (status /= 0) then
       write(*,*) 'CHOLESKI ERROR:', status, ' [BAYESVAR]'

       call savemat(V0i, 'V0i.dat.debug') ! debug
       call savemat(Vi, 'Vi.dat.debug') ! debug
       call savevec(b0, 'b0.dat.debug') ! debug
       call savevec(b, 'b.dat.debug') ! debug
       call savemat(X, 'X.dat.debug') ! debug
       call savemat(Y, 'Y.dat.debug') ! debug


       stop 1
    end if

    ! zero out lower triangular
    forall (j = 1 : Nb-1) Vi(j+1:Nb,j) = 0.0d0

    ! 2) solve Vi * b = z
    call DPOTRS('U', Nb, 1, Vi, Nb, b, Nb, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, ' [BAYESVAR]'
       stop 1
    end if

    ! DRAW FROM POSTERIOR with mean b and inverse variance Vi 
    ! notice: I am not scaling the draw)' * chol(Vi), i.e. chol is upper triangular)
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, Nb, bdraw, 0.0d0, 1.0d0)
    call DTRSV('U', 'N', 'N', Nb, Vi, Nb, bdraw, 1)

    ! add posterior mean
    bdraw = bdraw + b 

    ! resid = Y - X * reshape(beta, Nx, Ny)
    ! note: DGEMM does not care about explicitly reshaping beta
    call DGEMM('N','N',T,Ny,Nx,-1.0d0,X,T,bdraw,Nx,1.0d0,Y,T)
    Y = Y + ebar


  END SUBROUTINE bayesVARSVbarshock

  ! @\newpage\subsection{bayesVAR}@
  SUBROUTINE bayesVAR(bdraw, Y, p, Ydata, Ny, T, iSigmaResid, b0, V0i, VSLstream)
    ! Bayesian VAR (assuming no constant)
    ! on exit, Y returns residuals Y - X * reshape(bdraw, Nx, Ny)
    ! notice: top rows of companion have transpose(reshape(bdraw,Nx,Ny)) 
    ! only upper triangular part of iSigmaResid will be used

    INTENT(IN) :: Ydata, Ny, p, T, iSigmaResid, b0, V0i
    INTENT(OUT) :: Y, bdraw
    INTENT(INOUT) :: VSLstream
    INTEGER :: T, Nx, Ny, status, Nb, j, p
    DOUBLE PRECISION, DIMENSION(Ny * Ny * p,Ny * Ny * p) :: V0i, Vi
    DOUBLE PRECISION, DIMENSION(Ny * Ny * p) ::    b, b0, bdraw
    DOUBLE PRECISION :: iSigmaResid(Ny,Ny), Y(T,Ny), Ydata(-(p-1):T,Ny), X(T,Ny * p), XX(Ny * p, Ny * p), Xy(Ny * p, Ny), tmp(Ny * p, Ny)
    TYPE (vsl_stream_state) :: VSLstream

    ! STEP 1: construct regressors

    Y  = Ydata(1:T,:)
    Nx = Ny * p
    Nb = Ny * Nx
    FORALL (j = 1:p) X(:, ((j-1) * Ny + 1) : ((j-1) * Ny + Ny) ) = Ydata(-(j-1):T-j,:)

    ! STEP 2: estimate VAR coefficients: beta = inv(XX) * Xy


    ! XY = X'Y * iSigmaResid
    call DGEMM('T', 'N', Nx, Ny, T, 1.0d0, X, T, Y, T, 0.0d0, tmp, Nx)
    call DSYMM('R', 'U', Nx, Ny, 1.0d0, iSigmaResid, Ny, tmp, Nx, 0.0d0, XY, Nx)

    ! store vec(XY) in b
    call vec(b,XY)

    ! b = V0i * b0 + b 
    ! (not yet complete, need to multiply by posterior Variance, see below)
    call DSYMV('U', Nb, 1.0d0, V0i, Nb, b0, 1, 1.0d0, b, 1)

    ! POSTERIOR VARIANCE
    ! Vi = V0i + kron(iSigmaResid, X'X)

    call XprimeX(XX,X)
    call symmetric(XX) ! important for symkronecker
    Vi = V0i
    call symkronecker(1.0d0,iSigmaResid,Ny,XX,Nx,1.0d0,Vi)

    ! Solve for posterior mean
    ! solve: Vi * b = ...
    ! 1) Choleski factorization
    call dpotrf('u', Nb, Vi, Nb, status)
    if (status /= 0) then
       write(*,*) 'CHOLESKI ERROR:', status, ' [BAYESVAR]'

       call savemat(iSigmaResid, 'iSigmaResid.dat.debug') ! debug
       call savemat(V0i, 'V0i.dat.debug') ! debug
       call savemat(Vi, 'Vi.dat.debug') ! debug
       call savevec(b0, 'b0.dat.debug') ! debug
       call savevec(b, 'b.dat.debug') ! debug
       call savemat(X, 'X.dat.debug') ! debug
       call savemat(Y, 'Y.dat.debug') ! debug


       stop 1
    end if

    ! zero out lower triangular
    forall (j = 1 : Nb-1) Vi(j+1:Nb,j) = 0.0d0

    ! 2) solve Vi * b = z
    call DPOTRS('U', Nb, 1, Vi, Nb, b, Nb, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, ' [BAYESVAR]'
       stop 1
    end if

    ! DRAW FROM POSTERIOR with mean b and inverse variance Vi 
    ! notice: I am not scaling the draw)' * chol(Vi), i.e. chol is upper triangular)
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, Nb, bdraw, 0.0d0, 1.0d0)
    call DTRSV('U', 'N', 'N', Nb, Vi, Nb, bdraw, 1)

    ! add posterior mean
    bdraw = bdraw + b 

    ! resid = Y - X * reshape(beta, Nx, Ny)
    ! note: DGEMM does not care about explicitly reshaping beta
    call DGEMM('N','N',T,Ny,Nx,-1.0d0,X,T,bdraw,Nx,1.0d0,Y,T)


  END SUBROUTINE bayesVAR

  ! @\newpage\subsection{bayesdiffuseVAR}@
  SUBROUTINE bayesdiffuseVAR(bdraw, Y, p, Ydata, Ny, T, iSigmaResid, VSLstream)
    ! Bayesian VAR (assuming no constant)
    ! on exit, Y returns residuals Y - X * reshape(bdraw, Nx, Ny)
    ! notice: top rows of companion have transpose(reshape(bdraw,Nx,Ny)) 
    ! only upper triangular part of iSigmaResid will be used

    INTENT(IN) :: Ydata, Ny, p, T, iSigmaResid
    INTENT(OUT) :: Y, bdraw
    INTENT(INOUT) :: VSLstream
    INTEGER :: T, Nx, Ny, status, Nb, j, p
    DOUBLE PRECISION, DIMENSION(Ny * Ny * p,Ny * Ny * p) :: Vi
    DOUBLE PRECISION, DIMENSION(Ny * Ny * p) ::    b, bdraw
    DOUBLE PRECISION :: iSigmaResid(Ny,Ny), Y(T,Ny), Ydata(-(p-1):T,Ny), X(T,Ny * p), XX(Ny * p, Ny * p), Xy(Ny * p, Ny), tmp(Ny * p, Ny)
    TYPE (vsl_stream_state) :: VSLstream

    ! STEP 1: construct regressors

    Y  = Ydata(1:T,:)
    Nx = Ny * p
    Nb = Ny * Nx
    FORALL (j = 1:p) X(:, ((j-1) * Ny + 1) : ((j-1) * Ny + Ny) ) = Ydata(-(j-1):T-j,:)

    ! STEP 2: estimate VAR coefficients: beta = inv(XX) * Xy


    ! XY = X'Y * iSigmaResid
    call DGEMM('T', 'N', Nx, Ny, T, 1.0d0, X, T, Y, T, 0.0d0, tmp, Nx)
    call DSYMM('R', 'U', Nx, Ny, 1.0d0, iSigmaResid, Ny, tmp, Nx, 0.0d0, XY, Nx)

    ! store vec(XY) in b
    call vec(b,XY)

    ! b = V0i * b0 + b 
    ! (not yet complete, need to multiply by posterior Variance, see below)
    ! call DSYMV('U', Nb, 1.0d0, V0i, Nb, b0, 1, 1.0d0, b, 1)

    ! POSTERIOR VARIANCE
    ! Vi = V0i + kron(iSigmaResid, X'X)

    call XprimeX(XX,X)
    call symmetric(XX) ! important for symkronecker
    Vi = 0.0d0 ! V0i
    call symkronecker(1.0d0,iSigmaResid,Ny,XX,Nx,0.0d0,Vi)

    ! Solve for posterior mean
    ! solve: Vi * b = ...
    ! 1) Choleski factorization
    call dpotrf('u', Nb, Vi, Nb, status)
    if (status /= 0) then
       write(*,*) 'CHOLESKI ERROR:', status, ' [BAYESVAR]'

       call savemat(iSigmaResid, 'iSigmaResid.dat.debug') ! debug
       ! call savemat(V0i, 'V0i.dat.debug') ! debug
       call savemat(Vi, 'Vi.dat.debug') ! debug
       ! call savevec(b0, 'b0.dat.debug') ! debug
       call savevec(b, 'b.dat.debug') ! debug
       call savemat(X, 'X.dat.debug') ! debug
       call savemat(Y, 'Y.dat.debug') ! debug


       stop 1
    end if

    ! zero out lower triangular
    forall (j = 1 : Nb-1) Vi(j+1:Nb,j) = 0.0d0

    ! 2) solve Vi * b = z
    call DPOTRS('U', Nb, 1, Vi, Nb, b, Nb, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, ' [BAYESVAR]'
       stop 1
    end if

    ! DRAW FROM POSTERIOR with mean b and inverse variance Vi 
    ! notice: I am not scaling the draw)' * chol(Vi), i.e. chol is upper triangular)
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, Nb, bdraw, 0.0d0, 1.0d0)
    call DTRSV('U', 'N', 'N', Nb, Vi, Nb, bdraw, 1)

    ! add posterior mean
    bdraw = bdraw + b 

    ! resid = Y - X * reshape(beta, Nx, Ny)
    ! note: DGEMM does not care about explicitly reshaping beta
    call DGEMM('N','N',T,Ny,Nx,-1.0d0,X,T,bdraw,Nx,1.0d0,Y,T)


  END SUBROUTINE bayesdiffuseVAR


  ! @\newpage\subsection{bayesVARscaleSV}@
  SUBROUTINE bayesVARscaleSV(bdraw, Y, p, Ydata, Ny, T, scaleSV, iSigmaResid, b0, V0i, VSLstream)
    ! Bayesian VAR (assuming no constant)
    ! on exit, Y returns residuals Y - X * reshape(bdraw, Nx, Ny)
    ! notice: top rows of companion have transpose(reshape(bdraw,Nx,Ny)) 
    ! only upper triangular part of iSigmaResid will be used
    ! scale SV assumes common scale factor for all equations

    ! NOTE: returns scaled residuals (i.e. after division by scaleSV)

    INTENT(IN) :: Ydata, Ny, p, T, iSigmaResid, b0, V0i, scaleSV
    INTENT(OUT) :: Y, bdraw
    INTENT(INOUT) :: VSLstream
    INTEGER :: T, Nx, Ny, status, Nb, j, tt, p
    DOUBLE PRECISION, DIMENSION(Ny * Ny * p,Ny * Ny * p) :: V0i, Vi
    DOUBLE PRECISION, DIMENSION(Ny * Ny * p) ::    b, b0, bdraw
    DOUBLE PRECISION :: iSigmaResid(Ny,Ny), Y(T,Ny), Ydata(-(p-1):T,Ny), X(T,Ny * p), XX(Ny * p, Ny * p), Xy(Ny * p, Ny), tmp(Ny * p, Ny)
    DOUBLE PRECISION :: scaleSV(T)
    TYPE (vsl_stream_state) :: VSLstream

    ! STEP 1: construct regressors

    Y  = Ydata(1:T,:)
    Nx = Ny * p
    Nb = Ny * Nx
    FORALL (j = 1:p) X(:, ((j-1) * Ny + 1) : ((j-1) * Ny + Ny) ) = Ydata(-(j-1):T-j,:)

    ! STEP 2: scale equations
    forall (tt=1:T,j=1:Ny) Y(tt,j) = Y(tt,j) / scaleSV(tt)
    forall (tt=1:T,j=1:Nx) X(tt,j) = X(tt,j) / scaleSV(tt)


    ! STEP 3: estimate VAR coefficients: beta = inv(XX) * Xy
    ! XY = X'Y * iSigmaResid
    call DGEMM('T', 'N', Nx, Ny, T, 1.0d0, X, T, Y, T, 0.0d0, tmp, Nx)
    call DSYMM('R', 'U', Nx, Ny, 1.0d0, iSigmaResid, Ny, tmp, Nx, 0.0d0, XY, Nx)

    ! store vec(XY) in b
    call vec(b,XY)

    ! b = V0i * b0 + b 
    ! (not yet complete, need to multiply by posterior Variance, see below)
    call DSYMV('U', Nb, 1.0d0, V0i, Nb, b0, 1, 1.0d0, b, 1)

    ! POSTERIOR VARIANCE
    ! Vi = V0i + kron(iSigmaResid, X'X)

    call XprimeX(XX,X)
    call symmetric(XX) ! important for symkronecker
    Vi = V0i
    call symkronecker(1.0d0,iSigmaResid,Ny,XX,Nx,1.0d0,Vi)

    ! Solve for posterior mean
    ! solve: Vi * b = ...
    ! 1) Choleski factorization
    call dpotrf('u', Nb, Vi, Nb, status)
    if (status /= 0) then
       write(*,*) 'CHOLESKI ERROR:', status, ' [BAYESVARSCALESV]'

       call savemat(iSigmaResid, 'iSigmaResid.dat.debug') ! debug
       call savemat(V0i, 'V0i.dat.debug') ! debug
       call savemat(Vi, 'Vi.dat.debug') ! debug
       call savevec(b0, 'b0.dat.debug') ! debug
       call savevec(b, 'b.dat.debug') ! debug
       call savemat(X, 'X.dat.debug') ! debug
       call savemat(Y, 'Y.dat.debug') ! debug


       stop 1
    end if

    ! zero out lower triangular
    forall (j = 1 : Nb-1) Vi(j+1:Nb,j) = 0.0d0

    ! 2) solve Vi * b = z
    call DPOTRS('U', Nb, 1, Vi, Nb, b, Nb, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, ' [BAYESVARSCALESV]'
       stop 1
    end if

    ! DRAW FROM POSTERIOR with mean b and inverse variance Vi 
    ! notice: I am not scaling the draw)' * chol(Vi), i.e. chol is upper triangular)
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, Nb, bdraw, 0.0d0, 1.0d0)
    call DTRSV('U', 'N', 'N', Nb, Vi, Nb, bdraw, 1)

    ! add posterior mean
    bdraw = bdraw + b 

    ! resid = Y - X * reshape(beta, Nx, Ny)
    ! note: DGEMM does not care about explicitly reshaping beta
    call DGEMM('N','N',T,Ny,Nx,-1.0d0,X,T,bdraw,Nx,1.0d0,Y,T)


    ! FOR NOW: do not rescale residuals
    ! ! finally: rescale residuals
    ! forall (tt=1:T,j=1:Ny) Y(tt,j) = Y(tt,j) * scaleSV(tt)

  END SUBROUTINE bayesVARscaleSV

  ! @\newpage\subsection{bayesVARSV}@
  SUBROUTINE bayesVARSV(bdraw, Y, p, Ydata, Ny, T, iSigmaResid, b0, V0i, VSLstream)
    ! Bayesian VAR with (known) Time-varying Volatility
    ! note: iSigmaResid is (Ny,Ny,T) and assumed upper triangular
    ! (assuming no constant)
    ! on exit, Y returns residuals Y - X * reshape(bdraw, Nx, Ny)
    ! notice: top rows of companion have transpose(reshape(bdraw,Nx,Ny)) 

    INTENT(IN) :: Ydata, Ny, p, T, iSigmaResid, b0, V0i
    INTENT(OUT) :: Y, bdraw
    INTENT(INOUT) :: VSLstream
    INTEGER :: T, Nx, Ny, status, Nb, j, p
    DOUBLE PRECISION, DIMENSION(Ny * Ny * p,Ny * Ny * p) :: V0i, Vi
    DOUBLE PRECISION, DIMENSION(Ny * Ny * p) ::    b, b0, bdraw
    DOUBLE PRECISION :: iSigmaResid(Ny,Ny,T), Y(T,Ny), Ytilde(T,Ny), Ydata(-(p-1):T,Ny), X(T,Ny * p), XX(Ny * p, Ny * p), XY(Ny * p, Ny)
    TYPE (vsl_stream_state) :: VSLstream

    ! STEP 1: construct regressors


    Y  = Ydata(1:T,:)
    Nx = Ny * p
    Nb = Ny * Nx
    FORALL (j = 1:p) X(:, ((j-1) * Ny + 1) : ((j-1) * Ny + Ny) ) = Ydata(-(j-1):T-j,:)

    ! STEP 2: estimate VAR coefficients: beta = inv(XX) * Xy
    ! construct Ytilde(t) = iSigmaResid(t) Y(t)
    Ytilde = 0.0d0
    DO j = 1, T
       call dsymv('U', Ny, 1.0d0, iSigmaResid(:,:,j), Ny, Y(j,:), 1, 0.0d0, Ytilde(j,:), 1)
    END DO
    ! call savemat(Y, 'y.debug')
    ! call savemat(Ytilde, 'ytilde.debug')
    ! call savemat(X, 'x.debug')

    ! XY = sum_t {X(t) Ytilde(t)'}
    call DGEMM('T', 'N', Nx, Ny, T, 1.0d0, X, T, Ytilde, T, 0.0d0, XY, Nx)
    ! store vec(XY) in b
    call vec(b,XY)

    ! b = V0i * b0 + b 
    ! (b is not yet complete, need to multiply by posterior Variance, see below)
    call DSYMV('U', Nb, 1.0d0, V0i, Nb, b0, 1, 1.0d0, b, 1)

    ! POSTERIOR VARIANCE
    ! Vi = V0i + sum_t kron(iSigmaResid(t), X(t) X(t)')

    Vi = V0i
    DO j = 1, T

       XX = 0.0d0
       call DSYR('U',Nx,1.0d0,X(j,:),1,XX,Nx)
       call symmetric(XX) ! important for symkronecker
       call symkronecker(1.0d0,iSigmaResid(:,:,j),Ny,XX,Nx,1.0d0,Vi)
    END DO




    ! Solve for posterior mean
    ! solve: Vi * b = ...
    ! 1) Choleski factorization
    call dpotrf('u', Nb, Vi, Nb, status)
    if (status /= 0) then
       write(*,*) 'CHOLESKI ERROR:', status, ' [BAYESVAR]'

       ! do j=1,T

       ! end do


       call savemat(V0i, 'V0i.dat.debug') ! debug
       call savemat(Vi, 'Vi.dat.debug') ! debug
       call savevec(b0, 'b0.dat.debug') ! debug
       call savevec(b, 'b.dat.debug') ! debug
       call savemat(X, 'X.dat.debug') ! debug
       call savemat(Y, 'Y.dat.debug') ! debug


       stop 1
    end if

    ! zero out lower triangular
    forall (j = 1 : Nb-1) Vi(j+1:Nb,j) = 0.0d0

    ! 2) solve Vi * b = z
    call DPOTRS('U', Nb, 1, Vi, Nb, b, Nb, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, ' [BAYESVAR]'
       stop 1
    end if

    ! DRAW FROM POSTERIOR with mean b and inverse variance Vi 
    ! notice: I am not scaling the draw)' * chol(Vi), i.e. chol is upper triangular)
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, Nb, bdraw, 0.0d0, 1.0d0)
    call DTRSV('U', 'N', 'N', Nb, Vi, Nb, bdraw, 1)

    ! add posterior mean
    bdraw = bdraw + b

    ! resid = Y - X * reshape(beta, Nx, Ny)
    ! note: DGEMM does not care about explicitly reshaping beta
    call DGEMM('N','N',T,Ny,Nx,-1.0d0,X,T,bdraw,Nx,1.0d0,Y,T)


  END SUBROUTINE bayesVARSV

  ! @\newpage\subsection{bayesdiffuseVARSV}@
  SUBROUTINE bayesdiffuseVARSV(bdraw, Y, p, Ydata, Ny, T, iSigmaResid, VSLstream)
    ! Bayesian VAR with (known) Time-varying Volatility
    ! note: iSigmaResid is (Ny,Ny,T) and assumed upper triangular
    ! (assuming no constant)
    ! on exit, Y returns residuals Y - X * reshape(bdraw, Nx, Ny)
    ! notice: top rows of companion have transpose(reshape(bdraw,Nx,Ny)) 

    INTENT(IN) :: Ydata, Ny, p, T, iSigmaResid
    INTENT(OUT) :: Y, bdraw
    INTENT(INOUT) :: VSLstream
    INTEGER :: T, Nx, Ny, status, Nb, j, p
    DOUBLE PRECISION, DIMENSION(Ny * Ny * p,Ny * Ny * p) :: Vi
    DOUBLE PRECISION, DIMENSION(Ny * Ny * p) ::    b, bdraw
    DOUBLE PRECISION :: iSigmaResid(Ny,Ny,T), Y(T,Ny), Ytilde(T,Ny), Ydata(-(p-1):T,Ny), X(T,Ny * p), XX(Ny * p, Ny * p), XY(Ny * p, Ny)
    TYPE (vsl_stream_state) :: VSLstream

    ! STEP 1: construct regressors


    Y  = Ydata(1:T,:)
    Nx = Ny * p
    Nb = Ny * Nx
    FORALL (j = 1:p) X(:, ((j-1) * Ny + 1) : ((j-1) * Ny + Ny) ) = Ydata(-(j-1):T-j,:)

    ! STEP 2: estimate VAR coefficients: beta = inv(XX) * Xy
    ! construct Ytilde(t) = iSigmaResid(t) Y(t)
    Ytilde = 0.0d0
    DO j = 1, T
       call dsymv('U', Ny, 1.0d0, iSigmaResid(:,:,j), Ny, Y(j,:), 1, 0.0d0, Ytilde(j,:), 1)
    END DO
    ! call savemat(Y, 'y.debug')
    ! call savemat(Ytilde, 'ytilde.debug')
    ! call savemat(X, 'x.debug')

    ! XY = sum_t {X(t) Ytilde(t)'}
    call DGEMM('T', 'N', Nx, Ny, T, 1.0d0, X, T, Ytilde, T, 0.0d0, XY, Nx)
    ! store vec(XY) in b
    call vec(b,XY)

    ! b = V0i * b0 + b 
    ! (b is not yet complete, need to multiply by posterior Variance, see below)
    ! call DSYMV('U', Nb, 1.0d0, V0i, Nb, b0, 1, 1.0d0, b, 1)

    ! POSTERIOR VARIANCE
    ! Vi = V0i + sum_t kron(iSigmaResid(t), X(t) X(t)')

    Vi = 0.0d0
    DO j = 1, T

       XX = 0.0d0
       call DSYR('U',Nx,1.0d0,X(j,:),1,XX,Nx)
       call symmetric(XX) ! important for symkronecker
       call symkronecker(1.0d0,iSigmaResid(:,:,j),Ny,XX,Nx,1.0d0,Vi)
    END DO




    ! Solve for posterior mean
    ! solve: Vi * b = ...
    ! 1) Choleski factorization
    call dpotrf('u', Nb, Vi, Nb, status)
    if (status /= 0) then
       write(*,*) 'CHOLESKI ERROR:', status, ' [BAYESVAR]'

       call savemat(Vi, 'Vi.dat.debug') ! debug
       call savevec(b, 'b.dat.debug') ! debug
       call savemat(X, 'X.dat.debug') ! debug
       call savemat(Y, 'Y.dat.debug') ! debug
       call savearray3(iSigmaResid, 'iSigmaResid', 'debug') 

       stop 1
    end if

    ! zero out lower triangular
    forall (j = 1 : Nb-1) Vi(j+1:Nb,j) = 0.0d0

    ! 2) solve Vi * b = z
    call DPOTRS('U', Nb, 1, Vi, Nb, b, Nb, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, ' [BAYESVAR]'
       stop 1
    end if

    ! DRAW FROM POSTERIOR with mean b and inverse variance Vi 
    ! notice: I am not scaling the draw)' * chol(Vi), i.e. chol is upper triangular)
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, Nb, bdraw, 0.0d0, 1.0d0)
    call DTRSV('U', 'N', 'N', Nb, Vi, Nb, bdraw, 1)

    ! add posterior mean
    bdraw = bdraw + b

    ! resid = Y - X * reshape(beta, Nx, Ny)
    ! note: DGEMM does not care about explicitly reshaping beta
    call DGEMM('N','N',T,Ny,Nx,-1.0d0,X,T,bdraw,Nx,1.0d0,Y,T)


  END SUBROUTINE bayesdiffuseVARSV

  ! @\newpage\subsection{bayesVARSVconst}@
  SUBROUTINE bayesVARSVconst(bdraw, Y, p, Ydata, Ny, T, iSigmaResid, b0, V0i, VSLstream)
    ! Bayesian VAR with (known) Time-varying Volatility
    !
    ! including a constant!
    !
    ! note: iSigmaResid is (Ny,Ny,T) and assumed upper triangular
    ! on exit, Y returns residuals Y - X * reshape(bdraw, Nx, Ny)
    ! notice: top rows of companion have transpose(reshape(bdraw,Nx,Ny)) 

    INTENT(IN) :: Ydata, Ny, p, T, iSigmaResid, b0, V0i
    INTENT(OUT) :: Y, bdraw
    INTENT(INOUT) :: VSLstream
    INTEGER :: T, Nx, Ny, status, Nb, j, p
    DOUBLE PRECISION, DIMENSION(Ny * (Ny * p + 1),Ny * (Ny * p + 1)) :: V0i, Vi
    DOUBLE PRECISION, DIMENSION(Ny * (Ny * p + 1)) ::    b, b0, bdraw
    DOUBLE PRECISION :: iSigmaResid(Ny,Ny,T), Y(T,Ny), Ytilde(T,Ny), Ydata(-(p-1):T,Ny), X(T,Ny * p + 1), XX(Ny * p + 1, Ny * p + 1), XY(Ny * p + 1, Ny)
    TYPE (vsl_stream_state) :: VSLstream

    ! STEP 1: construct regressors

    Y  = Ydata(1:T,:)
    Nx = Ny * p + 1
    Nb = Ny * Nx
    X = 1.0d0
    FORALL (j = 1:p) X(:, 1 + ((j-1) * Ny + 1) : 1 + ((j-1) * Ny + Ny) ) = Ydata(-(j-1):T-j,:)


    ! STEP 2: estimate VAR coefficients: beta = inv(XX) * Xy
    ! construct Ytilde(t) = iSigmaResid(t) Y(t)

    Ytilde = 0.0d0
    DO j = 1, T
       call dsymv('U', Ny, 1.0d0, iSigmaResid(:,:,j), Ny, Y(j,:), 1, 0.0d0, Ytilde(j,:), 1)
    END DO
    ! call savemat(Y, 'y.debug')
    ! call savemat(Ytilde, 'ytilde.debug')
    ! call savemat(X, 'x.debug')

    ! XY = sum_t {X(t) Ytilde(t)'}
    call DGEMM('T', 'N', Nx, Ny, T, 1.0d0, X, T, Ytilde, T, 0.0d0, XY, Nx)
    ! store vec(XY) in b
    call vec(b,XY)

    ! b = V0i * b0 + b 
    ! (b is not yet complete, need to multiply by posterior Variance, see below)
    call DSYMV('U', Nb, 1.0d0, V0i, Nb, b0, 1, 1.0d0, b, 1)

    ! POSTERIOR VARIANCE
    ! Vi = V0i + sum_t kron(iSigmaResid(t), X(t) X(t)')
    Vi = V0i
    DO j = 1, T

       XX = 0.0d0
       call DSYR('U',Nx,1.0d0,X(j,:),1,XX,Nx)
       call symmetric(XX) ! important for symkronecker
       call symkronecker(1.0d0,iSigmaResid(:,:,j),Ny,XX,Nx,1.0d0,Vi)
    END DO

    ! Solve for posterior mean
    ! solve: Vi * b = ...
    ! 1) Choleski factorization
    call dpotrf('u', Nb, Vi, Nb, status)
    if (status /= 0) then
       write(*,*) 'CHOLESKI ERROR:', status, ' [BAYESVAR]'

       call savemat(V0i, 'V0i.dat.debug') ! debug
       call savemat(Vi, 'Vi.dat.debug') ! debug
       call savevec(b0, 'b0.dat.debug') ! debug
       call savevec(b, 'b.dat.debug') ! debug
       call savemat(X, 'X.dat.debug') ! debug
       call savemat(Y, 'Y.dat.debug') ! debug


       stop 1
    end if

    ! zero out lower triangular
    forall (j = 1 : Nb-1) Vi(j+1:Nb,j) = 0.0d0

    ! choleski of Vi
    call DPOTRS('U', Nb, 1, Vi, Nb, b, Nb, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, ' [BAYESVAR]'
       stop 1
    end if

    ! DRAW FROM POSTERIOR with mean b and inverse variance Vi 
    ! notice: I am not scaling the draw)' * chol(Vi), i.e. chol is upper triangular)
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, Nb, bdraw, 0.0d0, 1.0d0)
    call DTRSV('U', 'N', 'N', Nb, Vi, Nb, bdraw, 1)

    ! add posterior mean
    bdraw = bdraw + b

    ! resid = Y - X * reshape(beta, Nx, Ny)
    ! note: DGEMM does not care about explicitly reshaping beta
    call DGEMM('N','N',T,Ny,Nx,-1.0d0,X,T,bdraw,Nx,1.0d0,Y,T)

  END SUBROUTINE bayesVARSVconst


  ! @\newpage\subsection{bayesVARZSV}@
  SUBROUTINE bayesVARZSV(bdraw, Y, p, Ydata, Ny, T, Z, Nz, iSigmaResid, b0, V0i, VSLstream)
    ! Bayesian VAR with (known) Time-varying Volatility
    ! note: iSigmaResid is (Ny,Ny,T) and assumed upper triangular
    !
    ! including exogenous Z regressors
    !
    ! on exit, Y returns residuals Y - X * reshape(bdraw, Nx, Ny)
    ! notice: top rows of companion have transpose(reshape(bdraw,Nx,Ny)) 

    INTENT(IN) :: Ydata, Ny, p, T, iSigmaResid, b0, V0i
    INTENT(IN) :: Z, Nz
    INTENT(OUT) :: Y, bdraw
    INTENT(INOUT) :: VSLstream
    INTEGER :: T, Ny, status, Nb, j, p
    INTEGER :: Nz 
    INTEGER :: Nx ! = (Ny * p + Nz)
    DOUBLE PRECISION, DIMENSION(Ny * (Ny * p + Nz), Ny *(Ny * p + Nz)) :: V0i, Vi
    DOUBLE PRECISION, DIMENSION(Ny * (Ny * p + Nz)) ::    b, b0, bdraw
    DOUBLE PRECISION :: iSigmaResid(Ny,Ny,T), Y(T,Ny), Ytilde(T,Ny), Ydata(-(p-1):T,Ny), X(T,Ny * p + Nz), XX(Ny * p + Nz, Ny * p + Nz), XY(Ny * p + Nz, Ny)
    DOUBLE PRECISION :: Z(T,Nz) ! note: length T, not Tdata
    TYPE (vsl_stream_state) :: VSLstream

    ! STEP 1: construct regressors


    Y  = Ydata(1:T,:)
    Nx = Ny * p + Nz
    Nb = Ny * Nx
    ! collect lags of Ydata
    FORALL (j = 1:p) X(:, ((j-1) * Ny + 1) : ((j-1) * Ny + Ny) ) = Ydata(-(j-1):T-j,:)
    ! collect exogenous regressors
    X(:,Ny * p + 1 : Nx) = z


    ! STEP 2: estimate VAR coefficients: beta = inv(XX) * Xy
    ! construct Ytilde(t) = iSigmaResid(t) Y(t)
    Ytilde = 0.0d0
    DO j = 1, T
       call dsymv('U', Ny, 1.0d0, iSigmaResid(:,:,j), Ny, Y(j,:), 1, 0.0d0, Ytilde(j,:), 1)
    END DO

    ! XY = sum_t {X(t) Ytilde(t)'}
    call DGEMM('T', 'N', Nx, Ny, T, 1.0d0, X, T, Ytilde, T, 0.0d0, XY, Nx)
    ! store vec(XY) in b
    call vec(b,XY)

    ! b = V0i * b0 + b 
    ! (b is not yet complete, need to multiply by posterior Variance, see below)
    call DSYMV('U', Nb, 1.0d0, V0i, Nb, b0, 1, 1.0d0, b, 1)

    ! POSTERIOR VARIANCE
    ! Vi = V0i + sum_t kron(iSigmaResid(t), X(t) X(t)')

    Vi = V0i
    DO j = 1, T

       XX = 0.0d0
       call DSYR('U',Nx,1.0d0,X(j,:),1,XX,Nx)
       call symmetric(XX) ! important for symkronecker
       call symkronecker(1.0d0,iSigmaResid(:,:,j),Ny,XX,Nx,1.0d0,Vi)
    END DO




    ! Solve for posterior mean
    ! solve: Vi * b = ...
    ! 1) Choleski factorization
    call dpotrf('u', Nb, Vi, Nb, status)
    if (status /= 0) then
       write(*,*) 'CHOLESKI ERROR:', status, ' [BAYESVAR]'

       ! do j=1,T

       ! end do


       call savemat(V0i, 'V0i.dat.debug') ! debug
       call savemat(Vi, 'Vi.dat.debug') ! debug
       call savevec(b0, 'b0.dat.debug') ! debug
       call savevec(b, 'b.dat.debug') ! debug
       call savemat(X, 'X.dat.debug') ! debug
       call savemat(Y, 'Y.dat.debug') ! debug


       stop 1
    end if

    ! zero out lower triangular
    forall (j = 1 : Nb-1) Vi(j+1:Nb,j) = 0.0d0

    ! 2) solve Vi * b = z
    call DPOTRS('U', Nb, 1, Vi, Nb, b, Nb, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, ' [BAYESVAR]'
       stop 1
    end if

    ! DRAW FROM POSTERIOR with mean b and inverse variance Vi 
    ! notice: I am not scaling the draw)' * chol(Vi), i.e. chol is upper triangular)
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, Nb, bdraw, 0.0d0, 1.0d0)
    call DTRSV('U', 'N', 'N', Nb, Vi, Nb, bdraw, 1)

    ! add posterior mean
    bdraw = bdraw + b

    ! resid = Y - X * reshape(beta, Nx, Ny)
    ! note: DGEMM does not care about explicitly reshaping beta
    call DGEMM('N','N',T,Ny,Nx,-1.0d0,X,T,bdraw,Nx,1.0d0,Y,T)


  END SUBROUTINE bayesVARZSV

  ! @\newpage\subsection{bayesVARXSV}@
  SUBROUTINE bayesVARXSV(bdraw, Y, Ny, T, X, Nx, iSigmaResid, b0, V0i, VSLstream)
    ! Bayesian VAR with (known) Time-varying Volatility
    !
    ! with given matrix of regressors
    !
    ! note: iSigmaResid is (Ny,Ny,T) and assumed upper triangular
    ! on exit, Y returns residuals Y - X * reshape(bdraw, Nx, Ny)
    ! notice: top rows of companion have transpose(reshape(bdraw,Nx,Ny)) 

    INTEGER, INTENT(IN) :: T, Nx, Ny
    DOUBLE PRECISION, INTENT(INOUT) :: Y(T,Ny)
    DOUBLE PRECISION, INTENT(IN) :: X(T,Nx)
    DOUBLE PRECISION, INTENT(IN), DIMENSION(Ny * Nx) :: b0
    DOUBLE PRECISION, INTENT(OUT), DIMENSION(Ny * Nx) :: bdraw
    DOUBLE PRECISION, DIMENSION(Ny * Nx) :: b
    DOUBLE PRECISION, INTENT(IN), DIMENSION(Ny * Nx,Ny * Nx) :: V0i
    DOUBLE PRECISION, DIMENSION(Ny * Nx,Ny * Nx) :: Vi
    DOUBLE PRECISION, INTENT(IN), DIMENSION(Ny,Ny,T)  :: iSigmaResid

    INTEGER :: Nb, status, j

    DOUBLE PRECISION :: Ytilde(T,Ny), XX(Nx,Nx), XY(Nx, Ny)
    TYPE (vsl_stream_state), INTENT(INOUT) :: VSLstream

    ! STEP 1: construct regressors

    Nb = Ny * Nx

    ! STEP 2: estimate VAR coefficients: beta = inv(XX) * Xy
    ! construct Ytilde(t) = iSigmaResid(t) Y(t)

    Ytilde = 0.0d0
    DO j = 1, T
       call dsymv('U', Ny, 1.0d0, iSigmaResid(:,:,j), Ny, Y(j,:), 1, 0.0d0, Ytilde(j,:), 1)
    END DO

    ! POSTERIOR VARIANCE
    ! Vi = V0i + sum_t kron(iSigmaResid(t), X(t) X(t)')
    Vi = V0i
    DO j = 1, T
       XX = 0.0d0
       call DSYR('U',Nx,1.0d0,X(j,:),1,XX,Nx)
       call symmetric(XX) ! important for symkronecker
       call symkronecker(1.0d0,iSigmaResid(:,:,j),Ny,XX,Nx,1.0d0,Vi)
    END DO

    ! Choleski factorization of posterior variance
    call savemat(Vi, 'Vipre.debug') ! debug
    call dpotrf('u', Nb, Vi, Nb, status)
    if (status /= 0) then
       write(*,*) 'CHOLESKI ERROR:', status, ' [BAYESVAR-X-SV]'
       call savemat(V0i, 'V0i.debug') ! debug
       call savemat(Vi, 'Vi.debug') ! debug
       call savevec(b0, 'b0.debug') ! debug
       call savevec(b, 'b.debug') ! debug
       call savemat(X, 'X.debug') ! debug
       call savemat(Y, 'Y.debug') ! debug
       stop 1
    end if
    ! zero out lower triangular
    forall (j = 1 : Nb-1) Vi(j+1:Nb,j) = 0.0d0


    ! prepare computation of posterior mean
    ! 1) XY = sum_t {X(t) Ytilde(t)'}
    call DGEMM('T', 'N', Nx, Ny, T, 1.0d0, X, T, Ytilde, T, 0.0d0, XY, Nx)
    ! 2) b = vec(XY) 
    call vec(b,XY)
    ! 3) b = V0i * b0 + b 
    call DSYMV('U', Nb, 1.0d0, V0i, Nb, b0, 1, 1.0d0, b, 1)
    ! 4) Solve for posterior mean Vi * b = b
    call DPOTRS('U', Nb, 1, Vi, Nb, b, Nb, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, ' [BAYESVAR]'
       stop 1
    end if

    ! DRAW FROM POSTERIOR with inverse variance Vi 
    ! notice: I am not scaling the draw)' * chol(Vi), i.e. chol is upper triangular)
    status  = vdrnggaussian(VSLmethodGaussian, VSLstream, Nb, bdraw, 0.0d0, 1.0d0)
    call DTRSV('U', 'N', 'N', Nb, Vi, Nb, bdraw, 1)
    ! add posterior mean
    bdraw = bdraw + b

    ! resid = Y - X * reshape(beta, Nx, Ny)
    ! note: DGEMM does not care about explicitly reshaping beta
    call DGEMM('N','N',T,Ny,Nx,-1.0d0,X,T,bdraw,Nx,1.0d0,Y,T)

  END SUBROUTINE bayesVARXSV

  ! @\newpage\subsection{bayesVARXSVtriang}@
  SUBROUTINE bayesVARXSVtriang(bdraw, Y, Ny, T, X, Nx, SVol, Ainv, b0, V0i, VSLstream)
    ! Bayesian VAR with (known) Time-varying Volatility
    !
    ! with given matrix of regressors
    !
    ! triangular algorithm of CCM, Ainv in unit lower triangular choleski factor
    !
    ! on exit, Y returns residuals Y - X * reshape(bdraw, Nx, Ny)
    !
    ! notice: top rows of companion have transpose(reshape(bdraw,Nx,Ny)) 
    ! Prior V0i is assumed block diagonal (so we can pick marginals by subindexing)

    INTEGER, INTENT(IN) :: T, Nx, Ny
    DOUBLE PRECISION, INTENT(INOUT) :: Y(T,Ny)
    DOUBLE PRECISION, INTENT(IN) :: X(T,Nx), Ainv(Ny,Ny)
    DOUBLE PRECISION, INTENT(IN), DIMENSION(Ny * Nx) :: b0
    DOUBLE PRECISION, INTENT(OUT), DIMENSION(Ny * Nx) :: bdraw
    DOUBLE PRECISION, INTENT(IN), DIMENSION(Ny * Nx,Ny * Nx) :: V0i
    DOUBLE PRECISION, INTENT(IN), DIMENSION(T,Ny)  :: SVol

    DOUBLE PRECISION :: Yresid(T,Ny), lhs(T), rhs(T,Nx) 
    DOUBLE PRECISION, DIMENSION(Nx) :: thisb
    INTEGER :: i, jj, kk
    INTEGER :: ndx(Nx)

    TYPE (vsl_stream_state), INTENT(INOUT) :: VSLstream


    ! Nb = Ny * Nx
    bdraw  = 0.0d0
    Yresid = 0.0d0

    ! loop over VAR equations
    do i=1,Ny

       ! prepare lhs (loop version)
       ! lhs = Y(:,i)
       ! do jj=1,i-1
       !    ! forall(kk=1:T) lhs(kk) = lhs(kk) - Ainv(i,jj) * Yresid(kk,jj)
       !    lhs = lhs - Ainv(i,jj) * Yresid(:,jj)
       ! end do

       ! prepare lhs (DGEMV)
       lhs = Y(:,i)
       if (i .gt. 1) then
          ! lhs = y - yresid(:,1:i-1) * Ainv(i,1:i-1)'
          call DGEMV('n',T,i-1,-1.0d0,Yresid(:,1:i-1),T,Ainv(i,1:i-1),1,1.0d0,lhs,1)
       end if
       ! scale lhs
       forall (kk=1:T)   lhs(kk) = lhs(kk) / SVol(kk,i)
       ! scale rhs
       forall (kk=1:T,jj=1:Nx) rhs(kk,jj) = X(kk,jj) / SVol(kk,i)

       ! index into coefficient vector
       ndx = (/ (i-1) * Nx + 1 : i * Nx /)
       call bayesRegressionSlope(thisb, lhs, rhs, Nx, T, 1.0d0, b0(ndx), V0i(ndx,ndx), VSLstream)

       ! store results
       bdraw(ndx) = thisb !  needed to avoid compiler warnings
       forall (kk=1:T) Yresid(kk,i) = lhs(kk) * SVol(kk,i)

    end do

    ! Yresid = Y - X * reshape(beta, Nx, Ny), and store in Y
    ! note: DGEMM does not care about explicitly reshaping beta
    call DGEMM('N','N',T,Ny,Nx,-1.0d0,X,T,bdraw,Nx,1.0d0,Y,T)


  END SUBROUTINE bayesVARXSVtriang

  ! @\newpage\subsection{bayesVARXSVcta}@
  SUBROUTINE bayesVARXSVcta(bdraw, Y, pai, Ny, T, X, Nx, SVol, A, b0, V0i, VSLstream)
    ! Bayesian VAR with (known) Time-varying Volatility
    !
    ! with given matrix of regressors
    !
    ! triangular algorithm of CCM, A in unit lower triangular choleski factor
    !
    ! on exit, Y returns residuals Y - X * reshape(paidraw, Nx, Ny)
    !
    ! notice: top rows of companion have transpose(reshape(paidraw,Nx,Ny)) 
    ! Prior V0i is assumed block diagonal (so we can pick marginals by subindexing)

    INTEGER, INTENT(IN) :: T, Nx, Ny
    DOUBLE PRECISION, INTENT(INOUT) :: Y(T,Ny)
    DOUBLE PRECISION, INTENT(IN) :: X(T,Nx), A(Ny,Ny)
    DOUBLE PRECISION, INTENT(IN), DIMENSION(Ny * Nx) :: b0
    DOUBLE PRECISION, INTENT(OUT), DIMENSION(Ny * Nx) :: bdraw
    DOUBLE PRECISION, INTENT(IN), DIMENSION(Ny * Nx,Ny * Nx) :: V0i
    DOUBLE PRECISION, INTENT(IN), DIMENSION(T,Ny)  :: SVol

    DOUBLE PRECISION, INTENT(IN), DIMENSION(Nx,Ny) :: pai
    DOUBLE PRECISION, DIMENSION(Nx,Ny) :: paidraw

    DOUBLE PRECISION, DIMENSION(T,Ny) :: resid, residA

    DOUBLE PRECISION :: lhs(T*Ny), rhs(T*Ny,Nx), lambda(T*Ny)
    DOUBLE PRECISION, DIMENSION(Nx) :: thisb
    INTEGER :: Tj, Nj ! number of obs in jth equation
    INTEGER :: j, jj, kk
    INTEGER :: ndx(Nx)

    TYPE (vsl_stream_state), INTENT(INOUT) :: VSLstream


    paidraw = pai

    ! call savemat(pai, 'pai0.debug')
    ! call savemat(V0i, 'V0i.debug')
    ! call savevec(b0, 'b0.debug')

    ! call savemat(SVol, 'SVol.debug')
    ! call savemat(Y, 'Y.debug')
    ! call savemat(X, 'X.debug')
    ! call savemat(A, 'A.debug')


    ! loop over VAR equations
    do j=1,Ny

       Nj           = (Ny - j) + 1
       Tj           = Nj * T
       paidraw(:,j) = 0.0d0

       lhs    = 0.0d0
       rhs    = 0.0d0
       lambda = 0.0d0
       residA = 0.0d0
       resid  = Y

       ! 1: lhs
       ! resid = y - x * paidraw
       call DGEMM('N','N',T,Ny,Nx,-1.0d0,X,T,paidraw,Nx,1.0d0,resid,T)


       ! residA(:,1:Ny-j) = resid * A(j:N,:)'
       call DGEMM('N','T',T,Nj,Ny,1.0d0,resid,T,A(j:Ny,:),Nj,0.0d0,residA(:,1:Nj),T)
       lhs(1:Tj) = reshape(residA(:,1:Nj), (/ Tj /))

       ! call savemat(resid, 'resid.debug')
       ! call savemat(residA, 'residA.debug')

       ! 2: rhs
       ! rhs = kron(A(j:N,j),X) 
       do jj=0, Nj-1
          rhs(jj * T + 1 : jj * T + T, :) = A(j + jj,j) * X
       end do

       ! 3 scale by SV
       lambda(1:Tj) = reshape(SVol(:,j:Ny), (/ Tj /))
       forall (kk=1:Tj) lhs(kk) = lhs(kk) / lambda(kk)
       forall (kk=1:Tj,jj=1:Nx) rhs(kk,jj) = rhs(kk,jj) / lambda(kk)

       ! call savevec(lambda, 'lambda.debug')
       ! call savevec(lhs, 'lhs.debug')
       ! call savemat(rhs, 'rhs.debug')
       ! call savemat(paidraw, 'paidraw.debug')

       ! 4: index into coefficient vector
       ndx = (/ (j-1) * Nx + 1 : j * Nx /)
       call bayesRegressionSlope(thisb, lhs(1:Tj), rhs(1:Tj,:), Nx, Tj, 1.0d0, b0(ndx), V0i(ndx,ndx), VSLstream)

       ! store results
       paidraw(:,j) = thisb

       ! call savevec(thisb, 'thisb.debug')
       ! if (j == 10) stop 11
    end do

    ! call savemat(paidraw, 'paidraw.debug')
    ! stop 11

    ! Yresid = Y - X * paidraw, and store in Y
    ! note: DGEMM does not care about explicitly reshaping beta
    call DGEMM('N','N',T,Ny,Nx,-1.0d0,X,T,paidraw,Nx,1.0d0,Y,T)

    bdraw = reshape(paidraw, (/ Ny * Nx /))

  END SUBROUTINE bayesVARXSVcta

  ! @\newpage\subsection{bayesVARXSVeqf}@
  SUBROUTINE bayesVARXSVeqf(paidraw, Y, N, T, X, K, SVol, A, mu0, invOmega0, VSLstream)
    ! Bayesian VAR with (known) Time-varying Volatility
    !
    ! with given matrix of regressors
    !
    ! triangular setup of CCM, Ainv in unit lower triangular choleski factor
    !
    ! on exit, Y returns residuals Y - X * reshape(bdraw, Nx, Ny)
    !
    ! notice: top rows of companion have transpose(reshape(bdraw,Nx,Ny)) 
    ! Prior V0i is assumed block diagonal (so we can pick marginals by subindexing)

    ! logical, INTENT(IN) :: doout

    INTEGER, INTENT(IN) :: T, K, N
    DOUBLE PRECISION, INTENT(INOUT) :: Y(T,N)
    DOUBLE PRECISION :: Z(T,N)
    DOUBLE PRECISION, INTENT(IN) :: X(T,K), A(N,N)
    DOUBLE PRECISION, INTENT(IN), DIMENSION(N * K) :: mu0
    DOUBLE PRECISION, INTENT(OUT), DIMENSION(N * K) :: paidraw
    DOUBLE PRECISION, INTENT(IN), DIMENSION(N * K, N * K) :: invOmega0
    DOUBLE PRECISION, INTENT(IN), DIMENSION(T,N)  :: SVol

    DOUBLE PRECISION :: q(N * K), invOmega(N * K, N * K),  cholinvOmega(N * K, N * K)
    DOUBLE PRECISION :: zj(T), cj(T,N * K)
    INTEGER :: NK, jK
    INTEGER :: j, kk, ii
    INTEGER :: errcode

    TYPE (vsl_stream_state), INTENT(INOUT) :: VSLstream

    ! init output
    paidraw  = 0.0d0

    NK = N * K

    ! if (doout) then
    !    call savemat(A, 'A.out')
    !    call savemat(Y, 'Y.out')
    !    call savemat(SVol, 'SV.out')
    !    call savemat(X, 'X.out')
    !    forall (j=1:NK) q(j) = invOmega0(j,j)
    !    call savevec(q, 'diaginvOmega0.out')
    !    q = 0
    !    call savevec(mu0, 'mu0.out')
    ! end if

    ! init priors
    invOmega = invOmega0
    call dsymv('u', NK, 1.0d0, invOmega, NK, mu0, 1, 0.0d0, q, 1)

    ! Z = Y * A'
    Z = Y ! need to keep Y for computing residuals later
    call DTRMM('R','L','T','U',T,N,1.0d0,A,N,Z,T)

    do j=1,N

       jK = j * K

       ! zj
       forall (kk=1:T) zj(kk) = Z(kk,j) / SVol(kk,j)

       ! cj
       cj = 0.0d0
       do ii = 1,j-1
          cj(:, ((ii-1) * K + 1) : ii * K) = A(j,ii) * X
       end do
       ii = j
       cj(:, ((ii-1) * K + 1) : ii * K) = X
       forall (kk=1:T,ii=1:jK) cj(kk,ii) = cj(kk,ii) / SVol(kk,j)

       ! update q
       call dgemv('t', T, jK, 1.0d0, cj, T, zj, 1, 1.0d0, q, 1)

       ! update invOmega
       ! note: not exploiting any zeros in cj; doing so messes up contiguous memory ...
       ! ... main performance improvement comes from exploting cj-zeros in q update anyway
       call dsyrk('u', 't', NK, T, 1.0d0, cj, T, 1.0d0, invOmega, NK)


    end do

    ! choleski of invOmega
    ! cholinvOmega    = chol(invOmega);
    cholinvOmega = invOmega 
    call DPOTRF('u', NK, cholinvOmega, NK, errcode)
    if (errcode .ne. 0) then
       print *, 'DPOTRF error [eqf]', errcode
    end if

    ! call savemat(invOmega, 'cholinvOmega.debug')

    ! draw standard normals
    errcode = vdrnggaussian(VSLmethodGaussian, VSLstream, NK, paidraw, 0.0d0, 1.0d0)
    ! call savevec(paidraw, 'zdraws.debug')

    ! paidraw = cholinvOmega \ (cholinvOmega' \ q + zdraws);
    call dtrsv('u', 't', 'n', NK, cholinvOmega, NK, q, 1)
    paidraw = q + paidraw
    call dtrsv('u', 'n', 'n', NK, cholinvOmega, NK, paidraw, 1)

    ! call savevec(paidraw, 'paidraw.debug')

    call DGEMM('N','N',T,N,K,-1.0d0,X,T,paidraw,K,1.0d0,Y,T)


  END SUBROUTINE bayesVARXSVeqf

  ! @\newpage\subsection{bayesVARXSVeqf}@
  SUBROUTINE bayesVARXSVeqf0(paidraw, q, invOmega, Y, N, T, X, K, SVol, A, mu0, invOmega0, VSLstream)
    ! Bayesian VAR with (known) Time-varying Volatility
    !
    ! with given matrix of regressors
    !
    ! triangular setup of CCM, Ainv in unit lower triangular choleski factor
    !
    ! on exit, Y returns residuals Y - X * reshape(bdraw, Nx, Ny)
    !
    ! notice: top rows of companion have transpose(reshape(bdraw,Nx,Ny)) 
    ! Prior V0i is assumed block diagonal (so we can pick marginals by subindexing)

    INTEGER, INTENT(IN) :: T, K, N
    DOUBLE PRECISION, INTENT(INOUT) :: Y(T,N)
    DOUBLE PRECISION, INTENT(IN) :: X(T,K), A(N,N)
    DOUBLE PRECISION, INTENT(IN), DIMENSION(N * K) :: mu0
    DOUBLE PRECISION, INTENT(OUT), DIMENSION(N * K) :: paidraw
    DOUBLE PRECISION, INTENT(IN), DIMENSION(N * K, N * K) :: invOmega0
    DOUBLE PRECISION, INTENT(IN), DIMENSION(T,N)  :: SVol

    DOUBLE PRECISION, INTENT(OUT) :: q(N * K), invOmega(N * K, N * K) 
    DOUBLE PRECISION :: zj(T), cj(T,N * K)
    ! DOUBLE PRECISION, ALLOCATABLE, DIMENSION(:,:) :: QQ
    INTEGER :: NK
    INTEGER :: j, kk, ii
    INTEGER :: errcode

    TYPE (vsl_stream_state), INTENT(INOUT) :: VSLstream

    ! init output
    paidraw  = 0.0d0

    NK = N * K

    invOmega = 0.0d0
    q        = 0.0d0
    ! init priors
    invOmega = invOmega0
    call dsymv('u', NK, 1.0d0, invOmega, NK, mu0, 1, 0.0d0, q, 1)
    ! call savevec(q, 'q00.debug')

    ! Z = Y * A'
    call DTRMM('R','L','T','U',T,N,1.0d0,A,N,Y,T)

    ! call savemat(Y, 'Z.debug')

    do j=1, N

       ! cj
       cj = 0.0d0
       do ii = 1,N
          cj(:, ((ii-1) * K + 1) : ii * K) = A(j,ii) * X
       end do
       forall (kk=1:T,ii=1:NK) cj(kk,ii) = cj(kk,ii) / SVol(kk,j)

       ! zj
       forall (kk=1:T) zj(kk) = Y(kk,j) / SVol(kk,j)

       ! update q
       call dgemv('t', T, NK, 1.0d0, cj, T, zj, 1, 1.0d0, q, 1)

       ! update invOmega
       call dsyrk('u', 't', NK, T, 1.0d0, cj, T, 1.0d0, invOmega, NK)

    end do


    ! choleski of invOmega
    ! cholinvOmega    = chol(invOmega);
    call DPOTRF('u', NK, invOmega, NK, errcode)
    if (errcode .ne. 0) then
       print *, 'DPOTRF error [eqf0]', errcode
    end if

    ! paidraw = cholinvOmega \ (cholinvOmega' \ q + zdraws);
    call dtrsv('u', 't', 'n', NK, invOmega, NK, q, 1)

    ! draw standard normals
    errcode = vdrnggaussian(VSLmethodGaussian, VSLstream, NK, paidraw, 0.0d0, 1.0d0)
    ! call savevec(paidraw, 'zdraws.debug')
    paidraw = q + paidraw
    call dtrsv('u', 'n', 'n', NK, invOmega, NK, paidraw, 1)

  END SUBROUTINE bayesVARXSVeqf0

  ! @\newpage\subsection{VARmaxroot}@
  SUBROUTINE VARmaxroot(maxlambda, beta, Ny, p)

    ! assumes beta contains no slope for constant

    INTENT(IN) :: beta, Ny, p
    INTENT(OUT) :: maxlambda

    INTEGER :: Ny, p, Nx, j
    DOUBLE PRECISION  :: kompanion(Ny * p, Ny * p), beta(Ny * p, Ny), maxlambda


    ! construct companion form
    Nx = Ny * p
    kompanion = 0.0d0
    FORALL (j = 1 : Ny * (p - 1))
       kompanion(j+Ny,j) = 1.0d0
    END FORALL

    kompanion(1:Ny,:) = transpose(beta(1:Nx,:))

    ! compute largest root


    maxlambda = maxroot(kompanion, Nx)

  END SUBROUTINE VARmaxroot

  ! @\newpage\subsection{maxrootVAR}@
  FUNCTION maxrootVAR(beta, Ny, p) RESULT(maxlambda)

    ! assumes beta contains no slope for constant

    INTENT(IN) :: beta, Ny, p

    INTEGER :: Ny, p, Nx, j
    DOUBLE PRECISION  :: kompanion(Ny * p, Ny * p), beta(Ny * p, Ny), maxlambda


    ! construct companion form
    Nx = Ny * p
    kompanion = 0.0d0
    FORALL (j = 1 : Ny * (p - 1))
       kompanion(j+Ny,j) = 1.0d0
    END FORALL

    kompanion(1:Ny,:) = transpose(beta(1:Nx,:))

    ! compute largest root


    maxlambda = maxroot(kompanion, Nx)

  END FUNCTION maxrootVAR

  ! @\newpage\subsection{ARmaxroot}@
  SUBROUTINE ARmaxroot(maxlambda, beta, p)

    ! assumes beta contains no slope for constant

    INTENT(IN) :: beta, p
    INTENT(OUT) :: maxlambda

    INTEGER :: p, j
    DOUBLE PRECISION  :: kompanion(p, p), beta(p), maxlambda


    ! construct companion form
    kompanion = 0.0d0
    FORALL (j = 1 : (p - 1))
       kompanion(1+j,j) = 1.0d0
    END FORALL

    kompanion(1,:) = beta

    ! compute largest root


    maxlambda = maxroot(kompanion, p)

  END SUBROUTINE ARmaxroot

  ! @\newpage\subsection{simPriorMaxroot}@
  SUBROUTINE simPriorMaxroot(maxlambdas, Ndraws, f0, sqrtVf0, Ny, p, VSLstream)

    ! simulates max root of VAR(p), *without* rejection sampling for stationarity
    INTENT(IN) :: f0, sqrtVf0, Ny, p, Ndraws
    INTENT(OUT) :: maxlambdas
    INTENT(INOUT) :: VSLstream

    INTEGER :: Ny, p, Ndraws, Nx, errcode, j, Nf
    DOUBLE PRECISION  :: maxlambdas(Ndraws), kompanion(Ny * p, Ny * p), f(Ny * Ny * p,Ndraws), f0(Ny * Ny * p), sqrtVf0(Ny * Ny * p, Ny * Ny * p)
    type (vsl_stream_state) :: VSLstream


    Nf = Ny * Ny * p

    ! construct companion form
    Nx = Ny * p
    kompanion = 0.0d0
    FORALL (j = 1 : Ny * (p - 1))
       kompanion(j+Ny,j) = 1.0d0
    END FORALL

    errcode = vdrnggaussian(VSLmethodGaussian, VSLstream, Ndraws * Nf, f, 0.0d0, 1.0d0)

    DO j=1,Ndraws

       CALL DTRMV('U', 'T', 'N', Nf, sqrtVf0, Nf, f(:,j), 1)
       f(:,j) = f(:,j) + f0

       kompanion(1:Ny,:) = transpose(reshape(f(:,j), (/ Ny * p, Ny /)))

       maxlambdas(j) = maxroot(kompanion, Nx)

    END DO


  END SUBROUTINE simPriorMaxroot


  ! @\newpage\subsection{NormalGammaDraw (single draw)}@
  SUBROUTINE normalgammadraw(Nbeta, beta, sigma, Ebeta, invVbeta, ssr, dof, VSLstream, ischol)

    ! draw parameters beta and invsigma2 from normal-gamma
    ! sigma is 1 / (sqrt(Gamma(ssr/2, dof/2))
    ! beta | sigma is N(Ebeta, (invVbeta)^(-1) * sigma^2)

    ! as usual, invVbeta is supposed to be stored in right-upper format

    INTENT(IN)    :: Nbeta, Ebeta, invVbeta, ssr, dof
    INTENT(OUT)   :: beta, sigma
    INTENT(INOUT) :: VSLstream
    LOGICAL, INTENT(IN), OPTIONAL :: ischol

    INTEGER :: Nbeta
    INTEGER :: dof ! in principle: could also be REAL, but keeping with rest of code, assume integer valued Nobs
    DOUBLE PRECISION :: Ebeta(Nbeta), invVbeta(Nbeta,Nbeta), cholinvVbeta(Nbeta,Nbeta)
    DOUBLE PRECISION :: beta(Nbeta), sigma(1)
    DOUBLE PRECISION :: ssr

    logical :: dochol

    INTEGER :: errcode

    type (vsl_stream_state) :: VSLstream

    IF (PRESENT(ischol)) THEN
       dochol = .NOT. ischol
    ELSE
       dochol = .true.
    END IF

    ! draw invsigma2 from gamma
    errcode = vdrnggamma(VSL_RNG_METHOD_GAMMA_GNORM_ACCURATE, VSLstream, 1, sigma, dble(dof - 1) * 0.5d0, 0.0d0, 2.0d0 / ssr)
    ! Notes:
    ! - ifort uses inverse of "beta" as used in wiki notation
    ! - "alpha" corresponds to (dof-1) / 2
    if (errcode /= 0) then
       write(*,*) 'vdrnggamma error: ', errcode, ' [NORMALGAMMADRAWS]'
       stop 1
    end if

    ! convert gamma-draws into sigma 
    sigma = 1.0d0 / sqrt(sigma) 

    ! draw standard-normals for beta
    errcode = vdrnggaussian(VSLmethodGaussian, VSLstream, Nbeta, beta, 0.0d0, 1.0d0)
    ! - scale beta by inv(chol(invVbeta))
    ! - choleski of invVbet
    cholinvVbeta = invVbeta
    if (dochol) then
       call dpotrf('u', Nbeta, cholinvVbeta, Nbeta, errcode)
       if (errcode /= 0) then
          write(*,*) 'CHOLESKI ERROR:', errcode, ' [NormalGammaDraws]'
          stop 1
       end if
    end if
    ! call savevec(beta,'zdraw.debug')
    ! - solve for beta: cholinvVbeta * beta = z
    call DTRSV('U','N','N',Nbeta,cholinvVbeta,Nbeta,beta,1) ! Note: no transpose since using right-choleski factor of invVbeta
    ! call savemat(cholinvVbeta,'cholinvVbeta.debug')
    ! call savevec(beta,'beta.debug')
    ! stop 12
    ! add mean and scale by sigma
    beta = Ebeta + sigma * beta

  END SUBROUTINE normalgammadraw

  ! @\newpage\subsection{NormalGammaDraws -- vector draw}@
  SUBROUTINE normalgammadraws(Nbeta, Ndraw, beta, sigma, Ebeta, invVbeta, ssr, dof, VSLstream, ischol)

    ! Ndraws from normalgamma; with Ndraws different parameters (except dof)

    ! draw parameters beta and invsigma2 from normal-gamma
    ! sigma is 1 / (sqrt(Gamma(ssr/2, dof/2))
    ! beta | sigma is N(Ebeta, (invVbeta)^(-1) * sigma^2)

    ! as usual, invVbeta is supposed to be stored in right-upper format

    INTENT(IN)    :: Nbeta, Ndraw, Ebeta, invVbeta, ssr, dof
    INTENT(OUT)   :: beta, sigma
    INTENT(INOUT) :: VSLstream
    LOGICAL, INTENT(IN), OPTIONAL :: ischol

    INTEGER :: Nbeta, Ndraw
    INTEGER :: dof ! in principle: could also be REAL, but keeping with rest of code, assume integer valued Nobs
    DOUBLE PRECISION :: Ebeta(Nbeta,Ndraw), invVbeta(Nbeta,Nbeta,Ndraw), cholinvVbeta(Nbeta,Nbeta)
    DOUBLE PRECISION :: beta(Nbeta,Ndraw), sigma(Ndraw)
    DOUBLE PRECISION :: ssr(Ndraw)

    logical :: dochol

    INTEGER :: n, errcode

    type (vsl_stream_state) :: VSLstream

    IF (PRESENT(ischol)) THEN
       dochol = .NOT. ischol
    ELSE
       dochol = .true.
    END IF

    ! draw invsigma2 from gamma -- exploiting scalability property
    errcode = vdrnggamma(VSL_RNG_METHOD_GAMMA_GNORM_ACCURATE, VSLstream, Ndraw, sigma, dble(dof - 1) * 0.5d0, 0.0d0, 1.0d0)
    sigma = sigma * 2.0d0 / ssr

    ! Notes:
    ! - ifort uses inverse of "beta" as used in wiki notation (i.e. "theta" in wikipedia)
    ! - "alpha" corresponds to (dof-1) / 2
    if (errcode /= 0) then
       write(*,*) 'vdrnggamma error: ', errcode, ' [NORMALGAMMADRAWS]'
       stop 1
    end if

    ! convert gamma-draws into sigma 
    sigma = 1.0d0 / sqrt(sigma) 

    ! draw beta
    errcode = vdrnggaussian(VSLmethodGaussian, VSLstream, Nbeta * Ndraw, beta, 0.0d0, 1.0d0)

    !$OMP PARALLEL DO SHARED(invVbeta,Ndraw,Nbeta,dochol,beta) PRIVATE(cholinvVbeta, errcode) DEFAULT(NONE) SCHEDULE(STATIC)
    do n=1,Ndraw
       ! scale beta by inv(chol(invVbeta))
       ! - choleski of invVbet
       cholinvVbeta = invVbeta(:,:,n)
       if (dochol) then
          call dpotrf('u', Nbeta, cholinvVbeta, Nbeta, errcode)
          if (errcode /= 0) then
             write(*,*) 'CHOLESKI ERROR:', errcode, ' [NormalGammaDraws]'
             stop 1
          end if
       end if

       ! - solve for beta: cholinvVbeta * beta = z
       call DTRSV('U','N','N',Nbeta,cholinvVbeta,Nbeta,beta(:,n),1) ! Note: no transpose

    end do
    !$OMP END PARALLEL DO 

    ! add mean and scale by sigma
    forall (n=1:Ndraw) beta(:,n) = Ebeta(:,n) + sigma(n) * beta(:,n)     

  END SUBROUTINE normalgammadraws

  ! @\newpage\subsection{NormalGammaDrawsUnivariate}@
  SUBROUTINE normalgammadrawsunivariate(Ndraw, beta, sigma, Ebeta, invVbeta, ssr, dof, VSLstream, ischol)

    ! Ndraws from normalgamma; with Ndraws different parameters (except dof)

    ! draw parameters beta and invsigma2 from normal-gamma
    ! sigma is 1 / (sqrt(Gamma(ssr/2, dof/2))
    ! beta | sigma is N(Ebeta, (invVbeta)^(-1) * sigma^2)

    ! as usual, invVbeta is supposed to be stored in right-upper format

    INTENT(IN)    :: Ndraw, Ebeta, invVbeta, ssr, dof
    INTENT(OUT)   :: beta, sigma
    INTENT(INOUT) :: VSLstream
    LOGICAL, INTENT(IN), OPTIONAL :: ischol

    INTEGER :: Ndraw
    INTEGER :: dof ! in principle: could also be REAL, but keeping with rest of code, assume integer valued Nobs
    DOUBLE PRECISION :: Ebeta(Ndraw), invVbeta(Ndraw), sqrtVbeta(Ndraw)
    DOUBLE PRECISION :: beta(Ndraw), sigma(Ndraw)
    DOUBLE PRECISION :: ssr(Ndraw)

    logical :: dochol

    INTEGER :: n, errcode

    type (vsl_stream_state) :: VSLstream

    IF (PRESENT(ischol)) THEN
       dochol = .NOT. ischol
    ELSE
       dochol = .true.
    END IF

    ! draw invsigma2 from gamma -- exploiting scalability property
    errcode = vdrnggamma(VSL_RNG_METHOD_GAMMA_GNORM_ACCURATE, VSLstream, Ndraw, sigma, dble(dof - 1) * 0.5d0, 0.0d0, 1.0d0)
    sigma = sigma * 2.0d0 / ssr

    ! Notes:
    ! - ifort uses inverse of "beta" as used in wiki notation (i.e. "theta" in wikipedia)
    ! - "alpha" corresponds to (dof-1) / 2
    if (errcode /= 0) then
       write(*,*) 'vdrnggamma error: ', errcode, ' [NORMALGAMMADRAWS]'
       stop 1
    end if

    ! convert gamma-draws into sigma 
    sigma = 1.0d0 / sqrt(sigma) 

    ! draw beta
    sqrtVbeta = 1.0d0 / invVbeta
    if (doChol) then
       sqrtVbeta = sqrt(sqrtVbeta)
    end if
    errcode = vdrnggaussian(VSLmethodGaussian, VSLstream, Ndraw, beta, 0.0d0, 1.0d0)
    ! add mean and scale by sigma
    forall (n=1:Ndraw) beta(n) = Ebeta(n) + sigma(n) * sqrtVbeta(N) * beta(n)     

  END SUBROUTINE normalgammadrawsunivariate

  ! @\newpage\subsection{NormalGammaUpdate}@
  SUBROUTINE normalgammaupdate(T, Nx, y, X, b, iV, ssr, dof, updatedof)

    ! update parameters of normal-gamma given new regression data yX
    ! as usual, invVbeta is supposed to be stored in right-upper format
    ! fomulas are taken from Koop, Ch3 Ex3; robust to X'X being singular( and thus suited for sequential application)

    INTENT(IN)    :: T, Nx, y, X
    INTENT(INOUT) :: b, iV, ssr, dof
    LOGICAL, INTENT(IN), OPTIONAL :: updatedof

    INTEGER :: Nx, T
    INTEGER :: dof 
    DOUBLE PRECISION, DIMENSION(Nx) :: b, b0, bdev, XY
    DOUBLE PRECISION, DIMENSION(Nx,Nx) :: iV, iV0, icholV, XX
    DOUBLE PRECISION :: ssr
    DOUBLE PRECISION :: y(T), X(T,Nx), resid(T)

    INTEGER :: status

    IF (PRESENT(updatedof)) THEN
       IF (updatedof) dof = dof + T
    END IF

    ! ! if needed: factorize iV
    ! ! - choleski of iV
    ! icholV = iV
    ! if (dochol) then
    !    call dpotrf('u', Nx, icholV, Nx, status)
    !    if (status /= 0) then
    !       write(*,*) 'CHOLESKI ERROR:', status, ' [NormalGammaUpdate]'
    !       stop 1
    !    end if
    ! end if

    ! store priors
    b0  = b
    iV0 = iV

    ! XX
    XX = 0.0d0 
    call DSYRK('U','T',Nx,T,1.0d0,X,T,0.0d0,XX,Nx)
    ! XY 
    call DGEMV('T', T, Nx, 1.0d0, X, T, Y, 1, 0.0d0, XY, 1)

    ! UPDATE b -- PART 1: b = iV0 * b0 + Xy
    b  = Xy
    call DSYMV('U', Nx, 1.0d0, iV0, Nx, b0, 1, 1.0d0, b, 1)
    ! UPDATE iV
    iV = iV0 + XX
    ! UPDATE b -- PART 2: b = iV * b
    ! - factorize iV
    icholV = iV
    call DPOTRF('U', Nx, icholV, Nx, status)
    if (status /= 0) then
       write(*,*) 'DPOTRF ERROR:', status, '[NormalGammaUpdate iV]'
       stop 1
    end if
    call DPOTRS('U', Nx, 1, icholV, Nx, b, Nx, status)
    if (status /= 0) then
       write(*,*) 'DPOTRS error: ', status, '[NormalGammaUpdate iV]'
       stop 1
    end if

    ! call savevec(y,'gibbsy.debug')
    ! call savemat(X,'gibbsX.debug')
    ! call savevec(b0, 'gibbsb0.debug')
    ! call savemat(iV0, 'gibbsiV0.debug')
    ! call savevec(b, 'gibbsb.debug')
    ! call savemat(iV, 'gibbsiV.debug')
    ! call savevec((/ ssr /), 'gibbsssr0.debug')
    ! stop 12

    !  resid = y - X * b (residual at posterior mean)
    resid = y
    call dgemv('N', T, Nx, -1.0d0, X, T, b, 1, 1.0d0, resid, 1)

    ssr = ssr + sum(resid ** 2)
    ! call savevec(resid, 'gibbsresid.debug')
    ! call savevec((/ ssr /), 'gibbsssrStep1.debug')


    ! final piece: (b-b0)' * iV0 * (b-b0)
    bdev = b - b0
    ! factorize iV0
    icholV = iV0
    call DPOTRF('U', Nx, icholV, Nx, status)
    if (status /= 0) then
       write(*,*) 'DPOTRF ERROR:', status, '[NormalGammaUpdate iV]'
       stop 1
    end if
    call DTRMV('u','n','n',Nx,icholV,Nx,bdev,1)

    ssr = ssr + sum(bdev ** 2)

    ! call savevec((/ ssr /), 'gibbsssr.debug')

  END SUBROUTINE normalgammaupdate



END MODULE gibbsbox


