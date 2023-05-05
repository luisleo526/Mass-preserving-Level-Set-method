subroutine interface_solver()
use all
implicit none

if(p%glb%method==1)then
    call classical_ls()
else if (p%glb%method==2)then
    call mpls()
else if (p%glb%method==3)then
    call clsvof()
endif

end subroutine 

subroutine classical_ls()
use all
implicit none

!call level_set_symplectic_solver 
call level_set_rk3_solver
if(mod(p%glb%iter,20).eq.0)call level_set_rk3_redis(1)

end subroutine

subroutine mpls()
use all
implicit none
integer :: id,i,j,k,mid
real(8) :: tmp1, tmp2
logical :: reconstruct

!call level_set_symplectic_solver 

do mid = 1, 2

    tmp1 = p%glb%imass
    tmp2 = p%glb%ivol

    p%glb%imass = p%of(0)%loc%marker(mid)%imass
    p%glb%ivol = p%of(0)%loc%marker(mid)%ivol

    !$omp parallel do private(i,j,k)
    do id = 0, p%glb%threads-1

        !$omp parallel do num_threads(p%glb%nthreads) collapse(3) private(i,j,k)
        do k = p%of(id)%loc%ks-p%glb%ghc, p%of(id)%loc%ke+p%glb%ghc
        do j = p%of(id)%loc%js-p%glb%ghc, p%of(id)%loc%je+p%glb%ghc
        do i = p%of(id)%loc%is-p%glb%ghc, p%of(id)%loc%ie+p%glb%ghc
            p%of(id)%loc%phi%now(i,j,k) = p%of(id)%loc%marker(mid)%lsf%now(i,j,k)
        enddo
        enddo
        enddo
        !$omp end parallel do

    enddo
    !$omp end parallel do

    call level_set_rk3_solver
    if(mod(p%glb%iter,20).eq.0)call level_set_rk3_redis(1)
    call mass_preserving_level_set

    !$omp parallel do private(i,j,k)
    do id = 0, p%glb%threads-1

        !$omp parallel do num_threads(p%glb%nthreads) collapse(3) private(i,j,k)
        do k = p%of(id)%loc%ks-p%glb%ghc, p%of(id)%loc%ke+p%glb%ghc
        do j = p%of(id)%loc%js-p%glb%ghc, p%of(id)%loc%je+p%glb%ghc
        do i = p%of(id)%loc%is-p%glb%ghc, p%of(id)%loc%ie+p%glb%ghc
            p%of(id)%loc%marker(mid)%lsf%now(i,j,k) = p%of(id)%loc%phi%now(i,j,k)
        enddo
        enddo
        enddo
        !$omp end parallel do

    enddo
    !$omp end parallel do

    p%glb%imass = tmp1
    p%glb%ivol = tmp2

enddo

reconstruct = .false.
!$omp parallel do private(i,j,k) reduction(.or.:reconstruct)
do id = 0, p%glb%threads-1

    !$omp parallel do num_threads(p%glb%nthreads) collapse(3) private(i,j,k) reduction(.or.:reconstruct)
    do k = p%of(id)%loc%ks-p%glb%ghc, p%of(id)%loc%ke+p%glb%ghc
    do j = p%of(id)%loc%js-p%glb%ghc, p%of(id)%loc%je+p%glb%ghc
    do i = p%of(id)%loc%is-p%glb%ghc, p%of(id)%loc%ie+p%glb%ghc
        reconstruct = reconstruct .or. (p%of(id)%loc%marker(1)%lsf%now(i,j,k)+p%glb%ls_wid) * (p%of(id)%loc%marker(2)%lsf%now(i,j,k)+p%glb%ls_wid) > 0.0d0
        p%of(id)%loc%phi%now(i,j,k) = max( p%of(id)%loc%marker(1)%lsf%now(i,j,k), p%of(id)%loc%marker(2)%lsf%now(i,j,k))
    enddo
    enddo
    enddo
    !$omp end parallel do

    call p%of(id)%bc(0, p%of(id)%loc%phi%now)

enddo
!$omp end parallel do

call pt%phi%sync

if( reconstruct )then
    call level_set_rk3_redis(1)
    call mass_preserving_level_set
endif

end subroutine

subroutine clsvof()
use all
implicit none

call vof_wlic_solver
!call level_set_symplectic_solver 
call level_set_rk3_solver

if(mod(p%glb%iter,20).eq.0)then
    call clsvof_recon
else if(mod(p%glb%iter,10).eq.0)then
    call level_set_rk3_redis(1)
endif

end subroutine