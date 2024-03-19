//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// IE
#include <cpp_interfaces/interface/ie_internal_plugin_config.hpp>
#include <ie_metric_helpers.hpp>
// Plugin
#include "device_helpers.hpp"
#include "vpux/properties.hpp"
#include "vpux_metrics.hpp"
#include "vpux_private_properties.hpp"

namespace vpux {

Metrics::Metrics(const VPUXBackends::CPtr& backends): _backends(backends) {
    _supportedMetrics = {ov::supported_properties.name(),
                         ov::available_devices.name(),
                         ov::device::full_name.name(),
                         ov::device::capabilities.name(),
                         ov::range_for_async_infer_requests.name(),
                         ov::range_for_streams.name(),
                         ov::device::capability::EXPORT_IMPORT,
                         ov::device::architecture.name(),
                         ov::internal::caching_properties.name(),
                         ov::internal::supported_properties.name(),
                         ov::cache_dir.name(),
                         ov::intel_vpux::device_alloc_mem_size.name(),
                         ov::intel_vpux::device_total_mem_size.name(),
                         ov::intel_vpux::driver_version.name()};

    _supportedConfigKeys = {ov::log::level.name(),
                            ov::enable_profiling.name(),
                            ov::device::id.name(),
                            ov::hint::performance_mode.name(),
                            ov::num_streams.name(),
                            ov::hint::num_requests.name(),
                            ov::intel_vpux::compilation_mode_params.name()};
}

std::vector<std::string> Metrics::GetAvailableDevicesNames() const {
    return _backends == nullptr ? std::vector<std::string>() : _backends->getAvailableDevicesNames();
}

// TODO each backend may support different metrics
const std::vector<std::string>& Metrics::SupportedMetrics() const {
    return _supportedMetrics;
}

std::string Metrics::GetFullDeviceName(const std::string& specifiedDeviceName) const {
    const auto devName = getDeviceName(specifiedDeviceName);
    auto device = _backends->getDevice(devName);
    if (device) {
        return device->getFullDeviceName();
    }
    OPENVINO_THROW("No device with name '", specifiedDeviceName, "' is available");
}

// TODO each backend may support different configs
const std::vector<std::string>& Metrics::GetSupportedConfigKeys() const {
    return _supportedConfigKeys;
}

// TODO each backend may support different optimization capabilities
const std::vector<std::string>& Metrics::GetOptimizationCapabilities() const {
    return _optimizationCapabilities;
}

const std::tuple<uint32_t, uint32_t, uint32_t>& Metrics::GetRangeForAsyncInferRequest() const {
    return _rangeForAsyncInferRequests;
}

const std::tuple<uint32_t, uint32_t>& Metrics::GetRangeForStreams() const {
    return _rangeForStreams;
}

std::string Metrics::GetDeviceArchitecture(const std::string& specifiedDeviceName) const {
    const auto devName = getDeviceName(specifiedDeviceName);
    return utils::getPlatformNameByDeviceName(devName);
}

Uuid Metrics::GetDeviceUuid(const std::string& specifiedDeviceName) const {
    const auto devName = getDeviceName(specifiedDeviceName);
    auto device = _backends->getDevice(devName);
    if (device) {
        return device->getUuid();
    }
    return Uuid{};
}

std::vector<ov::PropertyName> Metrics::GetCachingProperties() const {
    return _cachingProperties;
}

std::vector<ov::PropertyName> Metrics::GetInternalSupportedProperties() const {
    return _internalSupportedProperties;
}

std::string Metrics::GetBackendName() const {
    if (_backends == nullptr) {
        OPENVINO_THROW("No available backends");
    }

    return _backends->getBackendName();
}

uint64_t Metrics::GetDeviceAllocMemSize(const std::string& specifiedDeviceName) const {
    const auto devName = getDeviceName(specifiedDeviceName);
    auto device = _backends->getDevice(devName);
    if (device) {
        return device->getAllocMemSize();
    }
    OPENVINO_THROW("No device with name '", specifiedDeviceName, "' is available");
}

uint64_t Metrics::GetDeviceTotalMemSize(const std::string& specifiedDeviceName) const {
    const auto devName = getDeviceName(specifiedDeviceName);
    auto device = _backends->getDevice(devName);
    if (device) {
        return device->getTotalMemSize();
    }
    OPENVINO_THROW("No device with name '", specifiedDeviceName, "' is available");
}

uint32_t Metrics::GetDriverVersion(const std::string& specifiedDeviceName) const {
    const auto devName = getDeviceName(specifiedDeviceName);
    auto device = _backends->getDevice(devName);
    if (device) {
        return device->getDriverVersion();
    }
    OPENVINO_THROW("No device with name '", specifiedDeviceName, "' is available");
}

std::string Metrics::getDeviceName(const std::string& specifiedDeviceName) const {
    std::vector<std::string> devNames;
    if (_backends == nullptr || (devNames = _backends->getAvailableDevicesNames()).empty()) {
        OPENVINO_THROW("No available devices");
    }

    // In case of single device and empty input from user we should use the first element from the device list
    if (specifiedDeviceName.empty()) {
        if (devNames.size() == 1) {
            return devNames[0];
        } else {
            OPENVINO_THROW("The device name was not specified. Please specify device name by providing DEVICE_ID");
        }
    }

    // In case of multiple devices and non-empty input from user we have to check if such device exists in system
    // First, check format "platform.slice_id"
    if (std::find(devNames.cbegin(), devNames.cend(), specifiedDeviceName) == devNames.cend()) {
        // Second, check format "platform"
        const auto userPlatform = utils::getPlatformByDeviceName(specifiedDeviceName);
        const auto platformIt = std::find_if(devNames.cbegin(), devNames.cend(), [=](const std::string& devName) {
            const auto devPlatform = utils::getPlatformByDeviceName(devName);
            return userPlatform == devPlatform;
        });
        if (platformIt == devNames.cend()) {
            OPENVINO_THROW("List of system devices doesn't contain specified device ", specifiedDeviceName);
        }
    }

    return specifiedDeviceName;
}

}  // namespace vpux
