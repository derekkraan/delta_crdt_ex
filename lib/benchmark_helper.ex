defmodule BenchmarkHelper do
  defmacro inject_in_dev() do
    quote do
      if Mix.env() == :dev do
        def handle_call(:hibernate, _from, state) do
          {:reply, :ok, state, :hibernate}
        end

        def handle_call(:ping, _from, state) do
          {:reply, :ok, state}
        end
      end
    end
  end
end
