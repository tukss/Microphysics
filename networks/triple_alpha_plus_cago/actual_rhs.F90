module actual_rhs_module

  use network
  use burn_type_module
  use screen_module
  use rates_module
  use dydt_module
  use rate_type_module

  use amrex_fort_module, only : rt => amrex_real
  implicit none

  public

contains

  subroutine actual_rhs_init()

    implicit none

    !$gpu

  end subroutine actual_rhs_init


  subroutine get_rates(state, rr)

    !$acc routine seq

    type (burn_t), intent(in) :: state
    type (rate_t), intent(out) :: rr

    real(rt)         :: temp, dens
    real(rt)         :: ymol(nspec)

    real(rt)         :: rates(nrates), dratesdt(nrates)

    !$gpu

    temp = state % T
    dens = state % rho
    ymol = state % xn * aion_inv

    call make_rates(temp, dens, rates, dratesdt)
    call screen(temp, dens, ymol, rates, dratesdt)

    rr % rates(1,:) = rates(:)
    rr % rates(2,:) = dratesdt(:)

    rr % T_eval = temp

  end subroutine get_rates


  subroutine actual_rhs(state, ydot)

    !$acc routine seq

    use temperature_integration_module, only: temperature_rhs

    implicit none

    type (burn_t), intent(in) :: state
    real(rt)         :: ydot(neqs)

    type (rate_t) :: rr

    real(rt)         :: ymol(nspec)
    real(rt)         :: rates(nrates)
    integer :: k

    !$gpu

    ydot = ZERO

    ymol = state % xn * aion_inv

    ! set up the species ODEs for the reaction network
    ! species inputs are in molar fractions but come out in mass fractions

    call get_rates(state, rr)

    rates(:)    = rr % rates(1,:)

    call dydt(ymol, rates, ydot(1:nspec_evolve))

    ! Energy generation rate

    call ener_gener_rate(ydot(1:nspec_evolve), ydot(net_ienuc))

    call temperature_rhs(state, ydot)

  end subroutine actual_rhs



  subroutine actual_jac(state, jac)

    !$acc routine seq

    use burn_type_module, only : neqs, njrows, njcols
    use temperature_integration_module, only: temperature_jac

    implicit none

    type (burn_t), intent(in) :: state
    real(rt)         :: jac(njrows, njcols)

    type (rate_t) :: rr

    real(rt)         :: ymol(nspec)
    real(rt)         :: rates(nrates), dratesdt(nrates)

    integer :: i, j

    !$gpu

    call get_rates(state, rr)

    rates(:)    = rr % rates(1,:)
    dratesdt(:) = rr % rates(2,:)

    ! initialize
    do j = 1, neqs
       jac(:,j) = ZERO
    enddo

    ymol = state % xn * aion_inv

    ! ======================================================================
    ! THESE ARE IN TERMS OF MOLAR FRACTIONS

    ! helium jacobian elements
    jac(ihe4,ihe4)  = - NINE * ymol(ihe4) * ymol(ihe4) * rates(ir3a) &
                              - ONE * ymol(ic12) * rates(ircago)
    jac(ihe4,ic12)  = - ONE * ymol(ihe4) * rates(ircago)

    ! carbon jacobian elements
    jac(ic12,ihe4) =   THREE * ymol(ihe4) * ymol(ihe4) * rates(ir3a) &
                             - ONE * ymol(ic12) * rates(ircago)
    jac(ic12,ic12) = - ONE * ymol(ihe4) * rates(ircago)

    ! oxygen jacobian elements
    jac(io16,ihe4) = ONE * ymol(ic12) * rates(ircago)
    jac(io16,ic12) = ONE * ymol(ihe4) * rates(ircago)

    ! ======================================================================

    ! Add the temperature derivatives: df(y_i) / dT

    call dydt(ymol, dratesdt, jac(1:nspec_evolve,net_itemp))

    ! Energy generation rate Jacobian elements with respect to species

    do j = 1, nspec_evolve
       call ener_gener_rate(jac(1:nspec_evolve,j), jac(net_ienuc,j))
    enddo

    ! Jacobian elements with respect to temperature

    call ener_gener_rate(jac(1:nspec_evolve,net_itemp), jac(net_ienuc,net_itemp))

    call temperature_jac(state, jac)

  end subroutine actual_jac


  subroutine ener_gener_rate(dydt, enuc)

    !$acc routine seq

    use network

    implicit none

    !$gpu

    real(rt)         :: dydt(nspec_evolve), enuc

    enuc = -sum(dydt(:) * aion(1:nspec_evolve) * ebin(1:nspec_evolve))

  end subroutine ener_gener_rate

  subroutine update_unevolved_species(state)

    !$acc routine seq

    implicit none

    type (burn_t)    :: state

    !$gpu

    ! although we nspec_evolve < nspec, we never change the Fe56
    ! abundance, so there is no algebraic relation we need to
    ! enforce here.

  end subroutine update_unevolved_species

end module actual_rhs_module
