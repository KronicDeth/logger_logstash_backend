################################################################################
# Copyright 2015 Marcelo Gornstein <marcelog@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################
defmodule LoggerLogstashBackend do
  use GenEvent
  use Timex

  def init({__MODULE__, name}) do
    {:ok, configure(name, [])}
  end

  def handle_call({:configure, opts}, %{name: name}) do
    {:ok, :ok, configure(name, opts)}
  end

  def handle_event(
    {level, _gl, {Logger, msg, ts, md}}, %{level: min_level} = state
  ) do
    if is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt do
      log_event level, msg, ts, md, state
    end
    {:ok, state}
  end

  defp log_event(
    level, msg, ts, md, %{
      host: host,
      port: port,
      type: type,
      metadata: metadata,
      socket: socket
    }
  ) do
    md = Enum.into(Keyword.merge(md, metadata), %{})
    md = Map.put md, :pid, inspect(md.pid)
    ts = Timex.datetime(ts, :local)
    timestamp = Timex.format!(ts, "%FT%T%z", :strftime)
    message = to_string(msg)
    level_string = to_string(level)
    fields = Map.put(md, :level, level_string)

    IO.inspect "#{__MODULE__}.log_event type = #{inspect type}"
    {:ok, json} = JSX.encode %{
      type: type
    }
    IO.inspect "#{__MODULE__}.log_event encoded type = #{inspect type}"

    IO.inspect "#{__MODULE__}.log_event timestamp = #{inspect timestamp}"
    {:ok, json} = JSX.encode %{
      "@timestamp": timestamp,
    }
    IO.inspect "#{__MODULE__}.log_event encoded timestamp = #{inspect timestamp}"

    IO.inspect "#{__MODULE__}.log_event message = #{inspect message}"
    {:ok, json} = JSX.encode %{
      message: message
    }
    IO.inspect "#{__MODULE__}.log_event encoded message = #{inspect message}"

    IO.inspect "#{__MODULE__}.log_event fields = #{inspect fields}"
    encoded = JSX.encode %{
      fields: fields
    }
    IO.inspect "#{__MODULE__}.log_event JSX encoded fields = #{inspect encoded}"

    encoded = Poison.encode %{
      fields: fields
    }
    IO.inspect "#{__MODULE__}.log_event Poison encoded fields = #{inspect encoded}"

    {:ok, json} = JSX.encode %{
      type: type,
      "@timestamp": timestamp,
      message: message,
      fields: fields
    }
    :gen_udp.send socket, host, port, to_char_list(json)
  end

  defp configure(name, opts) do
    env = Application.get_env :logger, name, []
    opts = Keyword.merge env, opts
    Application.put_env :logger, name, opts

    level = Keyword.get opts, :level, :debug
    metadata = Keyword.get opts, :metadata, []
    type = Keyword.get opts, :type, "elixir"
    host = Keyword.get opts, :host
    port = Keyword.get opts, :port
    {:ok, socket} = :gen_udp.open 0
    %{
      name: name,
      host: to_char_list(host),
      port: port,
      level: level,
      socket: socket,
      type: type,
      metadata: metadata
    }
  end
end
