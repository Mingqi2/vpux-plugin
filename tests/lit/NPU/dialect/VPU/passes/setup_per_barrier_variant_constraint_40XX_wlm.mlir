//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//


// RUN: vpux-opt --vpu-arch=%arch% --setup-per-barrier-variant-constraint="enable-partial-workload-management=true" %s | FileCheck %s
// REQUIRES: arch-NPU40XX

module @mainModule attributes { VPU.arch = #VPU.arch_kind<NPU40XX> } {
}

// CHECK: module @mainModule attributes
// CHECK: IE.PipelineOptions @Options
// CHECK: IE.Option @VPU.BarrierMaxVariantSum : 256
// CHECK: IE.Option @VPU.BarrierMaxVariantCount : 256