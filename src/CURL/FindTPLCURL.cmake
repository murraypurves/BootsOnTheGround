SET(tribits_name CURL)
SET(headers
    curl/curl.h
    curl/easy.h
    curl/curlbuild.h
)
SET(libs
    curl
    idn
    lber
    ldap
    dl
)
SET(hunter_name CURL)
SET(hunter_args )

botgHuntTPL(
    "${tribits_name}"
    "${headers}"
    "${libs}"
    "${hunter_name}"
    "${hunter_args}"
)