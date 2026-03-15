require "test_helper"

class TestCostField < Minitest::Test
  def test_response_struct_has_cost_field
    response = Legendator::AiClient::Response.new(
      content: "test",
      input_tokens: 10,
      output_tokens: 5,
      model: "gpt-4.1-mini",
      raw: {},
      cost: 0.001
    )
    assert_equal 0.001, response.cost
  end

  def test_response_cost_defaults_to_nil
    response = Legendator::AiClient::Response.new(
      content: "test",
      input_tokens: 10,
      output_tokens: 5,
      model: "gpt-4.1-mini",
      raw: {}
    )
    assert_nil response.cost
  end

  def test_pipeline_result_has_cost_field
    result = Legendator::Pipeline::Result.new(
      srt_content: "1\n00:00:01,000 --> 00:00:02,000\nHello\n",
      coverage: { total_subtitles: 1, translated: 1 },
      token_usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15 },
      chunks_info: { total_chunks: 1 },
      provider: :openrouter,
      model: "gpt-4.1-mini",
      cost: 0.005
    )
    assert_equal 0.005, result.cost
  end
end
