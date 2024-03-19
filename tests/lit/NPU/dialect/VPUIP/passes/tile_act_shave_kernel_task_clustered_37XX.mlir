//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch% compilation-mode=DefaultHW" --tile-act-shave-kernel-task --canonicalize %s | FileCheck %s
// REQUIRES: arch-VPUX37XX

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NWHC = affine_map<(d0, d1, d2, d3) -> (d0, d3, d2, d1)>

module @VPU.SW {
  func.func private @builtin_MVN(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "singleShaveMVN.cpp", VPU.kernel_entry = "singleShaveMVN"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterStridedMVN(%arg0: memref<1x128x64x32xf16, #NWHC>)
        -> memref<1x128x64x32xf16, #NWHC> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16, #NWHC>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, #NWHC>) outputs(%arg2 : memref<1x128x64x32xf16, #NWHC, @CMX_NN>) -> memref<1x128x64x32xf16, #NWHC, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) outputs(%3 as %arg2: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_MVN inputs(%arg1 as %arg3: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) on tile 0 -> memref<1x128x64x32xf16, #NWHC, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg3, %arg4) : memref<1x128x64x32xf16, #NWHC, @CMX_NN>, memref<1x128x64x32xf16, #NWHC, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x64x32xf16, #NWHC>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) outputs(%5 as %arg2: memref<1x128x64x32xf16, #NWHC>) -> memref<1x128x64x32xf16, #NWHC> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, #NWHC, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16, #NWHC>) -> memref<1x128x64x32xf16, #NWHC>
    }
    return %6: memref<1x128x64x32xf16, #NWHC>


    // CHECK:    [[INPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16, #NWHC>) outputs([[INPUT_CMX]] as %arg2: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, #NWHC>) outputs(%arg2 : memref<1x128x64x32xf16, #NWHC, @CMX_NN>) -> memref<1x128x64x32xf16, #NWHC, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView [[COPY0]] [0, 64, 0, 0] [1, 64, 64, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView [[COPY0]] [0, 0, 0, 0] [1, 64, 64, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 64, 0, 0] [1, 64, 64, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 0, 0, 0] [1, 64, 64, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[MVN:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>, [[SUBVIEW0]] as %arg2: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>) outputs([[SUBVIEW3]] as %arg3: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>, [[SUBVIEW2]] as %arg4: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>) {
    // CHECK{LITERAL}:      %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_MVN inputs(%arg1 as %arg5: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>, %arg2 as %arg6: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>, %arg4 as %arg8: memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>) strides([[262144, 1, 128, 8192], [262144, 1, 128, 8192]]) on tile 0 -> (memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>, memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>){
    // CHECK:        VPUIP.SW.Kernel.run {attrs  = [false, true, 6.0892105102539063E-4]}(%arg5, %arg7) : memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>, memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg6, %arg8) : memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>, memref<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN>
    // CHECK:      }
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[MVN]]#0, [[MVN]]#1 : !VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x64x64x32xf16, {order = #NWHC, strides = [262144, 1, 128, 8192]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>) outputs(%4 : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NWHC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[BUFF_OUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16, #NWHC>
    // CHECK:    [[COPY_OUTPUT_TO_DDR:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCAT]] as %arg1: memref<1x128x64x32xf16, #NWHC, @CMX_NN>) outputs([[BUFF_OUT_DDR]] as %arg2: memref<1x128x64x32xf16, #NWHC>) -> memref<1x128x64x32xf16, #NWHC> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, #NWHC, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16, #NWHC>) -> memref<1x128x64x32xf16, #NWHC>
    // CHECK:    }
    // CHECK:    return [[COPY_OUTPUT_TO_DDR]] : memref<1x128x64x32xf16, #NWHC>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_MVN(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "singleShaveMVN.cpp", VPU.kernel_entry = "singleShaveMVN"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileNoSymmetricClusterStridedMVNWithNCHW(%arg0: memref<1x33x16x1xf16>)
        -> memref<1x33x16x1xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x33x16x1xf16>) outputs(%0 as %arg2: memref<1x33x16x1xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x33x16x1xf16>) outputs(%arg2 : memref<1x33x16x1xf16, @CMX_NN>) -> memref<1x33x16x1xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x33x16x1xf16, @CMX_NN>) outputs(%3 as %arg2: memref<1x33x16x1xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_MVN inputs(%arg1 as %arg3: memref<1x33x16x1xf16, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x33x16x1xf16, @CMX_NN>) on tile 0 -> memref<1x33x16x1xf16, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg3, %arg4) : memref<1x33x16x1xf16, @CMX_NN>, memref<1x33x16x1xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x33x16x1xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x33x16x1xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x33x16x1xf16>) -> memref<1x33x16x1xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x33x16x1xf16, @CMX_NN>) outputs(%arg2 : memref<1x33x16x1xf16>) -> memref<1x33x16x1xf16>
    }
    return %6: memref<1x33x16x1xf16>


    // CHECK:    [[INPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x33x16x1xf16>) outputs([[INPUT_CMX]] as %arg2: memref<1x33x16x1xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x33x16x1xf16>) outputs(%arg2 : memref<1x33x16x1xf16, @CMX_NN>) -> memref<1x33x16x1xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView [[COPY0]] [0, 16, 0, 0] [1, 17, 16, 1] : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView [[COPY0]] [0, 0, 0, 0] [1, 16, 16, 1] : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 16, 0, 0] [1, 17, 16, 1] : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 0, 0, 0] [1, 16, 16, 1] : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[MVN:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>, [[SUBVIEW0]] as %arg2: memref<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>) outputs([[SUBVIEW3]] as %arg3: memref<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>, [[SUBVIEW2]] as %arg4: memref<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>) {
    // CHECK{LITERAL}:      results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_MVN inputs(%arg1 as %arg5: memref<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>, %arg2 as %arg6: memref<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>, %arg4 as %arg8: memref<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>) strides([[272, 16, 1, 1], [256, 16, 1, 1]]) on tile 0 -> (memref<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>, memref<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>){
    // CHECK:                          VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg5, %arg7) : memref<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>, memref<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>
    // CHECK:                          VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg6, %arg8) : memref<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>, memref<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN>
    // CHECK:               }
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]]  = VPUIP.ConcatView inputs([[MVN]]#0, [[MVN]]#1 : !VPUIP.DistributedBuffer<1x16x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x17x16x1xf16, {order = #NCHW, strides = [528, 16, 1, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>) outputs(%4 : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x33x16x1xf16>
    // CHECK:    [[COPY1:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCAT]] as %arg1: memref<1x33x16x1xf16, @CMX_NN>) outputs([[OUTPUT_DDR]] as %arg2: memref<1x33x16x1xf16>) -> memref<1x33x16x1xf16> {
    // CHECK:                          VPUIP.Copy inputs(%arg1 : memref<1x33x16x1xf16, @CMX_NN>) outputs(%arg2 : memref<1x33x16x1xf16>) -> memref<1x33x16x1xf16>
    // CHECK:    }
    // CHECK:    return [[COPY1]] : memref<1x33x16x1xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW {
  func.func private @builtin_MVN(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "singleShaveMVN.cpp", VPU.kernel_entry = "singleShaveMVN"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileNoSymmetricClusterStridedMVNWithNHWC(%arg0: memref<1x33x16x1xf16, #NHWC>)
        -> memref<1x33x16x1xf16, #NHWC> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x33x16x1xf16, #NHWC>) outputs(%0 as %arg2: memref<1x33x16x1xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x33x16x1xf16, #NHWC>) outputs(%arg2 : memref<1x33x16x1xf16, #NHWC, @CMX_NN>) -> memref<1x33x16x1xf16, #NHWC, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x33x16x1xf16, #NHWC, @CMX_NN>) outputs(%3 as %arg2: memref<1x33x16x1xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_MVN inputs(%arg1 as %arg3: memref<1x33x16x1xf16, #NHWC, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x33x16x1xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x33x16x1xf16, #NHWC, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg3, %arg4) : memref<1x33x16x1xf16, #NHWC, @CMX_NN>, memref<1x33x16x1xf16, #NHWC, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x33x16x1xf16, #NHWC>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x33x16x1xf16, #NHWC, @CMX_NN>) outputs(%5 as %arg2: memref<1x33x16x1xf16, #NHWC>) -> memref<1x33x16x1xf16, #NHWC> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x33x16x1xf16, #NHWC, @CMX_NN>) outputs(%arg2 : memref<1x33x16x1xf16, #NHWC>) -> memref<1x33x16x1xf16, #NHWC>
    }
    return %6: memref<1x33x16x1xf16, #NHWC>


    // CHECK:    [[INPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x33x16x1xf16, #NHWC>) outputs([[INPUT_CMX]] as %arg2: memref<1x33x16x1xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> {
    // CHECK:             VPUIP.Copy inputs(%arg1 : memref<1x33x16x1xf16, #NHWC>) outputs(%arg2 : memref<1x33x16x1xf16, #NHWC, @CMX_NN>) -> memref<1x33x16x1xf16, #NHWC, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView [[COPY0]] [0, 16, 0, 0] [1, 17, 16, 1] : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x17x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView [[COPY0]] [0, 0, 0, 0] [1, 16, 16, 1] : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x16x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 16, 0, 0] [1, 17, 16, 1] : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x17x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 0, 0, 0] [1, 16, 16, 1] : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x16x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[MVN:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x16x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN>, [[SUBVIEW0]] as %arg2: memref<1x17x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN>) outputs([[SUBVIEW3]] as %arg3: memref<1x16x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN>, [[SUBVIEW2]] as %arg4: memref<1x17x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x16x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x17x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>) {
    // CHECK:                     VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_MVN inputs(%arg1 as %arg5: memref<1x16x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN>, %arg2 as %arg6: memref<1x17x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x16x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN>, %arg4 as %arg8: memref<1x17x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN>)
    // CHECK{LITERAL}:              strides([[272, 1, 17, 17], [256, 1, 16, 16]]) on tile 0 -> (memref<1x16x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN>, memref<1x17x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN>){
    // CHECK:                         VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg5, %arg7) : memref<1x16x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN>, memref<1x16x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN>
    // CHECK:                         VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg6, %arg8) : memref<1x17x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN>, memref<1x17x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN>
    // CHECK:                     }
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[MVN]]#0, [[MVN]]#1 : !VPUIP.DistributedBuffer<1x16x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x17x16x1xf16, {order = #NHWC, strides = [528, 1, 33, 33]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>) outputs(%4 : !VPUIP.DistributedBuffer<1x33x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x33x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x33x16x1xf16, #NHWC>
    // CHECK:    [[COPY1:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCAT]] as %arg1: memref<1x33x16x1xf16, #NHWC, @CMX_NN>) outputs([[OUTPUT_DDR]] as %arg2: memref<1x33x16x1xf16, #NHWC>) -> memref<1x33x16x1xf16, #NHWC> {
    // CHECK:                         VPUIP.Copy inputs(%arg1 : memref<1x33x16x1xf16, #NHWC, @CMX_NN>) outputs(%arg2 : memref<1x33x16x1xf16, #NHWC>) -> memref<1x33x16x1xf16, #NHWC>
    // CHECK:    }
    // CHECK:    return [[COPY1]] : memref<1x33x16x1xf16, #NHWC>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_MVN(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "singleShaveMVN.cpp", VPU.kernel_entry = "singleShaveMVN"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @NotTileClusterMVNForUnalignedShape(%arg0: memref<1x32x1x10240xf16>)
        -> memref<1x32x1x10240xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x32x1x10240xf16>) outputs(%0 as %arg2: memref<1x32x1x10240xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x32x1x10240xf16>) outputs(%arg2 : memref<1x32x1x10240xf16, @CMX_NN>) -> memref<1x32x1x10240xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x32x1x10240xf16, @CMX_NN>) outputs(%3 as %arg2: memref<1x32x1x10240xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_MVN inputs(%arg1 as %arg3: memref<1x32x1x10240xf16, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x32x1x10240xf16, @CMX_NN>) on tile 0 -> memref<1x32x1x10240xf16, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg3, %arg4) : memref<1x32x1x10240xf16, @CMX_NN>, memref<1x32x1x10240xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x32x1x10240xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x32x1x10240xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x32x1x10240xf16>) -> memref<1x32x1x10240xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x32x1x10240xf16, @CMX_NN>) outputs(%arg2 : memref<1x32x1x10240xf16>) -> memref<1x32x1x10240xf16>
    }
    return %6: memref<1x32x1x10240xf16>

    // CHECK:    [[INPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x32x1x10240xf16>) outputs([[INPUT_CMX]] as %arg2: memref<1x32x1x10240xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x32x1x10240xf16>) outputs(%arg2 : memref<1x32x1x10240xf16, @CMX_NN>) -> memref<1x32x1x10240xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>
    // CHECK:    [[MVN:%.*]] = VPUIP.NCEClusterTiling inputs([[COPY0]] as %arg1: memref<1x32x1x10240xf16, @CMX_NN>) outputs([[OUTPUT_CMX]] as %arg2: memref<1x32x1x10240xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x32x1x10240xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}> {
    // CHECK:      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_MVN inputs(%arg1 as %arg3: memref<1x32x1x10240xf16, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x32x1x10240xf16, @CMX_NN>) on tile 0 -> memref<1x32x1x10240xf16, @CMX_NN>{
    // CHECK:        VPUIP.SW.Kernel.run {attrs = [false, true, 6.0892105102539063E-4]}(%arg3, %arg4) : memref<1x32x1x10240xf16, @CMX_NN>, memref<1x32x1x10240xf16, @CMX_NN>
    // CHECK:      }
    // CHECK:    }
    // CHECK:    [[BUFF_OUT_DDR:%.*]] = memref.alloc() : memref<1x32x1x10240xf16>
    // CHECK:    [[COPY_OUTPUT_TO_DDR:%.*]] = VPUIP.NCEClusterTiling inputs([[MVN]] as %arg1: memref<1x32x1x10240xf16, @CMX_NN>) outputs([[BUFF_OUT_DDR]] as %arg2: memref<1x32x1x10240xf16>) -> memref<1x32x1x10240xf16> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x32x1x10240xf16, @CMX_NN>) outputs(%arg2 : memref<1x32x1x10240xf16>) -> memref<1x32x1x10240xf16>
    // CHECK:    }
    // CHECK:    return [[COPY_OUTPUT_TO_DDR]] : memref<1x32x1x10240xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
    func.func private @builtin_Interpolate(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i64, i64, i64, i64, none, none, none, none, none) attributes {VPU.kernel_code = "single_shave_interpolate.cpp", VPU.kernel_entry = "singleShaveInterpolate"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterHalfPixelInterpolate(%arg0: memref<1x1x96x160xf16>) -> memref<1x1x192x320xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]], memory_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]]}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg2: memref<1x1x96x160xf16>) outputs(%0 as %arg3: memref<1x1x96x160xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x1x96x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]], memory_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]]}> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x1x96x160xf16>) outputs(%arg3 : memref<1x1x96x160xf16, @CMX_NN>) -> memref<1x1x96x160xf16, @CMX_NN>
    }
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x192x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %3 = VPUIP.NCEClusterTiling inputs(%1 as %arg2: memref<1x1x96x160xf16, @CMX_NN>) outputs(%2 as %arg3: memref<1x1x192x320xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x1x192x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Interpolate inputs(%arg2 as %arg4: memref<1x1x96x160xf16, @CMX_NN>) outputs(%arg3 as %arg5: memref<1x1x192x320xf16, @CMX_NN>) on tile 0 -> memref<1x1x192x320xf16, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [2, 0, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg4, %arg5) : memref<1x1x96x160xf16, @CMX_NN>, memref<1x1x192x320xf16, @CMX_NN>
      }
    }
    %4 = memref.alloc() : memref<1x1x192x320xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg2: memref<1x1x192x320xf16, @CMX_NN>) outputs(%4 as %arg3: memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x1x192x320xf16, @CMX_NN>) outputs(%arg3 : memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16>
    }
    return %5 : memref<1x1x192x320xf16>

    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView %arg0 [0, 0, 47, 0] [1, 1, 49, 160] : memref<1x1x96x160xf16> to memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>
    // CHECK:    [[INPUT_BUF0:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME{LITERAL}:     VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 26, 160], [1, 1, 25, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 24, 0]], memory_shapes = [[1, 1, 26, 160], [1, 1, 25, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 24, 0]]}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW0]] as %arg1: memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs([[INPUT_BUF0]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs(%arg2 : memref<1x1x49x160xf16, @CMX_NN>) -> memref<1x1x49x160xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView %arg0 [0, 0, 0, 0] [1, 1, 49, 160] : memref<1x1x96x160xf16> to memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>
    // CHECK:    [[INPUT_BUF1:%.*]] = VPURT.AllocDistributed ->
    // CHECK-SAME{LITERAL}:     !VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 25, 160], [1, 1, 26, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0]], memory_shapes = [[1, 1, 25, 160], [1, 1, 26, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 23, 0]]}>
    // CHECK:    [[COPY1:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs([[INPUT_BUF1]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs(%arg2 : memref<1x1x49x160xf16, @CMX_NN>) -> memref<1x1x49x160xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[CLUSTER_INTERPOLATE:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[COPY1]] as %arg1: memref<1x1x49x160xf16, @CMX_NN>, [[COPY0]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>) outputs([[OUTPUT_BUF0]] as %arg3: memref<1x1x96x320xf16, @CMX_NN>, [[OUTPUT_BUF1]] as %arg4: memref<1x1x96x320xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                   %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Interpolate inputs(%arg1 as %arg5: memref<1x1x49x160xf16, @CMX_NN>, %arg2 as %arg6: memref<1x1x49x160xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x1x96x320xf16, @CMX_NN>, %arg4 as %arg8: memref<1x1x96x320xf16, @CMX_NN>) on tile 0 -> (memref<1x1x96x320xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>){
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = [2, 0, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg5, %arg7) : memref<1x1x49x160xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = [2, 0, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 47, 0, 0], [0, 96, 0, 0]]}(%arg6, %arg8) : memref<1x1x49x160xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>
    // CHECK:                   }
    // CHECK:    }
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x1x192x320xf16>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 1, 96, 320] : memref<1x1x192x320xf16> to memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    [[COPY2:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_INTERPOLATE]]#0 as %arg1: memref<1x1x96x320xf16, @CMX_NN>) outputs([[SUBVIEW2]] as %arg2: memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x1x96x320xf16, @CMX_NN>) outputs(%arg2 : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    }
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 96, 0] [1, 1, 96, 320] : memref<1x1x192x320xf16> to memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    [[COPY3:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_INTERPOLATE]]#1 as %arg1: memref<1x1x96x320xf16, @CMX_NN>) outputs([[SUBVIEW3]] as %arg2: memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x1x96x320xf16, @CMX_NN>) outputs(%arg2 : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[COPY2]], [[COPY3]] : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>, memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) outputs([[OUTPUT_DDR]] : memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16>
    // CHECK:    return [[CONCAT]] : memref<1x1x192x320xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

!InputDistributedBuffer = !VPUIP.DistributedBuffer<
    1x1x96x160xf16, #NCHW, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2 : i64,
    compute_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]],
    memory_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]]
}>

!OutputDistributedBuffer = !VPUIP.DistributedBuffer<
    1x1x192x320xf16, #NCHW, @CMX_NN, {
    mode = "SEGMENTED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2 : i64,
    compute_shapes = [[1, 1, 96, 320], [1, 1, 96, 320]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 96, 0]],
    memory_shapes = [[1, 1, 96, 320], [1, 1, 96, 320]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 96, 0]]
}>

module @VPU.SW {
    func.func private @builtin_Interpolate(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i64, i64, i64, i64, none, none, none, none, none) attributes {VPU.kernel_code = "single_shave_interpolate.cpp", VPU.kernel_entry = "singleShaveInterpolate"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

// CHECK-LABEL: @TileClusterHalfPixelInterpolateWithExplicitDistribution
// CHECK-SAME: ([[ARG0:%.+]]: memref<1x1x96x160xf16>)
func.func @TileClusterHalfPixelInterpolateWithExplicitDistribution(%arg0: memref<1x1x96x160xf16>) -> memref<1x1x192x320xf16> {
    %0 = VPURT.AllocDistributed -> !InputDistributedBuffer
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg2: memref<1x1x96x160xf16>) outputs(%0 as %arg3: memref<1x1x96x160xf16, @CMX_NN>)
        -> !InputDistributedBuffer {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x1x96x160xf16>) outputs(%arg3 : memref<1x1x96x160xf16, @CMX_NN>) -> memref<1x1x96x160xf16, @CMX_NN>
    }
    %2 = VPURT.AllocDistributed -> !OutputDistributedBuffer
    %3 = VPUIP.NCEClusterTiling inputs(%1 as %arg2: memref<1x1x96x160xf16, @CMX_NN>) outputs(%2 as %arg3: memref<1x1x192x320xf16, @CMX_NN>)
        -> !OutputDistributedBuffer {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Interpolate
        inputs(%arg2 as %arg4: memref<1x1x96x160xf16, @CMX_NN>) outputs(%arg3 as %arg5: memref<1x1x192x320xf16, @CMX_NN>) on tile 0
          -> memref<1x1x192x320xf16, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [2, 0, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg4, %arg5) : memref<1x1x96x160xf16, @CMX_NN>, memref<1x1x192x320xf16, @CMX_NN>
      }
    }

    %4 = memref.alloc() : memref<1x1x192x320xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg2: memref<1x1x192x320xf16, @CMX_NN>) outputs(%4 as %arg3: memref<1x1x192x320xf16>)
        -> memref<1x1x192x320xf16> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x1x192x320xf16, @CMX_NN>) outputs(%arg3 : memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16>
    }
    return %5 : memref<1x1x192x320xf16>

    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView [[ARG0]] [0, 0, 47, 0] [1, 1, 49, 160] :
    // CHECK-SAME:  memref<1x1x96x160xf16> to memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>

    // CHECK:    [[INPUT_BUF0:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME:     -> !VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN,
    // CHECK-SAME:         {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64,
    // CHECK-SAME{LITERAL}: compute_shapes = [[1, 1, 26, 160], [1, 1, 25, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 24, 0]],
    // CHECK-SAME{LITERAL}: memory_shapes = [[1, 1, 26, 160], [1, 1, 25, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 24, 0]]}>

    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:  inputs([[SUBVIEW0]] as [[IN_ARG0:%.*]]: memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>)
    // CHECK-SAME:  outputs([[INPUT_BUF0]] as [[IN_ARG1:%.*]]: memref<1x1x49x160xf16, @CMX_NN>)
    // CHECK-NEXT:     VPUIP.Copy

    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView [[ARG0]] [0, 0, 0, 0] [1, 1, 49, 160] :
    // CHECK-SAME:  memref<1x1x96x160xf16> to memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>

    // CHECK:    [[INPUT_BUF1:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME:     -> !VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN,
    // CHECK-SAME:         {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64,
    // CHECK-SAME{LITERAL}: compute_shapes = [[1, 1, 25, 160], [1, 1, 26, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0]],
    // CHECK-SAME{LITERAL}: memory_shapes = [[1, 1, 25, 160], [1, 1, 26, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 23, 0]]}>

    // CHECK:    [[COPY1:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:  inputs([[SUBVIEW1]] as [[IN_ARG2:%.*]]: memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>)
    // CHECK-SAME:  outputs([[INPUT_BUF1]] as [[IN_ARG3:%.*]]: memref<1x1x49x160xf16, @CMX_NN>)
    // CHECK-NEXT:     VPUIP.Copy

    // CHECK:    [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME:     -> !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN,
    // CHECK-SAME:         {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}: compute_shapes = [[1, 1, 48, 320], [1, 1, 48, 320]], compute_offsets = [[0, 0, 0, 0], [0, 0, 48, 0]],
    // CHECK-SAME{LITERAL}: memory_shapes = [[1, 1, 48, 320], [1, 1, 48, 320]], memory_offsets = [[0, 0, 0, 0], [0, 0, 48, 0]]}>

    // CHECK:    [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME:    -> !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN,
    // CHECK-SAME:         {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}: compute_shapes = [[1, 1, 48, 320], [1, 1, 48, 320]], compute_offsets = [[0, 0, 0, 0], [0, 0, 48, 0]],
    // CHECK-SAME{LITERAL}: memory_shapes = [[1, 1, 48, 320], [1, 1, 48, 320]], memory_offsets = [[0, 0, 0, 0], [0, 0, 48, 0]]}>

    // CHECK:    [[CLUSTER_INTERPOLATE:%.*]]:2 = VPUIP.NCEClusterTiling
    // CHECK-SAME:    inputs([[COPY1]] as [[IN_ARG4:%.*]]: memref<1x1x49x160xf16, @CMX_NN>,
    // CHECK-SAME:           [[COPY0]] as [[IN_ARG5:%.*]]: memref<1x1x49x160xf16, @CMX_NN>)
    // CHECK-SAME:    outputs([[OUTPUT_BUF0]] as [[IN_ARG6:%.*]]: memref<1x1x96x320xf16, @CMX_NN>,
    // CHECK-SAME:            [[OUTPUT_BUF1]] as [[IN_ARG7:%.*]]: memref<1x1x96x320xf16, @CMX_NN>)
    // CHECK:       %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Interpolate
    // CHECK-SAME:      inputs([[IN_ARG4]] as [[IN_ARG8:%.*]]: memref<1x1x49x160xf16, @CMX_NN>,
    // CHECK-SAME:             [[IN_ARG5]] as [[IN_ARG9:%.*]]: memref<1x1x49x160xf16, @CMX_NN>)
    // CHECK-SAME:      outputs([[IN_ARG6]] as [[IN_ARG10:%.*]]: memref<1x1x96x320xf16, @CMX_NN>,
    // CHECK-SAME:              [[IN_ARG7]] as [[IN_ARG11:%.*]]: memref<1x1x96x320xf16, @CMX_NN>) on tile 0
    // CHECK-SAME:    -> (memref<1x1x96x320xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>){
    // CHECK:        VPUIP.SW.Kernel.run
    // CHECK-SAME:      {attrs = [2, 0, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}
    // CHECK-SAME:      ([[IN_ARG8]], [[IN_ARG10]]) : memref<1x1x49x160xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run
    // CHECK-SAME:      {attrs = [2, 0, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 47, 0, 0], [0, 96, 0, 0]]}
    // CHECK-SAME:      ([[IN_ARG9]], [[IN_ARG11]]) : memref<1x1x49x160xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>


    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x1x192x320xf16>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 1, 96, 320] :
    // CHECK-SAME:  memref<1x1x192x320xf16> to memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>

    // CHECK:    [[COPY2:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:  inputs([[CLUSTER_INTERPOLATE]]#0 as [[IN_ARG12:%.*]]: memref<1x1x96x320xf16, @CMX_NN>)
    // CHECK-SAME:  outputs([[SUBVIEW2]] as [[IN_ARG13:%.*]]: memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>)
    // CHECK-SAME:    -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}> {
    // CHECK-NEXT:           VPUIP.Copy

    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 96, 0] [1, 1, 96, 320] :
    // CHECK-SAME:    memref<1x1x192x320xf16> to memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>

    // CHECK:    [[COPY3:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:  inputs([[CLUSTER_INTERPOLATE]]#1 as [[IN_ARG14:%.*]]: memref<1x1x96x320xf16, @CMX_NN>)
    // CHECK-SAME:  outputs([[SUBVIEW3]] as [[IN_ARG15:%.*]]: memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>)
    // CHECK-SAME:    -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}> {
    // CHECK-NEXT:        VPUIP.Copy

    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView
    // CHECK-SAME:  inputs([[COPY2]], [[COPY3]] : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>,
    // CHECK-SAME:                                memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>)
    // CHECK-SAME:  outputs([[OUTPUT_DDR]] : memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16>

    // CHECK:    return [[CONCAT]] : memref<1x1x192x320xf16>
}


// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
    func.func private @builtin_Interpolate(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i64, i64, i64, i64, none, none, none, none, none) attributes {VPU.kernel_code = "single_shave_interpolate.cpp", VPU.kernel_entry = "singleShaveInterpolate"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterAlignCornersInterpolate(%arg0: memref<1x1x96x160xf16>) -> memref<1x1x192x320xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]], memory_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]]}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg2: memref<1x1x96x160xf16>) outputs(%0 as %arg3: memref<1x1x96x160xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x1x96x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]], memory_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]]}> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x1x96x160xf16>) outputs(%arg3 : memref<1x1x96x160xf16, @CMX_NN>) -> memref<1x1x96x160xf16, @CMX_NN>
    }
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x192x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %3 = VPUIP.NCEClusterTiling inputs(%1 as %arg2: memref<1x1x96x160xf16, @CMX_NN>) outputs(%2 as %arg3: memref<1x1x192x320xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x1x192x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Interpolate inputs(%arg2 as %arg4: memref<1x1x96x160xf16, @CMX_NN>) outputs(%arg3 as %arg5: memref<1x1x192x320xf16, @CMX_NN>) on tile 0 -> memref<1x1x192x320xf16, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [2, 4, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg4, %arg5) : memref<1x1x96x160xf16, @CMX_NN>, memref<1x1x192x320xf16, @CMX_NN>
      }
    }
    %4 = memref.alloc() : memref<1x1x192x320xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg2: memref<1x1x192x320xf16, @CMX_NN>) outputs(%4 as %arg3: memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x1x192x320xf16, @CMX_NN>) outputs(%arg3 : memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16>
    }
    return %5 : memref<1x1x192x320xf16>


    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView %arg0 [0, 0, 47, 0] [1, 1, 49, 160] : memref<1x1x96x160xf16> to memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>
    // CHECK:    [[INPUT_BUF0:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME{LITERAL}:     VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 26, 160], [1, 1, 25, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 24, 0]], memory_shapes = [[1, 1, 26, 160], [1, 1, 25, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 24, 0]]}>
    // CHECK:    [[COPY2:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW0]] as %arg1: memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs([[INPUT_BUF0]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs(%arg2 : memref<1x1x49x160xf16, @CMX_NN>) -> memref<1x1x49x160xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView %arg0 [0, 0, 0, 0] [1, 1, 49, 160] : memref<1x1x96x160xf16> to memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>
    // CHECK:    [[INPUT_BUF1:%.*]] = VPURT.AllocDistributed ->
    // CHECK-SAME{LITERAL}:     !VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 25, 160], [1, 1, 26, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0]], memory_shapes = [[1, 1, 25, 160], [1, 1, 26, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 23, 0]]}>
    // CHECK:    [[COPY4:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs([[INPUT_BUF1]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs(%arg2 : memref<1x1x49x160xf16, @CMX_NN>) -> memref<1x1x49x160xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[CLUSTER_INTERPOLATE:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[COPY4]] as %arg1: memref<1x1x49x160xf16, @CMX_NN>, [[COPY2]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>) outputs([[OUTPUT_BUF0]] as %arg3: memref<1x1x96x320xf16, @CMX_NN>, [[OUTPUT_BUF1]] as %arg4: memref<1x1x96x320xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                   %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Interpolate inputs(%arg1 as %arg5: memref<1x1x49x160xf16, @CMX_NN>, %arg2 as %arg6: memref<1x1x49x160xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x1x96x320xf16, @CMX_NN>, %arg4 as %arg8: memref<1x1x96x320xf16, @CMX_NN>) on tile 0 -> (memref<1x1x96x320xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>){
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = [2, 4, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg5, %arg7) : memref<1x1x49x160xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = [2, 4, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 47, 0, 0], [0, 96, 0, 0]]}(%arg6, %arg8) : memref<1x1x49x160xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>
    // CHECK:                   }
    // CHECK:    }
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x1x192x320xf16>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 1, 96, 320] : memref<1x1x192x320xf16> to memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    [[COPY5:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_INTERPOLATE]]#0 as %arg1: memref<1x1x96x320xf16, @CMX_NN>) outputs([[SUBVIEW2]] as %arg2: memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x1x96x320xf16, @CMX_NN>) outputs(%arg2 : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    }
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 96, 0] [1, 1, 96, 320] : memref<1x1x192x320xf16> to memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    [[COPY6:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_INTERPOLATE]]#1 as %arg1: memref<1x1x96x320xf16, @CMX_NN>) outputs([[SUBVIEW3]] as %arg2: memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x1x96x320xf16, @CMX_NN>) outputs(%arg2 : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[COPY5]], [[COPY6]] : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>, memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) outputs([[OUTPUT_DDR]] : memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16>
    // CHECK:    return [[CONCAT]] : memref<1x1x192x320xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
    func.func private @builtin_Interpolate(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i64, i64, i64, i64, none, none, none, none, none) attributes {VPU.kernel_code = "single_shave_interpolate.cpp", VPU.kernel_entry = "singleShaveInterpolate"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterPytorchHalfPixelInterpolate(%arg0: memref<1x1x96x160xf16>) -> memref<1x1x192x320xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]], memory_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]]}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg2: memref<1x1x96x160xf16>) outputs(%0 as %arg3: memref<1x1x96x160xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x1x96x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]], memory_shapes = [[1, 1, 49, 160], [1, 1, 49, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 47, 0]]}> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x1x96x160xf16>) outputs(%arg3 : memref<1x1x96x160xf16, @CMX_NN>) -> memref<1x1x96x160xf16, @CMX_NN>
    }
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x192x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // LINEAR_ONNX = 2, PYTORCH_HALF_PIXEL = 1
    %3 = VPUIP.NCEClusterTiling inputs(%1 as %arg2: memref<1x1x96x160xf16, @CMX_NN>) outputs(%2 as %arg3: memref<1x1x192x320xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x1x192x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Interpolate inputs(%arg2 as %arg4: memref<1x1x96x160xf16, @CMX_NN>) outputs(%arg3 as %arg5: memref<1x1x192x320xf16, @CMX_NN>) on tile 0 -> memref<1x1x192x320xf16, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [2, 1, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg4, %arg5) : memref<1x1x96x160xf16, @CMX_NN>, memref<1x1x192x320xf16, @CMX_NN>
      }
    }
    %4 = memref.alloc() : memref<1x1x192x320xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg2: memref<1x1x192x320xf16, @CMX_NN>) outputs(%4 as %arg3: memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x1x192x320xf16, @CMX_NN>) outputs(%arg3 : memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16>
    }
    return %5 : memref<1x1x192x320xf16>

    // CHECK:    [[INPUT_SUBVIEW1:%.*]] = VPUIP.SubView %arg0 [0, 0, 47, 0] [1, 1, 49, 160] : memref<1x1x96x160xf16> to memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>
    // CHECK:    [[INPUT_BUFF1:%.*]] = VPURT.AllocDistributed ->
    // CHECK-SAME{Literal}:            !VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 26, 160], [1, 1, 25, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 24, 0]], memory_shapes = [[1, 1, 26, 160], [1, 1, 25, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 24, 0]]}>
    // CHECK:    [[INPUT_COPY1:%.*]] = VPUIP.NCEClusterTiling inputs([[INPUT_SUBVIEW1]] as %arg1: memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs([[INPUT_BUFF1]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>) ->
    // CHECK-SAME{Literal}:            !VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 26, 160], [1, 1, 25, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 24, 0]], memory_shapes = [[1, 1, 26, 160], [1, 1, 25, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 24, 0]]}> {
    // CHECK:                                   VPUIP.Copy inputs(%arg1 : memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs(%arg2 : memref<1x1x49x160xf16, @CMX_NN>) -> memref<1x1x49x160xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[INPUT_SUBVIEW0:%.*]] = VPUIP.SubView %arg0 [0, 0, 0, 0] [1, 1, 49, 160] : memref<1x1x96x160xf16> to memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>
    // CHECK:    [[INPUT_BUFF0:%.*]] = VPURT.AllocDistributed ->
    // CHECK-SAME{Literal}:             !VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 25, 160], [1, 1, 26, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0]], memory_shapes = [[1, 1, 25, 160], [1, 1, 26, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 23, 0]]}>
    // CHECK:    [[INPUT_COPY0:%.*]] = VPUIP.NCEClusterTiling inputs([[INPUT_SUBVIEW0]] as %arg1: memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs([[INPUT_BUFF0]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>) ->
    // CHECK-SAME{Literal}:             !VPUIP.DistributedBuffer<1x1x49x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 1, 25, 160], [1, 1, 26, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0]], memory_shapes = [[1, 1, 25, 160], [1, 1, 26, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 23, 0]]}> {
    // CHECK:                                   VPUIP.Copy inputs(%arg1 : memref<1x1x49x160xf16, {order = #NCHW, strides = [15360, 15360, 160, 1]}>) outputs(%arg2 : memref<1x1x49x160xf16, @CMX_NN>) -> memref<1x1x49x160xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUFF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_BUFF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INTERP:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[INPUT_COPY0]] as %arg1: memref<1x1x49x160xf16, @CMX_NN>, [[INPUT_COPY1]] as %arg2: memref<1x1x49x160xf16, @CMX_NN>) outputs([[OUTPUT_BUFF0]] as %arg3: memref<1x1x96x320xf16, @CMX_NN>, [[OUTPUT_BUFF1]] as %arg4: memref<1x1x96x320xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x1x96x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                                   %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Interpolate inputs(%arg1 as %arg5: memref<1x1x49x160xf16, @CMX_NN>, %arg2 as %arg6: memref<1x1x49x160xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x1x96x320xf16, @CMX_NN>, %arg4 as %arg8: memref<1x1x96x320xf16, @CMX_NN>) on tile 0 -> (memref<1x1x96x320xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>){
    // CHECK:                                         VPUIP.SW.Kernel.run {attrs = [2, 1, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg5, %arg7) : memref<1x1x49x160xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>
    // CHECK:                                         VPUIP.SW.Kernel.run {attrs = [2, 1, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 96, 1, 1], [320, 192, 1, 1], [2, 3], -7.500000e-01, [0, 47, 0, 0], [0, 96, 0, 0]]}(%arg6, %arg8) : memref<1x1x49x160xf16, @CMX_NN>, memref<1x1x96x320xf16, @CMX_NN>
    // CHECK:                                   }
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUFF:%.*]] = memref.alloc() : memref<1x1x192x320xf16>
    // CHECK:    [[OUTPUT_SUBVIEW0:%.*]] = VPUIP.SubView [[OUTPUT_BUFF]] [0, 0, 0, 0] [1, 1, 96, 320] : memref<1x1x192x320xf16> to memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    [[OUTPUT_COPY0:%.*]] = VPUIP.NCEClusterTiling inputs([[INTERP]]#0 as %arg1: memref<1x1x96x320xf16, @CMX_NN>) outputs([[OUTPUT_SUBVIEW0]] as %arg2: memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}> {
    // CHECK:                                    VPUIP.Copy inputs(%arg1 : memref<1x1x96x320xf16, @CMX_NN>) outputs(%arg2 : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    }
    // CHECK:    [[OUTPUT_SUBVIEW1:%.*]] = VPUIP.SubView [[OUTPUT_BUFF]] [0, 0, 96, 0] [1, 1, 96, 320] : memref<1x1x192x320xf16> to memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    [[OUTPUT_COPY1:%.*]] = VPUIP.NCEClusterTiling inputs([[INTERP]]#1 as %arg1: memref<1x1x96x320xf16, @CMX_NN>) outputs([[OUTPUT_SUBVIEW1]] as %arg2: memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}> {
    // CHECK:                                     VPUIP.Copy inputs(%arg1 : memref<1x1x96x320xf16, @CMX_NN>) outputs(%arg2 : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) -> memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[OUTPUT_COPY0]], [[OUTPUT_COPY1]] : memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>, memref<1x1x96x320xf16, {order = #NCHW, strides = [61440, 61440, 320, 1]}>) outputs([[OUTPUT_BUFF]] : memref<1x1x192x320xf16>) -> memref<1x1x192x320xf16>
    // CHECK:    return [[CONCAT:%.*]] : memref<1x1x192x320xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_Gelu(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "gelu_fp16.cpp", VPU.kernel_entry = "gelu_fp16"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterGelu(%arg0: memref<1x128x64x32xf16>)
        -> memref<1x128x64x32xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16>) outputs(%arg2 : memref<1x128x64x32xf16, @CMX_NN>) -> memref<1x128x64x32xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%3 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Gelu inputs(%arg1 as %arg6: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x128x64x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run(%arg6, %arg7) : memref<1x128x64x32xf16, @CMX_NN>, memref<1x128x64x32xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x64x32xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    }
    return %6: memref<1x128x64x32xf16>

    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView %arg0 [0, 0, 32, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[INPUT_BUF0:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME{LITERAL}:     VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY2:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW0]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[INPUT_BUF0]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs(%arg2 : memref<1x128x32x32xf16, @CMX_NN>) -> memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView %arg0 [0, 0, 0, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[INPUT_BUF1:%.*]] = VPURT.AllocDistributed ->
    // CHECK-SAME{LITERAL}:     !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY4:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[INPUT_BUF1]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs(%arg2 : memref<1x128x32x32xf16, @CMX_NN>) -> memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[CLUSTER_GELU:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[COPY4]] as %arg1: memref<1x128x32x32xf16, @CMX_NN>, [[COPY2]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>) outputs([[OUTPUT_BUF0]] as %arg3: memref<1x128x32x32xf16, @CMX_NN>, [[OUTPUT_BUF1]] as %arg4: memref<1x128x32x32xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                   %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Gelu inputs(%arg1 as %arg5: memref<1x128x32x32xf16, @CMX_NN>, %arg2 as %arg6: memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x128x32x32xf16, @CMX_NN>, %arg4 as %arg8: memref<1x128x32x32xf16, @CMX_NN>) on tile 0 -> (memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>){
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = []}(%arg5, %arg7) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg8) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:                   }
    // CHECK:    }
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY5:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_GELU]]#0 as %arg1: memref<1x128x32x32xf16, @CMX_NN>) outputs([[SUBVIEW2]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    }
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 32, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY6:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_GELU]]#1 as %arg1: memref<1x128x32x32xf16, @CMX_NN>) outputs([[SUBVIEW3]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[COPY5]], [[COPY6]] : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[OUTPUT_DDR]] : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    // CHECK:    return [[CONCAT]] : memref<1x128x64x32xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

!DistributedBuffer = !VPUIP.DistributedBuffer<
    1x128x64x32xf16, #NCHW, @CMX_NN, {
    mode = "SEGMENTED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2 : i64,
    compute_shapes = [[1, 128, 32, 32], [1, 128, 32, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 32, 0]],
    memory_shapes = [[1, 128, 32, 32], [1, 128, 32, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 32, 0]]
}>

module @VPU.SW {
  func.func private @builtin_Gelu(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "gelu_fp16.cpp", VPU.kernel_entry = "gelu_fp16"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

// CHECK-LABEL: @TileClusterGeluWithExplicitDistributedAttr
// CHECK-SAME: ([[ARG0:%.+]]: memref<1x128x64x32xf16>)
func.func @TileClusterGeluWithExplicitDistributedAttr(%arg0: memref<1x128x64x32xf16>)
        -> memref<1x128x64x32xf16> {
    %0 = VPURT.AllocDistributed -> !DistributedBuffer
    %1 = VPUIP.NCEClusterTiling
      inputs(%arg0 as %arg1: memref<1x128x64x32xf16>)
      outputs(%0 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>)
        -> !DistributedBuffer {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16>) outputs(%arg2 : memref<1x128x64x32xf16, @CMX_NN>)
        -> memref<1x128x64x32xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !DistributedBuffer
    %4 = VPUIP.NCEClusterTiling
      inputs(%1 as %arg1: memref<1x128x64x32xf16, #NCHW, @CMX_NN>)
      outputs(%3 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>)
        -> !DistributedBuffer {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Gelu
        inputs(%arg1 as %arg6: memref<1x128x64x32xf16, #NCHW, @CMX_NN>)
        outputs(%arg2 as %arg7: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) on tile 0
          -> memref<1x128x64x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run(%arg6, %arg7) : memref<1x128x64x32xf16, @CMX_NN>, memref<1x128x64x32xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x64x32xf16>
    %6 = VPUIP.NCEClusterTiling
      inputs(%4 as %arg1: memref<1x128x64x32xf16, @CMX_NN>)
      outputs(%5 as %arg2: memref<1x128x64x32xf16>)
        -> memref<1x128x64x32xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    }
    return %6: memref<1x128x64x32xf16>

    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView [[ARG0]] [0, 0, 32, 0] [1, 128, 32, 32] :
    // CHECK-SAME:    memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>

    // CHECK:    [[INPUT_BUF0:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME:       VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN,
    // CHECK-SAME:          {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}:  compute_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  compute_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]],
    // CHECK-SAME{LITERAL}:  memory_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  memory_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]]}>

    // CHECK:    [[COPY2:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SANE:    inputs([[SUBVIEW0]] as [[IN_ARG0:%.*]]: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>)
    // CHECK-SAME:    outputs([[INPUT_BUF0]] as [[IN_ARG1:%.*]]: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK-NEXT:         VPUIP.Copy

    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView [[ARG0]] [0, 0, 0, 0] [1, 128, 32, 32] :
    // CHECK-SAME:    memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>

    // CHECK:    [[INPUT_BUF1:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME:       VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN,
    // CHECK-SAME:          {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}:  compute_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  compute_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]],
    // CHECK-SAME{LITERAL}:  memory_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  memory_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]]}>

    // CHECK:    [[COPY4:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:    inputs([[SUBVIEW1]] as [[IN_ARG2:%.*]]: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>)
    // CHECK-SAME:    outputs([[INPUT_BUF1]] as [[IN_ARG3:%.*]]: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK-NEXT:         VPUIP.Copy

    // CHECK:    [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed ->
    // CHECK-SAME:       VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN,
    // CHECK-SAME:          {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}:  compute_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  compute_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]],
    // CHECK-SAME{LITERAL}:  memory_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  memory_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]]}>

    // CHECK:    [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed ->
    // CHECK-SAME:       VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN,
    // CHECK-SAME:          {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}:  compute_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  compute_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]],
    // CHECK-SAME{LITERAL}:  memory_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  memory_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]]}>

    // CHECK:    [[CLUSTER_GELU:%.*]]:2 = VPUIP.NCEClusterTiling
    // CHECK-SAME:    inputs([[COPY4]] as [[IN_ARG4:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>,
    // CHECK-SAME:           [[COPY2]] as [[IN_ARG5:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK-SAME:    outputs([[OUTPUT_BUF0]] as [[IN_ARG6:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>,
    // CHECK-SAME:            [[OUTPUT_BUF1]] as [[IN_ARG7:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK:         %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Gelu
    // CHECK-SAME:      inputs([[IN_ARG4]] as [[IN_ARG8:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>,
    // CHECK-SAME:             [[IN_ARG5]] as [[IN_ARG9:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK-SAME:      outputs([[IN_ARG6]] as [[IN_ARG10:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>,
    // CHECK-SAME:              [[IN_ARG7]] as [[IN_ARG11:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>) on tile 0
    // CHECK-SAME:        -> (memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>){
    // CHECK:            VPUIP.SW.Kernel.run {attrs = []}([[IN_ARG8]], [[IN_ARG10]]) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:            VPUIP.SW.Kernel.run {attrs = []}([[IN_ARG9]], [[IN_ARG11]]) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:          }
    // CHECK:    }

    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 128, 32, 32] :
    // CHECK-SAME:    memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>

    // CHECK:    [[COPY5:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:    inputs([[CLUSTER_GELU]]#0 as [[IN_ARG12:%.*]]: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK-SAME:    outputs([[SUBVIEW2]] as [[IN_ARG13:%.*]]: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>)
    // CHECK-SAME:      -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK-NEXT:     VPUIP.Copy

    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 32, 0] [1, 128, 32, 32] :
    // CHECK-SAME:    memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>

    // CHECK:    [[COPY6:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:    inputs([[CLUSTER_GELU]]#1 as [[IN_ARG14:%.*]]: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK-SAME:    outputs([[SUBVIEW3]] as [[IN_ARG15:%.*]]: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>)
    // CHECK-SAME:      -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK-NEXT:               VPUIP.Copy

    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[COPY5]], [[COPY6]]
    // CHECK-SAME                                  outputs([[OUTPUT_DDR]]
    // CHECK-SAME:    -> memref<1x128x64x32xf16>
    // CHECK:    return [[CONCAT]] : memref<1x128x64x32xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_HardSigmoid(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "activation_hardsigmoid.cpp", VPU.kernel_entry = "activation_hardsigmoid"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterHardSigmoid(%arg0: memref<1x128x64x32xf16>)
        -> memref<1x128x64x32xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16>) outputs(%arg2 : memref<1x128x64x32xf16, @CMX_NN>) -> memref<1x128x64x32xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%3 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_HardSigmoid inputs(%arg1 as %arg6: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x128x64x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run {attrs = [0.1666259765625, 5.000000e-01]}(%arg6, %arg7) : memref<1x128x64x32xf16, @CMX_NN>, memref<1x128x64x32xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x64x32xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    }
    return %6: memref<1x128x64x32xf16>

    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView %arg0 [0, 0, 32, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[INPUT_BUF0:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME{LITERAL}:     VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY2:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW0]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[INPUT_BUF0]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs(%arg2 : memref<1x128x32x32xf16, @CMX_NN>) -> memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView %arg0 [0, 0, 0, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[INPUT_BUF1:%.*]] = VPURT.AllocDistributed ->
    // CHECK-SAME{LITERAL}:     !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY4:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[INPUT_BUF1]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs(%arg2 : memref<1x128x32x32xf16, @CMX_NN>) -> memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[CLUSTER_HARDSIGMOID:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[COPY4]] as %arg1: memref<1x128x32x32xf16, @CMX_NN>, [[COPY2]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>) outputs([[OUTPUT_BUF0]] as %arg3: memref<1x128x32x32xf16, @CMX_NN>, [[OUTPUT_BUF1]] as %arg4: memref<1x128x32x32xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                   %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_HardSigmoid inputs(%arg1 as %arg5: memref<1x128x32x32xf16, @CMX_NN>, %arg2 as %arg6: memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x128x32x32xf16, @CMX_NN>, %arg4 as %arg8: memref<1x128x32x32xf16, @CMX_NN>) on tile 0 -> (memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>){
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = [0.1666259765625, 5.000000e-01]}(%arg5, %arg7) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = [0.1666259765625, 5.000000e-01]}(%arg6, %arg8) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:                   }
    // CHECK:    }
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY5:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_HARDSIGMOID]]#0 as %arg1: memref<1x128x32x32xf16, @CMX_NN>) outputs([[SUBVIEW2]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    }
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 32, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY6:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_HARDSIGMOID]]#1 as %arg1: memref<1x128x32x32xf16, @CMX_NN>) outputs([[SUBVIEW3]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[COPY5]], [[COPY6]] : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[OUTPUT_DDR]] : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    // CHECK:    return [[CONCAT]] : memref<1x128x64x32xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_Gelu(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "gelu_fp16.cpp", VPU.kernel_entry = "gelu_fp16"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterGeluWithCMXInput(%arg0: !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
        -> memref<1x128x64x32xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Gelu inputs(%arg1 as %arg6: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x128x64x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run(%arg6, %arg7) : memref<1x128x64x32xf16, @CMX_NN>, memref<1x128x64x32xf16, @CMX_NN>
      }
    }
    %2 = memref.alloc() : memref<1x128x64x32xf16>
    %3 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs(%2 as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
      %4 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    }
    return %3: memref<1x128x64x32xf16>

    // CHECK:    [[INPUT_DDR1:%.*]] = memref.alloc() : memref<1x128x64x32xf16, @DDR>
    // CHECK:    [[COPYBACK1:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs([[INPUT_DDR1]] as %arg2: memref<1x128x64x32xf16, @DDR>) -> memref<1x128x64x32xf16, @DDR> {
    // CHECK:                             VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16, @DDR>) -> memref<1x128x64x32xf16, @DDR>
    // CHECK:    }
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView [[COPYBACK1]] [0, 0, 32, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16, @DDR> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>
    // CHECK:    [[INPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY1:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>) outputs([[INPUT_BUF1]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                             VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>) outputs(%arg2 : memref<1x128x32x32xf16, @CMX_NN>) -> memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[INPUT_DDR0:%.*]] = memref.alloc() : memref<1x128x64x32xf16, @DDR>
    // CHECK:    [[COPYBACK0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs([[INPUT_DDR0]] as %arg2: memref<1x128x64x32xf16, @DDR>) -> memref<1x128x64x32xf16, @DDR> {
    // CHECK:                            VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16, @DDR>) -> memref<1x128x64x32xf16, @DDR>
    // CHECK:    }
    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView [[COPYBACK0]] [0, 0, 0, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16, @DDR> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>
    // CHECK:    [[INPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW0]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>) outputs([[INPUT_BUF0]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                            VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>) outputs(%arg2 : memref<1x128x32x32xf16, @CMX_NN>) -> memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:    }

    // CHECK:    [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[CLUSTER_GELU:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[COPY0]] as %arg1: memref<1x128x32x32xf16, @CMX_NN>, [[COPY1]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>) outputs([[OUTPUT_BUF0]] as %arg3: memref<1x128x32x32xf16, @CMX_NN>, [[OUTPUT_BUF1]] as %arg4: memref<1x128x32x32xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                   %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Gelu inputs(%arg1 as %arg5: memref<1x128x32x32xf16, @CMX_NN>, %arg2 as %arg6: memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x128x32x32xf16, @CMX_NN>, %arg4 as %arg8: memref<1x128x32x32xf16, @CMX_NN>) on tile 0 -> (memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>){
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = []}(%arg5, %arg7) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg8) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:                   }
    // CHECK:    }
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY5:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_GELU]]#0 as %arg1: memref<1x128x32x32xf16, @CMX_NN>) outputs([[SUBVIEW2]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    }
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 32, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY6:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_GELU]]#1 as %arg1: memref<1x128x32x32xf16, @CMX_NN>) outputs([[SUBVIEW3]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[COPY5]], [[COPY6]] : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[OUTPUT_DDR]] : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    // CHECK:    return [[CONCAT]] : memref<1x128x64x32xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

!DistributedBuffer = !VPUIP.DistributedBuffer<
    1x128x64x32xf16, #NCHW, @CMX_NN, {
    mode = "SEGMENTED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2 : i64,
    compute_shapes = [[1, 128, 32, 32], [1, 128, 32, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 32, 0]],
    memory_shapes = [[1, 128, 32, 32], [1, 128, 32, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 32, 0]]
}>

module @VPU.SW {
  func.func private @builtin_Gelu(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "gelu_fp16.cpp", VPU.kernel_entry = "gelu_fp16"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

// CHECK-LABEL: @TileClusterGeluWithCMXInputAndExplicitDistribution
// CHECK-SAME: ([[ARG0:%.+]]: !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN
func.func @TileClusterGeluWithCMXInputAndExplicitDistribution(%arg0: !DistributedBuffer)
        -> memref<1x128x64x32xf16> {
    %0 = VPURT.AllocDistributed -> !DistributedBuffer
    %1 = VPUIP.NCEClusterTiling
      inputs(%arg0 as %arg1: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>)
        -> !DistributedBuffer {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Gelu
        inputs(%arg1 as %arg6: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) on tile 0
          -> memref<1x128x64x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run(%arg6, %arg7) : memref<1x128x64x32xf16, @CMX_NN>, memref<1x128x64x32xf16, @CMX_NN>
      }
    }
    %2 = memref.alloc() : memref<1x128x64x32xf16>
    %3 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs(%2 as %arg2: memref<1x128x64x32xf16>)
      -> memref<1x128x64x32xf16> {
      %4 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>)
        -> memref<1x128x64x32xf16>
    }
    return %3: memref<1x128x64x32xf16>

    // CHECK:    [[INPUT_DDR1:%.*]] = memref.alloc() : memref<1x128x64x32xf16, @DDR>
    // CHECK:    [[COPYBACK1:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:  inputs([[ARG0]] as [[IN_ARG0:%.*]]: memref<1x128x64x32xf16, @CMX_NN>)
    // CHECK-SAME:  outputs([[INPUT_DDR1]] as [[IN_ARG1:%.*]]: memref<1x128x64x32xf16, @DDR>)
    // CHECK-SAME:    -> memref<1x128x64x32xf16, @DDR> {
    // CHECK-NEXT:   VPUIP.Copy

    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView [[COPYBACK1]] [0, 0, 32, 0] [1, 128, 32, 32] :
    // CHECK-SAME:    memref<1x128x64x32xf16, @DDR> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>

    // CHECK:    [[INPUT_BUF1:%.*]] = VPURT.AllocDistributed ->
    // CHECK-SAME:        !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN,
    // CHECK-SAME:          {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}:  compute_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  compute_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]],
    // CHECK-SAME{LITERAL}:  memory_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  memory_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]]}>


    // CHECK:    [[COPY1:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:    inputs([[SUBVIEW1]] as [[IN_ARG2:%.*]]: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>)
    // CHECK-SAME:    outputs([[INPUT_BUF1]] as [[IN_ARG3:%.*]]: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK-SAME:      -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN,
    // CHECK-SAME:          {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}:  compute_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  compute_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]],
    // CHECK-SAME{LITERAL}:  memory_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  memory_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]]}>
    // CHECK-NEXT:            VPUIP.Copy

    // CHECK:    [[INPUT_DDR0:%.*]] = memref.alloc() : memref<1x128x64x32xf16, @DDR>
    // CHECK:    [[COPYBACK0:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:      inputs([[ARG0]] as [[IN_ARG4:%.*]]: memref<1x128x64x32xf16, @CMX_NN>)
    // CHECK-SAME:      outputs([[INPUT_DDR0]] as [[IN_ARG5:%.*]]: memref<1x128x64x32xf16, @DDR>)
    // CHECK-SAME:        -> memref<1x128x64x32xf16, @DDR> {
    // CHECK-NEXT:       VPUIP.Copy

    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView [[COPYBACK0]] [0, 0, 0, 0] [1, 128, 32, 32] :
    // CHECK-SAME:    memref<1x128x64x32xf16, @DDR> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>

    // CHECK:    [[INPUT_BUF0:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME:      -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN,
    // CHECK-SAME:          {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}:  compute_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  compute_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]],
    // CHECK-SAME{LITERAL}:  memory_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  memory_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]]}>

    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:      inputs([[SUBVIEW0]] as [[IN_ARG6:%.*]]: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @DDR>)
    // CHECK-SAME:      outputs([[INPUT_BUF0]] as [[IN_ARG7:%.*]]: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK-SAME:        -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN,
    // CHECK-SAME:            {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}:    compute_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:    compute_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]],
    // CHECK-SAME{LITERAL}:    memory_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:    memory_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]]}>
    // CHECK-NEXT:           VPUIP.Copy

    // CHECK:    [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME:     -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN,
    // CHECK-SAME:         {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}: compute_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}: compute_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]],
    // CHECK-SAME{LITERAL}: memory_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}: memory_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]]}>

    // CHECK:    [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME:      -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN,
    // CHECK-SAME:          {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}:  compute_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  compute_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]],
    // CHECK-SAME{LITERAL}:  memory_shapes = [[1, 128, 16, 32], [1, 128, 16, 32]],
    // CHECK-SAME{LITERAL}:  memory_offsets = [[0, 0, 0, 0], [0, 0, 16, 0]]}>

    // CHECK:    [[CLUSTER_GELU:%.*]]:2 = VPUIP.NCEClusterTiling
    // CHECK-SAME:    inputs([[COPY0]] as [[IN_ARG8:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>,
    // CHECK-SAME:           [[COPY1]] as [[IN_ARG9:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK-SAME:    outputs([[OUTPUT_BUF0]] as [[IN_ARG10:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>,
    // CHECK-SAME:            [[OUTPUT_BUF1]] as [[IN_ARG11:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK:      %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Gelu
    // CHECK-SAME:      inputs([[IN_ARG8]] as [[IN_ARG12:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>,
    // CHECK-SAME:             [[IN_ARG9]] as [[IN_ARG13:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK-SAME:      outputs([[IN_ARG10]] as [[IN_ARG14:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>,
    // CHECK-SAME:              [[IN_ARG11]] as [[IN_ARG15:[^:]+]]: memref<1x128x32x32xf16, @CMX_NN>) on tile 0
    // CHECK-SAME:        -> (memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>){
    // CHECK:         VPUIP.SW.Kernel.run {attrs = []}([[IN_ARG12]], [[IN_ARG14]]) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:         VPUIP.SW.Kernel.run {attrs = []}([[IN_ARG13]], [[IN_ARG15]]) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>

    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 128, 32, 32] :
    // CHECK-SAME:    memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY5:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:    inputs([[CLUSTER_GELU]]#0 as [[IN_ARG16:%.*]]: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK-SAME:    outputs([[SUBVIEW2]] as [[IN_ARG17:%.*]]: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>)
    // CHECK-SAME:      -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:               VPUIP.Copy

    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 32, 0] [1, 128, 32, 32] :
    // CHECK-SAME:    memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY6:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:    inputs([[CLUSTER_GELU]]#1 as [[IN_ARG18:%.*]]: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK-SAME:    outputs([[SUBVIEW3]] as [[IN_ARG19:%.*]]: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>)
    // CHECK-SAME:      -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:               VPUIP.Copy

    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView
    // CHECK-SAME:  inputs([[COPY5]], [[COPY6]] : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>,
    // CHECK-SAME:                                memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>)
    // CHECK-SAME:  outputs([[OUTPUT_DDR]] : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    // CHECK:    return [[CONCAT]] : memref<1x128x64x32xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_Gelu(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "gelu_fp16.cpp", VPU.kernel_entry = "gelu_fp16"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterGeluWithdifferentTiles(%arg0: memref<1x128x6x32xf16>)
        -> memref<1x128x6x32xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x6x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x6x32xf16>) outputs(%0 as %arg2: memref<1x128x6x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x6x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x6x32xf16>) outputs(%arg2 : memref<1x128x6x32xf16, @CMX_NN>) -> memref<1x128x6x32xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x6x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x6x32xf16, #NCHW, @CMX_NN>) outputs(%3 as %arg2: memref<1x128x6x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x6x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Gelu inputs(%arg1 as %arg6: memref<1x128x6x32xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x6x32xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x128x6x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run(%arg6, %arg7) : memref<1x128x6x32xf16, @CMX_NN>, memref<1x128x6x32xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x6x32xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x128x6x32xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x128x6x32xf16>) -> memref<1x128x6x32xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x6x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x6x32xf16>) -> memref<1x128x6x32xf16>
    }
    return %6: memref<1x128x6x32xf16>

    // CHECK:     [[INPUT_SUBVIEW1:%.*]] = VPUIP.SubView %arg0 [0, 0, 4, 0] [1, 128, 2, 32] : memref<1x128x6x32xf16> to memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>
    // CHECK:     [[INPUT_CMX_1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x2x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:     [[COPY_INPUT_1:%.*]] = VPUIP.NCEClusterTiling inputs([[INPUT_SUBVIEW1]] as %arg1: memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) outputs([[INPUT_CMX_1]] as %arg2: memref<1x128x2x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x2x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                             VPUIP.Copy inputs(%arg1 : memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) outputs(%arg2 : memref<1x128x2x32xf16, @CMX_NN>) -> memref<1x128x2x32xf16, @CMX_NN>
    // CHECK:     }
    // CHECK:     [[INPUT_SUBVIEW0:%.*]] = VPUIP.SubView %arg0 [0, 0, 0, 0] [1, 128, 4, 32] : memref<1x128x6x32xf16> to memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>
    // CHECK:     [[INPUT_CMX_0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x4x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:     [[COPY_INPUT_0:%.*]] = VPUIP.NCEClusterTiling inputs([[INPUT_SUBVIEW0]] as %arg1: memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) outputs([[INPUT_CMX_0]] as %arg2: memref<1x128x4x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x4x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                             VPUIP.Copy inputs(%arg1 : memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) outputs(%arg2 : memref<1x128x4x32xf16, @CMX_NN>) -> memref<1x128x4x32xf16, @CMX_NN>
    // CHECK:     }
    // CHECK:     [[OUTPUT_CMX_1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x2x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:     [[OUTPUT_CMX_0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x4x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:     [[GELU:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[COPY_INPUT_0]] as %arg1: memref<1x128x4x32xf16, @CMX_NN>, [[COPY_INPUT_1]] as %arg2: memref<1x128x2x32xf16, @CMX_NN>) outputs([[OUTPUT_CMX_0]] as %arg3: memref<1x128x4x32xf16, @CMX_NN>, [[OUTPUT_CMX_1]] as %arg4: memref<1x128x2x32xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x128x4x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x2x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                           %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Gelu inputs(%arg1 as %arg5: memref<1x128x4x32xf16, @CMX_NN>, %arg2 as %arg6: memref<1x128x2x32xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x128x4x32xf16, @CMX_NN>, %arg4 as %arg8: memref<1x128x2x32xf16, @CMX_NN>) on tile 0 -> (memref<1x128x4x32xf16, @CMX_NN>, memref<1x128x2x32xf16, @CMX_NN>){
    // CHECK:                                 VPUIP.SW.Kernel.run {attrs = []}(%arg5, %arg7) : memref<1x128x4x32xf16, @CMX_NN>, memref<1x128x4x32xf16, @CMX_NN>
    // CHECK:                                 VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg8) : memref<1x128x2x32xf16, @CMX_NN>, memref<1x128x2x32xf16, @CMX_NN>
    // CHECK:                           }
    // CHECK:     }
    // CHECK:     [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x128x6x32xf16>
    // CHECK:     [[OUTPUT_SUBVIEW0:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 128, 4, 32] : memref<1x128x6x32xf16> to memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>
    // CHECK:     [[COPY_OUTPUT_0:%.*]] = VPUIP.NCEClusterTiling inputs([[GELU]]#0 as %arg1: memref<1x128x4x32xf16, @CMX_NN>) outputs([[OUTPUT_SUBVIEW0]] as %arg2: memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) -> memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}> {
    // CHECK:                                 VPUIP.Copy inputs(%arg1 : memref<1x128x4x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) -> memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>
    // CHECK:     }
    // CHECK:     [[OUTPUT_SUBVIEW1:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 4, 0] [1, 128, 2, 32] : memref<1x128x6x32xf16> to memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>
    // CHECK:     [[COPY_OUTPUT_1:%.*]] = VPUIP.NCEClusterTiling inputs([[GELU]]#1 as %arg1: memref<1x128x2x32xf16, @CMX_NN>) outputs([[OUTPUT_SUBVIEW1]] as %arg2: memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) -> memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}> {
    // CHECK:                                 VPUIP.Copy inputs(%arg1 : memref<1x128x2x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) -> memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>
    // CHECK:     }
    // CHECK:     [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[COPY_OUTPUT_0]], [[COPY_OUTPUT_1]] : memref<1x128x4x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>, memref<1x128x2x32xf16, {order = #NCHW, strides = [24576, 192, 32, 1]}>) outputs([[OUTPUT_DDR]] : memref<1x128x6x32xf16>) -> memref<1x128x6x32xf16>
    // CHECK:     return [[CONCAT]] : memref<1x128x6x32xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_SoftMax(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "singleShaveSoftmax.cpp", VPU.kernel_entry = "singleShaveSoftmax"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterSoftmax(%arg0: memref<1x128x64x32xf16>)
        -> memref<1x128x64x32xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16>) outputs(%arg2 : memref<1x128x64x32xf16, @CMX_NN>) -> memref<1x128x64x32xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%3 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_SoftMax inputs(%arg1 as %arg6: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x128x64x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run {attrs = [0]}(%arg6, %arg7) : memref<1x128x64x32xf16, @CMX_NN>, memref<1x128x64x32xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x64x32xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    }
    return %6: memref<1x128x64x32xf16>

    // CHECK:    [[INPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16>) outputs([[INPUT_CMX]] as %arg2: memref<1x128x64x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16>) outputs(%arg2 : memref<1x128x64x32xf16, @CMX_NN>) -> memref<1x128x64x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView [[COPY0]] [0, 0, 32, 0] [1, 128, 32, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView [[COPY0]] [0, 0, 0, 0] [1, 128, 32, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 0, 32, 0] [1, 128, 32, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 0, 0, 0] [1, 128, 32, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SOFTMAX:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, [[SUBVIEW0]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>) outputs([[SUBVIEW3]] as %arg3: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, [[SUBVIEW2]] as %arg4: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK{LITERAL}:      %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_SoftMax inputs(%arg1 as %arg5: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, %arg2 as %arg6: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, %arg4 as %arg8: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>) strides([[131072, 1024, 32, 1], [131072, 1024, 32, 1]]) on tile 0 -> (memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>){
    // CHECK:        VPUIP.SW.Kernel.run {attrs = [0]}(%arg5, %arg7) : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = [0]}(%arg6, %arg8) : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>
    // CHECK:      }
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[SOFTMAX]]#0, [[SOFTMAX]]#1 : !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) outputs([[OUTPUT_CMX]] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[BUFF_OUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16>
    // CHECK:    [[COPY_OUTPUT_TO_DDR:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCAT]] as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs([[BUFF_OUT_DDR]] as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    // CHECK:    }
    // CHECK:    return [[COPY_OUTPUT_TO_DDR]] : memref<1x128x64x32xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_SoftMax(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "singleShaveSoftmax.cpp", VPU.kernel_entry = "singleShaveSoftmax"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileSoftmaxWhenAxisIsHighestDim(%arg0: memref<1x128x64x32xf16>)
        -> memref<1x128x64x32xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16>) outputs(%arg2 : memref<1x128x64x32xf16, @CMX_NN>) -> memref<1x128x64x32xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%3 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_SoftMax inputs(%arg1 as %arg6: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x128x64x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run {attrs = [2]}(%arg6, %arg7) : memref<1x128x64x32xf16, @CMX_NN>, memref<1x128x64x32xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x64x32xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    }
    return %6: memref<1x128x64x32xf16>

    // CHECK:    [[INPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16>) outputs([[INPUT_CMX]] as %arg2: memref<1x128x64x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:         VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16>) outputs(%arg2 : memref<1x128x64x32xf16, @CMX_NN>) -> memref<1x128x64x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView [[COPY0]] [0, 0, 32, 0] [1, 128, 32, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView [[COPY0]] [0, 0, 0, 0] [1, 128, 32, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 0, 32, 0] [1, 128, 32, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_CMX]] [0, 0, 0, 0] [1, 128, 32, 32] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SOFTMAX:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, [[SUBVIEW0]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>) outputs([[SUBVIEW3]] as %arg3: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, [[SUBVIEW2]] as %arg4: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK{LITERAL}:      %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_SoftMax inputs(%arg1 as %arg5: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, %arg2 as %arg6: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, %arg4 as %arg8: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>) strides([[131072, 1024, 32, 1], [131072, 1024, 32, 1]]) on tile 0 -> (memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>){
    // CHECK:        VPUIP.SW.Kernel.run {attrs = [2]}(%arg5, %arg7) : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = [2]}(%arg6, %arg8) : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN>
    // CHECK:      }
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[SOFTMAX]]#0, [[SOFTMAX]]#1 : !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) outputs([[OUTPUT_CMX]] : !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[BUFF_OUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16>
    // CHECK:    [[COPY_OUTPUT_TO_DDR:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCAT]] as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs([[BUFF_OUT_DDR]] as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
    // CHECK:         VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    // CHECK:    }
    // CHECK:    return [[COPY_OUTPUT_TO_DDR]] : memref<1x128x64x32xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_SoftMax(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "single_shave_softmax.cpp", VPU.kernel_entry = "singleShaveSoftmax"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @NotTileClusterSoftmaxForUnsupportedAxis(%arg0: memref<1x128x2x1xf16>)
        -> memref<1x128x2x1xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x2x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x2x1xf16>) outputs(%0 as %arg2: memref<1x128x2x1xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x1x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x2x1xf16>) outputs(%arg2 : memref<1x128x2x1xf16, @CMX_NN>) -> memref<1x128x2x1xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x2x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x2x1xf16, #NCHW, @CMX_NN>) outputs(%3 as %arg2: memref<1x128x2x1xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x2x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_SoftMax inputs(%arg1 as %arg6: memref<1x128x2x1xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x2x1xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x128x2x1xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run {attrs = [2]}(%arg6, %arg7) : memref<1x128x2x1xf16, @CMX_NN>, memref<1x128x2x1xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x2x1xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x128x2x1xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x128x2x1xf16>) -> memref<1x128x2x1xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x2x1xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x2x1xf16>) -> memref<1x128x2x1xf16>
    }
    return %6: memref<1x128x2x1xf16>

    // CHECK:    [[INPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x2x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x2x1xf16>) outputs([[INPUT_CMX]] as %arg2: memref<1x128x2x1xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x1x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x128x2x1xf16>) outputs(%arg2 : memref<1x128x2x1xf16, @CMX_NN>) -> memref<1x128x2x1xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_CMX:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x2x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[SOFTMAX:%.*]] = VPUIP.NCEClusterTiling inputs([[COPY0]] as %arg1: memref<1x128x2x1xf16, @CMX_NN>) outputs([[OUTPUT_CMX]] as %arg2: memref<1x128x2x1xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x2x1xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_SoftMax inputs(%arg1 as %arg3: memref<1x128x2x1xf16, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x128x2x1xf16, @CMX_NN>) on tile 0 -> memref<1x128x2x1xf16, @CMX_NN>{
    // CHECK:        VPUIP.SW.Kernel.run {attrs = [2]}(%arg3, %arg4) : memref<1x128x2x1xf16, @CMX_NN>, memref<1x128x2x1xf16, @CMX_NN>
    // CHECK:      }
    // CHECK:    }
    // CHECK:    [[BUFF_OUT_DDR:%.*]] = memref.alloc() : memref<1x128x2x1xf16>
    // CHECK:    [[COPY_OUTPUT_TO_DDR:%.*]] = VPUIP.NCEClusterTiling inputs([[SOFTMAX]] as %arg1: memref<1x128x2x1xf16, @CMX_NN>) outputs([[BUFF_OUT_DDR]] as %arg2: memref<1x128x2x1xf16>) -> memref<1x128x2x1xf16> {
    // CHECK:            VPUIP.Copy inputs(%arg1 : memref<1x128x2x1xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x2x1xf16>) -> memref<1x128x2x1xf16>
    // CHECK:    }
    // CHECK:    return [[COPY_OUTPUT_TO_DDR]] : memref<1x128x2x1xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
    func.func private @builtin_Interpolate(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i64, i64, i64, i64, none, none, none, none, none) attributes {VPU.kernel_code = "single_shave_interpolate.cpp", VPU.kernel_entry = "singleShaveInterpolate"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @NotTileClusterHalfPixelInterpolateForCMXSizeRequirement(%arg0: memref<1x16x154x160xf16>) -> memref<1x16x308x320xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x16x154x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 16, 77, 160], [1, 16, 77, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 76, 0]], memory_shapes = [[1, 16, 77, 160], [1, 16, 77, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 76, 0]]}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg2: memref<1x16x154x160xf16>) outputs(%0 as %arg3: memref<1x16x154x160xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x16x154x160xf16, #NCHW, @CMX_NN, {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, compute_shapes = [[1, 16, 77, 160], [1, 16, 77, 160]], compute_offsets = [[0, 0, 0, 0], [0, 0, 76, 0]], memory_shapes = [[1, 16, 77, 160], [1, 16, 77, 160]], memory_offsets = [[0, 0, 0, 0], [0, 0, 76, 0]]}> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x16x154x160xf16>) outputs(%arg3 : memref<1x16x154x160xf16, @CMX_NN>) -> memref<1x16x154x160xf16, @CMX_NN>
    }
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x16x308x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %3 = VPUIP.NCEClusterTiling inputs(%1 as %arg2: memref<1x16x154x160xf16, @CMX_NN>) outputs(%2 as %arg3: memref<1x16x308x320xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x16x308x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Interpolate inputs(%arg2 as %arg4: memref<1x16x154x160xf16, @CMX_NN>) outputs(%arg3 as %arg5: memref<1x16x308x320xf16, @CMX_NN>) on tile 0 -> memref<1x16x308x320xf16, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [2, 0, 0, 0, [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [160, 154, 16, 1], [320, 308, 16, 1], [2, 3], -7.500000e-01, [0, 0, 0, 0], [0, 0, 0, 0]]}(%arg4, %arg5) : memref<1x16x154x160xf16, @CMX_NN>, memref<1x16x308x320xf16, @CMX_NN>
      }
    }
    %4 = memref.alloc() : memref<1x16x308x320xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg2: memref<1x16x308x320xf16, @CMX_NN>) outputs(%4 as %arg3: memref<1x16x308x320xf16>) -> memref<1x16x308x320xf16> {
      %7 = VPUIP.Copy inputs(%arg2 : memref<1x16x308x320xf16, @CMX_NN>) outputs(%arg3 : memref<1x16x308x320xf16>) -> memref<1x16x308x320xf16>
    }
    return %5 : memref<1x16x308x320xf16>

    // CHECK:    [[INPUT_BUF:%.*]] = VPURT.AllocDistributed
    // CHECK:    [[COPY0:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x16x154x160xf16>) outputs([[INPUT_BUF]] as %arg2: memref<1x16x154x160xf16, @CMX_NN>)
    // CHECK:                          VPUIP.Copy inputs(%arg1 : memref<1x16x154x160xf16>) outputs(%arg2 : memref<1x16x154x160xf16, @CMX_NN>) -> memref<1x16x154x160xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUF:%.*]] = VPURT.AllocDistributed
    // CHECK:    [[INTERP:%.*]] = VPUIP.NCEClusterTiling inputs([[COPY0]] as %arg1: memref<1x16x154x160xf16, @CMX_NN>) outputs([[OUTPUT_BUF]] as %arg2: memref<1x16x308x320xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x16x308x320xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                          VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Interpolate inputs(%arg1 as %arg3: memref<1x16x154x160xf16, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x16x308x320xf16, @CMX_NN>) on tile 0 -> memref<1x16x308x320xf16, @CMX_NN>{
    // CHECK:                             VPUIP.SW.Kernel.run
    // CHECK-NOT:                         VPUIP.SW.Kernel.run
    // CHECK:                          }
    // CHECK:    }
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW {
  func.func private @builtin_Multiply(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>) attributes {VPU.kernel_code = "eltwise_mul.cpp", VPU.kernel_entry = "eltwise_mul"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterMultiply() -> memref<1x64x88x88xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    %3 = VPUIP.NCEClusterTiling inputs(%0 as %arg0: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                                          %1 as %arg1: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                                  outputs(%2 as %arg2: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                                      -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Multiply
                    inputs(%arg0 as %arg3: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                           %arg1 as %arg4: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                    outputs(%arg2 as %arg5: memref<1x64x88x88xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x64x88x88xf16, #NHWC, @CMX_NN>{
        VPUIP.SW.Kernel.run(%arg3, %arg4, %arg5) : memref<1x64x88x88xf16, #NHWC, @CMX_NN>, memref<1x64x88x88xf16, #NHWC, @CMX_NN>, memref<1x64x88x88xf16, #NHWC, @CMX_NN>
      }
    }

    %4 = memref.alloc() : memref<1x64x88x88xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg1: memref<1x64x88x88xf16, @CMX_NN>) outputs(%4 as %arg2: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16> {
      %results = VPUIP.Copy inputs(%arg1 : memref<1x64x88x88xf16, @CMX_NN>) outputs(%arg2 : memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>
    }

    return %5: memref<1x64x88x88xf16>

    // For Multiply First Input
    // CHECK:    [[INPUT0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT0_TILE0:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT0_TILE1:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // For Multiply Second Input
    // CHECK:    [[INPUT1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT1_TILE0:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT1_TILE1:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[MULTI_OUT:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[MULTI_OUT_TILE0:%.*]] = VPUIP.SubView [[MULTI_OUT]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:    [[MULTI_OUT_TILE1:%.*]] = VPUIP.SubView [[MULTI_OUT]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:    [[MULTIPLY:%.*]]:2 = VPUIP.NCEClusterTiling
    // CHECK:                     inputs([[INPUT0_TILE1]] as %arg0: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE1]] as %arg1: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT0_TILE0]] as %arg2: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE0]] as %arg3: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     outputs([[MULTI_OUT_TILE1]] as %arg4: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[MULTI_OUT_TILE0]] as %arg5: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     -> (!VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK:    %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Multiply
    // CHECK:                     inputs(%arg0 as %arg6: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg1 as %arg7: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg2 as %arg8: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg3 as %arg9: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     outputs(%arg4 as %arg10: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                             %arg5 as %arg11: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg7, %arg10) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}(%arg8, %arg9, %arg11) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>

    // CHECK:    [[CONCATVIEW:%.*]] = VPUIP.ConcatView inputs([[MULTIPLY]]#0, [[MULTIPLY]]#1
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK:                     outputs([[MULTI_OUT]] : !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[OUTPUT_BUF:%.*]] = memref.alloc() : memref<1x64x88x88xf16>
    // CHECK:    [[OUTPUT_COPY:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCATVIEW]] as %arg0: memref<1x64x88x88xf16, @CMX_NN>)
    // CHECK:                                                 outputs([[OUTPUT_BUF]] as %arg1: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>

    // CHECK:    return [[OUTPUT_COPY]] : memref<1x64x88x88xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW {
  func.func private @builtin_Multiply(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>) attributes {VPU.kernel_code = "eltwise_mul.cpp", VPU.kernel_entry = "eltwise_mul"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterMultiplyAtBroadcastAxis() -> memref<1x64x88x88xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x1x88xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    %3 = VPUIP.NCEClusterTiling inputs(%0 as %arg0: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                                       %1 as %arg1: memref<1x1x1x88xf16, #NHWC, @CMX_NN>)
                                outputs(%2 as %arg2: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                                      -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Multiply
                    inputs(%arg0 as %arg3: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                           %arg1 as %arg4: memref<1x1x1x88xf16, #NHWC, @CMX_NN>)
                    outputs(%arg2 as %arg5: memref<1x64x88x88xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x64x88x88xf16, #NHWC, @CMX_NN>{
        VPUIP.SW.Kernel.run(%arg3, %arg4, %arg5) : memref<1x64x88x88xf16, #NHWC, @CMX_NN>, memref<1x1x1x88xf16, #NHWC, @CMX_NN>, memref<1x64x88x88xf16, #NHWC, @CMX_NN>
      }
    }

    %4 = memref.alloc() : memref<1x64x88x88xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg1: memref<1x64x88x88xf16, @CMX_NN>) outputs(%4 as %arg2: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16> {
      %results = VPUIP.Copy inputs(%arg1 : memref<1x64x88x88xf16, @CMX_NN>) outputs(%arg2 : memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>
    }

    return %5: memref<1x64x88x88xf16>

    // For Multiply First Input
    // CHECK:    [[INPUT0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT0_TILE0:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT0_TILE1:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // For Multiply Second Input
    // CHECK:    [[INPUT1_TILE0:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 0, 0] [1, 1, 1, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x1x1x88xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x1x1x88xf16, {order = #NHWC, strides = [88, 1, 88, 1]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>

    // CHECK:    [[INPUT1_TILE1:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 0, 0] [1, 1, 1, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x1x1x88xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x1x1x88xf16, {order = #NHWC, strides = [88, 1, 88, 1]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>

    // CHECK:    [[MULTI_OUT:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[MULTI_OUT_TILE0:%.*]] = VPUIP.SubView [[MULTI_OUT]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:    [[MULTI_OUT_TILE1:%.*]] = VPUIP.SubView [[MULTI_OUT]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:    [[MULTIPLY:%.*]]:2 = VPUIP.NCEClusterTiling
    // CHECK:                     inputs([[INPUT0_TILE1]] as %arg0: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE1]] as %arg1: memref<1x1x1x88xf16, #NHWC, @CMX_NN>
    // CHECK:                            [[INPUT0_TILE0]] as %arg2: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE0]] as %arg3: memref<1x1x1x88xf16, #NHWC, @CMX_NN>
    // CHECK:                     outputs([[MULTI_OUT_TILE1]] as %arg4: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[MULTI_OUT_TILE0]] as %arg5: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     -> (!VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:    %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Multiply
    // CHECK:                     inputs(%arg0 as %arg6: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg1 as %arg7: memref<1x1x1x88xf16, #NHWC, @CMX_NN>
    // CHECK:                            %arg2 as %arg8: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg3 as %arg9: memref<1x1x1x88xf16, #NHWC, @CMX_NN>
    // CHECK:                     outputs(%arg4 as %arg10: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                             %arg5 as %arg11: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg7, %arg10) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x1x1x88xf16, #NHWC, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}(%arg8, %arg9, %arg11) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x1x1x88xf16, #NHWC, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>

    // CHECK:    [[CONCATVIEW:%.*]] = VPUIP.ConcatView inputs([[MULTIPLY]]#0, [[MULTIPLY]]#1
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK:                     outputs([[MULTI_OUT]] : !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[OUTPUT_BUF:%.*]] = memref.alloc() : memref<1x64x88x88xf16>
    // CHECK:    [[OUTPUT_COPY:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCATVIEW]] as %arg0: memref<1x64x88x88xf16, @CMX_NN>)
    // CHECK:                                                 outputs([[OUTPUT_BUF]] as %arg1: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>

    // CHECK:    return [[OUTPUT_COPY]] : memref<1x64x88x88xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW {
  func.func private @builtin_Multiply(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>) attributes {VPU.kernel_code = "eltwise_mul.cpp", VPU.kernel_entry = "eltwise_mul"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterMultiplyWithSameInputs() -> memref<1x64x88x88xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    %2 = VPUIP.NCEClusterTiling inputs(%0 as %arg0: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                                          %0 as %arg1: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                                  outputs(%1 as %arg2: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                                      -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Multiply
                    inputs(%arg0 as %arg3: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                           %arg1 as %arg4: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                    outputs(%arg2 as %arg5: memref<1x64x88x88xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x64x88x88xf16, #NHWC, @CMX_NN>{
        VPUIP.SW.Kernel.run(%arg3, %arg4, %arg5) : memref<1x64x88x88xf16, #NHWC, @CMX_NN>, memref<1x64x88x88xf16, #NHWC, @CMX_NN>, memref<1x64x88x88xf16, #NHWC, @CMX_NN>
      }
    }

    %3 = memref.alloc() : memref<1x64x88x88xf16>
    %4 = VPUIP.NCEClusterTiling inputs(%2 as %arg1: memref<1x64x88x88xf16, @CMX_NN>) outputs(%3 as %arg2: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16> {
      %results = VPUIP.Copy inputs(%arg1 : memref<1x64x88x88xf16, @CMX_NN>) outputs(%arg2 : memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>
    }

    return %4: memref<1x64x88x88xf16>

    // CHECK:    [[INPUT0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT0_TILE0:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT1_TILE0:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT0_TILE1:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT1_TILE1:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[MULTI_OUT:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[MULTI_OUT_TILE0:%.*]] = VPUIP.SubView [[MULTI_OUT]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:    [[MULTI_OUT_TILE1:%.*]] = VPUIP.SubView [[MULTI_OUT]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:    [[MULTIPLY:%.*]]:2 = VPUIP.NCEClusterTiling
    // CHECK:                     inputs([[INPUT1_TILE1]] as [[ARG0:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT0_TILE1]] as [[ARG1:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE0]] as [[ARG2:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT0_TILE0]] as [[ARG3:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     outputs([[MULTI_OUT_TILE1]] as [[ARG4:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[MULTI_OUT_TILE0]] as [[ARG5:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     -> (!VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK:    %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Multiply
    // CHECK:                     inputs([[ARG0]] as [[ARG6:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[ARG1]] as [[ARG7:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[ARG2]] as [[ARG8:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[ARG3]] as [[ARG9:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     outputs([[ARG4]] as [[ARG10:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                             [[ARG5]] as [[ARG11:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}([[ARG6]], [[ARG7]], [[ARG10]]) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}([[ARG8]], [[ARG9]], [[ARG11]]) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>

    // CHECK:    [[CONCATVIEW:%.*]] = VPUIP.ConcatView inputs([[MULTIPLY]]#0, [[MULTIPLY]]#1
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK:                     outputs([[MULTI_OUT]] : !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[OUTPUT_BUF:%.*]] = memref.alloc() : memref<1x64x88x88xf16>
    // CHECK:    [[OUTPUT_COPY:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCATVIEW]] as %arg0: memref<1x64x88x88xf16, @CMX_NN>)
    // CHECK:                                                 outputs([[OUTPUT_BUF]] as %arg1: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>

    // CHECK:    return [[OUTPUT_COPY]] : memref<1x64x88x88xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW {
    func.func private @builtin_Minimum(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>) attributes {VPU.kernel_code = "eltwise_min.cpp", VPU.kernel_entry = "eltwise_min"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterMinimum() -> memref<1x64x88x88xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    %3 = VPUIP.NCEClusterTiling inputs(%0 as %arg0: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                                          %1 as %arg1: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                                  outputs(%2 as %arg2: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                                      -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Minimum
                    inputs(%arg0 as %arg3: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                           %arg1 as %arg4: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                    outputs(%arg2 as %arg5: memref<1x64x88x88xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x64x88x88xf16, #NHWC, @CMX_NN>{
        VPUIP.SW.Kernel.run(%arg3, %arg4, %arg5) : memref<1x64x88x88xf16, #NHWC, @CMX_NN>, memref<1x64x88x88xf16, #NHWC, @CMX_NN>, memref<1x64x88x88xf16, #NHWC, @CMX_NN>
      }
    }

    %4 = memref.alloc() : memref<1x64x88x88xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg1: memref<1x64x88x88xf16, @CMX_NN>) outputs(%4 as %arg2: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16> {
      %results = VPUIP.Copy inputs(%arg1 : memref<1x64x88x88xf16, @CMX_NN>) outputs(%arg2 : memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>
    }

    return %5: memref<1x64x88x88xf16>

    // For Minimum Input & Output
    // CHECK:    [[INPUT0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT0_TILE0:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT0_TILE1:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT1_TILE0:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT1_TILE1:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[MIN_OUT:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[MIN_OUT_TILE0:%.*]] = VPUIP.SubView [[MIN_OUT]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:    [[MIN_OUT_TILE1:%.*]] = VPUIP.SubView [[MIN_OUT]] [0, 0, 0, 0] [1, 64, 44, 88]

    // CHECK:    [[MINIMUM:%.*]]:2 = VPUIP.NCEClusterTiling
    // CHECK:                     inputs([[INPUT0_TILE1]] as [[INPUT0_TILE1_ARG:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE1]] as [[INPUT1_TILE1_ARG:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT0_TILE0]] as [[INPUT0_TILE0_ARG:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE0]] as [[INPUT1_TILE0_ARG:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     outputs([[MIN_OUT_TILE1]] as [[MIN_OUT_TILE1_ARG:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                             [[MIN_OUT_TILE0]] as [[MIN_OUT_TILE0_ARG:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     -> (!VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK:    %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Minimum
    // CHECK:                     inputs([[INPUT0_TILE1_ARG]] as [[INPUT0_TILE1_SW_ARG:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE1_ARG]] as [[INPUT1_TILE1_SW_ARG:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT0_TILE0_ARG]] as [[INPUT0_TILE0_SW_ARG:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE0_ARG]] as [[INPUT1_TILE0_SW_ARG:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     outputs([[MIN_OUT_TILE1_ARG]] as [[MIN_OUT_TILE1_SW_ARG:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                             [[MIN_OUT_TILE0_ARG]] as [[MIN_OUT_TILE0_SW_ARG:[^:]+]]: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}([[INPUT0_TILE1_SW_ARG]], [[INPUT1_TILE1_SW_ARG]], [[MIN_OUT_TILE1_SW_ARG]]) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}([[INPUT0_TILE0_SW_ARG]], [[INPUT1_TILE0_SW_ARG]], [[MIN_OUT_TILE0_SW_ARG]]) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>

    // CHECK:    [[CONCATVIEW:%.*]] = VPUIP.ConcatView inputs([[MINIMUM]]#0, [[MINIMUM]]#1
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK:                     outputs([[MIN_OUT]] : !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[OUTPUT_BUF:%.*]] = memref.alloc() : memref<1x64x88x88xf16>
    // CHECK:    [[OUTPUT_COPY:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCATVIEW]] as [[INPUT0_TILE1_ARG]]: memref<1x64x88x88xf16, @CMX_NN>)
    // CHECK:                                                 outputs([[OUTPUT_BUF]] as [[INPUT1_TILE1_ARG]]: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>

    // CHECK:    return [[OUTPUT_COPY]] : memref<1x64x88x88xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

// CHECK-LABEL: @SkipMVNTiling
module @SkipMVNTiling attributes {} {
    VPURT.SW.Runtime entryPoint : @VPU.SW::@runtime stack_configuration : [4096, 4096, 4096, 4096]
    module @VPU.SW {
        func.func private
            @builtin_MVN(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64)
            attributes {VPU.kernel_code = "singleShaveMVN.cpp", VPU.kernel_entry = "singleShaveMVN"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @main(%NET_INPUT: memref<1x32x5120x1xf16>,
                %NET_OUTPUT: memref<1x32x5120x1xf16>)
        -> memref<1x32x5120x1xf16> {
    %ALLOC_INPUT_DIST = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<
        1x32x5120x1xf16,
        #NCHW,
        @CMX_NN, {
            mode = "SEGMENTED",
            num_tiles = [1, 2, 1, 1],
            num_clusters = 2 : i64,
            alignment = [1, 16, 1, 1]
        }>

    %INPUT_TILING_COPY = VPUIP.NCEClusterTiling
        inputs(%NET_INPUT as %arg2: memref<1x32x5120x1xf16>)
        outputs(%ALLOC_INPUT_DIST as %arg3: memref<1x32x5120x1xf16, @CMX_NN>)
            -> !VPUIP.DistributedBuffer<
                1x32x5120x1xf16,
                #NCHW,
                @CMX_NN, {
                    mode = "SEGMENTED",
                    num_tiles = [1, 2, 1, 1],
                    num_clusters = 2 : i64,
                    alignment = [1, 16, 1, 1]
                }> {
      %INPUT_COPY = VPUIP.Copy
          inputs(%arg2 : memref<1x32x5120x1xf16>)
          outputs(%arg3 : memref<1x32x5120x1xf16, @CMX_NN>)
            -> memref<1x32x5120x1xf16, @CMX_NN>
    }

    %MVN_OUTPUT = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<
        1x32x5120x1xf16,
        #NCHW,
        @CMX_NN, {
            mode = "SEGMENTED",
            num_tiles = [1, 2, 1, 1],
            num_clusters = 2 : i64
        }>

    %MVN_TILING = VPUIP.NCEClusterTiling
        inputs(%INPUT_TILING_COPY as %arg2: memref<1x32x5120x1xf16, @CMX_NN>)
        outputs(%MVN_OUTPUT as %arg3: memref<1x32x5120x1xf16, @CMX_NN>)
            -> !VPUIP.DistributedBuffer<
                    1x32x5120x1xf16,
                    #NCHW,
                    @CMX_NN, {
                        mode = "SEGMENTED",
                        num_tiles = [1, 2, 1, 1],
                        num_clusters = 2 : i64
                    }> {
      %results = VPUIP.SW.Kernel {
          resultSegmentSizes = array<i32: 1, 0>
      } @VPU.SW::@builtin_MVN
        inputs(%arg2 as %arg4: memref<1x32x5120x1xf16, @CMX_NN>)
        outputs(%arg3 as %arg5: memref<1x32x5120x1xf16, @CMX_NN>) on tile 0
            -> memref<1x32x5120x1xf16, @CMX_NN>{
        VPUIP.SW.Kernel.run {
            attrs = [false, true, 9.9999997473787516E-6]
        }(%arg4, %arg5) : memref<1x32x5120x1xf16, @CMX_NN>, memref<1x32x5120x1xf16, @CMX_NN>
      }
    }

    %OUTPUT_TILING_COPY = VPUIP.NCEClusterTiling
        inputs(%MVN_TILING as %arg2: memref<1x32x5120x1xf16, @CMX_NN>)
        outputs(%NET_OUTPUT as %arg3: memref<1x32x5120x1xf16>)
            -> memref<1x32x5120x1xf16> {
      %OUTPUT_COPY = VPUIP.Copy
          inputs(%arg2 : memref<1x32x5120x1xf16, @CMX_NN>)
          outputs(%arg3 : memref<1x32x5120x1xf16>)
            -> memref<1x32x5120x1xf16>
    }

    return %OUTPUT_TILING_COPY : memref<1x32x5120x1xf16>

    // CHECK: ([[NET_INPUT:%.*]]: memref<1x32x5120x1xf16>, [[NET_OUTPUT:%.*]]: memref<1x32x5120x1xf16>)

    // CHECK:   [[ALLOC_INPUT_DIST:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME:  -> !VPUIP.DistributedBuffer<1x32x5120x1xf16
    // CHECK-SAME:      alignment = [1, 16, 1, 1]

    // CHECK:   [[INPUT_TILING_COPY:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:  inputs([[NET_INPUT]] as %arg2: memref<1x32x5120x1xf16>)
    // CHECK-SAME:  outputs([[ALLOC_INPUT_DIST]] as %arg3: memref<1x32x5120x1xf16, @CMX_NN>)
    // CHECK-SAME:  -> !VPUIP.DistributedBuffer<1x32x5120x1xf16,
    // CHECK-SAME:      alignment = [1, 16, 1, 1]

    // CHECK:   [[MVN_OUTPUT:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME:  -> !VPUIP.DistributedBuffer<1x32x5120x1xf16,

    // CHECK:   [[MVN_TILING:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:  inputs([[INPUT_TILING_COPY]] as %arg2: memref<1x32x5120x1xf16, @CMX_NN>)
    // CHECK-SAME:  outputs([[MVN_OUTPUT]] as %arg3: memref<1x32x5120x1xf16, @CMX_NN>)
    // CHECK-SAME:  -> !VPUIP.DistributedBuffer<1x32x5120x1xf16,
    // CHECK:       VPUIP.SW.Kernel.run {{.*}} : memref<1x32x5120x1xf16
    // CHECK-NOT:   VPUIP.SW.Kernel.run {{.*}} : memref<1x16x5120x1xf16

    // CHECK:   [[OUTPUT_TILING_COPY:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:  inputs([[MVN_TILING]] as %arg2: memref<1x32x5120x1xf16, @CMX_NN>)
    // CHECK-SAME:  outputs([[NET_OUTPUT]] as %arg3: memref<1x32x5120x1xf16>)
    // CHECK-SAME:  -> memref<1x32x5120x1xf16>

    // CHECK:   return [[OUTPUT_TILING_COPY]] : memref<1x32x5120x1xf16>
}
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW  {
    func.func private @builtin_Convert(memref<*xf32>, memref<*xf16>) attributes {VPU.kernel_code = "single_shave_convert.cpp", VPU.kernel_entry = "single_shave_convert"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileConvertOpTest(%arg0: memref<1x64x16x16xf32>)
        -> memref<1x64x16x16xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x16x16xf32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x64x16x16xf32>) outputs(%0 as %arg2: memref<1x64x16x16xf32, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x64x16x16xf32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x64x16x16xf32>) outputs(%arg2 : memref<1x64x16x16xf32, @CMX_NN>) -> memref<1x64x16x16xf32, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x16x16xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x64x16x16xf32, #NCHW, @CMX_NN>) outputs(%3 as %arg2: memref<1x64x16x16xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x64x16x16xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Convert inputs(%arg1 as %arg6: memref<1x64x16x16xf32, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x64x16x16xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x64x16x16xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run {attrs = [0]}(%arg6, %arg7) : memref<1x64x16x16xf32, @CMX_NN>, memref<1x64x16x16xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x64x16x16xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x64x16x16xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x64x16x16xf16>) -> memref<1x64x16x16xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x64x16x16xf16, @CMX_NN>) outputs(%arg2 : memref<1x64x16x16xf16>) -> memref<1x64x16x16xf16>
    }
    return %6: memref<1x64x16x16xf16>
    // CHECK:   [[SUBVIEW1:%.*]] = VPUIP.SubView %arg0 [0, 0, 8, 0] [1, 64, 8, 16] : memref<1x64x16x16xf32> to memref<1x64x8x16xf32, {order = #NCHW, strides = [16384, 256, 16, 1]}>
    // CHECK:   [[ALLOC_DSTR1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x8x16xf32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:   [[TILING_COPY1:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x64x8x16xf32, {order = #NCHW, strides = [16384, 256, 16, 1]}>) outputs(%1 as %arg2: memref<1x64x8x16xf32, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x64x8x16xf32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:   VPUIP.Copy inputs(%arg1 : memref<1x64x8x16xf32, {order = #NCHW, strides = [16384, 256, 16, 1]}>) outputs(%arg2 : memref<1x64x8x16xf32, @CMX_NN>) -> memref<1x64x8x16xf32, @CMX_NN>
    // CHECK:   }
    // CHECK:   [[SUBVIEW2:%.*]] = VPUIP.SubView %arg0 [0, 0, 0, 0] [1, 64, 8, 16] : memref<1x64x16x16xf32> to memref<1x64x8x16xf32, {order = #NCHW, strides = [16384, 256, 16, 1]}>
    // CHECK:   [[ALLOC_DSTR2:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x8x16xf32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:   [[TILING_COPY2:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW2]] as %arg1: memref<1x64x8x16xf32, {order = #NCHW, strides = [16384, 256, 16, 1]}>) outputs([[ALLOC_DSTR2]] as %arg2: memref<1x64x8x16xf32, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x64x8x16xf32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:   VPUIP.Copy inputs(%arg1 : memref<1x64x8x16xf32, {order = #NCHW, strides = [16384, 256, 16, 1]}>) outputs(%arg2 : memref<1x64x8x16xf32, @CMX_NN>) -> memref<1x64x8x16xf32, @CMX_NN>
    // CHECK:   }
    // CHECK:   [[ALLOC_DSTR3:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x8x16xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:   [[ALLOC_DSTR4:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x8x16xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:   [[TILING_KERNEL:%.*]] = VPUIP.NCEClusterTiling inputs([[TILING_COPY2]] as %arg1: memref<1x64x8x16xf32, @CMX_NN>, [[TILING_COPY1]] as %arg2: memref<1x64x8x16xf32, @CMX_NN>) outputs([[ALLOC_DSTR4]] as %arg3: memref<1x64x8x16xf16, @CMX_NN>, [[ALLOC_DSTR3]] as %arg4: memref<1x64x8x16xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x64x8x16xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x64x8x16xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:   VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Convert inputs(%arg1 as %arg5: memref<1x64x8x16xf32, @CMX_NN>, %arg2 as %arg6: memref<1x64x8x16xf32, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x64x8x16xf16, @CMX_NN>, %arg4 as %arg8: memref<1x64x8x16xf16, @CMX_NN>) on tile 0 -> (memref<1x64x8x16xf16, @CMX_NN>, memref<1x64x8x16xf16, @CMX_NN>){
    // CHECK:    VPUIP.SW.Kernel.run {attrs = [0]}(%arg5, %arg7) : memref<1x64x8x16xf32, @CMX_NN>, memref<1x64x8x16xf16, @CMX_NN>
    // CHECK:    VPUIP.SW.Kernel.run {attrs = [0]}(%arg6, %arg8) : memref<1x64x8x16xf32, @CMX_NN>, memref<1x64x8x16xf16, @CMX_NN>
    // CHECK:   }
    // CHECK:   }
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW  {
    func.func private @builtin_Convert(memref<*xf32>, memref<*xf16>) attributes {VPU.kernel_code = "single_shave_convert.cpp", VPU.kernel_entry = "single_shave_convert"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @NotTileConvertOpTest(%arg0: memref<1x64x16x16xf32>)
        -> memref<1x64x16x16xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x16x16xf32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x64x16x16xf32>) outputs(%0 as %arg2: memref<1x64x16x16xf32, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x64x16x16xf32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x64x16x16xf32>) outputs(%arg2 : memref<1x64x16x16xf32, @CMX_NN>) -> memref<1x64x16x16xf32, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x16x16xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x64x16x16xf32, #NCHW, @CMX_NN>) outputs(%3 as %arg2: memref<1x64x16x16xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x64x16x16xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Convert inputs(%arg1 as %arg6: memref<1x64x16x16xf32, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x64x16x16xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x64x16x16xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run {attrs = [0]}(%arg6, %arg7) : memref<1x64x16x16xf32, @CMX_NN>, memref<1x64x16x16xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x64x16x16xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x64x16x16xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x64x16x16xf16>) -> memref<1x64x16x16xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x64x16x16xf16, @CMX_NN>) outputs(%arg2 : memref<1x64x16x16xf16>) -> memref<1x64x16x16xf16>
    }
    return %6: memref<1x64x16x16xf16>
    // CHECK:   [[ALLOC_DSTR1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x16x16xf32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>


    // CHECK:   [[TILING_COPY1:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x64x16x16xf32>) outputs(%0 as %arg2: memref<1x64x16x16xf32, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x64x16x16xf32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}> {
    // CHECK:   }
    // CHECK:	[[ALLOC_DSTR2:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x16x16xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:   [[TILING_KERNEL:%.*]] = VPUIP.NCEClusterTiling inputs([[TILING_COPY1]] as %arg1: memref<1x64x16x16xf32, @CMX_NN>) outputs([[ALLOC_DSTR2]] as %arg2: memref<1x64x16x16xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x64x16x16xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:   VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Convert inputs(%arg1 as %arg3: memref<1x64x16x16xf32, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x64x16x16xf16, @CMX_NN>) on tile 0 -> memref<1x64x16x16xf16, @CMX_NN>{
    // CHECK:    VPUIP.SW.Kernel.run {attrs = [0]}(%arg3, %arg4) : memref<1x64x16x16xf32, @CMX_NN>, memref<1x64x16x16xf16, @CMX_NN>
    // CHECK:   }
    // CHECK:   }
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_Tanh(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "tanh_fp16.cpp", VPU.kernel_entry = "tanh_fp16"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterTanh(%arg0: memref<1x128x64x32xf16>)
        -> memref<1x128x64x32xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16>) outputs(%arg2 : memref<1x128x64x32xf16, @CMX_NN>) -> memref<1x128x64x32xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%3 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Tanh inputs(%arg1 as %arg6: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x128x64x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run(%arg6, %arg7) : memref<1x128x64x32xf16, @CMX_NN>, memref<1x128x64x32xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x64x32xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    }
    return %6: memref<1x128x64x32xf16>

    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView %arg0 [0, 0, 32, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[INPUT_BUF0:%.*]] = VPURT.AllocDistributed
    // CHECK-SAME{LITERAL}:     VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY2:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW0]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[INPUT_BUF0]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs(%arg2 : memref<1x128x32x32xf16, @CMX_NN>) -> memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView %arg0 [0, 0, 0, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[INPUT_BUF1:%.*]] = VPURT.AllocDistributed ->
    // CHECK-SAME{LITERAL}:     !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY4:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[INPUT_BUF1]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>)
    // CHECK:                       VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs(%arg2 : memref<1x128x32x32xf16, @CMX_NN>) -> memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[CLUSTER_TANH:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[COPY4]] as %arg1: memref<1x128x32x32xf16, @CMX_NN>, [[COPY2]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>) outputs([[OUTPUT_BUF0]] as %arg3: memref<1x128x32x32xf16, @CMX_NN>, [[OUTPUT_BUF1]] as %arg4: memref<1x128x32x32xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                   %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Tanh inputs(%arg1 as %arg5: memref<1x128x32x32xf16, @CMX_NN>, %arg2 as %arg6: memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x128x32x32xf16, @CMX_NN>, %arg4 as %arg8: memref<1x128x32x32xf16, @CMX_NN>) on tile 0 -> (memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>){
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = []}(%arg5, %arg7) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:                     VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg8) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:                   }
    // CHECK:    }
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY5:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_TANH]]#0 as %arg1: memref<1x128x32x32xf16, @CMX_NN>) outputs([[SUBVIEW2]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    }
    // CHECK:    [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 32, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY6:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_TANH]]#1 as %arg1: memref<1x128x32x32xf16, @CMX_NN>) outputs([[SUBVIEW3]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:               VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[COPY5]], [[COPY6]] : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[OUTPUT_DDR]] : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    // CHECK:    return [[CONCAT]] : memref<1x128x64x32xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW  {
    func.func private @builtin_TopK(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, memref<*xsi32, @CMX_NN>, i64, i64, i64, i64) attributes {VPU.kernel_code = "single_shave_topk.cpp", VPU.kernel_entry = "single_shave_topk"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}
func.func @TileClusterTopKWithCopyUser(%arg0: memref<1x8x128x128xf16, #NHWC>, %arg1: memref<1x1x128x128xsi32, #NHWC>) -> memref<1x1x128x128xsi32, #NHWC> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x8x128x128xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg2: memref<1x8x128x128xf16, #NHWC>) outputs(%0 as %arg3: memref<1x8x128x128xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x8x128x128xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %8 = VPUIP.Copy inputs(%arg2 : memref<1x8x128x128xf16, #NHWC>) outputs(%arg3 : memref<1x8x128x128xf16, #NHWC, @CMX_NN>) -> memref<1x8x128x128xf16, #NHWC, @CMX_NN>
    }
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x128x128xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x128x128xsi32, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4:2 = VPUIP.NCEClusterTiling inputs(%1 as %arg2: memref<1x8x128x128xf16, #NHWC, @CMX_NN>) outputs(%2 as %arg3: memref<1x1x128x128xf16, #NHWC, @CMX_NN>, %3 as %arg4: memref<1x1x128x128xsi32, #NHWC, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x1x128x128xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x1x128x128xsi32, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
      %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_TopK inputs(%arg2 as %arg5: memref<1x8x128x128xf16, #NHWC, @CMX_NN>) outputs(%arg3 as %arg6: memref<1x1x128x128xf16, #NHWC, @CMX_NN>, %arg4 as %arg7: memref<1x1x128x128xsi32, #NHWC, @CMX_NN>) on tile 0 -> (memref<1x1x128x128xf16, #NHWC, @CMX_NN>, memref<1x1x128x128xsi32, #NHWC, @CMX_NN>){
        VPUIP.SW.Kernel.run {attrs = [0, 0, 2, 1]}(%arg5, %arg6, %arg7) : memref<1x8x128x128xf16, #NHWC, @CMX_NN>, memref<1x1x128x128xf16, #NHWC, @CMX_NN>, memref<1x1x128x128xsi32, #NHWC, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x1x128x128xsi32, #NHWC>
    %6 = VPUIP.NCEClusterTiling inputs(%4#1 as %arg2: memref<1x1x128x128xsi32, #NHWC, @CMX_NN>) outputs(%5 as %arg3: memref<1x1x128x128xsi32, #NHWC>) -> memref<1x1x128x128xsi32, #NHWC> {
      %8 = VPUIP.Copy inputs(%arg2 : memref<1x1x128x128xsi32, #NHWC, @CMX_NN>) outputs(%arg3 : memref<1x1x128x128xsi32, #NHWC>) -> memref<1x1x128x128xsi32, #NHWC>
    }
    %7 = VPUIP.Copy inputs(%6 : memref<1x1x128x128xsi32, #NHWC>) outputs(%arg1 : memref<1x1x128x128xsi32, #NHWC>) -> memref<1x1x128x128xsi32, #NHWC>
    return %7 : memref<1x1x128x128xsi32, #NHWC>

    // CHECK:                [[INPUT_BUF:%.*]] = VPURT.AllocDistributed ->
    // CHECK-SAME{LITERAL}:      !VPUIP.DistributedBuffer<1x8x128x128xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:                [[CLUSTER_COPY_INPUT:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg2: memref<1x8x128x128xf16, #NHWC>) outputs([[INPUT_BUF]] as %arg3: memref<1x8x128x128xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x8x128x128xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                    VPUIP.Copy inputs(%arg2 : memref<1x8x128x128xf16, #NHWC>) outputs(%arg3 : memref<1x8x128x128xf16, #NHWC, @CMX_NN>) -> memref<1x8x128x128xf16, #NHWC, @CMX_NN>
    // CHECK:                }
    // CHECK:                [[SUBVIEW0:%.*]] = VPUIP.SubView [[CLUSTER_COPY_INPUT]] [0, 0, 64, 0] [1, 8, 64, 128] : !VPUIP.DistributedBuffer<1x8x128x128xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x8x64x128xf16, {order = #NHWC, strides = [131072, 1, 1024, 8]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:                [[SUBVIEW1:%.*]] = VPUIP.SubView [[CLUSTER_COPY_INPUT]] [0, 0, 0, 0] [1, 8, 64, 128] : !VPUIP.DistributedBuffer<1x8x128x128xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x8x64x128xf16, {order = #NHWC, strides = [131072, 1, 1024, 8]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:                [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x128x128xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:                [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_BUF0]] [0, 0, 64, 0] [1, 1, 64, 128] : !VPUIP.DistributedBuffer<1x1x128x128xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x1x64x128xf16, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:                [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_BUF0]] [0, 0, 0, 0] [1, 1, 64, 128] : !VPUIP.DistributedBuffer<1x1x128x128xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x1x64x128xf16, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:                [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x128x128xsi32, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:                [[SUBVIEW4:%.*]] = VPUIP.SubView [[OUTPUT_BUF1]] [0, 0, 64, 0] [1, 1, 64, 128] : !VPUIP.DistributedBuffer<1x1x128x128xsi32, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x1x64x128xsi32, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:                [[SUBVIEW5:%.*]] = VPUIP.SubView [[OUTPUT_BUF1]] [0, 0, 0, 0] [1, 1, 64, 128] : !VPUIP.DistributedBuffer<1x1x128x128xsi32, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x1x64x128xsi32, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:                [[CLUSTER_TOPK:%.*]]:4 = VPUIP.NCEClusterTiling
    // CHECK-SAME:               inputs([[SUBVIEW1]] as %arg2: memref<1x8x64x128xf16, {order = #NHWC, strides = [131072, 1, 1024, 8]}, @CMX_NN>,
    // CHECK-SAME:                      [[SUBVIEW0]] as %arg3: memref<1x8x64x128xf16, {order = #NHWC, strides = [131072, 1, 1024, 8]}, @CMX_NN>)
    // CHECK-SAME:               outputs([[SUBVIEW3]] as %arg4: memref<1x1x64x128xf16, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>,
    // CHECK-SAME:                       [[SUBVIEW5]] as %arg5: memref<1x1x64x128xsi32, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>,
    // CHECK-SAME:                       [[SUBVIEW2]] as %arg6: memref<1x1x64x128xf16, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>,
    // CHECK-SAME:                       [[SUBVIEW4]] as %arg7: memref<1x1x64x128xsi32, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>)
    // CHECK-SAME:               -> (!VPUIP.DistributedBuffer<1x1x64x128xf16, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK-SAME:                   !VPUIP.DistributedBuffer<1x1x64x128xsi32, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK-SAME:                   !VPUIP.DistributedBuffer<1x1x64x128xf16, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK-SAME:                   !VPUIP.DistributedBuffer<1x1x64x128xsi32, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                    %results:4 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 4, 0>} @VPU.SW::@builtin_TopK
    // CHECK-SAME:                   inputs(%arg2 as %arg8: memref<1x8x64x128xf16, {order = #NHWC, strides = [131072, 1, 1024, 8]}, @CMX_NN>,
    // CHECK-SAME:                          %arg3 as %arg9: memref<1x8x64x128xf16, {order = #NHWC, strides = [131072, 1, 1024, 8]}, @CMX_NN>)
    // CHECK-SAME:                   outputs(%arg4 as %arg10: memref<1x1x64x128xf16, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>,
    // CHECK-SAME:                           %arg5 as %arg11: memref<1x1x64x128xsi32, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>,
    // CHECK-SAME:                           %arg6 as %arg12: memref<1x1x64x128xf16, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>,
    // CHEKC-SAME{LITERAL}:                   %arg7 as %arg13: memref<1x1x64x128xsi32, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>) strides([[8192, 1, 128, 1], [8192, 1, 128, 1]]) on tile 0
    // CHECK-SAME:                   -> (memref<1x1x64x128xf16, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>,
    // CHECK-SAME:                       memref<1x1x64x128xsi32, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>,
    // CHECK-SAME:                       memref<1x1x64x128xf16, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>,
    // CHECK-SAME:                       memref<1x1x64x128xsi32, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>){
    // CHECK:                        VPUIP.SW.Kernel.run {attrs = [0, 0, 2, 1]}(%arg8, %arg10, %arg11) :
    // CHECK-SAME:                       memref<1x8x64x128xf16, {order = #NHWC, strides = [131072, 1, 1024, 8]}, @CMX_NN>,
    // CHECK-SAME:                       memref<1x1x64x128xf16, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>,
    // CHECK-SAME:                       memref<1x1x64x128xsi32, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>
    // CHECK:                        VPUIP.SW.Kernel.run {attrs = [0, 0, 2, 1]}(%arg9, %arg12, %arg13) :
    // CHECK-SAME:                       memref<1x8x64x128xf16, {order = #NHWC, strides = [131072, 1, 1024, 8]}, @CMX_NN>,
    // CHECK-SAME:                       memref<1x1x64x128xf16, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>,
    // CHECK-SAME:                       memref<1x1x64x128xsi32, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN>
    // CHECK:                    }
    // CHECK:                }

    // CHECK:                [[CONCAT:%.*]] = VPUIP.ConcatView
    // CHECK-SAME:               inputs([[CLUSTER_TOPK]]#1, [[CLUSTER_TOPK]]#3 :
    // CHECK-SAME:                   !VPUIP.DistributedBuffer<1x1x64x128xsi32, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK-SAME:                   !VPUIP.DistributedBuffer<1x1x64x128xsi32, {order = #NHWC, strides = [16384, 1, 128, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK-SAME:               outputs([[OUTPUT_BUF1]] : !VPUIP.DistributedBuffer<1x1x128x128xsi32, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK-SAME:               -> !VPUIP.DistributedBuffer<1x1x128x128xsi32, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:                [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x1x128x128xsi32, #NHWC>
    // CHECK:                [[CLUSTER_COPY_OUTPUT:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCAT]] as %arg2: memref<1x1x128x128xsi32, #NHWC, @CMX_NN>) outputs([[OUTPUT_DDR]] as %arg3: memref<1x1x128x128xsi32, #NHWC>) -> memref<1x1x128x128xsi32, #NHWC> {
    // CHECK:                    VPUIP.Copy inputs(%arg2 : memref<1x1x128x128xsi32, #NHWC, @CMX_NN>) outputs(%arg3 : memref<1x1x128x128xsi32, #NHWC>) -> memref<1x1x128x128xsi32, #NHWC>
    // CHECK:                [[OUTPUT_COPY:%.*]] = VPUIP.Copy inputs([[CLUSTER_COPY_OUTPUT]] : memref<1x1x128x128xsi32, #NHWC>) outputs(%arg1 : memref<1x1x128x128xsi32, #NHWC>) -> memref<1x1x128x128xsi32, #NHWC>
    // CHECK:                return [[OUTPUT_COPY]] : memref<1x1x128x128xsi32, #NHWC>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW  {
    func.func private @builtin_TopK(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, memref<*xsi32, @CMX_NN>, i64, i64, i64, i64) attributes {VPU.kernel_code = "single_shave_topk.cpp", VPU.kernel_entry = "single_shave_topk"}
    func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterTopKWithoutCopyUser(%arg0: memref<1x5x256x512xf16>, %arg1: memref<1x1x256x512xf16>, %arg2: memref<1x1x256x512xsi32>) -> (memref<1x1x256x512xf16>, memref<1x1x256x512xsi32>) {
    %0 = memref.alloc() : memref<1x5x256x512xf16>
    %1 = VPUIP.Copy inputs(%arg0 : memref<1x5x256x512xf16>) outputs(%0 : memref<1x5x256x512xf16>) -> memref<1x5x256x512xf16>
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x5x256x512xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %3 = VPUIP.NCEClusterTiling inputs(%1 as %arg3: memref<1x5x256x512xf16>) outputs(%2 as %arg4: memref<1x5x256x512xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x5x256x512xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %13 = VPUIP.Copy inputs(%arg3 : memref<1x5x256x512xf16>) outputs(%arg4 : memref<1x5x256x512xf16, @CMX_NN>) -> memref<1x5x256x512xf16, @CMX_NN>
    }
    %4 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x256x512xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %5 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x256x512xsi32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %6:2 = VPUIP.NCEClusterTiling inputs(%3 as %arg3: memref<1x5x256x512xf16, @CMX_NN>) outputs(%4 as %arg4: memref<1x1x256x512xf16, @CMX_NN>, %5 as %arg5: memref<1x1x256x512xsi32, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x1x256x512xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x1x256x512xsi32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
      %results_0:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_TopK inputs(%arg3 as %arg6: memref<1x5x256x512xf16, @CMX_NN>) outputs(%arg4 as %arg7: memref<1x1x256x512xf16, @CMX_NN>, %arg5 as %arg8: memref<1x1x256x512xsi32, @CMX_NN>) on tile 0 -> (memref<1x1x256x512xf16, @CMX_NN>, memref<1x1x256x512xsi32, @CMX_NN>){
        VPUIP.SW.Kernel.run {attrs = [2, 0, 2, 1]}(%arg6, %arg7, %arg8) : memref<1x5x256x512xf16, @CMX_NN>, memref<1x1x256x512xf16, @CMX_NN>, memref<1x1x256x512xsi32, @CMX_NN>
      }
    }
    %7 = memref.alloc() : memref<1x1x256x512xf16>
    %8 = VPUIP.NCEClusterTiling inputs(%6#0 as %arg3: memref<1x1x256x512xf16, @CMX_NN>) outputs(%7 as %arg4: memref<1x1x256x512xf16>) -> memref<1x1x256x512xf16> {
      %13 = VPUIP.Copy inputs(%arg3 : memref<1x1x256x512xf16, @CMX_NN>) outputs(%arg4 : memref<1x1x256x512xf16>) -> memref<1x1x256x512xf16>
    }
    %9 = memref.alloc() : memref<1x1x256x512xsi32>
    %10 = VPUIP.NCEClusterTiling inputs(%6#1 as %arg3: memref<1x1x256x512xsi32, @CMX_NN>) outputs(%9 as %arg4: memref<1x1x256x512xsi32>) -> memref<1x1x256x512xsi32> {
      %13 = VPUIP.Copy inputs(%arg3 : memref<1x1x256x512xsi32, @CMX_NN>) outputs(%arg4 : memref<1x1x256x512xsi32>) -> memref<1x1x256x512xsi32>
    }
    %11 = VPUIP.Copy inputs(%8 : memref<1x1x256x512xf16>) outputs(%arg1 : memref<1x1x256x512xf16>) -> memref<1x1x256x512xf16>
    %12 = VPUIP.Copy inputs(%10 : memref<1x1x256x512xsi32>) outputs(%arg2 : memref<1x1x256x512xsi32>) -> memref<1x1x256x512xsi32>
    return %11, %12 : memref<1x1x256x512xf16>, memref<1x1x256x512xsi32>

    // CHECK:           [[ALLOC0:%.*]] = memref.alloc() : memref<1x5x256x512xf16>
    // CHECK:           [[COPY0:%.*]] = VPUIP.Copy inputs(%arg0 : memref<1x5x256x512xf16>) outputs([[ALLOC0]] : memref<1x5x256x512xf16>) -> memref<1x5x256x512xf16>
    // CHECK:           [[SUBVIEW0:%.*]] = VPUIP.SubView [[COPY0]] [0, 0, 128, 0] [1, 5, 128, 512] : memref<1x5x256x512xf16> to memref<1x5x128x512xf16, {order = #NCHW, strides = [655360, 131072, 512, 1]}>
    // CHECK:           [[ALLOC1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x5x128x512xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[TILING_INPUT0:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW0]] as %arg3: memref<1x5x128x512xf16, {order = #NCHW, strides = [655360, 131072, 512, 1]}>) outputs([[ALLOC1]] as %arg4: memref<1x5x128x512xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x5x128x512xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:               VPUIP.Copy inputs(%arg3 : memref<1x5x128x512xf16, {order = #NCHW, strides = [655360, 131072, 512, 1]}>) outputs(%arg4 : memref<1x5x128x512xf16, @CMX_NN>) -> memref<1x5x128x512xf16, @CMX_NN>
    // CHECK:           }
    // CHECK:           [[SUBVIEW1:%.*]] = VPUIP.SubView [[COPY0]] [0, 0, 0, 0] [1, 5, 128, 512] : memref<1x5x256x512xf16> to memref<1x5x128x512xf16, {order = #NCHW, strides = [655360, 131072, 512, 1]}>
    // CHECK:           [[ALLOC2:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x5x128x512xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[TILING_INPUT1:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg3: memref<1x5x128x512xf16, {order = #NCHW, strides = [655360, 131072, 512, 1]}>) outputs([[ALLOC2]] as %arg4: memref<1x5x128x512xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x5x128x512xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:               VPUIP.Copy inputs(%arg3 : memref<1x5x128x512xf16, {order = #NCHW, strides = [655360, 131072, 512, 1]}>) outputs(%arg4 : memref<1x5x128x512xf16, @CMX_NN>) -> memref<1x5x128x512xf16, @CMX_NN>
    // CHECK:           }
    // CHECK:           [[ALLOC3:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x128x512xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[ALLOC4:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x128x512xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[ALLOC5:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x128x512xsi32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[ALLOC6:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x128x512xsi32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[CLUSTER_TOPK:%.*]]:4 = VPUIP.NCEClusterTiling inputs([[TILING_INPUT1]] as %arg3: memref<1x5x128x512xf16, @CMX_NN>, [[TILING_INPUT0]] as %arg4: memref<1x5x128x512xf16, @CMX_NN>) outputs([[ALLOC4]] as %arg5: memref<1x1x128x512xf16, @CMX_NN>, [[ALLOC6]] as %arg6: memref<1x1x128x512xsi32, @CMX_NN>, [[ALLOC3]] as %arg7: memref<1x1x128x512xf16, @CMX_NN>, [[ALLOC5]] as %arg8: memref<1x1x128x512xsi32, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x1x128x512xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x1x128x512xsi32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x1x128x512xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x1x128x512xsi32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:               %results:4 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 4, 0>} @VPU.SW::@builtin_TopK inputs(%arg3 as %arg9: memref<1x5x128x512xf16, @CMX_NN>, %arg4 as %arg10: memref<1x5x128x512xf16, @CMX_NN>) outputs(%arg5 as %arg11: memref<1x1x128x512xf16, @CMX_NN>, %arg6 as %arg12: memref<1x1x128x512xsi32, @CMX_NN>, %arg7 as %arg13: memref<1x1x128x512xf16, @CMX_NN>, %arg8 as %arg14: memref<1x1x128x512xsi32, @CMX_NN>) on tile 0 -> (memref<1x1x128x512xf16, @CMX_NN>, memref<1x1x128x512xsi32, @CMX_NN>, memref<1x1x128x512xf16, @CMX_NN>, memref<1x1x128x512xsi32, @CMX_NN>){
    // CHECK:                   VPUIP.SW.Kernel.run {attrs = [2, 0, 2, 1]}(%arg9, %arg11, %arg12) : memref<1x5x128x512xf16, @CMX_NN>, memref<1x1x128x512xf16, @CMX_NN>, memref<1x1x128x512xsi32, @CMX_NN>
    // CHECK:                   VPUIP.SW.Kernel.run {attrs = [2, 0, 2, 1]}(%arg10, %arg13, %arg14) : memref<1x5x128x512xf16, @CMX_NN>, memref<1x1x128x512xf16, @CMX_NN>, memref<1x1x128x512xsi32, @CMX_NN>
    // CHECK:               }
    // CHECK:           }
    // CHECK:           [[ALLOC7:%.*]] = memref.alloc() : memref<1x1x256x512xf16, @DDR>
    // CHECK:           [[ALLOC8:%.*]] = memref.alloc() : memref<1x1x256x512xsi32, @DDR>
    // CHECK:           [[SUBVIEW2:%.*]] = VPUIP.SubView [[ALLOC7]] [0, 0, 0, 0] [1, 1, 128, 512] : memref<1x1x256x512xf16, @DDR> to memref<1x1x128x512xf16, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>
    // CHECK:           [[TILING_OUTPUT0:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_TOPK]]#0 as %arg3: memref<1x1x128x512xf16, @CMX_NN>) outputs([[SUBVIEW2]] as %arg4: memref<1x1x128x512xf16, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>) -> memref<1x1x128x512xf16, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR> {
    // CHECK:               VPUIP.Copy inputs(%arg3 : memref<1x1x128x512xf16, @CMX_NN>) outputs(%arg4 : memref<1x1x128x512xf16, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>) -> memref<1x1x128x512xf16, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>
    // CHECK:           }
    // CHECK:           [[SUBVIEW3:%.*]] = VPUIP.SubView [[ALLOC8]] [0, 0, 0, 0] [1, 1, 128, 512] : memref<1x1x256x512xsi32, @DDR> to memref<1x1x128x512xsi32, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>
    // CHECK:           [[TILING_OUTPUT1:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_TOPK]]#1 as %arg3: memref<1x1x128x512xsi32, @CMX_NN>) outputs([[SUBVIEW3]] as %arg4: memref<1x1x128x512xsi32, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>) -> memref<1x1x128x512xsi32, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR> {
    // CHECK:               VPUIP.Copy inputs(%arg3 : memref<1x1x128x512xsi32, @CMX_NN>) outputs(%arg4 : memref<1x1x128x512xsi32, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>) -> memref<1x1x128x512xsi32, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>
    // CHECK:           }
    // CHECK:           [[SUBVIEW4:%.*]] = VPUIP.SubView [[ALLOC7]] [0, 0, 128, 0] [1, 1, 128, 512] : memref<1x1x256x512xf16, @DDR> to memref<1x1x128x512xf16, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>
    // CHECK:           [[TILING_OUTPUT2:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_TOPK]]#2 as %arg3: memref<1x1x128x512xf16, @CMX_NN>) outputs([[SUBVIEW4]] as %arg4: memref<1x1x128x512xf16, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>) -> memref<1x1x128x512xf16, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR> {
    // CHECK:               VPUIP.Copy inputs(%arg3 : memref<1x1x128x512xf16, @CMX_NN>) outputs(%arg4 : memref<1x1x128x512xf16, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>) -> memref<1x1x128x512xf16, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>
    // CHECK:           }
    // CHECK:           [[SUBVIEW5:%.*]] = VPUIP.SubView [[ALLOC8]] [0, 0, 128, 0] [1, 1, 128, 512] : memref<1x1x256x512xsi32, @DDR> to memref<1x1x128x512xsi32, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>
    // CHECK:           [[TILING_OUTPUT3:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_TOPK]]#3 as %arg3: memref<1x1x128x512xsi32, @CMX_NN>) outputs([[SUBVIEW5]] as %arg4: memref<1x1x128x512xsi32, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>) -> memref<1x1x128x512xsi32, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR> {
    // CHECK:               VPUIP.Copy inputs(%arg3 : memref<1x1x128x512xsi32, @CMX_NN>) outputs(%arg4 : memref<1x1x128x512xsi32, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>) -> memref<1x1x128x512xsi32, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>
    // CHECK:           }
    // CHECK:           [[CONCAT0:%.*]] = VPUIP.ConcatView inputs([[TILING_OUTPUT0]], [[TILING_OUTPUT2]] : memref<1x1x128x512xf16, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>, memref<1x1x128x512xf16, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>) outputs([[ALLOC7]] : memref<1x1x256x512xf16, @DDR>) -> memref<1x1x256x512xf16, @DDR>
    // CHECK:           [[ALLOC9:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x256x512xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[TILING_OUTPUT4:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCAT0]] as %arg3: memref<1x1x256x512xf16, @DDR>) outputs([[ALLOC9]] as %arg4: memref<1x1x256x512xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x1x256x512xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:               VPUIP.Copy inputs(%arg3 : memref<1x1x256x512xf16, @DDR>) outputs(%arg4 : memref<1x1x256x512xf16, @CMX_NN>) -> memref<1x1x256x512xf16, @CMX_NN>
    // CHECK:           }
    // CHECK:           [[CONCAT1:%.*]] = VPUIP.ConcatView inputs([[TILING_OUTPUT1]], [[TILING_OUTPUT3]] : memref<1x1x128x512xsi32, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>, memref<1x1x128x512xsi32, {order = #NCHW, strides = [131072, 131072, 512, 1]}, @DDR>) outputs([[ALLOC8]] : memref<1x1x256x512xsi32, @DDR>) -> memref<1x1x256x512xsi32, @DDR>
    // CHECK:           [[ALLOC10:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x256x512xsi32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[TILING_OUTPUT5:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCAT1]] as %arg3: memref<1x1x256x512xsi32, @DDR>) outputs([[ALLOC10]] as %arg4: memref<1x1x256x512xsi32, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x1x256x512xsi32, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:               VPUIP.Copy inputs(%arg3 : memref<1x1x256x512xsi32, @DDR>) outputs(%arg4 : memref<1x1x256x512xsi32, @CMX_NN>) -> memref<1x1x256x512xsi32, @CMX_NN>
    // CHECK:           }
    // CHECK:           [[ALLOC11:%.*]] = memref.alloc() : memref<1x1x256x512xf16>
    // CHECK:           [[TILING_OUTPUT6:%.*]] = VPUIP.NCEClusterTiling inputs([[TILING_OUTPUT4]] as %arg3: memref<1x1x256x512xf16, @CMX_NN>) outputs([[ALLOC11]] as %arg4: memref<1x1x256x512xf16>) -> memref<1x1x256x512xf16> {
    // CHECK:               VPUIP.Copy inputs(%arg3 : memref<1x1x256x512xf16, @CMX_NN>) outputs(%arg4 : memref<1x1x256x512xf16>) -> memref<1x1x256x512xf16>
    // CHECK:           }
    // CHECK:           [[ALLOC12:%.*]] = memref.alloc() : memref<1x1x256x512xsi32>
    // CHECK:           [[TILING_OUTPUT7:%.*]] = VPUIP.NCEClusterTiling inputs([[TILING_OUTPUT5]] as %arg3: memref<1x1x256x512xsi32, @CMX_NN>) outputs([[ALLOC12]] as %arg4: memref<1x1x256x512xsi32>) -> memref<1x1x256x512xsi32> {
    // CHECK:               VPUIP.Copy inputs(%arg3 : memref<1x1x256x512xsi32, @CMX_NN>) outputs(%arg4 : memref<1x1x256x512xsi32>) -> memref<1x1x256x512xsi32>
    // CHECK:           }
    // CHECK:           [[COPY_OUT0:%.*]] = VPUIP.Copy inputs([[TILING_OUTPUT6]] : memref<1x1x256x512xf16>) outputs(%arg1 : memref<1x1x256x512xf16>) -> memref<1x1x256x512xf16>
    // CHECK:           [[COPY_OUT1:%.*]] = VPUIP.Copy inputs([[TILING_OUTPUT7]] : memref<1x1x256x512xsi32>) outputs(%arg2 : memref<1x1x256x512xsi32>) -> memref<1x1x256x512xsi32>
    // CHECK:           return [[COPY_OUT0]], [[COPY_OUT1]] : memref<1x1x256x512xf16>, memref<1x1x256x512xsi32>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_Sigmoid(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "sigmoid_fp16.cpp", VPU.kernel_entry = "sigmoid_fp16"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterSigmoid(%arg0: memref<1x128x64x32xf16>)
        -> memref<1x128x64x32xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x64x32xf16>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16>) outputs(%arg2 : memref<1x128x64x32xf16, @CMX_NN>) -> memref<1x128x64x32xf16, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg1: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%3 as %arg2: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x64x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Sigmoid inputs(%arg1 as %arg6: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) outputs(%arg2 as %arg7: memref<1x128x64x32xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x128x64x32xf16, #NCHW, @CMX_NN> {
        VPUIP.SW.Kernel.run {attrs = [0.1666259765625, 5.000000e-01]}(%arg6, %arg7) : memref<1x128x64x32xf16, @CMX_NN>, memref<1x128x64x32xf16, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x128x64x32xf16>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x128x64x32xf16, @CMX_NN>) outputs(%5 as %arg2: memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x128x64x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    }
    return %6: memref<1x128x64x32xf16>

    // CHECK:    [[SUBVIEW0:%.*]] = VPUIP.SubView %arg0 [0, 0, 32, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[INPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY2:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW0]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[INPUT_BUF0]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:             VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs(%arg2 : memref<1x128x32x32xf16, @CMX_NN>) -> memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[SUBVIEW1:%.*]] = VPUIP.SubView %arg0 [0, 0, 0, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[INPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPY4:%.*]] = VPUIP.NCEClusterTiling inputs([[SUBVIEW1]] as %arg1: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[INPUT_BUF1]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:             VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs(%arg2 : memref<1x128x32x32xf16, @CMX_NN>) -> memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUF1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[OUTPUT_BUF0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[CLUSTER_SIGMOID:%.*]]:2 = VPUIP.NCEClusterTiling inputs([[COPY4]] as %arg1: memref<1x128x32x32xf16, @CMX_NN>, [[COPY2]] as %arg2: memref<1x128x32x32xf16, @CMX_NN>) outputs([[OUTPUT_BUF0]] as %arg3: memref<1x128x32x32xf16, @CMX_NN>, [[OUTPUT_BUF1]] as %arg4: memref<1x128x32x32xf16, @CMX_NN>) -> (!VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x128x32x32xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:           %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Sigmoid inputs(%arg1 as %arg5: memref<1x128x32x32xf16, @CMX_NN>, %arg2 as %arg6: memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg3 as %arg7: memref<1x128x32x32xf16, @CMX_NN>, %arg4 as %arg8: memref<1x128x32x32xf16, @CMX_NN>) on tile 0 -> (memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>){
    // CHECK:               VPUIP.SW.Kernel.run {attrs = [0.1666259765625, 5.000000e-01]}(%arg5, %arg7) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:               VPUIP.SW.Kernel.run {attrs = [0.1666259765625, 5.000000e-01]}(%arg6, %arg8) : memref<1x128x32x32xf16, @CMX_NN>, memref<1x128x32x32xf16, @CMX_NN>
    // CHECK:           }
    // CHECK:    }
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x128x64x32xf16>
    // CHECK:    [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 0, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY5:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_SIGMOID]]#0 as %arg1: memref<1x128x32x32xf16, @CMX_NN>) outputs([[SUBVIEW2]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:             VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    }
    // CHECK:    [[SUBVIEW3:%.*]]  = VPUIP.SubView [[OUTPUT_DDR]] [0, 0, 32, 0] [1, 128, 32, 32] : memref<1x128x64x32xf16> to memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    [[COPY6:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_SIGMOID]]#1 as %arg1: memref<1x128x32x32xf16, @CMX_NN>) outputs([[SUBVIEW3]] as %arg2: memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}> {
    // CHECK:             VPUIP.Copy inputs(%arg1 : memref<1x128x32x32xf16, @CMX_NN>) outputs(%arg2 : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) -> memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>
    // CHECK:    }
    // CHECK:    [[CONCAT:%.*]] = VPUIP.ConcatView inputs([[COPY5]], [[COPY6]] : memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>, memref<1x128x32x32xf16, {order = #NCHW, strides = [262144, 2048, 32, 1]}>) outputs([[OUTPUT_DDR]] : memref<1x128x64x32xf16>) -> memref<1x128x64x32xf16>
    // CHECK:    return [[CONCAT]] : memref<1x128x64x32xf16>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW {
  func.func private @builtin_DepthToSpace(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "single_shave_depth_to_space.cpp", VPU.kernel_entry = "single_shave_depth_to_space"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterSWDepthToSpace(%arg0: memref<1x128x12x270xf16, #NHWC>)
        -> memref<1x8x48x1080xf16, #NHWC> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x12x270xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x12x270xf16, #NHWC>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x12x270xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x12x270xf16, #NHWC>) outputs(%arg2 : memref<1x128x64x32xf16, #NHWC, @CMX_NN>) -> memref<1x128x64x32xf16, #NHWC, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x8x48x1080xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg2: memref<1x128x12x270xf16, #NHWC, @CMX_NN>) outputs(%3 as %arg3: memref<1x8x48x1080xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x8x48x1080xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_DepthToSpace inputs(%arg2 as %arg4: memref<1x128x12x270xf16, #NHWC, @CMX_NN>) outputs(%arg3 as %arg5: memref<1x8x48x1080xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x8x48x1080xf16, #NHWC, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [4, 1]}(%arg4, %arg5) : memref<1x128x12x270xf16, #NHWC, @CMX_NN>, memref<1x8x48x1080xf16, #NHWC, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x8x48x1080xf16, #NHWC>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x8x48x1080xf16, #NHWC, @CMX_NN>) outputs(%5 as %arg2: memref<1x8x48x1080xf16, #NHWC>) -> memref<1x8x48x1080xf16, #NHWC> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x8x48x1080xf16, #NHWC, @CMX_NN>) outputs(%arg2 : memref<1x8x48x1080xf16, #NHWC>) -> memref<1x8x48x1080xf16, #NHWC>
    }
    return %6: memref<1x8x48x1080xf16, #NHWC>

    // CHECK:                [[INPUT_BUF:%.*]] = VPURT.AllocDistributed ->
    // CHECK-SAME{LITERAL}:      !VPUIP.DistributedBuffer<1x128x12x270xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:                [[CLUSTER_COPY_INPUT:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x12x270xf16, #NHWC>) outputs([[INPUT_BUF]] as %arg2: memref<1x128x64x32xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x12x270xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                    VPUIP.Copy inputs(%arg1 : memref<1x128x12x270xf16, #NHWC>) outputs(%arg2 : memref<1x128x64x32xf16, #NHWC, @CMX_NN>) -> memref<1x128x64x32xf16, #NHWC, @CMX_NN>
    // CHECK:                }
    // CHECK:                [[SUBVIEW0:%.*]] = VPUIP.SubView [[CLUSTER_COPY_INPUT]] [0, 0, 6, 0] [1, 128, 6, 270] : !VPUIP.DistributedBuffer<1x128x12x270xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x128x6x270xf16, {order = #NHWC, strides = [414720, 1, 34560, 128]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:                [[SUBVIEW1:%.*]] = VPUIP.SubView [[CLUSTER_COPY_INPUT]] [0, 0, 0, 0] [1, 128, 6, 270] : !VPUIP.DistributedBuffer<1x128x12x270xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x128x6x270xf16, {order = #NHWC, strides = [414720, 1, 34560, 128]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:                [[OUTPUT_BUF:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x8x48x1080xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}>
    // CHECK:                [[SUBVIEW2:%.*]] = VPUIP.SubView [[OUTPUT_BUF]] [0, 0, 24, 0] [1, 8, 24, 1080] : !VPUIP.DistributedBuffer<1x8x48x1080xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}> to !VPUIP.DistributedBuffer<1x8x24x1080xf16, {order = #NHWC, strides = [414720, 1, 8640, 8]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}>
    // CHECK:                [[SUBVIEW3:%.*]] = VPUIP.SubView [[OUTPUT_BUF]] [0, 0, 0, 0] [1, 8, 24, 1080] : !VPUIP.DistributedBuffer<1x8x48x1080xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}> to !VPUIP.DistributedBuffer<1x8x24x1080xf16, {order = #NHWC, strides = [414720, 1, 8640, 8]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}>

    // CHECK:                [[CLUSTER_D2S:%.*]]:2 = VPUIP.NCEClusterTiling
    // CHECK-SAME:               inputs([[SUBVIEW1]] as %arg1: memref<1x128x6x270xf16, {order = #NHWC, strides = [414720, 1, 34560, 128]}, @CMX_NN>,
    // CHECK-SAME:                      [[SUBVIEW0]] as %arg2: memref<1x128x6x270xf16, {order = #NHWC, strides = [414720, 1, 34560, 128]}, @CMX_NN>)
    // CHECK-SAME:               outputs([[SUBVIEW3]] as %arg3: memref<1x8x24x1080xf16, {order = #NHWC, strides = [414720, 1, 8640, 8]}, @CMX_NN>,
    // CHECK-SAME:                       [[SUBVIEW2]] as %arg4: memref<1x8x24x1080xf16, {order = #NHWC, strides = [414720, 1, 8640, 8]}, @CMX_NN>)
    // CHECK-SAME:               -> (!VPUIP.DistributedBuffer<1x8x24x1080xf16, {order = #NHWC, strides = [414720, 1, 8640, 8]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}>,
    // CHECK-SAME:                   !VPUIP.DistributedBuffer<1x8x24x1080xf16, {order = #NHWC, strides = [414720, 1, 8640, 8]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}>) {
    // CHECK:                    %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_DepthToSpace
    // CHECK-SAME:                   inputs(%arg1 as %arg5: memref<1x128x6x270xf16, {order = #NHWC, strides = [414720, 1, 34560, 128]}, @CMX_NN>,
    // CHECK-SAME:                          %arg2 as %arg6: memref<1x128x6x270xf16, {order = #NHWC, strides = [414720, 1, 34560, 128]}, @CMX_NN>)
    // CHECK-SAME:                   outputs(%arg3 as %arg7: memref<1x8x24x1080xf16, {order = #NHWC, strides = [414720, 1, 8640, 8]}, @CMX_NN>,
    // CHECK-SAME{LITERAL}:                  %arg4 as %arg8: memref<1x8x24x1080xf16, {order = #NHWC, strides = [414720, 1, 8640, 8]}, @CMX_NN>) strides([[207360, 1, 8640, 8], [207360, 1, 8640, 8]]) on tile 0
    // CHECK-SAME:                   -> (memref<1x8x24x1080xf16, {order = #NHWC, strides = [414720, 1, 8640, 8]}, @CMX_NN>,
    // CHECK-SAME:                       memref<1x8x24x1080xf16, {order = #NHWC, strides = [414720, 1, 8640, 8]}, @CMX_NN>){
    // CHECK:                        VPUIP.SW.Kernel.run {attrs = [4, 1]}(%arg5, %arg7) : memref<1x128x6x270xf16, {order = #NHWC, strides = [414720, 1, 34560, 128]}, @CMX_NN>, memref<1x8x24x1080xf16, {order = #NHWC, strides = [414720, 1, 8640, 8]}, @CMX_NN>
    // CHECK:                        VPUIP.SW.Kernel.run {attrs = [4, 1]}(%arg6, %arg8) : memref<1x128x6x270xf16, {order = #NHWC, strides = [414720, 1, 34560, 128]}, @CMX_NN>, memref<1x8x24x1080xf16, {order = #NHWC, strides = [414720, 1, 8640, 8]}, @CMX_NN>
    // CHECK:                    }
    // CHECK:                }

    // CHECK:                [[CONCAT:%.*]] = VPUIP.ConcatView
    // CHECK-SAME:               inputs([[CLUSTER_D2S]]#0, [[CLUSTER_D2S]]#1 :
    // CHECK-SAME:                   !VPUIP.DistributedBuffer<1x8x24x1080xf16, {order = #NHWC, strides = [414720, 1, 8640, 8]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}>,
    // CHECK-SAME:                   !VPUIP.DistributedBuffer<1x8x24x1080xf16, {order = #NHWC, strides = [414720, 1, 8640, 8]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}>)
    // CHECK-SAME:               outputs([[OUTPUT_BUF]] : !VPUIP.DistributedBuffer<1x8x48x1080xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}>)
    // CHECK-SAME:                   -> !VPUIP.DistributedBuffer<1x8x48x1080xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}>
    // CHECK:                [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x8x48x1080xf16, #NHWC>
    // CHECK:                [[CLUSTER_COPY_OUTPUT:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCAT]] as %arg1: memref<1x8x48x1080xf16, #NHWC, @CMX_NN>) outputs([[OUTPUT_DDR]] as %arg2: memref<1x8x48x1080xf16, #NHWC>) -> memref<1x8x48x1080xf16, #NHWC> {
    // CHECK:                    VPUIP.Copy inputs(%arg1 : memref<1x8x48x1080xf16, #NHWC, @CMX_NN>) outputs(%arg2 : memref<1x8x48x1080xf16, #NHWC>) -> memref<1x8x48x1080xf16, #NHWC>
    // CHECK:                return [[CLUSTER_COPY_OUTPUT]] : memref<1x8x48x1080xf16, #NHWC>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW {
  func.func private @builtin_DepthToSpace(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "single_shave_depth_to_space.cpp", VPU.kernel_entry = "single_shave_depth_to_space"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @NotTileClusterDMADepthToSpace(%arg0: memref<1x128x12x270xf16, #NHWC>)
        -> memref<1x8x48x1080xf16, #NHWC> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x12x270xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x12x270xf16, #NHWC>) outputs(%0 as %arg2: memref<1x128x64x32xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x12x270xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x128x12x270xf16, #NHWC>) outputs(%arg2 : memref<1x128x64x32xf16, #NHWC, @CMX_NN>) -> memref<1x128x64x32xf16, #NHWC, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x8x48x1080xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg2: memref<1x128x12x270xf16, #NHWC, @CMX_NN>) outputs(%3 as %arg3: memref<1x8x48x1080xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x8x48x1080xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_DepthToSpace inputs(%arg2 as %arg4: memref<1x128x12x270xf16, #NHWC, @CMX_NN>) outputs(%arg3 as %arg5: memref<1x8x48x1080xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x8x48x1080xf16, #NHWC, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [4, 0]}(%arg4, %arg5) : memref<1x128x12x270xf16, #NHWC, @CMX_NN>, memref<1x8x48x1080xf16, #NHWC, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x8x48x1080xf16, #NHWC>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg1: memref<1x8x48x1080xf16, #NHWC, @CMX_NN>) outputs(%5 as %arg2: memref<1x8x48x1080xf16, #NHWC>) -> memref<1x8x48x1080xf16, #NHWC> {
      %7 = VPUIP.Copy inputs(%arg1 : memref<1x8x48x1080xf16, #NHWC, @CMX_NN>) outputs(%arg2 : memref<1x8x48x1080xf16, #NHWC>) -> memref<1x8x48x1080xf16, #NHWC>
    }
    return %6: memref<1x8x48x1080xf16, #NHWC>

    // CHECK:    [[INPUT_BUF:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x128x12x270xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[COPYIN:%.*]] = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x128x12x270xf16, #NHWC>) outputs([[INPUT_BUF]] as %arg2: memref<1x128x64x32xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x128x12x270xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:             VPUIP.Copy inputs(%arg1 : memref<1x128x12x270xf16, #NHWC>) outputs(%arg2 : memref<1x128x64x32xf16, #NHWC, @CMX_NN>) -> memref<1x128x64x32xf16, #NHWC, @CMX_NN>
    // CHECK:    }
    // CHECK:    [[OUTPUT_BUF:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x8x48x1080xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}>
    // CHECK:    [[CLUSTER_D2S:%.*]] = VPUIP.NCEClusterTiling inputs([[COPYIN]] as %arg1: memref<1x128x12x270xf16, #NHWC, @CMX_NN>) outputs([[OUTPUT_BUF]] as %arg2: memref<1x8x48x1080xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x8x48x1080xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64, alignment = [1, 1, 4, 1]}> {
    // CHECK:           %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_DepthToSpace inputs(%arg1 as %arg3: memref<1x128x12x270xf16, #NHWC, @CMX_NN>) outputs(%arg2 as %arg4: memref<1x8x48x1080xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x8x48x1080xf16, #NHWC, @CMX_NN>{
    // CHECK:               VPUIP.SW.Kernel.run {attrs = [4, 0]}(%arg3, %arg4) : memref<1x128x12x270xf16, #NHWC, @CMX_NN>, memref<1x8x48x1080xf16, #NHWC, @CMX_NN>
    // CHECK:           }
    // CHECK:    }
    // CHECK:    [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x8x48x1080xf16, #NHWC>
    // CHECK:    [[COPYOUT:%.*]] = VPUIP.NCEClusterTiling inputs([[CLUSTER_D2S]] as %arg1: memref<1x8x48x1080xf16, #NHWC, @CMX_NN>) outputs([[OUTPUT_DDR]] as %arg2: memref<1x8x48x1080xf16, #NHWC>) -> memref<1x8x48x1080xf16, #NHWC> {
    // CHECK:             VPUIP.Copy inputs(%arg1 : memref<1x8x48x1080xf16, #NHWC, @CMX_NN>) outputs(%arg2 : memref<1x8x48x1080xf16, #NHWC>) -> memref<1x8x48x1080xf16, #NHWC>
    // CHECK:    }
    // CHECK:    return [[COPYOUT]] : memref<1x8x48x1080xf16, #NHWC>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW {
  func.func private @builtin_Clamp(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "clamp_fp16.cpp", VPU.kernel_entry = "clamp_fp16"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterClamp(%arg0: memref<1x5x34x60xf16, #NHWC>)
        -> memref<1x5x34x60xf16, #NHWC> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x5x34x60xf16, #NHWC>) outputs(%0 as %arg2: memref<1x5x34x60xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x5x34x60xf16, #NHWC>) outputs(%arg2 : memref<1x5x34x60xf16, #NHWC, @CMX_NN>) -> memref<1x5x34x60xf16, #NHWC, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg3: memref<1x5x34x60xf16, #NHWC, @CMX_NN>) outputs(%3 as %arg4: memref<1x5x34x60xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Clamp inputs(%arg3 as %arg5: memref<1x5x34x60xf16, #NHWC, @CMX_NN>) outputs(%arg4 as %arg6: memref<1x5x34x60xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x5x34x60xf16, #NHWC, @CMX_NN>{
        VPUIP.SW.Kernel.run {attrs = [-1.000000e+00, 1.000000e+00]}(%arg5, %arg6) : memref<1x5x34x60xf16, #NHWC, @CMX_NN>, memref<1x5x34x60xf16, #NHWC, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x5x34x60xf16, #NHWC>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg7: memref<1x5x34x60xf16, #NHWC, @CMX_NN>) outputs(%5 as %arg8: memref<1x5x34x60xf16, #NHWC>) -> memref<1x5x34x60xf16, #NHWC> {
      %7 = VPUIP.Copy inputs(%arg7 : memref<1x5x34x60xf16, #NHWC, @CMX_NN>) outputs(%arg8 : memref<1x5x34x60xf16, #NHWC>) -> memref<1x5x34x60xf16, #NHWC>
    }
    return %6: memref<1x5x34x60xf16, #NHWC>

    // CHECK:           [[INPUT_BUF:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[INPUT_COPY:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:                inputs(%arg0 as %arg1: memref<1x5x34x60xf16, #NHWC>)
    // CHECK-SAME:                outputs([[INPUT_BUF]] as %arg2: memref<1x5x34x60xf16, #NHWC, @CMX_NN>)
    // CHECK-SAME:                -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                     VPUIP.Copy inputs(%arg1 : memref<1x5x34x60xf16, #NHWC>) outputs(%arg2 : memref<1x5x34x60xf16, #NHWC, @CMX_NN>) -> memref<1x5x34x60xf16, #NHWC, @CMX_NN>
    // CHECK:               }
    // CHECK:           [[INPUT_SUBVIEW0:%.*]] = VPUIP.SubView [[INPUT_COPY]] [0, 0, 18, 0] [1, 5, 16, 60] : !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[INPUT_SUBVIEW1:%.*]] = VPUIP.SubView [[INPUT_COPY]] [0, 0, 0, 0] [1, 5, 18, 60] : !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:           [[OUTPUT_BUF:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[OUTPUT_BUF_SUBVIEW0:%.*]] = VPUIP.SubView [[OUTPUT_BUF]] [0, 0, 18, 0] [1, 5, 16, 60] : !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[OUTPUT_BUF_SUBVIEW1:%.*]] = VPUIP.SubView [[OUTPUT_BUF]] [0, 0, 0, 0] [1, 5, 18, 60] : !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:           [[CLUSTER_CLAMP:%.*]]:2 =  VPUIP.NCEClusterTiling
    // CHECK-SAME:                inputs([[INPUT_SUBVIEW1]] as %arg1: memref<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>,
    // CHECK-SAME:                       [[INPUT_SUBVIEW0]] as %arg2: memref<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>)
    // CHECK-SAME:                outputs([[OUTPUT_BUF_SUBVIEW1]] as %arg3: memref<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>,
    // CHECK-SAME:                        [[OUTPUT_BUF_SUBVIEW0]] as %arg4: memref<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>)
    // CHECK-SAME:                -> (!VPUIP.DistributedBuffer<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK-SAME:                    !VPUIP.DistributedBuffer<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                     VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Clamp
    // CHECK-SAME:                      inputs(%arg1 as %arg5: memref<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>,
    // CHECK-SAME:                             %arg2 as %arg6: memref<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>)
    // CHECK-SAME:                      outputs(%arg3 as %arg7: memref<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>,
    // CHECK-SAME{LITERAL}:                     %arg4 as %arg8: memref<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>) strides([[5100, 1, 300, 5], [5100, 1, 300, 5]]) on tile 0
    // CHECK-SAME:                      -> (memref<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>, memref<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>){
    // CHECK:                           VPUIP.SW.Kernel.run {attrs = [-1.000000e+00, 1.000000e+00]}(%arg5, %arg7) : memref<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>, memref<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>
    // CHECK:                           VPUIP.SW.Kernel.run {attrs = [-1.000000e+00, 1.000000e+00]}(%arg6, %arg8) : memref<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>, memref<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>
    // CHECK:                     }
    // CHECK:               }

    // CHECK:           [[CONCAT_VIEW:%.*]] = VPUIP.ConcatView
    // CHECK-SAME:                inputs([[CLUSTER_CLAMP]]#0, [[CLUSTER_CLAMP]]#1 :
    // CHECK-SAME:                    !VPUIP.DistributedBuffer<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK-SAME:                    !VPUIP.DistributedBuffer<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK-SAME:                outputs([[OUTPUT_BUF]] : !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK-SAME:                -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x5x34x60xf16, #NHWC>
    // CHECK:           [[OUTPUT_COPY:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:                inputs([[CONCAT_VIEW]] as %arg1: memref<1x5x34x60xf16, #NHWC, @CMX_NN>)
    // CHECK-SAME:                outputs([[OUTPUT_DDR]] as %arg2: memref<1x5x34x60xf16, #NHWC>) -> memref<1x5x34x60xf16, #NHWC> {
    // CHECK:                         VPUIP.Copy inputs(%arg1 : memref<1x5x34x60xf16, #NHWC, @CMX_NN>) outputs(%arg2 : memref<1x5x34x60xf16, #NHWC>) -> memref<1x5x34x60xf16, #NHWC>
    // CHECK:              }
    // CHECK:           return [[OUTPUT_COPY]] : memref<1x5x34x60xf16, #NHWC>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

module @VPU.SW {
  func.func private @builtin_Divide(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>) attributes {VPU.kernel_code = "eltwise_div.cpp", VPU.kernel_entry = "eltwise_div"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterDivide() -> memref<1x64x1x88xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x1x88xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    %1 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x1x88xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x1x88xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>

    %3 = VPUIP.NCEClusterTiling inputs(%0 as %arg0: memref<1x64x1x88xf16, #NCHW, @CMX_NN>,
                                          %1 as %arg1: memref<1x64x1x88xf16, #NCHW, @CMX_NN>)
                                  outputs(%2 as %arg2: memref<1x64x1x88xf16, #NCHW, @CMX_NN>)
                                      -> !VPUIP.DistributedBuffer<1x64x1x88xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Divide
                    inputs(%arg0 as %arg3: memref<1x64x1x88xf16, #NCHW, @CMX_NN>,
                           %arg1 as %arg4: memref<1x64x1x88xf16, #NCHW, @CMX_NN>)
                    outputs(%arg2 as %arg5: memref<1x64x1x88xf16, #NCHW, @CMX_NN>) on tile 0 -> memref<1x64x1x88xf16, #NCHW, @CMX_NN>{
        VPUIP.SW.Kernel.run(%arg3, %arg4, %arg5) : memref<1x64x1x88xf16, #NCHW, @CMX_NN>, memref<1x64x1x88xf16, #NCHW, @CMX_NN>, memref<1x64x1x88xf16, #NCHW, @CMX_NN>
      }
    }

    %4 = memref.alloc() : memref<1x64x1x88xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg1: memref<1x64x1x88xf16, @CMX_NN>) outputs(%4 as %arg2: memref<1x64x1x88xf16>) -> memref<1x64x1x88xf16> {
      %results = VPUIP.Copy inputs(%arg1 : memref<1x64x1x88xf16, @CMX_NN>) outputs(%arg2 : memref<1x64x1x88xf16>) -> memref<1x64x1x88xf16>
    }

    return %5: memref<1x64x1x88xf16>

    // For Divide First Input
    // CHECK:    [[INPUT0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x1x88xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT0_TILE0:%.*]] = VPUIP.SubView [[INPUT0]] [0, 32, 0, 0] [1, 32, 1, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x1x88xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT0_TILE1:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 0, 0] [1, 32, 1, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x1x88xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>

    // For Divide Second Input
    // CHECK:    [[INPUT1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x1x88xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT1_TILE0:%.*]] = VPUIP.SubView [[INPUT1]] [0, 32, 0, 0] [1, 32, 1, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x1x88xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT1_TILE1:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 0, 0] [1, 32, 1, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x1x88xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>

    // CHECK:    [[DIVIDE_OUT:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x1x88xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
    // CHECK:    [[DIVIDE_OUT_TILE0:%.*]] = VPUIP.SubView [[DIVIDE_OUT]] [0, 32, 0, 0] [1, 32, 1, 88]
    // CHECK:    [[DIVIDE_OUT_TILE1:%.*]] = VPUIP.SubView [[DIVIDE_OUT]] [0, 0, 0, 0] [1, 32, 1, 88]
    // CHECK:    [[DIVIDE:%.*]]:2 = VPUIP.NCEClusterTiling
    // CHECK:                     inputs([[INPUT0_TILE1]] as %arg0: memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE1]] as %arg1: memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>
    // CHECK:                            [[INPUT0_TILE0]] as %arg2: memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE0]] as %arg3: memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>
    // CHECK:                     outputs([[DIVIDE_OUT_TILE1]] as %arg4: memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>
    // CHECK:                            [[DIVIDE_OUT_TILE0]] as %arg5: memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>
    // CHECK:                     -> (!VPUIP.DistributedBuffer<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>)
    // CHECK:    %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Divide
    // CHECK:                     inputs(%arg0 as %arg6: memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>
    // CHECK:                            %arg1 as %arg7: memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>
    // CHECK:                            %arg2 as %arg8: memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>
    // CHECK:                            %arg3 as %arg9: memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>
    // CHECK:                     outputs(%arg4 as %arg10: memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>
    // CHECK:                             %arg5 as %arg11: memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg7, %arg10) : memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>, memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>, memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}(%arg8, %arg9, %arg11) : memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>, memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>, memref<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN>

    // CHECK:    [[CONCATVIEW:%.*]] = VPUIP.ConcatView inputs([[DIVIDE]]#0, [[DIVIDE]]#1
    // CHECK:                     !VPUIP.DistributedBuffer<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>,
    // CHECK:                     !VPUIP.DistributedBuffer<1x32x1x88xf16, {order = #NCHW, strides = [5632, 88, 88, 1]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>)
    // CHECK:                     outputs([[DIVIDE_OUT]] : !VPUIP.DistributedBuffer<1x64x1x88xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x64x1x88xf16, #NCHW, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>

    // CHECK:    [[OUTPUT_BUF:%.*]] = memref.alloc() : memref<1x64x1x88xf16>
    // CHECK:    [[OUTPUT_COPY:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCATVIEW]] as %arg0: memref<1x64x1x88xf16, @CMX_NN>)
    // CHECK:                                                 outputs([[OUTPUT_BUF]] as %arg1: memref<1x64x1x88xf16>) -> memref<1x64x1x88xf16>

    // CHECK:    return [[OUTPUT_COPY]] : memref<1x64x1x88xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW {
  func.func private @builtin_Power(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>) attributes {VPU.kernel_code = "eltwise_power.cpp", VPU.kernel_entry = "eltwise_power"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterPower() -> memref<1x64x88x88xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    %3 = VPUIP.NCEClusterTiling inputs(%0 as %arg0: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                                          %1 as %arg1: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                                  outputs(%2 as %arg2: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                                      -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Power
                    inputs(%arg0 as %arg3: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                           %arg1 as %arg4: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                    outputs(%arg2 as %arg5: memref<1x64x88x88xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x64x88x88xf16, #NHWC, @CMX_NN>{
        VPUIP.SW.Kernel.run(%arg3, %arg4, %arg5) : memref<1x64x88x88xf16, #NHWC, @CMX_NN>, memref<1x64x88x88xf16, #NHWC, @CMX_NN>, memref<1x64x88x88xf16, #NHWC, @CMX_NN>
      }
    }

    %4 = memref.alloc() : memref<1x64x88x88xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg1: memref<1x64x88x88xf16, @CMX_NN>) outputs(%4 as %arg2: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16> {
      %results = VPUIP.Copy inputs(%arg1 : memref<1x64x88x88xf16, @CMX_NN>) outputs(%arg2 : memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>
    }

    return %5: memref<1x64x88x88xf16>

    // For Power First Input
    // CHECK:    [[INPUT0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT0_TILE0:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT0_TILE1:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // For Power Second Input
    // CHECK:    [[INPUT1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT1_TILE0:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT1_TILE1:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[POWER_OUT:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[POWER_OUT_TILE0:%.*]] = VPUIP.SubView [[POWER_OUT]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:    [[POWER_OUT_TILE1:%.*]] = VPUIP.SubView [[POWER_OUT]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:    [[POWER:%.*]]:2 = VPUIP.NCEClusterTiling
    // CHECK:                     inputs([[INPUT0_TILE1]] as %arg0: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE1]] as %arg1: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT0_TILE0]] as %arg2: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE0]] as %arg3: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     outputs([[POWER_OUT_TILE1]] as %arg4: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[POWER_OUT_TILE0]] as %arg5: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     -> (!VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK:    %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Power
    // CHECK:                     inputs(%arg0 as %arg6: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg1 as %arg7: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg2 as %arg8: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg3 as %arg9: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     outputs(%arg4 as %arg10: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                             %arg5 as %arg11: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg7, %arg10) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}(%arg8, %arg9, %arg11) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>

    // CHECK:    [[CONCATVIEW:%.*]] = VPUIP.ConcatView inputs([[POWER]]#0, [[POWER]]#1
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK:                     outputs([[POWER_OUT]] : !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[OUTPUT_BUF:%.*]] = memref.alloc() : memref<1x64x88x88xf16>
    // CHECK:    [[OUTPUT_COPY:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCATVIEW]] as %arg0: memref<1x64x88x88xf16, @CMX_NN>)
    // CHECK:                                                 outputs([[OUTPUT_BUF]] as %arg1: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>

    // CHECK:    return [[OUTPUT_COPY]] : memref<1x64x88x88xf16>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW {
  func.func private @builtin_Power(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>) attributes {VPU.kernel_code = "eltwise_power.cpp", VPU.kernel_entry = "eltwise_power"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterPowerAtBroadcastAxis() -> memref<1x64x88x88xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x1x1x88xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    %3 = VPUIP.NCEClusterTiling inputs(%0 as %arg0: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                                       %1 as %arg1: memref<1x1x1x88xf16, #NHWC, @CMX_NN>)
                                outputs(%2 as %arg2: memref<1x64x88x88xf16, #NHWC, @CMX_NN>)
                                      -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Power
                    inputs(%arg0 as %arg3: memref<1x64x88x88xf16, #NHWC, @CMX_NN>,
                           %arg1 as %arg4: memref<1x1x1x88xf16, #NHWC, @CMX_NN>)
                    outputs(%arg2 as %arg5: memref<1x64x88x88xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x64x88x88xf16, #NHWC, @CMX_NN>{
        VPUIP.SW.Kernel.run(%arg3, %arg4, %arg5) : memref<1x64x88x88xf16, #NHWC, @CMX_NN>, memref<1x1x1x88xf16, #NHWC, @CMX_NN>, memref<1x64x88x88xf16, #NHWC, @CMX_NN>
      }
    }

    %4 = memref.alloc() : memref<1x64x88x88xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg1: memref<1x64x88x88xf16, @CMX_NN>) outputs(%4 as %arg2: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16> {
      %results = VPUIP.Copy inputs(%arg1 : memref<1x64x88x88xf16, @CMX_NN>) outputs(%arg2 : memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>
    }

    return %5: memref<1x64x88x88xf16>

    // For Power First Input
    // CHECK:    [[INPUT0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT0_TILE0:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT0_TILE1:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // For Power Second Input
    // CHECK:    [[INPUT1_TILE0:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 0, 0] [1, 1, 1, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x1x1x88xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x1x1x88xf16, {order = #NHWC, strides = [88, 1, 88, 1]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>

    // CHECK:    [[INPUT1_TILE1:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 0, 0] [1, 1, 1, 88]
    // CHECK:         !VPUIP.DistributedBuffer<1x1x1x88xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x1x1x88xf16, {order = #NHWC, strides = [88, 1, 88, 1]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>

    // CHECK:    [[POWER_OUT:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[POWER_OUT_TILE0:%.*]] = VPUIP.SubView [[POWER_OUT]] [0, 0, 44, 0] [1, 64, 44, 88]
    // CHECK:    [[POWER_OUT_TILE1:%.*]] = VPUIP.SubView [[POWER_OUT]] [0, 0, 0, 0] [1, 64, 44, 88]
    // CHECK:    [[POWER:%.*]]:2 = VPUIP.NCEClusterTiling
    // CHECK:                     inputs([[INPUT0_TILE1]] as %arg0: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE1]] as %arg1: memref<1x1x1x88xf16, #NHWC, @CMX_NN>
    // CHECK:                            [[INPUT0_TILE0]] as %arg2: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE0]] as %arg3: memref<1x1x1x88xf16, #NHWC, @CMX_NN>
    // CHECK:                     outputs([[POWER_OUT_TILE1]] as %arg4: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            [[POWER_OUT_TILE0]] as %arg5: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                     -> (!VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:    %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Power
    // CHECK:                     inputs(%arg0 as %arg6: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg1 as %arg7: memref<1x1x1x88xf16, #NHWC, @CMX_NN>
    // CHECK:                            %arg2 as %arg8: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                            %arg3 as %arg9: memref<1x1x1x88xf16, #NHWC, @CMX_NN>
    // CHECK:                     outputs(%arg4 as %arg10: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:                             %arg5 as %arg11: memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg7, %arg10) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x1x1x88xf16, #NHWC, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}(%arg8, %arg9, %arg11) : memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>, memref<1x1x1x88xf16, #NHWC, @CMX_NN>, memref<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN>

    // CHECK:    [[CONCATVIEW:%.*]] = VPUIP.ConcatView inputs([[POWER]]#0, [[POWER]]#1
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK:                     !VPUIP.DistributedBuffer<1x64x44x88xf16, {order = #NHWC, strides = [495616, 1, 5632, 64]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK:                     outputs([[POWER_OUT]] : !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x64x88x88xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[OUTPUT_BUF:%.*]] = memref.alloc() : memref<1x64x88x88xf16>
    // CHECK:    [[OUTPUT_COPY:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCATVIEW]] as %arg0: memref<1x64x88x88xf16, @CMX_NN>)
    // CHECK:                                                 outputs([[OUTPUT_BUF]] as %arg1: memref<1x64x88x88xf16>) -> memref<1x64x88x88xf16>

    // CHECK:    return [[OUTPUT_COPY]] : memref<1x64x88x88xf16>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW {
  func.func private @builtin_Abs(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>, i1, i1, f64) attributes {VPU.kernel_code = "activation_abs.cpp", VPU.kernel_entry = "activation_abs"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterAbs(%arg0: memref<1x5x34x60xf16, #NHWC>)
        -> memref<1x5x34x60xf16, #NHWC> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPUIP.NCEClusterTiling inputs(%arg0 as %arg1: memref<1x5x34x60xf16, #NHWC>) outputs(%0 as %arg2: memref<1x5x34x60xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %2 = VPUIP.Copy inputs(%arg1 : memref<1x5x34x60xf16, #NHWC>) outputs(%arg2 : memref<1x5x34x60xf16, #NHWC, @CMX_NN>) -> memref<1x5x34x60xf16, #NHWC, @CMX_NN>
    }
    %3 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %4 = VPUIP.NCEClusterTiling inputs(%1 as %arg3: memref<1x5x34x60xf16, #NHWC, @CMX_NN>) outputs(%3 as %arg4: memref<1x5x34x60xf16, #NHWC, @CMX_NN>) -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_Abs inputs(%arg3 as %arg5: memref<1x5x34x60xf16, #NHWC, @CMX_NN>) outputs(%arg4 as %arg6: memref<1x5x34x60xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x5x34x60xf16, #NHWC, @CMX_NN>{
        VPUIP.SW.Kernel.run (%arg5, %arg6) : memref<1x5x34x60xf16, #NHWC, @CMX_NN>, memref<1x5x34x60xf16, #NHWC, @CMX_NN>
      }
    }
    %5 = memref.alloc() : memref<1x5x34x60xf16, #NHWC>
    %6 = VPUIP.NCEClusterTiling inputs(%4 as %arg7: memref<1x5x34x60xf16, #NHWC, @CMX_NN>) outputs(%5 as %arg8: memref<1x5x34x60xf16, #NHWC>) -> memref<1x5x34x60xf16, #NHWC> {
      %7 = VPUIP.Copy inputs(%arg7 : memref<1x5x34x60xf16, #NHWC, @CMX_NN>) outputs(%arg8 : memref<1x5x34x60xf16, #NHWC>) -> memref<1x5x34x60xf16, #NHWC>
    }
    return %6: memref<1x5x34x60xf16, #NHWC>

    // CHECK:           [[INPUT_BUF:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[INPUT_COPY:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:                inputs(%arg0 as %arg1: memref<1x5x34x60xf16, #NHWC>)
    // CHECK-SAME:                outputs([[INPUT_BUF]] as %arg2: memref<1x5x34x60xf16, #NHWC, @CMX_NN>)
    // CHECK-SAME:                -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                     VPUIP.Copy inputs(%arg1 : memref<1x5x34x60xf16, #NHWC>) outputs(%arg2 : memref<1x5x34x60xf16, #NHWC, @CMX_NN>) -> memref<1x5x34x60xf16, #NHWC, @CMX_NN>
    // CHECK:               }
    // CHECK:           [[INPUT_SUBVIEW0:%.*]] = VPUIP.SubView [[INPUT_COPY]] [0, 0, 18, 0] [1, 5, 16, 60] : !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[INPUT_SUBVIEW1:%.*]] = VPUIP.SubView [[INPUT_COPY]] [0, 0, 0, 0] [1, 5, 18, 60] : !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:           [[OUTPUT_BUF:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[OUTPUT_BUF_SUBVIEW0:%.*]] = VPUIP.SubView [[OUTPUT_BUF]] [0, 0, 18, 0] [1, 5, 16, 60] : !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[OUTPUT_BUF_SUBVIEW1:%.*]] = VPUIP.SubView [[OUTPUT_BUF]] [0, 0, 0, 0] [1, 5, 18, 60] : !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> to !VPUIP.DistributedBuffer<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:           [[CLUSTER_ABS:%.*]]:2 =  VPUIP.NCEClusterTiling
    // CHECK-SAME:                inputs([[INPUT_SUBVIEW1]] as %arg1: memref<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>,
    // CHECK-SAME:                       [[INPUT_SUBVIEW0]] as %arg2: memref<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>)
    // CHECK-SAME:                outputs([[OUTPUT_BUF_SUBVIEW1]] as %arg3: memref<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>,
    // CHECK-SAME:                        [[OUTPUT_BUF_SUBVIEW0]] as %arg4: memref<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>)
    // CHECK-SAME:                -> (!VPUIP.DistributedBuffer<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK-SAME:                    !VPUIP.DistributedBuffer<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) {
    // CHECK:                     VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_Abs
    // CHECK-SAME:                      inputs(%arg1 as %arg5: memref<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>,
    // CHECK-SAME:                             %arg2 as %arg6: memref<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>)
    // CHECK-SAME:                      outputs(%arg3 as %arg7: memref<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>,
    // CHECK-SAME{LITERAL}:                     %arg4 as %arg8: memref<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>) strides([[5100, 1, 300, 5], [5100, 1, 300, 5]]) on tile 0
    // CHECK-SAME:                      -> (memref<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>, memref<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>){
    // CHECK:                           VPUIP.SW.Kernel.run {attrs = []}(%arg5, %arg7) : memref<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>, memref<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>
    // CHECK:                           VPUIP.SW.Kernel.run {attrs = []}(%arg6, %arg8) : memref<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>, memref<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN>
    // CHECK:                     }
    // CHECK:               }

    // CHECK:           [[CONCAT_VIEW:%.*]] = VPUIP.ConcatView
    // CHECK-SAME:                inputs([[CLUSTER_ABS]]#0, [[CLUSTER_ABS]]#1 :
    // CHECK-SAME:                    !VPUIP.DistributedBuffer<1x5x18x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>,
    // CHECK-SAME:                    !VPUIP.DistributedBuffer<1x5x16x60xf16, {order = #NHWC, strides = [10200, 1, 300, 5]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK-SAME:                outputs([[OUTPUT_BUF]] : !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK-SAME:                -> !VPUIP.DistributedBuffer<1x5x34x60xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:           [[OUTPUT_DDR:%.*]] = memref.alloc() : memref<1x5x34x60xf16, #NHWC>
    // CHECK:           [[OUTPUT_COPY:%.*]] = VPUIP.NCEClusterTiling
    // CHECK-SAME:                inputs([[CONCAT_VIEW]] as %arg1: memref<1x5x34x60xf16, #NHWC, @CMX_NN>)
    // CHECK-SAME:                outputs([[OUTPUT_DDR]] as %arg2: memref<1x5x34x60xf16, #NHWC>) -> memref<1x5x34x60xf16, #NHWC> {
    // CHECK:                         VPUIP.Copy inputs(%arg1 : memref<1x5x34x60xf16, #NHWC, @CMX_NN>) outputs(%arg2 : memref<1x5x34x60xf16, #NHWC>) -> memref<1x5x34x60xf16, #NHWC>
    // CHECK:              }
    // CHECK:           return [[OUTPUT_COPY]] : memref<1x5x34x60xf16, #NHWC>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

module @VPU.SW {
  func.func private @builtin_PRelu(memref<*xf16, @CMX_NN>, memref<*xf16, @CMX_NN>) attributes {VPU.kernel_code = "prelu_fp16.cpp", VPU.kernel_entry = "prelu_fp16"}
  func.func private @runtime() attributes {VPU.kernel_code = "nnActEntry"}
}

func.func @TileClusterPRelu() -> memref<1x18x160x288xf16> {
    %0 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x18x160x288xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    %1 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x18x1x1xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    %2 = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x18x160x288xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    %3 = VPUIP.NCEClusterTiling inputs(%0 as %arg0: memref<1x18x160x288xf16, #NHWC, @CMX_NN>,
                                       %1 as %arg1: memref<1x18x1x1xf16, #NHWC, @CMX_NN>)
                                outputs(%2 as %arg2: memref<1x18x160x288xf16, #NHWC, @CMX_NN>)
                                      -> !VPUIP.DistributedBuffer<1x18x160x288xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
      %results = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 1, 0>} @VPU.SW::@builtin_PRelu
                    inputs(%arg0 as %arg3: memref<1x18x160x288xf16, #NHWC, @CMX_NN>,
                           %arg1 as %arg4: memref<1x18x1x1xf16, #NHWC, @CMX_NN>)
                    outputs(%arg2 as %arg5: memref<1x18x160x288xf16, #NHWC, @CMX_NN>) on tile 0 -> memref<1x18x160x288xf16, #NHWC, @CMX_NN>{
        VPUIP.SW.Kernel.run(%arg3, %arg4, %arg5) : memref<1x18x160x288xf16, #NHWC, @CMX_NN>, memref<1x18x1x1xf16, #NHWC, @CMX_NN>, memref<1x18x160x288xf16, #NHWC, @CMX_NN>
      }
    }

    %4 = memref.alloc() : memref<1x18x160x288xf16>
    %5 = VPUIP.NCEClusterTiling inputs(%3 as %arg1: memref<1x18x160x288xf16, @CMX_NN>) outputs(%4 as %arg2: memref<1x18x160x288xf16>) -> memref<1x18x160x288xf16> {
      %results = VPUIP.Copy inputs(%arg1 : memref<1x18x160x288xf16, @CMX_NN>) outputs(%arg2 : memref<1x18x160x288xf16>) -> memref<1x18x160x288xf16>
    }

    return %5: memref<1x18x160x288xf16>

    // For PRelu First Input
    // CHECK:    [[INPUT0:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x18x160x288xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[INPUT0_TILE0:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 80, 0] [1, 18, 80, 288]
    // CHECK:         !VPUIP.DistributedBuffer<1x18x160x288xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[INPUT0_TILE1:%.*]] = VPUIP.SubView [[INPUT0]] [0, 0, 0, 0] [1, 18, 80, 288]
    // CHECK:         !VPUIP.DistributedBuffer<1x18x160x288xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // For PRelu Second Input
    // CHECK:    [[INPUT1:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x18x1x1xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:    [[INPUT1_TILE0:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 0, 0] [1, 18, 1, 1]
    // CHECK:         !VPUIP.DistributedBuffer<1x18x1x1xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x18x1x1xf16, {order = #NHWC, strides = [18, 1, 18, 18]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>

    // CHECK:    [[INPUT1_TILE1:%.*]] = VPUIP.SubView [[INPUT1]] [0, 0, 0, 0] [1, 18, 1, 1]
    // CHECK:         !VPUIP.DistributedBuffer<1x18x1x1xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
    // CHECK:         !VPUIP.DistributedBuffer<1x18x1x1xf16, {order = #NHWC, strides = [18, 1, 18, 18]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>

    // CHECK:    [[PRELU_OUT:%.*]] = VPURT.AllocDistributed -> !VPUIP.DistributedBuffer<1x18x160x288xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[PRELU_OUT_TILE0:%.*]] = VPUIP.SubView [[PRELU_OUT]] [0, 0, 80, 0] [1, 18, 80, 288]
    // CHECK:    [[PRELU_OUT_TILE1:%.*]] = VPUIP.SubView [[PRELU_OUT]] [0, 0, 0, 0] [1, 18, 80, 288]
    // CHECK:    [[PRELU:%.*]]:2 = VPUIP.NCEClusterTiling
    // CHECK:                     inputs([[INPUT0_TILE1]] as [[ARG0:[^:]+]]: memref<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE1]] as [[ARG1:[^:]+]]: memref<1x18x1x1xf16, #NHWC, @CMX_NN>
    // CHECK:                            [[INPUT0_TILE0]] as [[ARG2:[^:]+]]: memref<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN>
    // CHECK:                            [[INPUT1_TILE0]] as [[ARG3:[^:]+]]: memref<1x18x1x1xf16, #NHWC, @CMX_NN>
    // CHECK:                     outputs([[PRELU_OUT_TILE1]] as [[ARG4:[^:]+]]: memref<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN>
    // CHECK:                            [[PRELU_OUT_TILE0]] as [[ARG5:[^:]+]]: memref<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN>
    // CHECK:                     -> (!VPUIP.DistributedBuffer<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPUIP.DistributedBuffer<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>)
    // CHECK:    %results:2 = VPUIP.SW.Kernel {resultSegmentSizes = array<i32: 2, 0>} @VPU.SW::@builtin_PRelu
    // CHECK:                     inputs([[ARG0]] as [[ARG6:[^:]+]]: memref<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN>
    // CHECK:                            [[ARG1]] as [[ARG7:[^:]+]]: memref<1x18x1x1xf16, #NHWC, @CMX_NN>
    // CHECK:                            [[ARG2]] as [[ARG8:[^:]+]]: memref<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN>
    // CHECK:                            [[ARG3]] as [[ARG9:[^:]+]]: memref<1x18x1x1xf16, #NHWC, @CMX_NN>
    // CHECK:                     outputs([[ARG4]] as [[ARG10:[^:]+]]: memref<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN>
    // CHECK:                             [[ARG5]] as [[ARG11:[^:]+]]: memref<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}([[ARG6]], [[ARG7]], [[ARG10]]) : memref<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN>, memref<1x18x1x1xf16, #NHWC, @CMX_NN>, memref<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN>
    // CHECK:        VPUIP.SW.Kernel.run {attrs = []}([[ARG8]], [[ARG9]], [[ARG11]]) : memref<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN>, memref<1x18x1x1xf16, #NHWC, @CMX_NN>, memref<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN>

    // CHECK:    [[CONCATVIEW:%.*]] = VPUIP.ConcatView inputs([[PRELU]]#0, [[PRELU]]#1
    // CHECK:                     !VPUIP.DistributedBuffer<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:                     !VPUIP.DistributedBuffer<1x18x80x288xf16, {order = #NHWC, strides = [829440, 1, 5184, 18]}, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:                     outputs([[PRELU_OUT]] : !VPUIP.DistributedBuffer<1x18x160x288xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<1x18x160x288xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    [[OUTPUT_BUF:%.*]] = memref.alloc() : memref<1x18x160x288xf16>
    // CHECK:    [[OUTPUT_COPY:%.*]] = VPUIP.NCEClusterTiling inputs([[CONCATVIEW]] as [[ARG12:[^:]+]]: memref<1x18x160x288xf16, @CMX_NN>)
    // CHECK:                                                 outputs([[OUTPUT_BUF]] as [[ARG13:[^:]+]]: memref<1x18x160x288xf16>) -> memref<1x18x160x288xf16>

    // CHECK:    return [[OUTPUT_COPY]] : memref<1x18x160x288xf16>
}
