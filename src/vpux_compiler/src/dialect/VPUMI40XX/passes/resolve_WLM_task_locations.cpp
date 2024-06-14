//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/IE/utils/resources.hpp"
#include "vpux/compiler/dialect/VPUMI40XX/passes.hpp"
#include "vpux/compiler/dialect/VPUMI40XX/utils.hpp"

#include <npu_40xx_nnrt.hpp>

using namespace vpux;

namespace {

class ResolveWLMTaskLocationPass final : public VPUMI40XX::ResolveWLMTaskLocationBase<ResolveWLMTaskLocationPass> {
public:
    explicit ResolveWLMTaskLocationPass(Logger log) {
        Base::initLogger(log, Base::getArgumentName());
    }

private:
    void safeRunOnFunc() final;
};

void ResolveWLMTaskLocationPass::safeRunOnFunc() {
    auto netFunc = getOperation();
    auto mpi = VPUMI40XX::getMPI(netFunc);

    const llvm::DenseMap<VPURegMapped::TaskType, size_t> sizes = {
            {VPURegMapped::TaskType::DPUInvariant, npu40xx::nn_public::VPU_INVARIANT_COUNT / 2},
            {VPURegMapped::TaskType::DPUVariant, npu40xx::nn_public::VPU_VARIANT_COUNT / 2},
            {VPURegMapped::TaskType::ActKernelInvocation, npu40xx::nn_public::VPU_KERNEL_INVO_COUNT / 2},
            {VPURegMapped::TaskType::ActKernelRange, npu40xx::nn_public::VPU_KERNEL_RANGE_COUNT / 2}};

    auto getSize = [&sizes](VPURegMapped::TaskType type) -> size_t {
        auto mapIt = sizes.find(type);
        VPUX_THROW_WHEN(mapIt == sizes.end(), "Task Type not registered");

        return mapIt->getSecond();
    };

    auto populate = [&netFunc](mlir::OpBuilder builder, VPURegMapped::TaskType taskType, size_t tileIdx, size_t count) {
        std::vector<mlir::Value> taskBuffers;
        for (size_t i = 0; i < count; ++i) {
            auto index = VPURegMapped::IndexType::get(builder.getContext(), static_cast<uint32_t>(tileIdx), 0,
                                                      static_cast<uint32_t>(i));
            auto taskBuffer = builder.create<VPURegMapped::DeclareTaskBufferOp>(netFunc.getLoc(), index, taskType);
            taskBuffers.push_back(taskBuffer.getResult());
        }
        return taskBuffers;
    };

    auto parentModule = netFunc.getOperation()->getParentOfType<mlir::ModuleOp>();
    const auto tilesCount = IE::getTileExecutor(parentModule).getCount();

    auto solveGroupOps = [&mpi, &populate, &getSize](VPURegMapped::TaskType taskType, size_t tileIdx) -> void {
        auto listHead = mpi.getListHead(taskType, tileIdx);
        if (!listHead)
            return;

        auto groupOp = mlir::cast<VPURegMapped::ExecutionGroupOp>(listHead.getDefiningOp());

        mlir::OpBuilder builder(listHead.getDefiningOp());
        auto groupSize = getSize(taskType);

        auto taskBuffers = populate(builder, taskType, tileIdx, groupSize * 2);

        size_t groupCtr = 0;

        while (groupOp) {
            size_t taskCtr = 0;
            for (auto execTaskOp : groupOp.getOps<VPURegMapped::TaskOpInterface>()) {
                if (execTaskOp.getTaskType() != taskType)
                    continue;
                execTaskOp.setTaskLocation(taskBuffers[groupCtr + taskCtr]);
                taskCtr++;
            }

            groupCtr = (groupCtr + groupSize) % (groupSize * 2);
            groupOp = VPUMI40XX::getNextGroup(groupOp);
        }
    };

    for (int64_t tileIdx = 0; tileIdx < tilesCount; tileIdx++) {
        solveGroupOps(VPURegMapped::TaskType::DPUInvariant, tileIdx);
        solveGroupOps(VPURegMapped::TaskType::DPUVariant, tileIdx);
        solveGroupOps(VPURegMapped::TaskType::ActKernelInvocation, tileIdx);
        solveGroupOps(VPURegMapped::TaskType::ActKernelRange, tileIdx);
    }
}

}  // namespace

std::unique_ptr<mlir::Pass> VPUMI40XX::createResolveWLMTaskLocationPass(Logger log) {
    return std::make_unique<ResolveWLMTaskLocationPass>(log);
}