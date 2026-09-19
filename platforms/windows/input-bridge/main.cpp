#include <algorithm>
#include <cctype>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "DmpInput.h"
#include "TouchInjector.h"

namespace {

std::vector<std::uint8_t> ParseHex(std::string value) {
    value.erase(
        std::remove_if(
            value.begin(),
            value.end(),
            [](unsigned char character) {
                return std::isspace(character) ||
                       character == ':' ||
                       character == '-';
            }),
        value.end());

    if (value.size() % 2 != 0) {
        throw std::runtime_error("hex payload must contain complete bytes");
    }

    std::vector<std::uint8_t> bytes;
    bytes.reserve(value.size() / 2);

    for (std::size_t index = 0; index < value.size(); index += 2) {
        bytes.push_back(
            static_cast<std::uint8_t>(
                std::stoul(value.substr(index, 2), nullptr, 16)));
    }

    return bytes;
}

void PrintUsage() {
    std::cout
        << "DisplayMesh Windows input bridge\n\n"
        << "Usage:\n"
        << "  displaymesh-input-bridge --decode <40-byte-hex>\n"
        << "  displaymesh-input-bridge --inject "
           "<left> <top> <right> <bottom> <40-byte-hex>\n";
}

}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc == 3 && std::string(argv[1]) == "--decode") {
            const auto bytes = ParseHex(argv[2]);
            displaymesh::InputSample sample{};
            std::string error;

            if (!displaymesh::DecodeInputSample(
                    bytes,
                    sample,
                    error)) {
                std::cerr << error << "\n";
                return 2;
            }

            std::cout
                << "contact=" << sample.contactId
                << " x=" << sample.normalizedX
                << " y=" << sample.normalizedY
                << " pressure=" << sample.pressure
                << " timestamp_us=" << sample.timestampMicros
                << "\n";
            return 0;
        }

        if (argc == 7 && std::string(argv[1]) == "--inject") {
            RECT target{
                std::stol(argv[2]),
                std::stol(argv[3]),
                std::stol(argv[4]),
                std::stol(argv[5]),
            };
            const auto bytes = ParseHex(argv[6]);

            displaymesh::InputSample sample{};
            std::string error;
            if (!displaymesh::DecodeInputSample(
                    bytes,
                    sample,
                    error)) {
                std::cerr << error << "\n";
                return 2;
            }

            displaymesh::TouchInjector injector;
            if (!injector.Initialize(target, 10, error)) {
                std::cerr << error << "\n";
                return 3;
            }

            if (!injector.Inject(sample, error)) {
                std::cerr << error << "\n";
                return 4;
            }

            return 0;
        }

        PrintUsage();
        return 1;
    } catch (const std::exception& error) {
        std::cerr << error.what() << "\n";
        return 5;
    }
}
