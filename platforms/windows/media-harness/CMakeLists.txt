cmake_minimum_required(VERSION 3.25)
project(DisplayMeshWindowsMediaHarness LANGUAGES CXX)

if(NOT WIN32)
    message(FATAL_ERROR "DisplayMesh Windows media harness targets Windows")
endif()

add_library(displaymesh_windows_media STATIC
    WindowsMediaProbe.cpp
)

target_include_directories(displaymesh_windows_media PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_features(displaymesh_windows_media PUBLIC cxx_std_20)
target_compile_definitions(displaymesh_windows_media PUBLIC
    UNICODE
    _UNICODE
    WINVER=0x0A00
    _WIN32_WINNT=0x0A00
)

target_link_libraries(displaymesh_windows_media PUBLIC
    d3d11
    dxgi
    mf
    mfplat
    mfuuid
    ole32
    oleaut32
)

add_executable(displaymesh-media-probe
    main.cpp
)

target_link_libraries(
    displaymesh-media-probe
    PRIVATE displaymesh_windows_media
)
