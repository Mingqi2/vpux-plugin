//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/VPU/IR/ops.hpp"

#include "vpux/compiler/utils/error.hpp"

using namespace vpux;

mlir::LogicalResult vpux::VPU::DeformablePSROIPoolingOp::inferReturnTypes(
        mlir::MLIRContext* ctx, std::optional<mlir::Location> optLoc, mlir::ValueRange operands,
        mlir::DictionaryAttr attrs, mlir::OpaqueProperties, mlir::RegionRange /*regions*/,
        mlir::SmallVectorImpl<mlir::Type>& inferredReturnTypes) {
    const auto loc = optLoc.value_or(mlir::UnknownLoc::get(ctx));

    VPU::DeformablePSROIPoolingOpAdaptor deformablepsroiPooling(operands, attrs);
    if (mlir::failed(deformablepsroiPooling.verify(loc))) {
        return mlir::failure();
    }

    const auto outputDim = deformablepsroiPooling.getOutputDim();
    const auto groupSize =
            deformablepsroiPooling.getGroupSize().has_value() ? deformablepsroiPooling.getGroupSize().value() : 1;
    const auto inTypeFeatureMap = deformablepsroiPooling.getInputScoreMaps().getType().cast<vpux::NDTypeInterface>();
    const auto inType2 = deformablepsroiPooling.getInputRois().getType().cast<vpux::NDTypeInterface>();
    const auto inShapeCoord = inType2.getShape();

    if (outputDim <= 0) {
        return errorAt(loc, "Pooled size attribute outputDim should be positive.");
    }

    if (groupSize <= 0) {
        return errorAt(loc, "Group size attribute groupSize should be positive.");
    }

    SmallVector<int64_t> outputShape({inShapeCoord.raw()[0],  // num_rois
                                      outputDim,              // output channel number
                                      groupSize,              // pooled_w
                                      groupSize});            // pooled_h

    const auto outType = inTypeFeatureMap.changeShape(Shape(outputShape));
    inferredReturnTypes.push_back(outType);

    return mlir::success();
}
