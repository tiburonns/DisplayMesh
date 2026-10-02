cmake_minimum_required(VERSION 3.25)
project(DisplayMeshWindowsProtocol LANGUAGES CXX)

add_library(displaymesh_protocol STATIC
    DmpFrame.cpp
    DmpHostSessionGate.cpp
    DmpHostReconnectPolicy.cpp
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

    add_executable(
        displaymesh-host-session-gate-tests
        tests/DmpHostSessionGateTests.cpp
    )

    target_link_libraries(
        displaymesh-host-session-gate-tests
        PRIVATE displaymesh_protocol
    )

    add_test(
        NAME displaymesh-host-session-gate
        COMMAND displaymesh-host-session-gate-tests
    )

    add_executable(
        displaymesh-host-reconnect-policy-tests
        tests/DmpHostReconnectPolicyTests.cpp
    )

    target_link_libraries(
        displaymesh-host-reconnect-policy-tests
        PRIVATE displaymesh_protocol
    )

    add_test(
        NAME displaymesh-host-reconnect-policy
        COMMAND displaymesh-host-reconnect-policy-tests
    )
endif()
