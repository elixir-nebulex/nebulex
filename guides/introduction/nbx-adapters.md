# Official adapters

Currently we officially support the following adapters:

| Cache | Nebulex Adapter | Dependency |
|:------|:----------------|:-----------|
| Nil (special adapter to disable caching) | `Nebulex.Adapters.Nil` | Built-In |
| Generational Local Cache | [Nebulex.Adapters.Local][la] | [nebulex_local][la] |
| Partitioned | [Nebulex.Adapters.Partitioned][pa] | [nebulex_distributed][pa] |
| Multilevel | [Nebulex.Adapters.Multilevel][ma] | [nebulex_distributed][ma] |
| Coherent | [Nebulex.Adapters.Coherent][ca] | [nebulex_distributed][ca] |
| Redis | [Nebulex.Adapters.Redis][nbx_redis] | [nebulex_redis_adapter][nbx_redis] |
| Cachex | [Nebulex.Adapters.Cachex][nbx_cachex] | [nebulex_adapters_cachex][nbx_cachex] |
| DiskLFU | [Nebulex.Adapters.DiskLFU][disk_lfu] | [nebulex_disk_lfu][disk_lfu] |

[la]: https://hexdocs.pm/nebulex_local/Nebulex.Adapters.Local.html
[pa]: https://hexdocs.pm/nebulex_distributed/Nebulex.Adapters.Partitioned.html
[ma]: https://hexdocs.pm/nebulex_distributed/Nebulex.Adapters.Multilevel.html
[ca]: https://hexdocs.pm/nebulex_distributed/Nebulex.Adapters.Coherent.html
[nbx_redis]: https://hexdocs.pm/nebulex_redis_adapter/Nebulex.Adapters.Redis.html
[nbx_cachex]: https://hexdocs.pm/nebulex_adapters_cachex/Nebulex.Adapters.Cachex.html
[disk_lfu]: https://github.com/elixir-nebulex/nebulex_disk_lfu

The adapter documentation links above will help you get started with your
adapter of choice. For API reference, you can check out the
[Nebulex Cache API](`Nebulex.Cache`).

> [!NOTE]
>
> _**All the official adapters listed above support Nebulex v3.**_

## Non-official adapters

The following non-official adapters are available:

Cache | Nebulex Adapter | Dependency
:-----| :---------------| :---------
Distributed with Horde | Nebulex.Adapters.Horde | [nebulex_adapters_horde][nbx_horde]
Multilevel with cluster broadcasting | NebulexLocalMultilevelAdapter | [nebulex_local_multilevel_adapter][nbx_local_multilevel]
Ecto Postgres table | Nebulex.Adapters.Ecto | [nebulex_adapters_ecto][nebulex_adapters_ecto]

[nbx_horde]: https://github.com/eliasdarruda/nebulex_adapters_horde
[nbx_local_multilevel]: https://github.com/slab/nebulex_local_multilevel_adapter
[nebulex_adapters_ecto]: https://github.com/hissssst/nebulex_adapters_ecto
