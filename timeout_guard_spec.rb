# frozen_string_literal: true

require_relative 'timeout_guard'
require_relative 'retry' # реалізація з лабораторної роботи 1.3

RSpec.describe TimeoutGuard do
  let(:timeout_ms) { 50 }

  def elapsed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  def run(fn, ms = timeout_ms)
    described_class.with_timeout(fn, ms)
  end

  describe 'operation that finishes in time' do
    it 'returns the result of fn' do
      expect(run(-> { :ok })).to eq(:ok)
    end

    it 'returns as soon as fn is done, without waiting for the timeout' do
      time = elapsed { run(-> { sleep(0.01) }, 1000) }

      expect(time).to be < 0.5
    end

    it 'propagates errors of fn unchanged' do
      expect { run(-> { raise ArgumentError, 'boom' }) }.to raise_error(ArgumentError, 'boom')
    end
  end

  describe 'operation that exceeds the timeout' do
    let(:hanging) { -> { sleep(2) } }

    it 'raises TimeoutError after about timeout_ms' do
      time = elapsed do
        expect { run(hanging) }.to raise_error(described_class::TimeoutError, /50 ms/)
      end

      expect(time).to be_between(0.05, 0.5)
    end

    it 'does not perform side effects after the deadline' do
      effects = []
      slow = -> { sleep(0.3); effects << :committed }

      expect { run(slow) }.to raise_error(described_class::TimeoutError)
      sleep(0.5)

      expect(effects).to be_empty
    end

    it 'runs cleanup (ensure) of the cancelled operation' do
      log = []
      fn = lambda do
        log << :started
        sleep(2)
      ensure
        log << :rolled_back
      end

      expect { run(fn) }.to raise_error(described_class::TimeoutError)
      expect(log).to eq(%i[started rolled_back])
    end
  end

  describe 'combined with Retry' do
    let(:sleeps) { [] }
    let(:sleeper) { ->(seconds) { sleeps << seconds } }
    let(:attempts) { [] }
    let(:hanging) { -> { attempts << :call; sleep(2) } }

    def retrier(max_attempts)
      Retry.new(max_attempts: max_attempts, base_delay: 0.01,
                retry_on: [described_class::TimeoutError], sleeper: sleeper)
    end

    it 'retries after a timeout and succeeds on a later attempt' do
      calls = 0
      flaky = -> { (calls += 1) == 1 ? sleep(2) : :ok }

      result = retrier(3).execute(-> { run(flaky) })

      expect(result).to eq(:ok)
      expect(calls).to eq(2)
    end

    it 'per-attempt timeout bounds the total wait to max_attempts * timeout' do
      time = elapsed do
        expect { retrier(3).execute(-> { run(hanging) }) }
          .to raise_error(described_class::TimeoutError)
      end

      expect(attempts.size).to eq(3)
      expect(time).to be_between(0.15, 0.6)
    end

    it 'an outer timeout caps the whole retry sequence regardless of max_attempts' do
      effects = []
      slow = -> { attempts << :call; sleep(0.5); effects << :committed }

      time = elapsed do
        expect { run(-> { retrier(10).execute(-> { run(slow) }) }, 120) }
          .to raise_error(described_class::TimeoutError)
      end
      sleep(0.7)

      expect(time).to be < 0.5
      expect(attempts.size).to be <= 3
      expect(effects).to be_empty
    end
  end
end
