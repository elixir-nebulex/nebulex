# Official adapters

Currently we officially support the following adapters:

| Cache | Nebulex Adapter | Dependency |
|:------|:----------------|:-----------|
| Nil (special adapter to disable caching) | [Nebulex.Adapters.Nil][nil] | Built-In |
| Generational Local Cache | [Nebulex.Adapters.Local][la] | [nebulex_local][la] |
| Partitioned | [Nebulex.Adapters.Partitioned][pa] | [nebulex_distributed][pa] |
| Multilevel | [Nebulex.Adapters.Multilevel][ma] | [nebulex_distributed][ma] |
| Redis | [Nebulex.Adapters.Redis][nbx_redis] | [nebulex_redis_adapter][nbx_redis] |
| Cachex | [Nebulex.Adapters.Cachex][nbx_cachex] | [nebulex_adapters_cachex][nbx_cachex] |
| DiskLFU | [Nebulex.Adapters.DiskLFU][disk_lfu] | [nebulex_disk_lfu][disk_lfu] |

[nil]: http://hexdocs.pm/nebulex/3.0.0-rc.1/Nebulex.Adapters.Nil.html
[la]: http://hexdocs.pm/nebulex_local/3.0.0-rc.1/Nebulex.Adapters.Local.html
[pa]: http://hexdocs.pm/nebulex_distributed/3.0.0-rc.1/Nebulex.Adapters.Partitioned.html
[ma]: http://hexdocs.pm/nebulex_distributed/3.0.0-rc.1/Nebulex.Adapters.Multilevel.html
[nbx_redis]: http://hexdocs.pm/nebulex_redis_adapter/3.0.0-rc.1/Nebulex.Adapters.Redis.html
[nbx_cachex]: http://hexdocs.pm/nebulex_adapters_cachex/3.0.0-rc.1/Nebulex.Adapters.Cachex.html
[disk_lfu]: https://github.com/elixir-nebulex/nebulex_disk_lfu

The adapter documentation links above will help you get started with your
adapter of choice. For API reference, you can check out the
[Nebulex documentation](http://hexdocs.pm/nebulex/3.0.0-rc.1/Nebulex.html).
