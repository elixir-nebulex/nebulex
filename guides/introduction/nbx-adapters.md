# Official adapters

These are the official adapters:

| Cache | Nebulex Adapter | Dependency |
|:------|:----------------|:-----------|
| Nil (special adapter to disable caching) | `Nebulex.Adapters.Nil` | Built-In |
| Generational Local Cache | [Nebulex.Adapters.Local][la] | [nebulex_local][nebulex_local] |
| Partitioned | [Nebulex.Adapters.Partitioned][pa] | [nebulex_distributed][nebulex_distributed] |
| Multilevel | [Nebulex.Adapters.Multilevel][ma] | [nebulex_distributed][nebulex_distributed] |
| Coherent | [Nebulex.Adapters.Coherent][ca] | [nebulex_distributed][nebulex_distributed] |
| Replicated | [Nebulex.Adapters.Replicated][ra] | [nebulex_distributed][nebulex_distributed] |
| Redis | [Nebulex.Adapters.Redis][nbx_redis] | [nebulex_redis_adapter][nebulex_redis_adapter] |
| Cachex | [Nebulex.Adapters.Cachex][nbx_cachex] | [nebulex_adapters_cachex][nebulex_adapters_cachex] |
| DiskLFU | [Nebulex.Adapters.DiskLFU][disk_lfu] | [nebulex_disk_lfu][nebulex_disk_lfu] |

[la]: https://hexdocs.pm/nebulex_local/Nebulex.Adapters.Local.html
[pa]: https://hexdocs.pm/nebulex_distributed/Nebulex.Adapters.Partitioned.html
[ma]: https://hexdocs.pm/nebulex_distributed/Nebulex.Adapters.Multilevel.html
[ca]: https://hexdocs.pm/nebulex_distributed/Nebulex.Adapters.Coherent.html
[ra]: https://hexdocs.pm/nebulex_distributed/Nebulex.Adapters.Replicated.html
[nbx_redis]: https://hexdocs.pm/nebulex_redis_adapter
[nbx_cachex]: https://hexdocs.pm/nebulex_adapters_cachex
[disk_lfu]: https://hexdocs.pm/nebulex_disk_lfu
[nebulex_local]: https://github.com/elixir-nebulex/nebulex_local
[nebulex_distributed]: https://github.com/elixir-nebulex/nebulex_distributed
[nebulex_redis_adapter]: https://github.com/elixir-nebulex/nebulex_redis_adapter
[nebulex_adapters_cachex]: https://github.com/elixir-nebulex/nebulex_adapters_cachex
[nebulex_disk_lfu]: https://github.com/elixir-nebulex/nebulex_disk_lfu

Each adapter's documentation explains how to set it up. For the API
reference, see the [Nebulex Cache API](`Nebulex.Cache`).

> #### Nebulex v3 compatibility {: .info}
>
> All the official adapters listed above support Nebulex v3. Nebulex v3.1
> requires adapters built for v3.1, since they must implement
> `Nebulex.Adapter.CompositeKV`; use the adapter releases that depend on
> `{:nebulex, "~> 3.0"}`.

## Non-official adapters

Adapters maintained outside the Nebulex organization:

| Cache | Nebulex Adapter | Dependency |
| :-----| :---------------| :--------- |
| Distributed with Horde | Nebulex.Adapters.Horde | [nebulex_adapters_horde][nbx_horde] |
| Multilevel with cluster broadcasting | NebulexLocalMultilevelAdapter | [nebulex_local_multilevel_adapter][nbx_local_multilevel] |
| Ecto Postgres table | Nebulex.Adapters.Ecto | [nebulex_adapters_ecto][nebulex_adapters_ecto] |

[nbx_horde]: https://github.com/eliasdarruda/nebulex_adapters_horde
[nbx_local_multilevel]: https://github.com/slab/nebulex_local_multilevel_adapter
[nebulex_adapters_ecto]: https://github.com/hissssst/nebulex_adapters_ecto
