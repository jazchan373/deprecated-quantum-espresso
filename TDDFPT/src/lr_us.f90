!
! Copyright (C) 2001-2015 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!---------------------------------------------------------------------------------
MODULE lr_us

CONTAINS
!-----------------------------------------------------------------------------------
SUBROUTINE lr_apply_s(vect, svect)
    !-------------------------------------------------------------------------------
    !   
    ! This subroutine applies the S operator to vect.
    ! IT: This routine is analogous to routine 'sd0psi'.
    !
    ! Created by X.Ge in May. 2013
    ! Modified by Iurii Timrov, Nov. 2013
    !
    USE kinds,              ONLY : dp
    USE io_global,          ONLY : stdout
    USE uspp,               ONLY : okvan, vkb, nkb
    USE wvfct,              ONLY : npwx, npw, nbnd
    USE klist,              ONLY : nks,xk
    USE becmod,             ONLY : becp, calbec
    USE noncollin_module,   ONLY : npol
    USE lr_variables,       ONLY : eels, lr_verbosity
    USE qpoint,             ONLY : nksq
    
    IMPLICIT NONE
    !
    COMPLEX(dp), INTENT(IN)  ::  vect(npwx*npol,nbnd,nksq)
    COMPLEX(dp), INTENT(OUT) :: svect(npwx*npol,nbnd,nksq)
    !
    ! Local variables
    !
    INTEGER :: ibnd, ik
    !
    IF (lr_verbosity > 5) THEN
       WRITE(stdout,'("<lr_apply_s>")')
    ENDIF
    !
    IF ( nkb==0 .or. (.not.okvan) ) THEN
       !
       svect(:,:,:) = vect(:,:,:) 
       RETURN
       !
    ENDIF
    !
    CALL start_clock('lr_apply_s')
    !
    svect = (0.0d0, 0.0d0)
    !
    IF (eels) THEN
       CALL lr_apply_s_eels()
    ELSE
       CALL lr_apply_s_optical()
    ENDIF
    !
    CALL stop_clock('lr_apply_s')
    !
    RETURN
    !
CONTAINS

SUBROUTINE lr_apply_s_optical()
    !
    ! Optical case
    !
    USE control_flags,    ONLY : gamma_only
    USE realus,           ONLY : real_space, invfft_orbital_gamma,             &
                               & fwfft_orbital_gamma, calbec_rs_gamma,       &
                               & v_loc_psir, igk_k,npw_k, real_space_debug, &
                               & s_psir_gamma
    !
    IMPLICIT NONE   
    !
    IF (gamma_only) THEN
       !
       IF (real_space_debug>4) THEN 
          !
          ! Real space implementation
          ! 
          DO ibnd = 1,nbnd,2
             CALL invfft_orbital_gamma(vect(:,:,1),ibnd,nbnd)
             CALL calbec_rs_gamma(ibnd,nbnd,becp%r)
             CALL s_psir_gamma(ibnd,nbnd)
             CALL fwfft_orbital_gamma(svect(:,:,1),ibnd,nbnd)
          ENDDO
          !
       ELSE
          !
          ! Not real space 
          !
          CALL calbec(npw,vkb,vect(:,:,1),becp)
          CALL s_psi(npwx,npw,nbnd,vect(1,1,1),svect(1,1,1))
          !
       ENDIF
       !
    ELSE 
       !
       ! Generalised K points algorithm
       !
       DO ik = 1, nksq
          !
          CALL init_us_2(npw_k(ik),igk_k(1,ik),xk(1,ik),vkb)
          CALL calbec(npw_k(ik),vkb,vect(:,:,ik),becp)
          CALL s_psi(npwx,npw_k(ik),nbnd,vect(1,1,ik),svect(1,1,ik))
          !
       ENDDO
       !
    ENDIF
    !
    RETURN
    !
END SUBROUTINE lr_apply_s_optical

SUBROUTINE lr_apply_s_eels()
   !
   ! EELS
   ! Written by I. Timrov (2013)
   !
   USE lr_variables,    ONLY : lr_periodic
   USE qpoint,          ONLY : nksq, npwq, igkq, ikks, ikqs
   USE gvect,           ONLY : ngm, g
   USE wvfct,           ONLY : g2kin, ecutwfc
   USE cell_base,       ONLY : tpiba2
   USE control_ph,      ONLY : nbnd_occ

   IMPLICIT NONE
   !
   INTEGER :: ikk, ikq
   !
   DO ik = 1, nksq
      !
      IF (lr_periodic) THEN
          ikk = ik
          ikq = ik
      ELSE
          ikk = ikks(ik)
          ikq = ikqs(ik)
      ENDIF
      !
      ! Determination of npwq, igkq; g2kin is used here as a workspace.
      !
      CALL gk_sort( xk(1,ikq), ngm, g, ( ecutwfc / tpiba2 ), npwq, igkq, g2kin )
      !
      ! Calculate beta-functions vkb at point k+q
      !
      CALL init_us_2(npwq, igkq, xk(1,ikq), vkb)
      !
      ! Calculate the product of beta-functions vkb with vect:
      ! becp%k = <vkb|vect>
      !
      CALL calbec(npwq, vkb, vect(:,:,ik), becp, nbnd_occ(ikk))
      !
      ! Apply the S operator
      !
      CALL s_psi(npwx, npwq, nbnd_occ(ikk), vect(:,:,ik), svect(:,:,ik))
      !
   ENDDO
   !
   RETURN
   !
END SUBROUTINE lr_apply_s_eels

END SUBROUTINE lr_apply_s

!------------------------------------------------------------------------
FUNCTION lr_dot_us(vect1,vect2)
   !---------------------------------------------------------------------
   !
   ! This subroutine calculates < vect1 | S | vect2 >
   !
   ! Written by X.Ge in May. 2013
   ! Modified by Iurii Timrov, Nov. 2013
   !
   USE kinds,              ONLY : dp
   USE wvfct,              ONLY : npwx, npw, nbnd
   USE klist,              ONLY : nks
   USE noncollin_module,   ONLY : npol
   USE qpoint,             ONLY : nksq

   IMPLICIT NONE
   !
   COMPLEX(kind=dp), EXTERNAL :: lr_dot
   COMPLEX(dp), INTENT(in) :: vect1(npwx*npol,nbnd,nksq), &
                              vect2(npwx*npol,nbnd,nksq)
   COMPLEX(dp), ALLOCATABLE :: svect1(:,:,:)
   COMPLEX(dp) :: lr_dot_us
   !
   CALL start_clock('lr_dot_us')
   !
   ALLOCATE(svect1(npwx*npol,nbnd,nksq))
   !
   CALL lr_apply_s(vect1(1,1,1),svect1(1,1,1))
   !
   lr_dot_us = lr_dot(svect1,vect2)
   ! 
   DEALLOCATE(svect1)
   !
   CALL stop_clock('lr_dot_us')
   !
   RETURN
   !
END FUNCTION lr_dot_us

END MODULE lr_us
