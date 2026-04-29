defmodule Rlm.Providers.RequestManager.Timeouts do
  @moduledoc false

  alias Rlm.Providers.RequestManager.Error

  def classify_transport_error(
        %Req.TransportError{reason: :timeout},
        fallback_class,
        partial_text
      ) do
    %Error{
      class: fallback_class,
      message: "%Req.TransportError{reason: :timeout}",
      partial_text: partial_text
    }
  end

  def classify_transport_error(%Req.TransportError{} = error, fallback_class, partial_text) do
    class = if fallback_class == :first_byte_timeout, do: :connect_error, else: :provider_error
    %Error{class: class, message: inspect(error), partial_text: partial_text}
  end

  def next_timeout(state, started_at, settings) do
    elapsed = System.monotonic_time(:millisecond) - started_at
    remaining_total = max(1, settings.total_timeout - elapsed)
    preferred = if state.got_data?, do: settings.idle_timeout, else: settings.first_byte_timeout
    max(1, min(preferred, remaining_total))
  end

  def timeout_class(started_at, settings, state) do
    elapsed = System.monotonic_time(:millisecond) - started_at

    if elapsed >= settings.total_timeout do
      :total_timeout
    else
      default_timeout_class(state)
    end
  end

  def default_timeout_class(state) do
    if state.got_data?, do: :idle_timeout, else: :first_byte_timeout
  end

  def timeout_message(:first_byte_timeout),
    do: "provider did not produce response bytes before the first-byte deadline"

  def timeout_message(:idle_timeout),
    do: "provider stream went silent past the idle timeout"

  def timeout_message(:total_timeout),
    do: "provider exceeded the total request deadline"
end
