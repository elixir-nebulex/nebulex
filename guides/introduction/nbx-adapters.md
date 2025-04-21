# Official adapters

Currently we officially support the folloawing adapters:

Cache | Nebulex Adapter | Dependency
:-----| :---------------| :---------
Nil (special adapter to disable caching) | [Nebulex.Adapters.Nil][nil] | Built-In
Generational Local Cache | Nebulex.Adapters.Local | [nebulex_local][la]
Partitioned | Nebulex.Adapters.Partitioned | [nebulex_distributed][pa]
Multilevel | Nebulex.Adapters.Multilevel | [nebulex_distributed][ma]
Redis | NebulexRedisAdapter | [nebulex_redis_adapter][nbx_redis]
Cachex | Nebulex.Adapters.Cachex | [nebulex_adapters_cachex][nbx_cachex]

[nil]: http://hexdocs.pm/nebulex/Nebulex.Adapters.Nil.html
[la]: http://hexdocs.pm/nebulex_local/Nebulex.Adapters.Local.html
[pa]: http://hexdocs.pm/nebulex_distributed/Nebulex.Adapters.Partitioned.html
[ma]: http://hexdocs.pm/nebulex_distributed/Nebulex.Adapters.Multilevel.html
[nbx_redis]: https://hexdocs.pm/nebulex_redis_adapter/Nebulex.Adapters.Redis.html
[nbx_cachex]: https://hexdocs.pm/nebulex_adapters_cachex/Nebulex.Adapters.Cachex.html

The adapter documentation links above will help you get started with your
adapter of choice. For API reference, you can check out the
[Nebulex documentation](http://hexdocs.pm/nebulex/Nebulex.html).
