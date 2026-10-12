# Info API

Nebulex v3 introduces the adapter Info API, a generic API to get information
about the cache, including the stats. Adapters implement the Info API and are
free to add the information keys they want, so check the documentation of the
adapter you use.

> See `c:Nebulex.Cache.info/2` for more information.

Nebulex also provides a simple implementation, `Nebulex.Adapters.Common.Info`,
which the `Nebulex.Adapters.Local` adapter uses. It keeps the stats updated
through a Telemetry handler, so it needs `:telemetry` to be available.

> **Note**: The `:telemetry` dependency is optional but recommended for
> production. Add `{:telemetry, "~> 1.0"}` to your `mix.exs` to get cache
> metrics.

## Usage

Let's define our cache:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local
end
```

And the configuration:

```elixir
config :my_app, MyApp.Cache,
  gc_interval: :timer.hours(12),
  max_size: 1_000_000,
  allocated_memory: 1_000_000,
  gc_memory_check_interval: :timer.seconds(10)
```

Once you have set up the `MyApp.Cache` within the application's supervision
tree, you can get the cache info like so:

```elixir
iex> MyApp.Cache.info!()
%{
  server: %{
    nbx_version: "3.0.0",
    cache_module: MyApp.Cache,
    cache_adapter: Nebulex.Adapters.Local,
    cache_name: MyApp.Cache,
    cache_pid: #PID<0.111.0>
  },
  memory: %{
    total: 1_000_000,
    used: 0
  },
  stats: %{
    deletions: 0,
    evictions: 0,
    expirations: 0,
    hits: 0,
    misses: 0,
    updates: 0,
    writes: 0
  }
}
```

You could also request a specific item or items:

```elixir
iex> MyApp.Cache.info!(:stats)
%{
  deletions: 0,
  evictions: 0,
  expirations: 0,
  hits: 0,
  misses: 0,
  updates: 0,
  writes: 0
}

iex> MyApp.Cache.info!([:stats, :memory])
%{
  memory: %{
    total: 1_000_000,
    used: 0
  },
  stats: %{
    deletions: 0,
    evictions: 0,
    expirations: 0,
    hits: 0,
    misses: 0,
    updates: 0,
    writes: 0
  }
}
```

## Understanding Cache Stats

The stats map has the following counters (see
`Nebulex.Adapters.Common.Info.Stats`):

- `hits`: reads that found the requested data in the cache.
- `misses`: reads that did not find the requested data, either because it
  was never cached or because it was removed.
- `writes`: entries inserted or overwritten.
- `updates`: existing entries updated in place.
- `deletions`: entries removed on request, by the application or the cache.
- `evictions`: entries removed by the cache itself, either to free space or
  because their TTL expired.
- `expirations`: entries removed because their TTL expired.

These counters tell you how the cache is doing. For example:

```elixir
iex> stats = MyApp.Cache.info!(:stats)
iex> hit_rate = stats.hits / (stats.hits + stats.misses)
iex> IO.inspect(hit_rate, label: "Cache hit rate")
```

## Telemetry Metrics

Now let's see how to report metrics out of the info data.

First, add the `:telemetry`, `:telemetry_metrics`, and `:telemetry_poller`
packages as dependencies in your `mix.exs`.

Create your Telemetry supervisor at `lib/my_app/telemetry.ex`:

```elixir
# lib/my_app/telemetry.ex
defmodule MyApp.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      # Configure `:telemetry_poller` for reporting the cache stats
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},

      # For example, we use the console reporter, but you can change it.
      # See `:telemetry_metrics` for more information.
      {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp metrics do
    [
      # Stats
      last_value("my_app.cache.info.stats.hits", tags: [:cache]),
      last_value("my_app.cache.info.stats.misses", tags: [:cache]),
      last_value("my_app.cache.info.stats.writes", tags: [:cache]),
      last_value("my_app.cache.info.stats.evictions", tags: [:cache]),

      # Memory
      last_value("my_app.cache.info.memory.used", tags: [:cache]),
      last_value("my_app.cache.info.memory.total", tags: [:cache])
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :cache_stats, []},
      {__MODULE__, :cache_memory, []}
    ]
  end

  def cache_stats do
    with {:ok, info} <- MyApp.Cache.info([:server, :stats]) do
      :telemetry.execute(
        [:my_app, :cache, :info, :stats],
        info.stats,
        %{cache: info.server[:cache_name]}
      )
    end

    :ok
  end

  def cache_memory do
    with {:ok, info} <- MyApp.Cache.info([:server, :memory]) do
      :telemetry.execute(
        [:my_app, :cache, :info, :memory],
        info.memory,
        %{cache: info.server[:cache_name]}
      )
    end

    :ok
  end
end
```

Then add it to your main application's supervision tree
(usually in `lib/my_app/application.ex`):

```elixir
children = [
  MyApp.Cache,
  MyApp.Telemetry,
  ...
]
```

Now start an IEx session and you should see output like this:

```
[Telemetry.Metrics.ConsoleReporter] Got new event!
Event name: my_app.cache.info.stats
All measurements: %{evictions: 2, hits: 1, misses: 2, writes: 2}
All metadata: %{cache: MyApp.Cache}

Metric measurement: :hits (last_value)
With value: 1
Tag values: %{cache: MyApp.Cache}

Metric measurement: :misses (last_value)
With value: 2
Tag values: %{cache: MyApp.Cache}

Metric measurement: :writes (last_value)
With value: 2
Tag values: %{cache: MyApp.Cache}

Metric measurement: :evictions (last_value)
With value: 2
Tag values: %{cache: MyApp.Cache}

[Telemetry.Metrics.ConsoleReporter] Got new event!
Event name: my_app.cache.info.memory
All measurements: %{total: 2000000, used: 0}
All metadata: %{cache: MyApp.Cache}

Metric measurement: :total (last_value)
With value: 2000000
Tag values: %{cache: MyApp.Cache}

Metric measurement: :used (last_value)
With value: 0
Tag values: %{cache: MyApp.Cache}
```

### Custom metrics

In the same way, you can add another periodic measurement for reporting the
cache size:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local

  def dispatch_cache_size do
    :telemetry.execute(
      [:my_app, :cache, :size],
      %{value: count_all()},
      %{cache: __MODULE__, node: node()}
    )
  end
end
```

Now let's add a new periodic measurement to invoke `dispatch_cache_size()`
through `:telemetry_poller`:

```elixir
defp periodic_measurements do
  [
    {__MODULE__, :cache_stats, []},
    {__MODULE__, :cache_memory, []},
    {MyApp.Cache, :dispatch_cache_size, []}
  ]
end
```

> Notice the node name was added to the metadata so we can use it in the
> metric tags.

Metrics:

```elixir
defp metrics do
  [
    # Stats
    last_value("my_app.cache.info.stats.hits", tags: [:cache]),
    last_value("my_app.cache.info.stats.misses", tags: [:cache]),
    last_value("my_app.cache.info.stats.writes", tags: [:cache]),
    last_value("my_app.cache.info.stats.evictions", tags: [:cache]),

    # Memory
    last_value("my_app.cache.info.memory.used", tags: [:cache]),
    last_value("my_app.cache.info.memory.total", tags: [:cache]),

    # Nebulex custom Metrics
    last_value("my_app.cache.size.value", tags: [:cache, :node])
  ]
end
```

If you start an IEx session as before, you should see the new metric too:

```
[Telemetry.Metrics.ConsoleReporter] Got new event!
Event name: my_app.cache.size
All measurements: %{value: 0}
All metadata: %{cache: MyApp.Cache, node: :nonode@nohost}

Metric measurement: :value (last_value)
With value: 0
Tag values: %{cache: MyApp.Cache, node: :nonode@nohost}
```

## Interpreting the Metrics

Once you have metrics flowing, here is how to read them. The thresholds are
rough guides, not rules.

Cache hit rate, as a percentage of successful lookups:

```elixir
hit_rate = hits / (hits + misses) * 100
```

- Above 80% usually means the cache is well sized.
- Below 30% may mean the cache is too small or the TTL too short.
- 0% means the cache is not being used.

Memory usage:

```elixir
utilization = used / total * 100
```

- Utilization that stays above 90% leads to frequent evictions.
- Memory that keeps growing over time can point to a leak.
- Spikes often line up with batch operations.

Evictions over time:

- Evictions going up usually mean the cache is too small.
- Sudden spikes may mean an unusual access pattern.
- High evictions together with a low hit rate point to a configuration
  problem.

Activity:

- `writes + updates` is how often the cache is written to.
- `deletions` is the cache turnover. With the default stats handler an
  expired entry counts as a deletion, an eviction, and an expiration at the
  same time, so do not add the three counters together.

## Poller Interval and Configuration

With `period: 10_000`, `:telemetry_poller` reports the cache stats every 10
seconds. Pick what fits your needs:

```elixir
# Every 5 seconds - for closely monitoring cache behavior (more overhead)
{:telemetry_poller, measurements: periodic_measurements(), period: 5_000},

# Every 10 seconds - good default for most applications
{:telemetry_poller, measurements: periodic_measurements(), period: 10_000},

# Every 30 seconds - for low-overhead monitoring in production
{:telemetry_poller, measurements: periodic_measurements(), period: 30_000},
```

Trade-offs:

- Shorter periods: more frequent updates and more overhead, better at catching
  quick changes.
- Longer periods: less overhead, less precise, enough for long-term trends.
- You can use different periods per environment (dev, staging, production).

## Monitoring Multiple Cache Instances

If your application uses multiple cache instances or dynamic caches, you can
track them separately by including cache metadata in the telemetry event:

```elixir
def cache_stats do
  with {:ok, info} <- MyApp.Cache.info([:server, :stats]) do
    :telemetry.execute(
      [:my_app, :cache, :info, :stats],
      info.stats,
      %{
        cache: info.server[:cache_name],
        cache_module: info.server[:cache_module]
      }
    )
  end

  :ok
end
```

Then in your metrics, group by cache instance:

```elixir
last_value("my_app.cache.info.stats.hits",
  tags: [:cache, :cache_module],
  tag_values: &%{
    cache: &1.cache,
    cache_module: &1.cache_module
  }
)
```

## Adapter-Specific Information

The Info API is adapter-specific. `Nebulex.Adapters.Local` provides the
stats and memory keys shown in this guide; other adapters may provide
different keys.

Check your adapter's documentation for:

- The available info keys (`:stats`, `:memory`, `:server`, and so on).
- What each stat means for that adapter.
- Adapter-specific configuration options.
- The cost of calling the Info API itself.

For example, some adapters may not support all the stats, or may measure
memory differently for distributed caches.
