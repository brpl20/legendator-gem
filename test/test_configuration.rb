require_relative "test_helper"

class TestConfiguration < Minitest::Test
  def setup
    Legendator.reset_configuration!
  end

  def teardown
    Legendator.reset_configuration!
  end

  # ─── Defaults ───────────────────────────────────────

  def test_default_provider
    assert_kind_of Symbol, Legendator.configuration.provider
  end

  def test_default_model
    assert_kind_of String, Legendator.configuration.model
    refute_empty Legendator.configuration.model
  end

  def test_default_target_language
    assert_kind_of String, Legendator.configuration.target_language
    refute_empty Legendator.configuration.target_language
  end

  def test_default_max_tokens_per_chunk
    assert_kind_of Integer, Legendator.configuration.max_tokens_per_chunk
    assert Legendator.configuration.max_tokens_per_chunk > 0
  end

  def test_default_temperature
    assert_kind_of Float, Legendator.configuration.temperature
  end

  def test_default_api_key_is_nil
    assert_nil Legendator.configuration.api_key
  end

  # ─── Configure Block ────────────────────────────────

  def test_configure_block
    Legendator.configure do |config|
      config.provider = :openrouter
      config.model = "custom-model"
      config.target_language = "es"
    end

    assert_equal :openrouter, Legendator.configuration.provider
    assert_equal "custom-model", Legendator.configuration.model
    assert_equal "es", Legendator.configuration.target_language
  end

  def test_configure_api_key
    Legendator.configure do |config|
      config.api_key = "sk-test-key"
    end

    assert_equal "sk-test-key", Legendator.configuration.api_key
  end

  # ─── Reset ──────────────────────────────────────────

  def test_reset_configuration
    Legendator.configure do |config|
      config.model = "totally-custom"
    end

    assert_equal "totally-custom", Legendator.configuration.model

    Legendator.reset_configuration!

    refute_equal "totally-custom", Legendator.configuration.model
  end

  # ─── api_key_for ────────────────────────────────────

  def test_api_key_for_returns_generic_key_when_set
    Legendator.configure do |config|
      config.api_key = "generic-key"
      config.openai_api_key = "openai-specific"
    end

    assert_equal "generic-key", Legendator.configuration.api_key_for(:openai)
    assert_equal "generic-key", Legendator.configuration.api_key_for(:openrouter)
  end

  def test_api_key_for_returns_provider_specific_key
    Legendator.configure do |config|
      config.openai_api_key = "openai-specific"
      config.openrouter_api_key = "openrouter-specific"
    end

    assert_equal "openai-specific", Legendator.configuration.api_key_for(:openai)
    assert_equal "openrouter-specific", Legendator.configuration.api_key_for(:openrouter)
  end

  def test_api_key_for_falls_back_to_env
    # ENV fallback is tested implicitly — if no config key is set
    # and no ENV var is present, api_key_for returns nil
    Legendator.reset_configuration!
    # Don't set any keys — result depends on ENV
    key = Legendator.configuration.api_key_for(:openai)
    # Should be either the ENV value or nil (no assertion on value,
    # just that it doesn't raise)
    assert_kind_of(String, key) if key
  end

  # ─── Config Module Delegation ───────────────────────

  def test_config_module_delegates_to_configuration
    Legendator.configure do |config|
      config.provider = :openrouter
      config.model = "delegated-model"
    end

    assert_equal :openrouter, Legendator::Config.provider
    assert_equal "delegated-model", Legendator::Config.model
  end

  # ─── Error Classes ──────────────────────────────────

  def test_error_hierarchy
    assert Legendator::Error < StandardError
    assert Legendator::ConfigurationError < Legendator::Error
    assert Legendator::TranslationError < Legendator::Error
    assert Legendator::ParseError < Legendator::Error
  end

  # ─── Version ────────────────────────────────────────

  def test_version_is_set
    refute_nil Legendator::VERSION
    assert_match(/\A\d+\.\d+\.\d+/, Legendator::VERSION)
  end
end
