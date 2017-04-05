#-------------------------------------------------------------------------------
FUNCTION( botgClearCMakeCache keep_cache )
    #quick return if passed anything CMake TRUE
    IF( DEFINED(keep_cache) AND keep_cache )
        RETURN()
    ENDIF()
    MESSAGE(STATUS "[BootsOnTheGround] clearing CMake cache ... ")

    #otherwise we clear the cache
    FILE(GLOB cmake_generated
        "${CMAKE_BINARY_DIR}/CMakeCache.txt"
        "${CMAKE_BINARY_DIR}/cmake_install.cmake"
        "${CMAKE_BINARY_DIR}/CMakeFiles/*"
    )

    FOREACH(file ${cmake_generated})
      IF (EXISTS "${file}")
         FILE(REMOVE_RECURSE "${file}")
         FILE(REMOVE "${file}")
      ENDIF()
    ENDFOREACH()

ENDFUNCTION()
#-------------------------------------------------------------------------------
MACRO(botgPrintVar regex)
    get_cmake_property(_variableNames VARIABLES)

    foreach (_variableName ${_variableNames})

        if( _variableName MATCHES "^_")
            CONTINUE()
        endif()

        if( NOT "${regex}" STREQUAL "" )
            if( NOT _variableName MATCHES "${regex}" )
                CONTINUE()
            endif()
        endif()

        message(STATUS "[BootsOnTheGround] ${_variableName}=${${_variableName}}")

    endforeach()

ENDMACRO()
#---------------------------------------------------------------------------
FUNCTION( botgHuntTPL tribits_name headers libs hunter_name hunter_args )

    SET(${tribits_name}_FORCE_HUNTER OFF
      CACHE BOOL "Force hunter download of TPL ${tribits_name}.")

    #This is necessary to avoid TriBITs thinking we have found libraries when all we have set is
    #the library names. (First noticed with HDF5 on ORNL's Jupiter Linux cluster)
    SET(${tribits_name}_FORCE_PRE_FIND_PACKAGE ON)

    TRIBITS_TPL_ALLOW_PRE_FIND_PACKAGE( ${tribits_name}  ${tribits_name}_ALLOW_PREFIND)

    MESSAGE( STATUS "[BootsOnTheGround] ${tribits_name}_ALLOW_PREFIND=${${tribits_name}_ALLOW_PREFIND}" )

    IF( ${tribits_name}_ALLOW_PREFIND OR ${tribits_name}_FORCE_HUNTER )

      #vanilla find
      IF( NOT ${tribits_name}_FORCE_HUNTER )
          MESSAGE( STATUS "[BootsOnTheGround] Calling FIND_PACKAGE(${tribits_name} CONFIG) ...")
          FIND_PACKAGE( ${tribits_name} CONFIG QUIET )
          #says it found it but it didn't populate any variables we need
          IF( ${tribits_name}_FOUND )
	      IF( "${${tribits_name}_LIBRARY_DIRS}" STREQUAL "" AND
                  "${${tribits_name}_INCLUDE_DIRS}" STREQUAL "" )
                  SET( ${tribits_name}_FOUND OFF )
              ENDIF()
          ENDIF()
          MESSAGE( STATUS "[BootsOnTheGround] Calling FIND_PACKAGE(${tribits_name} CONFIG) ... ${tribits_name}_FOUND=${${tribits_name}_FOUND}")
      ENDIF()

      #use hunter!
      IF( NOT ${tribits_name}_FOUND AND NOT (hunter_name STREQUAL "") )
        SET( hunter_argx "" )
        IF( hunter_name STREQUAL "" )
            LIST(APPEND hunter_argx ${tribits_name})
        ELSE()
            LIST(APPEND hunter_argx ${hunter_name})
        ENDIF()
        LIST(APPEND hunter_argx ${hunter_args} )

        MESSAGE(STATUS "[BootsOnTheGround] Calling hunter_add_package( ${hunter_argx} )...")

        HUNTER_ADD_PACKAGE( ${hunter_argx} )

        #issue found in: cmake-3.7/Modules/CheckSymbolExists.cmake
        CMAKE_POLICY(PUSH)
        CMAKE_POLICY(SET CMP0054 OLD)
        FIND_PACKAGE( ${hunter_argx} )
        CMAKE_POLICY(POP)

        #no choice but to be successful with hunter
        GLOBAL_SET(${tribits_name}_FOUND TRUE)

        #set global information about where the stuff is, converting names
        #from hunter to tribits.
        FOREACH( type INCLUDE_DIRS LIBRARY_DIRS)
            GLOBAL_SET(${tribits_name}_${type} ${${hunter_name}_${type}})
        ENDFOREACH()

      ENDIF()

      MESSAGE( STATUS "[BootsOnTheGround] PREFIND result of TPL ${tribits_name}_FOUND=${${tribits_name}_FOUND}")

    ENDIF()

    # Third, call TRIBITS_TPL_FIND_INCLUDE_DIRS_AND_LIBRARIES()
    TRIBITS_TPL_FIND_INCLUDE_DIRS_AND_LIBRARIES( ${tribits_name}
      REQUIRED_HEADERS ${headers}
      REQUIRED_LIBS_NAMES ${libs}
    )

    MESSAGE( STATUS "[BootsOnTheGround] FINAL result of TPL ${tribits_name}_FOUND=${${tribits_name}_FOUND}")

ENDFUNCTION()
#-------------------------------------------------------------------------------
# Process TriBITS and set .
#
MACRO( botgProcessTribits TriBITS_dir )
    MESSAGE( STATUS "[BootsOnTheGround] initializing TriBITS ..." )

    # Why TriBITS do you blow away my MODULE_PATH?
    SET(save_path ${CMAKE_MODULE_PATH})

    # Enable TriBITS.
    SET(${PROJECT_NAME}_TRIBITS_DIR ${TriBITS_dir}
      CACHE PATH "TriBITS base directory (default assumes in TriBITS source tree).")
    INCLUDE( ${TriBITS_dir}/TriBITS.cmake )

    # Recover with appended path.
    SET(CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH};${save_path}")

ENDMACRO()
#-------------------------------------------------------------------------------
# Prevent in-source builds.
#
FUNCTION(botgPreventInSourceBuilds)

  GET_FILENAME_COMPONENT(srcdir "${CMAKE_SOURCE_DIR}" REALPATH)
  GET_FILENAME_COMPONENT(bindir "${CMAKE_BINARY_DIR}" REALPATH)

  IF("${srcdir}" STREQUAL "${bindir}")
    botgClearCMakeCache( FALSE )
    MESSAGE(FATAL_ERROR "[BootsOnTheGround] in-source builds are not allowed!")
  ENDIF()

ENDFUNCTION()
#-------------------------------------------------------------------------------
# Return the compiler variable as "SUITE/COMPILER".
#
FUNCTION( botgGetCompilerName lang compiler )

    SET( compiler_ "${CMAKE_${lang}_COMPILER}")
    GET_FILENAME_COMPONENT(compiler_ "${compiler_}" NAME_WE)
    SET( compiler_suite_ "${CMAKE_${lang}_COMPILER_ID}")
    IF( compiler_suite_ STREQUAL "AppleClang" )
        SET(compiler_suite_ "Clang" )
    ENDIF()
    SET( ${compiler} "${compiler_suite_}/${compiler_}" PARENT_SCOPE )

ENDFUNCTION()
#-------------------------------------------------------------------------------
# Set the global compiler name BOTG_${lang}_COMPILER="SUITE/COMPILER".
#
MACRO( botgProcessCompiler lang )

    botgGetCompilerName( ${lang} compiler )
    GLOBAL_SET( BOTG_${lang}_COMPILER ${compiler} )

    MESSAGE( STATUS "[BootsOnTheGround] set lang=${lang} compiler global BOTG_${lang}_COMPILER=${BOTG_${lang}_COMPILER}")
ENDMACRO()
#-------------------------------------------------------------------------------
# Check if given Fortran source compiles and links into an executable
#
# botgTryCompileFortran(<code> <var> [FAIL_REGEX <fail-regex>])
#  <code>       - source code to try to compile, must define 'program'
#  <var>        - variable to store whether the source code compiled
#  <fail-regex> - fail if test output matches this regex
#
# The following variables may be set before calling this macro to
# modify the way the check is run:
#
#  CMAKE_REQUIRED_FLAGS = string of compile command line flags
#  CMAKE_REQUIRED_DEFINITIONS = list of macros to define (-DFOO=bar)
#  CMAKE_REQUIRED_INCLUDES = list of include directories
#  CMAKE_REQUIRED_LIBRARIES = list of libraries to link
#
# William A. Wieselquist pulled into BOTG from the SCALE repository.
# It had these commits.
#
MACRO( botgTryCompileFortran source var )
    SET(_fail_regex)
    SET(_key)

    # Collect arguments.
    FOREACH(arg ${ARGN})
        IF("${arg}" MATCHES "^(FAIL_REGEX)$")
            SET(_key "${arg}")
        ELSEIF(_key)
            LIST(APPEND _${_key} "${arg}")
        ELSE()
            MESSAGE(FATAL_ERROR "[BootsOnTheGround] Unknown argument:\n  ${arg}\n")
        ENDIF()
    ENDFOREACH()

    # Set definitions.
    SET(defs "-D${var} ${CMAKE_REQUIRED_FLAGS}")

    # Set libraries.
    IF(CMAKE_REQUIRED_LIBRARIES)
        SET(libs "-DLINK_LIBRARIES:STRING=${CMAKE_REQUIRED_LIBRARIES}")
    ELSE()
        SET(libs)
    ENDIF()

    # Set includes.
    IF(CMAKE_REQUIRED_INCLUDES)
        SET(includes "-DINCLUDE_DIRECTORIES:STRING=${CMAKE_REQUIRED_INCLUDES}")
    ELSE()
        SET(includes)
    ENDIF()

    # Set temporary file.
    SET(tempfile "${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeTmp/botgTryCompileFortran.f90")
    FILE(WRITE "${tempfile}" "${source}\n")

    # Try to compile.
    TRY_COMPILE( ${var} "${CMAKE_BINARY_DIR}" "${tempfile}"
      COMPILE_DEFINITIONS
        "${CMAKE_REQUIRED_DEFINITIONS}"
      CMAKE_FLAGS
        "-DCOMPILE_DEFINITIONS:STRING=${defs}"
        "${libs}"
        "${includes}"
      OUTPUT_VARIABLE output
    )

    # Set the output.
    FOREACH(_regex ${_fail_regex})
        IF("${output}" MATCHES "${_regex}")
            SET(${var} 0)
        ENDIF()
    ENDFOREACH()
ENDMACRO()
#-------------------------------------------------------------------------------
MACRO( botgCheckFlag_Fortran flag result)
   SET(save_defs "${CMAKE_REQUIRED_DEFINITIONS}")
   MESSAGE(STATUS "Performing Test ${flag}")
   SET(CMAKE_REQUIRED_DEFINITIONS "${flag}")
   botgTryCompileFortran("
     program main
          print *, \"Hello World\"
     end program main
     " ${result}
     # Some compilers do not fail with a bad flag
     FAIL_REGEX "unrecognized .*option"                     # GNU
     FAIL_REGEX "ignoring unknown option"                   # MSVC
     FAIL_REGEX "warning D9002"                             # MSVC, any lang
     FAIL_REGEX "[Uu]nknown option"                         # HP
     FAIL_REGEX "[Ww]arning: [Oo]ption"                     # SunPro
     FAIL_REGEX "command option .* is not recognized"       # XL
     )
   IF( ${result} )
     MESSAGE(STATUS "Performing Test ${flag} - Success")
   ELSE()
     MESSAGE(STATUS "Performing Test ${flag} - Fail")
   ENDIF()
   SET (CMAKE_REQUIRED_DEFINITIONS "${save_defs}")
ENDMACRO()
#-------------------------------------------------------------------------------
FUNCTION( botgMinimumCompilerVersion lang compiler min_version )
    botgCompilerMatches( ${lang} ${compiler} found )
    IF( found )
        SET(version "${CMAKE_${lang}_COMPILER_VERSION}")
        IF( "${version}" STREQUAL "" )
            MESSAGE( WARNING "CMAKE_${lang}_COMPILER_VERSION could not be discovered!")
        ELSEIF( CMAKE_${lang}_COMPILER_VERSION VERSION_LESS ${min_version} )
            MESSAGE( FATAL_ERROR "compiler=${compiler} for lang=${lang} is required to have minimum version=${min_version} but found ${version}!")
        ENDIF()
    ENDIF()
ENDFUNCTION()
#-------------------------------------------------------------------------------
MACRO( botgUseCxxStandard version )
    botgAddCompilerFlags( CXX "GNU|Clang|Intel" ANY_SYSTEM
        "-std=c++${version}"
    )
ENDMACRO()
#-------------------------------------------------------------------------------
MACRO( botgEnableFortran )
    FOREACH( directive ${ARGN} )
        IF( directive STREQUAL "C_PREPROCESSOR" )
            botgAddCompilerFlags( Fortran "GNU|Clang" ANY_SYSTEM "-cpp" )
        ELSEIF( directive STREQUAL "UNLIMITED_LINE_LENGTH" )
            botgAddCompilerFlags( Fortran "GNU|Clang" ANY_SYSTEM "-ffree-line-length-none" )
        ELSE()
            MESSAGE(FATAL_ERROR "[BootsOnTheGround] EnableFortran directive=${directive} is unknown!")
        ENDIF()
    ENDFOREACH()
ENDMACRO()
#-------------------------------------------------------------------------------
MACRO( botgCheckFlag lang flag found )
    IF( ${lang} STREQUAL "Fortran" )
        #CMake does not have a core one so we provide above.
        botgCheckFlag_Fortran( "${flag}" ${found} )
    ELSEIF( ${lang} STREQUAL "CXX" )
        INCLUDE(CheckCXXCompilerFlag)
        CHECK_CXX_COMPILER_FLAG("${flag}" ${found})
    ELSEIF( ${lang} STREQUAL "C" )
        INCLUDE(CheckCCompilerFlag)
        CHECK_C_COMPILER_FLAG("${flag}" ${found})
    ELSE()
        MESSAGE(FATAL_ERROR "[BootsOnTheGround] lang=${lang} is not known!" )
    ENDIF()
ENDMACRO()
#-------------------------------------------------------------------------------
FUNCTION( botgCompilerMatches lang compiler found )
    SET(${found} OFF PARENT_SCOPE)
    IF( ("${compiler}" STREQUAL "ANY_COMPILER") OR ("${compiler}" STREQUAL "") )
        SET(${found} ON PARENT_SCOPE )
    ELSE()
        STRING(REGEX MATCH "${compiler}" found_ ${BOTG_${lang}_COMPILER})
        IF( NOT "${found_}" STREQUAL "" )
            SET(${found} ON PARENT_SCOPE)
        ENDIF()
    ENDIF()
ENDFUNCTION()
#-------------------------------------------------------------------------------
FUNCTION( botgSystemMatches system found)
    SET(${found} OFF PARENT_SCOPE)
    IF( ("${system}" STREQUAL "ANY_SYSTEM") OR ("${system}" STREQUAL "") )
        SET(${found} ON PARENT_SCOPE )
    ELSE()
        STRING(REGEX MATCH "${system}" found_ ${BOTG_SYSTEM})
        IF( NOT "${found_}" STREQUAL "" )
            SET(${found} ON PARENT_SCOPE)
        ENDIF()
    ENDIF()
ENDFUNCTION()
#-------------------------------------------------------------------------------
FUNCTION( botgCompilerAndSystemMatches lang compiler system found_both)
    botgCompilerMatches( ${lang} ${compiler} found_compiler )
    MESSAGE(STATUS "[BootsOnTheGround] lang='${lang}' compiler='${compiler}' found='${found_compiler}'")
    botgSystemMatches( ${system} found_system )
    MESSAGE(STATUS "[BootsOnTheGround] system='${system}' found='${found_system}'")
    IF( found_system AND found_compiler )
        SET(${found_both} ON PARENT_SCOPE )
    ELSE()
        SET(${found_both} OFF PARENT_SCOPE )
    ENDIF()
ENDFUNCTION()
#-------------------------------------------------------------------------------
MACRO( botgAddCompilerFlags lang compiler system) #list of flags comes at end
    botgCompilerAndSystemMatches( "${lang}" "${compiler}" "${system}" found )
    IF( found )
        MESSAGE(STATUS "[BootsOnTheGround] adding package=${PACKAGE_NAME} ${lang} flags for compiler='${BOTG_${lang}_COMPILER}' on system='${BOTG_SYSTEM}'")
        FOREACH( flag ${ARGN} )
            #check if flag is already in list
            STRING(FIND "${CMAKE_${lang}_FLAGS}" "${flag}" position)
            IF( ${position} LESS 0 )
                #create a special variable to store whether the flag works
                STRING(REGEX REPLACE "[^0-9a-zA-Z]" "_" flagname ${flag})
                botgCheckFlag( ${lang} ${flag} BOTG_USE_${lang}_FLAG_${flagname})
                IF( BOTG_USE_${lang}_FLAG_${flagname} )
                    MESSAGE(STATUS "[BootsOnTheGround] enabled flag='${flag}'!")
                    SET( CMAKE_${lang}_FLAGS "${CMAKE_${lang}_FLAGS} ${flag}")
                ELSE()
                    MESSAGE(STATUS "[BootsOnTheGround] could not add invalid flag='${flag}'!")
                ENDIF()
            ELSE()
                MESSAGE(STATUS "[BootsOnTheGround] flag='${flag}' has already been added.")
            ENDIF()
        ENDFOREACH()
    ENDIF()
ENDMACRO()
#-------------------------------------------------------------------------------
MACRO( botgAddLinkerFlags compiler system) #list of flags comes at end
    #Use CXX to check the validity of flags
    botgCompilerAndSystemMatches( CXX "${compiler}" "${system}" found )
    IF( found )
        MESSAGE(STATUS "[BootsOnTheGround] adding package=${PACKAGE_NAME} flags for linker on system='${BOTG_SYSTEM}'")
        FOREACH( flag ${ARGN} )
            #check if flag is already in list
            STRING(FIND "${CMAKE_EXE_LINKER_FLAGS}" "${flag}" position)
            IF( ${position} LESS 0 )
                #create a special variable to store whether the flag works
                STRING(REGEX REPLACE "[^0-9a-zA-Z]" "_" flagname ${flag})
                botgCheckFlag( CXX ${flag} BOTG_USE_EXE_LINKER_FLAG_${flagname})
                IF( BOTG_USE_EXE_LINKER_FLAG_${flagname} )
                    MESSAGE(STATUS "[BootsOnTheGround] enabled linker flag='${flag}'!")
                    SET( CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${flag}")
                ELSE()
                    MESSAGE(STATUS "[BootsOnTheGround] could not add invalid linker flag='${flag}'!")
                ENDIF()
            ELSE()
                MESSAGE(STATUS "[BootsOnTheGround] linker flag='${flag}' has already been added.")
            ENDIF()
        ENDFOREACH()
    ENDIF()
ENDMACRO()
#-------------------------------------------------------------------------------
# Do most of the legwork setting up a CMakeLists.txt file for a project.
#
MACRO( botgProject name )
    SET(project_root_dir "${CMAKE_SOURCE_DIR}")
    MESSAGE( STATUS "[BootsOnTheGround] configuring project with root directory=${project_root_dir} ...")

    # Clear the cache unless provided -D KEEP_CACHE:BOOL=ON.
    botgClearCMakeCache("${KEEP_CACHE}")

    # Install locally by default.
    IF( CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
        SET( CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/INSTALL" CACHE PATH "default install path" FORCE )
    ENDIF()

    # Enable the hunter gate for downloading/installing TPLs!
    PROJECT("" NONE) #hack to make HunterGate happy
    SET(HUNTER_SKIP_LOCK ON)
    INCLUDE( "${BOTG_ROOT_DIR}/cmake/HunterGate.cmake" )

    # Set project name.
    SET(PROJECT_NAME ${name} CACHE STRING "global project name" FORCE )
    MESSAGE( STATUS "[BootsOnTheGround] declared PROJECT_NAME=${PROJECT_NAME} ...")
    PROJECT( ${PROJECT_NAME} C CXX Fortran )

    # Turn off MPI by default.
    SET(TPL_ENABLE_MPI OFF CACHE BOOL "Turn off MPI by default.")

    # Cannot use TriBITS commands until after this statement!
    botgProcessTribits( "${BOTG_ROOT_DIR}/external/TriBITS/tribits" )

    # Just good practice.
    botgPreventInSourceBuilds()

    # Turn on tests by default.
    GLOBAL_SET( ${PROJECT_NAME}_ENABLE_TESTS ON CACHE BOOL "Enable all tests by default.")
    GLOBAL_SET( ${PROJECT_NAME}_ENABLE_SECONDARY_TESTED_CODE ON)

    # These variables make sure we have matching botgEnd() for packages and projects.
    GLOBAL_SET(BOTG_INSIDE_PROJECT_CMAKELISTS "${CMAKE_CURRENT_LIST_FILE}" )
    GLOBAL_SET(BOTG_INSIDE_PACKAGE_CMAKELISTS "" )
    GLOBAL_SET(BOTG_INSIDE_SUPERPACKAGE_CMAKELISTS "" )

    # Set the operating system name so we can have system-dependent flags.
    GLOBAL_SET( BOTG_SYSTEM ${CMAKE_SYSTEM_NAME} )
    MESSAGE( STATUS "[BootsOnTheGround] set operating system global BOTG_SYSTEM=${BOTG_SYSTEM}")

    # Process compiler for each language.
    botgProcessCompiler( C )
    botgProcessCompiler( CXX )
    botgProcessCompiler( Fortran )

ENDMACRO()
#-------------------------------------------------------------------------------
#  Initialize a super package (package with subpackages) CMakeLists.txt file.
#
MACRO( botgSuperPackage name )
    GLOBAL_SET(BOTG_INSIDE_SUPERPACKAGE_CMAKELISTS "${CMAKE_CURRENT_LIST_FILE}" )
    TRIBITS_PACKAGE_DECL( ${name} )
    TRIBITS_PROCESS_SUBPACKAGES()
    TRIBITS_PACKAGE_DEF()
ENDMACRO()
#-------------------------------------------------------------------------------
#  Initialize a package CMakeLists.txt file.
#
MACRO( botgPackage name )
    GLOBAL_SET(BOTG_INSIDE_PACKAGE_CMAKELISTS "${CMAKE_CURRENT_LIST_FILE}" )
    STRING( COMPARE NOTEQUAL "${BOTG_INSIDE_SUPERPACKAGE_CMAKELISTS}" "" is_subpackage )
    IF( ${is_subpackage} )
        TRIBITS_SUBPACKAGE( ${name} )
    ELSE()
        TRIBITS_PACKAGE( ${name} )
    ENDIF()
ENDMACRO()
#-------------------------------------------------------------------------------
# Finalize a CMakeLists.txt file.
#
MACRO( botgEnd )
    STRING( COMPARE NOTEQUAL "${BOTG_INSIDE_PACKAGE_CMAKELISTS}" "" is_package )
    STRING( COMPARE NOTEQUAL "${BOTG_INSIDE_SUPERPACKAGE_CMAKELISTS}" "" is_superpackage )
    STRING( COMPARE NOTEQUAL "${BOTG_INSIDE_PROJECT_CMAKELISTS}" "" has_project )
    
    IF( NOT ${has_project} )
        MESSAGE( FATAL_ERROR "[BootsOnTheGround]  botgEnd has been used without a corresponding botgProject in ${CMAKE_CURRENT_LIST_FILE}!" )
    ENDIF()

    #Inside a package/subpackage.
    IF( ${is_package} )
        IF( NOT "${BOTG_INSIDE_PACKAGE_CMAKELISTS}" STREQUAL "${CMAKE_CURRENT_LIST_FILE}" )
            MESSAGE( FATAL_ERROR "[BootsOnTheGround] botEnd has been used without botgPackage!" )
        ENDIF()
        
        # Miscellaneous wrap-up.
        botgProcessTPLS()
        
        # Add standard test directory.
        IF( IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/test" )
            TRIBITS_ADD_TEST_DIRECTORIES(test)
        ENDIF()

        #Inside a subpackage
        IF( ${is_superpackage} )

            ################################
            TRIBITS_SUBPACKAGE_POSTPROCESS()
            ################################

        #Inside a plain package
        ELSE()

            #############################
            TRIBITS_PACKAGE_POSTPROCESS()
            #############################

        ENDIF()

        GLOBAL_SET(BOTG_INSIDE_PACKAGE_CMAKELISTS "")

    #Inside a superpackage.
    ELSEIF( ${is_superpackage} )
        IF( NOT "${BOTG_INSIDE_SUPERPACKAGE_CMAKELISTS}" STREQUAL "${CMAKE_CURRENT_LIST_FILE}" )
            MESSAGE( FATAL_ERROR "[BootsOnTheGround] botEnd has been used without botgSuperPackage in ${CMAKE_CURRENT_LIST_FILE}!" )
        ENDIF()

        #############################
        TRIBITS_PACKAGE_POSTPROCESS()
        #############################

        GLOBAL_SET(BOTG_INSIDE_SUPERPACKAGE_CMAKELISTS "")

    #Inside a project.
    ELSE()

        IF( ${is_package} )
            MESSAGE( FATAL_ERROR "[BootsOnTheGround] package=${BOTG_INSIDE_PACKAGE_CMAKELISTS} did not have botgEnd()!" )
        ELSEIF( ${is_superpackage} )
            MESSAGE( FATAL_ERROR "[BootsOnTheGround] super package=${BOTG_INSIDE_SUPERPACKAGE_CMAKELISTS} did not have botgEnd()!" )
        ENDIF()

        ############################
        TRIBITS_PROJECT_ENABLE_ALL()
        ############################

        # Final print of all the variables for inspection.
        # For example: -D MATCH_VARIABLE_REGEX:STRING="" will print everything.
        #              -D MATCH_VARIABLE_REGEX:STRING="^BootsOnTheGround" will
        #                 print all the BootsOnTheGround variables.
        #
        IF( DEFINED MATCH_VARIABLE_REGEX )
            botgPrintVar("${MATCH_VARIABLE_REGEX}")
        ENDIF()

    ENDIF()

ENDMACRO()
#-------------------------------------------------------------------------------
MACRO( botgAddTPL type need name )
    APPEND_SET( ${type}_${need}_DEP_PACKAGES BootsOnTheGround_${name} )
    APPEND_SET( ${type}_${need}_DEP_TPLS ${name} )
ENDMACRO()
#------------------------------------------------------------------------------
MACRO( botgProcessTPLS )
    #Linker options always need to be loaded as far as I can tell.
    #Imagine we have true TPL C, and we create BootsOnTheGround wrapper B, and we
    #depend on this package in a code A, A-->B-->C.
    #We can include in the CMake for B the necessary linker options, but what about
    #A? We should be able to "inherit" them from B but I have yet to figure it out
    #without resorting to these types of files.
    FOREACH( name ${${PACKAGE_NAME}_LIB_REQUIRED_DEP_TPLS}
                  ${${PACKAGE_NAME}_LIB_OPTIONAL_DEP_TPLS}
                  ${${PACKAGE_NAME}_TEST_REQUIRED_DEP_TPLS}
                  ${${PACKAGE_NAME}_TEST_OPTIONAL_DEP_TPLS} )
       IF( TPL_ENABLE_${name} )
           SET( linker_file "${BOTG_ROOT_DIR}/src/${name}/cmake/LinkerFlags.cmake" )
           IF( EXISTS "${linker_file}" )
               MESSAGE( STATUS "[BootsOnTheGround] package=${PACKAGE_NAME} is adding TPL=${name} linker options from file='${linker_file}'")
               INCLUDE( "${linker_file}" )
           ENDIF()
       ENDIF()
    ENDFOREACH()
ENDMACRO()
#-------------------------------------------------------------------------------
