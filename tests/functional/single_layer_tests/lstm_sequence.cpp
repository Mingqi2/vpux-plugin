// Copyright (C) 2018-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "single_layer_tests/lstm_sequence.hpp"
#include <ngraph/op/util/attr_types.hpp>
#include <vector>
#include "shared_tests_instances/vpu_ov1_layer_test.hpp"

#include <memory>
#include <string>
#include <tuple>
#include "ngraph/pass/visualize_tree.hpp"
#include "ov_models/builders.hpp"
#include "ov_models/utils/ov_helpers.hpp"
#include "shared_test_classes/base/layer_test_utils.hpp"

using ngraph::helpers::InputLayerType;

namespace LayerTestsDefinitions {

class LSTMSequenceLayerTest_NPU3700 :
        public testing::WithParamInterface<LSTMSequenceParams>,
        virtual public LayerTestsUtils::LayerTestsCommon,
        virtual public LayerTestsUtils::VpuOv1LayerTestsCommon {
public:
    static std::string getTestCaseName(const testing::TestParamInfo<LSTMSequenceParams>& obj) {
        ngraph::helpers::SequenceTestsMode mode;
        size_t seq_lengths;
        size_t batch;
        size_t hidden_size;
        size_t input_size;
        std::vector<std::string> activations;
        std::vector<float> activations_alpha;
        std::vector<float> activations_beta;
        float clip;
        ngraph::op::RecurrentSequenceDirection direction;
        InputLayerType WRBType;
        InferenceEngine::Precision netPrecision;
        std::string targetDevice;
        std::tie(mode, seq_lengths, batch, hidden_size, input_size, activations, clip, direction, WRBType, netPrecision,
                 targetDevice) = obj.param;
        std::vector<std::vector<size_t>> inputShapes = {
                {{batch, input_size},
                 {batch, hidden_size},
                 {batch, hidden_size},
                 {4 * hidden_size, input_size},
                 {4 * hidden_size, hidden_size},
                 {4 * hidden_size}},
        };
        std::ostringstream result;
        result << "mode=" << mode << "_";
        result << "seq_lengths=" << seq_lengths << "_";
        result << "batch=" << batch << "_";
        result << "hidden_size=" << hidden_size << "_";
        result << "input_size=" << input_size << "_";
        result << "IS=" << ov::test::utils::vec2str(inputShapes) << "_";
        result << "activations=" << ov::test::utils::vec2str(activations) << "_";
        result << "direction=" << direction << "_";
        result << "clip=" << clip << "_";
        result << "WRBType=" << WRBType << "_";
        result << "netPRC=" << netPrecision.name() << "_";
        result << "targetDevice=" << targetDevice << "_";
        return result.str();
    }

protected:
    void GenerateInputs() override {
        for (const auto& input : executableNetwork.GetInputsInfo()) {
            const auto& info = input.second;
            auto blob = GenerateInput(*info);
            inputs.push_back(blob);
        }
    }
    void SetUp() override {
        using namespace ngraph::helpers;
        using namespace ngraph::builder;
        size_t seq_lengths;

        size_t batch;
        size_t hidden_size;
        size_t input_size;
        std::vector<std::string> activations;
        std::vector<float> activations_alpha;
        std::vector<float> activations_beta;
        float clip;
        ngraph::op::RecurrentSequenceDirection direction;
        InputLayerType WRBType;
        InferenceEngine::Precision netPrecision;
        std::tie(m_mode, seq_lengths, batch, hidden_size, input_size, activations, clip, direction, WRBType,
                 netPrecision, targetDevice) = this->GetParam();

        size_t num_directions = direction == ngraph::op::RecurrentSequenceDirection::BIDIRECTIONAL ? 2 : 1;
        std::vector<std::vector<size_t>> inputShapes = {
                {{batch, seq_lengths, input_size},
                 {batch, num_directions, hidden_size},
                 {batch, num_directions, hidden_size},
                 {batch},
                 {num_directions, 4 * hidden_size, input_size},
                 {num_directions, 4 * hidden_size, hidden_size},
                 {num_directions, 4 * hidden_size}},
        };
        auto ngPrc = FuncTestUtils::PrecisionUtils::convertIE2nGraphPrc(netPrecision);
        ov::ParameterVector params{std::make_shared<ov::op::v0::Parameter>(ngPrc, ov::Shape(inputShapes[0])),
                                   std::make_shared<ov::op::v0::Parameter>(ngPrc, ov::Shape(inputShapes[1])),
                                   std::make_shared<ov::op::v0::Parameter>(ngPrc, ov::Shape(inputShapes[2]))};

        ASSERT_EQ(InputLayerType::CONSTANT, WRBType);
        std::vector<ngraph::Shape> WRB = {inputShapes[4], inputShapes[5], inputShapes[6], inputShapes[3]};
        auto lstm_sequence = makeLSTM(convert2OutputVector(castOps2Nodes(params)), WRB, hidden_size, activations, {},
                                      {}, clip, true, direction, m_mode);
        ngraph::ResultVector results{std::make_shared<ov::op::v0::Result>(lstm_sequence->output(0)),
                                     std::make_shared<ov::op::v0::Result>(lstm_sequence->output(1)),
                                     std::make_shared<ov::op::v0::Result>(lstm_sequence->output(2))};
        function = std::make_shared<ngraph::Function>(results, params, "lstm_sequence");
    }

private:
    void SkipBeforeValidate() override {
        throw LayerTestsUtils::VpuSkipTestException("differs from the reference");
    }

private:
    ngraph::helpers::SequenceTestsMode m_mode;
    int64_t m_max_seq_len = 0;
};

class LSTMSequenceLayerTest_NPU3720 : public LSTMSequenceTest, virtual public LayerTestsUtils::VpuOv1LayerTestsCommon {
    void SetUp() override {
        inPrc = InferenceEngine::Precision::FP16;
        outPrc = InferenceEngine::Precision::FP16;
        LSTMSequenceTest::SetUp();
    }
};

TEST_P(LSTMSequenceLayerTest_NPU3700, HW) {
    setPlatformVPU3700();
    setDefaultHardwareModeMLIR();
    Run();
}

TEST_P(LSTMSequenceLayerTest_NPU3720, HW) {
    setPlatformVPU3720();
    setDefaultHardwareModeMLIR();
    Run();
}

}  // namespace LayerTestsDefinitions

using namespace LayerTestsDefinitions;

namespace {
std::vector<ngraph::helpers::SequenceTestsMode> mode = {
        ngraph::helpers::SequenceTestsMode::PURE_SEQ,
};

// --------- NPU3700 ---------
std::vector<size_t> seq_lengths_zero_clip3700{1};
std::vector<size_t> batch3700{1};
std::vector<size_t> hidden_size3700{1};
std::vector<size_t> input_size3700{1};
std::vector<std::vector<std::string>> activations = {{"sigmoid", "tanh", "tanh"}};
std::vector<float> clip{0.f};
std::vector<ngraph::op::RecurrentSequenceDirection> direction = {ngraph::op::RecurrentSequenceDirection::FORWARD,
                                                                 ngraph::op::RecurrentSequenceDirection::REVERSE,
                                                                 ngraph::op::RecurrentSequenceDirection::BIDIRECTIONAL};
std::vector<InferenceEngine::Precision> netPrecisions = {InferenceEngine::Precision::FP16};

INSTANTIATE_TEST_CASE_P(smoke_LSTMSequenceCommonZeroClip, LSTMSequenceLayerTest_NPU3700,
                        ::testing::Combine(::testing::ValuesIn(mode), ::testing::ValuesIn(seq_lengths_zero_clip3700),
                                           ::testing::ValuesIn(batch3700), ::testing::ValuesIn(hidden_size3700),
                                           ::testing::ValuesIn(input_size3700), ::testing::ValuesIn(activations),
                                           ::testing::ValuesIn(clip), ::testing::ValuesIn(direction),
                                           ::testing::Values(InputLayerType::CONSTANT),
                                           ::testing::ValuesIn(netPrecisions),
                                           ::testing::Values(LayerTestsUtils::testPlatformTargetDevice())),
                        LSTMSequenceLayerTest_NPU3700::getTestCaseName);

// --------- NPU3720 ---------
std::vector<size_t> seq_lengths_zero_clip{3};
std::vector<size_t> batch{3};
std::vector<size_t> hidden_size{64};
std::vector<size_t> input_size{67};

const auto lstmConfig = ::testing::Combine(
        ::testing::ValuesIn(mode), ::testing::ValuesIn(seq_lengths_zero_clip), ::testing::ValuesIn(batch),
        ::testing::ValuesIn(hidden_size), ::testing::ValuesIn(input_size), ::testing::ValuesIn(activations),
        ::testing::ValuesIn(clip), ::testing::ValuesIn(direction), ::testing::Values(InputLayerType::CONSTANT),
        ::testing::ValuesIn(netPrecisions), ::testing::Values(LayerTestsUtils::testPlatformTargetDevice()));

INSTANTIATE_TEST_CASE_P(smoke_precommit_LSTMSequenceCommonZeroClip, LSTMSequenceLayerTest_NPU3720, lstmConfig,
                        LSTMSequenceLayerTest_NPU3720::getTestCaseName);

}  // namespace
