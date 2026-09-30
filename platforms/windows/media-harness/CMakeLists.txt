cmake_minimum_required(VERSION 3.25)
project(DisplayMeshWindowsMediaHarness LANGUAGES CXX)

if(NOT WIN32)
    message(FATAL_ERROR "DisplayMesh Windows media harness targets Windows")
endif()

add_library(displaymesh_windows_media STATIC
    WindowsMediaProbe.cpp
    BoundedEncodeWorker.cpp
    H264AnnexBPacketizer.cpp
    H264AccessUnitNormalizer.cpp
    MftEncodedSampleProcessor.cpp
    MftEncoderPumpState.cpp
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


include(CTest)

if(BUILD_TESTING)
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
endif()
