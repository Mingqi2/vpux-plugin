//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#pragma once

#include <string>

namespace vpux {

constexpr char LOCATION_LAYER_TYPE_PREFIX[] = "t";

//
// Prefix for ReadValue and Assign operations in IE dialect VPUX compiler.
//
#define READVALUE_PREFIX std::string("vpux_ie_read_value_")
#define ASSIGN_PREFIX std::string("vpux_ie_assign_")

inline bool isStateInputName(const std::string& name) {
    return !name.compare(0, READVALUE_PREFIX.length(), READVALUE_PREFIX);
}
inline bool isStateOutputName(const std::string& name) {
    return !name.compare(0, ASSIGN_PREFIX.length(), ASSIGN_PREFIX);
}

inline std::string stateOutputToStateInputName(const std::string& name) {
    return READVALUE_PREFIX + name.substr(ASSIGN_PREFIX.length());
}

}  // namespace vpux
