cmake_minimum_required(VERSION 3.25)
project(DisplayMeshWindowsBridgeProbe LANGUAGES CXX)

if(NOT WIN32)
    message(FATAL_ERROR "DisplayMesh bridge probe targets Windows")
endif()

add_executable(displaymesh-bridge-probe
    main.cpp
)

add_library(displaymesh-shared-d3d11 STATIC
    ../bridge/SharedD3D11TexturePool.cpp
)

target_include_directories(
    displaymesh-shared-d3d11
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/../bridge
)

target_compile_features(
    displaymesh-shared-d3d11
    PUBLIC cxx_std_20
)

target_compile_definitions(
    displaymesh-shared-d3d11
    PUBLIC
        NOMINMAX
        UNICODE
        _UNICODE
        WINVER=0x0A00
        _WIN32_WINNT=0x0A00
)

target_link_libraries(
    displaymesh-shared-d3d11
    PUBLIC
        d3d11
        dxgi
)

target_include_directories(displaymesh-bridge-probe PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../bridge
)

target_compile_features(
    displaymesh-bridge-probe
    PRIVATE cxx_std_20
)

target_compile_definitions(
    displaymesh-bridge-probe
    PRIVATE
        UNICODE
        _UNICODE
        WINVER=0x0A00
        _WIN32_WINNT=0x0A00
)

target_link_libraries(
    displaymesh-bridge-probe
    PRIVATE
        Setupapi
)

include(CTest)

if(BUILD_TESTING)
    add_executable(displaymesh-frame-mailbox-tests
        tests/LatestFrameMailboxTests.cpp
    )

    target_include_directories(
        displaymesh-frame-mailbox-tests
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/../bridge
    )

    target_compile_features(
        displaymesh-frame-mailbox-tests
        PRIVATE cxx_std_20
    )

    add_test(
        NAME displaymesh-frame-mailbox
        COMMAND displaymesh-frame-mailbox-tests
    )

    add_executable(displaymesh-gpu-slot-contract-tests
        tests/SharedGpuSlotContractTests.cpp
    )

    target_include_directories(
        displaymesh-gpu-slot-contract-tests
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/../bridge
    )

    target_compile_features(
        displaymesh-gpu-slot-contract-tests
        PRIVATE cxx_std_20
    )

    add_test(
        NAME displaymesh-gpu-slot-contract
        COMMAND displaymesh-gpu-slot-contract-tests
    )

    add_executable(displaymesh-shared-d3d11-tests
        tests/SharedD3D11TexturePoolTests.cpp
    )

    target_include_directories(
        displaymesh-shared-d3d11-tests
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/../bridge
    )

    target_compile_features(
        displaymesh-shared-d3d11-tests
        PRIVATE cxx_std_20
    )

    target_link_libraries(
        displaymesh-shared-d3d11-tests
        PRIVATE
            displaymesh-shared-d3d11
    )

    add_test(
        NAME displaymesh-shared-d3d11
        COMMAND displaymesh-shared-d3d11-tests
    )
endif()
