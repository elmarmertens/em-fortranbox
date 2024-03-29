include 'mkl_vsl.f90'
! include 'mkl_vsl.fi'

MODULE vslbox

USE mkl_vsl
USE mkl_vsl_type

IMPLICIT NONE

INTEGER, PARAMETER :: VSLmethodGaussian   = VSL_RNG_METHOD_GAUSSIAN_BOXMULLER ! = 0
INTEGER, PARAMETER :: VSLmethodUniform    = VSL_RNG_METHOD_UNIFORM_STD ! = 0
INTEGER, PARAMETER :: VSLmethodBeta       = VSL_RNG_METHOD_BETA_CJA ! = 0
INTEGER, PARAMETER :: VSLmethodChisquare  = VSL_RNG_METHOD_CHISQUARE_CHI2GAMMA
INTEGER, PARAMETER :: VSLmethodGamma      = VSL_RNG_METHOD_GAMMA_GNORM_ACCURATE

END MODULE vslbox
