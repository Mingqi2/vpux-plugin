//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/core/barrier_info.hpp"
#include "vpux/compiler/core/cycle_cost_info.hpp"
#include "vpux/compiler/dialect/VPURT/inference_execution_simulator.hpp"
#include "vpux/compiler/dialect/VPURT/ops.hpp"
#include "vpux/compiler/dialect/VPURT/passes.hpp"
#include "vpux/compiler/dialect/VPURT/task.hpp"
#include "vpux/compiler/dialect/VPURT/utils/barrier_legalization_utils.hpp"

#include <llvm/ADT/SetOperations.h>

using namespace vpux;
namespace {

// resolve out of order dependencies for tasks in the same FIFO by linking task's update barrier(s)
// to any next task's (in the same FIFO) update barrier(s) that is/are earlier than current update barrier(s)
// re-link DMAs in FIFO: DMA-1 -> DMA-2 -> DMA-3 with following barriers:
/*
           DMA-1                 DMA-1
    DMA-2    |            DMA-2   |
      |      |                \  /
    Bar0     |                Bar0
      |      |       =>        |
    DMA-3    |               DMA-3
         \  /                  |
         Bar1                 Bar1
*/
void resolveOutOfOrderDependencies(const std::map<VPURT::TaskQueueType, SmallVector<uint32_t>>& dmaTaskOpQueues,
                                   BarrierInfo& barrierInfo) {
    for (const auto& entry : dmaTaskOpQueues) {
        // operate per queue
        const auto& dmaQueue = entry.second;

        std::set<size_t> nextUpdateBarriers;
        for (const auto& task : dmaQueue | reversed) {
            const auto& updateBarriers = barrierInfo.getUpdateBarriers(task);
            if (updateBarriers.empty()) {
                continue;
            }
            if (!barrierInfo.getWaitBarriers(task).empty()) {
                nextUpdateBarriers.insert(updateBarriers.begin(), updateBarriers.end());
                continue;
            }

            // link earlier next update barriers
            const auto minUpdateBarrier = VPURT::getMinEntry(updateBarriers);
            for (const auto& nextUpdate : nextUpdateBarriers) {
                if (nextUpdate >= minUpdateBarrier) {
                    break;
                }

                barrierInfo.addProducer(barrierInfo.getBarrierOpAtIndex(nextUpdate), task);
            }

            nextUpdateBarriers.insert(updateBarriers.begin(), updateBarriers.end());
        }
    }

    barrierInfo.optimizeBarriers();
}

// link tasks to barriers and create legal variant batches if needed
void linkTasksToBarriers(const BarrierInfo::TaskSet& tasksToAdd, const BarrierInfo::TaskSet& newBarriers,
                         bool waitBarriers, size_t legalVariantCount, BarrierInfo& barrierInfo) {
    mlir::OpBuilder builder(barrierInfo.getBarrierOpAtIndex(*newBarriers.begin()));
    BarrierInfo::TaskSet newBarrierBatch;

    for (const auto& barrierIdn : newBarriers) {
        BarrierInfo::TaskSet barrierTasks;
        if (waitBarriers) {
            barrierTasks = barrierInfo.getBarrierConsumers(barrierIdn);
        } else {
            barrierTasks = barrierInfo.getBarrierProducers(barrierIdn);
        }

        llvm::set_union(barrierTasks, tasksToAdd);
        auto batches = barrierInfo.createLegalVariantBatches(barrierTasks, legalVariantCount);
        if (batches.size() > 1) {
            auto insertionPoint = barrierInfo.getBarrierOpAtIndex(barrierIdn);
            BarrierInfo::TaskSet prevBatch;
            if (waitBarriers) {
                prevBatch = barrierInfo.getBarrierProducers(barrierIdn);
            } else {
                batches.push_back(barrierInfo.getBarrierConsumers(barrierIdn));
            }
            for (const auto& batch : batches) {
                if (!prevBatch.empty()) {
                    builder.setInsertionPoint(insertionPoint);
                    const auto newBarrier = builder.create<VPURT::DeclareVirtualBarrierOp>(insertionPoint->getLoc());
                    barrierInfo.addNewBarrier(newBarrier);
                    const auto newBarrierIdn = barrierInfo.getIndex(newBarrier);
                    newBarrierBatch.insert(newBarrierIdn);
                    barrierInfo.addProducers(newBarrierIdn, prevBatch);
                    barrierInfo.addConsumers(newBarrierIdn, batch);
                }
                prevBatch = batch;
            }
            barrierInfo.resetBarrier(barrierIdn);
        } else if (waitBarriers) {
            barrierInfo.addConsumers(barrierIdn, tasksToAdd);
            newBarrierBatch.insert(barrierIdn);
        } else {
            barrierInfo.addProducers(barrierIdn, tasksToAdd);
            newBarrierBatch.insert(barrierIdn);
        }
    }
}

// eliminate tasks (if possible) not controlled by barriers, by sharing wait / update barriers of
// parent / child DMA to create a schedule fully managed by barriers which simplifies runtime handling
// 1) update barriers: find task(s) without update barrier, find next task (on the same FIFO) with
// update barrier(s) link update barrier(s) to all tasks that don't have update barrier
// 2) wait barriers: find task(s) without wait barrier, find previous task (on the same FIFO) with
// wait barrier(s) link wait barrier(s) to all tasks that don't have wait barrier
/*
    Bar0
      |             Bar0
    DMA-0            |
      |     =>  DMA-0 DMA-1
    DMA-1            |
      |             Bar1
    Bar1
*/
void shareWaitAndUpdateBarriers(const std::map<VPURT::TaskQueueType, SmallVector<uint32_t>>& dmaTaskOpQueues,
                                size_t legalVariantCount, BarrierInfo& barrierInfo) {
    for (const auto& entry : dmaTaskOpQueues) {
        // operate per queue
        const auto& dmaQueue = entry.second;
        // handle update barriers
        BarrierInfo::TaskSet tasksNoUpdateBarrier;
        for (const auto& taskInd : dmaQueue) {
            const auto& taskUpdateBarriers = barrierInfo.getUpdateBarriers(taskInd);
            if (taskUpdateBarriers.empty()) {
                tasksNoUpdateBarrier.insert(taskInd);
            } else if (!tasksNoUpdateBarrier.empty()) {
                linkTasksToBarriers(tasksNoUpdateBarrier, taskUpdateBarriers, false, legalVariantCount, barrierInfo);
                tasksNoUpdateBarrier.clear();
            }
        }

        // handle wait barriers
        BarrierInfo::TaskSet tasksNoWaitBarrier;
        for (const auto& taskInd : dmaQueue | reversed) {
            const auto& taskWaitBarriers = barrierInfo.getWaitBarriers(taskInd);
            if (taskWaitBarriers.empty()) {
                tasksNoWaitBarrier.insert(taskInd);
            } else if (!tasksNoWaitBarrier.empty()) {
                linkTasksToBarriers(tasksNoWaitBarrier, taskWaitBarriers, true, legalVariantCount, barrierInfo);
                tasksNoWaitBarrier.clear();
            }
        }
    }
}

// check if barrier is waiting for / updating tasks only on the same queue
bool taskQueueIsBottleneck(size_t taskInd, size_t barrierInd, bool producers, BarrierInfo& barrierInfo) {
    BarrierInfo::TaskSet tasks;
    if (producers) {
        tasks = barrierInfo.getBarrierProducers(barrierInd);
    } else {
        tasks = barrierInfo.getBarrierConsumers(barrierInd);
    }

    const auto taskQueueType = VPURT::getTaskQueueType(barrierInfo.getTaskOpAtIndex(taskInd), false);
    for (const auto& task : tasks) {
        if (taskQueueType != VPURT::getTaskQueueType(barrierInfo.getTaskOpAtIndex(task), false)) {
            return false;
        }

        // would indicate a cycle
        if ((producers && task >= taskInd) || (!producers && taskInd >= task)) {
            return false;
        }
    }

    return true;
}

// find barriers between max and min barrier
BarrierInfo::TaskSet findValidBarrierCandidates(size_t maxWaitBarrier, size_t minUpdateBarrier,
                                                const BarrierInfo::TaskSet& maybeNewBarriers) {
    BarrierInfo::TaskSet intermediateBarriers;
    for (const auto& barrierIdn : maybeNewBarriers) {
        if (barrierIdn <= maxWaitBarrier || barrierIdn >= minUpdateBarrier) {
            continue;
        }

        intermediateBarriers.insert(barrierIdn);
    }

    return intermediateBarriers;
}

void linkNewBarriers(size_t taskInd, const BarrierInfo::TaskSet& newBarriers, bool producer, BarrierInfo& barrierInfo) {
    for (const auto& newBarrierInd : newBarriers) {
        if (producer) {
            barrierInfo.addProducer(barrierInfo.getBarrierOpAtIndex(newBarrierInd), taskInd);
        } else {
            barrierInfo.addConsumer(barrierInfo.getBarrierOpAtIndex(newBarrierInd), taskInd);
        }
    }
}

bool taskCanBeLinkedToNewUpdateBarrier(size_t taskInd, size_t barrierInd,
                                       std::map<size_t, VPURT::TaskConfig>& taskIndMap, BarrierInfo& barrierInfo) {
    // check if only consumers on same queue
    if (taskQueueIsBottleneck(taskInd, barrierInd, false, barrierInfo)) {
        return true;
    }

    for (const auto& producerInd : barrierInfo.getBarrierProducers(barrierInd)) {
        // avoid comparing invalid costs
        if (taskIndMap[producerInd].cycleCost == 1) {
            return false;
        }
    }

    const auto taskCycleEnd = taskIndMap[taskInd].cycleStart + taskIndMap[taskInd].cycleCost;
    for (const auto& consumerInd : barrierInfo.getBarrierConsumers(barrierInd)) {
        if (taskCycleEnd > taskIndMap[consumerInd].cycleStart) {
            return false;
        }
    }

    return true;
}

bool taskCanBeLinkedToNewWaitBarrier(size_t taskInd, size_t barrierInd, std::map<size_t, VPURT::TaskConfig>& taskIndMap,
                                     BarrierInfo& barrierInfo) {
    // check if only consumers on same queue
    if (taskQueueIsBottleneck(taskInd, barrierInd, true, barrierInfo)) {
        return true;
    }

    const auto taskCycleBegin = taskIndMap[taskInd].cycleStart;
    for (const auto& producerInd : barrierInfo.getBarrierProducers(barrierInd)) {
        // avoid comparing invalid costs
        if (taskIndMap[producerInd].cycleCost == 1) {
            return false;
        }
        if (taskCycleBegin <= taskIndMap[producerInd].cycleStart + taskIndMap[producerInd].cycleCost) {
            return false;
        }
    }

    return true;
}

// reduce parallel overlapping control flows for FIFO/Queue
// 1) update barriers: for any task's update barrier, find next task with earlier update barriers
// try to link earlier update barriers to current task.
// 2) wait barriers: for any task's wait barrier, find previous task with later wait barriers
// try to link later wait barriers to current task.
// When linking tasks check if performance will not be affected by:
// - barrier is fully dependent on tasks from the same FIFO/Queue
// - barrier producer/consumer simulated cycles will not cause a performance regression
/*
            Bar0                         Bar0
             |   \                        |  \
            ...    \                     ...  DMA-0
             |       \                    |  /
            Bar1   DMA-0                 Bar1
          /  |       /                 /  |
        /   ...    /                 /   ...
      /      |   /         =>      /      |
    DMA-1   Bar2                 DMA-1   Bar2
      \      |                     \      |
        \   ...                      \   ...
          \  |                         \  |
            Bar3                         Bar3
*/
void reduceParallelControlFlowsForQueue(VPURT::TaskConfigVec& ops, std::map<size_t, VPURT::TaskConfig>& taskIndMap,
                                        BarrierInfo& barrierInfo) {
    auto frontTask = ops.begin();

    // handle update barriers
    while (frontTask != ops.end()) {
        const auto frontTaskInd = barrierInfo.getIndex(frontTask->taskOp);
        const auto minUpdateBarrier = VPURT::getMinEntry(barrierInfo.getUpdateBarriers(frontTaskInd));
        if (minUpdateBarrier == std::numeric_limits<size_t>::min()) {
            ++frontTask;
            continue;
        }

        const auto maxWaitBarrier = VPURT::getMaxEntry(barrierInfo.getWaitBarriers(frontTaskInd));
        if (maxWaitBarrier + 1 == minUpdateBarrier) {
            ++frontTask;
            continue;
        }

        // find next tasks wait barrier
        BarrierInfo::TaskSet intermediateBarriers;
        auto nextTask = frontTask;
        ++nextTask;
        while (nextTask != ops.end()) {
            const auto nextTaskInd = barrierInfo.getIndex(nextTask->taskOp);
            const auto& nextWaitBarriers = barrierInfo.getWaitBarriers(nextTaskInd);
            // stop when task max wait barrier > minUpdateBarrier
            if (VPURT::getMaxEntry(nextWaitBarriers) > minUpdateBarrier) {
                break;
            }
            llvm::set_union(intermediateBarriers,
                            findValidBarrierCandidates(maxWaitBarrier, minUpdateBarrier, nextWaitBarriers));
            ++nextTask;
        }

        BarrierInfo::TaskSet newUpdateBarriers;
        for (const auto& barrier : intermediateBarriers) {
            // check if task can be linked
            if (!taskCanBeLinkedToNewUpdateBarrier(frontTaskInd, barrier, taskIndMap, barrierInfo)) {
                continue;
            }
            newUpdateBarriers.insert(barrier);
        }

        // add new barriers
        linkNewBarriers(frontTaskInd, newUpdateBarriers, true, barrierInfo);
        ++frontTask;
    }

    // handle wait barriers
    auto frontTaskRev = ops.begin();
    ++frontTaskRev;
    while (frontTaskRev != ops.end()) {
        const auto frontTaskRevInd = barrierInfo.getIndex(frontTaskRev->taskOp);
        const auto maxWaitBarrier = VPURT::getMaxEntry(barrierInfo.getWaitBarriers(frontTaskRevInd));
        if (maxWaitBarrier == std::numeric_limits<size_t>::max()) {
            ++frontTaskRev;
            continue;
        }

        const auto minUpdateBarrier = VPURT::getMinEntry(barrierInfo.getUpdateBarriers(frontTaskRevInd));
        if (minUpdateBarrier == maxWaitBarrier + 1) {
            ++frontTaskRev;
            continue;
        }

        // find prev tasks wait barrier
        BarrierInfo::TaskSet intermediateBarriers;
        auto prevTask = frontTaskRev;
        do {
            --prevTask;
            const auto prevTaskInd = barrierInfo.getIndex(prevTask->taskOp);
            const auto& prevUpdateBarriers = barrierInfo.getUpdateBarriers(prevTaskInd);
            // stop when task min update barrier < maxWaitBarrier
            if (VPURT::getMinEntry(prevUpdateBarriers) < maxWaitBarrier) {
                break;
            }
            llvm::set_union(intermediateBarriers,
                            findValidBarrierCandidates(maxWaitBarrier, minUpdateBarrier, prevUpdateBarriers));
        } while (prevTask != ops.begin());

        BarrierInfo::TaskSet newWaitBarriers;
        for (const auto& barrier : intermediateBarriers) {
            // check if task can be linked
            if (!taskCanBeLinkedToNewWaitBarrier(frontTaskRevInd, barrier, taskIndMap, barrierInfo)) {
                continue;
            }
            newWaitBarriers.insert(barrier);
        }

        // add new barriers
        linkNewBarriers(frontTaskRevInd, newWaitBarriers, false, barrierInfo);

        ++frontTaskRev;
    }
}

void reduceParallelControlFlows(std::map<VPURT::TaskQueueType, VPURT::TaskConfigVec> taskQueueMap,
                                BarrierInfo& barrierInfo) {
    // create BarrierInfo::index -> TaskConfig mapping
    std::map<size_t, VPURT::TaskConfig> taskIndMap;
    for (auto& entry : taskQueueMap) {
        for (auto& taskConfig : entry.second) {
            taskIndMap[barrierInfo.getIndex(taskConfig.taskOp)] = taskConfig;
        }
    }

    for (auto& entry : taskQueueMap) {
        if (entry.first.type != VPU::ExecutorKind::DMA_NN) {
            continue;
        }

        // reduce per FIFO/Queue
        reduceParallelControlFlowsForQueue(entry.second, taskIndMap, barrierInfo);
    }
}

//
//  SimplifySchedulePass
//

class SimplifySchedulePass final : public VPURT::SimplifyScheduleBase<SimplifySchedulePass> {
public:
    explicit SimplifySchedulePass(const bool shareWaitAndUpdateBarriersFlag, const bool reduceParallelControlFlowsFlag,
                                  Logger log)
            : _shareWaitAndUpdateBarriers(shareWaitAndUpdateBarriersFlag),
              _reduceParallelControlFlows(reduceParallelControlFlowsFlag) {
        Base::initLogger(log, Base::getArgumentName());
    }

private:
    void safeRunOnFunc() final;

private:
    bool _shareWaitAndUpdateBarriers{true};
    bool _reduceParallelControlFlows{true};
};

void SimplifySchedulePass::safeRunOnFunc() {
    if (!_shareWaitAndUpdateBarriers) {
        return;
    }

    auto funcOp = getOperation();
    auto& barrierInfo = getAnalysis<BarrierInfo>();
    auto& cycleCostInfo = getAnalysis<CycleCostInfo>();
    const auto legalVariantCount = VPUIP::getBarrierMaxVariantCount(funcOp) / 2;

    // order tasks and barriers
    VPURT::orderExecutionTasksAndBarriers(funcOp, barrierInfo);

    // 1. avoid out of order dependencies
    auto dmaTaskOpQueues = VPURT::getTaskOpQueues(funcOp, barrierInfo, VPU::ExecutorKind::DMA_NN);
    // inject dependencies where needed
    resolveOutOfOrderDependencies(dmaTaskOpQueues, barrierInfo);
    // re-order execution
    VPURT::orderExecutionTasksAndBarriers(funcOp, barrierInfo);

    // 2. make execution fully controlled by barriers
    shareWaitAndUpdateBarriers(dmaTaskOpQueues, legalVariantCount, barrierInfo);
    // re-order execution
    VPURT::orderExecutionTasksAndBarriers(funcOp, barrierInfo);

    if (_reduceParallelControlFlows) {
        // run simulation to get operation cycles
        VPURT::InferenceExecutionSimulator infSim(_log, funcOp, cycleCostInfo);
        infSim.runSim();

        // 3. reduce parallel control flows based on cycles
        reduceParallelControlFlows(infSim.getQueueTaskMap(), barrierInfo);

        // re-order execution
        VPURT::orderExecutionTasksAndBarriers(funcOp, barrierInfo);

        // optimize
        barrierInfo.optimizeBarriers();
        barrierInfo.updateIR();
    }

    barrierInfo.clearAttributes();
    VPURT::postProcessBarrierOps(funcOp);
}

}  // namespace

//
// createSimplifySchedulePass
//

std::unique_ptr<mlir::Pass> vpux::VPURT::createSimplifySchedulePass(const bool shareWaitAndUpdateBarriersFlag,
                                                                    const bool reduceParallelControlFlowsFlag,
                                                                    Logger log) {
    return std::make_unique<SimplifySchedulePass>(shareWaitAndUpdateBarriersFlag, reduceParallelControlFlowsFlag, log);
}
