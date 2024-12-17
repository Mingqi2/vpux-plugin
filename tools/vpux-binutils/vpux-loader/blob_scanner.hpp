//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#pragma once

#include <string_view>
#include <unordered_map>

#include <llvm/Support/FormatVariadic.h>

#include <vpux_elf/accessor.hpp>
#include "vpux_elf/reader.hpp"
#include "vpux_elf/types/elf_structs.hpp"
#include "vpux_elf/types/section_header.hpp"

// Class which encapsulates a group of memory requirements generated by ELF sections filtered based on a given criteria
// The actual memory requirement is stored within the elf::SectionHeader sh_size field
struct MemoryRequirementsGroup {
    struct IndividualRequirement {
        size_t mIndex;
        elf::SectionHeader mHeader;
    };

    // Track individual sections that generated requirements
    std::vector<IndividualRequirement> mIndividualRequirements = {};
    // Track total required memory
    size_t mTotalGroupRequirement = 0;
};

// Class which encapsulated memory requirements for an arbitrary collection of groups
class MemoryRequirementsCategory {
public:
    MemoryRequirementsCategory(std::string_view name): mName(name){};

    void addRequirementToGroup(const std::string& groupName,
                               MemoryRequirementsGroup::IndividualRequirement& individualRequirement) {
        mMap[groupName].mIndividualRequirements.push_back(individualRequirement);
        mMap[groupName].mTotalGroupRequirement += individualRequirement.mHeader.sh_size;
        mTotal += individualRequirement.mHeader.sh_size;
    }

    size_t getTotalRequired() const {
        return mTotal;
    }

    void print() {
        llvm::outs() << llvm::formatv(" - By {0} ({1} bytes):\n", mName, mTotal);
        for (const auto& entry : mMap) {
            llvm::outs() << llvm::formatv("    - {0}: {1} bytes from {2} sections\n", entry.first,
                                          entry.second.mTotalGroupRequirement,
                                          entry.second.mIndividualRequirements.size());
        }
    }

private:
    std::unordered_map<std::string, MemoryRequirementsGroup> mMap = {};
    std::string mName = {};
    size_t mTotal = 0;
};

using ProcessorMap = std::unordered_map<std::string, elf::Elf_Xword>;

// Generic map of processor and their corresponding flag values
// This information would ideally be exposed by the ELF loader
static ProcessorMap defaultProcMap = {{"EXEC", elf::SHF_EXECINSTR},
                                      {"DPU", elf::VPU_SHF_PROC_DPU},
                                      {"DMA", elf::VPU_SHF_PROC_DMA},
                                      {"SHAVE", elf::VPU_SHF_PROC_SHAVE}};

// Class which scans a given blob and stores memory requirements information based the following categories:
//  - processor type
//  - allocation type
class BlobScanner {
public:
    using Requirement = MemoryRequirementsGroup::IndividualRequirement;

    BlobScanner(elf::AccessManager* accessManager, const ProcessorMap& processorMap)
            : mProcessorRequirements("Processor"), mAllocationTypeRequirements("Allocation type") {
        elf::Reader<elf::Elf64> reader(accessManager);

        for (size_t sectionIdx = 0; sectionIdx < reader.getSectionsNum(); ++sectionIdx) {
            auto sectionHeader = reader.getSection(sectionIdx).getHeader();

            if (sectionHeader->sh_flags & elf::SHF_ALLOC) {
                Requirement requirement{sectionIdx, *sectionHeader};
                // Track individual processor requirements
                // This implementation does not account for situations where 2 processors need to access the same
                // section
                for (auto& procMapElem : processorMap) {
                    if (sectionHeader->sh_flags & procMapElem.second) {
                        mProcessorRequirements.addRequirementToGroup(procMapElem.first, requirement);
                    }
                }
                // Track global requirements for binary sections
                if (sectionHeader->sh_type == elf::SHT_PROGBITS) {
                    mAllocationTypeRequirements.addRequirementToGroup("Data (backed by blob data)", requirement);
                    ;
                }
                // Track global requirements for scratch sections
                if (sectionHeader->sh_type == elf::SHT_NOBITS) {
                    mAllocationTypeRequirements.addRequirementToGroup("Empty (not backed by blob data)", requirement);
                    ;
                }
            }
        }
    }

    const MemoryRequirementsCategory& getRequirementsByProcessor() {
        return mProcessorRequirements;
    }

    const MemoryRequirementsCategory& getRequirementsByAllocationType() {
        return mAllocationTypeRequirements;
    }

    void printResult() {
        llvm::outs() << llvm::formatv(
                "================================================================================\n");
        llvm::outs() << llvm::formatv("Blob NPU memory requirements scan results:\n\n");

        mProcessorRequirements.print();
        llvm::outs() << llvm::formatv("\n");
        mAllocationTypeRequirements.print();
        llvm::outs() << llvm::formatv(
                "================================================================================\n");
    }

private:
    MemoryRequirementsCategory mProcessorRequirements;
    MemoryRequirementsCategory mAllocationTypeRequirements;
};