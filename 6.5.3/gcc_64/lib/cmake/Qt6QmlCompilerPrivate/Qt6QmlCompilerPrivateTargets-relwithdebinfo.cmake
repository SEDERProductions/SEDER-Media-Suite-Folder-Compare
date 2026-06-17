#----------------------------------------------------------------
# Generated CMake target import file for configuration "RelWithDebInfo".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "Qt6::QmlCompilerPrivate" for configuration "RelWithDebInfo"
set_property(TARGET Qt6::QmlCompilerPrivate APPEND PROPERTY IMPORTED_CONFIGURATIONS RELWITHDEBINFO)
set_target_properties(Qt6::QmlCompilerPrivate PROPERTIES
  IMPORTED_LOCATION_RELWITHDEBINFO "${_IMPORT_PREFIX}/lib/libQt6QmlCompiler.so.6.5.3"
  IMPORTED_SONAME_RELWITHDEBINFO "libQt6QmlCompiler.so.6"
  )

list(APPEND _cmake_import_check_targets Qt6::QmlCompilerPrivate )
list(APPEND _cmake_import_check_files_for_Qt6::QmlCompilerPrivate "${_IMPORT_PREFIX}/lib/libQt6QmlCompiler.so.6.5.3" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
