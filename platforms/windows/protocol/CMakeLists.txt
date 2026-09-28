cmake_minimum_required(VERSION 3.25)
project(DisplayMeshWindowsProtocol LANGUAGES CXX)

add_library(displaymesh_protocol STATIC
    DmpFrame.cpp
)

target_include_directories(displaymesh_protocol PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_features(displaymesh_protocol PUBLIC cxx_std_20)

include(CTest)
if(BUILD_TESTING)
    add_executable(displaymesh-protocol-tests
        tests/DmpFrameTests.cpp
    )
    target_link_libraries(
        displaymesh-protocol-tests
        PRIVATE displaymesh_protocol
    )
    add_test(
        NAME displaymesh-protocol
        COMMAND displaymesh-protocol-tests
    )
endif()
