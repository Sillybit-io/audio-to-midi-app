// sillymidi-engine: newline-delimited JSON sidecar around muscriptor.cpp.
// stdout carries one JSON object per line; stderr is free text for logs.

#include "muscriptor/muscriptor.hpp"

#include <algorithm>
#include <atomic>
#include <csignal>
#include <cstdlib>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include <sys/stat.h>
#include <unistd.h>

namespace
{

std::atomic<bool> gCancel{false};

void onSigterm(int)
{
    gCancel.store(true);
}

std::string jsonEscape(const std::string& inText)
{
    std::string out;
    for (const unsigned char c : inText) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof buf, "\\u%04x", c);
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
        }
    }
    return out;
}

std::string str(const std::string& inText)
{
    return "\"" + jsonEscape(inText) + "\"";
}

void emit(const std::string& inLine)
{
    std::fwrite(inLine.data(), 1, inLine.size(), stdout);
    std::fputc('\n', stdout);
    std::fflush(stdout);
}

const char* errorName(msl::Error inError)
{
    switch (inError) {
        case msl::Error::FileNotFound: return "FileNotFound";
        case msl::Error::InvalidCheckpoint: return "InvalidCheckpoint";
        case msl::Error::UnsupportedArch: return "UnsupportedArch";
        case msl::Error::UnsupportedCheckpointVersion: return "UnsupportedCheckpointVersion";
        case msl::Error::OutOfMemory: return "OutOfMemory";
        case msl::Error::DeviceUnavailable: return "DeviceUnavailable";
        case msl::Error::ContextOverflow: return "ContextOverflow";
        case msl::Error::Cancelled: return "Cancelled";
        case msl::Error::InvalidArgument: return "InvalidArgument";
        case msl::Error::Internal: return "Internal";
    }
    return "Internal";
}

int fail(const std::string& inCode, const std::string& inMessage)
{
    emit("{\"type\":\"error\",\"code\":" + str(inCode) + ",\"message\":" + str(inMessage) + "}");
    return inCode == "Cancelled" ? 2 : 1;
}

int failWith(msl::Error inError)
{
    return fail(errorName(inError), msl::describe(inError));
}

std::string deviceJson(const msl::Device& inDevice, std::size_t inIndex)
{
    return "{\"index\":" + std::to_string(inIndex) + ",\"name\":" + str(inDevice.name) + ",\"backend\":"
        + str(inDevice.backend) + ",\"integrated\":" + (inDevice.integrated ? "true" : "false")
        + ",\"memory_total\":" + std::to_string(inDevice.memory_total) + "}";
}

int runDevices()
{
    const auto devices = msl::availableDevices();
    std::string line = "{\"type\":\"devices\",\"auto\":" + std::to_string(msl::autoDevice(devices)) + ",\"devices\":[";
    for (std::size_t i = 0; i < devices.size(); ++i) {
        line += (i ? "," : "") + deviceJson(devices[i], i);
    }
    emit(line + "]}");
    return 0;
}

int runInstruments()
{
    std::string line = "{\"type\":\"instruments\",\"instruments\":[";
    bool first = true;
    for (const auto group : msl::allInstrumentGroups()) {
        line += std::string(first ? "" : ",") + "{\"name\":" + str(std::string(msl::instrumentName(group)))
            + ",\"program\":" + std::to_string(msl::programFor(group)) + "}";
        first = false;
    }
    emit(line + "]}");
    return 0;
}

// Reads raw little-endian float32 mono at 16 kHz, or a RIFF WAV (PCM16 or float32, mono or stereo, 16 kHz).
bool readAudio(const std::string& inPath, std::vector<float>& outSamples, std::string& outProblem)
{
    std::ifstream in(inPath, std::ios::binary);
    if (!in) {
        outProblem = "audio file not found";
        return false;
    }
    const std::vector<char> bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());

    if (bytes.size() < 12 || std::memcmp(bytes.data(), "RIFF", 4) != 0) {
        const std::size_t n = bytes.size() / sizeof(float);
        outSamples.resize(n);
        std::memcpy(outSamples.data(), bytes.data(), n * sizeof(float));
        return true;
    }

    auto u16 = [&](std::size_t o) { return static_cast<std::uint16_t>(static_cast<std::uint8_t>(bytes[o]) | (static_cast<std::uint8_t>(bytes[o + 1]) << 8)); };
    auto u32 = [&](std::size_t o) { return static_cast<std::uint32_t>(u16(o)) | (static_cast<std::uint32_t>(u16(o + 2)) << 16); };

    std::uint16_t format = 0, channels = 0, bits = 0;
    std::uint32_t rate = 0;
    std::size_t dataOffset = 0, dataSize = 0;
    std::size_t pos = 12;
    while (pos + 8 <= bytes.size()) {
        const std::size_t size = u32(pos + 4);
        const std::size_t body = pos + 8;
        if (std::memcmp(bytes.data() + pos, "fmt ", 4) == 0 && body + 16 <= bytes.size()) {
            format = u16(body);
            channels = u16(body + 2);
            rate = u32(body + 4);
            bits = u16(body + 14);
        } else if (std::memcmp(bytes.data() + pos, "data", 4) == 0) {
            dataOffset = body;
            dataSize = std::min(size, bytes.size() - body);
            break;
        }
        pos = body + size + (size & 1);
    }
    if (dataOffset == 0 || rate != 16000 || (channels != 1 && channels != 2)) {
        outProblem = "audio must be 16 kHz mono or stereo";
        return false;
    }
    const bool isFloat = format == 3 && bits == 32;
    const bool isPcm16 = format == 1 && bits == 16;
    if (!isFloat && !isPcm16) {
        outProblem = "audio must be float32 or 16-bit PCM";
        return false;
    }
    const std::size_t bytesPerSample = isFloat ? 4 : 2;
    const std::size_t frames = dataSize / (bytesPerSample * channels);
    outSamples.resize(frames);
    for (std::size_t f = 0; f < frames; ++f) {
        float sum = 0.0f;
        for (std::size_t c = 0; c < channels; ++c) {
            const std::size_t o = dataOffset + (f * channels + c) * bytesPerSample;
            if (isFloat) {
                float v;
                std::memcpy(&v, bytes.data() + o, 4);
                sum += v;
            } else {
                sum += static_cast<float>(static_cast<std::int16_t>(u16(o))) / 32768.0f;
            }
        }
        outSamples[f] = sum / static_cast<float>(channels);
    }
    return true;
}

int runTranscribe(int argc, char** argv)
{
    std::string model, audio, deviceArg, instrumentArg;
    int threads = 0;
    bool preludeForcing = true;
#if defined(__x86_64__)
    deviceArg = "cpu";
#else
    deviceArg = "auto";
#endif
    for (int i = 2; i < argc; ++i) {
        const std::string flag = argv[i];
        auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : std::string(); };
        if (flag == "--model") model = next();
        else if (flag == "--audio") audio = next();
        else if (flag == "--device") deviceArg = next();
        else if (flag == "--threads") threads = std::atoi(next().c_str());
        else if (flag == "--instruments") instrumentArg = next();
        else if (flag == "--no-prelude-forcing") preludeForcing = false;
        else return fail("InvalidArgument", "unknown flag " + flag);
    }
    if (model.empty() || audio.empty()) {
        return fail("InvalidArgument", "--model and --audio are required");
    }

    std::vector<msl::InstrumentGroup> instruments;
    if (!instrumentArg.empty()) {
        std::size_t start = 0;
        while (start <= instrumentArg.size()) {
            const std::size_t comma = instrumentArg.find(',', start);
            const std::string name = instrumentArg.substr(start, comma == std::string::npos ? std::string::npos : comma - start);
            bool found = false;
            for (const auto group : msl::allInstrumentGroups()) {
                if (msl::instrumentName(group) == name) {
                    instruments.push_back(group);
                    found = true;
                }
            }
            if (!found) {
                return fail("InvalidArgument", "unknown instrument " + name);
            }
            if (comma == std::string::npos) break;
            start = comma + 1;
        }
    }

    std::vector<float> samples;
    std::string problem;
    if (!readAudio(audio, samples, problem)) {
        return fail("InvalidArgument", problem);
    }

    // A line on stdin asks for a stop. When stdin is the app's pipe, its end means the app has gone, which stops the run
    // too; a terminal or /dev/null on stdin never stops it.
    struct stat stdinInfo {};
    const bool fromHost = fstat(STDIN_FILENO, &stdinInfo) == 0 && S_ISFIFO(stdinInfo.st_mode);
    std::signal(SIGTERM, onSigterm);
    std::thread([fromHost] {
        std::string line;
        while (std::getline(std::cin, line)) {
            gCancel.store(true);
        }
        if (fromHost) gCancel.store(true);
    }).detach();

    msl::LoadOptions load;
    load.should_cancel = [] { return gCancel.load(); };
    load.on_progress = [](float p) { emit("{\"type\":\"load\",\"progress\":" + std::to_string(p) + "}"); };
    const auto devices = msl::availableDevices();
    if (deviceArg == "cpu") {
        for (std::size_t i = 0; i < devices.size(); ++i) {
            if (devices[i].backend == "CPU") load.device = i;
        }
    } else if (deviceArg != "auto") {
        const long index = std::atol(deviceArg.c_str());
        if (index < 0 || static_cast<std::size_t>(index) >= devices.size()) {
            return fail("InvalidArgument", "no such device " + deviceArg);
        }
        load.device = static_cast<std::size_t>(index);
    }

    auto transcriber = msl::Transcriber::load(model, load);
    if (!transcriber) return failWith(transcriber.error());

    const auto& active = transcriber->device();
    std::size_t activeIndex = 0;
    for (std::size_t i = 0; i < devices.size(); ++i) {
        if (devices[i].name == active.name && devices[i].backend == active.backend) activeIndex = i;
    }
    emit("{\"type\":\"ready\",\"device\":" + deviceJson(active, activeIndex) + ",\"chunks\":"
         + std::to_string(msl::Transcriber::chunkCount(samples.size())) + "}");

    msl::TranscribeOptions options;
    options.instruments = instruments;
    options.prelude_forcing = preludeForcing;
    options.n_threads = threads;
    options.should_cancel = [] { return gCancel.load(); };

    const auto result = transcriber->transcribe(samples, options, [](const msl::TranscriptionUpdate& update) {
        std::string line = "{\"type\":\"update\",\"progress\":" + std::to_string(update.progress)
            + ",\"finalized_through\":" + std::to_string(update.finalized_through) + ",\"notes\":[";
        bool first = true;
        for (const auto& note : update.new_notes) {
            line += std::string(first ? "" : ",") + "{\"onset\":" + std::to_string(note.onset)
                + ",\"offset\":" + std::to_string(note.offset) + ",\"pitch\":" + std::to_string(note.pitch)
                + ",\"program\":" + std::to_string(note.program) + ",\"is_drum\":" + (note.is_drum ? "true" : "false")
                + ",\"instrument\":" + str(msl::instrumentLabel(note.program)) + "}";
            first = false;
        }
        emit(line + "]}");
        return !gCancel.load();
    });
    if (!result) return failWith(result.error());

    emit("{\"type\":\"done\",\"note_count\":" + std::to_string(result->size()) + "}");
    return 0;
}

} // namespace

int main(int argc, char** argv)
{
    const std::string command = argc > 1 ? argv[1] : "";
    try {
        if (command == "devices") return runDevices();
        if (command == "instruments") return runInstruments();
        if (command == "transcribe") return runTranscribe(argc, argv);
    } catch (const msl::Exception& e) {
        return failWith(e.error());
    } catch (const std::exception& e) {
        return fail("Internal", e.what());
    }
    std::fprintf(stderr, "usage: %s devices | instruments | transcribe --model f.gguf --audio f [--device auto|cpu|N] [--threads N] [--instruments a,b] [--no-prelude-forcing]\n", argv[0]);
    return 64;
}
