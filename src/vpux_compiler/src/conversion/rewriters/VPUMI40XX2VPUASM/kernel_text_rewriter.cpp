//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/conversion/rewriters/VPUMI40XX2VPUASM/kernel_text_rewriter.hpp"
#include "vpux/compiler/dialect/VPUASM/ops.hpp"

namespace vpux {
namespace vpumi40xx2vpuasm {

mlir::LogicalResult KernelTextRewriter::symbolize(VPUMI40XX::DeclareKernelTextOp op, SymbolMapper&,
                                                  mlir::ConversionPatternRewriter& rewriter) const {
    auto symName = findSym(op).getRootReference();
    rewriter.create<VPUASM::DeclareKernelTextOp>(op.getLoc(), symName, op.getKernelPathAttr());
    rewriter.eraseOp(op);
    return mlir::success();
}

}  // namespace vpumi40xx2vpuasm
}  // namespace vpux