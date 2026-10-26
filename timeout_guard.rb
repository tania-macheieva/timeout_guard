# frozen_string_literal: true

module TimeoutGuard
  class TimeoutError < StandardError; end

  # Виконує fn у окремому потоці й чекає не довше timeout_ms.
  # Після перевищення потік примусово завершується (відміна операції):
  # код після місця переривання не виконується, а блоки `ensure` у fn
  # спрацьовують і можуть відкотити зміни.
  def self.with_timeout(fn, timeout_ms)
    worker = Thread.new do
      Thread.current.report_on_exception = false
      fn.call
    end

    begin
      # join повертає nil при перевищенні ліміту й пробрасує помилку fn, якщо вона була
      raise TimeoutError, "operation timed out after #{timeout_ms} ms" unless worker.join(timeout_ms / 1000.0)

      worker.value
    ensure
      if worker.alive?
        worker.kill
        worker.join
      end
    end
  end
end
