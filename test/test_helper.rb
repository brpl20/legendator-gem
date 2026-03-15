$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "minitest/reporters"
Minitest::Reporters.use!(Minitest::Reporters::SpecReporter.new)

require "legendator"

FIXTURES_PATH = File.expand_path("fixtures", __dir__)

def fixture(name)
  File.read(File.join(FIXTURES_PATH, name))
end
