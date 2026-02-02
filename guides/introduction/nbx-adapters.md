# Official adapters

Currently we officially support the following adapters:

| Cache | Nebulex Adapter | Dependency |
|:------|:----------------|:-----------|
| Nil (special adapter to disable caching) | [Nebulex.Adapters.Nil][nil] | Built-In |
| Generational Local Cache | [Nebulex.Adapters.Local][la] | [nebulex_local][la] |
| Partitioned | [Nebulex.Adapters.Partitioned][pa] | [nebulex_distributed][pa] |
| Multilevel | [Nebulex.Adapters.Multilevel][ma] | [nebulex_distributed][ma] |
| Coherent | [Nebulex.Adapters.Coherent][ca] | [nebulex_distributed][ca] |
| Redis | [Nebulex.Adapters.Redis][nbx_redis] | [nebulex_redis_adapter][nbx_redis] |
| Cachex | [Nebulex.Adapters.Cachex][nbx_cachex] | [nebulex_adapters_cachex][nbx_cachex] |
| DiskLFU | [Nebulex.Adapters.DiskLFU][disk_lfu] | [nebulex_disk_lfu][disk_lfu] |

[nil]: http://hexdocs.pm/nebulex/3.0.0-rc.2/Nebulex.Adapters.Nil.html
[la]: http://hexdocs.pm/nebulex_local/3.0.0-rc.2/Nebulex.Adapters.Local.html
[pa]: http://hexdocs.pm/nebulex_distributed/3.0.0-rc.2/Nebulex.Adapters.Partitioned.html
[ma]: http://hexdocs.pm/nebulex_distributed/3.0.0-rc.2/Nebulex.Adapters.Multilevel.html
[ca]: http://hexdocs.pm/nebulex_distributed/3.0.0-rc.2/Nebulex.Adapters.Coherent.html
[nbx_redis]: http://hexdocs.pm/nebulex_redis_adapter/3.0.0-rc.2/Nebulex.Adapters.Redis.html
[nbx_cachex]: http://hexdocs.pm/nebulex_adapters_cachex/3.0.0-rc.2/Nebulex.Adapters.Cachex.html
[disk_lfu]: http://github.com/elixir-nebulex/nebulex_disk_lfu

The adapter documentation links above will help you get started with your
adapter of choice. For API reference, you can check out the
[Nebulex Cache API](http://hexdocs.pm/nebulex/3.0.0-rc.2/Nebulex.Cache.html).

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

[nbx_horde]: http://github.com/eliasdarruda/nebulex_adapters_horde
[nbx_local_multilevel]: http://github.com/slab/nebulex_local_multilevel_adapter
[nebulex_adapters_ecto]: http://github.com/hissssst/nebulex_adapters_ecto
