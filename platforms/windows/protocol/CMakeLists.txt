cmake_minimum_required(VERSION 3.25)
project(DisplayMeshWindowsProtocol LANGUAGES CXX)

add_library(displaymesh_protocol STATIC
    DmpFrame.cpp
    DmpHostSessionGate.cpp
    DmpHostReconnectPolicy.cpp
    DmpSecureSession.cpp
    DmpProtectedFrameCodec.cpp
)

target_include_directories(displaymesh_protocol PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_features(displaymesh_protocol PUBLIC cxx_std_20)

target_link_libraries(displaymesh_protocol PUBLIC bcrypt)

include(CTest)
if(BUILD_TESTING)
    # Release builds define NDEBUG by default. The protocol tests intentionally
    # use assert() for invariants, so keep those assertions active in CI.
    if(MSVC)
        add_compile_options(/UNDEBUG)
    else()
        add_compile_options(-UNDEBUG)
    endif()
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

    add_executable(
        displaymesh-secure-session-tests
        tests/DmpSecureSessionTests.cpp
    )

    target_link_libraries(
        displaymesh-secure-session-tests
        PRIVATE displaymesh_protocol
    )

    add_test(
        NAME displaymesh-secure-session
        COMMAND displaymesh-secure-session-tests
    )
endif()
