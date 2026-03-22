require "json"

module Legendator
  class ConsistencyChecker
    SAMPLE_SIZE = 5

    Result = Struct.new(:pass, :errors, :sample_details, keyword_init: true) do
      alias_method :pass?, :pass
    end

    def initialize(original_srt:, translated_srt:, target_language:, provider: nil, model: nil, api_key: nil)
      @original_srt = original_srt
      @translated_srt = translated_srt
      @target_language = target_language
      @provider = provider
      @model = model
      @api_key = api_key
    end

    def run
      result = check_structure
      return result unless result.pass?

      check_translation(result)
    end

    def check_structure
      original = SrtParser.new(@original_srt)
      translated = SrtParser.new(@translated_srt)

      orig_texts = original.extract_texts
      orig_timestamps = original.extract_timestamps
      trans_texts = translated.extract_texts
      trans_timestamps = translated.extract_timestamps

      errors = []

      if orig_texts.size != trans_texts.size
        errors << "Subtitle count mismatch: original has #{orig_texts.size}, translated has #{trans_texts.size}"
      end

      missing_ids = orig_texts.keys - trans_texts.keys
      if missing_ids.any?
        errors << "Missing subtitle IDs in translation: #{missing_ids.sort.join(', ')}"
      end

      extra_ids = trans_texts.keys - orig_texts.keys
      if extra_ids.any?
        errors << "Extra subtitle IDs in translation: #{extra_ids.sort.join(', ')}"
      end

      common_ids = orig_texts.keys & trans_texts.keys
      common_ids.each do |id|
        if orig_timestamps[id] != trans_timestamps[id]
          errors << "Timestamp mismatch for ID #{id}: original '#{orig_timestamps[id]}' vs translated '#{trans_timestamps[id]}'"
        end
      end

      Result.new(pass: errors.empty?, errors: errors, sample_details: [])
    end

    private

    def check_translation(structural_result)
      return structural_result unless @provider && @model

      original_texts = SrtParser.new(@original_srt).extract_texts
      translated_texts = SrtParser.new(@translated_srt).extract_texts

      sample_ids = pick_sample_ids(original_texts.keys, SAMPLE_SIZE)

      pairs = sample_ids.each_with_object({}) do |id, hash|
        hash[id] = {
          original: original_texts[id],
          translated: translated_texts[id]
        }
      end

      client = AiClient.new(provider: @provider, model: @model, api_key: @api_key)
      prompt = build_verification_prompt(pairs)

      response = client.chat(
        system_prompt: "You are a translation verification assistant. Answer ONLY with valid JSON.",
        user_prompt: prompt,
        temperature: 0
      )

      verdicts = parse_verification_response(response.content)

      errors = structural_result.errors.dup
      sample_details = []

      pairs.each do |id, pair|
        passed = verdicts[id] != false
        sample_details << { id: id, original: pair[:original], translated: pair[:translated], passed: passed }
        unless passed
          errors << "Subtitle ID #{id} was not translated"
        end
      end

      Result.new(pass: errors.empty?, errors: errors, sample_details: sample_details)
    end

    def pick_sample_ids(all_ids, count)
      all_ids.sample([count, all_ids.size].min)
    end

    def build_verification_prompt(pairs)
      pairs_json = pairs.each_with_object({}) do |(id, pair), hash|
        hash[id.to_s] = { "original" => pair[:original], "translated" => pair[:translated] }
      end

      <<~PROMPT
        For each pair below, answer ONLY with a JSON object.
        Each pair has an original subtitle and a supposed translation to #{@target_language}.
        Answer whether each one was actually translated (not left in the original language).

        #{JSON.generate(pairs_json)}

        Return format: {"1": true, "2": false, ...}
        Return ONLY the JSON, nothing else.
      PROMPT
    end

    def parse_verification_response(content)
      parsed = begin
        JSON.parse(content)
      rescue JSON::ParserError
        {}
      end

      parsed.each_with_object({}) do |(k, v), hash|
        hash[k.to_i] = v
      end
    end
  end
end
