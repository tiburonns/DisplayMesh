#pragma once
#define NOMINMAX

#include <Windows.h>
#include <d3d11_1.h>
#include <dxgi1_2.h>
#include <wrl/client.h>

#include <array>
#include <cstdint>
#include <utility>

#include "SharedGpuSlotContract.h"

namespace displaymesh::bridge {

class OwnedWin32Handle {
public:
    OwnedWin32Handle() noexcept = default;

    explicit OwnedWin32Handle(
        HANDLE handle) noexcept
        : handle_(handle) {}

    ~OwnedWin32Handle() {
        Reset();
    }

    OwnedWin32Handle(
        const OwnedWin32Handle&) = delete;
    OwnedWin32Handle& operator=(
        const OwnedWin32Handle&) = delete;

    OwnedWin32Handle(
        OwnedWin32Handle&& other) noexcept
        : handle_(std::exchange(
              other.handle_,
              nullptr)) {}

    OwnedWin32Handle& operator=(
        OwnedWin32Handle&& other) noexcept {
        if (this != &other) {
            Reset();
            handle_ = std::exchange(
                other.handle_,
                nullptr);
        }
        return *this;
    }

    HANDLE Get() const noexcept {
        return handle_;
    }

    explicit operator bool() const noexcept {
        return handle_ != nullptr &&
            handle_ != INVALID_HANDLE_VALUE;
    }

    void Reset(
        HANDLE next = nullptr) noexcept {
        if (handle_ != nullptr &&
            handle_ != INVALID_HANDLE_VALUE) {
            CloseHandle(handle_);
        }
        handle_ = next;
    }

private:
    HANDLE handle_{nullptr};
};

class SharedD3D11TextureSlot {
public:
    SharedD3D11TextureSlot() noexcept = default;
    SharedD3D11TextureSlot(
        SharedD3D11TextureSlot&&) noexcept = default;
    SharedD3D11TextureSlot& operator=(
        SharedD3D11TextureSlot&&) noexcept = default;

    SharedD3D11TextureSlot(
        const SharedD3D11TextureSlot&) = delete;
    SharedD3D11TextureSlot& operator=(
        const SharedD3D11TextureSlot&) = delete;

    const SharedGpuSurfaceDescriptor&
    Descriptor() const noexcept {
        return descriptor_;
    }

    ID3D11Texture2D* Texture() const noexcept {
        return texture_.Get();
    }

    HANDLE SharedHandle() const noexcept {
        return sharedHandle_.Get();
    }

    bool IsValid() const noexcept {
        return descriptor_.IsValid() &&
            texture_ != nullptr &&
            static_cast<bool>(sharedHandle_);
    }

private:
    friend class SharedD3D11TexturePool;

    SharedGpuSurfaceDescriptor descriptor_{};
    Microsoft::WRL::ComPtr<
        ID3D11Texture2D> texture_;
    OwnedWin32Handle sharedHandle_;
};

class SharedD3D11TexturePool {
public:
    explicit SharedD3D11TexturePool(
        Microsoft::WRL::ComPtr<
            ID3D11Device> device) noexcept;

    HRESULT Recreate(
        std::uint32_t width,
        std::uint32_t height,
        DXGI_FORMAT format =
            DXGI_FORMAT_B8G8R8A8_UNORM) noexcept;

    void Reset() noexcept;

    std::uint64_t Generation() const noexcept {
        return generation_;
    }

    const SharedD3D11TextureSlot* Slot(
        std::uint32_t index) const noexcept;

    bool Matches(
        const FrameAnnouncement& frame) const noexcept {
        return contract_.Matches(frame);
    }

private:
    HRESULT CreateSlot(
        std::uint32_t slotIndex,
        std::uint64_t generation,
        std::uint32_t width,
        std::uint32_t height,
        DXGI_FORMAT format,
        SharedD3D11TextureSlot&
            output) noexcept;

    Microsoft::WRL::ComPtr<
        ID3D11Device> device_;
    std::array<
        SharedD3D11TextureSlot,
        kFrameMailboxSlotCount>
        slots_{};
    SharedGpuSlotContract contract_;
    std::uint64_t generation_{0};
};

}  // namespace displaymesh::bridge
