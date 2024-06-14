//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --tiling-strategy-assignment="vpunn-cost=true" %s | FileCheck %s
// REQUIRES: arch-VPUX40XX

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @SplitNCEMaxPoolOverH
// CHECK-SAME:      [[INPUT:%arg[0-9]]]: tensor<1x16x200x200xf16, {order = #NHWC}>)
func.func @SplitNCEMaxPoolOverH(%arg0: tensor<1x16x200x200xf16, {order = #NHWC}>) -> tensor<1x16x200x200xf16, {order = #NHWC}> {
    %0 = VPU.NCE.MaxPool(%arg0) {
        kernel_size = [3, 3],
        pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
        strides = [1, 1]
    } -> tensor<1x16x200x200xf16, {order = #NHWC}>

    return %0 : tensor<1x16x200x200xf16, {order = #NHWC}>

    // CHECK:       [[MAXPOOL:%.+]] = VPU.NCE.MaxPool([[INPUT]]) {
    // CHECK-SAME:      pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
    // CHECK-SAME:      tilingStrategy = [1, 1, 4, 1]
    // CHECK-SAME:      } -> tensor<1x16x200x200xf16, {order = #NHWC}>

    // CHECK:       return [[MAXPOOL]] : tensor<1x16x200x200xf16, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!qElemType = !quant.uniform<u8:f16, 0.96372549019607844>
!qElemType1 = !quant.uniform<u8:f16, 0.054779411764705882>
!qElemType2 = !quant.uniform<u8<0:254>:f16, 8.7179349163385824E-4:127>

// CHECK-LABEL:   @SplitSparseQuantNCEConvOverC
// CHECK-SAME:          [[INPUT:%arg[0-9]]]: tensor<1x32x80x80x!qElemType, {order = #NHWC}>
func.func @SplitSparseQuantNCEConvOverC(%arg0: tensor<1x32x80x80x!qElemType, {order = #NHWC}>) -> tensor<1x320x80x80x!qElemType1, {order = #NHWC}> {
    %weights = const.Declare tensor<320x32x3x3x!qElemType2, {order = #NHWC}> = dense<1.000000e+00> : tensor<320x32x3x3xf16>, [#const.ConvertElemType<ui8>, #const.QuantCast<!qElemType2>, #const.Reorder<#NHWC>, #const.Sparsify<false>]
    %weights_sm = const.Declare tensor<320x1x1x384xi1> = dense<1.000000e+00> : tensor<320x32x3x3xf16>, [#const.Reorder<#NHWC>, #const.GetSparsityMap]
    %weights_sparse = VPU.GroupSparseTensor(%weights, %weights_sm) {sparsity_compression = #VPU.SparsityCompression<axis = 0 : i64, numElems = dense<1> : tensor<320xi64>, alignment = 16 : i64>, is_weights}
        -> !VPU.SparseTensor<data=tensor<320x32x3x3x!qElemType2, {order = #NHWC}>, sparsity_map=tensor<320x1x1x384xi1>, is_weights, #VPU.SparsityCompression<axis = 0 : i64, numElems = dense<1> : tensor<320xi64>, alignment = 16 : i64>>
    %weights_table = const.Declare tensor<320x1x1x4xsi32, {order = #NCHW}> = dense<10> : tensor<320x1x1x4xsi32>

    %0 = VPU.NCE.Convolution(%arg0, %weights_sparse, %weights_table) {
        pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
        rawFilterShape = [320, 32, 3, 3],
        strides = [1, 1]
    } -> tensor<1x320x80x80x!qElemType1, {order = #NHWC}>

    return %0 : tensor<1x320x80x80x!qElemType1, {order = #NHWC}>

    // CHECK-DAG:        [[WEIGHTS:%.+]] = const.Declare tensor<320x32x3x3x!qElemType2, {order = #NHWC}> = dense<1.000000e+00>
    // CHECK-SAME:      : tensor<320x32x3x3xf16>, [#const.ConvertElemType<ui8>, #const.QuantCast<!qElemType2>, #const.Reorder<#NHWC>, #const.Sparsify<false>]

    // CHECK-DAG:        [[WEIGHTS_SM:%.+]] = const.Declare tensor<320x1x1x384xi1> = dense<1.000000e+00>
    // CHECK-SAME:      : tensor<320x32x3x3xf16>, [#const.Reorder<#NHWC>, #const.GetSparsityMap]

    // CHECK:        [[WEIGHTS_SPARSE:%.+]] = VPU.GroupSparseTensor([[WEIGHTS]], [[WEIGHTS_SM]]) {is_weights, sparsity_compression = #VPU.SparsityCompression<axis = 0 : i64, numElems = dense<1> : tensor<320xi64>, alignment = 16 : i64>} -> !VPU.SparseTensor<
    // CHECK-SAME:       data=tensor<320x32x3x3x!qElemType2, {order = #NHWC}>,
    // CHECK-SAME:       sparsity_map=tensor<320x1x1x384xi1>, is_weights

    // CHECK-DAG:        [[WEIGHTS_TABLE:%.+]] = const.Declare tensor<320x1x1x4xsi32, {order = #NCHW}> = dense<10>
    // CHECK-SAME:      : tensor<320x1x1x4xsi32>

    // CHECK:        [[OUTPUT:%.+]] = VPU.NCE.Convolution([[INPUT]], [[WEIGHTS_SPARSE]], [[WEIGHTS_TABLE]])
    // CHECK-SAME:          pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
    // CHECK-SAME:          rawFilterShape = [320, 32, 3, 3], strides = [1, 1], tilingStrategy = [1, 1, 3, 1]
    // CHECK-SAME:          -> tensor<1x320x80x80x!qElemType1, {order = #NHWC}>

    // CHECK:        return [[OUTPUT]] : tensor<1x320x80x80x!qElemType1, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL:   @DontPrefetchToNonComputeParentOp
// CHECK-SAME:          [[INPUT:%arg[0-9]]]: tensor<2x1x1024xf16>
func.func @DontPrefetchToNonComputeParentOp(%arg: tensor<2x1x1024xf16>) -> tensor<1x4096x1x1xf16, {order = #NHWC}>
{
    %affine_reshape = VPU.AffineReshape(%arg) {dim_mapping = [[0], [0], [1, 2, 3]], shape_value = [2, 1024, 1, 1]} : tensor<2x1x1024xf16> -> tensor<2x1024x1x1xf16>
    %permute_cast = VPU.PermuteCast(%affine_reshape) {dst_order = #NHWC, mem_perm = #NHWC} : tensor<2x1024x1x1xf16> -> tensor<2x1024x1x1xf16, {order = #NHWC}>
    %slice = VPU.Slice %permute_cast [0, 0, 0, 0] [1, 1024, 1, 1] : tensor<2x1024x1x1xf16, {order = #NHWC}> to tensor<1x1024x1x1xf16, {order = #NHWC}>

    %weights = const.Declare tensor<4096x1024x1x1xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<4096x1024x1x1xf16>, [#const.Reorder<#NHWC>]
    %weights_table = const.Declare tensor<4096x1x1x4xsi32, {order = #NCHW}> = dense<10> : tensor<4096x1x1x4xsi32>
    %conv = VPU.NCE.Convolution(%slice, %weights, %weights_table) {
            multiClusterStrategy = #VPU.multi_cluster_strategy<SplitOverKernel>,
            pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
            rawFilterShape = [4096, 1024, 1, 1], strides = [1, 1]}
            -> tensor<1x4096x1x1xf16, {order = #NHWC}>
    return %conv : tensor<1x4096x1x1xf16, {order = #NHWC}>

    // No NCE or SW parent op of conv, so prefetching doesn't work
    // The tiling strategy is pipelining tiling
    // CHECK:       [[AFFINE_RESHAPE:%.+]] = VPU.AffineReshape([[INPUT]])
    // CHECK:       [[PERMUTE_CAST:%.+]] = VPU.PermuteCast([[AFFINE_RESHAPE]])
    // CHECK:       [[SLICE:%.+]] = VPU.Slice [[PERMUTE_CAST]]
    // CHECK-DAG:       [[WEIGHTS:%.+]] = const.Declare tensor<4096x1024x1x1xf16, {order = #NHWC}>
    // CHECK-DAG:       [[WT:%.+]] = const.Declare tensor<4096x1x1x4xsi32, {order = #NCHW}> = dense<10>
    // CHECK:       [[CONV:%.+]] = VPU.NCE.Convolution([[SLICE]], [[WEIGHTS]], [[WT]])
    // CHECK-SAME:       tilingStrategy = [1, 4, 1, 1]
    // CHECK:       return [[CONV]]
}