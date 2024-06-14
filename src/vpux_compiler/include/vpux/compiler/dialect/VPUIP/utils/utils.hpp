//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#pragma once

#include "vpux/compiler/core/attributes/stride_reqs.hpp"
#include "vpux/compiler/dialect/IERT/ops.hpp"
#include "vpux/compiler/dialect/VPURT/IR/ops.hpp"

#include "vpux/compiler/utils/swizzling_utils.hpp"
#include "vpux/utils/core/enums.hpp"

#include <mlir/IR/Builders.h>
#include <mlir/IR/BuiltinTypes.h>
#include <mlir/IR/Location.h>
#include <mlir/IR/Value.h>
#include <vpux/compiler/dialect/VPU/utils/explicit_distribution_utils.hpp>

namespace vpux {
namespace VPUIP {

//
// Profiling
//

constexpr uint32_t HW_TIMER_ABSOLUTE_ADDR_30XX = 0x208200BC;
constexpr uint32_t HW_TIMER_ABSOLUTE_ADDR_37XX = 0x26029000;
// DMA Profiling consist of 2 32bit timestamps
constexpr uint16_t HW_DMA_PROFILING_SIZE_BYTES = 8;
constexpr uint16_t HW_DMA_PROFILING_SIZE_BYTES_40XX = 64;
constexpr uint32_t HW_DMA_PROFILING_MAX_BUFFER_SIZE = 512;
// maximal number of profiled DMAs in HWDDR profiling mode - 2^12
constexpr uint32_t HW_DMA_PROFILING_ID_LIMIT = 4096;
// DPU Profiling consist of 2 64bit timestamps(start and stop)
constexpr uint16_t HW_DPU_PROFILING_SIZE_BYTES_30XX = 16;
// DPU Profiling for 37XX use MODE0: // 8’h0, odu_tstamp[27:0], odu_wl_duration[27:0], {3’h0,sve_id[4:0]},
// idu_tstamp[27:0], idu_wl_duration[27:0]
constexpr uint16_t HW_DPU_PROFILING_SIZE_BYTES_37XX = 16;
// DPU Profiling for 40XX use MODE3 and consists of two 128-bit structures
// The alignment of the profiling record is required to be 32-bytes
constexpr uint16_t HW_DPU_PROFILING_SIZE_BYTES_40XX = 32;
constexpr uint32_t HW_DPU_PROFILING_MAX_BUFFER_SIZE =
        1024;  // Up to 64 DPU Tasks in single CMX DPU profiling buffer instance
// UPA Profiling consist of 2 64bit timestamps(start and stop) + 2 32bit for active and stall counters
constexpr uint16_t HW_UPA_PROFILING_SIZE_BYTES = 24;
// ActShave Profiling buffer: 64bit start timestamp + 32bit duration + 4 32bit counters + 32 bit reserved
constexpr uint16_t HW_ACT_SHAVE_PROFILING_SIZE_BYTES = 32;
// ActShave Profiling buffer size in bytes
constexpr uint32_t HW_ACT_SHAVE_PROFILING_MAX_BUFFER_SIZE = 256;
// M2I Profiling buffer size in bytes
constexpr uint32_t HW_M2I_PROFILING_MAX_BUFFER_SIZE = 128;
// 3720 architecture has 2 Mb CMX size. This define describes its half.
constexpr uint32_t HW_MIDDLE_OF_AVAILABLE_CMX_MEMORY_3720 = (1024 * 1024);
// 4000 arch has 1.4 Mb of CMX memory available
constexpr uint32_t HW_AVAILABLE_CMX_SIZE_4000 = 1024 * 1432;

// SW Kernel reads a few bytes of data for better performance
// 1024 bytes is safe for 40XX+
// 256 bytes is safe for 30XX and 37XX due to 4x smaller vector size
constexpr int64_t MAX_SW_KERNEL_PREFETCH_DATA_SIZE_30XX_37XX = 256;
constexpr int64_t MAX_SW_KERNEL_PREFETCH_DATA_SIZE_40XX = 1024;

// PLL WORKPOINT_CONFIG_MIRROR ADDRESS
constexpr uint32_t NUM_CAPTURED_WORKPOINTS = 2;
constexpr uint32_t HW_PLL_WORKPOINT_ABSOLUTE_ADDR = 0x20082020;
constexpr uint16_t HW_PLL_WORKPOINT_SIZE = 4;

// TODO: E#78647 refactor to use api/vpu_cmx_info_{arch}.h
const EnumMap<VPU::ArchKind, size_t> firmwareVariantCount = {
        {VPU::ArchKind::NPU30XX, 512},
        {VPU::ArchKind::NPU37XX, 256},
        {VPU::ArchKind::NPU40XX, 128},
};

uint16_t getProfWorkloadSize(mlir::ModuleOp module);
//
// Run-time info
//

double getMemoryDerateFactor(IE::MemoryResourceOp mem);
uint32_t getMemoryBandwidth(IE::MemoryResourceOp mem);
int64_t getNumTilesUsed(mlir::ModuleOp module);
int64_t getNumAvailableBarriers(mlir::Operation* parentOp);
size_t getBarrierMaxVariantCount(mlir::Operation* parentOp);
size_t getBarrierMaxVariantSum(mlir::Operation* parentOp);
int64_t getNumberOfIndependentDmaQueues(mlir::Operation* parentOp);

//
// DW Convolution utility
//

mlir::Value alignDepthWiseWeightsTensor(mlir::OpBuilder& builder, mlir::Location loc, mlir::Value origFilter);
mlir::Value getTopBufferOfNCEClusterTiling(mlir::Operation* innerOp, mlir::Value buffer);

// Sparsity utils for optimize-copies pass family
void moveRootAllocBefore(mlir::Operation* root, mlir::Operation* targerOp);
mlir::Type extractDataType(mlir::Type type);
mlir::Type extractDataType(mlir::Value value);

// Return operation which allocate memory buffer. Note, that
// For sparse data rootAlloc look like this:
// val <=== VPUIP.GroupSparseBuffer <-- AllocatorOp
//                                 \<-- [AllocatorOp] # optional sparsity map
template <class AllocatorOp, typename = std::enable_if<std::is_same<AllocatorOp, mlir::memref::AllocOp>::value ||
                                                       std::is_same<AllocatorOp, VPURT::AllocDistributed>::value>>
mlir::Operation* getRootAlloc(mlir::Value val) {
    if (auto rootGroup = val.getDefiningOp<VPUIP::GroupSparseBufferOp>()) {
        if (rootGroup.getData().getDefiningOp<AllocatorOp>() == nullptr) {
            return nullptr;
        }
        // TODO: Handle SET
        const auto sparsityMap = rootGroup.getSparsityMap();
        if (sparsityMap && sparsityMap.getDefiningOp<AllocatorOp>() == nullptr) {
            return nullptr;
        }
        return rootGroup;
    }
    return val.getDefiningOp<AllocatorOp>();
}

mlir::Operation* getRootConst(mlir::Value val);

//
// Unrolling Utilities
//

using outputBuffers = SmallVector<mlir::Value>;
using outputItiBuffers = SmallVector<SmallVector<mlir::Value>>;

SmallVector<mlir::Value> getPerClusterMemoryBuffers(mlir::MLIRContext* ctx, mlir::Location loc, StringRef bufferName,
                                                    mlir::Value operand, int64_t numClusters, mlir::OpBuilder& builder,
                                                    bool allowDiscontinuousBuffers = false);
SmallVector<mlir::Value> getPerClusterComputeBuffers(mlir::MLIRContext* ctx, mlir::Location loc, StringRef bufferName,
                                                     mlir::Value operand, int64_t numClusters, mlir::OpBuilder& builder,
                                                     bool allowDiscontinuousBuffers = false);
SmallVector<mlir::Value> getPerClusterComputeBuffers(mlir::MLIRContext* ctx, mlir::Location loc, StringRef bufferName,
                                                     mlir::Value operand, VPUIP::DistributedBufferType distributedType,
                                                     int64_t numClusters, mlir::OpBuilder& builder,
                                                     bool allowDiscontinuousBuffers = false);
std::pair<outputBuffers, outputItiBuffers> getPerClusterOutputHaloBuffers(mlir::MLIRContext* ctx, mlir::Location loc,
                                                                          StringRef bufferName, mlir::Value operand,
                                                                          int64_t numClusters);
SmallVector<mlir::Value> getPerClusterSWMemoryBuffers(mlir::MLIRContext* ctx, mlir::Location loc, StringRef bufferName,
                                                      VPUIP::SwKernelOp swTaskOp, mlir::Value operand,
                                                      int64_t numClusters, mlir::OpBuilder& builder, Logger log,
                                                      bool allowDiscontinuousBuffers = false);
SmallVector<mlir::Value> getPerClusterSWComputeBuffers(mlir::MLIRContext* ctx, mlir::Location loc, StringRef bufferName,
                                                       VPUIP::SwKernelOp swTaskOp, mlir::Value operand,
                                                       int64_t numClusters, mlir::OpBuilder& builder, Logger log,
                                                       bool allowDiscontinuousBuffers = false);

SmallVector<mlir::Value> getSplitBuffers(mlir::MLIRContext* ctx, mlir::Location loc, StringRef bufferName,
                                         mlir::Value operand, SmallVector<vpux::Shape> shapes,
                                         SmallVector<vpux::Shape> shapeOffsets, int64_t splitNum,
                                         mlir::OpBuilder& builder);

//
// MovePureViewOpBeforeCopy Utilities
//

int64_t getSOHMinimalHeightAlignment(vpux::ShapeRef shape, int64_t numClusters, bool isInputSparse, VPU::ArchKind arch);

int64_t getSpecificAxisFromAttr(mlir::ArrayAttr attr);

template <typename DistType>
VPU::DistributedTensorAttr getSOHDistAttrWithNewShape(mlir::MLIRContext* ctx, DistType origDistType, ShapeRef newShape,
                                                      VPU::ArchKind arch) {
    const auto origDistAttr = origDistType.getDistribution();
    VPUX_THROW_UNLESS(VPU::isSegmentedOverH(origDistAttr), "Input dist type is not SEGMENTED over H");

    const auto origShape = origDistType.getShape();
    if (origShape == newShape) {
        return origDistAttr;
    }

    auto isInputSparse = origDistType.template isa<VPUIP::SparseBufferType>();
    const auto newHeightAlignment =
            VPUIP::getSOHMinimalHeightAlignment(newShape, origDistAttr.getNumClusters().getInt(), isInputSparse, arch);
    const auto newAlignment =
            newHeightAlignment == 1 ? nullptr : getIntArrayAttr(ctx, SmallVector<int64_t>{1, 1, newHeightAlignment, 1});

    if (!VPU::isDistributedAttrWithExplicitShapesAndOffsets(origDistAttr)) {
        return VPU::DistributedTensorAttr::get(ctx, origDistAttr.getMode(), origDistAttr.getNumTiles(),
                                               origDistAttr.getKernel(), origDistAttr.getPads(),
                                               origDistAttr.getStrides(), origDistAttr.getNumClusters(), newAlignment,
                                               origDistAttr.getUniformDistributedSegments(), nullptr, nullptr, nullptr,
                                               nullptr, origDistAttr.getEqualMemoryAndComputeView());
    }

    // When DistributedTensorAttr has explicit per cluster memory/compute shapes, recompute them for the new shape
    // Since this method throws for any distribution mode other than SEGMENTED over H, it is safe to recompute the
    // memory/compute view
    auto optionalPerClusterMemoryShapes = VPU::getPerClusterMemoryShapes(newShape, origDistAttr);
    VPUX_THROW_UNLESS(optionalPerClusterMemoryShapes.has_value(),
                      "Cannot get per cluster memory shapes. Unsupported distribution: {0}", origDistAttr);
    auto perClusterMemoryShapes = vpux::getIntArrayOfArray(ctx, optionalPerClusterMemoryShapes.value());
    auto perClusterMemoryOffsets =
            vpux::getIntArrayOfArray(ctx, VPU::getPerClusterMemoryShapeOffsets(newShape, origDistAttr));
    auto perClusterComputeShapes =
            vpux::getIntArrayOfArray(ctx, VPU::getPerClusterComputeShapes(newShape, origDistAttr));
    auto perClusterComputeOffsets =
            vpux::getIntArrayOfArray(ctx, VPU::getPerClusterComputeShapeOffsets(newShape, origDistAttr));

    return VPU::DistributedTensorAttr::get(
            ctx, origDistAttr.getMode(), origDistAttr.getNumTiles(), origDistAttr.getKernel(), origDistAttr.getPads(),
            origDistAttr.getStrides(), origDistAttr.getNumClusters(), newAlignment,
            origDistAttr.getUniformDistributedSegments(), perClusterComputeShapes, perClusterComputeOffsets,
            perClusterMemoryShapes, perClusterMemoryOffsets, origDistAttr.getEqualMemoryAndComputeView());
}

template <typename DistType>
bool isDistributedCompatibleAfterShapeChangeForViewOps(DistType inDistType, DistType outDistType) {
    const auto inShape = inDistType.getShape();
    const auto outShape = outDistType.getShape();

    if (inShape.totalSize() != outShape.totalSize()) {
        return false;
    }

    if (outDistType.getDistribution().getNumClusters() != inDistType.getDistribution().getNumClusters()) {
        return false;
    }

    auto inMode = inDistType.getDistribution().getMode().getValue();
    auto outMode = outDistType.getDistribution().getMode().getValue();

    auto isFullMemoryMode = [](VPU::DistributionMode mode) {
        return VPU::bitEnumContainsAny(mode, VPU::DistributionMode::DUPLICATED) ||
               VPU::bitEnumContainsAny(mode, VPU::DistributionMode::MULTICASTED);
    };

    if (isFullMemoryMode(inMode) && isFullMemoryMode(outMode)) {
        return true;
    }

    if (inMode != outMode) {
        return false;
    }

    auto inNumTilesAxis = getSpecificAxisFromAttr(inDistType.getDistribution().getNumTiles());
    auto outNumTilesAxis = getSpecificAxisFromAttr(outDistType.getDistribution().getNumTiles());
    if (inNumTilesAxis == -1 || outNumTilesAxis == -1 ||
        (inShape.size() != outShape.size() && inShape[Dim(inNumTilesAxis)] != outShape[Dim(outNumTilesAxis)])) {
        return false;
    }

    // Check per-cluster shape compatible
    const auto inPerClusterShapes = inDistType.getPerClusterMemoryShapes();
    const auto inPerClusterShapeOffsets = inDistType.getPerClusterMemoryShapeOffsets();
    const auto outPerClusterShapes = outDistType.getPerClusterMemoryShapes();
    const auto outPerClusterShapeOffsets = outDistType.getPerClusterMemoryShapeOffsets();
    const auto inStrides = inDistType.getStrides();
    const auto outStrides = outDistType.getStrides();
    const auto calcBufferOffset = [](ShapeRef shapeOffset, Strides strides) {
        Byte bufOffset{0};
        for (size_t axis = 0; axis < strides.size(); axis++) {
            bufOffset += shapeOffset[Dim(axis)] * static_cast<Byte>(strides[Dim(axis)]);
        }
        return bufOffset.count();
    };
    const auto isPerClusterCompatible = [&](ShapeRef inShape, ShapeRef outShape, ShapeRef inShapeOffset,
                                            ShapeRef outShapeOffset) {
        if (inShape.totalSize() != outShape.totalSize()) {
            return false;
        }
        const auto inDataOffset = calcBufferOffset(inShapeOffset, inStrides);
        const auto outDataOffset = calcBufferOffset(outShapeOffset, outStrides);
        return inDataOffset == outDataOffset;
    };
    return llvm::all_of_zip(inPerClusterShapes, outPerClusterShapes, inPerClusterShapeOffsets,
                            outPerClusterShapeOffsets, isPerClusterCompatible);
}

template <typename DistType>
bool isDistributedCompatibleAfterShapeChangeForViewOps(DistType inDistType, ShapeRef shape, DimsOrder outOrder,
                                                       VPU::ArchKind arch) {
    const auto mode = inDistType.getDistribution().getMode().getValue();
    VPUX_THROW_UNLESS(VPU::bitEnumContainsAny(mode, VPU::DistributionMode::DUPLICATED) ||
                              VPU::bitEnumContainsAny(mode, VPU::DistributionMode::SEGMENTED),
                      "Only support DUPLICATED or SEGMENTED mode.");
    const auto inShape = inDistType.getShape();
    if (inShape == shape) {
        return true;
    }
    if (inShape.totalSize() != shape.totalSize()) {
        return false;
    }
    if (VPU::bitEnumContainsAny(mode, VPU::DistributionMode::DUPLICATED) ||
        VPU::bitEnumContainsAny(mode, VPU::DistributionMode::MULTICASTED)) {
        return true;
    }
    // Check both original and new shape are 4D
    if (inShape.size() != shape.size() || inShape.size() != 4) {
        return false;
    }
    // Only NHWC layout is supported in SOH
    if (inDistType.getDimsOrder() != DimsOrder::NHWC) {
        return false;
    }
    // only SOH supported for SEGMENTED
    const auto inDistAttr = inDistType.getDistribution();
    if (!VPU::isSegmentedOverH(inDistAttr)) {
        return false;
    }
    if (shape[Dims4D::Act::H] < inDistAttr.getNumClusters().getInt()) {
        return false;
    }

    const auto isInputSparse = inDistType.template isa<VPUIP::SparseBufferType>();
    auto minHeightAlignment =
            VPUIP::getSOHMinimalHeightAlignment(shape, inDistAttr.getNumClusters().getInt(), isInputSparse, arch);
    if (auto alignment = inDistType.getDistribution().getAlignment()) {
        minHeightAlignment = parseIntArrayAttr<int64_t>(alignment)[Dims4D::Act::H.ind()];
    }
    const auto tilingScheme = parseIntArrayAttr<int64_t>(inDistAttr.getNumTiles());
    if (inDistAttr.getUniformDistributedSegments() == nullptr) {
        auto tiledShapeHeight = divUp(shape[Dims4D::Act::H], tilingScheme[Dims4D::Act::H.ind()]);
        tiledShapeHeight = alignValUp(tiledShapeHeight, minHeightAlignment);
        const auto remainderTileSize =
                shape[Dims4D::Act::H] - tiledShapeHeight * (tilingScheme[Dims4D::Act::H.ind()] - 1);
        if (remainderTileSize <= 0) {
            return false;
        }
    } else {
        auto tiledShapeHeight = shape[Dims4D::Act::H] / tilingScheme[Dims4D::Act::H.ind()];
        tiledShapeHeight = alignValDown(tiledShapeHeight, minHeightAlignment);
        if (tiledShapeHeight <= 0) {
            return false;
        }

        auto remainderCount = shape[Dims4D::Act::H] - tiledShapeHeight * tilingScheme[Dims4D::Act::H.ind()];
        if (remainderCount % minHeightAlignment) {
            return false;
        }
    }

    // Create dist type with new shape
    const auto ctx = inDistType.getContext();
    const auto order = mlir::AffineMapAttr::get(outOrder.toAffineMap(ctx));
    const auto newDistribution = getSOHDistAttrWithNewShape(ctx, inDistType, shape, arch);
    const auto outDistType = DistType::get(ctx, shape.raw(), inDistType.getElementType(), order,
                                           inDistType.getMemSpace(), newDistribution);
    if (newDistribution.getAlignment()) {
        auto newShape = outDistType.getShape();
        auto newAlignment = parseIntArrayAttr<int64_t>(newDistribution.getAlignment());
        if (newShape[Dims4D::Act::H] < newAlignment[Dims4D::Act::H.ind()]) {
            return false;
        }
    }
    return VPUIP::isDistributedCompatibleAfterShapeChangeForViewOps<DistType>(inDistType, outDistType);
}

template <typename DistType>
VPU::DistributedTensorAttr getOverlappedOverHDistAttrWithNewShape(mlir::MLIRContext* ctx, DistType origDistType,
                                                                  ShapeRef newShape) {
    const auto origDistAttr = origDistType.getDistribution();
    VPUX_THROW_UNLESS(VPU::isOverlappedOverH(origDistAttr), "Input dist type is not OVERLAPPED over H");

    const auto origShape = origDistType.getShape();
    if (origShape == newShape) {
        return origDistAttr;
    }

    if (!VPU::isDistributedAttrWithExplicitShapesAndOffsets(origDistAttr)) {
        return VPU::DistributedTensorAttr::get(ctx, origDistAttr.getMode(), origDistAttr.getNumTiles(),
                                               origDistAttr.getKernel(), origDistAttr.getPads(),
                                               origDistAttr.getStrides(), origDistAttr.getNumClusters(), nullptr,
                                               origDistAttr.getUniformDistributedSegments(), nullptr, nullptr, nullptr,
                                               nullptr, origDistAttr.getEqualMemoryAndComputeView());
    }

    // When DistributedTensorAttr has explicit per cluster memory/compute shapes, recompute them for the new shape
    auto perClusterMemoryShapes = vpux::getIntArrayOfArray(
            ctx, VPU::getOverlappedPerClusterNewMemoryShapes(newShape, origShape, origDistAttr));

    auto perClusterMemoryOffsets =
            vpux::getIntArrayOfArray(ctx, VPU::getOverlappedPerClusterNewMemoryShapeOffsets(newShape, origDistAttr));

    auto perClusterComputeShapes =
            vpux::getIntArrayOfArray(ctx, VPU::getPerClusterComputeShapes(newShape, origDistAttr));

    auto perClusterComputeOffsets =
            vpux::getIntArrayOfArray(ctx, VPU::getPerClusterComputeShapeOffsets(newShape, origDistAttr));

    return VPU::DistributedTensorAttr::get(
            ctx, origDistAttr.getMode(), origDistAttr.getNumTiles(), origDistAttr.getKernel(), origDistAttr.getPads(),
            origDistAttr.getStrides(), origDistAttr.getNumClusters(), nullptr,
            origDistAttr.getUniformDistributedSegments(), perClusterComputeShapes, perClusterComputeOffsets,
            perClusterMemoryShapes, perClusterMemoryOffsets, origDistAttr.getEqualMemoryAndComputeView());
}

template <typename DistType>
bool isOverlappedDistributedCompatibleAfterShapeChangeForViewOps(DistType inDistType, ShapeRef shape,
                                                                 DimsOrder outOrder) {
    const auto mode = inDistType.getDistribution().getMode().getValue();

    VPUX_THROW_UNLESS(VPU::bitEnumContainsAny(mode, VPU::DistributionMode::OVERLAPPED),
                      "Only support OVERLAPPED mode.");

    const auto inShape = inDistType.getShape();
    if (inShape == shape) {
        return true;
    }
    if (inShape.totalSize() != shape.totalSize()) {
        return false;
    }

    // Check both original and new shape are 4D
    if (inShape.size() != shape.size() || inShape.size() != 4) {
        return false;
    }
    // Only NHWC layout is supported
    if (inDistType.getDimsOrder() != DimsOrder::NHWC) {
        return false;
    }
    // only Overlapped Over H is supported
    const auto inDistAttr = inDistType.getDistribution();
    if (!VPU::isOverlappedOverH(inDistAttr)) {
        return false;
    }
    if (shape[Dims4D::Act::H] < inDistAttr.getNumClusters().getInt()) {
        return false;
    }

    const auto isSameDimAsClustering = [&]() {
        const auto numTiles = parseIntArrayAttr<int64_t>(inDistAttr.getNumTiles());
        for (auto dim : irange(inShape.size())) {
            if (numTiles[dim] > 1 && inShape.raw()[dim] != shape.raw()[dim]) {
                return true;
            }
        }
        return false;
    };
    // Shape change dim is not on the same dim as tiling
    if (isSameDimAsClustering()) {
        return false;
    }

    // Create dist type with new shape
    const auto ctx = inDistType.getContext();
    const auto order = mlir::AffineMapAttr::get(outOrder.toAffineMap(ctx));
    const auto newDistribution = getOverlappedOverHDistAttrWithNewShape(ctx, inDistType, shape);
    const auto outDistType = DistType::get(ctx, shape.raw(), inDistType.getElementType(), order,
                                           inDistType.getMemSpace(), newDistribution);

    return VPUIP::isDistributedCompatibleAfterShapeChangeForViewOps<DistType>(inDistType, outDistType);
}

mlir::FailureOr<std::pair<int64_t, int64_t>> getDistributedAxesMappingAfterShapeChanged(
        vpux::NDTypeInterface reshapeInType, vpux::NDTypeInterface reshapeOutType,
        VPU::DistributedTensorAttr copyInDistribution, Logger log);
VPU::DistributedTensorAttr changeDistributedAxisOnDistributedTensorAttr(VPU::DistributedTensorAttr inDistribution,
                                                                        int64_t inDistributionAxis,
                                                                        int64_t outDistributionAxis, ShapeRef newShape);

//
// Distributed buffer type compatibility check
//

std::optional<int64_t> getTilingDimIndex(mlir::Type type);
bool isMemoryContiguousWithTiling(VPUIP::DistributedBufferType distributedBufferType);
bool hasDistributedOperand(mlir::Operation* op);

//
// Compressed Convolution utility
//

bool isOnlyPadOverIC(Const::ContentAttr content);
bool canWeightsBeCompressed(VPUIP::NCEClusterTaskOp op);
bool canTilingWeightsBeCompressed(VPUIP::NCEClusterTilingOp op);

// Copy Utilities

bool isChannelOffsetsAndTileDimCompatibleWithClusterCopy(SmallVector<int64_t> offsets, int32_t tileIndexVal,
                                                         VPUIP::DistributedBufferType distributedType);
bool isCopyWithStaticStrides(VPUIP::CopyOp copyOp);
bool isCopyToDDR(VPUIP::CopyOp copyOp);
bool isCopyFromDDR(VPUIP::CopyOp copyOp);
std::optional<vpux::Dim> getCopyDMATilingDim(mlir::Operation* op);
vpux::Dim getCopyDMATilingDimForLargePlaneNum(mlir::Operation* op);
int64_t getStridingLevel(const vpux::NDTypeInterface& type);
int64_t getStridingLevel(const mlir::Value val);
bool hasLegalStridingLevel(mlir::Operation* op);
bool isSplitNeededForLargePlanesNum(const vpux::NDTypeInterface& type, ShapeRef shape, const VPU::ArchKind arch);
bool isSplitNeededForLargePlanesNum(mlir::Operation* op);
int64_t getMaxStridingLevel(const VPU::ArchKind arch);
int64_t getMaxNumberPlanes(const VPU::ArchKind arch);

//
// Operation utility
//
bool isOpOnlySplitOnDim(VPUIP::SubViewOp op, Dim dim);
Byte getRequiredCMXSize(mlir::Operation* op);

//
// PermuteAsNNDMA Utility
//
Shape backInferD2SInputShape(Shape shape, int64_t paddedOC, int64_t paddedIC, int64_t blockSize);

//
// Sparsity utils
//

mlir::Operation* findSETableOp(mlir::Value value);

//
// Eltwise In Place utils
//

bool isEltwiseTheOnlyConsumer(VPUIP::NCEClusterTaskOp clusterTaskOp, mlir::Value inputBuff, bool checkThroughCopyOps,
                              Logger log);

//
// Dynamic shape utils
//

bool hasDynamicShape(mlir::Operation* op);

//
// Dummy Buffer Utils
//
mlir::Value createDummyBuffer(mlir::OpBuilder& builder, mlir::Operation* insertionPoint = nullptr);

//
// Distributed Type utils
//

template <typename DistType>
VPU::DistributedTensorAttr getDistributedAttrAfterShapeCast(VPU::DistributedTypeInterface origDistrType,
                                                            ArrayRef<int64_t> shape, VPU::ArchKind arch) {
    auto distributedType = origDistrType.getDistributedTypes().front().template cast<DistType>();
    auto origDistribution = distributedType.getDistribution();
    const auto mode = origDistribution.getMode().getValue();

    auto ndTypeIf = origDistrType.template cast<NDTypeInterface>();
    const auto origShape = ndTypeIf.getShape().raw();
    auto ctx = origDistrType.getContext();

    const auto isSameDimAsClustering = [&]() {
        const auto numTiles = parseIntArrayAttr<int64_t>(origDistribution.getNumTiles());
        for (auto dim : irange(origShape.size())) {
            if (numTiles[dim] > 1 && origShape[dim] != shape[dim]) {
                return true;
            }
        }
        return false;
    };

    // ShapeCastOp is not a "compute" op, therefore memory and compute shapes are the same
    if (VPU::isDistributedAttrWithExplicitShapesAndOffsets(origDistribution)) {
        VPUX_THROW_WHEN((mode != VPU::DistributionMode::OVERLAPPED) && (mode != VPU::DistributionMode::SEGMENTED) &&
                                !VPU::bitEnumContainsAny(mode, VPU::DistributionMode::DUPLICATED) &&
                                !VPU::bitEnumContainsAny(mode, VPU::DistributionMode::MULTICASTED),
                        "Cannot cast shape with explicit memory/compute shapes/offsets with DistributionMode {0}",
                        origDistribution.getMode());

        if (auto sparseBuff = origDistrType.template dyn_cast<VPUIP::SparseBufferType>()) {
            origDistribution = VPU::getExplicitDistrAttrForActualDataFromSparseType(sparseBuff);
        }

        // When having input broadcasted across all clusters, ShapeCast can set its output as DUPLICATED,
        // regardless of input mode. The reason for that is because ShapeCast is not a compute op and
        // therefore compute shapes/offsets mean nothing to it. Moreover, in cases such as SEG|DUP where
        // a tile axis or alignment exists, the ShapeCast's new shape might not be compatible with those
        // attributes anymore so it would be better to discard them.
        if (VPU::bitEnumContainsAny(mode, VPU::DistributionMode::DUPLICATED) ||
            VPU::bitEnumContainsAny(mode, VPU::DistributionMode::MULTICASTED)) {
            auto duplicatedOutputMode = VPU::DistributionModeAttr::get(ctx, VPU::DistributionMode::DUPLICATED);
            return VPU::getNonOverlappedDistributedAttr(Shape(shape), duplicatedOutputMode, nullptr,
                                                        origDistribution.getNumClusters(), nullptr,
                                                        origDistribution.getUniformDistributedSegments(), ctx);
        }

        const auto numClusters = checked_cast<size_t>(origDistribution.getNumClusters().getInt());

        const auto shapeVec = SmallVector<int64_t>(shape);
        auto perClusterShapes = SmallVector<SmallVector<int64_t>>(numClusters, shapeVec);

        const bool clusteringDimChanges = isSameDimAsClustering();
        if (VPU::isSegmentedOverH(origDistribution)) {
            VPUX_THROW_WHEN(
                    clusteringDimChanges && !VPUIP::isDistributedCompatibleAfterShapeChangeForViewOps(
                                                    distributedType, ShapeRef(shape), ndTypeIf.getDimsOrder(), arch),
                    "Cannot cast shape from '{0}' to '{1}' as clustering", origShape, shape);

            return getSOHDistAttrWithNewShape(ctx, distributedType, ShapeRef(shape), arch);
        }

        if (!clusteringDimChanges && VPU::isOverlappedOverH(origDistribution) &&
            distributedType.getShape().totalSize() == ShapeRef(shape).totalSize() &&
            ndTypeIf.getDimsOrder() == DimsOrder::NHWC) {
            return getOverlappedOverHDistAttrWithNewShape(ctx, distributedType, ShapeRef(shape));
        }

        // SEGMENTED/OVERLAPPED case
        if ((mode == VPU::DistributionMode::OVERLAPPED) || (mode == VPU::DistributionMode::SEGMENTED)) {
            VPUX_THROW_WHEN(clusteringDimChanges,
                            "Cannot cast shape from '{0}' to '{1}' when having explicit memory/compute "
                            "shapes/offsets as segmentation dim changes at output",
                            origShape, shape);

            // Use newly casted shape for all dims except the clustering dim
            const auto origPerClusterShapes = parseIntArrayOfArrayAttr<int64_t>(origDistribution.getMemoryShapes());
            const auto numTiles = parseIntArrayAttr<int64_t>(origDistribution.getNumTiles());
            for (size_t cluster = 0; cluster < numClusters; cluster++) {
                for (size_t dim = 0; dim < shape.size(); dim++) {
                    if (numTiles[dim] != 1) {
                        perClusterShapes[cluster][dim] = origPerClusterShapes[cluster][dim];
                    }
                }
            }
        }

        auto perClusterShapesAttr = vpux::getIntArrayOfArray(ctx, perClusterShapes);
        return VPU::DistributedTensorAttr::get(
                ctx, origDistribution.getMode(), origDistribution.getNumTiles(), origDistribution.getKernel(),
                origDistribution.getPads(), origDistribution.getStrides(), origDistribution.getNumClusters(),
                origDistribution.getAlignment(), origDistribution.getUniformDistributedSegments(), perClusterShapesAttr,
                origDistribution.getMemoryOffsets(), perClusterShapesAttr, origDistribution.getMemoryOffsets(),
                origDistribution.getEqualMemoryAndComputeView());
    }

    auto dataShape = shape;
    if (auto sparseBuff = origDistrType.template dyn_cast<VPUIP::SparseBufferType>()) {
        if (auto seAttr = sparseBuff.getSeAttr()) {
            dataShape = seAttr.backInferInputShape(ShapeRef(shape)).raw();
        }
    }

    if (VPU::bitEnumContainsAny(mode, VPU::DistributionMode::SEGMENTED)) {
        VPUX_THROW_WHEN(
                isSameDimAsClustering() && !VPUIP::isDistributedCompatibleAfterShapeChangeForViewOps<DistType>(
                                                   distributedType, ShapeRef(dataShape), ndTypeIf.getDimsOrder(), arch),
                "Cannot cast shape from '{0}' to '{1}' as clustering", origShape, shape);
    }

    VPUX_THROW_WHEN((mode == VPU::DistributionMode::OVERLAPPED) && isSameDimAsClustering(),
                    "Cannot cast shape from '{0}' to '{1}' as OVERLAPPED clustering; clustering dim changes at output",
                    origShape, shape);

    if (VPU::isSegmentedOverH(origDistribution)) {
        return getSOHDistAttrWithNewShape(ctx, distributedType, ShapeRef(dataShape), arch);
    }

    return origDistribution;
}

//
// SW Kernel prefetching reserved memory utils
//

int64_t getMaximalSWKernelPrefetchDataSize(mlir::ModuleOp module);

}  // namespace VPUIP
}  // namespace vpux