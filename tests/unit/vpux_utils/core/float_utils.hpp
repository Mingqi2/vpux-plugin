//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//
#pragma once
#include <algorithm>
#include <bitset>
#include <cassert>
#include <climits>
#include <cmath>
#include <map>
#include <numeric>
#include <sstream>
#include <string>
#include <vector>

#include "vpux/utils/core/type/bfloat16.hpp"
#include "vpux/utils/core/type/float16.hpp"

namespace vpux {
namespace type {
namespace utils {
union DoubleUnion {
    DoubleUnion() {
        i = 0;
    }
    DoubleUnion(double val) {
        d = val;
    }
    DoubleUnion(uint64_t val) {
        i = val;
    }
    double d;
    uint64_t i;
};

union FloatUnion {
    FloatUnion() {
        i = 0;
    }
    FloatUnion(float val) {
        f = val;
    }
    FloatUnion(uint32_t val) {
        i = val;
    }
    FloatUnion(uint32_t s, uint32_t e, uint32_t f): FloatUnion(s << 31 | e << 23 | f) {
    }
    float f;
    uint32_t i;
};

std::string bfloat16_to_bits(vpux::type::bfloat16 f);
std::string float16_to_bits(vpux::type::float16 f);
std::string float_to_bits(float f);
std::string double_to_bits(double d);
float bits_to_float(const std::string& s);
double bits_to_double(const std::string& s);
vpux::type::bfloat16 bits_to_bfloat16(const std::string& s);
vpux::type::float16 bits_to_float16(const std::string& s);
}  // namespace utils
}  // namespace type
}  // namespace vpux
