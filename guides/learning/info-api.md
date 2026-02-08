# Info API

Since Nebulex v3, the adapter's Info API is introduced. This is a more generic
API to get information about the cache, including the stats. Adapters are
responsible for implementing the Info API and are also free to add the
information specification keys they want. Therefore, it is highly recommended
to review the adapter's documentation you're using.

> See `c:Nebulex.Cache.info/2` for more information.

Nebulex also provides a simple implementation `Nebulex.Adapters.Common.Info`,
which is used by the `Nebulex.Adapters.Local` adapter. This implementation uses
a Telemetry handler to aggregate the stats and keep them updated, therefore,
it requires `:telemetry` to be available.

> **Note**: The `:telemetry` dependency is optional but highly recommended
> for production environments. Add `{:telemetry, "~> 1.0"}` to your `mix.exs`
> to enable cache metrics and observability.

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
    cache_module: "MyCache",
    cache_adapter: "Nebulex.Adapters.Local",
    cache_name: "MyCache",
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

You could also request for a specific item or items:

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

The stats map includes the following metrics:

- **`hits`** - Number of successful `get` operations that found a value in the cache
- **`misses`** - Number of `get` operations that did not find a value (returned `nil`)
- **`writes`** - Number of `put` operations that added new entries to the cache
- **`updates`** - Number of `put` operations that updated existing cache entries
- **`deletions`** - Number of entries removed via `delete` operations
- **`evictions`** - Number of entries automatically removed due to exceeding `max_size`
- **`expirations`** - Number of entries automatically removed due to TTL expiration

These metrics are useful for understanding cache behavior and health. For example:

```elixir
iex> stats = MyApp.Cache.info!(:stats).stats
iex> hit_rate = stats.hits / (stats.hits + stats.misses)
iex> IO.inspect(hit_rate, label: "Cache hit rate")
```

## Telemetry Metrics

Now, let's see how we can provide metrics out of the info data.

First of all, make sure you have added `:telemetry`, `:telemetry_metrics`, and
`:telemetry_poller` packages as dependencies to your `mix.exs` file.

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

Now start an IEx session and you should see something like the following output:

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

If you start an IEx session like previously, you should see the new metric too:

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

Once you have metrics flowing, you can use them to understand cache health:

**Cache Hit Rate**

Calculate hit rate as a percentage of successful lookups:

```elixir
hit_rate = hits / (hits + misses) * 100
```

- Hit rates above 80% generally indicate a well-sized cache
- Low hit rates (<30%) may indicate the cache is too small or TTL too short
- A hit rate of 0% suggests the cache isn't being used effectively

**Memory Usage**

Monitor memory trends:

```elixir
utilization = used / total * 100
```

- Consistently high utilization (>90%) may trigger frequent evictions
- Growing memory usage over time can indicate memory leaks
- Spikes in memory can correlate with batch operations

**Eviction Rate**

Track evictions over time:

- Increasing evictions usually mean cache capacity is insufficient
- Sudden eviction spikes may indicate unusual access patterns
- High evictions combined with low hit rate suggests cache configuration issues

**Activity Indicators**

- `writes + updates` shows cache update frequency
- `deletions + evictions + expirations` shows cache turnover
- Imbalanced ratios can reveal inefficient access patterns

## Poller Interval and Configuration

The `:telemetry_poller` with `period: 10_000` reports cache stats every 10 seconds.
Consider your needs:

```elixir
# Every 5 seconds - for closely monitoring cache behavior (more overhead)
{:telemetry_poller, measurements: periodic_measurements(), period: 5_000},

# Every 10 seconds - good default for most applications
{:telemetry_poller, measurements: periodic_measurements(), period: 10_000},

# Every 30 seconds - for low-overhead monitoring in production
{:telemetry_poller, measurements: periodic_measurements(), period: 30_000},
```

Trade-offs:

- **Shorter periods**: More frequent updates, higher overhead, better precision for detecting rapid changes
- **Longer periods**: Lower overhead, less precise but sufficient for long-term trending
- **Adaptive**: You can use different periods in different environments (dev, staging, production)

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

The Info API is adapter-specific. While `Nebulex.Adapters.Local` provides the stats
and memory metrics shown in this guide, other adapters may provide different information keys.

Always consult your adapter's documentation for:

- Available info keys (`:stats`, `:memory`, `:server`, etc.)
- What each stat means in the adapter's context
- Any adapter-specific configuration options
- Performance characteristics of the Info API itself

For example, some adapters may not support all stat types or may have different
memory measurement approaches for distributed caches.
