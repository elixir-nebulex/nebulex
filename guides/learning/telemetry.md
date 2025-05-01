# Telemetry

This guide explains how to instrument and monitor cache telemetry events in your
Nebulex application. For general information about `:telemetry`, see the
[official documentation][telemetry] or the [Phoenix Telemetry guide][phx_telemetry].

[telemetry]: https://github.com/beam-telemetry/telemetry
[phx_telemetry]: https://hexdocs.pm/phoenix/telemetry.html

## Telemetry Events

Many Elixir libraries, including Nebulex, use `:telemetry` to provide insights
into application behavior by emitting events at key lifecycle moments.

For detailed information about emitted events, measurements, and metadata, see
the [Telemetry Events documentation][nbx_telemetry_events].

[nbx_telemetry_events]: http://hexdocs.pm/nebulex/Nebulex.Cache.html#module-telemetry-events

## Nebulex Metrics

Assuming you have defined the cache `MyApp.Cache` with the default
`:telemetry_prefix` (`[:my_app, :cache]`), you can use `Telemetry.Metrics`
to define various metrics.

### Counter Metric

Count the number of completed cache commands:

```elixir
Telemetry.Metrics.counter("my_app.cache.command.stop.duration")
```

### Distribution Metric

Track command completion times in specific buckets:

```elixir
Telemetry.Metrics.distribution(
  "my_app.cache.command.stop.duration",
  buckets: [100, 200, 300]  # Duration in milliseconds
)
```

### Summary Metric

For more detailed analysis, you can define a summary metric to track:
- Average command duration
- Minimum and maximum execution times
- Percentiles
- Aggregation by command or callback name

```elixir
Telemetry.Metrics.summary(
  "my_app.cache.command.stop.duration",
  unit: {:native, :millisecond},
  tags: [:command]
)
```

### Extracting tag values from adapter's metadata

Let's add another metric for the command event, this time to group by
**command**, **cache**, and **name** (in case of dynamic caches):

```elixir
Telemetry.Metrics.summary(
  "my_app.cache.command.stop.duration",
  unit: {:native, :millisecond},
  tags: [:command, :cache, :name],
  tag_values:
    &%{
      cache: &1.adapter_meta.cache,
      name: &1.adapter_meta.name,
      command: &1.command
    }
)
```

We've introduced the `:tag_values` option here, because we need to perform a
transformation on the event metadata in order to get to the values we need.
