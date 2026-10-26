# frozen_string_literal: true

class Retry
  def initialize(max_attempts:, strategy: :constant, base_delay: 0.1,
                 retry_on: [StandardError], sleeper: Kernel.method(:sleep), random: Random.new)
    @max_attempts = max_attempts
    @strategy = strategy
    @base_delay = base_delay
    @retry_on = Array(retry_on)
    @sleeper = sleeper
    @random = random
  end

  def execute(fn)
    attempt = 0

    begin
      attempt += 1
      fn.call
    rescue StandardError => e
      raise unless attempt < @max_attempts && retryable?(e)

      @sleeper.call(delay_for(attempt))
      retry
    end
  end

  private

  def retryable?(error)
    @retry_on.any? do |rule|
      rule.is_a?(Module) ? error.is_a?(rule) : rule.call(error)
    end
  end

  def delay_for(attempt)
    case @strategy
    when :constant
      @base_delay
    when :exponential
      exponential(attempt)
    when :exponential_jitter
      exponential(attempt) * @random.rand
    else
      raise ArgumentError, "unknown strategy: #{@strategy.inspect}"
    end
  end

  def exponential(attempt)
    @base_delay * (2**(attempt - 1))
  end
end
