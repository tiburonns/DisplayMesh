cmake_minimum_required(VERSION 3.25)
project(DisplayMeshWindowsMediaHarness LANGUAGES CXX)

if(NOT WIN32)
    message(FATAL_ERROR "DisplayMesh Windows media harness targets Windows")
endif()

add_library(displaymesh_shared_d3d11 STATIC
    ../bridge/SharedD3D11TexturePool.cpp
)

target_include_directories(
    displaymesh_shared_d3d11
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/../bridge
)

target_compile_features(
    displaymesh_shared_d3d11
    PUBLIC cxx_std_20
)

target_compile_definitions(
    displaymesh_shared_d3d11
    PUBLIC
        NOMINMAX
        UNICODE
        _UNICODE
        WINVER=0x0A00
        _WIN32_WINNT=0x0A00
)

target_link_libraries(
    displaymesh_shared_d3d11
    PUBLIC
        d3d11
        dxgi
)

add_library(displaymesh_windows_media STATIC
    WindowsMediaProbe.cpp
    BoundedEncodeWorker.cpp
    H264AnnexBPacketizer.cpp
    H264AccessUnitNormalizer.cpp
    MftEncodedSampleProcessor.cpp
    MftEncoderPumpState.cpp
    LiveEncodeCoordinator.cpp
    MftLiveEncodeAdapter.cpp
    MftAsyncEventPump.cpp
    MftDxgiInputSampleFactory.cpp
    SharedSurfaceEncodeInput.cpp
    ReceiverAdaptiveController.cpp
)

target_include_directories(displaymesh_windows_media PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../bridge
)

target_compile_features(displaymesh_windows_media PUBLIC cxx_std_20)
target_compile_definitions(displaymesh_windows_media PUBLIC
    UNICODE
    _UNICODE
    WINVER=0x0A00
    _WIN32_WINNT=0x0A00
)

target_link_libraries(displaymesh_windows_media PUBLIC
    displaymesh_shared_d3d11
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


include(CTest)

if(BUILD_TESTING)
    # CI builds the test executables in Release. Keep assert() active so
    # invariant checks are evaluated instead of being compiled out by NDEBUG.
    if(MSVC)
        add_compile_options(/UNDEBUG)
    else()
        add_compile_options(-UNDEBUG)
    endif()
    add_executable(
        bounded-encode-worker-tests
        tests/BoundedEncodeWorkerTests.cpp
    )

    target_link_libraries(
        bounded-encode-worker-tests
        PRIVATE displaymesh_windows_media
    )

    add_test(
        NAME bounded-encode-worker
        COMMAND bounded-encode-worker-tests
    )

    add_executable(
        h264-dmp-packetizer-tests
        tests/H264AnnexBPacketizerTests.cpp
    )

    target_link_libraries(
        h264-dmp-packetizer-tests
        PRIVATE displaymesh_windows_media
    )

    add_test(
        NAME h264-dmp-packetizer
        COMMAND h264-dmp-packetizer-tests
    )

    add_executable(
        h264-dmp-frame-integration-tests
        tests/H264DmpFrameIntegrationTests.cpp
        ../protocol/DmpFrame.cpp
    )

    target_include_directories(
        h264-dmp-frame-integration-tests
        PRIVATE ../protocol
    )

    target_link_libraries(
        h264-dmp-frame-integration-tests
        PRIVATE displaymesh_windows_media
    )

    add_test(
        NAME h264-dmp-frame-integration
        COMMAND h264-dmp-frame-integration-tests
    )

    add_executable(
        h264-access-unit-normalizer-tests
        tests/H264AccessUnitNormalizerTests.cpp
    )

    target_link_libraries(
        h264-access-unit-normalizer-tests
        PRIVATE displaymesh_windows_media
    )

    add_test(
        NAME h264-access-unit-normalizer
        COMMAND h264-access-unit-normalizer-tests
    )

    add_executable(
        h264-normalizer-packetizer-integration-tests
        tests/H264NormalizerPacketizerIntegrationTests.cpp
    )

    target_link_libraries(
        h264-normalizer-packetizer-integration-tests
        PRIVATE displaymesh_windows_media
    )

    add_test(
        NAME h264-normalizer-packetizer-integration
        COMMAND h264-normalizer-packetizer-integration-tests
    )

    add_executable(
        mft-encoded-sample-processor-tests
        tests/MftEncodedSampleProcessorTests.cpp
    )

    target_link_libraries(
        mft-encoded-sample-processor-tests
        PRIVATE displaymesh_windows_media
    )

    add_test(
        NAME mft-encoded-sample-processor
        COMMAND mft-encoded-sample-processor-tests
    )

    add_executable(
        mft-encoder-pump-state-tests
        tests/MftEncoderPumpStateTests.cpp
    )

    target_link_libraries(
        mft-encoder-pump-state-tests
        PRIVATE displaymesh_windows_media
    )

    add_test(
        NAME mft-encoder-pump-state
        COMMAND mft-encoder-pump-state-tests
    )

    add_executable(
        live-encode-coordinator-tests
        tests/LiveEncodeCoordinatorTests.cpp
    )

    target_link_libraries(
        live-encode-coordinator-tests
        PRIVATE displaymesh_windows_media
    )

    add_test(
        NAME live-encode-coordinator
        COMMAND live-encode-coordinator-tests
    )

    add_executable(
        mft-async-event-pump-tests
        tests/MftAsyncEventPumpTests.cpp
    )

    target_link_libraries(
        mft-async-event-pump-tests
        PRIVATE displaymesh_windows_media
    )

    add_test(
        NAME mft-async-event-pump
        COMMAND mft-async-event-pump-tests
    )

    add_executable(
        mft-live-encode-adapter-tests
        tests/MftLiveEncodeAdapterTests.cpp
    )

    target_link_libraries(
        mft-live-encode-adapter-tests
        PRIVATE displaymesh_windows_media
    )

    add_test(
        NAME mft-live-encode-adapter
        COMMAND mft-live-encode-adapter-tests
    )

    add_executable(
        mft-dxgi-input-sample-tests
        tests/MftDxgiInputSampleFactoryTests.cpp
    )

    target_link_libraries(
        mft-dxgi-input-sample-tests
        PRIVATE displaymesh_windows_media
    )

    add_test(
        NAME mft-dxgi-input-sample
        COMMAND mft-dxgi-input-sample-tests
    )

    add_executable(
        shared-surface-encode-input-tests
        tests/SharedSurfaceEncodeInputTests.cpp
    )

    target_link_libraries(
        shared-surface-encode-input-tests
        PRIVATE displaymesh_windows_media
    )

    add_test(
        NAME shared-surface-encode-input
        COMMAND shared-surface-encode-input-tests
    )

    add_executable(
        receiver-adaptive-controller-tests
        tests/ReceiverAdaptiveControllerTests.cpp
    )

    target_link_libraries(
        receiver-adaptive-controller-tests
        PRIVATE displaymesh_windows_media
    )

    add_test(
        NAME receiver-adaptive-controller
        COMMAND receiver-adaptive-controller-tests
    )
endif()
