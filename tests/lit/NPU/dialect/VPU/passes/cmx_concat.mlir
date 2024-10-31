//
// Copyright (C) 2022-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --cmx-concat --canonicalize %s | FileCheck %s
// REQUIRES: arch-NPU37XX || arch-NPU40XX

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

func.func @AllInputsAreBlockArgsNoChages(
            %input1: tensor<1x48x32x32xf16, {order = #NHWC}>,
            %input2: tensor<1x32x32x48xf16>,
            %weightsTableMaxPool: tensor<96x1x1x4xsi32, {mem_space = [@CMX_NN, 0], order = #NCHW}>)
           -> tensor<1x96x32x32xf16, {order = #NHWC}> {
    %1 = VPU.PermuteCast(%input2) {dst_order = #NHWC, mem_perm = #NCHW} : tensor<1x32x32x48xf16> -> tensor<1x48x32x32xf16, {order = #NHWC}>

    // Concat inputs are in DDR and Concat output is in DDR
    %2 = VPU.Concat(%input1, %1) {static_offsets = [[0, 0, 0, 0], [0, 48, 0, 0]]} : tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x96x32x32xf16, {order = #NHWC}>

    // Concat result copy-in for NCE user
    %3 = VPU.Copy(%2) {out_mem_space = [@CMX_NN, 0]} : tensor<1x96x32x32xf16, {order = #NHWC}> -> tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %4 = VPU.NCE.MaxPool(%3, %weightsTableMaxPool) {
            opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
            strides = [1, 1], kernel_size = [1, 1]
        } -> tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %5 = VPU.Copy(%4) : tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x96x32x32xf16, {order = #NHWC}>

    return %5 : tensor<1x96x32x32xf16, {order = #NHWC}>

    // CHECK:   [[IN_2:%.+]] = VPU.PermuteCast(%arg1)
    // CHECK:   [[CONCAT_OUT:%.+]] = VPU.Concat(%arg0, [[IN_2]])
    // CHECK:   [[IN_CMX:%.+]] = VPU.Copy([[CONCAT_OUT]]) {out_mem_space = [@CMX_NN, 0]}
    // CHECK:   [[OUT_CMX:%.+]] = VPU.NCE.MaxPool([[IN_CMX]], %arg2 )
    // CHECK:   [[OUT_DDR:%.+]] = VPU.Copy([[OUT_CMX]])
    // CHECK:   return [[OUT_DDR]] : tensor<1x96x32x32xf16, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!Distributed = !VPU.DistributedTensor<
    1x144x32x32xf16, #NHWC, @CMX_NN, {
   mode = "DUPLICATED",
    num_clusters = 4
}>

!DistributedTile = !VPU.DistributedTensor<
    1x48x32x32xf16, #NHWC, @CMX_NN, {
   mode = "DUPLICATED",
    num_clusters = 4
}>

!DistributedTileOutput = !VPU.DistributedTensor<
    1x48x32x32xf16, #NHWC, @CMX_NN, {
   mode = "DUPLICATED|SEGMENTED",
    num_tiles = [1, 4, 1, 1],
    num_clusters = 4
}>

func.func @ConcatClusterTilingOutputAndBlockArgInput(%input: tensor<1x48x32x32xf16, {order = #NHWC}>,
           %filter: tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
           %weightsTable: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
           %maxPoolWeightsTable: tensor<96x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
           %input2: tensor<1x32x1536xf16>)
           -> tensor<1x96x32x32xf16, {order = #NHWC}> {

    // Create a concat subgraph with DPU output and constant argument

    // Concat input from DPU
    %0 = VPU.NCE.ClusterTiling (%input as %arg0: tensor<1x48x32x32xf16, {order = #NHWC}>) -> !DistributedTile {
        %16 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %1 = VPU.NCE.ClusterTiling (%0 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter as %arg1: tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg2: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !DistributedTileOutput {
        %16 = VPU.NCE.DepthConvolution(%arg0, %arg1, %arg2)
            {opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
            rawFilterShape = [48, 1, 3, 3],
            strides = [1, 1]}
            -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %2 = VPU.NCE.ClusterTiling (%1 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x48x32x32xf16, {order = #NHWC}> {
        %16 = VPU.Copy(%arg0) : tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>
        VPU.Yield %16
    }

    // Concat const input
    %3 = VPU.Reshape(%input2) {shape_value = [1, 32, 32, 48]} : tensor<1x32x1536xf16> -> tensor<1x32x32x48xf16>
    %4 = VPU.PermuteCast(%3) {dst_order = #NHWC, mem_perm = #NCHW} : tensor<1x32x32x48xf16> -> tensor<1x48x32x32xf16, {order = #NHWC}>

    %5 = VPU.Concat(%2, %4) {static_offsets = [[0, 0, 0, 0], [0, 48, 0, 0]]} : tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x96x32x32xf16, {order = #NHWC}>

    %6 = VPU.NCE.ClusterTiling (%5 as %arg0: tensor<1x96x32x32xf16, {order = #NHWC}>) -> !Distributed {
        %16 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x96x32x32xf16, {order = #NHWC}> -> tensor<1x96x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %7 = VPU.NCE.ClusterTiling (
        %6 as %arg0: tensor<1x96x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %maxPoolWeightsTable as %arg1: tensor<96x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !Distributed {
        %16 = VPU.NCE.MaxPool(%arg0, %arg1) {
                opaque_ppe = #VPU.PPEStub<>,
                pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
                strides = [1, 1],
                kernel_size = [1, 1]
            } -> tensor<1x96x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %8 = VPU.NCE.ClusterTiling (%7 as %arg0: tensor<1x96x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x96x32x32xf16, {order = #NHWC}> {
        %16 = VPU.Copy(%arg0) : tensor<1x96x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x96x32x32xf16, {order = #NHWC}>
        VPU.Yield %16
    }

    return %8 : tensor<1x96x32x32xf16, {order = #NHWC}>

    // CHECK:       [[IN_DPU:%.+]] = VPU.NCE.ClusterTiling (%arg0 as %arg5: tensor<1x48x32x32xf16, {order = #NHWC}>)
    // CHECK-SAME:       -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}> {
    // CHECK:           VPU.Copy(%arg5) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

    // CHECK:       [[OUT_DPU:%.+]] =  VPU.NCE.ClusterTiling (
    // CHECK-SAME:                          [[IN_DPU]] as %arg5: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    // CHECK:                       VPU.NCE.DepthConvolution

    // CHECK:       [[RESHAPE:%.+]] = VPU.Reshape(%arg4) {shape_value = [1, 32, 32, 48]} : tensor<1x32x1536xf16> -> tensor<1x32x32x48xf16>
    // CHECK:       [[IN_CONST:%.+]] = VPU.PermuteCast([[RESHAPE]]) {dst_order = #NHWC, mem_perm = #NCHW} : tensor<1x32x32x48xf16> -> tensor<1x48x32x32xf16, {order = #NHWC}>
    // CHECK:       [[IN_CONST_CMX:%.+]] = VPU.NCE.ClusterTiling ([[IN_CONST]] as %arg5: tensor<1x48x32x32xf16, {order = #NHWC}>)
    // CHECK-SAME:        -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}> {
    // CHECK:                  VPU.Copy(%arg5) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

    // CHECK:       [[DPU_OUT_CAST:%.+]] = VPU.DistributedCast([[OUT_DPU]] :
    // CHECK-SAME       !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>)
    // CHECK-SAME:          -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>

    // CHECK:       [[OUT_CONCAT:%.+]] = VPU.Concat([[DPU_OUT_CAST]], [[IN_CONST_CMX]])
    // CHECK-SAME{LITERAL}:                 {static_offsets = [[0, 0, 0, 0], [0, 48, 0, 0]]} :
    // CHECK-SAME:          !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>,
    // CHECK-SAME:          !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>
    // CHECK-SAME:              -> !VPU.DistributedTensor<1x96x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>

    // CHECK:       [[OUT_CMX:%.+]] = VPU.NCE.ClusterTiling
    // CHECK-SAME:                          [[OUT_CONCAT]] as %arg5: tensor<1x96x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:                                   VPU.NCE.MaxPool

    // CHECK:       [[OUT_DDR:%.+]] = VPU.NCE.ClusterTiling (
    // CHECK-SAME:                      [[OUT_CMX]] as %arg5: tensor<1x96x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x96x32x32xf16, {order = #NHWC}> {
    // CHECK:                               VPU.Copy(%arg5) : tensor<1x96x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x96x32x32xf16, {order = #NHWC}>

    // CHECK:       return [[OUT_DDR]] : tensor<1x96x32x32xf16, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!Input_DDR = tensor<1x128x16x32xf16, {mem_space = @DDR, order = #NHWC}>

!InputStub_CMX = tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

func.func @ConcatClusterTilingOutputAndConstantInput2(%arg0: !Input_DDR,
        %weights: tensor<128x128x3x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable: tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
           -> !VPU.DistributedTensor<1x128x16x33xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {

    // constant input
    %input2 = const.Declare tensor<1x128x16x1xf16, {order = #NHWC}> = dense<0.000000e+00> :
        tensor<1x128x16x1xf16>, [#const.Reorder<#NHWC>]

    %input_cmx = VPU.NCE.ClusterTiling(%arg0 as %arg1: !Input_DDR)
                        -> tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> {
        %0 = VPU.Copy(%arg1) { out_mem_space = @CMX_NN } : !Input_DDR -> !InputStub_CMX
        VPU.Yield %0
    }

    %conv_output = VPU.NCE.ClusterTiling (
        %input_cmx as %arg2: !InputStub_CMX,
        %weights as %arg3: tensor<128x128x3x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg4: tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !VPU.DistributedTensor<1x128x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {

        %557 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 1 : i64, bottom = 1 : i64>,
            rawFilterShape = [128, 128, 3, 1], strides = [1, 1]} -> tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %557
    }

    %conv_ddr = VPU.NCE.ClusterTiling (%conv_output as %arg2: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>)
        -> tensor<1x128x16x32xf16, {order = #NHWC}> {

        %557 = VPU.Copy(%arg2) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        -> tensor<1x128x16x32xf16, {order = #NHWC}>
        VPU.Yield %557
    }

    %concat_output = VPU.Concat(%input2, %conv_ddr) {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 1]]} :
        tensor<1x128x16x1xf16, {order = #NHWC}>, tensor<1x128x16x32xf16, {order = #NHWC}>
            -> tensor<1x128x16x33xf16, {order = #NHWC}>

    %concat_cmx = VPU.NCE.ClusterTiling (%concat_output as %arg2: tensor<1x128x16x33xf16, {order = #NHWC}>)
            -> !VPU.DistributedTensor<1x128x16x33xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
        %557 = VPU.Copy(%arg2) {out_mem_space = @CMX_NN} : tensor<1x128x16x33xf16, {order = #NHWC}>
            -> tensor<1x128x16x33xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %557
    }

    %conv_2 = VPU.NCE.ClusterTiling (
        %concat_cmx as %arg2: tensor<1x128x16x33xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights as %arg3: tensor<128x128x3x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg4: tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !VPU.DistributedTensor<1x128x16x33xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {

        %557 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 1 : i64, bottom = 1 : i64>,
            rawFilterShape = [128, 128, 3, 1], strides = [1, 1]} -> tensor<1x128x16x33xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %557
    }

    return %conv_2: !VPU.DistributedTensor<1x128x16x33xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    //CHECK:        [[CST:%.*]] = const.Declare tensor<1x128x16x1xf16, {order = #NHWC}> = dense<0.000000e+00> : tensor<1x128x16x1xf16>, [#const.Reorder<#NHWC>]

    //CHECK:        [[CST_INPUT:%.*]] =  VPU.NCE.ClusterTiling ([[CST]] as %arg3: tensor<1x128x16x1xf16, {order = #NHWC}>) -> !VPU.DistributedTensor<1x128x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    //CHECK:            [[RES0:%.*]] = VPU.Copy(%arg3) {out_mem_space = @CMX_NN} : tensor<1x128x16x1xf16, {order = #NHWC}> -> tensor<1x128x16x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES0]]
    //CHECK:        }

    //CHECK:        [[INPUT_CMX:%.*]] = VPU.NCE.ClusterTiling (%arg0 as %arg3: tensor<1x128x16x32xf16, {mem_space = @DDR, order = #NHWC}>) -> tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> {
    //CHECK:            [[RES1:%.*]] = VPU.Copy(%arg3) {out_mem_space = @CMX_NN} : tensor<1x128x16x32xf16, {mem_space = @DDR, order = #NHWC}> -> tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES1]]
    //CHECK:        }

    //CHECK:        [[CONV_OUTPUT:%.*]] = VPU.NCE.ClusterTiling ([[INPUT_CMX]] as %arg3: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                %arg1 as %arg4: tensor<128x128x3x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                %arg2 as %arg5: tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    //CHECK-SAME:                -> !VPU.DistributedTensor<1x128x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    //CHECK:            [[RES2:%.*]] = VPU.NCE.Convolution(%arg3, %arg4, %arg5) {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 1 : i64, bottom = 1 : i64>, rawFilterShape = [128, 128, 3, 1], strides = [1, 1]} -> tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES2]]
    //CHECK:        }

    //CHECK:        [[CONCAT_OUTPUT:%.*]] = VPU.Concat([[CST_INPUT]], [[CONV_OUTPUT]])
    //CHECK-SAME{LITERAL}:             {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 1]]} :
    //CHECK-SAME:                      !VPU.DistributedTensor<1x128x16x1xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPU.DistributedTensor<1x128x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    //CHECK-SAME:                      -> !VPU.DistributedTensor<1x128x16x33xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!qElemType = !quant.uniform<u8:f16:1, {
    1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01,
    1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01}>
!qElemType1 = !quant.uniform<u8:f16:1,
    {1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01,
     1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01}>
!qElemType2 = !quant.uniform<u8:f16:1,
    {1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01,
     1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01,
     1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01,
     1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01}>
!qElemType3 = !quant.uniform<u8:f16:0,
    {1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01,
     1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01, 1.000000e-01, 2.000000e-01,
     1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01,
     1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01}>
!qElemType4 = !quant.uniform<u8:f16:0,
    {1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01,
     1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01, 1.500000e-01}>

!Input_DDR = tensor<1x16x16x157x!qElemType1, {mem_space = @DDR, order = #NHWC}>

!InputStub_CMX = tensor<1x16x16x157x!qElemType1, {mem_space = @CMX_NN, order = #NHWC}>

func.func @ConcatClusterTilingOutputAndConstantInput2WithPerAxisQuantization(%arg0: !Input_DDR,
        %weights: tensor<16x16x3x1x!qElemType4, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights_dw_conv: tensor<32x16x1x1x!qElemType3, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
        %weightsTable_dw_conv: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
           -> !VPU.DistributedTensor<1x32x16x157x!qElemType2, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {

    // constant input
    %input2 = const.Declare tensor<1x16x16x157x!qElemType, {order = #NHWC}> = dense<1.000000e+00> :
        tensor<1x16x16x157xf16>, [
            #const.CastElemType<ui8>,
            #const.CastElemType<!qElemType>,
            #const.Reorder<#NHWC>
        ]

    %input_cmx = VPU.NCE.ClusterTiling(%arg0 as %arg1: !Input_DDR)
                        -> tensor<1x16x16x157x!qElemType1, {mem_space = @CMX_NN, order = #NHWC}> {
        %0 = VPU.Copy(%arg1) { out_mem_space = @CMX_NN } : !Input_DDR -> !InputStub_CMX
        VPU.Yield %0
    }

    %conv_output = VPU.NCE.ClusterTiling (
        %input_cmx as %arg2: tensor<1x16x16x157x!qElemType1, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights as %arg3: tensor<16x16x3x1x!qElemType4, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg4: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !VPU.DistributedTensor<1x16x16x157x!qElemType1, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {

        %557 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 1 : i64, bottom = 1 : i64>,
            rawFilterShape = [16, 16, 3, 1], strides = [1, 1]} -> tensor<1x16x16x157x!qElemType1, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %557
    }

    %conv_out_ddr = VPU.NCE.ClusterTiling (%conv_output as %arg2: tensor<1x16x16x157x!qElemType1, {mem_space = @CMX_NN, order = #NHWC}>)
        -> tensor<1x16x16x157x!qElemType1, {order = #NHWC}> {

        %557 = VPU.Copy(%arg2) {out_mem_space = @DDR} : tensor<1x16x16x157x!qElemType1, {mem_space = @CMX_NN, order = #NHWC}>
        -> tensor<1x16x16x157x!qElemType1, {order = #NHWC}>
        VPU.Yield %557
    }

    %concat_output = VPU.Concat(%input2, %conv_out_ddr) {static_offsets = [[0, 0, 0, 0], [0, 16, 0, 0]]} :
        tensor<1x16x16x157x!qElemType, {order = #NHWC}>, tensor<1x16x16x157x!qElemType1, {order = #NHWC}>
            -> tensor<1x32x16x157x!qElemType2, {order = #NHWC}>

    %concat_cmx = VPU.NCE.ClusterTiling (%concat_output as %arg2: tensor<1x32x16x157x!qElemType2, {order = #NHWC}>)
            -> !VPU.DistributedTensor<1x32x16x157x!qElemType2, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
        %557 = VPU.Copy(%arg2) {out_mem_space = @CMX_NN} : tensor<1x32x16x157x!qElemType2, {order = #NHWC}>
            -> tensor<1x32x16x157x!qElemType2, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %557
    }

    %dw_conv = VPU.NCE.ClusterTiling (
        %concat_cmx as %arg1: tensor<1x32x16x157x!qElemType2, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights_dw_conv as %arg2: tensor<32x16x1x1x!qElemType3, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable_dw_conv as %arg3: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
          -> !VPU.DistributedTensor<1x32x16x157x!qElemType2, #NHWC, @CMX_NN,
              {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
        %inner = VPU.NCE.DepthConvolution(%arg1, %arg2, %arg3) {
          opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
          rawFilterShape = [32, 1, 3, 3], strides = [1, 1]}
              -> tensor<1x32x16x157x!qElemType2, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %inner
    }

    return %dw_conv: !VPU.DistributedTensor<1x32x16x157x!qElemType2, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    //CHECK:        [[CST:%.*]] = const.Declare tensor<1x16x16x157x!qElemType4, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x16x16x157xf16>

    //CHECK:        [[CST_INPUT:%.*]] =  VPU.NCE.ClusterTiling ([[CST]] as [[INNER_ARG0:[^:]+]]: tensor<1x16x16x157x!qElemType4, {order = #NHWC}>) -> !VPU.DistributedTensor<1x16x16x157x!qElemType4, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    //CHECK:            [[RES0:%.*]] = VPU.Copy([[INNER_ARG0]]) {out_mem_space = @CMX_NN} : tensor<1x16x16x157x!qElemType4, {order = #NHWC}> -> tensor<1x16x16x157x!qElemType4, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES0]]
    //CHECK:        }

    //CHECK:        [[INPUT_CMX:%.*]] = VPU.NCE.ClusterTiling (%arg0 as [[INNER_ARG1:[^:]+]]: tensor<1x16x16x157x!qElemType, {mem_space = @DDR, order = #NHWC}>) -> tensor<1x16x16x157x!qElemType, {mem_space = @CMX_NN, order = #NHWC}> {
    //CHECK:            [[RES1:%.*]] = VPU.Copy([[INNER_ARG1]]) {out_mem_space = @CMX_NN} : tensor<1x16x16x157x!qElemType, {mem_space = @DDR, order = #NHWC}> -> tensor<1x16x16x157x!qElemType, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES1]]
    //CHECK:        }

    //CHECK:        [[CONV_OUTPUT:%.*]] = VPU.NCE.ClusterTiling ([[INPUT_CMX]] as [[INNER_ARG2:[^:]+]]: tensor<1x16x16x157x!qElemType, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                %arg1 as [[INNER_ARG3:[^:]+]]: tensor<16x16x3x1x!qElemType1, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                %arg3 as [[INNER_ARG4:[^:]+]]: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    //CHECK-SAME:                -> !VPU.DistributedTensor<1x16x16x157x!qElemType, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    //CHECK:            [[RES2:%.*]] = VPU.NCE.Convolution([[INNER_ARG2]], [[INNER_ARG3]], [[INNER_ARG4]]) {
    //CHECK-SAME:           opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 1 : i64, bottom = 1 : i64>,
    //CHECK-SAME:           rawFilterShape = [16, 16, 3, 1], strides = [1, 1]} -> tensor<1x16x16x157x!qElemType, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES2]]
    //CHECK:        }

    //CHECK:        [[CONCAT_OUTPUT:%.*]] = VPU.Concat([[CST_INPUT]], [[CONV_OUTPUT]])
    //CHECK-SAME{LITERAL}:           {static_offsets = [[0, 0, 0, 0], [0, 16, 0, 0]]} :
    //CHECK-SAME:                    !VPU.DistributedTensor<1x16x16x157x!qElemType4, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    //CHECK-SAME:                    !VPU.DistributedTensor<1x16x16x157x!qElemType, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    //CHECK-SAME:                    -> !VPU.DistributedTensor<1x32x16x157x!qElemType3, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!qElemType = !quant.uniform<u8<0:254>:f16:0, {0.005432609498031496:127,0.0076202632874015751:127,0.0084814837598425202:127,0.010134719488188976:127,0.004432978592519685:127,0.0051903912401574806:127,0.012341596948818898:127,0.007293460875984252:127,0.0081815944881889757:127,0.0066513902559055121:127,0.0091427780511811017:127,0.008819820374015748:127,0.0069359005905511809:127,0.0061900221456692916:127,0.007331908218503937:127,0.0072319451279527561:127,0.0073972687007874014:127,0.006797490157480315:127,0.0076394869586614176:127,0.0088736466535433069:127,0.0074088029035433069:127,0.006293829970472441:127,0.0081277682086614167:127,0.0082507997047244086:127,0.0071934977854330711:127,0.0062707615649606301:127,0.006782111220472441:127,0.008704478346456693:127,0.0082123523622047237:127,0.0075203001968503934:127,0.006286140501968504:127,0.0069512795275590549:127,0.0051942359744094491:127,0.0071742741141732286:127,0.0037466935285433069:127,0.0086506520669291341:127,0.0061208169291338587:127,0.0042984128937007876:127,0.0072011872539370081:127,0.0075164554625984249:127,0.0078624810759476797:127,0.0086506520669291341:127,0.009719488188976378:127,0.0095272514763779531:127,0.0063899483267716535:127,0.0073357529527559055:127,0.0074049581692913384:127,0.008735236220472441:127,0.0072473240649606301:127,0.0094272883858267723:127,0.0074626291830708659:127,0.0068859190452755905:127,0.0066014087106299217:127,0.0074126476377952754:127,0.0062707615649606301:127,0.0065744955708661413:127,0.007758673720472441:127,0.006316898375984252:127,0.0082277312992125977:127,0.0054825910433070864:127,0.0095503198818897642:127,0.0082892470472440936:127,0.0081123892716535427:127,0.004905880905511811:127,0.0056556040846456697:127,0.0075433686023622043:127,0.0069551242618110234:127,0.0071204478346456697:127,0.0050788939468503934:127,0.005882443405511811:127,0.0077202263779527561:127,0.0064629982775590549:127,0.0066936823326771656:127,0.0081046998031496058:127,0.0065860297736220468:127,0.0051211860236220468:127,0.0057440329724409451:127,0.011749507874015748:127,0.0074664739173228344:127,0.0060362327755905509:127,0.0071550504429133861:127,0.0052980437992125986:127,0.0083200049212598433:127,0.0075587475393700783:127,0.0063284325787401575:127,0.0092581200787401566:127,0.005417230561023622:127,0.0071973425196850396:127,0.0066936823326771656:127,0.0060785248523622043:127,0.0085276205708661422:127,0.0067013718011811026:127,0.0050673597440944879:127,0.0077702079232283465:127,0.0061054379921259847:127,0.0068359375:127,0.0059324249507874014:127,0.0069743479330708659:127,0.007293460875984252:127,0.0057248093011811026:127,0.0071242925688976382:127,0.0057747908464566931:127,0.0062169352854330711:127,0.0069551242618110234:127,0.0064553088090551179:127,0.0049327940452755905:127,0.0070973794291338587:127,0.0055095041830708659:127,0.0066014087106299217:127,0.0055364173228346454:127,0.0094042199803149612:127,0.0057824803149606301:127,0.0077855868602362205:127,0.0080354945866141728:127,0.0084661048228346462:127,0.0093965305118110243:127,0.0093580831692913393:127,0.0096579724409448821:127,0.0057055856299212601:127,0.0076933132381889766:127,0.0071204478346456697:127,0.0057440329724409451:127,0.007347287155511811:127,0.0046329047736220468:127,0.0061438853346456697:127,0.0062438484251968506:127,0.0080047367125984248:127,0.0061784879429133861:127,0.0080431840551181098:127,0.0076548658956692916:127,0.0061054379921259847:127,0.0107421875:127,0.0094503567913385832:127,0.0096118356299212601:127,0.0064745324803149604:127,0.007347287155511811:127,0.0092119832677165346:127,0.0088890255905511809:127,0.0076241080216535436:127,0.0064437746062992124:127,0.0062899852362204725:127,0.007385734498031496:127,0.007858636811023622:127,0.0056094672736220468:127,0.0064168614665354329:127,0.0046290600393700783:127,0.0047251783956692916:127,0.0085353100393700791:127,0.0076548658956692916:127,0.010219303641732283:127,0.0059977854330708659:127,0.0079970472440944878:127,0.0061669537401574806:127,0.0069397453248031494:127,0.01028081938976378:127,0.0077702079232283465:127,0.0082584891732283457:127,0.0067936454232283465:127,0.0081123892716535427:127,0.0048635888287401575:127,0.0058247723917322835:127,0.0064207062007874014:127,0.0073588213582677165:127,0.004936638779527559:127,0.0064245509350393699:127,0.0061477300688976382:127,0.0065168245570866139:127,0.0084430364173228352:127,0.006797490157480315:127,0.0043253260334645671:127,0.0075203001968503934:127,0.0057132750984251971:127,0.005324956938976378:127,0.005324956938976378:127,0.0095041830708661422:127,0.006401482529527559:127,0.0076241080216535436:127,0.0063591904527559055:127,0.0094349778543307092:127,0.010488435039370079:127,0.0054133858267716535:127,0.010442298228346457:127,0.0080431840551181098:127,0.0058709092027559055:127,0.010342335137795276:127,0.0078893946850393699:127,0.006874384842519685:127,0.0080585629921259838:127,0.006363035187007874:127,0.0092042937992125977:127,0.005867064468503937:127,0.0052019254429133861:127,0.0059016670767716535:127,0.010926734744094488:127,0.0089428518700787399:127,0.005394162155511811:127,0.0084814837598425202:127,0.0064130167322834645:127,0.0049673966535433069:127,0.0058785986712598425:127,0.0049020361712598425:127,0.0081277682086614167:127,0.010734498031496063:127,0.0069128321850393699:127,0.0077086921751968506:127,0.008765994094488189:127,0.0091120201771653538:127,0.0093811515748031503:127,0.011380413385826772:127,0.0080739419291338578:127,0.0099194143700787399:127,0.0078970841535433069:127,0.0077394500492125986:127,0.007797121062992126:127,0.0055517962598425194:127,0.0067551980807086616:127,0.0054287647637795275:127,0.0065052903543307084:127,0.0077855868602362205:127,0.0088275098425196849:127,0.0045598548228346454:127,0.0054672121062992124:127,0.006316898375984252:127,0.0051442544291338587:127,0.005913201279527559:127,0.0052480622539370081:127,0.004859744094488189:127,0.006401482529527559:127,0.0084814837598425202:127,0.0072819266732283465:127,0.0076010396161417327:127,0.0081431471456692907:127,0.010903666338582677:127,0.0086045152559055121:127,0.0082046628937007867:127,0.007308839812992126:127,0.0066821481299212601:127,0.010342335137795276:127,0.0059977854330708659:127,0.0061400406003937012:127,0.010088582677165354:127,0.0076817790354330711:127,0.0074664739173228344:127,0.0084968626968503942:127,0.0074126476377952754:127,0.0065129798228346454:127,0.005820927657480315:127,0.0078893946850393699:127,0.009696419783464567:127,0.0053595595472440945:127,0.0077778973917322835:127,0.0067705770177165355:127,0.0085045521653543312:127,0.0052941990649606301:127,0.0091889148622047237:127,0.0107421875:127}>
!qElemType1 = !quant.uniform<u8<0:254>:f16:0, {0.0059631828248031494:127,0.010211614173228346:127,0.0044868048720472439:127,0.0080739419291338578:127,0.0059631828248031494:127,0.0074510949803149604:127,0.004456046998031496:127,0.0072357898622047246:127,0.0086275836614173231:127,0.0072050319881889766:127,0.0068705401082677165:127,0.0047828494094488191:127,0.0098348302165354329:127,0.0066090981791338587:127,0.006882074311023622:127,0.0073742002952755905:127,0.004379152312992126:127,0.01022699311023622:127,0.0059016670767716535:127,0.0081123892716535427:127,0.0062899852362204725:127,0.0072396345964566931:127,0.0065591166338582673:127,0.0040677288385826769:127,0.0062476931594488191:127,0.0061938668799212601:127,0.0076433316929133861:127,0.0067782664862204725:127,0.0070281742125984249:127,0.0059170460137795275:127,0.0060131643700787399:127,0.0084584153543307092:127,0.0059747170275590549:127,0.0065245140255905509:127,0.009696419783464567:127,0.010788324311023622:127,0.0085199311023622052:127,0.0099501722440944878:127,0.007301150344488189:127,0.0080970103346456687:127,0.010542261318897638:127,0.0071781188484251971:127,0.0089659202755905508:127,0.005882443405511811:127,0.007370355561023622:127,0.0095810777559055121:127,0.0063976377952755905:127,0.0069474347933070864:127,0.0086275836614173231:127,0.0075971948818897642:127,0.0089428518700787399:127,0.0072396345964566931:127,0.0078970841535433069:127,0.0080662524606299208:127,0.0075971948818897642:127,0.0078701710137795283:127,0.0089351624015748028:127,0.011541892224409449:127,0.0069512795275590549:127,0.0067628875492125986:127,0.0082738681102362197:127,0.0057517224409448821:127,0.0076317974901574806:127,0.0072973056102362205:127,0.0064130167322834645:127,0.0077279158464566931:127,0.0084814837598425202:127,0.0074203371062992124:127,0.010119340551181102:127,0.0080585629921259838:127,0.0062438484251968506:127,0.0059747170275590549:127,0.0049712413877952754:127,0.0080431840551181098:127,0.0076356422244094491:127,0.008765994094488189:127,0.0079047736220472439:127,0.0080739419291338578:127,0.0082046628937007867:127,0.0096733513779527561:127,0.005913201279527559:127,0.0073049950787401575:127,0.007308839812992126:127,0.0090428149606299208:127,0.01194943405511811:127,0.0065706508366141728:127,0.0072357898622047246:127,0.012018639271653543:127,0.0066706139271653546:127,0.0075779712106299217:127,0.008765994094488189:127,0.0071319820374015751:127,0.006386103592519685:127,0.0045867679625984249:127,0.0054441437007874014:127,0.0099501722440944878:127,0.0051173412893700783:127,0.0073126845472440945:127,0.0091043307086614167:127,0.0058170829232283465:127,0.0075356791338582673:127,0.0097886934055118109:127,0.0086660310039370081:127,0.0055633304625984249:127,0.0083046259842519693:127,0.0080662524606299208:127,0.0052519069881889766:127,0.0071281373031496066:127,0.0089505413385826768:127,0.0059977854330708659:127,0.0054364542322834645:127,0.0092273622047244086:127,0.0051711675688976382:127,0.006301519438976378:127,0.0078817052165354329:127,0.007378045029527559:127,0.0073203740157480315:127,0.0088890255905511809:127,0.0063053641732283465:127,0.005432609498031496:127,0.0065706508366141728:127,0.0056171567421259847:127,0.0090043676181102358:127,0.006355345718503937:127,0.0076164185531496066:127,0.010203924704724409:127,0.0063207431102362205:127,0.0081892839566929127:127,0.0078471021389398057:127,0.0060477669783464564:127,0.0074011134350393699:127,0.0076125738188976382:127,0.0075318343996062988:127,0.012218565452755906:127,0.0069781926673228344:127,0.0044214443897637795:127,0.007758673720472441:127,0.0081815944881889757:127,0.0090966412401574797:127,0.0075087659940944879:127,0.0043753075787401575:127,0.0093657726377952763:127,0.0077317605807086616:127,0.0054518331692913384:127,0.0058785986712598425:127,0.0086967888779527561:127,0.0065860297736220468:127,0.0082354207677165346:127,0.0064976008858267714:127,0.0078394131397637803:127,0.0092350516732283457:127,0.0066052534448818902:127,0.0055825541338582673:127,0.011165108267716535:127,0.0062822957677165355:127,0.0060131643700787399:127,0.0038178211122047246:127,0.0075702817421259847:127,0.0079509104330708659:127,0.0070243294783464564:127,0.0076510211614173231:127,0.004898191437007874:127,0.0072742372047244095:127,0.0051980807086614176:127,0.0071089136318897642:127,0.0063822588582677165:127,0.0061092827263779532:127,0.0082661786417322826:127,0.0069089874507874014:127,0.0074395607775590549:127,0.0065245140255905509:127,0.0079893577755905508:127,0.0074049581692913384:127,0.0064130167322834645:127,0.0073049950787401575:127,0.0089351624015748028:127,0.0074049581692913384:127,0.0070935346948818902:127,0.0041753813976377957:127,0.010211614173228346:127,0.008727546751968504:127,0.0059824064960629919:127,0.0080662524606299208:127,0.0076817790354330711:127,0.0094964936023622052:127,0.010034756397637795:127,0.0061784879429133861:127,0.0080508735236220468:127,0.005897822342519685:127,0.005394162155511811:127,0.0070973794291338587:127,0.006828248031496063:127,0.0089351624015748028:127,0.0095118725393700791:127,0.0054979699803149604:127,0.006774421751968504:127,0.0041407787893700783:127,0.0049712413877952754:127,0.0050173781988188974:127,0.0078663267488554705:127,0.007278081938976378:127,0.009727177657480315:127,0.010911355807086614:127,0.0069935716043307084:127,0.0043676181102362205:127,0.006797490157480315:127,0.0082200418307086606:127,0.0053441806102362205:127,0.0058939776082677165:127,0.0058170829232283465:127,0.0088736466535433069:127,0.005843996062992126:127,0.0066321665846456697:127,0.0068013348917322835:127,0.0078317232019319317:127,0.0080893208661417318:127,0.0061861774114173231:127,0.0053903174212598425:127,0.007370355561023622:127,0.005797859251968504:127,0.0069012979822834645:127,0.010234682578740157:127,0.0054556779035433069:127,0.0053672490157480315:127,0.0075818159448818902:127,0.0070127952755905509:127,0.0057786355807086616:127,0.0056133120078740153:127,0.0066437007874015751:127,0.0074972317913385824:127,0.0066360113188976382:127,0.0073357529527559055:127,0.008735236220472441:127,0.0070089505413385824:127,0.0074203371062992124:127,0.0056671382874015751:127,0.0058555302657480315:127,0.0073934239665354329:127,0.010373093011811024:127,0.0062438484251968506:127,0.0089197834645669289:127,0.0083584522637795283:127,0.007797121062992126:127,0.0098809670275590549:127,0.0095272514763779531:127,0.0073665108267716535:127,0.005843996062992126:127,0.010657603346456693:127,0.0085737573818897642:127,0.006393793061023622:127,0.0053672490157480315:127,0.006874384842519685:127,0.0067628875492125986:127,0.0066321665846456697:127,0.0060862143208661413:127,0.0057709461122047246:127}>
!qElemType2 = !quant.uniform<u8:f16, 0.005156310165629667:128>
!qElemType3 = !quant.uniform<u8:f16:1, {0.022924280166625975:128,0.027521947785919789:128,0.016755336873671589:128,0.023258573868695426:128,0.021329346825094783:128,0.022206858092663335:128,0.017414629693124808:128,0.025725302976720474:128,0.04035177417829925:128,0.039877452102361939:128,0.019696509604360542:128,0.016667206147137809:128,0.022648655199537092:128,0.023228304058897729:128,0.022925527423035864:128,0.020843727448407342:128,0.018640646280026905:128,0.017982464210659851:128,0.01435394661099303:128,0.034490536708457795:128,0.020809061387005973:128,0.01290123743169448:128,0.024218404994291419:128,0.027764709323060278:128,0.022276938195322074:128,0.021564958609786689:128,0.030791904412063899:128,0.029373210084204581:128,0.021013355255126952:128,0.024865405699786017:128,0.015163267827501483:128,0.02548813445895326:128,0.022903185264736999:128,0.021412530599855911:128,0.024912519080966127:128,0.02116099338905484:128,0.022823285121543736:128,0.030267009548112459:128,0.027108095206466374:128,0.016261517767812692:128,0.031718910441679113:128,0.017873536839204677:128,0.017845116409600948:128,0.018383743248733819:128,0.023326009862563189:128,0.022319818010517196:128,0.024800216450410729:128,0.027690827612783395:128,0.031142145044663373:128,0.026720663145476695:128,0.016528876622517903:128,0.020418733708998736:128,0.024138793758317536:128,0.03321515812593348:128,0.020590496998207242:128,0.018071114783193551:128,0.032032280342251647:128,0.030427253012563667:128,0.024438781364291323:128,0.019647213056975719:128,0.022821317934522443:128,0.024247758528765512:128,0.015760628382364909:128,0.025033511367498661:128,0.021588858436135686:128,0.016476582545860142:128,0.022650748608159084:128,0.0177277639800427:128,0.032576080397063611:128,0.019337154837215646:128,0.02297202839570887:128,0.029241308511472216:128,0.016522916158040364:128,0.026866492103127873:128,0.02092752269670075:128,0.034847379198261336:128,0.032781832825903801:128,0.014279078502281039:128,0.021762538423725202:128,0.021311290591370827:128,0.028667209662643134:128,0.023765770594278972:128,0.023815557068469478:128,0.044513461169074564:128,0.032421931098489197:128,0.03002499786077761:128,0.031838033713546453:128,0.024145556431190641:128,0.021161800272324505:128,0.031209955028459139:128,0.025283468470853918:128,0.01732616892047957:128,0.016823394625794654:128,0.02078382080676509:128,0.021091982897590188:128,0.024062400705674114:128,0.020331332262824565:128,0.028297197117524989:128,0.013211218516031902:128,0.016557588764265472:128,0.031070198732263903:128,0.022877749274758732:128,0.03624756195965935:128,0.01737187235963111:128,0.026132347069534601:128,0.026542629915125231:128,0.014909995770921895:128,0.024012755412681431:128,0.035427194483139933:128,0.024294342714197496:128,0.022404348149019128:128,0.021335845835068645:128,0.02256917766496247:128,0.023255689471375709:128,0.021388906591078814:128,0.020786159178789926:128,0.014618758126801136:128,0.032014418583290252:128,0.019043367049273324:128,0.03382606506347656:128,0.017791800405464922:128,0.017847973692650888:128,0.027465902590284162:128,0.013453326038285798:128,0.045102945963541669:128,0.02503055310716816:128,0.022987585441738952:128,0.026797996782789043:128,0.025158007004681755:128,0.026806553672341738:128,0.014629296227997425:128,0.022040096918741862:128,0.031678936528224573:128,0.019264440910488952:128,0.028550538829728668:128,0.0089593345043705967:128,0.020728477777219288:128,0.025210795683019302:128,0.02310800926358092:128,0.019929867164761413:128,0.018436292573517445:128,0.030014727162379844:128,0.022187463909971946:128,0.019751759136424345:128,0.017881738438325769:128,0.021602621265486174:128,0.024383567361270682:128,0.035712498309565528:128,0.027128069073546167:128,0.022044882119870653:128,0.023218316657870424:128,0.010626565708833583:128,0.031101613886216108:128,0.023069032968259327:128,0.021654069189931832:128,0.022204309351303998:128,0.016380965475942574:128,0.018854253432329965:128,0.021022813460406135:128,0.024309406093522615:128,0.022784648222081802:128,0.018934858546537512:128,0.024681219400144092:128,0.020703021217794979:128,0.019723523831834979:128,0.020057967129875631:128,0.014133816606858198:128,0.033596698910582298:128,0.023892684076346603:128,0.024609109467151117:128,0.028670646630081478:128,0.027292773302863626:128,0.017114382164151062:128,0.023647835675407857:128,0.03263408249499751:128,0.031196597978180529:128,0.020296502580829694:128,0.019465277241725549:128,0.025060953813440659:128,0.023614793665268842:128,0.03277554044536516:128,0.016632679396984623:128,0.023566106721466664:128,0.025345629336787204:128,0.024762559404560163:128,0.026401456197102866:128,0.026388040243410595:128,0.031358971315271711:128,0.019852470884136126:128,0.022528240727443322:128,0.024498611337998334:128,0.022034401052138386:128,0.026844589382994409:128,0.032649758282829733:128,0.023407607920029584:128,0.028706757227579753:128,0.020623823240691539:128,0.018634274426628562:128,0.011752599828383501:128,0.029385619070015703:128,0.025594127879423254:128,0.024044897042068782:128,0.029109748204549153:128,0.02352578219245462:128,0.021232704087799672:128,0.029677931467692056:128,0.031729544845281864:128,0.020515093148923389:128,0.017519626430436676:128,0.022067734774421244:128,0.030555308098886527:128,0.024671492857091568:128,0.025936851314469881:128,0.020540887234257718:128,0.029207931780347637:128,0.035684879153382545:128,0.010320494689193426:128,0.016845751743690639:128,0.028008460998535156:128,0.021619507845710307:128,0.031059879415175493:128,0.031349536484363033:128,0.020561781116560394:128,0.025361187317792105:128,0.029602952096976484:128,0.018419393838620655:128,0.020952611811020795:128,0.026997566223144531:128,0.024035680995267979:128,0.025962363972383388:128,0.02947376288619696:128,0.023551235011979647:128,0.024341737522798425:128,0.016866819531309838:128,0.022100001690434475:128,0.020389919654995786:128,0.019820029127831554:128,0.022071182961557426:128,0.025665016735301298:128,0.025656579522525563:128,0.026553053014418657:128,0.022017437803979013:128,0.030855760387345856:128,0.031257893057430493:128,0.03458897085750804:128,0.019402410469803157:128,0.035861882976457184:128,0.01602763849146226:128,0.036409243415383728:128,0.022965613533468807:128,0.023193195754406499:128,0.026030784494736614:128,0.034810817942899815:128,0.031546383278042663:128,0.01658791467255237:128,0.02175890885147394:128}>
!qElemType4 = !quant.uniform<u8:f16:1, {0.024341350443222942:128,0.017084268495148304:128,0.017526762158262963:128,0.044665418886670881:128,0.014878934037451651:128,0.018850030151067995:128,0.016790534935745539:128,0.020082926282695694:128,0.023479696348601697:128,0.030591532763312845:128,0.027739396749758252:128,0.023290029226564892:128,0.021164946462593828:128,0.021992782517975453:128,0.017892178367165959:128,0.018017791299258963:128,0.026160696441052008:128,0.021707076652377259:128,0.030337745068120023:128,0.035091850804347617:128,0.038212179670146867:128,0.018997417711744121:128,0.025354520947325463:128,0.018096489999808518:128,0.041950270708869489:128,0.022770389856076708:128,0.025570031708362057:128,0.032032403758927887:128,0.020588889776491651:128,0.016474928575403551:128,0.024502149282717236:128,0.017092663634057138:128,0.01953284787196739:128,0.03069486431047028:128,0.027772022696102367:128,0.02351812287872913:128,0.027301378811106964:128,0.019644579232907761:128,0.014204369806775859:128,0.024514086106244254:128,0.022035898881800034:128,0.02194381321177763:128,0.02391637259838628:128,0.019629545772776886:128,0.021901258767819873:128,0.021866880678663068:128,0.028815562117333507:128,0.020367299809175378:128,0.02017801415686514:128,0.02027588919097302:128,0.018120374866560394:128,0.03163609224207261:128,0.028229501200657266:128,0.033697266672171801:128,0.027003569696463791:128,0.021648082546159332:128,0.037176440743839037:128,0.021053306729185813:128,0.029609999002194871:128,0.021921356986550723:128,0.030988454818725586:128,0.015278868581734452:128,0.023755732704611385:128,0.022216230280259076:128,0.010132553063186944:128,0.028088727651857864:128,0.027280710257735905:128,0.027005802416333966:128,0.018992142583809647:128,0.015685843486411898:128,0.022894283369475719:128,0.030811408921784047:128,0.018662719165577608:128,0.018475387610641179:128,0.024181198606304095:128,0.026315094442928538:128,0.02299795898736692:128,0.023478675356098249:128,0.022808993096445122:128,0.013859868984596402:128,0.0211943037369672:128,0.014226069637373382:128,0.027809800353704714:128,0.021577684552061792:128,0.0253173407386331:128,0.026227669622383865:128,0.019921370113597198:128,0.038237407160740269:128,0.024433098587335323:128,0.016226603003109203:128,0.024370236490287033:128,0.02028341386832443:128,0.019333429897532745:128,0.034384877073998545:128,0.028963118908452053:128,0.023606765971464268:128,0.012830578579622156:128,0.019569406322404451:128,0.022250164256376378:128,0.021529918558457317:128,0.029063277151070391:128,0.018235214083802468:128,0.019385225632611441:128,0.024275055118635588:128,0.01666241159626082:128,0.0219663937886556:128,0.026289305032468308:128,0.019342298133700503:128,0.027341572443644206:128,0.02290661849227606:128,0.019716901405184877:128,0.016512735217225318:128,0.028441676906510897:128,0.029430806403066598:128,0.025039387684242399:128,0.0290895751878327:128,0.034764860190597234:128,0.037462103600595514:128,0.014935651947470272:128,0.026333272223379098:128,0.021660121281941731:128,0.03146632418913:128,0.0074371559947144748:128,0.017306253021838618:128,0.030173402674057905:128,0.026753038518569049:128,0.024928415522855872:128,0.027946134642058727:128,0.02711959539675245:128,0.01877438881817986:128,0.011445473689658968:128,0.035466824325860714:128,0.035045489142922791:128,0.025251347410912606:128,0.021097181357589423:128,0.022541612737319049:128,0.016336992675182866:128,0.024403808631148993:128,0.03086412467208563:128,0.019668556662166818:128,0.01370074421751733:128,0.023331060596540863:128,0.039728405896355123:128,0.020020642935060989:128,0.023440774281819662:128,0.021945705600813322:128,0.017145040923473881:128,0.030885625353046491:128,0.020945451773849186:128,0.024633088766359817:128,0.022831987867168353:128,0.020557569054996266:128,0.022508756787169213:128,0.018854217903286802:128,0.035635643379361023:128,0.023957647061815447:128,0.023875409481572171:128,0.024847699146644742:128,0.027310866935580384:128,0.013790276938793707:128,0.023084355335609586:128,0.021183111153396907:128,0.020882643905340458:128,0.028018241770127239:128,0.024005960950664446:128,0.0260496550915288:128,0.014959191808513567:128,0.022510457506366804:128,0.028647707957847445:128,0.021788427876491174:128,0.028315773197248869:128,0.02113511048111261:128,0.019874114616244446:128,0.0065872311592102047:128,0.020274905597462374:128,0.029604230207555433:128,0.029660956999834846:128,0.018450055402867933:128,0.026535367965698241:128,0.022571470223221125:128,0.018524928186454025:128,0.024386308707442936:128,0.030055336858711992:128,0.020580858342787799:128,0.037568182103774127:128,0.018204050438076842:128,0.020490150825650085:128,0.032532852771235445:128,0.019410906585992552:128,0.033519406412162035:128,0.028226811278100106:128,0.016053324119717466:128,0.021093229219025258:128,0.027210287954293047:128,0.0258023832358566:128,0.026240348815917969:128,0.026256708070343616:128,0.020656604392855774:128,0.026059163785448262:128,0.027235605202469173:128,0.019803535237031825:128,0.024764900581509458:128,0.018183741850011488:128,0.030860176273420744:128,0.020345575669232535:128,0.024832263647341261:128,0.018281142851885628:128,0.026999758739097445:128,0.020725088493496763:128,0.019325218948663448:128,0.040418579999138324:128,0.026050623725442326:128,0.026157405329685586:128,0.023497825510361614:128,0.01953307507084865:128,0.022577544754626703:128,0.02189783395505419:128,0.021924405939438764:128,0.015311581013249417:128,0.024261625140321021:128,0.028277059629851695:128,0.02353080207226323:128,0.028582099839752795:128,0.024015143338371726:128,0.014878405309190938:128,0.032525558097689762:128,0.014315143286013136:128,0.02874172435087316:128,0.018981773713055778:128,0.021773289699180454:128,0.025582790374755859:128,0.021595076018688725:128,0.036577097574869794:128,0.04283464282166724:128,0.031246350793277516:128,0.030953467125986137:128,0.022030807943905099:128,0.028258979086782418:128,0.016630327000337487:128,0.018631717270495844:128,0.023983245737412395:128,0.020275119706696154:128,0.020861704209271598:128,0.028151910445269417:128,0.018165918425017712:128,0.022749822279986214:128,0.026866668813368855:128,0.013554843266805013:128,0.031434390124152688:128,0.020783345839556527:128,0.028356490415685318:128,0.019601866778205423:128,0.025144323648190966:128,0.019934815986483705:128,0.021175317203297333:128,0.030968200459199794:128}>
!qElemType5 = !quant.uniform<u8:f16:1, {0.022924280166625975:128,0.027521947785919789:128,0.016755336873671589:128,0.023258573868695426:128,0.021329346825094783:128,0.022206858092663335:128,0.017414629693124808:128,0.025725302976720474:128,0.04035177417829925:128,0.039877452102361939:128,0.019696509604360542:128,0.016667206147137809:128,0.022648655199537092:128,0.023228304058897729:128,0.022925527423035864:128,0.020843727448407342:128,0.018640646280026905:128,0.017982464210659851:128,0.01435394661099303:128,0.034490536708457795:128,0.020809061387005973:128,0.01290123743169448:128,0.024218404994291419:128,0.027764709323060278:128,0.022276938195322074:128,0.021564958609786689:128,0.030791904412063899:128,0.029373210084204581:128,0.021013355255126952:128,0.024865405699786017:128,0.015163267827501483:128,0.02548813445895326:128,0.022903185264736999:128,0.021412530599855911:128,0.024912519080966127:128,0.02116099338905484:128,0.022823285121543736:128,0.030267009548112459:128,0.027108095206466374:128,0.016261517767812692:128,0.031718910441679113:128,0.017873536839204677:128,0.017845116409600948:128,0.018383743248733819:128,0.023326009862563189:128,0.022319818010517196:128,0.024800216450410729:128,0.027690827612783395:128,0.031142145044663373:128,0.026720663145476695:128,0.016528876622517903:128,0.020418733708998736:128,0.024138793758317536:128,0.03321515812593348:128,0.020590496998207242:128,0.018071114783193551:128,0.032032280342251647:128,0.030427253012563667:128,0.024438781364291323:128,0.019647213056975719:128,0.022821317934522443:128,0.024247758528765512:128,0.015760628382364909:128,0.025033511367498661:128,0.021588858436135686:128,0.016476582545860142:128,0.022650748608159084:128,0.0177277639800427:128,0.032576080397063611:128,0.019337154837215646:128,0.02297202839570887:128,0.029241308511472216:128,0.016522916158040364:128,0.026866492103127873:128,0.02092752269670075:128,0.034847379198261336:128,0.032781832825903801:128,0.014279078502281039:128,0.021762538423725202:128,0.021311290591370827:128,0.028667209662643134:128,0.023765770594278972:128,0.023815557068469478:128,0.044513461169074564:128,0.032421931098489197:128,0.03002499786077761:128,0.031838033713546453:128,0.024145556431190641:128,0.021161800272324505:128,0.031209955028459139:128,0.025283468470853918:128,0.01732616892047957:128,0.016823394625794654:128,0.02078382080676509:128,0.021091982897590188:128,0.024062400705674114:128,0.020331332262824565:128,0.028297197117524989:128,0.013211218516031902:128,0.016557588764265472:128,0.031070198732263903:128,0.022877749274758732:128,0.03624756195965935:128,0.01737187235963111:128,0.026132347069534601:128,0.026542629915125231:128,0.014909995770921895:128,0.024012755412681431:128,0.035427194483139933:128,0.024294342714197496:128,0.022404348149019128:128,0.021335845835068645:128,0.02256917766496247:128,0.023255689471375709:128,0.021388906591078814:128,0.020786159178789926:128,0.014618758126801136:128,0.032014418583290252:128,0.019043367049273324:128,0.03382606506347656:128,0.017791800405464922:128,0.017847973692650888:128,0.027465902590284162:128,0.013453326038285798:128,0.045102945963541669:128,0.02503055310716816:128,0.022987585441738952:128,0.026797996782789043:128,0.025158007004681755:128,0.026806553672341738:128,0.014629296227997425:128,0.022040096918741862:128,0.031678936528224573:128,0.019264440910488952:128,0.028550538829728668:128,0.0089593345043705967:128,0.020728477777219288:128,0.025210795683019302:128,0.02310800926358092:128,0.019929867164761413:128,0.018436292573517445:128,0.030014727162379844:128,0.022187463909971946:128,0.019751759136424345:128,0.017881738438325769:128,0.021602621265486174:128,0.024383567361270682:128,0.035712498309565528:128,0.027128069073546167:128,0.022044882119870653:128,0.023218316657870424:128,0.010626565708833583:128,0.031101613886216108:128,0.023069032968259327:128,0.021654069189931832:128,0.022204309351303998:128,0.016380965475942574:128,0.018854253432329965:128,0.021022813460406135:128,0.024309406093522615:128,0.022784648222081802:128,0.018934858546537512:128,0.024681219400144092:128,0.020703021217794979:128,0.019723523831834979:128,0.020057967129875631:128,0.014133816606858198:128,0.033596698910582298:128,0.023892684076346603:128,0.024609109467151117:128,0.028670646630081478:128,0.027292773302863626:128,0.017114382164151062:128,0.023647835675407857:128,0.03263408249499751:128,0.031196597978180529:128,0.020296502580829694:128,0.019465277241725549:128,0.025060953813440659:128,0.023614793665268842:128,0.03277554044536516:128,0.016632679396984623:128,0.023566106721466664:128,0.025345629336787204:128,0.024762559404560163:128,0.026401456197102866:128,0.026388040243410595:128,0.031358971315271711:128,0.019852470884136126:128,0.022528240727443322:128,0.024498611337998334:128,0.022034401052138386:128,0.026844589382994409:128,0.032649758282829733:128,0.023407607920029584:128,0.028706757227579753:128,0.020623823240691539:128,0.018634274426628562:128,0.011752599828383501:128,0.029385619070015703:128,0.025594127879423254:128,0.024044897042068782:128,0.029109748204549153:128,0.02352578219245462:128,0.021232704087799672:128,0.029677931467692056:128,0.031729544845281864:128,0.020515093148923389:128,0.017519626430436676:128,0.022067734774421244:128,0.030555308098886527:128,0.024671492857091568:128,0.025936851314469881:128,0.020540887234257718:128,0.029207931780347637:128,0.035684879153382545:128,0.010320494689193426:128,0.016845751743690639:128,0.028008460998535156:128,0.021619507845710307:128,0.031059879415175493:128,0.031349536484363033:128,0.020561781116560394:128,0.025361187317792105:128,0.029602952096976484:128,0.018419393838620655:128,0.020952611811020795:128,0.026997566223144531:128,0.024035680995267979:128,0.025962363972383388:128,0.02947376288619696:128,0.023551235011979647:128,0.024341737522798425:128,0.016866819531309838:128,0.022100001690434475:128,0.020389919654995786:128,0.019820029127831554:128,0.022071182961557426:128,0.025665016735301298:128,0.025656579522525563:128,0.026553053014418657:128,0.022017437803979013:128,0.030855760387345856:128,0.031257893057430493:128,0.03458897085750804:128,0.019402410469803157:128,0.035861882976457184:128,0.01602763849146226:128,0.036409243415383728:128,0.022965613533468807:128,0.023193195754406499:128,0.026030784494736614:128,0.034810817942899815:128,0.031546383278042663:128,0.01658791467255237:128,0.02175890885147394:128,0.024341350443222942:128,0.017084268495148304:128,0.017526762158262963:128,0.044665418886670881:128,0.014878934037451651:128,0.018850030151067995:128,0.016790534935745539:128,0.020082926282695694:128,0.023479696348601697:128,0.030591532763312845:128,0.027739396749758252:128,0.023290029226564892:128,0.021164946462593828:128,0.021992782517975453:128,0.017892178367165959:128,0.018017791299258963:128,0.026160696441052008:128,0.021707076652377259:128,0.030337745068120023:128,0.035091850804347617:128,0.038212179670146867:128,0.018997417711744121:128,0.025354520947325463:128,0.018096489999808518:128,0.041950270708869489:128,0.022770389856076708:128,0.025570031708362057:128,0.032032403758927887:128,0.020588889776491651:128,0.016474928575403551:128,0.024502149282717236:128,0.017092663634057138:128,0.01953284787196739:128,0.03069486431047028:128,0.027772022696102367:128,0.02351812287872913:128,0.027301378811106964:128,0.019644579232907761:128,0.014204369806775859:128,0.024514086106244254:128,0.022035898881800034:128,0.02194381321177763:128,0.02391637259838628:128,0.019629545772776886:128,0.021901258767819873:128,0.021866880678663068:128,0.028815562117333507:128,0.020367299809175378:128,0.02017801415686514:128,0.02027588919097302:128,0.018120374866560394:128,0.03163609224207261:128,0.028229501200657266:128,0.033697266672171801:128,0.027003569696463791:128,0.021648082546159332:128,0.037176440743839037:128,0.021053306729185813:128,0.029609999002194871:128,0.021921356986550723:128,0.030988454818725586:128,0.015278868581734452:128,0.023755732704611385:128,0.022216230280259076:128,0.010132553063186944:128,0.028088727651857864:128,0.027280710257735905:128,0.027005802416333966:128,0.018992142583809647:128,0.015685843486411898:128,0.022894283369475719:128,0.030811408921784047:128,0.018662719165577608:128,0.018475387610641179:128,0.024181198606304095:128,0.026315094442928538:128,0.02299795898736692:128,0.023478675356098249:128,0.022808993096445122:128,0.013859868984596402:128,0.0211943037369672:128,0.014226069637373382:128,0.027809800353704714:128,0.021577684552061792:128,0.0253173407386331:128,0.026227669622383865:128,0.019921370113597198:128,0.038237407160740269:128,0.024433098587335323:128,0.016226603003109203:128,0.024370236490287033:128,0.02028341386832443:128,0.019333429897532745:128,0.034384877073998545:128,0.028963118908452053:128,0.023606765971464268:128,0.012830578579622156:128,0.019569406322404451:128,0.022250164256376378:128,0.021529918558457317:128,0.029063277151070391:128,0.018235214083802468:128,0.019385225632611441:128,0.024275055118635588:128,0.01666241159626082:128,0.0219663937886556:128,0.026289305032468308:128,0.019342298133700503:128,0.027341572443644206:128,0.02290661849227606:128,0.019716901405184877:128,0.016512735217225318:128,0.028441676906510897:128,0.029430806403066598:128,0.025039387684242399:128,0.0290895751878327:128,0.034764860190597234:128,0.037462103600595514:128,0.014935651947470272:128,0.026333272223379098:128,0.021660121281941731:128,0.03146632418913:128,0.0074371559947144748:128,0.017306253021838618:128,0.030173402674057905:128,0.026753038518569049:128,0.024928415522855872:128,0.027946134642058727:128,0.02711959539675245:128,0.01877438881817986:128,0.011445473689658968:128,0.035466824325860714:128,0.035045489142922791:128,0.025251347410912606:128,0.021097181357589423:128,0.022541612737319049:128,0.016336992675182866:128,0.024403808631148993:128,0.03086412467208563:128,0.019668556662166818:128,0.01370074421751733:128,0.023331060596540863:128,0.039728405896355123:128,0.020020642935060989:128,0.023440774281819662:128,0.021945705600813322:128,0.017145040923473881:128,0.030885625353046491:128,0.020945451773849186:128,0.024633088766359817:128,0.022831987867168353:128,0.020557569054996266:128,0.022508756787169213:128,0.018854217903286802:128,0.035635643379361023:128,0.023957647061815447:128,0.023875409481572171:128,0.024847699146644742:128,0.027310866935580384:128,0.013790276938793707:128,0.023084355335609586:128,0.021183111153396907:128,0.020882643905340458:128,0.028018241770127239:128,0.024005960950664446:128,0.0260496550915288:128,0.014959191808513567:128,0.022510457506366804:128,0.028647707957847445:128,0.021788427876491174:128,0.028315773197248869:128,0.02113511048111261:128,0.019874114616244446:128,0.0065872311592102047:128,0.020274905597462374:128,0.029604230207555433:128,0.029660956999834846:128,0.018450055402867933:128,0.026535367965698241:128,0.022571470223221125:128,0.018524928186454025:128,0.024386308707442936:128,0.030055336858711992:128,0.020580858342787799:128,0.037568182103774127:128,0.018204050438076842:128,0.020490150825650085:128,0.032532852771235445:128,0.019410906585992552:128,0.033519406412162035:128,0.028226811278100106:128,0.016053324119717466:128,0.021093229219025258:128,0.027210287954293047:128,0.0258023832358566:128,0.026240348815917969:128,0.026256708070343616:128,0.020656604392855774:128,0.026059163785448262:128,0.027235605202469173:128,0.019803535237031825:128,0.024764900581509458:128,0.018183741850011488:128,0.030860176273420744:128,0.020345575669232535:128,0.024832263647341261:128,0.018281142851885628:128,0.026999758739097445:128,0.020725088493496763:128,0.019325218948663448:128,0.040418579999138324:128,0.026050623725442326:128,0.026157405329685586:128,0.023497825510361614:128,0.01953307507084865:128,0.022577544754626703:128,0.02189783395505419:128,0.021924405939438764:128,0.015311581013249417:128,0.024261625140321021:128,0.028277059629851695:128,0.02353080207226323:128,0.028582099839752795:128,0.024015143338371726:128,0.014878405309190938:128,0.032525558097689762:128,0.014315143286013136:128,0.02874172435087316:128,0.018981773713055778:128,0.021773289699180454:128,0.025582790374755859:128,0.021595076018688725:128,0.036577097574869794:128,0.04283464282166724:128,0.031246350793277516:128,0.030953467125986137:128,0.022030807943905099:128,0.028258979086782418:128,0.016630327000337487:128,0.018631717270495844:128,0.023983245737412395:128,0.020275119706696154:128,0.020861704209271598:128,0.028151910445269417:128,0.018165918425017712:128,0.022749822279986214:128,0.026866668813368855:128,0.013554843266805013:128,0.031434390124152688:128,0.020783345839556527:128,0.028356490415685318:128,0.019601866778205423:128,0.025144323648190966:128,0.019934815986483705:128,0.021175317203297333:128,0.030968200459199794:128}>
!qElemType6 = !quant.uniform<u8:f16, 0.012766204628289915:128>
!qElemType7 = !quant.uniform<u8<0:254>:f16:0, {4.6569343626968503E-4:127,7.4443666953740155E-4:127,6.0698742002952757E-4:127,5.3970457062007876E-4:127,4.303699403297244E-4:127,6.8195973794291337E-4:127,4.9741249384842518E-4:127,6.2765286663385824E-4:127,9.3282864788385824E-4:127,8.7179349163385824E-4:127,5.5508350762795275E-4:127,5.4835522268700788E-4:127,5.8968611589566933E-4:127,4.2484313484251969E-4:127,7.0214459276574809E-4:127,8.3574910802165357E-4:127,4.234013594980315E-4:127,8.073941929133858E-4:127,5.9593380905511814E-4:127,6.7186731053149606E-4:127,5.1134965551181098E-4:127,8.0114649975393699E-4:127,5.9160848302165358E-4:127,8.645846149114173E-4:127,6.8964920644685036E-4:127,7.0502814345472446E-4:127,6.2909464197834642E-4:127,8.1700602854330704E-4:127,7.0743110236220477E-4:127,5.5844765009842518E-4:127,7.6990803395669296E-4:127,5.7382658710629917E-4:127,6.242887241633858E-4:127,4.813126691683071E-4:127,6.5120186392716539E-4:127,4.8347533218503938E-4:127,6.1083215428149606E-4:127,6.9493571604330704E-4:127,6.0698742002952757E-4:127,6.7186731053149606E-4:127,6.5889133243110238E-4:127,5.925696665846457E-4:127,7.1367879552165358E-4:127,4.8804095410925197E-4:127,6.3726470226377948E-4:127,6.9829985851377948E-4:127,6.3630351870078736E-4:127,5.4066575418307088E-4:127,7.8865111343503938E-4:127,6.4399298720472446E-4:127,5.9112789124015751E-4:127,5.3201510211614176E-4:127,6.8820743110236217E-4:127,5.5892824187992124E-4:127,6.9349394069881886E-4:127,8.3767147514763782E-4:127,8.4680271899606301E-4:127,0.0010736420398622048:127,6.6513902559055119E-4:127,9.4772699311023627E-4:127,7.0887287770669296E-4:127,7.6269915723425191E-4:127,7.3818897637795275E-4:127,6.3293937623031492E-4:127,7.1512057086614176E-4:127,8.0931656003937005E-4:127,7.6317974901574809E-4:127,7.4972317913385824E-4:127,7.4107252706692912E-4:127,6.4399298720472446E-4:127,4.6737550750492124E-4:127,8.6266224778543305E-4:127,4.9693190206692912E-4:127,7.4203371062992124E-4:127,7.6414093257874021E-4:127,0.0010899821604330709:127,7.7471395177165358E-4:127,8.3046259842519689E-4:127,5.2720918430118114E-4:127,5.6950126107283461E-4:127,7.2521299827755907E-4:127,6.5985251599409451E-4:127,6.1659925565944881E-4:127,0.0010255828617125983:127,0.0010400006151574804:127,7.1512057086614176E-4:127,4.8491710752952757E-4:127,8.5256982037401575E-4:127,6.0362327755905513E-4:127,6.891686146653543E-4:127,9.9290262057086611E-4:127,5.060631459153543E-4:127,4.5055479515255907E-4:127,5.3201510211614176E-4:127,6.8676565575787399E-4:127,6.0794860359251969E-4:127,7.3146069143700788E-4:127,6.5168245570866145E-4:127,8.4343857652559057E-4:127,6.4062884473425191E-4:127,7.3915015994094487E-4:127,6.0458446112204725E-4:127,7.9489880659448819E-4:127,9.3715397391732279E-4:127,6.8820743110236217E-4:127,8.1508366141732279E-4:127,6.8388210506889762E-4:127,0.0010899821604330709:127,7.0502814345472446E-4:127,6.6802257627952757E-4:127,3.808689868356299E-4:127,7.5068436269685036E-4:127,9.0351254921259844E-4:127,5.9689499261811026E-4:127,0.0010986328125:127,6.7090612696850394E-4:127,6.4399298720472446E-4:127,8.6602639025590549E-4:127,6.0170091043307088E-4:127,7.3674720103346456E-4:127,6.8292092150590549E-4:127,8.5016686146653544E-4:127,6.9589689960629917E-4:127,6.6850316806102363E-4:127,8.4343857652559057E-4:127,7.7711691067913389E-4:127,0.0011418860728346456:127,8.2950141486220477E-4:127,6.0506505290354332E-4:127,6.6561961737204725E-4:127,6.2621109128937005E-4:127,6.6850316806102363E-4:127,6.6081369955708663E-4:127,8.2998200664370083E-4:127,7.2617418184055119E-4:127,8.2181194635826766E-4:127,0.0011043999138779527:127,7.9585999015748031E-4:127,7.2425181471456694E-4:127,6.3101700910433067E-4:127,9.4580462598425191E-4:127,8.073941929133858E-4:127,7.2184885580708663E-4:127,8.3959384227362207E-4:127,7.833646038385827E-4:127,7.8192282849409451E-4:127,6.5264363927165358E-4:127,6.8195973794291337E-4:127,7.9297643946850394E-4:127,6.8099855437992124E-4:127,7.7279158464566933E-4:127,6.4591535433070871E-4:127,6.992610420767716E-4:127,7.7903927780511814E-4:127,7.6702448326771658E-4:127,6.4831831323818902E-4:127,6.6321665846456694E-4:127,6.2524990772637793E-4:127,5.9833676796259845E-4:127,5.9305025836614176E-4:127,6.2092458169291337E-4:127,9.4003752460629916E-4:127,9.4964936023622052E-4:127,5.7767132135826767E-4:127,6.4399298720472446E-4:127,9.510911355807087E-4:127,6.1948280634842518E-4:127,7.146399790846457E-4:127,7.5164554625984249E-4:127,9.1024083415354331E-4:127,8.0979715182086611E-4:127,6.1467688853346456E-4:127,6.7234790231299212E-4:127,8.900559793307087E-4:127,8.1844780388779523E-4:127,6.992610420767716E-4:127,5.5219995693897637E-4:127,6.9589689960629917E-4:127,6.7667322834645668E-4:127,7.9585999015748031E-4:127,8.7756059301181098E-4:127,8.9149775467519689E-4:127,7.4587844488188974E-4:127,7.4491726131889762E-4:127,0.0010476900836614174:127,7.7759750246062995E-4:127,9.0495432455708663E-4:127,7.1752352977362207E-4:127,4.983736774114173E-4:127,6.8340151328740155E-4:127,4.3517585814468503E-4:127,6.2861405019685036E-4:127,5.4258812130905513E-4:127,8.7371585875984248E-4:127,5.4114634596456694E-4:127,7.4443666953740155E-4:127,5.7863250492125979E-4:127,4.6569343626968503E-4:127,6.7955677903543306E-4:127,8.0066590797244093E-4:127,6.6369725024606301E-4:127,5.7526836245078736E-4:127,6.2861405019685036E-4:127,8.2229253813976373E-4:127,5.6037001722440943E-4:127,5.2240326648622052E-4:127,6.3534233513779523E-4:127,5.9353085014763783E-4:127,6.2909464197834642E-4:127,8.8140532726377947E-4:127,8.2950141486220477E-4:127,6.2669168307086611E-4:127,6.9012979822834642E-4:127,8.1364188607283461E-4:127,5.6037001722440943E-4:127,7.4780081200787399E-4:127,9.0591550812007876E-4:127,5.4114634596456694E-4:127,5.0366018700787399E-4:127,7.9009288877952757E-4:127,6.8772683932086611E-4:127,7.8192282849409451E-4:127,8.544921875E-4:127,7.5116495447834642E-4:127,7.0358636811023627E-4:127,5.824772391732284E-4:127,5.0702432947834642E-4:127,7.8480637918307088E-4:127,7.5741264763779523E-4:127,8.7083230807086611E-4:127,6.8964920644685036E-4:127,4.9549012672244093E-4:127,7.4491726131889762E-4:127,6.891686146653543E-4:127,8.0210768331692912E-4:127,7.285771407480315E-4:127,7.0839228592519689E-4:127,7.0791169414370083E-4:127,7.5116495447834642E-4:127,5.4402989665354332E-4:127,6.4014825295275585E-4:127,6.3053641732283461E-4:127,4.0802242249015746E-4:127,6.3870647760826767E-4:127,7.2953832431102363E-4:127,0.0011053610974409449:127,5.3585983636811026E-4:127,7.9537939837598425E-4:127,5.824772391732284E-4:127,4.7722763902559057E-4:127,7.2040708046259845E-4:127,6.2717227485236217E-4:127,5.9977854330708663E-4:127,5.5123877337598425E-4:127,6.4495417076771658E-4:127,7.5597087229330704E-4:127,7.0166400098425191E-4:127,8.6314283956692912E-4:127,6.814791461614173E-4:127,0.0010476900836614174:127,4.7338290477362207E-4:127,4.6737550750492124E-4:127,8.0595241756889762E-4:127,7.7519454355314964E-4:127,8.9053657111220477E-4:127,8.7275467519685036E-4:127,7.9345703125E-4:127,7.1031465305118114E-4:127,9.7031480684055119E-4:127,6.0554564468503938E-4:127,5.887249323326772E-4:127,6.2524990772637793E-4:127,6.5985251599409451E-4:127,7.1608175442913389E-4:127,6.3293937623031492E-4:127,9.4772699311023627E-4:127,5.0654373769685036E-4:127,6.8051796259842518E-4:127,6.5985251599409451E-4:127,6.5696896530511814E-4:127,8.1508366141732279E-4:127,6.8099855437992124E-4:127,5.5604469119094487E-4:127,5.3489865280511814E-4:127,7.5260672982283461E-4:127,5.1711675688976373E-4:127,8.6122047244094487E-4:127,6.3293937623031492E-4:127,6.7427026943897637E-4:127,7.6798566683070871E-4:127,3.8375253752460632E-4:127,6.5985251599409451E-4:127,7.4732022022637793E-4:127,5.9016670767716539E-4:127,5.6085060900590549E-4:127,7.2905773252952757E-4:127,6.1083215428149606E-4:127,7.1992648868110238E-4:127,6.8772683932086611E-4:127,7.1367879552165358E-4:127,7.1031465305118114E-4:127,9.2225562869094487E-4:127,0.0010207769438976377:127,7.0262518454724415E-4:127,7.3818897637795275E-4:127,6.6994494340551181E-4:127,8.5112804502952756E-4:127,5.6133120078740155E-4:127,6.6610020915354332E-4:127,5.9785617618110238E-4:127,7.896122969980315E-4:127,5.8391901451771658E-4:127,6.7378967765748031E-4:127,5.392239788385827E-4:127,8.2229253813976373E-4:127,7.2953832431102363E-4:127,5.8439960629921264E-4:127,8.6266224778543305E-4:127,7.0887287770669296E-4:127,9.6695066437007876E-4:127,5.9160848302165358E-4:127,5.7815191313976373E-4:127,4.7122024175688974E-4:127,6.7715382012795275E-4:127,5.9353085014763783E-4:127,6.752314530019685E-4:127,8.4872508612204725E-4:127,6.9493571604330704E-4:127,7.6125738188976373E-4:127,4.3301319512795275E-4:127,5.5796705831692912E-4:127,4.7073964997539368E-4:127,5.0414077878937005E-4:127,7.9249584768700788E-4:127,5.1471379798228342E-4:127,7.7231099286417327E-4:127,7.7807809424212601E-4:127,6.6321665846456694E-4:127,8.1027774360236217E-4:127,8.9966781496062994E-4:127,6.141962967519685E-4:127,7.7375276820866145E-4:127,8.2181194635826766E-4:127,6.6802257627952757E-4:127,5.3826279527559057E-4:127,5.0558255413385824E-4:127,7.5452909694881886E-4:127,7.107952448326772E-4:127,7.1175642839566933E-4:127,5.5700587475393699E-4:127,7.1367879552165358E-4:127,5.4499108021653544E-4:127,4.8395592396653544E-4:127,7.5500968873031492E-4:127,6.5120186392716539E-4:127,5.7574895423228342E-4:127,6.4014825295275585E-4:127,6.8628506397637793E-4:127,3.5707969365157482E-4:127,7.1031465305118114E-4:127,6.4879890501968508E-4:127,5.1279143085629917E-4:127,7.0022222563976373E-4:127,5.4354930487204725E-4:127,7.2761595718503938E-4:127,5.6757889394685036E-4:127,6.6802257627952757E-4:127,6.3053641732283461E-4:127,6.4783772145669296E-4:127,4.1979692113681104E-4:127,6.8388210506889762E-4:127,7.2569359005905513E-4:127,0.0010236604945866141:127,7.4491726131889762E-4:127,5.3682101993110238E-4:127,4.7554556779035435E-4:127,5.6469534325787399E-4:127,4.9116480068897637E-4:127,8.7515763410433067E-4:127,5.7190421998031492E-4:127,8.2181194635826766E-4:127,6.4735712967519689E-4:127,5.8776374876968508E-4:127,5.8199664739173233E-4:127,8.6025928887795275E-4:127,8.2709845595472445E-4:127,4.9741249384842518E-4:127,7.9682117372047243E-4:127,7.9778235728346456E-4:127,8.3094319020669295E-4:127,4.9645131028543306E-4:127,4.9741249384842518E-4:127,6.2957523375984249E-4:127,5.6661771038385824E-4:127,6.2140517347440943E-4:127,9.7319835752952756E-4:127,9.217750369094488E-4:127,4.202775129183071E-4:127,6.4495417076771658E-4:127,5.2192267470472446E-4:127,5.8824434055118114E-4:127,7.1800412155511814E-4:127,6.8676565575787399E-4:127,7.7231099286417327E-4:127,6.5552718996062995E-4:127,7.896122969980315E-4:127,7.6125738188976373E-4:127,6.2861405019685036E-4:127,5.9785617618110238E-4:127,5.2000030757874021E-4:127,7.7375276820866145E-4:127,5.5796705831692912E-4:127,8.2709845595472445E-4:127,5.7334599532480311E-4:127,7.3386365034448819E-4:127,4.0634035125492124E-4:127,5.8584138164370083E-4:127,4.9981545275590549E-4:127,4.7506497600885829E-4:127,6.0266209399606301E-4:127,8.0499123400590549E-4:127,7.6462152436023627E-4:127,4.0417768823818896E-4:127,7.362666092519685E-4:127,6.3678411048228342E-4:127,4.9452894315944881E-4:127,3.801480991633858E-4:127,5.1759734867125979E-4:127,4.5295775406003938E-4:127,6.4062884473425191E-4:127,7.540485051673228E-4:127,6.281334584153543E-4:127,6.2284694881889762E-4:127,7.4587844488188974E-4:127,0.0011918676181102363:127,3.553976224163386E-4:127,4.8900213767224415E-4:127,6.7667322834645668E-4:127,7.1704293799212601E-4:127,6.6225547490157482E-4:127,9.0976024237204725E-4:127,5.2288385826771658E-4:127,7.5068436269685036E-4:127,6.0458446112204725E-4:127,7.8288401205708663E-4:127,4.8059178149606301E-4:127,5.5123877337598425E-4:127,5.9737558439960632E-4:127,5.2817036786417327E-4:127,7.3482483390748031E-4:127,5.4979699803149606E-4:127,5.709430364173228E-4:127,6.7667322834645668E-4:127,7.9105407234251969E-4:127,8.5353100393700788E-4:127,7.7134980930118114E-4:127,4.9549012672244093E-4:127,8.2181194635826766E-4:127,8.5353100393700788E-4:127,8.8573065329724415E-4:127,7.6125738188976373E-4:127,6.9109098179133855E-4:127,3.5683939776082679E-4:127,7.5885442298228342E-4:127,0.0010207769438976377:127,9.434016670767716E-4:127,0.0010976716289370079:127,5.7478777066929129E-4:127,6.242887241633858E-4:127,6.6610020915354332E-4:127,7.9441821481299212E-4:127,7.3578601747047243E-4:127,4.7602615957185042E-4:127,7.5308732160433067E-4:127,6.1852162278543306E-4:127,7.9730176550196849E-4:127,9.4484344242125979E-4:127,4.3757881705216534E-4:127,8.2277312992125979E-4:127,5.9353085014763783E-4:127,6.930133489173228E-4:127,8.7179349163385824E-4:127,4.7698734313484254E-4:127,7.1752352977362207E-4:127,4.3349378690944881E-4:127,8.5160863681102363E-4:127,8.3959384227362207E-4:127,7.4299489419291337E-4:127,9.472464013287402E-4:127,9.6743125615157481E-4:127,4.6280988558070865E-4:127,6.853238804133858E-4:127,7.362666092519685E-4:127,0.0010092427411417322:127,8.7996355191929129E-4:127,6.1707984744094487E-4:127,7.718304010826772E-4:127,7.1031465305118114E-4:127,6.2284694881889762E-4:127,5.3489865280511814E-4:127,4.411832554133858E-4:127,5.1807794045275585E-4:127,4.8299474040354332E-4:127,7.4780081200787399E-4:127,6.6177488312007876E-4:127,6.281334584153543E-4:127,5.5460291584645668E-4:127,7.1223702017716539E-4:127,9.3859574926181098E-4:127,7.1752352977362207E-4:127,6.8436269685039368E-4:127,8.506474532480315E-4:127}>

!ConvInputDistributed = !VPU.DistributedTensor<
    1x2048x13x13x!qElemType2, #NHWC, @CMX_NN, {
    mode = "DUPLICATED",
    num_clusters = 2,
    alignment = [1, 16, 1, 1]
}>

// CHECK-LABEL: @CMXConcatDistributedQuantPerAxisSameAxisAsConcat
// CHECK-SAME:  ([[ACT0:%.+]]: tensor<1x2048x13x13x!qElemType, {order = #NHWC}>, [[ACT1:%.+]]: tensor<1x2048x13x13x!qElemType, {order = #NHWC}>,
// CHECK-SAME:  [[FILTER0:%.+]]: tensor<256x2048x1x1x!qElemType1, {order = #NHWC}>,
// CHECK-SAME:  [[FILTER1:%.+]]: tensor<256x2048x1x1x!qElemType2, {order = #NHWC}>,
// CHECK-SAME:  [[FILTER2:%.+]]: tensor<512x16x1x1x!qElemType3, {order = #NHWC}>)
func.func @CMXConcatDistributedQuantPerAxisSameAxisAsConcat(
    %act0: tensor<1x2048x13x13x!qElemType2, {order = #NHWC}>,
    %act1: tensor<1x2048x13x13x!qElemType2, {order = #NHWC}>,
    %filter0: tensor<256x2048x1x1x!qElemType1, {order = #NHWC}>,
    %filter1: tensor<256x2048x1x1x!qElemType, {order = #NHWC}>,
    %filter2: tensor<512x16x1x1x!qElemType7, {order = #NHWC}>)
           -> tensor<1x512x13x13x!qElemType6, {order = #NHWC}> {

    %weightsTable0 = const.Declare tensor<256x1x1x4xsi32> =
        dense<1> : tensor<256x1x1x4xsi32>

    %weightsTable1 = const.Declare tensor<256x1x1x4xsi32> =
        dense<1> : tensor<256x1x1x4xsi32>

    %weightsTable2 = const.Declare tensor<512x1x1x4xsi32> =
        dense<1> : tensor<512x1x1x4xsi32>

    %act0_cmx = VPU.NCE.ClusterTiling (%act0 as %arg1: tensor<1x2048x13x13x!qElemType2, {order = #NHWC}>) -> !ConvInputDistributed {
      %inner = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<1x2048x13x13x!qElemType2, {order = #NHWC}>
        -> tensor<1x2048x13x13x!qElemType2, {mem_space = @CMX_NN, order = #NHWC}>
      VPU.Yield %inner
    }

    %filter0_cmx = VPU.NCE.ClusterTiling (%filter0 as %arg1: tensor<256x2048x1x1x!qElemType1, {order = #NHWC}>)
        -> !VPU.DistributedTensor<256x2048x1x1x!qElemType1, #NHWC, @CMX_NN,
            {mode = "SEGMENTED", num_tiles = [2, 1, 1, 1], num_clusters = 2 : i64, alignment = [16, 1, 1, 1]}> {
      %inner = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<256x2048x1x1x!qElemType1, {order = #NHWC}>
        -> tensor<256x2048x1x1x!qElemType1, {mem_space = @CMX_NN, order = #NHWC}>
      VPU.Yield %inner
    }

    %weightsTable0_cmx = VPU.NCE.ClusterTiling (%weightsTable0 as %arg1: tensor<256x1x1x4xsi32>)
        -> !VPU.DistributedTensor<256x1x1x4xsi32, #NCHW, @CMX_NN,
            {mode = "SEGMENTED", num_tiles = [2, 1, 1, 1], num_clusters = 2 : i64, alignment = [16, 1, 1, 1]}> {
      %inner = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<256x1x1x4xsi32>
        -> tensor<256x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
      VPU.Yield %inner
    }

    %conv_0 = VPU.NCE.ClusterTiling (
        %act0_cmx as %arg1: tensor<1x2048x13x13x!qElemType2, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter0_cmx as %arg2: tensor<256x2048x1x1x!qElemType1, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0_cmx as %arg3: tensor<256x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !VPU.DistributedTensor<1x256x13x13x!qElemType3, #NHWC, @CMX_NN,
                {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}> {
      %inner = VPU.NCE.Convolution(%arg1, %arg2, %arg3) {
        opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
        rawFilterShape = [256, 2048, 1, 1], strides = [1, 1]
      } -> tensor<1x256x13x13x!qElemType3, {mem_space = @CMX_NN, order = #NHWC}>
      VPU.Yield %inner
    }

    %conv_0_ddr = VPU.NCE.ClusterTiling (%conv_0 as %arg1: tensor<1x256x13x13x!qElemType3, {mem_space = @CMX_NN, order = #NHWC}>)
        -> tensor<1x256x13x13x!qElemType3, {order = #NHWC}> {
      %inner = VPU.Copy(%arg1) : tensor<1x256x13x13x!qElemType3, {mem_space = @CMX_NN, order = #NHWC}>
        -> tensor<1x256x13x13x!qElemType3, {order = #NHWC}>
      VPU.Yield %inner
    }

    %act1_cmx = VPU.NCE.ClusterTiling (%act1 as %arg1: tensor<1x2048x13x13x!qElemType2, {order = #NHWC}>) -> !ConvInputDistributed {
      %inner = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<1x2048x13x13x!qElemType2, {order = #NHWC}>
        -> tensor<1x2048x13x13x!qElemType2, {mem_space = @CMX_NN, order = #NHWC}>
      VPU.Yield %inner
    }

    %filter1_cmx = VPU.NCE.ClusterTiling (%filter1 as %arg1: tensor<256x2048x1x1x!qElemType, {order = #NHWC}>)
        -> !VPU.DistributedTensor<256x2048x1x1x!qElemType, #NHWC, @CMX_NN,
            {mode = "SEGMENTED", num_tiles = [2, 1, 1, 1], num_clusters = 2 : i64, alignment = [16, 1, 1, 1]}> {
      %inner = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<256x2048x1x1x!qElemType, {order = #NHWC}>
        -> tensor<256x2048x1x1x!qElemType, {mem_space = @CMX_NN, order = #NHWC}>
      VPU.Yield %inner
    }

    %weightsTable1_cmx = VPU.NCE.ClusterTiling (%weightsTable1 as %arg1: tensor<256x1x1x4xsi32>)
        -> !VPU.DistributedTensor<256x1x1x4xsi32, #NCHW, @CMX_NN,
            {mode = "SEGMENTED", num_tiles = [2, 1, 1, 1], num_clusters = 2 : i64, alignment = [16, 1, 1, 1]}> {
      %inner = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<256x1x1x4xsi32>
        -> tensor<256x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
      VPU.Yield %inner
    }

    %conv_1 = VPU.NCE.ClusterTiling (
        %act1_cmx as %arg1: tensor<1x2048x13x13x!qElemType2, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter1_cmx as %arg2: tensor<256x2048x1x1x!qElemType, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable1_cmx as %arg3: tensor<256x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !VPU.DistributedTensor<1x256x13x13x!qElemType4, #NHWC, @CMX_NN,
            {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}> {
      %inner = VPU.NCE.Convolution(%arg1, %arg2, %arg3) {
        opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
        rawFilterShape = [256, 2048, 1, 1], strides = [1, 1]}
            -> tensor<1x256x13x13x!qElemType4, {mem_space = @CMX_NN, order = #NHWC}>
      VPU.Yield %inner
    }

    %conv_1_ddr = VPU.NCE.ClusterTiling (%conv_1 as %arg1: tensor<1x256x13x13x!qElemType4, {mem_space = @CMX_NN, order = #NHWC}>)
        -> tensor<1x256x13x13x!qElemType4, {order = #NHWC}> {
      %inner = VPU.Copy(%arg1) : tensor<1x256x13x13x!qElemType4, {mem_space = @CMX_NN, order = #NHWC}>
        -> tensor<1x256x13x13x!qElemType4, {order = #NHWC}>
      VPU.Yield %inner
    }

    %concat = VPU.Concat(%conv_0_ddr, %conv_1_ddr) {static_offsets = [[0, 0, 0, 0], [0, 256, 0, 0]]} :
        tensor<1x256x13x13x!qElemType3, {order = #NHWC}>, tensor<1x256x13x13x!qElemType4, {order = #NHWC}>
            -> tensor<1x512x13x13x!qElemType5, {order = #NHWC}>

    %concat_cmx = VPU.NCE.ClusterTiling (%concat as %arg1: tensor<1x512x13x13x!qElemType5, {order = #NHWC}>)
        -> !VPU.DistributedTensor<1x512x13x13x!qElemType5, #NHWC, @CMX_NN,
        {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}> {
      %inner = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<1x512x13x13x!qElemType5, {order = #NHWC}>
        -> tensor<1x512x13x13x!qElemType5, {mem_space = @CMX_NN, order = #NHWC}>
      VPU.Yield %inner
    }

    %filter2_cmx = VPU.NCE.ClusterTiling (%filter2 as %arg1: tensor<512x16x1x1x!qElemType7, {order = #NHWC}>)
        -> !VPU.DistributedTensor<512x16x1x1x!qElemType7, #NHWC, @CMX_NN,
            {mode = "SEGMENTED", num_tiles = [2, 1, 1, 1], num_clusters = 2 : i64, alignment = [16, 1, 1, 1]}> {
      %inner = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<512x16x1x1x!qElemType7, {order = #NHWC}>
        -> tensor<512x16x1x1x!qElemType7, {mem_space = @CMX_NN, order = #NHWC}>
      VPU.Yield %inner
    }

    %weightsTable2_cmx = VPU.NCE.ClusterTiling (%weightsTable2 as %arg1: tensor<512x1x1x4xsi32>)
        -> !VPU.DistributedTensor<512x1x1x4xsi32, #NCHW, @CMX_NN,
            {mode = "SEGMENTED", num_tiles = [2, 1, 1, 1], num_clusters = 2 : i64, alignment = [16, 1, 1, 1]}> {
      %inner = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<512x1x1x4xsi32>
        -> tensor<512x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
      VPU.Yield %inner
    }

    %dw_conv = VPU.NCE.ClusterTiling (
      %concat_cmx as %arg1: tensor<1x512x13x13x!qElemType5, {mem_space = @CMX_NN, order = #NHWC}>,
      %filter2_cmx as %arg2: tensor<512x16x1x1x!qElemType7, {mem_space = @CMX_NN, order = #NHWC}>,
      %weightsTable2_cmx as %arg3: tensor<512x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !VPU.DistributedTensor<1x512x13x13x!qElemType6, #NHWC, @CMX_NN,
            {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}> {
      %inner = VPU.NCE.DepthConvolution(%arg1, %arg2, %arg3) {
        opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
        rawFilterShape = [512, 1, 3, 3], strides = [1, 1]}
            -> tensor<1x512x13x13x!qElemType6, {mem_space = @CMX_NN, order = #NHWC}>
      VPU.Yield %inner
    }

    %dw_conv_cast = VPU.DistributedCast(
      %dw_conv : !VPU.DistributedTensor<1x512x13x13x!qElemType6, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>)
      -> !VPU.DistributedTensor<1x512x13x13x!qElemType6, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>

    %dw_conv_ddr = VPU.NCE.ClusterTiling (%dw_conv_cast as %arg1: tensor<1x512x13x13x!qElemType6, {mem_space = @CMX_NN, order = #NHWC}>)
        -> tensor<1x512x13x13x!qElemType6, {order = #NHWC}> {
      %inner = VPU.Copy(%arg1) : tensor<1x512x13x13x!qElemType6, {mem_space = @CMX_NN, order = #NHWC}>
        -> tensor<1x512x13x13x!qElemType6, {order = #NHWC}>
      VPU.Yield %inner
    }

    return %dw_conv_ddr : tensor<1x512x13x13x!qElemType6, {order = #NHWC}>

// CHECK:       [[CST0:%.+]] = const.Declare tensor<256x1x1x4xsi32>
// CHECK:       [[CST1:%.+]] = const.Declare tensor<512x1x1x4xsi32>

// CHECK:       [[INCMX0:%.+]] = VPU.NCE.ClusterTiling ([[ACT0]] as [[INNER_ARG0:[^:]+]]: tensor<1x2048x13x13x!qElemType, {order = #NHWC}>)
// CHECK-NEXT:      VPU.Copy([[INNER_ARG0]])

// CHECK:       [[WCMX0:%.+]] = VPU.NCE.ClusterTiling ([[FILTER0]] as [[INNER_ARG1:[^:]+]]: tensor<256x2048x1x1x!qElemType1, {order = #NHWC}>)
// CHECK-NEXT:      VPU.Copy([[INNER_ARG1]])

// CHECK:       [[WTCMX0:%.+]] = VPU.NCE.ClusterTiling ([[CST0]] as [[INNER_ARG2:[^:]+]]: tensor<256x1x1x4xsi32>)
// CHECK-NEXT:      VPU.Copy([[INNER_ARG2]])

// CHECK:       [[NCE0:%.+]] = VPU.NCE.ClusterTiling ([[INCMX0]] as [[INNER_ARG3:[^:]+]]: tensor<1x2048x13x13x!qElemType, {mem_space = @CMX_NN, order = #NHWC}>,
// CHECK-SAME:    [[WCMX0]] as [[INNER_ARG4:[^:]+]]: tensor<256x2048x1x1x!qElemType1, {mem_space = @CMX_NN, order = #NHWC}>,
// CHECK-SAME:    [[WTCMX0]] as [[INNER_ARG5:[^:]+]]: tensor<256x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x256x13x13x!qElemType5, #NHWC, @CMX_NN
// CEHCK-SAME:          {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}> {
// CHECK-NEXT:      VPU.NCE.Convolution([[INNER_ARG3]], [[INNER_ARG4]], [[INNER_ARG5]])
// CHECK-SAME:        {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, rawFilterShape = [256, 2048, 1, 1], strides = [1, 1]}
// CHECK-SAME:         -> tensor<1x256x13x13x!qElemType5, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[INCMX1:%.+]] = VPU.NCE.ClusterTiling ([[ACT1]] as [[INNER_ARG6:[^:]+]]: tensor<1x2048x13x13x!qElemType, {order = #NHWC}>)
// CHECK-NEXT:      VPU.Copy([[INNER_ARG6]])

// CHECK:       [[WCMX1:%.+]] = VPU.NCE.ClusterTiling ([[FILTER1]] as [[INNER_ARG7:[^:]+]]: tensor<256x2048x1x1x!qElemType2, {order = #NHWC}>)
// CHECK-NEXT:      VPU.Copy([[INNER_ARG7]])

// CHECK:       [[WTCMX1:%.+]] = VPU.NCE.ClusterTiling ([[CST0]] as [[INNER_ARG8:[^:]+]]: tensor<256x1x1x4xsi32>)
// CHECK-NEXT:      VPU.Copy([[INNER_ARG8]])

// CHECK:       [[NCE1:%.+]] = VPU.NCE.ClusterTiling ([[INCMX1]] as [[INNER_ARG9:[^:]+]]: tensor<1x2048x13x13x!qElemType, {mem_space = @CMX_NN, order = #NHWC}>,
// CHECK-SAME:    [[WCMX1]] as [[INNER_ARG10:[^:]+]]: tensor<256x2048x1x1x!qElemType2, {mem_space = @CMX_NN, order = #NHWC}>,
// CHECK-SAME:    [[WTCMX1]] as [[INNER_ARG11:[^:]+]]: tensor<256x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x256x13x13x!qElemType6, #NHWC, @CMX_NN,
// CHECK-SAME:          {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}> {
// CHECK-NEXT:      VPU.NCE.Convolution([[INNER_ARG9]], [[INNER_ARG10]], [[INNER_ARG11]])
// CHECK-SAME:        {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, rawFilterShape = [256, 2048, 1, 1], strides = [1, 1]}
// CHECK-SAME:        -> tensor<1x256x13x13x!qElemType6, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[DCAST0:%.+]] = VPU.DistributedCast(
// CHECK-SAME:    [[NCE0]] : !VPU.DistributedTensor<1x256x13x13x!qElemType5, #NHWC, @CMX_NN,
// CHECK-SAME:                  {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>)
// CHECK-SAME:    -> !VPU.DistributedTensor<1x256x13x13x!qElemType5, #NHWC, @CMX_NN,
// CHECK-SAME:        {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>

// CHECK:       [[DCAST1:%.+]] = VPU.DistributedCast(
// CHECK-SAME:    [[NCE1]] : !VPU.DistributedTensor<1x256x13x13x!qElemType6, #NHWC, @CMX_NN,
// CHECK-SAME:                  {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>)
// CHECK-SAME:    -> !VPU.DistributedTensor<1x256x13x13x!qElemType6, #NHWC, @CMX_NN,
// CHECK-SAME:        {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>

// CHECK:       [[CONCAT:%.+]] = VPU.Concat([[DCAST0]], [[DCAST1]])
// CHECK-SAME{LITERAL}: {static_offsets = [[0, 0, 0, 0], [0, 256, 0, 0]]} :
// CHECK-SAME:      !VPU.DistributedTensor<1x256x13x13x!qElemType5, #NHWC, @CMX_NN,
// CHECK-SAME:       {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>,
// CHECK-SAME:      !VPU.DistributedTensor<1x256x13x13x!qElemType6, #NHWC, @CMX_NN,
// CHECK-SAME:       {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>
// CHECK-SAME:      -> !VPU.DistributedTensor<1x512x13x13x!qElemType7, #NHWC, @CMX_NN,
// CHECK-SAME:          {mode = "DUPLICATED", num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}>

// CHECK:       [[WCMX2:%.+]] = VPU.NCE.ClusterTiling ([[FILTER2]] as [[INNER_ARG12:[^:]+]]: tensor<512x16x1x1x!qElemType3, {order = #NHWC}>)
// CHECK-NEXT:      VPU.Copy([[INNER_ARG12]])

// CHECK:       [[WTCMX2:%.+]] = VPU.NCE.ClusterTiling ([[CST1]] as [[INNER_ARG13:[^:]+]]: tensor<512x1x1x4xsi32>)
// CHECK-NEXT:      VPU.Copy([[INNER_ARG13]])

// CHECK:       [[NCE2:%.+]] = VPU.NCE.ClusterTiling ([[CONCAT]] as [[INNER_ARG14:[^:]+]]: tensor<1x512x13x13x!qElemType7, {mem_space = @CMX_NN, order = #NHWC}>,
// CHECK-SAME:      [[WCMX2]] as [[INNER_ARG15:[^:]+]]: tensor<512x16x1x1x!qElemType3, {mem_space = @CMX_NN, order = #NHWC}>,
// CHECK-SAME:      [[WTCMX2]] as [[INNER_ARG16:[^:]+]]: tensor<512x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x512x13x13x!qElemType4, #NHWC, @CMX_NN,
// CHECK-SAME           {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1]}> {
// CHECK-NEXT:      VPU.NCE.DepthConvolution([[INNER_ARG14]], [[INNER_ARG15]], [[INNER_ARG16]])
// CHECK-SAME:          {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>, rawFilterShape = [512, 1, 3, 3], strides = [1, 1]}
// CHECK-SAME:      -> tensor<1x512x13x13x!qElemType4, {mem_space = @CMX_NN, order = #NHWC}>

}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

func.func @ConcatNCEOutputAndBlockArgInput(%input: tensor<1x48x32x32xf16, {order = #NHWC}>,
           %filter: tensor<48x16x1x1xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>,
           %weightsTable: tensor<48x1x1x4xsi32, {mem_space = [@CMX_NN, 0], order = #NCHW}>,
           %weightsTableMaxPool: tensor<96x1x1x4xsi32, {mem_space = [@CMX_NN, 0], order = #NCHW}>,
           %input2: tensor<1x32x32x48xf16>)
           -> tensor<1x96x32x32xf16, {order = #NHWC}> {

    // Create a concat subgraph with three input tiles and one output user

    // Concat input from DPU
    %0 = VPU.Copy(%input) {out_mem_space = [@CMX_NN, 0]} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %1 = VPU.NCE.DepthConvolution(%0, %filter, %weightsTable)
        {opaque_ppe = #VPU.PPEStub<>,
        pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
        post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
        rawFilterShape = [48, 1, 3, 3],
        strides = [1, 1]}
        -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    // NCE copy-out to concatinate in DDR
    %2 = VPU.Copy(%1) : tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>

    // Concat const input
    %3 = VPU.PermuteCast(%input2) {dst_order = #NHWC, mem_perm = #NCHW} : tensor<1x32x32x48xf16> -> tensor<1x48x32x32xf16, {order = #NHWC}>

    // Concat inputs are in DDR and Concat output is in DDR
    %4 = VPU.Concat(%3, %2) {static_offsets = [[0, 0, 0, 0], [0, 48, 0, 0]]} : tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x96x32x32xf16, {order = #NHWC}>

    // Concat result copy-in for NCE user
    %5 = VPU.Copy(%4) {out_mem_space = [@CMX_NN, 0]} : tensor<1x96x32x32xf16, {order = #NHWC}> -> tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %6 = VPU.NCE.MaxPool(%5, %weightsTableMaxPool) {
            opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
            strides = [1, 1], kernel_size = [1, 1]
        } -> tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %7 = VPU.Copy(%6) : tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x96x32x32xf16, {order = #NHWC}>

    return %7 : tensor<1x96x32x32xf16, {order = #NHWC}>

    // CHECK:       [[IN_DPU:%.+]] = VPU.Copy(%arg0) {out_mem_space = [@CMX_NN, 0]} : tensor<1x48x32x32xf16, {order = #NHWC}>
    // CHECK-SAME:                      -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    // CHECK:       [[OUT_DPU:%.+]] = VPU.NCE.DepthConvolution([[IN_DPU]], %arg1, %arg2)

    // CHECK:       [[IN_CONST:%.+]] = VPU.PermuteCast(%arg4) {dst_order = #NHWC, mem_perm = #NCHW} : tensor<1x32x32x48xf16>
    // CHECK-SAME:                      -> tensor<1x48x32x32xf16, {order = #NHWC}>
    // CHECK:       [[IN_CONST_CMX:%.+]] = VPU.Copy([[IN_CONST]]) {out_mem_space = [@CMX_NN, 0]} : tensor<1x48x32x32xf16, {order = #NHWC}>
    // CHECK-SAME:                      -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    // CHECK:       [[CONCAT_CMX:%.+]] = VPU.Concat([[IN_CONST_CMX]], [[OUT_DPU]])
    // CHECK-SAME{LITERAL}:             {static_offsets = [[0, 0, 0, 0], [0, 48, 0, 0]]} :
    // CHECK-SAME:                      tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>, tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    // CHECK-SAME:                      -> tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    // CHECK:       [[OUT_CMX:%.+]] = VPU.NCE.MaxPool([[CONCAT_CMX]], %arg3 )
    // CHECK:       [[OUT_DDR:%.+]] = VPU.Copy([[OUT_CMX]]) : tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    // CHECK-SAME:                      -> tensor<1x96x32x32xf16, {order = #NHWC}>

    // CHECK:       return [[OUT_DDR]] : tensor<1x96x32x32xf16, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @CaseWithoutChildTiling
module @CaseWithoutChildTiling {

IE.CNNNetwork
    entryPoint : @main
    inputsInfo : {
        DataInfo "input" : tensor<1x144x32x32xf16>
        DataInfo "filter" : tensor<48x16x1x1xf16, {mem_space = [@CMX_NN, 0]}>
        DataInfo "weightsTable" : tensor<48x1x1x4xsi32, {mem_space = [@CMX_NN, 0]}>
        DataInfo "weightsTableMaxPool" : tensor<144x1x1x4xsi32, {mem_space = [@CMX_NN, 0]}>
    }
    outputsInfo : {
        DataInfo "prob" : tensor<1x144x32x32xf16>
    }

func.func @main(%input: tensor<1x144x32x32xf16, {order = #NHWC}>,
           %filter: tensor<48x16x1x1xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>,
           %weightsTable: tensor<48x1x1x4xsi32, {mem_space = [@CMX_NN, 0], order = #NCHW}>,
           %weightsTableMaxPool: tensor<144x1x1x4xsi32, {mem_space = [@CMX_NN, 0], order = #NCHW}>)
           -> tensor<1x144x32x32xf16, {order = #NHWC}> {

    // Create a concat subgraph with three input tiles and one output user

    // Concat input tile 1
    %0 = VPU.Slice %input [0, 0, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>
    %1 = VPU.Copy(%0) {out_mem_space = [@CMX_NN, 0]} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %2 = VPU.NCE.DepthConvolution(%1, %filter, %weightsTable)
        {opaque_ppe = #VPU.PPEStub<>,
        pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
        post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
        rawFilterShape = [48, 1, 3, 3],
        strides = [1, 1]}
        -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    // NCE copy-out to concatinate in DDR
    %3 = VPU.Copy(%2) : tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>

    // Concat input tile 2
    %4 = VPU.Slice %input [0, 48, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>
    %5 = VPU.Copy(%4) {out_mem_space = [@CMX_NN, 0]} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %6 = VPU.NCE.DepthConvolution(%5, %filter, %weightsTable)
        {opaque_ppe = #VPU.PPEStub<>,
        pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
        post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
        rawFilterShape = [48, 1, 3, 3],
        strides = [1, 1]}
        -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    // NCE copy-out to concatinate in DDR
    %7 = VPU.Copy(%6) : tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>

    // Concat input tile 3
    %8 = VPU.Slice %input [0, 96, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>
    %9 = VPU.Copy(%8) {out_mem_space = [@CMX_NN, 0]} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %10 = VPU.NCE.DepthConvolution(%9, %filter, %weightsTable)
        {opaque_ppe = #VPU.PPEStub<>,
        pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
        post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>, rawFilterShape = [48, 1, 3, 3],
        strides = [1, 1]}
        -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    // NCE copy-out to concatinate in DDR
    %11 = VPU.Copy(%10) : tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>

    // Concat inputs are in DDR and Concat output is in DDR
    %12 = VPU.Concat(%3, %7, %11) {static_offsets = [[0, 0, 0, 0], [0, 48, 0, 0], [0, 96, 0, 0]]} : tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x144x32x32xf16, {order = #NHWC}>

    // Concat result copy-in for NCE user
    %13 = VPU.Copy(%12) {out_mem_space = [@CMX_NN, 0]} : tensor<1x144x32x32xf16, {order = #NHWC}> -> tensor<1x144x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %14 = VPU.NCE.MaxPool(%13, %weightsTableMaxPool) {
            opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
            strides = [1, 1], kernel_size = [1, 1]
        } -> tensor<1x144x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %15 = VPU.Copy(%14) : tensor<1x144x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x144x32x32xf16, {order = #NHWC}>

    return %15 : tensor<1x144x32x32xf16, {order = #NHWC}>

    // the below checks that the concat is occuring in NNCMX and the copy operations
    // arround the concat are not used by the concat producer and consumer operations

    // input to the first tile copy-in (DDR->NNCMX) for weights
    // CHECK:       [[VAL0:%.+]] = VPU.Slice %arg0
    // CHECK-SAME:      [0, 0, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>
    // CHECK:       [[VAL1:%.+]] = VPU.Copy([[VAL0]])

    // first tile of NCE task
    // CHECK:       [[VAL2:%.+]] = VPU.NCE.DepthConvolution([[VAL1]], %arg1, %arg2)

    // no copy-out to concatinate in DDR
    // CHECK-NOT:   VPU.Copy

    // input to the second tile copy-in (DDR->NNCMX) for weights
    // CHECK:       [[VAL3:%.+]] = VPU.Slice %arg0
    // CHECK-SAME:      [0, 48, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>
    // CHECK:       [[VAL4:%.+]] = VPU.Copy([[VAL3]])

    // second tile of NCE task
    // CHECK:       [[VAL5:%.+]] = VPU.NCE.DepthConvolution([[VAL4]], %arg1, %arg2)

    // no copy-out to concatinate in DDR
    // CHECK-NOT:   VPU.Copy

    // input to the third tile copy-in (DDR->NNCMX) for weights
    // CHECK:       [[VAL6:%.+]] = VPU.Slice %arg0
    // CHECK-SAME:      [0, 96, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>
    // CHECK:       [[VAL7:%.+]] = VPU.Copy([[VAL6]])

    // third tile of NCE task
    // CHECK:       [[VAL8:%.+]] = VPU.NCE.DepthConvolution([[VAL7]], %arg1, %arg2)

    // no copy-out to concatinate in DDR
    // CHECK-NOT:   VPU.Copy

    // no copy-out (NNCMX->DDR) operations to concatinate in DDR
    // Concat in NNCMX using results of NCE tiles in NNCMX
    // CHECK:       [[VAL9:%.+]] = VPU.Concat([[VAL2]], [[VAL5]], [[VAL8]])

    // no Concat buffer copy-in to NNCMX
    // CHECK-NOT:   VPU.Copy

    // user of the concat uses result of concat without intermediate copy operation
    // CHECK:       [[VAL10:%.+]] = VPU.NCE.MaxPool([[VAL9]], %arg3 )
    // CHECK:       [[VAL11:%.+]] = VPU.Copy([[VAL10]])

    // CHECK:       return [[VAL11:%.+]] : tensor<1x144x32x32xf16, {order = #NHWC}>
}

}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @CaseWithChildTiling
module @CaseWithChildTiling {

IE.CNNNetwork
    entryPoint : @main
    inputsInfo : {
        DataInfo "input" : tensor<1x144x32x32xf16>
        DataInfo "filter" : tensor<48x16x1x1xf16, {mem_space = [@CMX_NN, 0]}>
        DataInfo "weightsTable" : tensor<48x1x1x4xsi32, {mem_space = [@CMX_NN, 0]}>
        DataInfo "filterCons" : tensor<144x16x1x1xf16, {mem_space = [@CMX_NN, 0]}>
        DataInfo "weightsTableCons" : tensor<144x1x1x4xsi32, {mem_space = [@CMX_NN, 0]}>
    }
    outputsInfo : {
        DataInfo "prob1" : tensor<1x144x16x32xf16>
        DataInfo "prob2" : tensor<1x144x16x32xf16>
    }

func.func @main(%input: tensor<1x144x32x32xf16, {order = #NHWC}>,
           %filter: tensor<48x16x1x1xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>,
           %weightsTable: tensor<48x1x1x4xsi32, {mem_space = [@CMX_NN, 0], order = #NCHW}>,
           %filterCons: tensor<144x16x1x1xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>,
           %weightsTableCons: tensor<144x1x1x4xsi32, {mem_space = [@CMX_NN, 0], order = #NCHW}>)
           -> (tensor<1x144x16x32xf16, {order = #NHWC}>, tensor<1x144x16x32xf16, {order = #NHWC}>) {

    // Create a concat subgraph with three input tiles and two output users

    // Concat input tile 1
    %0 = VPU.Slice %input [0, 0, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>
    %1 = VPU.Copy(%0) {out_mem_space = [@CMX_NN, 0]} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %2 = VPU.NCE.DepthConvolution(%1, %filter, %weightsTable)
        {opaque_ppe = #VPU.PPEStub<>,
        pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
        post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
        rawFilterShape = [48, 1, 3, 3],
        strides = [1, 1]}
        -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    // NCE copy-out to concatinate in DDR
    %3 = VPU.Copy(%2) : tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>

    // Concat input tile 2
    %4 = VPU.Slice %input [0, 48, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>
    %5 = VPU.Copy(%4) {out_mem_space = [@CMX_NN, 0]} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %6 = VPU.NCE.DepthConvolution(%5, %filter, %weightsTable)
        {opaque_ppe = #VPU.PPEStub<>,
        pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
        post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
        rawFilterShape = [48, 1, 3, 3],
        strides = [1, 1]}
        -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    // NCE copy-out to concatinate in DDR
    %7 = VPU.Copy(%6) : tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>

    // Concat input tile 3
    %8 = VPU.Slice %input [0, 96, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>
    %9 = VPU.Copy(%8) {out_mem_space = [@CMX_NN, 0]} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %10 = VPU.NCE.DepthConvolution(%9, %filter, %weightsTable)
        {opaque_ppe = #VPU.PPEStub<>,
        pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
        post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>, rawFilterShape = [48, 1, 3, 3],
        strides = [1, 1]}
        -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    // NCE copy-out to concatinate in DDR
    %11 = VPU.Copy(%10) : tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>

    // Concat inputs are in DDR and Concat output is in DDR
    %12 = VPU.Concat(%3, %7, %11) {static_offsets = [[0, 0, 0, 0], [0, 48, 0, 0], [0, 96, 0, 0]]} : tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x144x32x32xf16, {order = #NHWC}>

    %13 = VPU.Slice %12 [0, 0, 0, 0] [1, 144, 16, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x144x16x32xf16, {order = #NHWC}>
    // Concat slice result copy-in for NCE user
    %14 = VPU.Copy(%13) {out_mem_space = [@CMX_NN, 0]} : tensor<1x144x16x32xf16, {order = #NHWC}> -> tensor<1x144x16x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    %15 = VPU.NCE.DepthConvolution(%14, %filterCons, %weightsTableCons) {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>, post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>, rawFilterShape = [144, 1, 3, 3], strides = [1, 1]} -> tensor<1x144x16x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    %16 = VPU.Copy(%15) : tensor<1x144x16x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x144x16x32xf16, {order = #NHWC}>

    %17 = VPU.Slice %12 [0, 144, 0, 0] [1, 144, 16, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x144x16x32xf16, {order = #NHWC}>
    // Concat slice result copy-in for NCE user
    %18 = VPU.Copy(%17) {out_mem_space = [@CMX_NN, 0]} : tensor<1x144x16x32xf16, {order = #NHWC}> -> tensor<1x144x16x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    %19 = VPU.NCE.DepthConvolution(%18, %filterCons, %weightsTableCons) {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>, post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>, rawFilterShape = [144, 1, 3, 3], strides = [1, 1]} -> tensor<1x144x16x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    %20 = VPU.Copy(%19) : tensor<1x144x16x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x144x16x32xf16, {order = #NHWC}>

    return %16, %20 : tensor<1x144x16x32xf16, {order = #NHWC}>, tensor<1x144x16x32xf16, {order = #NHWC}>

    // the below checks that the concat is occuring in NNCMX and the copy operations
    // arround the concat are not used by the concat producer and consumer operations

    // input to the first tile copy-in (DDR->NNCMX) for weights
    // CHECK:       [[VAL0:%.+]] = VPU.Slice %arg0
    // CHECK-SAME:      [0, 0, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>
    // CHECK:       [[VAL1:%.+]] = VPU.Copy([[VAL0]])

    // first tile of NCE task
    // CHECK:       [[VAL2:%.+]] = VPU.NCE.DepthConvolution([[VAL1]], %arg1, %arg2)

    // no copy-out to concatinate in DDR
    // CHECK-NOT:   VPU.Copy

    // input to the second tile copy-in (DDR->NNCMX) for weights
    // CHECK:       [[VAL3:%.+]] = VPU.Slice %arg0
    // CHECK-SAME:      [0, 48, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>
    // CHECK:       [[VAL4:%.+]] = VPU.Copy([[VAL3]])

    // second tile of NCE task
    // CHECK:       [[VAL5:%.+]] = VPU.NCE.DepthConvolution([[VAL4]], %arg1, %arg2)

    // no copy-out to concatinate in DDR
    // CHECK-NOT:   VPU.Copy

    // input to the third tile copy-in (DDR->NNCMX) for weights
    // CHECK:       [[VAL6:%.+]] = VPU.Slice %arg0
    // CHECK-SAME:      [0, 96, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>
    // CHECK:       [[VAL7:%.+]] = VPU.Copy([[VAL6]])

    // third tile of NCE task
    // CHECK:       [[VAL8:%.+]] = VPU.NCE.DepthConvolution([[VAL7]], %arg1, %arg2)

    // no copy-out to concatinate in DDR
    // CHECK-NOT:   VPU.Copy

    // no copy-out (NNCMX->DDR) operations to concatinate in DDR
    // Concat in NNCMX using results of NCE tiles in NNCMX
    // CHECK:       [[VAL9:%.+]] = VPU.Concat([[VAL2]], [[VAL5]], [[VAL8]])

    // no Concat buffer copy-in to NNCMX
    // CHECK-NOT:   VPU.Copy

    // users of concat which use part of the master buffer through slices
    // concat partial buffer user slicing output of concat in NNCMX
    // CHECK:       [[VAL10:%.+]] = VPU.Slice [[VAL9]]
    // CHECK-SAME:      [0, 0, 0, 0] [1, 144, 16, 32] : tensor<1x144x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> to tensor<1x144x16x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    // no Concat buffer slice copy-in to NNCMX
    // CHECK-NOT:   VPU.Copy

    // concat user reading from NNCMX slice without intermediate copy operation
    // CHECK:       [[VAL11:%.+]] = VPU.NCE.DepthConvolution([[VAL10]], %arg3, %arg4)
    // copy-out
    // CHECK:       [[VAL12:%.+]] = VPU.Copy([[VAL11]])

    // user of second part of concat master buffer
    // CHECK:       [[VAL13:%.+]] = VPU.Slice [[VAL9]]
    // CHECK-SAME:      [0, 144, 0, 0] [1, 144, 16, 32] : tensor<1x144x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> to tensor<1x144x16x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    // no Concat buffer slice copy-in to NNCMX
    // CHECK-NOT:   VPU.Copy

    // user reading from NNCMX without intermediate copy operation
    // CHECK:       [[VAL14:%.+]] = VPU.NCE.DepthConvolution([[VAL13]], %arg3, %arg4)
    // copy-out
    // CHECK:       [[VAL15:%.+]] = VPU.Copy([[VAL14]])

    // CHECK:       return [[VAL12:%.+]], [[VAL15:%.+]] : tensor<1x144x16x32xf16, {order = #NHWC}>, tensor<1x144x16x32xf16, {order = #NHWC}>
}

}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!Distributed = !VPU.DistributedTensor<
    1x144x32x32xf16, #NHWC, @CMX_NN, {
   mode = "DUPLICATED",
    num_clusters = 4
}>

!DistributedTile = !VPU.DistributedTensor<
    1x48x32x32xf16, #NHWC, @CMX_NN, {
   mode = "DUPLICATED",
    num_clusters = 4
}>

!DistributedTileOutput = !VPU.DistributedTensor<
    1x48x32x32xf16, #NHWC, @CMX_NN, {
   mode = "DUPLICATED|SEGMENTED",
    num_tiles = [1, 4, 1, 1],
    num_clusters = 4
}>

module @CaseWithNceClusterTilingWithoutChildTiling {

IE.CNNNetwork
    entryPoint : @main
    inputsInfo : {
        DataInfo "input" : tensor<1x144x32x32xf16>
        DataInfo "filter" : tensor<48x16x1x1xf16, {mem_space = @CMX_NN}>
        DataInfo "weightsTable" : tensor<48x1x1x4xsi32, {mem_space = @CMX_NN}>
        DataInfo "maxPoolWeightsTable" : tensor<144x1x1x4xsi32, {mem_space = @CMX_NN}>
    }
    outputsInfo : {
        DataInfo "prob" : tensor<1x144x32x32xf16>
    }

func.func @main(%input: tensor<1x144x32x32xf16, {order = #NHWC}>,
           %filter: tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
           %weightsTable: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
           %maxPoolWeightsTable: tensor<144x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
           -> tensor<1x144x32x32xf16, {order = #NHWC}> {

    // Create a concat subgraph with three input tiles and one output user

    // Concat input tile 1
    %0 = VPU.Slice %input [0, 0, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>

    %1 = VPU.NCE.ClusterTiling (%0 as %arg0: tensor<1x48x32x32xf16, {order = #NHWC}>) -> !DistributedTile {
        %16 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %2 = VPU.NCE.ClusterTiling (%1 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter as %arg1: tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg2: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !DistributedTileOutput {
        %16 = VPU.NCE.DepthConvolution(%arg0, %arg1, %arg2)
            {opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
            rawFilterShape = [48, 1, 3, 3],
            strides = [1, 1]}
            -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %3 = VPU.NCE.ClusterTiling (%2 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x48x32x32xf16, {order = #NHWC}> {
        %16 = VPU.Copy(%arg0) : tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>
        VPU.Yield %16
    }

    // Concat input tile 2
    %4 = VPU.Slice %input [0, 48, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>

    %5 = VPU.NCE.ClusterTiling (%4 as %arg0: tensor<1x48x32x32xf16, {order = #NHWC}>) -> !DistributedTile {
        %16 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %6 = VPU.NCE.ClusterTiling (
        %5 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter as %arg1: tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg2: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !DistributedTileOutput {
        %16 = VPU.NCE.DepthConvolution(%arg0, %arg1, %arg2)
            {opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
            rawFilterShape = [48, 1, 3, 3],
            strides = [1, 1]}
            -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %7 = VPU.NCE.ClusterTiling (%6 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x48x32x32xf16, {order = #NHWC}> {
        %16 = VPU.Copy(%arg0) : tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>
        VPU.Yield %16
    }

    // Concat input tile 3
    %8 = VPU.Slice %input [0, 96, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>

    %9 = VPU.NCE.ClusterTiling (%8 as %arg0: tensor<1x48x32x32xf16, {order = #NHWC}>) -> !DistributedTile {
        %16 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %10 = VPU.NCE.ClusterTiling (
        %9 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter as %arg1: tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg2: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !DistributedTileOutput {
        %16 = VPU.NCE.DepthConvolution(%arg0, %arg1, %arg2)
            {opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>, rawFilterShape = [48, 1, 3, 3],
            strides = [1, 1]}
            -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %11 = VPU.NCE.ClusterTiling (%10 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x48x32x32xf16, {order = #NHWC}> {
        %16 = VPU.Copy(%arg0) : tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>
        VPU.Yield %16
    }

    %12 = VPU.Concat(%3, %7, %11) {static_offsets = [[0, 0, 0, 0], [0, 48, 0, 0], [0, 96, 0, 0]]} : tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x144x32x32xf16, {order = #NHWC}>

    %13 = VPU.NCE.ClusterTiling (%12 as %arg0: tensor<1x144x32x32xf16, {order = #NHWC}>) -> !Distributed {
        %16 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x144x32x32xf16, {order = #NHWC}> -> tensor<1x144x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %14 = VPU.NCE.ClusterTiling (
        %13 as %arg0: tensor<1x144x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %maxPoolWeightsTable as %arg1: tensor<144x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !Distributed {
        %16 = VPU.NCE.MaxPool(%arg0, %arg1) {
                opaque_ppe = #VPU.PPEStub<>,
                pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
                strides = [1, 1],
                kernel_size = [1, 1]
            } -> tensor<1x144x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %15 = VPU.NCE.ClusterTiling (%14 as %arg0: tensor<1x144x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x144x32x32xf16, {order = #NHWC}> {
        %16 = VPU.Copy(%arg0) : tensor<1x144x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x144x32x32xf16, {order = #NHWC}>
        VPU.Yield %16
    }

    return %15 : tensor<1x144x32x32xf16, {order = #NHWC}>

}
}

// CHECK-LABEL: @CaseWithNceClusterTilingWithoutChildTiling

// Tile 0
// CHECK:       [[SLICE0:%.+]] = VPU.Slice %arg0 [0, 0, 0, 0] [1, 48, 32, 32]

// CHECK:       [[COPY0:%.+]]  = VPU.NCE.ClusterTiling ([[SLICE0]] as %arg4: tensor<1x48x32x32xf16, {order = #NHWC}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>
// CHECK:           [[COPY0_INNER:%.+]] = VPU.Copy(%arg4) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}>
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[NCE0:%.+]]   = VPU.NCE.ClusterTiling ([[COPY0]] as %arg4: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:          -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>
// CHECK:           [[NCE0_INNER:%.+]] = VPU.NCE.DepthConvolution(%arg4, %arg5, %arg6)
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// Tile 1
// CHECK:       [[SLICE1:%.+]] = VPU.Slice %arg0 [0, 48, 0, 0] [1, 48, 32, 32]

// CHECK:       [[COPY1:%.+]]  = VPU.NCE.ClusterTiling ([[SLICE1]] as %arg4: tensor<1x48x32x32xf16, {order = #NHWC}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>
// CHECK:           [[COPY1_INNER:%.+]] = VPU.Copy(%arg4) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}>
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[NCE1:%.+]]   = VPU.NCE.ClusterTiling ([[COPY1]] as %arg4: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:          -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>
// CHECK:           [[NCE1_INNER:%.+]] = VPU.NCE.DepthConvolution(%arg4, %arg5, %arg6)
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// Tile 2
// CHECK:       [[SLICE2:%.+]] = VPU.Slice %arg0 [0, 96, 0, 0] [1, 48, 32, 32]

// CHECK:       [[COPY2:%.+]]  = VPU.NCE.ClusterTiling ([[SLICE2]] as %arg4: tensor<1x48x32x32xf16, {order = #NHWC}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>
// CHECK:           [[COPY2_INNER:%.+]] = VPU.Copy(%arg4) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}>
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[NCE2:%.+]]   = VPU.NCE.ClusterTiling ([[COPY2]] as %arg4: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:          -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>
// CHECK:           [[NCE1_INNER:%.+]] = VPU.NCE.DepthConvolution(%arg4, %arg5, %arg6)
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[CAST0:%.+]] = VPU.DistributedCast([[NCE0]] :
// CHECK-SAME:      !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>
// CHECK-SAME:          -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>

// CHECK:       [[CAST1:%.+]] = VPU.DistributedCast([[NCE1]] :
// CHECK-SAME:      !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>
// CHECK-SAME:          -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>

// CHECK:       [[CAST2:%.+]] = VPU.DistributedCast([[NCE2]] :
// CHECK-SAME:      !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>
// CHECK-SAME:          -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>

// Concat
// CHECK:       [[CONCAT:%.+]] = VPU.Concat([[CAST0]], [[CAST1]], [[CAST2]])
// CHECK-SAME:      !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>
// CHECK-SAME:      !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>
// CHECK-SAME:      !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>
// CHECK-SAME:          -> !VPU.DistributedTensor<1x144x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>

// CHECK:       [[MAXPOOL:%.+]] = VPU.NCE.ClusterTiling
// CHECK-SAME:      [[CONCAT]] as %arg4: tensor<1x144x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
// CHECK-SAME:          -> !VPU.DistributedTensor<1x144x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>
// CHECK:           [[MAXPOOL_INNER:%.+]] = VPU.NCE.MaxPool(%arg4, %arg5 )
// CHECK-SAME:          kernel_size = [1, 1],
// CHECK-SAME:          opaque_ppe = #VPU.PPEStub<>,
// CHECK-SAME:          pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, strides = [1, 1]
// CHECK-SAME:              -> tensor<1x144x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}

// CHECK:       [[COPY_OUT:%.+]] = VPU.NCE.ClusterTiling
// CHECK-SAME:      ([[MAXPOOL]] as %arg4: tensor<1x144x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>)
// CHECK-SAME:          -> tensor<1x144x32x32xf16, {order = #NHWC}>
// CHECK:           [[COPY_OUT_INNER:%.+]] = VPU.Copy(%arg4)
// CHECK-SAME:          : tensor<1x144x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:              -> tensor<1x144x32x32xf16, {order = #NHWC}>

// CHECK:       return [[COPY_OUT]] : tensor<1x144x32x32xf16, {order = #NHWC}>

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!Distributed = !VPU.DistributedTensor<
    1x144x16x32xf16, #NHWC, @CMX_NN, {
   mode = "DUPLICATED",
    num_clusters = 4
}>

!DistributedTile = !VPU.DistributedTensor<
    1x48x32x32xf16, #NHWC, @CMX_NN, {
   mode = "DUPLICATED",
    num_clusters = 4
}>

!DistributedTileOutput = !VPU.DistributedTensor<
    1x48x32x32xf16, #NHWC, @CMX_NN, {
   mode = "DUPLICATED|SEGMENTED",
    num_tiles = [1, 4, 1, 1],
    num_clusters = 4
}>

module @CaseWithNceClusterTilingWithChildTiling {

IE.CNNNetwork
    entryPoint : @main
    inputsInfo : {
        DataInfo "input" : tensor<1x144x32x32xf16>
        DataInfo "filter" : tensor<48x16x1x1xf16, {mem_space = @CMX_NN}>
        DataInfo "weightsTable" : tensor<48x1x1x4xsi32, {mem_space = @CMX_NN}>
        DataInfo "maxPoolWeightsTable" : tensor<144x1x1x4xsi32, {mem_space = @CMX_NN}>
    }
    outputsInfo : {
        DataInfo "prob1" : tensor<1x144x16x32xf16>
        DataInfo "prob2" : tensor<1x144x16x32xf16>
    }

func.func @main(%input: tensor<1x144x32x32xf16, {order = #NHWC}>,
           %filter: tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
           %weightsTable: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
           %maxPoolWeightsTable: tensor<144x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
           -> (tensor<1x144x16x32xf16, {order = #NHWC}>, tensor<1x144x16x32xf16, {order = #NHWC}>) {

    // Create a concat subgraph with three input tiles and two output users

    // Concat input tile 1
    %0 = VPU.Slice %input [0, 0, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>

    %1 = VPU.NCE.ClusterTiling (%0 as %arg0: tensor<1x48x32x32xf16, {order = #NHWC}>) -> !DistributedTile {
        %21 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }

    %2 = VPU.NCE.ClusterTiling (%1 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter as %arg1: tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg2: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !DistributedTileOutput {
        %21 = VPU.NCE.DepthConvolution(%arg0, %arg1, %arg2)
            {opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
            rawFilterShape = [48, 1, 3, 3],
            strides = [1, 1]}
            -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }

    %3 = VPU.NCE.ClusterTiling (%2 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x48x32x32xf16, {order = #NHWC}> {
        %21 = VPU.Copy(%arg0) : tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>
        VPU.Yield %21
    }

    // Concat input tile 2
    %4 = VPU.Slice %input [0, 48, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>

    %5 = VPU.NCE.ClusterTiling (%4 as %arg0: tensor<1x48x32x32xf16, {order = #NHWC}>) -> !DistributedTile {
        %21 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }

    %6 = VPU.NCE.ClusterTiling (
        %5 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter as %arg1: tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg2: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !DistributedTileOutput {
        %21 = VPU.NCE.DepthConvolution(%arg0, %arg1, %arg2)
            {opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
            rawFilterShape = [48, 1, 3, 3],
            strides = [1, 1]}
            -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }

    %7 = VPU.NCE.ClusterTiling (%6 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x48x32x32xf16, {order = #NHWC}> {
        %21 = VPU.Copy(%arg0) : tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>
        VPU.Yield %21
    }

    // Concat input tile 3
    %8 = VPU.Slice %input [0, 96, 0, 0] [1, 48, 32, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>

    %9 = VPU.NCE.ClusterTiling (%8 as %arg0: tensor<1x48x32x32xf16, {order = #NHWC}>) -> !DistributedTile {
        %21 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }

    %10 = VPU.NCE.ClusterTiling (
        %9 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter as %arg1: tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg2: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !DistributedTileOutput {
        %21 = VPU.NCE.DepthConvolution(%arg0, %arg1, %arg2)
            {opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>, rawFilterShape = [48, 1, 3, 3],
            strides = [1, 1]}
            -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }

    %11 = VPU.NCE.ClusterTiling (%10 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x48x32x32xf16, {order = #NHWC}> {
        %21 = VPU.Copy(%arg0) : tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>
        VPU.Yield %21
    }

    %12 = VPU.Concat(%3, %7, %11) {static_offsets = [[0, 0, 0, 0], [0, 48, 0, 0], [0, 96, 0, 0]]} : tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x144x32x32xf16, {order = #NHWC}>

    // Output branch 1
    %13 = VPU.Slice %12 [0, 0, 0, 0] [1, 144, 16, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x144x16x32xf16, {order = #NHWC}>
    %14 = VPU.NCE.ClusterTiling (%13 as %arg0: tensor<1x144x16x32xf16, {order = #NHWC}>) -> !Distributed {
        %21 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x144x16x32xf16, {order = #NHWC}> -> tensor<1x144x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }

    %15 = VPU.NCE.ClusterTiling (
        %14 as %arg0: tensor<1x144x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %maxPoolWeightsTable as %arg1: tensor<144x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !Distributed {
        %21 = VPU.NCE.MaxPool(%arg0, %arg1) {
                opaque_ppe = #VPU.PPEStub<>,
                pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
                strides = [1, 1],
                kernel_size = [1, 1]
            } -> tensor<1x144x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }

    %16 = VPU.NCE.ClusterTiling (%15 as %arg0: tensor<1x144x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x144x16x32xf16, {order = #NHWC}> {
        %21 = VPU.Copy(%arg0) : tensor<1x144x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x144x16x32xf16, {order = #NHWC}>
        VPU.Yield %21
    }

    // Output branch 2
    %17 = VPU.Slice %12 [0, 0, 16, 0] [1, 144, 16, 32] : tensor<1x144x32x32xf16, {order = #NHWC}> to tensor<1x144x16x32xf16, {order = #NHWC}>
    %18 = VPU.NCE.ClusterTiling (%17 as %arg0: tensor<1x144x16x32xf16, {order = #NHWC}>) -> !Distributed {
        %21 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x144x16x32xf16, {order = #NHWC}> -> tensor<1x144x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }

    %19 = VPU.NCE.ClusterTiling (
        %18 as %arg0: tensor<1x144x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %maxPoolWeightsTable as %arg1: tensor<144x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !Distributed {
        %21 = VPU.NCE.MaxPool(%arg0, %arg1) {
                opaque_ppe = #VPU.PPEStub<>,
                pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
                strides = [1, 1],
                kernel_size = [1, 1]
            } -> tensor<1x144x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }

    %20 = VPU.NCE.ClusterTiling (%19 as %arg0: tensor<1x144x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x144x16x32xf16, {order = #NHWC}> {
        %21 = VPU.Copy(%arg0) : tensor<1x144x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x144x16x32xf16, {order = #NHWC}>
        VPU.Yield %21
    }

    return %16, %20 : tensor<1x144x16x32xf16, {order = #NHWC}>, tensor<1x144x16x32xf16, {order = #NHWC}>

}
}

// CHECK-LABEL: @CaseWithNceClusterTilingWithChildTiling

// Tile 0
// CHECK:       [[SLICE0:%.+]] = VPU.Slice %arg0 [0, 0, 0, 0] [1, 48, 32, 32]

// CHECK:       [[COPY0:%.+]]  = VPU.NCE.ClusterTiling ([[SLICE0]] as %arg4: tensor<1x48x32x32xf16, {order = #NHWC}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>
// CHECK:           [[COPY0_INNER:%.+]] = VPU.Copy(%arg4) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}>
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[NCE0:%.+]]   = VPU.NCE.ClusterTiling ([[COPY0]] as %arg4: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:          -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>
// CHECK:           [[NCE0_INNER:%.+]] = VPU.NCE.DepthConvolution(%arg4, %arg5, %arg6)
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// Tile 1
// CHECK:       [[SLICE1:%.+]] = VPU.Slice %arg0 [0, 48, 0, 0] [1, 48, 32, 32]

// CHECK:       [[COPY1:%.+]]  = VPU.NCE.ClusterTiling ([[SLICE1]] as %arg4: tensor<1x48x32x32xf16, {order = #NHWC}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>
// CHECK:           [[COPY1_INNER:%.+]] = VPU.Copy(%arg4) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}>
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[NCE1:%.+]]   = VPU.NCE.ClusterTiling ([[COPY1]] as %arg4: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:          -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>
// CHECK:           [[NCE1_INNER:%.+]] = VPU.NCE.DepthConvolution(%arg4, %arg5, %arg6)
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// Tile 2
// CHECK:       [[SLICE2:%.+]] = VPU.Slice %arg0 [0, 96, 0, 0] [1, 48, 32, 32]

// CHECK:       [[COPY2:%.+]]  = VPU.NCE.ClusterTiling ([[SLICE2]] as %arg4: tensor<1x48x32x32xf16, {order = #NHWC}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>
// CHECK:           [[COPY2_INNER:%.+]] = VPU.Copy(%arg4) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}>
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[NCE2:%.+]]   = VPU.NCE.ClusterTiling ([[COPY2]] as %arg4: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:          -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>
// CHECK:           [[NCE1_INNER:%.+]] = VPU.NCE.DepthConvolution(%arg4, %arg5, %arg6)
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// DistributedCast ops to cast inputs to the child's distribution modes
// CHECK:       [[DIST_CAST0:%.+]] = VPU.DistributedCast([[NCE0]]
// CHECK-SAME:      !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>)
// CHECK-SAME:          -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>

// CHECK:       [[DIST_CAST1:%.+]] = VPU.DistributedCast([[NCE1]]
// CHECK-SAME:      !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>)
// CHECK-SAME:          -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>

// CHECK:       [[DIST_CAST2:%.+]] = VPU.DistributedCast([[NCE2]]
// CHECK-SAME:      !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>)
// CHECK-SAME:          -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>

// Concat is CMX-ed
// CHECK:       [[CONCAT:%.+]] = VPU.Concat([[DIST_CAST0]], [[DIST_CAST1]], [[DIST_CAST2]])
// CHECK-SAME:      !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>,
// CHECK-SAME:          -> !VPU.DistributedTensor<1x144x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>

// Output Tile 0
// CHECK:       [[OUTSLICE0:%.+]] = VPU.Slice [[CONCAT]] [0, 0, 0, 0] [1, 144, 16, 32]

// CHECK:       [[MAXPOOL0:%.+]] = VPU.NCE.ClusterTiling
// CHECK-SAME:      ([[OUTSLICE0]] as %arg4: tensor<1x144x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK:           [[MAXPOOL0_INNER:%.+]] = VPU.NCE.MaxPool(%arg4, %arg5 )

// CHECK:       [[OUTCOPY0_OUT:%.+]] = VPU.NCE.ClusterTiling
// CHECK-SAME:      ([[MAXPOOL0]] as %arg4: tensor<1x144x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>)
// CHECK:           [[OUTCOPY0_OUT_INNER:%.+]] = VPU.Copy(%arg4)

// Output Tile 1
// CHECK:       [[OUTSLICE1:%.+]] = VPU.Slice [[CONCAT]] [0, 0, 16, 0] [1, 144, 16, 32]

// CHECK:       [[MAXPOOL1:%.+]] = VPU.NCE.ClusterTiling
// CHECK-SAME:      ([[OUTSLICE1]] as %arg4: tensor<1x144x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK:           [[MAXPOOL1_INNER:%.+]] = VPU.NCE.MaxPool(%arg4, %arg5 )

// CHECK:       [[OUTCOPY1_OUT:%.+]] = VPU.NCE.ClusterTiling
// CHECK-SAME:      ([[MAXPOOL1]] as %arg4: tensor<1x144x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>)
// CHECK:           [[OUTCOPY1_OUT_INNER:%.+]] = VPU.Copy(%arg4)

// CHECK:       return [[OUTCOPY0_OUT]], [[OUTCOPY1_OUT]]
// CHECK-SAME:      : tensor<1x144x16x32xf16, {order = #NHWC}>, tensor<1x144x16x32xf16, {order = #NHWC}>

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!Distributed = !VPU.DistributedTensor<
    1x48x16x32xf16, #NHWC, @CMX_NN, {
   mode = "DUPLICATED",
    num_clusters = 4
}>

!DistributedTile = !VPU.DistributedTensor<
    1x16x32x32xf16, #NHWC, @CMX_NN, {
   mode = "DUPLICATED",
    num_clusters = 4
}>

!DistributedTileOutput = !VPU.DistributedTensor<
    1x16x32x32xf16, #NHWC, @CMX_NN, {
   mode = "DUPLICATED|SEGMENTED",
    num_tiles = [1, 4, 1, 1],
    num_clusters = 4
}>

module @CaseWithEltwiseNceClusterTilingWithChildTiling {

IE.CNNNetwork
    entryPoint : @main
    inputsInfo : {
        DataInfo "input" : tensor<1x48x32x32xf16>
        DataInfo "filter" : tensor<16x16x1x1xf16, {mem_space = @CMX_NN}>
        DataInfo "weightsTable" : tensor<16x1x1x4xsi32, {mem_space = @CMX_NN}>
        DataInfo "maxPoolWeightsTable" : tensor<48x1x1x4xsi32, {mem_space = @CMX_NN}>
    }
    outputsInfo : {
        DataInfo "prob1" : tensor<1x48x16x32xf16>
    }

func.func @main(%input: tensor<1x48x32x32xf16, {order = #NHWC}>,
           %filter: tensor<16x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
           %weightsTable: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
           %maxPoolWeightsTable: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
           -> tensor<1x48x16x32xf16, {order = #NHWC}> {

    // Create a concat subgraph with three input tiles and two output users

    // Concat input tile 1
    %0 = VPU.Slice %input [0, 0, 0, 0] [1, 16, 32, 32] : tensor<1x48x32x32xf16, {order = #NHWC}> to tensor<1x16x32x32xf16, {order = #NHWC}>

    %1 = VPU.NCE.ClusterTiling (%0 as %arg0: tensor<1x16x32x32xf16, {order = #NHWC}>) -> !DistributedTile {
        %19 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x16x32x32xf16, {order = #NHWC}> -> tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %19
    }

    %2 = VPU.NCE.ClusterTiling (%1 as %arg0: tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter as %arg1: tensor<16x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg2: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !DistributedTileOutput {
        %19 = VPU.NCE.DepthConvolution(%arg0, %arg1, %arg2)
            {opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
            rawFilterShape = [16, 1, 3, 3],
            strides = [1, 1]}
            -> tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %19
    }

    %3 = VPU.NCE.ClusterTiling (%2 as %arg0: tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x16x32x32xf16, {order = #NHWC}> {
        %19 = VPU.Copy(%arg0) : tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x16x32x32xf16, {order = #NHWC}>
        VPU.Yield %19
    }

    // Concat input tile 2
    %4 = VPU.Slice %input [0, 16, 0, 0] [1, 16, 32, 32] : tensor<1x48x32x32xf16, {order = #NHWC}> to tensor<1x16x32x32xf16, {order = #NHWC}>

    %5 = VPU.NCE.ClusterTiling (%4 as %arg0: tensor<1x16x32x32xf16, {order = #NHWC}>) -> !DistributedTile {
        %19 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x16x32x32xf16, {order = #NHWC}> -> tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %19
    }

    %6 = VPU.NCE.ClusterTiling (
        %5 as %arg0: tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter as %arg1: tensor<16x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg2: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !DistributedTileOutput {
        %19 = VPU.NCE.DepthConvolution(%arg0, %arg1, %arg2)
            {opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
            rawFilterShape = [16, 1, 3, 3],
            strides = [1, 1]}
            -> tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %19
    }

    %7 = VPU.NCE.ClusterTiling (%6 as %arg0: tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x16x32x32xf16, {order = #NHWC}> {
        %19 = VPU.Copy(%arg0) : tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x16x32x32xf16, {order = #NHWC}>
        VPU.Yield %19
    }

    // Concat input tile 3
    %8 = VPU.Slice %input [0, 96, 0, 0] [1, 16, 32, 32] : tensor<1x48x32x32xf16, {order = #NHWC}> to tensor<1x16x32x32xf16, {order = #NHWC}>

    %9 = VPU.NCE.ClusterTiling (%8 as %arg0: tensor<1x16x32x32xf16, {order = #NHWC}>) -> !DistributedTile {
        %19 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x16x32x32xf16, {order = #NHWC}> -> tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %19
    }

    %10 = VPU.NCE.ClusterTiling (
        %9 as %arg0: tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter as %arg1: tensor<16x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg2: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !DistributedTileOutput {
        %19 = VPU.NCE.DepthConvolution(%arg0, %arg1, %arg2)
            {opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>, rawFilterShape = [16, 1, 3, 3],
            strides = [1, 1]}
            -> tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %19
    }

    %11 = VPU.NCE.ClusterTiling (%10 as %arg0: tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x16x32x32xf16, {order = #NHWC}> {
        %19 = VPU.Copy(%arg0) : tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x16x32x32xf16, {order = #NHWC}>
        VPU.Yield %19
    }

    %12 = VPU.Concat(%3, %7, %11) {static_offsets = [[0, 0, 0, 0], [0, 16, 0, 0], [0, 32, 0, 0]]} : tensor<1x16x32x32xf16, {order = #NHWC}>, tensor<1x16x32x32xf16, {order = #NHWC}>, tensor<1x16x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>

    // Output branch 1
    %13 = VPU.Slice %12 [0, 0, 0, 0] [1, 48, 16, 32] : tensor<1x48x32x32xf16, {order = #NHWC}> to tensor<1x48x16x32xf16, {order = #NHWC}>
    %14 = VPU.NCE.ClusterTiling (%13 as %arg0: tensor<1x48x16x32xf16, {order = #NHWC}>) -> !Distributed {
        %19 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x48x16x32xf16, {order = #NHWC}> -> tensor<1x48x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %19
    }

    // Output branch 2
    %15 = VPU.Slice %12 [0, 0, 16, 0] [1, 48, 16, 32] : tensor<1x48x32x32xf16, {order = #NHWC}> to tensor<1x48x16x32xf16, {order = #NHWC}>
    %16 = VPU.NCE.ClusterTiling (%15 as %arg0: tensor<1x48x16x32xf16, {order = #NHWC}>) -> !Distributed {
        %19 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x48x16x32xf16, {order = #NHWC}> -> tensor<1x48x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %19
    }

    %17 = VPU.NCE.ClusterTiling (
        %14 as %arg0: tensor<1x48x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %16 as %arg1: tensor<1x48x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>)
            -> !Distributed {
        %19 = VPU.NCE.Eltwise(%arg0, %arg1) {
            op_type = #VPU.eltwise_type<ADD>, opaque_ppe = #VPU.PPEStub<>
        } -> tensor<1x48x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %19
    }
    %18 = VPU.NCE.ClusterTiling (%17 as %arg0: tensor<1x48x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x48x16x32xf16, {order = #NHWC}> {
        %19 = VPU.Copy(%arg0) : tensor<1x48x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x48x16x32xf16, {order = #NHWC}>
        VPU.Yield %19
    }
    return %18 : tensor<1x48x16x32xf16, {order = #NHWC}>

}
}

// CHECK-LABEL: @CaseWithEltwiseNceClusterTilingWithChildTiling

// Tile 0
// CHECK:       [[SLICE0:%.+]] = VPU.Slice %arg0 [0, 0, 0, 0] [1, 16, 32, 32]

// CHECK:       [[COPY0:%.+]]  = VPU.NCE.ClusterTiling ([[SLICE0]] as %arg4: tensor<1x16x32x32xf16, {order = #NHWC}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x16x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>
// CHECK:           [[COPY0_INNER:%.+]] = VPU.Copy(%arg4) {out_mem_space = @CMX_NN} : tensor<1x16x32x32xf16, {order = #NHWC}>
// CHECK-SAME:              -> tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[NCE0:%.+]]   = VPU.NCE.ClusterTiling ([[COPY0]] as %arg4: tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:          -> !VPU.DistributedTensor<1x16x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>
// CHECK:           [[NCE0_INNER:%.+]] = VPU.NCE.DepthConvolution(%arg4, %arg5, %arg6)
// CHECK-SAME:              -> tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// Tile 1
// CHECK:       [[SLICE1:%.+]] = VPU.Slice %arg0 [0, 16, 0, 0] [1, 16, 32, 32]

// CHECK:       [[COPY1:%.+]]  = VPU.NCE.ClusterTiling ([[SLICE1]] as %arg4: tensor<1x16x32x32xf16, {order = #NHWC}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x16x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>
// CHECK:           [[COPY1_INNER:%.+]] = VPU.Copy(%arg4) {out_mem_space = @CMX_NN} : tensor<1x16x32x32xf16, {order = #NHWC}>
// CHECK-SAME:              -> tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[NCE1:%.+]]   = VPU.NCE.ClusterTiling ([[COPY1]] as %arg4: tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:          -> !VPU.DistributedTensor<1x16x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>
// CHECK:           [[NCE1_INNER:%.+]] = VPU.NCE.DepthConvolution(%arg4, %arg5, %arg6)
// CHECK-SAME:              -> tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// Tile 2
// CHECK:       [[SLICE2:%.+]] = VPU.Slice %arg0 [0, 96, 0, 0] [1, 16, 32, 32]

// CHECK:       [[COPY2:%.+]]  = VPU.NCE.ClusterTiling ([[SLICE2]] as %arg4: tensor<1x16x32x32xf16, {order = #NHWC}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x16x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>
// CHECK:           [[COPY2_INNER:%.+]] = VPU.Copy(%arg4) {out_mem_space = @CMX_NN} : tensor<1x16x32x32xf16, {order = #NHWC}>
// CHECK-SAME:              -> tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[NCE2:%.+]]   = VPU.NCE.ClusterTiling ([[COPY2]] as %arg4: tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:          -> !VPU.DistributedTensor<1x16x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>
// CHECK:           [[NCE1_INNER:%.+]] = VPU.NCE.DepthConvolution(%arg4, %arg5, %arg6)
// CHECK-SAME:              -> tensor<1x16x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// DistributedCast to cast the distribution mode
// CHECK:       [[DIST_CAST0:%.+]] = VPU.DistributedCast([[NCE0]]
// CHECK-SAME:      !VPU.DistributedTensor<1x16x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>)
// CHECK-SAME:          -> !VPU.DistributedTensor<1x16x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>

// CHECK:       [[DIST_CAST1:%.+]] = VPU.DistributedCast([[NCE1]]
// CHECK-SAME:      !VPU.DistributedTensor<1x16x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>)
// CHECK-SAME:          -> !VPU.DistributedTensor<1x16x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>

// CHECK:       [[DIST_CAST2:%.+]] = VPU.DistributedCast([[NCE2]]
// CHECK-SAME:      !VPU.DistributedTensor<1x16x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 4, 1, 1], num_clusters = 4 : i64}>)
// CHECK-SAME:          -> !VPU.DistributedTensor<1x16x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>

// Concat is CMX-ed
// CHECK:       [[CONCAT:%.+]] = VPU.Concat([[DIST_CAST0]], [[DIST_CAST1]], [[DIST_CAST2]])
// CHECK-SAME:      !VPU.DistributedTensor<1x16x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>,
// CHECK-SAME:          -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED", num_clusters = 4 : i64}>

// Output Tile 0
// CHECK:       [[OUTSLICE0:%.+]] = VPU.Slice [[CONCAT]] [0, 0, 0, 0] [1, 48, 16, 32]
// Output Tile 1
// CHECK:       [[OUTSLICE1:%.+]] = VPU.Slice [[CONCAT]] [0, 0, 16, 0] [1, 48, 16, 32]

// Eltwise with two same inputs
// CHECK:       [[ELTWISE:%.+]] = VPU.NCE.ClusterTiling
// CHECK-SAME:      ([[OUTSLICE0]] as %arg4: tensor<1x48x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
// CHECK-SAME:      [[OUTSLICE1]] as %arg5: tensor<1x48x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>)
// CHECK:           [[ELTWISE_INNER:%.+]] = VPU.NCE.Eltwise(%arg4, %arg5) {op_type = #VPU.eltwise_type<ADD>, opaque_ppe = #VPU.PPEStub<>}

// CHECK:       [[OUTCOPY_OUT:%.+]] = VPU.NCE.ClusterTiling
// CHECK-SAME:      ([[ELTWISE]] as %arg4: tensor<1x48x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>)
// CHECK:           [[OUTCOPY_OUT_INNER:%.+]] = VPU.Copy(%arg4)

// CHECK:       return [[OUTCOPY_OUT]]
// CHECK-SAME:      : tensor<1x48x16x32xf16, {order = #NHWC}>


// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!Distributed = !VPU.DistributedTensor<
    1x48x64x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED",
    num_tiles = [1, 2, 1, 1],
    num_clusters = 2
}>

!DistributedTile = !VPU.DistributedTensor<
    1x48x32x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED",
    num_tiles = [1, 2, 1, 1],
    num_clusters = 2
}>

!DistributedTileOutput = !VPU.DistributedTensor<
    1x48x32x32xf16, #NHWC, @CMX_NN, {
   mode = "SEGMENTED",
    num_tiles = [1, 2, 1, 1],
    num_clusters = 2
}>

func.func @main(%input: tensor<1x48x64x32xf16, {order = #NHWC}>,
           %filter: tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
           %weightsTable: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
           %maxPoolWeightsTable: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
           -> tensor<1x48x64x32xf16, {order = #NHWC}> {

    // Tile 0
    %0 = VPU.Slice %input [0, 0, 0, 0] [1, 48, 32, 32] : tensor<1x48x64x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>

    %1 = VPU.NCE.ClusterTiling (%0 as %arg0: tensor<1x48x32x32xf16, {order = #NHWC}>) -> !DistributedTile {
        %16 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %2 = VPU.NCE.ClusterTiling (%1 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter as %arg1: tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg2: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !DistributedTileOutput {
        %16 = VPU.NCE.DepthConvolution(%arg0, %arg1, %arg2)
            {opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
            rawFilterShape = [48, 1, 3, 3],
            strides = [1, 1]}
            -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %3 = VPU.NCE.ClusterTiling (%2 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x48x32x32xf16, {order = #NHWC}> {
        %16 = VPU.Copy(%arg0) : tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>
        VPU.Yield %16
    }

    // Tile 1
    %4 = VPU.Slice %input [0, 0, 32, 0] [1, 48, 32, 32] : tensor<1x48x64x32xf16, {order = #NHWC}> to tensor<1x48x32x32xf16, {order = #NHWC}>

    %5 = VPU.NCE.ClusterTiling (%4 as %arg0: tensor<1x48x32x32xf16, {order = #NHWC}>) -> !DistributedTile {
        %16 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %6 = VPU.NCE.ClusterTiling (
        %5 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter as %arg1: tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg2: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !DistributedTileOutput {
        %16 = VPU.NCE.DepthConvolution(%arg0, %arg1, %arg2)
            {opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
            rawFilterShape = [48, 1, 3, 3],
            strides = [1, 1]}
            -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %7 = VPU.NCE.ClusterTiling (%6 as %arg0: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x48x32x32xf16, {order = #NHWC}> {
        %16 = VPU.Copy(%arg0) : tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>
        VPU.Yield %16
    }

    %8 = VPU.Concat(%3, %7) {static_offsets = [[0, 0, 0, 0], [0, 0, 32, 0]]} : tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x64x32xf16, {order = #NHWC}>

    %9 = VPU.NCE.ClusterTiling (%8 as %arg0: tensor<1x48x64x32xf16, {order = #NHWC}>) -> !Distributed {
        %12 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x48x64x32xf16, {order = #NHWC}> -> tensor<1x48x64x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %12
    }

    %10 = VPU.NCE.ClusterTiling (
        %9 as %arg0: tensor<1x48x64x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %maxPoolWeightsTable as %arg1: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !Distributed {
        %12 = VPU.NCE.MaxPool(%arg0, %arg1) {
                opaque_ppe = #VPU.PPEStub<>,
                pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
                strides = [1, 1],
                kernel_size = [1, 1]
            } -> tensor<1x48x64x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %12
    }

    %11 = VPU.NCE.ClusterTiling (%10 as %arg0: tensor<1x48x64x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x48x64x32xf16, {order = #NHWC}> {
        %12 = VPU.Copy(%arg0) : tensor<1x48x64x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x48x64x32xf16, {order = #NHWC}>
        VPU.Yield %12
    }

    return %11 : tensor<1x48x64x32xf16, {order = #NHWC}>

}

// Tile 0
// CHECK:       [[SLICE0:%.+]] = VPU.Slice %arg0 [0, 0, 0, 0] [1, 48, 32, 32]

// CHECK:       [[COPY0:%.+]]  = VPU.NCE.ClusterTiling ([[SLICE0]] as %arg4: tensor<1x48x32x32xf16, {order = #NHWC}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
// CHECK:           [[COPY0_INNER:%.+]] = VPU.Copy(%arg4) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}>
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[NCE0:%.+]]   = VPU.NCE.ClusterTiling ([[COPY0]] as %arg4: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:      -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
// CHECK:           [[NCE0_INNER:%.+]] = VPU.NCE.DepthConvolution(%arg4, %arg5, %arg6)
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[COPY0_OUT:%.+]]  = VPU.NCE.ClusterTiling ([[NCE0]] as %arg4: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>)
// CHECK-SAME:      -> tensor<1x48x32x32xf16, {order = #NHWC}>
// CHECK:           [[COPY0_INNER:%.+]] = VPU.Copy(%arg4) : tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {order = #NHWC}>

// Tile 1
// CHECK:       [[SLICE1:%.+]] = VPU.Slice %arg0 [0, 0, 32, 0] [1, 48, 32, 32]

// CHECK:       [[COPY1:%.+]]  = VPU.NCE.ClusterTiling ([[SLICE1]] as %arg4: tensor<1x48x32x32xf16, {order = #NHWC}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
// CHECK:           [[COPY1_INNER:%.+]] = VPU.Copy(%arg4) {out_mem_space = @CMX_NN} : tensor<1x48x32x32xf16, {order = #NHWC}>
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[NCE1:%.+]]   = VPU.NCE.ClusterTiling ([[COPY1]] as %arg4: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:      -> !VPU.DistributedTensor<1x48x32x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64}>
// CHECK:           [[NCE0_INNER:%.+]] = VPU.NCE.DepthConvolution(%arg4, %arg5, %arg6)
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[COPY1_OUT:%.+]]  = VPU.NCE.ClusterTiling ([[NCE1]] as %arg4: tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>)
// CHECK-SAME:      -> tensor<1x48x32x32xf16, {order = #NHWC}>
// CHECK:           [[COPY1_INNER:%.+]] = VPU.Copy(%arg4) : tensor<1x48x32x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:              -> tensor<1x48x32x32xf16, {order = #NHWC}>

// Concat
// CHECK:       [[CONCAT:%.+]] = VPU.Concat([[COPY0_OUT]], [[COPY1_OUT]])
// CHECK-SAME:      : tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}>
// CHECK-SAME:      -> tensor<1x48x64x32xf16, {order = #NHWC}>

// CHECK:       [[COPY2_CMX:%.+]] = VPU.NCE.ClusterTiling
// CHECK-SAME:      [[CONCAT]] as %arg4: tensor<1x48x64x32xf16, {order = #NHWC}>
// CHECK:           VPU.Copy

// CHECK:       [[NCE_OUT:%.+]] = VPU.NCE.ClusterTiling
// CHECK-SAME:      [[COPY2_CMX]] as %arg4: tensor<1x48x64x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK:           VPU.NCE.MaxPool

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!ConcatOutDistributed = !VPU.DistributedTensor<
    1x64x20x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2
}>

!ConcatInput0Distributed = !VPU.DistributedTensor<
    1x48x20x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2
}>

!ConcatInput1Distributed = !VPU.DistributedTensor<
    1x16x20x32xf16, #NHWC, @CMX_NN, {
   mode = "SEGMENTED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2
}>

func.func @CMXConcatOverChannelsDistributedSOH(%input: tensor<1x64x20x32xf16, {order = #NHWC}>)
           -> tensor<1x64x20x32xf16, {order = #NHWC}> {

    %filter0 = const.Declare tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> =
        dense<1.0> : tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %weightsTable0 = const.Declare tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<1> : tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>

    %filter1 = const.Declare tensor<16x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> =
        dense<1.0> : tensor<16x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %weightsTable1 = const.Declare tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<1> : tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>

    %maxPoolWeightsTable = const.Declare tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<1> : tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>

    // Tile 0
    %0 = VPU.Slice %input [0, 0, 0, 0] [1, 48, 20, 32] : tensor<1x64x20x32xf16, {order = #NHWC}> to tensor<1x48x20x32xf16, {order = #NHWC}>

    %1 = VPU.NCE.ClusterTiling (%0 as %arg0: tensor<1x48x20x32xf16, {order = #NHWC}>) -> !ConcatInput0Distributed {
        %16 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x48x20x32xf16, {order = #NHWC}> -> tensor<1x48x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %2 = VPU.NCE.ClusterTiling (%1 as %arg0: tensor<1x48x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter0 as %arg1: tensor<48x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0 as %arg2: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !ConcatInput0Distributed {
        %16 = VPU.NCE.DepthConvolution(%arg0, %arg1, %arg2)
            {opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
            rawFilterShape = [48, 1, 3, 3],
            strides = [1, 1]}
            -> tensor<1x48x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %3 = VPU.NCE.ClusterTiling (%2 as %arg0: tensor<1x48x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x48x20x32xf16, {order = #NHWC}> {
        %16 = VPU.Copy(%arg0) : tensor<1x48x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x48x20x32xf16, {order = #NHWC}>
        VPU.Yield %16
    }

    // Tile 1
    %4 = VPU.Slice %input [0, 48, 0, 0] [1, 16, 20, 32] : tensor<1x64x20x32xf16, {order = #NHWC}> to tensor<1x16x20x32xf16, {order = #NHWC}>

    %5 = VPU.NCE.ClusterTiling (%4 as %arg0: tensor<1x16x20x32xf16, {order = #NHWC}>) -> !ConcatInput1Distributed {
        %16 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x16x20x32xf16, {order = #NHWC}> -> tensor<1x16x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %6 = VPU.NCE.ClusterTiling (
        %5 as %arg0: tensor<1x16x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %filter1 as %arg1: tensor<16x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable1 as %arg2: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !ConcatInput1Distributed {
        %16 = VPU.NCE.DepthConvolution(%arg0, %arg1, %arg2)
            {opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>,
            rawFilterShape = [16, 1, 3, 3],
            strides = [1, 1]}
            -> tensor<1x16x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %16
    }

    %7 = VPU.NCE.ClusterTiling (%6 as %arg0: tensor<1x16x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x16x20x32xf16, {order = #NHWC}> {
        %16 = VPU.Copy(%arg0) : tensor<1x16x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x16x20x32xf16, {order = #NHWC}>
        VPU.Yield %16
    }

    %8 = VPU.Concat(%3, %7) {static_offsets = [[0, 0, 0, 0], [0, 48, 0, 0]]} : tensor<1x48x20x32xf16, {order = #NHWC}>, tensor<1x16x20x32xf16, {order = #NHWC}> -> tensor<1x64x20x32xf16, {order = #NHWC}>

    %9 = VPU.NCE.ClusterTiling (%8 as %arg0: tensor<1x64x20x32xf16, {order = #NHWC}>) -> !ConcatOutDistributed {
        %12 = VPU.Copy(%arg0) {out_mem_space = @CMX_NN} : tensor<1x64x20x32xf16, {order = #NHWC}> -> tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %12
    }

    %10 = VPU.NCE.ClusterTiling (
        %9 as %arg0: tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %maxPoolWeightsTable as %arg1: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !ConcatOutDistributed {
        %12 = VPU.NCE.MaxPool(%arg0, %arg1) {
                opaque_ppe = #VPU.PPEStub<>,
                pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
                strides = [1, 1],
                kernel_size = [1, 1]
            } -> tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %12
    }

    %11 = VPU.NCE.ClusterTiling (%10 as %arg0: tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x64x20x32xf16, {order = #NHWC}> {
        %12 = VPU.Copy(%arg0) : tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x20x32xf16, {order = #NHWC}>
        VPU.Yield %12
    }

    return %11 : tensor<1x64x20x32xf16, {order = #NHWC}>

}

// Tile 0
// CHECK:       [[SLICE0:%.+]] = VPU.Slice %arg0 [0, 0, 0, 0] [1, 48, 20, 32]

// CHECK:       [[COPY0:%.+]]  = VPU.NCE.ClusterTiling ([[SLICE0]] as %arg1: tensor<1x48x20x32xf16, {order = #NHWC}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x48x20x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
// CHECK:           [[COPY0_INNER:%.+]] = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<1x48x20x32xf16, {order = #NHWC}>
// CHECK-SAME:              -> tensor<1x48x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[NCE0:%.+]]   = VPU.NCE.ClusterTiling ([[COPY0]] as %arg1: tensor<1x48x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:      -> !VPU.DistributedTensor<1x48x20x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
// CHECK:           [[NCE0_INNER:%.+]] = VPU.NCE.DepthConvolution
// CHECK-SAME:              -> tensor<1x48x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// Tile 1
// CHECK:       [[SLICE1:%.+]] = VPU.Slice %arg0 [0, 48, 0, 0] [1, 16, 20, 32]

// CHECK:       [[COPY1:%.+]]  = VPU.NCE.ClusterTiling ([[SLICE1]] as %arg1: tensor<1x16x20x32xf16, {order = #NHWC}>)
// CHECK-SAME:      -> !VPU.DistributedTensor<1x16x20x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
// CHECK:           [[COPY1_INNER:%.+]] = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<1x16x20x32xf16, {order = #NHWC}>
// CHECK-SAME:              -> tensor<1x16x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK:       [[NCE1:%.+]]   = VPU.NCE.ClusterTiling ([[COPY1]] as %arg1: tensor<1x16x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:      -> !VPU.DistributedTensor<1x16x20x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
// CHECK:           [[NCE0_INNER:%.+]] = VPU.NCE.DepthConvolution
// CHECK-SAME:              -> tensor<1x16x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// Concat
// CHECK:       [[CONCAT:%.+]] = VPU.Concat([[NCE0]], [[NCE1]])
// CHECK-SAME:      : !VPU.DistributedTensor<1x48x20x32xf16, #NHWC, @CMX_NN
// CHECK-SAME:              {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}
// CHECK-SAME:        !VPU.DistributedTensor<1x16x20x32xf16, #NHWC, @CMX_NN,
// CHECK-SAME:              {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}
// CHECK-SAME:      -> !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN
// CHECK-SAME:              {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}

// CHECK:       [[NCE_OUT:%.+]] = VPU.NCE.ClusterTiling
// CHECK-SAME:      [[CONCAT]] as %arg1: tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK:           VPU.NCE.MaxPool

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

func.func @DoNotConcatCMXWhenSlicedInput(%input: tensor<1x16x224x224xf16, {order = #NHWC}>,
           %filter: tensor<64x1x1x160xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>,
           %weightsTable: tensor<64x1x1x4xsi32, {mem_space = [@CMX_NN, 0], order = #NCHW}>,
           %weightsTableMaxPool: tensor<64x1x1x4xsi32, {mem_space = [@CMX_NN, 0], order = #NCHW}>)
           -> tensor<1x64x19x56xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> {

    %0 = VPU.Slice %input [0, 0, 0, 0] [1, 4, 114, 224] : tensor<1x16x224x224xf16, {order = #NHWC}> to tensor<1x4x114x224xf16, {order = #NHWC}>
    %1 = VPU.Copy(%0) {out_mem_space = [@CMX_NN, 0]} : tensor<1x4x114x224xf16, {order = #NHWC}>
        -> tensor<1x4x114x224xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %2 = VPU.NCE.CompressConvolution(%1, %filter, %weightsTable) {
            cm_sp_pattern = 7 : i64, pad = #VPU.Padding<left = 3 : i64, right = 2 : i64, top = 3 : i64, bottom = 0 : i64>,
            opaque_ppe = #VPU.PPEStub<>,
            rawFilterShape = [64, 3, 7, 7], strides = [2, 2]}
        -> tensor<1x64x56x112xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %3 = VPU.Copy(%2) : tensor<1x64x56x112xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
        -> tensor<1x64x56x112xf16, {order = #NHWC}>

    %4 = VPU.Slice %input [0, 0, 109, 0] [1, 4, 115, 224] : tensor<1x16x224x224xf16, {order = #NHWC}> to tensor<1x4x115x224xf16, {order = #NHWC}>
    %5 = VPU.Copy(%4) {out_mem_space = [@CMX_NN, 0]} : tensor<1x4x115x224xf16, {order = #NHWC}>
        -> tensor<1x4x115x224xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %6 = VPU.NCE.CompressConvolution(%5, %filter, %weightsTable) {
            cm_sp_pattern = 7 : i64, pad = #VPU.Padding<left = 3 : i64, right = 2 : i64, top = 0 : i64, bottom = 2 : i64>,
                opaque_ppe = #VPU.PPEStub<>,
            rawFilterShape = [64, 3, 7, 7], strides = [2, 2]}
        -> tensor<1x64x56x112xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %7 = VPU.Copy(%6) : tensor<1x64x56x112xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
        -> tensor<1x64x56x112xf16, {order = #NHWC}>

    %8 = VPU.Concat(%3, %7) {static_offsets = [[0, 0, 0, 0], [0, 0, 56, 0]]} : tensor<1x64x56x112xf16, {order = #NHWC}>, tensor<1x64x56x112xf16, {order = #NHWC}>
        -> tensor<1x64x112x112xf16, {order = #NHWC}>

    %9 = VPU.Slice %8 [0, 0, 0, 0] [1, 64, 38, 112] : tensor<1x64x112x112xf16, {order = #NHWC}> to tensor<1x64x38x112xf16, {order = #NHWC}>
    %10 = VPU.Copy(%9) {out_mem_space = [@CMX_NN, 0]} : tensor<1x64x38x112xf16, {order = #NHWC}>
        -> tensor<1x64x38x112xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %11 = VPU.NCE.MaxPool(%10, %weightsTableMaxPool) {
            kernel_size = [3, 3],
            pad = #VPU.Padding<left = 1 : i64, right = 0 : i64, top = 1 : i64, bottom = 0 : i64>,
            opaque_ppe = #VPU.PPEStub<>,
            strides = [2, 2]}
        -> tensor<1x64x19x56xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    return %11 : tensor<1x64x19x56xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    // CHECK:       [[IN1:%.+]] = VPU.Slice %arg0 [0, 0, 0, 0] [1, 4, 114, 224] : tensor<1x16x224x224xf16, {order = #NHWC}> to tensor<1x4x114x224xf16, {order = #NHWC}>
    // CHECK:       [[IN_CMX1:%.+]] = VPU.Copy([[IN1]]) {out_mem_space = [@CMX_NN, 0]} : tensor<1x4x114x224xf16, {order = #NHWC}> -> tensor<1x4x114x224xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    // CHECK:       [[OUT_COMP_CONV1_CMX:%.+]] = VPU.NCE.CompressConvolution([[IN_CMX1]], %arg1, %arg2)
    // CHECK-SAME:      -> tensor<1x64x56x112xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    // CHECK:       [[OUT_COMP_CONV1:%.+]] = VPU.Copy([[OUT_COMP_CONV1_CMX]]) : tensor<1x64x56x112xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x64x56x112xf16, {order = #NHWC}>

    // CHECK:       [[IN2:%.+]] = VPU.Slice %arg0 [0, 0, 109, 0] [1, 4, 115, 224] : tensor<1x16x224x224xf16, {order = #NHWC}> to tensor<1x4x115x224xf16, {order = #NHWC}>
    // CHECK:       [[IN_CMX2:%.+]] = VPU.Copy([[IN2]]) {out_mem_space = [@CMX_NN, 0]} : tensor<1x4x115x224xf16, {order = #NHWC}> -> tensor<1x4x115x224xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    // CHECK:       [[OUT_COMP_CONV2_CMX:%.+]] = VPU.NCE.CompressConvolution([[IN_CMX2]], %arg1, %arg2)
    // CHECK-SAME:      -> tensor<1x64x56x112xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    // CHECK:       [[OUT_COMP_CONV2:%.+]] = VPU.Copy([[OUT_COMP_CONV2_CMX]]) : tensor<1x64x56x112xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x64x56x112xf16, {order = #NHWC}>

    // CHECK:       [[CONCAT:%.+]] = VPU.Concat([[OUT_COMP_CONV1]], [[OUT_COMP_CONV2]])
    // CHECK-SAME:      : tensor<1x64x56x112xf16, {order = #NHWC}>, tensor<1x64x56x112xf16, {order = #NHWC}>
    // CHECK-SAME:      -> tensor<1x64x112x112xf16, {order = #NHWC}>

    // CHECK:       [[SLICE:%.+]] = VPU.Slice [[CONCAT]] [0, 0, 0, 0] [1, 64, 38, 112] : tensor<1x64x112x112xf16, {order = #NHWC}> to tensor<1x64x38x112xf16, {order = #NHWC}>
    // CHECK:       [[COPY:%.+]] = VPU.Copy([[SLICE]]) {out_mem_space = [@CMX_NN, 0]} : tensor<1x64x38x112xf16, {order = #NHWC}> -> tensor<1x64x38x112xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    // CHECK:       [[OUT_MAXPOOL:%.+]] = VPU.NCE.MaxPool([[COPY]], %arg3 ) {kernel_size = [3, 3], opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 1 : i64, right = 0 : i64, top = 1 : i64, bottom = 0 : i64>, strides = [2, 2]} -> tensor<1x64x19x56xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    // CHECK:       return [[OUT_MAXPOOL]] : tensor<1x64x19x56xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

func.func @DoNotConcatWithSameNCEInput(%arg0: tensor<1x48x32x32xf16, {order = #NHWC}>,
           %weightsTableMaxPool0: tensor<48x1x1x4xsi32, {mem_space = [@CMX_NN, 0], order = #NCHW}>,
           %weightsTableMaxPool1: tensor<96x1x1x4xsi32, {mem_space = [@CMX_NN, 0], order = #NCHW}>)
           -> tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> {

    // Concat result copy-in for NCE user
    %0 = VPU.Copy(%arg0) {out_mem_space = [@CMX_NN, 0]} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %1 = VPU.NCE.MaxPool(%0, %weightsTableMaxPool0) {
            opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
            strides = [1, 1], kernel_size = [1, 1]
        } -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %2 = VPU.Copy(%1) : tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>
    %3 = VPU.Concat(%2, %2) {static_offsets = [[0, 0, 0, 0], [0, 48, 0, 0]]} : tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x96x32x32xf16, {order = #NHWC}>
    %4 = VPU.Copy(%3) {out_mem_space = [@CMX_NN, 0]} : tensor<1x96x32x32xf16, {order = #NHWC}> -> tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %5 = VPU.NCE.MaxPool(%4, %weightsTableMaxPool1) {
            opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
            strides = [1, 1], kernel_size = [1, 1]
        } -> tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    return %5 : tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    // CHECK:       [[IN_DPU:%.+]] = VPU.Copy(%arg0)
    // CHECK:       [[MAXPOOL:%.+]] = VPU.NCE.MaxPool([[IN_DPU]], %arg1 )
    // CHECK:       [[OUT_DDR:%.+]] = VPU.Copy([[MAXPOOL]])
    // CHECK:       [[CONCAT:%.+]] = VPU.Concat([[OUT_DDR]], [[OUT_DDR]])
    // CHECK:       [[IN_DPU1:%.+]] = VPU.Copy([[CONCAT]])
    // CHECK:       [[MAXPOOL1:%.+]] = VPU.NCE.MaxPool([[IN_DPU1]], %arg2 )

    // CHECK:       return [[MAXPOOL1]] : tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: func.func @DoNotConcatWithInPlaceEltwise
// CHECK-SAME:    ([[INPUT1:%.+]]: tensor<1x48x32x32xf16, {order = #NHWC}>, [[INPUT2:%.+]]: tensor<1x48x32x32xf16, {order = #NHWC}>)
func.func @DoNotConcatWithInPlaceEltwise(%input1: tensor<1x48x32x32xf16, {order = #NHWC}>, %input2: tensor<1x48x32x32xf16, {order = #NHWC}>)
           -> tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> {

    %input1_eltwise1 = VPU.Copy(%input1) {out_mem_space = [@CMX_NN, 0]} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    %input2_eltwise1 = VPU.Copy(%input2) {out_mem_space = [@CMX_NN, 0]} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    %eltwise1 = VPU.NCE.Eltwise(%input1_eltwise1, %input2_eltwise1) {
            is_inplace = true,
            op_type = #VPU.eltwise_type<ADD>,
            opaque_ppe = #VPU.PPEStub<>
        } -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    %output_eltwise1 = VPU.Copy(%eltwise1) : tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>

    %input1_eltwise2 = VPU.Copy(%input1) {out_mem_space = [@CMX_NN, 0]} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    %input2_eltwise2 = VPU.Copy(%input2) {out_mem_space = [@CMX_NN, 0]} : tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    %eltwise2 = VPU.NCE.Eltwise(%input1_eltwise2, %input2_eltwise2) {
            is_inplace = true,
            op_type = #VPU.eltwise_type<ADD>,
            opaque_ppe = #VPU.PPEStub<>
        } -> tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>
    %output_eltwise2 = VPU.Copy(%eltwise2) : tensor<1x48x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<1x48x32x32xf16, {order = #NHWC}>

    %concat_ddr = VPU.Concat(%output_eltwise1, %output_eltwise2) {static_offsets = [[0, 0, 0, 0], [0, 48, 0, 0]]} : tensor<1x48x32x32xf16, {order = #NHWC}>, tensor<1x48x32x32xf16, {order = #NHWC}> -> tensor<1x96x32x32xf16, {order = #NHWC}>
    %concat_cmx = VPU.Copy(%concat_ddr) {out_mem_space = [@CMX_NN, 0]} : tensor<1x96x32x32xf16, {order = #NHWC}> -> tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    %output = VPU.NCE.MaxPool(%concat_cmx) {
            kernel_size = [1, 1],
            opaque_ppe = #VPU.PPEStub<>,
            pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
            strides = [1, 1]
        } -> tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    return %output : tensor<1x96x32x32xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    // CHECK: [[INPUT1_ELTWISE1:%.+]] = VPU.Copy([[INPUT1]])
    // CHECK: [[INPUT2_ELTWISE1:%.+]] = VPU.Copy([[INPUT2]])
    // CHECK: [[ELTWISE1:%.+]] = VPU.NCE.Eltwise([[INPUT1_ELTWISE1]], [[INPUT2_ELTWISE1]])
    // CHECK: [[OUTPUT_ELTWISE1:%.+]] = VPU.Copy([[ELTWISE1]])

    // CHECK: [[INPUT1_ELTWISE2:%.+]] = VPU.Copy([[INPUT1]])
    // CHECK: [[INPUT2_ELTWISE2:%.+]] = VPU.Copy([[INPUT2]])
    // CHECK: [[ELTWISE2:%.+]] = VPU.NCE.Eltwise([[INPUT1_ELTWISE2]], [[INPUT2_ELTWISE2]])
    // CHECK: [[OUTPUT_ELTWISE2:%.+]] = VPU.Copy([[ELTWISE2]])

    // CHECK: [[CONCAT_CMX:%.+]] = VPU.Concat([[OUTPUT_ELTWISE1]], [[OUTPUT_ELTWISE2]])
    // CHECK: [[CONCAT_DDR:%.+]] = VPU.Copy([[CONCAT_CMX]])
    // CHECK: [[OUTPUT:%.+]] = VPU.NCE.MaxPool([[CONCAT_DDR]])
    // CHECK: return [[OUTPUT]]
}


// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

!OutDistributed = !VPU.DistributedTensor<1x1024x1x1xf16, #NHWC, @CMX_NN, {
    mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64,
    alignment = [1, 16, 1, 1], uniform_distributed_segments,
    compute_shapes = [[1, 512, 1, 1], [1, 512, 1, 1]], compute_offsets = [[0, 0, 0, 0], [0, 512, 0, 0]],
    memory_shapes = [[1, 1024, 1, 1], [1, 1024, 1, 1]], memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>


// CHECK-LABEL: func.func @InputConcatOnlyTilingCopy
// CHECK-SAME:    ([[INPUT0:%.+]]: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, [[INPUT1:%.+]]: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>)
func.func @InputConcatOnlyTilingCopy(%arg0: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, %arg1: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>)
           -> tensor<2x1023x1x1xf16, {order = #NHWC}> {
    %filter0 = const.Declare tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> =
        dense<1.0> : tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %weightsTable0 = const.Declare tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<1> : tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>

    %0 = VPU.NCE.ClusterTiling (%arg0 as %arg2: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, %filter0 as %arg3: tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, %weightsTable0 as %arg4: tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !OutDistributed {
        %1302 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, rawFilterShape = [1024, 128, 1, 1], strides = [1, 1]}
            -> tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %1302
    }
    %1 = VPU.NCE.ClusterTiling (%0 as %arg2: tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x1024x1x1xf16, {order = #NHWC}> {
        %1302 = VPU.Copy(%arg2) : tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x1024x1x1xf16, {order = #NHWC}>
        VPU.Yield %1302
    }

    %filter1 = const.Declare tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> =
        dense<1.1> : tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %weightsTable1 = const.Declare tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<2> : tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>

    %2 = VPU.NCE.ClusterTiling (%arg1 as %arg2: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, %filter1 as %arg3: tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, %weightsTable1 as %arg4: tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !OutDistributed {
        %1302 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, rawFilterShape = [1024, 128, 1, 1], strides = [1, 1]}
            -> tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %1302
    }

    %3 = VPU.NCE.ClusterTiling (%2 as %arg2: tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x1024x1x1xf16, {order = #NHWC}> {
        %1302 = VPU.Copy(%arg2) : tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x1024x1x1xf16, {order = #NHWC}>
        VPU.Yield %1302
    }

    %4 = VPU.Concat(%1, %3) {static_offsets = [[0, 0, 0, 0], [1, 0, 0, 0]]} : tensor<1x1024x1x1xf16, {order = #NHWC}>, tensor<1x1024x1x1xf16, {order = #NHWC}> -> tensor<2x1024x1x1xf16, {order = #NHWC}>

    %5 = VPU.Slice %4 [0, 0, 0, 0] [2, 1023, 1, 1] : tensor<2x1024x1x1xf16, {order = #NHWC}> to tensor<2x1023x1x1xf16, {order = #NHWC}>

    return %5 : tensor<2x1023x1x1xf16, {order = #NHWC}>


    // CHECK-DAG:   [[WEIGHTSTABLE1:%.+]] = const.Declare tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> = dense<2> : tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
    // CHECK-DAG:   [[FILTER1:%.+]] = const.Declare tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> = dense<1.099610e+00> : tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK-DAG:   [[FILTER0:%.+]] = const.Declare tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> = dense<1.000000e+00> : tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK-DAG:   [[WEIGHTSTABLE0:%.+]] = const.Declare tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> = dense<1> : tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>

    // CHECK:       [[CONV0:%.+]]  = VPU.NCE.ClusterTiling ([[INPUT0]] as {{[^:]+}}: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, [[FILTER0]] as {{[^:]+}}: tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, [[WEIGHTSTABLE0]] as {{[^:]+}}: tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    // CHECK:       [[CONV1:%.+]]  = VPU.NCE.ClusterTiling ([[INPUT1]] as {{[^:]+}}: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, [[FILTER1]] as {{[^:]+}}: tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, [[WEIGHTSTABLE1]] as {{[^:]+}}:  tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)

    // CHECK:       [[CONCAT:%.+]] = VPU.Concat([[CONV0]], [[CONV1]])
    // CHECK-SAME{LITERAL}:     {static_offsets = [[0, 0, 0, 0], [1, 0, 0, 0]]} :
    // CHECK-SAME:     !VPU.DistributedTensor<1x1024x1x1xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1], uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:     compute_shapes = [[1, 512, 1, 1], [1, 512, 1, 1]], compute_offsets = [[0, 0, 0, 0], [0, 512, 0, 0]], memory_shapes = [[1, 1024, 1, 1], [1, 1024, 1, 1]], memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>,
    // CHECK-SAME:     !VPU.DistributedTensor<1x1024x1x1xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1], uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:     compute_shapes = [[1, 512, 1, 1], [1, 512, 1, 1]], compute_offsets = [[0, 0, 0, 0], [0, 512, 0, 0]], memory_shapes = [[1, 1024, 1, 1], [1, 1024, 1, 1]], memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    // CHECK-SAME:     -> !VPU.DistributedTensor<2x1024x1x1xf16, #NHWC, @CMX_NN, {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64, alignment = [1, 16, 1, 1], uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:     compute_shapes = [[2, 1024, 1, 1], [2, 1024, 1, 1]], compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]], memory_shapes = [[2, 1024, 1, 1], [2, 1024, 1, 1]], memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>

    // CHECK:       [[COPY:%.+]] = VPU.NCE.ClusterTiling ([[CONCAT]]  as [[INNER_ARG0:[^:]+]]: tensor<2x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<2x1024x1x1xf16, {order = #NHWC}> {
    // CHECK:           [[COPY_INNER:%.+]] = VPU.Copy([[INNER_ARG0]]) : tensor<2x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<2x1024x1x1xf16, {order = #NHWC}>
    // CHECK:           VPU.Yield [[COPY_INNER]]
    // CHECK:       }
    // CHECK:       [[SLICE:%.+]] = VPU.Slice [[COPY]] [0, 0, 0, 0] [2, 1023, 1, 1] : tensor<2x1024x1x1xf16, {order = #NHWC}> to tensor<2x1023x1x1xf16, {order = #NHWC}>
    // CHECK:       return [[SLICE]] : tensor<2x1023x1x1xf16, {order = #NHWC}>
}



// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>


// CHECK-LABEL: func.func @InputConcatOnlyCopy
// CHECK-SAME:    ([[INPUT0:%.+]]: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, [[INPUT1:%.+]]: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>)
func.func @InputConcatOnlyCopy(%arg0: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, %arg1: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>)
           -> tensor<2x1023x1x1xf16, {order = #NHWC}> {
    %filter0 = const.Declare tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> =
        dense<1.0> : tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %weightsTable0 = const.Declare tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<1> : tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>


    %0 = VPU.NCE.Convolution(%arg0, %filter0, %weightsTable0) {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, rawFilterShape = [1024, 128, 1, 1], strides = [1, 1]}
            -> tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %1= VPU.Copy(%0) : tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x1024x1x1xf16, {order = #NHWC}>


    %filter1 = const.Declare tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> =
        dense<1.1> : tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %weightsTable1 = const.Declare tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<2> : tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>

    %2 = VPU.NCE.Convolution(%arg1, %filter1, %weightsTable1) {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, rawFilterShape = [1024, 128, 1, 1], strides = [1, 1]}
            -> tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %3= VPU.Copy(%2) : tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x1024x1x1xf16, {order = #NHWC}>


    %4 = VPU.Concat(%1, %3) {static_offsets = [[0, 0, 0, 0], [1, 0, 0, 0]]} : tensor<1x1024x1x1xf16, {order = #NHWC}>, tensor<1x1024x1x1xf16, {order = #NHWC}> -> tensor<2x1024x1x1xf16, {order = #NHWC}>

    %5 = VPU.Slice %4 [0, 0, 0, 0] [2, 1023, 1, 1] : tensor<2x1024x1x1xf16, {order = #NHWC}> to tensor<2x1023x1x1xf16, {order = #NHWC}>

    return %5 : tensor<2x1023x1x1xf16, {order = #NHWC}>

    // CHECK-DAG:   [[WEIGHTSTABLE1:%.+]] = const.Declare tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> = dense<2> : tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
    // CHECK-DAG:   [[FILTER1:%.+]] = const.Declare tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> = dense<1.099610e+00> : tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK-DAG:   [[FILTER0:%.+]] = const.Declare tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> = dense<1.000000e+00> : tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK-DAG:   [[WEIGHTSTABLE0:%.+]] = const.Declare tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> = dense<1> : tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>

    // CHECK:       [[CONV0:%.+]]  = VPU.NCE.Convolution([[INPUT0]], [[FILTER0]], [[WEIGHTSTABLE0]])
    // CHECK:       [[CONV1:%.+]]  = VPU.NCE.Convolution([[INPUT1]], [[FILTER1]], [[WEIGHTSTABLE1]])

    // CHECK:       [[CONCAT:%.+]] = VPU.Concat([[CONV0]], [[CONV1]])
    // CHECK-SAME{LITERAL}:     {static_offsets = [[0, 0, 0, 0], [1, 0, 0, 0]]} : tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<2x1024x1x1xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}>

    // CHECK:       [[COPY:%.+]]  = VPU.Copy([[CONCAT]]) : tensor<2x1024x1x1xf16, {mem_space = [@CMX_NN, 0], order = #NHWC}> -> tensor<2x1024x1x1xf16, {order = #NHWC}>
    // CHECK:       [[SLICE:%.+]] = VPU.Slice [[COPY]] [0, 0, 0, 0] [2, 1023, 1, 1] : tensor<2x1024x1x1xf16, {order = #NHWC}> to tensor<2x1023x1x1xf16, {order = #NHWC}>
    // CHECK:       return [[SLICE]] : tensor<2x1023x1x1xf16, {order = #NHWC}>

}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>

!OutDistributed = !VPU.DistributedTensor<1x1024x1x1xf16, #NHWC, @CMX_NN, {
    mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64,
    alignment = [1, 16, 1, 1], uniform_distributed_segments,
    compute_shapes = [[1, 512, 1, 1], [1, 512, 1, 1]], compute_offsets = [[0, 0, 0, 0], [0, 512, 0, 0]],
    memory_shapes = [[1, 1024, 1, 1], [1, 1024, 1, 1]], memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>


// CHECK-LABEL: func.func @NotConcatForNotHighestDim
// CHECK-SAME:    ([[INPUT0:%.+]]: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, [[INPUT1:%.+]]: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>)
func.func @NotConcatForNotHighestDim(%arg0: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, %arg1: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>)
           -> tensor<1x1023x1x2xf16, {order = #NHWC}> {
    %filter0 = const.Declare tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> =
        dense<1.0> : tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %weightsTable0 = const.Declare tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<1> : tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>

    %0 = VPU.NCE.ClusterTiling (%arg0 as %arg2: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, %filter0 as %arg3: tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, %weightsTable0 as %arg4: tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !OutDistributed {
        %1302 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, rawFilterShape = [1024, 128, 1, 1], strides = [1, 1]}
            -> tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %1302
    }
    %1 = VPU.NCE.ClusterTiling (%0 as %arg2: tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x1024x1x1xf16, {order = #NHWC}> {
        %1302 = VPU.Copy(%arg2) : tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x1024x1x1xf16, {order = #NHWC}>
        VPU.Yield %1302
    }

    %filter1 = const.Declare tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> =
        dense<1.1> : tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    %weightsTable1 = const.Declare tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<2> : tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>

    %2 = VPU.NCE.ClusterTiling (%arg1 as %arg2: tensor<1x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, %filter1 as %arg3: tensor<1024x128x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>, %weightsTable1 as %arg4: tensor<1024x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !OutDistributed {
        %1302 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {opaque_ppe = #VPU.PPEStub<>, pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, rawFilterShape = [1024, 128, 1, 1], strides = [1, 1]}
            -> tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %1302
    }

    %3 = VPU.NCE.ClusterTiling (%2 as %arg2: tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x1024x1x1xf16, {order = #NHWC}> {
        %1302 = VPU.Copy(%arg2) : tensor<1x1024x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x1024x1x1xf16, {order = #NHWC}>
        VPU.Yield %1302
    }

    %4 = VPU.Concat(%1, %3) {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 1]]} : tensor<1x1024x1x1xf16, {order = #NHWC}>, tensor<1x1024x1x1xf16, {order = #NHWC}> -> tensor<1x1024x1x2xf16, {order = #NHWC}>

    %5 = VPU.Slice %4 [0, 0, 0, 0] [1, 1023, 1, 2] : tensor<1x1024x1x2xf16, {order = #NHWC}> to tensor<1x1023x1x2xf16, {order = #NHWC}>

    return %5 : tensor<1x1023x1x2xf16, {order = #NHWC}>


    // CHECK-DAG:   [[WEIGHTSTABLE1:%.+]] = const.Declare tensor<1024x1x1x4xsi32
    // CHECK-DAG:   [[FILTER1:%.+]] = const.Declare tensor<1024x128x1x1xf16
    // CHECK-DAG:   [[FILTER0:%.+]] = const.Declare tensor<1024x128x1x1xf16
    // CHECK-DAG:   [[WEIGHTSTABLE0:%.+]] = const.Declare tensor<1024x1x1x4xsi32

    // CHECK:       [[CONV0:%.+]] = VPU.NCE.ClusterTiling
    // CHECK:             [[CONV0_INNER:%.+]] = VPU.NCE.Convolution
    // CHECK:       [[COPY0:%.+]] = VPU.NCE.ClusterTiling
    // CHECK:             [[COPY0_INNER:%.+]] = VPU.Copy

    // CHECK:       [[CONV1:%.+]] = VPU.NCE.ClusterTiling
    // CHECK:             [[CONV1_INNER:%.+]] = VPU.NCE.Convolution
    // CHECK:       [[COPY1:%.+]] = VPU.NCE.ClusterTiling
    // CHECK:             [[COPY1_INNER:%.+]] = VPU.Copy

    // CHECK:       [[CONCAT:%.+]]= VPU.Concat
    // CHECK:       [[SLICE:%.+]]= VPU.Slice

    // CHECK:       return [[SLICE]]
}
