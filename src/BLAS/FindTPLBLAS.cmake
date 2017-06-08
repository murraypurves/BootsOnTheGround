SET(tribits_name BLAS)

SET(headers
)
SET(libs
    blas
)

IF( "${BOTG_SYSTEM}" STREQUAL "Windows" )
    SET(libs
        blas_win32
    )
ENDIF()

SET(hunter_name "") #empty means hunter will not build
SET(hunter_args )

botgHuntTPL(
    "${tribits_name}"
    "${headers}"
    "${libs}"
    "${hunter_name}"
    "${hunter_args}"
)
