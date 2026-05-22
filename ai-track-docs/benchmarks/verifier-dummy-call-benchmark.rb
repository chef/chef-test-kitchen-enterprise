# frozen_string_literal: true

require "benchmark"
require "logger"
require "ostruct"
require "stringio"

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "kitchen/verifier/dummy"

# Benchmarks the steady-state success path for Kitchen::Verifier::Dummy#call.
ITERATIONS = Integer(ENV.fetch("ITERATIONS", "10000"))
REPEATS = Integer(ENV.fetch("REPEATS", "7"))

logged_output = StringIO.new
logger = Logger.new(logged_output)
platform = OpenStruct.new(os_type: nil, shell_type: nil)
suite = OpenStruct.new(name: "fries")
instance = OpenStruct.new(
  name: "coolbeans",
  to_str: "instance",
  logger: logger,
  suite: suite,
  platform: platform
)

config = {
  test_base_path: "/basist",
  kitchen_root: "/rooty",
  sleep: 0,
  random_failure: false,
}

verifier = Kitchen::Verifier::Dummy.new(config).finalize_config!(instance)
state = { baseline: true }

samples_ms = Array.new(REPEATS) do
  elapsed = Benchmark.realtime do
    ITERATIONS.times { verifier.call(state) }
  end

  elapsed * 1000.0
end

mean = samples_ms.sum / samples_ms.size
variance = samples_ms.sum { |x| (x - mean) ** 2 } / samples_ms.size
stddev = Math.sqrt(variance)

puts "Function: Kitchen::Verifier::Dummy#call"
puts "Iterations per repeat: #{ITERATIONS}"
puts "Repeats: #{REPEATS}"
puts format("Mean (ms): %.3f", mean)
puts format("Stddev (ms): %.3f", stddev)
puts format("Min (ms): %.3f", samples_ms.min)
puts format("Max (ms): %.3f", samples_ms.max)
puts format("Per call mean (us): %.3f", (mean * 1000.0) / ITERATIONS)
puts "Samples (ms): #{samples_ms.map { |x| format("%.3f", x) }.join(", ")}"
