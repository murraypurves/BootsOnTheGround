#cd TPLs; for f in $(ls -1d TPLs/*); do echo "_$(basename $f) $f PT OPTIONAL"; done
SET( SUBPACKAGES_DIRS_CLASSIFICATIONS_OPTREQS
    _GTest            TPLs/GTest            PT OPTIONAL
    _BoostFilesystem  TPLs/Boost/Filesystem PT OPTIONAL
    _HDF5             TPLs/HDF5             PT OPTIONAL
    _Curl             TPLs/Curl             PT OPTIONAL
    _SZip             TPLs/SZip             PT OPTIONAL
    _ZLib             TPLs/ZLib             PT OPTIONAL
    _OpenSSL          TPLs/OpenSSL          PT OPTIONAL
    _GFlags           TPLs/GFlags           PT OPTIONAL
    _Fmt              TPLs/Fmt              PT OPTIONAL
    _Spdlog           TPLs/Spdlog           PT OPTIONAL
    _NLJson           TPLs/NLJson           PT OPTIONAL
)

SET(LIB_REQUIRED_DEP_PACKAGES)
SET(LIB_OPTIONAL_DEP_PACKAGES)
SET(TEST_REQUIRED_DEP_PACKAGES)
SET(TEST_OPTIONAL_DEP_PACKAGES)
SET(LIB_REQUIRED_DEP_TPLS)
SET(LIB_OPTIONAL_DEP_TPLS)
SET(TEST_REQUIRED_DEP_TPLS)
SET(TEST_OPTIONAL_DEP_TPLS)