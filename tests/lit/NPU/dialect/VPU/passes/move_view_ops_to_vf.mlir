//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch% compilation-mode=DefaultHW" --move-view-ops-to-vf %s | FileCheck %s
// REQUIRES: arch-VPUX30XX || arch-VPUX37XX

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

func.func @MoveGroupSparseTensor(%arg0: tensor<1x32x24x30xf16, {order = #NHWC}>) -> tensor<1x16x48x60xf16, {order = #NHWC}> {
    %cst = const.Declare tensor<16x32x2x2xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<16x32x2x2xf16, {order = #NHWC}>
    %0 = VPU.StorageElementTable {dataElemType = f16, dataShape = [1, 32, 24, 30], seAttr = #VPU.SEUpsampling<factors = [1, 1], padding = [1, 1, 1, 1]>, seDepth = 1 : i64, seSize = 32 : i64} -> tensor<1x1x49x61xi32, {order = #NHWC}>
    %cst_0 = const.Declare tensor<1x32x49x61xi1, {order = #NHWC}> = dense<1> : tensor<1x32x49x61xi8>, [#const.Reorder<#NHWC>, #const.ConvertElemType<i1>]
    %1 = VPU.GroupSparseTensor(%arg0, %cst_0, %0) {seAttr = #VPU.SEUpsampling<factors = [1, 1], padding = [1, 1, 1, 1]>} -> !VPU.SparseTensor<data=tensor<1x32x24x30xf16, {order = #NHWC}>, sparsity_map=tensor<1x32x49x61xi1, {order = #NHWC}>, storage_element_table=tensor<1x1x49x61xi32, {order = #NHWC}>, #VPU.SEUpsampling<factors = [1, 1], padding = [1, 1, 1, 1]>>
    %cst_1 = const.Declare tensor<16x1x1x4xsi32> = dense<[[[[0, 0, 1065353216, 0]]], [[[256, 0, 1065353216, 0]]], [[[512, 0, 1065353216, 0]]], [[[768, 0, 1065353216, 0]]], [[[1024, 0, 1065353216, 0]]], [[[1280, 0, 1065353216, 0]]], [[[1536, 0, 1065353216, 0]]], [[[1792, 0, 1065353216, 0]]], [[[2048, 0, 1065353216, 0]]], [[[2304, 0, 1065353216, 0]]], [[[2560, 0, 1065353216, 0]]], [[[2816, 0, 1065353216, 0]]], [[[3072, 0, 1065353216, 0]]], [[[3328, 0, 1065353216, 0]]], [[[3584, 0, 1065353216, 0]]], [[[3840, 0, 1065353216, 0]]]]> : tensor<16x1x1x4xsi32>
    %2 = VPU.VerticalFusion (%1 as %arg1: !VPU.SparseTensor<data=tensor<1x32x24x30xf16, {order = #NHWC}>, sparsity_map=tensor<1x32x49x61xi1, {order = #NHWC}>, storage_element_table=tensor<1x1x49x61xi32, {order = #NHWC}>, #VPU.SEUpsampling<factors = [1, 1], padding = [1, 1, 1, 1]>>, %cst as %arg2: tensor<16x32x2x2xf16, {order = #NHWC}>, %cst_1 as %arg3: tensor<16x1x1x4xsi32>) attributes {tilingStrategy = [1, 1, 2, 1]} -> tensor<1x16x48x60xf16, {order = #NHWC}> {
      %3 = VPU.NCE.Convolution(%arg1, %arg2, %arg3) {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, rawFilterShape = [16, 32, 2, 2], strides = [1, 1]} -> tensor<1x16x48x60xf16, {order = #NHWC}> 
      VPU.Yield %3 
    }
    return %2 : tensor<1x16x48x60xf16, {order = #NHWC}>

    //CHECK:  [[SET:%.+]] = VPU.StorageElementTable {dataElemType = f16, dataShape = [1, 32, 24, 30], seAttr = #VPU.SEUpsampling<factors = [1, 1], padding = [1, 1, 1, 1]>, seDepth = 1 : i64, seSize = 32 : i64} -> tensor<1x1x49x61xi32, {order = #NHWC}>
    //CHECK:  VPU.VerticalFusion (%arg0 as %arg1: tensor<1x32x24x30xf16, {order = #NHWC}>, %cst_0 as %arg2: tensor<1x32x49x61xi1, {order = #NHWC}>, [[SET]] as %arg3: tensor<1x1x49x61xi32, {order = #NHWC}>, %cst_1 as %arg4: tensor<16x32x2x2xf16, {order = #NHWC}>, %cst as %arg5: tensor<16x1x1x4xsi32>) 
    //CHECK-SAME: attributes {tilingStrategy = [1, 1, 2, 1]} 
    //CHECK:  [[GST:%.+]] = VPU.GroupSparseTensor(%arg1, %arg2, %arg3) 
    //CHECK:  [[CONV:%.+]] = VPU.NCE.Convolution([[GST]], %arg4, %arg5)  
    //CHECK:  VPU.Yield [[CONV]] 
    
}
