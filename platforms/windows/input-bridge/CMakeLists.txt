cmake_minimum_required(VERSION 3.25)
project(DisplayMeshInputBridge LANGUAGES CXX)

if(NOT WIN32)
    message(FATAL_ERROR "DisplayMesh input bridge targets Windows")
endif()

add_subdirectory(
    ../protocol
    ${CMAKE_CURRENT_BINARY_DIR}/displaymesh-protocol
)

add_library(displaymesh_input STATIC
    DmpInput.cpp
    DmpInputRouter.cpp
    TouchInjector.cpp
)

target_include_directories(displaymesh_input PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_features(displaymesh_input PUBLIC cxx_std_20)
target_compile_definitions(displaymesh_input PUBLIC
    UNICODE
    _UNICODE
    WINVER=0x0A00
    _WIN32_WINNT=0x0A00
)
target_link_libraries(
    displaymesh_input
    PUBLIC
        User32
        displaymesh_protocol
)

add_executable(displaymesh-input-bridge
    main.cpp
)
target_link_libraries(displaymesh-input-bridge PRIVATE displaymesh_input)

include(CTest)
if(BUILD_TESTING)
    add_executable(displaymesh-input-contract-tests
        tests/DmpInputTests.cpp
    )
    target_link_libraries(
        displaymesh-input-contract-tests
        PRIVATE displaymesh_input
    )
    add_test(
        NAME displaymesh-input-contract
        COMMAND displaymesh-input-contract-tests
    )

    add_executable(
        displaymesh-session-input-router-tests
        tests/DmpInputRouterTests.cpp
    )

    target_link_libraries(
        displaymesh-session-input-router-tests
        PRIVATE displaymesh_input
    )

    add_test(
        NAME displaymesh-session-input-router
        COMMAND displaymesh-session-input-router-tests
    )
endif()
