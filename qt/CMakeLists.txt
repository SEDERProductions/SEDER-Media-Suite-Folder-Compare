# SPDX-License-Identifier: GPL-3.0-only

cmake_minimum_required(VERSION 3.22)

project(SederFolderCompareQt VERSION 0.1.4 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Widgets Test)

set(RUST_MANIFEST "${CMAKE_CURRENT_SOURCE_DIR}/../Cargo.toml")
set(RUST_TARGET_DIR "${CMAKE_BINARY_DIR}/rust-target")
set(RUST_LIB_DIR "${RUST_TARGET_DIR}/release")
set(RUST_LIB "${RUST_LIB_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}seder_folder_compare${CMAKE_STATIC_LIBRARY_SUFFIX}")

add_custom_command(
    OUTPUT "${RUST_LIB}"
    COMMAND cargo build --manifest-path "${RUST_MANIFEST}" --release --lib --target-dir "${RUST_TARGET_DIR}"
    DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/../Cargo.toml"
        "${CMAKE_CURRENT_SOURCE_DIR}/../src/lib.rs"
        "${CMAKE_CURRENT_SOURCE_DIR}/../src/tests.rs"
        "${CMAKE_CURRENT_SOURCE_DIR}/../src/compare.rs"
        "${CMAKE_CURRENT_SOURCE_DIR}/../src/ffi.rs"
        "${CMAKE_CURRENT_SOURCE_DIR}/../src/report.rs"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.."
    COMMENT "Building Rust Folder Compare core"
    VERBATIM
)

add_custom_target(seder_folder_compare_rust DEPENDS "${RUST_LIB}")

add_library(seder_folder_compare_core STATIC IMPORTED GLOBAL)
set_target_properties(seder_folder_compare_core PROPERTIES IMPORTED_LOCATION "${RUST_LIB}")
add_dependencies(seder_folder_compare_core seder_folder_compare_rust)

set(APP_SOURCES
    src/main.cpp
    src/CompareFilterProxyModel.cpp
    src/CompareFilterProxyModel.h
    src/CompareResultTableModel.cpp
    src/CompareResultTableModel.h
    src/FolderCompareController.cpp
    src/FolderCompareController.h
    src/FolderCompareWorker.cpp
    src/FolderCompareWorker.h
    src/FolderCompareUtils.h
)

set(SEDER_APP_ICON_MACOS "${CMAKE_CURRENT_SOURCE_DIR}/../assets/icon.icns")
set(SEDER_APP_ICON_WINDOWS_RC "${CMAKE_CURRENT_SOURCE_DIR}/app.rc")

set(SEDER_APP_PLATFORM_SOURCES "")
if(APPLE)
    set_source_files_properties("${SEDER_APP_ICON_MACOS}" PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources")
    list(APPEND SEDER_APP_PLATFORM_SOURCES "${SEDER_APP_ICON_MACOS}")
endif()
if(WIN32)
    list(APPEND SEDER_APP_PLATFORM_SOURCES "${SEDER_APP_ICON_WINDOWS_RC}")
endif()

qt_add_executable(seder-folder-compare-qt
    WIN32
    ${APP_SOURCES}
    ${SEDER_APP_PLATFORM_SOURCES}
)

qt_add_resources(seder-folder-compare-qt icon_resources
    PREFIX "/"
    FILES
        "../assets/icon.svg"
)

qt_add_resources(seder-folder-compare-qt qml_resources
    PREFIX "/"
    FILES
        "qml/Main.qml"
)

target_include_directories(seder-folder-compare-qt PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_link_libraries(seder-folder-compare-qt PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    seder_folder_compare_core
)

if(WIN32)
    target_link_libraries(seder-folder-compare-qt PRIVATE
        ntdll ws2_32 userenv shell32 advapi32 bcrypt
    )
endif()

set_target_properties(seder-folder-compare-qt PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_GUI_IDENTIFIER com.sederproductions.media-suite.folder-compare
    MACOSX_BUNDLE_BUNDLE_NAME "SEDER Media Suite Folder Compare"
    MACOSX_BUNDLE_ICON_FILE icon.icns
)

enable_testing()

qt_add_executable(compare-model-tests
    tests/test_model.cpp
    src/CompareFilterProxyModel.cpp
    src/CompareFilterProxyModel.h
    src/CompareResultTableModel.cpp
    src/CompareResultTableModel.h
)

target_include_directories(compare-model-tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_link_libraries(compare-model-tests PRIVATE
    Qt6::Core
    Qt6::Test
    seder_folder_compare_core
)

if(WIN32)
    target_link_libraries(compare-model-tests PRIVATE
        ntdll ws2_32 userenv shell32 advapi32 bcrypt
    )
endif()

add_test(NAME compare-model-tests COMMAND compare-model-tests)
