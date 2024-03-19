//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/IE/passes.hpp"
#include "vpux/compiler/dialect/IE/utils/reshape_utils.hpp"
#include "vpux/compiler/utils/permute_utils.hpp"
#include "vpux/compiler/utils/rewriter.hpp"

#include <mlir/IR/IRMapping.h>

using namespace vpux;

namespace {

bool doesVectorContainSubVector(ArrayRef<int64_t> vec, ArrayRef<int64_t> subVec) {
    return std::search(vec.begin(), vec.end(), subVec.begin(), subVec.end()) != vec.end();
}

bool splitAxesAreModifiedIntegratedly(const SmallVector<SmallVector<int64_t>>& dimMapping, ArrayRef<int64_t> permAxis,
                                      DimsOrder permInOrder, vpux::MemShapeRef memShapeRef) {
    SmallVector<SmallVector<int64_t>> splitAxesVec;

    for (size_t inIdx = 0; inIdx < dimMapping.size(); inIdx++) {
        auto mappedDim = dimMapping[inIdx];
        SmallVector<int64_t> splitAxes;
        // mappedDim.size() > 1 indicates a split of input axis
        if (mappedDim.size() > 1) {
            for (size_t mapId = 0; mapId < mappedDim.size(); mapId++) {
                size_t outIdx = mappedDim[mapId];
                auto memDim = permInOrder.toMemDim(Dim(outIdx));
                splitAxes.push_back(memDim.ind());
            }
            splitAxesVec.push_back(splitAxes);
        }
    }

    if (splitAxesVec.empty()) {
        return false;
    }

    const auto nonTrivialMemDimPredicate = [&](const int64_t memDim) -> bool {
        return memShapeRef[MemDim(memDim)] > 1;
    };

    for (auto& splitAxes : splitAxesVec) {
        auto splitAxesRef = ArrayRef(splitAxes);
        const auto nonTrivialMemDims =
                std::count_if(splitAxesRef.begin(), splitAxesRef.end(), nonTrivialMemDimPredicate);
        // Allow the propagation if the data on split axes are moved as a whole.
        // Below cases can meet this requirement.
        // 1.Permutation does not break split axes.
        // 2.Split axes have no more than one non-trivial memDim, it's allowed to break split axes.
        if (!doesVectorContainSubVector(permAxis, splitAxesRef) && (nonTrivialMemDims > 1)) {
            return false;
        }
    }

    return true;
}

SmallVector<int64_t> deduceInAxis(SmallVector<SmallVector<int64_t>> dimMapping, int64_t outAxis) {
    SmallVector<int64_t> inAxis;
    for (size_t inIdx = 0; inIdx < dimMapping.size(); inIdx++) {
        auto mappedDim = dimMapping[inIdx];

        for (size_t mapId = 0; mapId < mappedDim.size(); mapId++) {
            auto outIdx = mappedDim[mapId];
            if (outIdx == outAxis) {
                inAxis.push_back(checked_cast<int64_t>(inIdx));
            }
        }
    }
    return inAxis;
}

bool isSplitOutAxis(SmallVector<SmallVector<int64_t>> dimMapping, int64_t outAxis) {
    for (size_t inIdx = 0; inIdx < dimMapping.size(); inIdx++) {
        auto mappedDim = dimMapping[inIdx];
        // mappedDim.size() > 1 indicates a split of input axis
        if (mappedDim.size() > 1) {
            for (size_t mapId = 0; mapId < mappedDim.size(); mapId++) {
                auto outIdx = mappedDim[mapId];
                if (outIdx == outAxis) {
                    return true;
                }
            }
        }
    }
    return false;
}

mlir::AffineMap calculateNewPermutation(SmallVector<SmallVector<int64_t>>& dimMapping, ArrayRef<int64_t> origPermVec,
                                        DimsOrder affineReshapeInOrder, DimsOrder affineReshapeOutOrder,
                                        vpux::MemShapeRef inMemShapeRef, vpux::MemShapeRef outMemShapeRef, Logger log,
                                        mlir::MLIRContext* ctx) {
    SmallVector<int64_t> inAxesVec;

    for (size_t i = 0; i < origPermVec.size(); i++) {
        // Step 1.1: Map original permutation axes to out dimsMapping axes.
        auto outIdx = affineReshapeOutOrder.toDim(MemDim(origPermVec[i])).ind();
        // Step 1.2: Deduce input dimsMapping axes from out dimsMapping axes.
        auto inIdx = deduceInAxis(dimMapping, checked_cast<int64_t>(outIdx));
        VPUX_THROW_WHEN(inIdx.empty(), "Unexpected dimMapping {0} and input dim index {1}", dimMapping, inIdx);
        // Step 1.3: Save input dimsMapping axes.
        if (isSplitOutAxis(dimMapping, outIdx) && outMemShapeRef[MemDim(origPermVec[i])] == 1 &&
            inMemShapeRef[MemDim(inIdx[0])] != 1) {
            continue;
        }

        for (auto idx : inIdx) {
            auto isAxisAlreadySaved = llvm::find(inAxesVec, idx) != inAxesVec.end();
            if (!isAxisAlreadySaved) {
                inAxesVec.push_back(idx);
            }
        }
    }

    SmallVector<unsigned> newPermVec;
    for (size_t idx = 0; idx < inAxesVec.size(); idx++) {
        // Step 2.1: Map saved input dimsMapping axes to permutation axes.
        auto memDim = affineReshapeInOrder.toMemDim(Dim(inAxesVec[idx]));
        // Step 2.2: Save the permutation axes as new permutation.
        newPermVec.push_back(checked_cast<unsigned>(memDim.ind()));
    }

    log.trace("Got newPermVec {0} converted from inAxesVec {1} with order {2}", newPermVec, inAxesVec,
              affineReshapeInOrder);
    VPUX_THROW_UNLESS(newPermVec.size() == affineReshapeInOrder.numDims(),
                      "New permutation and output dimensions do not match.");

    return mlir::AffineMap::getPermutationMap(ArrayRef(newPermVec), ctx);
}

// Create a new sub graph in below:
//
//      PermuteCastOp
//           |
//      MemPermuteOp
//           |
//       ReshapeOp
//           |
//      PermuteCastOp
//
// to replace the original pattern:
//
//      AffineReshapeOp
//           |
//      MemPermuteOp

mlir::LogicalResult replaceWithNewSubGraph(mlir::Value affineReshape, mlir::Value memPermute, mlir::AffineMap newPerm,
                                           mlir::PatternRewriter& rewriter, Logger log) {
    const auto ctx = rewriter.getContext();
    auto affineReshapeOp = affineReshape.getDefiningOp<IE::AffineReshapeOp>();
    VPUX_THROW_WHEN(affineReshapeOp == nullptr, "Not an AffineReshape operation");
    auto permuteOp = memPermute.getDefiningOp();
    if (!mlir::isa<IE::MemPermuteOp, IE::PermuteQuantizeOp>(permuteOp)) {
        VPUX_THROW("Not a MemPermute or PermuteQuantize operation");
    }

    const auto affineInShape = getShape(affineReshapeOp.getInput());

    // Cast to canonical order for convenience
    auto identityMap = mlir::AffineMap::getMultiDimIdentityMap(checked_cast<unsigned>(affineInShape.size()), ctx);
    auto inputCast = rewriter.create<IE::PermuteCastOp>(permuteOp->getLoc(), affineReshapeOp.getInput(), identityMap,
                                                        identityMap);

    // Create new permute
    const auto newPermAttr = mlir::AffineMapAttr::get(newPerm);
    const auto identityOrderAttr = mlir::AffineMapAttr::get(identityMap);

    auto newPermute = rewriter.create<IE::MemPermuteOp>(permuteOp->getLoc(), inputCast.getOutput(), identityOrderAttr,
                                                        newPermAttr);

    // Reshape to original output shape
    auto outputType = permuteOp->getResult(0).getType().cast<NDTypeInterface>();
    auto outputShape = outputType.getMemShape();
    auto outputShapeAttr = getIntArrayAttr(ctx, outputShape);
    const auto reassociationMap =
            vpux::IE::getReassociationMap(getShape(newPermute.getOutput()).raw(), outputShape.raw());
    if (mlir::failed(reassociationMap)) {
        log.nest().trace("getReassociationMap failed for op {0}", affineReshapeOp.getLoc());
        rewriter.eraseOp(newPermute);
        rewriter.eraseOp(inputCast);
        return mlir::failure();
    }

    const auto reassociationMapAttr = getIntArrayOfArray(ctx, reassociationMap.value());
    auto outputReshape = rewriter.create<IE::AffineReshapeOp>(affineReshapeOp.getLoc(), newPermute.getOutput(),
                                                              reassociationMapAttr, outputShapeAttr);
    inferReturnTypes(outputReshape, InferShapedTypeMode::ELEM_TYPE);

    // Set destination order
    mlir::AffineMap dstOrder;
    if (mlir::isa<IE::MemPermuteOp>(permuteOp)) {
        auto memPermuteOp = mlir::dyn_cast<IE::MemPermuteOp>(permuteOp);
        dstOrder = memPermuteOp.getDstOrder();
    } else if (mlir::isa<IE::PermuteQuantizeOp>(permuteOp)) {
        auto permuteQuantizeOp = mlir::dyn_cast<IE::PermuteQuantizeOp>(permuteOp);
        dstOrder = permuteQuantizeOp.getDstOrder();
    } else {
        VPUX_THROW("Not a MemPermute or PermuteQuantize operation");
    }

    auto newPermuteCast = rewriter.createOrFold<IE::PermuteCastOp>(
            permuteOp->getLoc(), outputReshape->getResult(0), dstOrder,
            mlir::AffineMap::getMultiDimIdentityMap(checked_cast<unsigned>(outputShape.size()), ctx));

    // Replace with new sub graph
    memPermute.replaceAllUsesWith(newPermuteCast);
    rewriter.eraseOp(permuteOp);
    rewriter.eraseOp(affineReshapeOp);
    return mlir::success();
}

//
// OptimizeMemPermute
//

class OptimizeMemPermute final : public mlir::OpRewritePattern<IE::MemPermuteOp> {
public:
    OptimizeMemPermute(mlir::MLIRContext* ctx, Logger log): mlir::OpRewritePattern<IE::MemPermuteOp>(ctx), _log(log) {
        this->setDebugName("OptimizeMemPermute");
    }

private:
    mlir::LogicalResult matchAndRewrite(IE::MemPermuteOp memPermuteOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

// Move MemPermuteOp to the front of AffineReshapeOp.
//
// This conversion can be performed in case the permutation is not breaking split dims.
//
// e.g.
//
// Original pattern: Reshape is before permutation.
//      A x B x C x D   (input mem shape)
//          |  /   /|         |
//          | /   / |   affinReshape  (dim_mapping [0], [1], [1], [2, 3]:
//          |/   /  |         |        means B & C are merged into B', D is split to C' & D')
//      A'x B'x C'x D'  (temp mem shape)
//            |               |
//            |          MemPermute    (perm [0, 2, 3, 1])
//            |               |
//      A'x C'x D'x B'  (output mem shape)
//
// After the pass: Permutation is before reshape.
//
//      A x B x C x D   (input mem shape)
//            |               |
//            |          new MemPermute    (new perm [0, 3, 1, 2])
//            |               |
//      A x D x B x C   (temp mem shape)
//          |\   \  |         |
//          | \   \ |     Reshape
//          |  \   \|         |
//      A'x C'x D'x B'  (output mem shape)
//

mlir::LogicalResult OptimizeMemPermute::matchAndRewrite(IE::MemPermuteOp origOp,
                                                        mlir::PatternRewriter& rewriter) const {
    auto ctx = rewriter.getContext();

    auto affineReshape = origOp.getInput().getDefiningOp<IE::AffineReshapeOp>();
    if (affineReshape == nullptr || !affineReshape->hasOneUse()) {
        return mlir::failure();
    }

    // Check that tensor rank is 4, otherwise compilation fails in later passes
    auto inType = affineReshape.getInput().getType().cast<vpux::NDTypeInterface>();
    auto outType = affineReshape.getOutput().getType().cast<vpux::NDTypeInterface>();
    auto inRank = inType.getRank();
    auto outRank = outType.getRank();
    if (inRank != 4 || outRank != 4) {
        return mlir::failure();
    }

    _log.trace("[{0}] Got '{1}' at '{2}'", getDebugName(), origOp->getName(), origOp->getLoc());

    auto dimMapping = parseIntArrayOfArrayAttr<int64_t>(affineReshape.getDimMapping());
    const auto originPerm = DimsOrder::fromAffineMap(origOp.getMemPerm());
    const auto originPermVec = to_small_vector(originPerm.toPermutation() | transformed([](Dim dim) {
                                                   return checked_cast<int64_t>(dim.ind());
                                               }));
    const auto origPermRef = ArrayRef(originPermVec);
    const auto inMemShape = inType.getMemShape();
    const auto outMemShape = outType.getMemShape();

    if (!splitAxesAreModifiedIntegratedly(dimMapping, origPermRef, outType.getDimsOrder(), outMemShape)) {
        const auto extendReassociationMap =
                vpux::IE::getReassociationMapExtension(inType.getShape().raw(), outType.getShape().raw());
        if (mlir::failed(extendReassociationMap)) {
            return matchFailed(rewriter, origOp, "Failed to get extension map");
        }

        if (!splitAxesAreModifiedIntegratedly(extendReassociationMap.value(), origPermRef, outType.getDimsOrder(),
                                              outMemShape)) {
            return matchFailed(rewriter, origOp, "[{0}]: Swap the split axes", getDebugName());
        }

        dimMapping = extendReassociationMap.value();
        _log.trace("The extended ReassociationMap {0} is used", dimMapping);
    }

    _log.trace("[{0}]: Rewriting {1}", getDebugName(), origOp->getLoc());

    auto newPerm = calculateNewPermutation(dimMapping, origPermRef, inType.getDimsOrder(), outType.getDimsOrder(),
                                           inMemShape, outMemShape, _log, ctx);

    const mlir::OperationName affineReshapeName = affineReshape->getName();
    const mlir::Location affineReshapeLoc = affineReshape->getLoc();
    auto result = replaceWithNewSubGraph(affineReshape.getOutput(), origOp.getOutput(), newPerm, rewriter, _log);
    if (result.succeeded()) {
        _log.nest().trace("[{0}]: Replaced {1} at {2} with new sub graph: newPerm '{3}'", getDebugName(),
                          affineReshapeName, affineReshapeLoc, newPerm);
        return mlir::success();
    } else {
        _log.nest().trace("[{0}]: Failed to replace {1} at {2}", getDebugName(), affineReshapeName, affineReshapeLoc);
        return mlir::failure();
    }
}

//
// PropagatePermuteQuantize
//
// Catch the pattern in below:
//
//      MemPermuteOp
//            |
//      AffineReshape
//            |
//     PermuteQuantizeOp
//            |
//
// If PermuteQuantizeOp only performs permutation, propagate permuteQuantize through AffineReshape
// so that the permutes can be folded or converted into PermuteCast.
//

class PropagatePermuteQuantize final : public mlir::OpRewritePattern<IE::PermuteQuantizeOp> {
public:
    PropagatePermuteQuantize(mlir::MLIRContext* ctx, Logger log)
            : mlir::OpRewritePattern<IE::PermuteQuantizeOp>(ctx), _log(log) {
        this->setDebugName("PropagatePermuteQuantize");
    }

private:
    bool isBeneficialPropagation(IE::MemPermuteOp memPermuteOp, mlir::AffineMap nextPerm) const;
    mlir::LogicalResult matchAndRewrite(IE::PermuteQuantizeOp permuteQuantizeOp,
                                        mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

// Propagation is beneficial in case permutes can be folded or converted into PermuteCast.

bool PropagatePermuteQuantize::isBeneficialPropagation(IE::MemPermuteOp memPermuteOp, mlir::AffineMap nextPerm) const {
    const auto inOrder = DimsOrder::fromValue(memPermuteOp.getInput());
    const auto inShape = getShape(memPermuteOp.getInput());
    const auto inMemShape = inOrder.toMemoryOrder(inShape);

    auto prevMemPerm = memPermuteOp.getMemPerm();
    auto newMemPerm = nextPerm.compose(prevMemPerm);

    return newMemPerm.isIdentity() || isTrivialPermute(inMemShape, newMemPerm);
}

mlir::LogicalResult PropagatePermuteQuantize::matchAndRewrite(IE::PermuteQuantizeOp origOp,
                                                              mlir::PatternRewriter& rewriter) const {
    auto ctx = rewriter.getContext();

    const auto permuteQuantizeInElemType = origOp.getInput().getType().cast<vpux::NDTypeInterface>().getElementType();
    const auto permuteQuantizeOutElemType = origOp.getOutput().getType().cast<vpux::NDTypeInterface>().getElementType();
    if (permuteQuantizeInElemType != permuteQuantizeOutElemType) {
        return mlir::failure();
    }

    // Check PermuteQuantize pads attributes.
    const auto padStart = parseIntArrayAttr<int64_t>(origOp.getPadsBegin());
    const auto padEnd = parseIntArrayAttr<int64_t>(origOp.getPadsEnd());

    const auto nonZeroPadStart = llvm::any_of(padStart, [](auto pad) {
        return pad > 0;
    });
    const auto nonZeroPadEnd = llvm::any_of(padEnd, [](auto pad) {
        return pad > 0;
    });
    if (nonZeroPadStart || nonZeroPadEnd) {
        return mlir::failure();
    }

    auto affineReshape = origOp.getInput().getDefiningOp<IE::AffineReshapeOp>();
    if (affineReshape == nullptr || !affineReshape->hasOneUse()) {
        return mlir::failure();
    }

    auto memPermute = affineReshape.getInput().getDefiningOp<IE::MemPermuteOp>();
    if (memPermute == nullptr || !memPermute->hasOneUse()) {
        return mlir::failure();
    }

    // Check that tensor rank is 4, otherwise compilation fails in later passes
    auto inType = affineReshape.getInput().getType().cast<vpux::NDTypeInterface>();
    auto outType = affineReshape.getOutput().getType().cast<vpux::NDTypeInterface>();
    auto inRank = inType.getRank();
    auto outRank = outType.getRank();
    if (inRank != 4 || outRank != 4) {
        return mlir::failure();
    }

    _log.trace("[{0}] Got '{1}' at '{2}'", getDebugName(), origOp->getName(), origOp->getLoc());

    auto dimMapping = parseIntArrayOfArrayAttr<int64_t>(affineReshape.getDimMapping());
    const auto originPerm = DimsOrder::fromAffineMap(origOp.getMemPerm());
    const auto originPermVec = to_small_vector(originPerm.toPermutation() | transformed([](Dim dim) {
                                                   return checked_cast<int64_t>(dim.ind());
                                               }));
    const auto origPermRef = ArrayRef(originPermVec);
    const auto inMemShape = inType.getMemShape();
    const auto outMemShape = outType.getMemShape();
    if (!splitAxesAreModifiedIntegratedly(dimMapping, origPermRef, outType.getDimsOrder(), outMemShape)) {
        return matchFailed(rewriter, origOp, "[{0}]: Split axes are broken", getDebugName());
    }

    auto newPerm = calculateNewPermutation(dimMapping, origPermRef, inType.getDimsOrder(), outType.getDimsOrder(),
                                           inMemShape, outMemShape, _log, ctx);

    if (!isBeneficialPropagation(memPermute, newPerm)) {
        _log.nest().trace("[{0}]: Propagation is not beneficial at {1}", getDebugName(), origOp->getLoc());
        return mlir::failure();
    }

    _log.trace("[{0}]: Rewriting {1}", getDebugName(), origOp->getLoc());

    const mlir::OperationName affineReshapeName = affineReshape->getName();
    const mlir::Location affineReshapeLoc = affineReshape->getLoc();
    auto result = replaceWithNewSubGraph(affineReshape.getOutput(), origOp.getOutput(), newPerm, rewriter, _log);
    if (result.succeeded()) {
        _log.nest().trace("[{0}]: Replaced {1} at {2} with new sub graph: newPerm '{3}'", getDebugName(),
                          affineReshapeName, affineReshapeLoc, newPerm);
        return mlir::success();
    } else {
        _log.nest().trace("[{0}]: Failed to replace {1} at {2}", getDebugName(), affineReshapeName, affineReshapeLoc);
        return mlir::failure();
    }
}

//
// MoveThroughOp
//
// Catch the pattern in below:
//           Op
//            |
//      MemPermute
//
// Move the MemPermute before Op

template <class ConcreteOp>
class MoveThroughOp final : public mlir::OpRewritePattern<IE::MemPermuteOp> {
public:
    MoveThroughOp(mlir::MLIRContext* ctx, Logger log): mlir::OpRewritePattern<IE::MemPermuteOp>(ctx), _log(log) {
        this->setDebugName("MoveThroughOp");
    }

private:
    mlir::LogicalResult matchAndRewrite(IE::MemPermuteOp memPermuteOp, mlir::PatternRewriter& rewriter) const final;

    bool checkMemPermutePattern(IE::MemPermuteOp memPermuteOp) const;

private:
    Logger _log;
};

template <class ConcreteOp>
mlir::LogicalResult MoveThroughOp<ConcreteOp>::matchAndRewrite(IE::MemPermuteOp origOp,
                                                               mlir::PatternRewriter& rewriter) const {
    auto concreteOp = origOp.getInput().getDefiningOp<ConcreteOp>();

    if (!checkMemPermutePattern(origOp)) {
        return mlir::failure();
    }

    if (concreteOp == nullptr) {
        return mlir::failure();
    }
    const auto originPerm = DimsOrder::fromAffineMap(origOp.getMemPerm());
    const auto originPermVec = to_small_vector(originPerm.toPermutation() | transformed([](Dim dim) {
                                                   return checked_cast<int64_t>(dim.ind());
                                               }));

    auto ctx = origOp->getContext();
    auto inOrder = DimsOrder::fromValue(origOp.getInput()).toAffineMap(ctx);
    auto memPerm = origOp.getMemPerm();
    auto perm = memPerm.compose(inOrder);
    auto outOrder = DimsOrder::fromAffineMap(perm);

    auto operation = concreteOp->getResult(0).getDefiningOp();
    if (auto iface = mlir::dyn_cast<IE::LayoutInfoOpInterface>(operation)) {
        auto orderInfo = iface.getLayoutInfo();
        orderInfo.setInput(0, outOrder);
        iface.inferLayoutInfo(orderInfo, /*seOpsEnabled=*/false, /*seTransposedConvEnabled=*/false);
        if (orderInfo.getInput(0) != outOrder || orderInfo.getOutput(0) != outOrder) {
            return mlir::failure();
        }
    }

    // create new MemPermute which keeps the shape unchanged and adjust the dst order only.
    auto newMemPermute =
            rewriter.create<IE::MemPermuteOp>(origOp->getLoc(), concreteOp->getOperand(0), perm, origOp.getMemPerm());
    mlir::IRMapping mapper;
    mapper.map(concreteOp->getOperand(0), newMemPermute.getOutput());
    mlir::Operation* newOp = rewriter.clone(*concreteOp, mapper);
    auto newOutput = newOp->getResult(0);
    newOutput.setType(newMemPermute.getOutput().getType());

    auto rank = getShape(newMemPermute.getOutput()).size();
    auto newPermuteCast = rewriter.createOrFold<IE::PermuteCastOp>(
            origOp->getLoc(), newOp->getResult(0), origOp.getDstOrder(),
            mlir::AffineMap::getMultiDimIdentityMap(checked_cast<unsigned>(rank), ctx));
    rewriter.replaceOp(origOp, newPermuteCast);
    rewriter.eraseOp(concreteOp);
    return mlir::success();
}

template <class ConcreteOp>
bool MoveThroughOp<ConcreteOp>::checkMemPermutePattern(IE::MemPermuteOp memPermuteOp) const {
    // Check pattern Op -> MemPermuteOp.
    auto op = memPermuteOp.getInput().getDefiningOp();
    if (!mlir::isa_and_nonnull<ConcreteOp>(op)) {
        return false;
    }
    return op->hasOneUse();
}

//
// MoveThroughConcat
//
// Catch below pattern
//           Op1           Op2
//            |             |
//       MemPermute    MemPermute
//               \      /
//                Concat
//                   |
//              MemPermute
//
// Move the child MemPermute from Concat output to inputs, so that it can be fused into original input MemPermute

class MoveThroughConcat final : public mlir::OpRewritePattern<IE::ConcatOp> {
public:
    MoveThroughConcat(mlir::MLIRContext* ctx, Logger log): mlir::OpRewritePattern<IE::ConcatOp>(ctx), _log(log) {
        this->setDebugName("MoveThroughConcat");
    }

private:
    mlir::LogicalResult matchAndRewrite(IE::ConcatOp origOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

mlir::LogicalResult MoveThroughConcat::matchAndRewrite(IE::ConcatOp origOp, mlir::PatternRewriter& rewriter) const {
    if (!origOp->hasOneUse()) {
        return mlir::failure();
    }

    auto childMemPermute = mlir::dyn_cast<IE::MemPermuteOp>(*origOp->getUsers().begin());
    if (childMemPermute == nullptr) {
        return mlir::failure();
    }

    const auto permutationMap = childMemPermute.getMemPerm();

    // Propagation is beneficial when:
    // 1. input is MemPermute, then child MemPermute can be fused, or
    // 2. new MemPermute would be a PermuteCast after propagation.
    auto isBeneficialPropagation = [&](mlir::Value input) {
        auto inputPermute = input.getDefiningOp<IE::MemPermuteOp>();
        if (inputPermute != nullptr) {
            return true;
        }

        auto inputType = input.getType().cast<NDTypeInterface>();
        auto inputMemShape = inputType.getMemShape();
        return isTrivialPermute(inputMemShape, permutationMap);
    };

    if (!llvm::all_of(origOp.getOperands(), isBeneficialPropagation)) {
        _log.nest().trace("[{0}] Propagation is not beneficial for {1} at {2}", getDebugName(), origOp->getName(),
                          origOp->getLoc());
        return mlir::failure();
    }

    _log.trace("[{0}] Got '{1}' at '{2}'", getDebugName(), origOp->getName(), origOp->getLoc());

    const auto ctx = rewriter.getContext();
    const auto origConcatType = origOp.getOutput().getType().dyn_cast<NDTypeInterface>();
    const auto permutation = DimsOrder::fromAffineMap(permutationMap);

    const auto origConcatOrder = origConcatType.getDimsOrder();
    const auto newConcatOrder = applyPermutation(origConcatOrder, permutation);
    const auto newConcatOrderMap = newConcatOrder.toAffineMap(ctx);

    SmallVector<mlir::Value> newInputs;
    for (const auto& input : origOp.getOperands()) {
        // Create MemPermute for input
        auto newPermute = rewriter.create<IE::MemPermuteOp>(childMemPermute->getLoc(), input,
                                                            mlir::AffineMapAttr::get(newConcatOrderMap),
                                                            childMemPermute.getMemPermAttr());
        newInputs.push_back(newPermute.getOutput());
    }

    const auto newConcatType = origConcatType.changeDimsOrder(newConcatOrder);

    // Create new ConcatOp
    auto perAxisAttr = origOp.getPerAxisAttr();
    auto staticOffsets = origOp.getStaticOffsetsAttr();
    auto newConcat =
            rewriter.create<IE::ConcatOp>(origOp->getLoc(), newConcatType, newInputs, perAxisAttr, staticOffsets);

    // Create PermuteCast to dst order
    const auto dstOrderMap = childMemPermute.getDstOrder();
    const auto dstOrder = DimsOrder::fromAffineMap(dstOrderMap);
    auto newPermuteCast =
            rewriter.createOrFold<IE::PermuteCastOp>(childMemPermute->getLoc(), newConcat.getOutput(), dstOrderMap,
                                                     mlir::AffineMap::getMultiDimIdentityMap(dstOrder.numDims(), ctx));

    _log.nest().trace("[{0}] Replace child MemPermute for {1} at {2}", getDebugName(), origOp->getName(),
                      origOp->getLoc());

    rewriter.replaceOp(childMemPermute, newPermuteCast);
    return mlir::success();
}

//
// PropagateMemPermuteBeforeOpPass
//

class PropagateMemPermuteBeforeOpPass final :
        public IE::PropagateMemPermuteBeforeOpBase<PropagateMemPermuteBeforeOpPass> {
public:
    explicit PropagateMemPermuteBeforeOpPass(Logger log): _log(log) {
        _log.setName(Base::getArgumentName());
    }

private:
    void safeRunOnFunc() final;

private:
    Logger _log;
};

void PropagateMemPermuteBeforeOpPass::safeRunOnFunc() {
    auto& ctx = getContext();
    auto func = getOperation();

    mlir::RewritePatternSet patterns(&ctx);
    patterns.add<OptimizeMemPermute>(&ctx, _log);
    patterns.add<PropagatePermuteQuantize>(&ctx, _log);
    patterns.add<MoveThroughOp<IE::MVNOp>>(&ctx, _log);
    patterns.add<MoveThroughOp<IE::GeluOp>>(&ctx, _log);
    patterns.add<MoveThroughConcat>(&ctx, _log);
    IE::ReshapeOp::getCanonicalizationPatterns(patterns, &ctx);
    IE::MemPermuteOp::getCanonicalizationPatterns(patterns, &ctx);

    if (mlir::failed(mlir::applyPatternsAndFoldGreedily(func, std::move(patterns), getDefaultGreedyRewriteConfig()))) {
        signalPassFailure();
    }
}

}  // namespace

std::unique_ptr<mlir::Pass> vpux::IE::createPropagateMemPermuteBeforeOpPass(Logger log) {
    return std::make_unique<PropagateMemPermuteBeforeOpPass>(log);
}
