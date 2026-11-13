---
name: dotnet-redis
description: Usar Redis corretamente em .NET com StackExchange.Redis 3.x - ConnectionMultiplexer singleton, configuração (timeouts, abortConnect, TLS, ACL/Entra), resiliência e reconexão, exceções e retry, async sem sync-over-async, timeouts e diagnóstico, pipelining, transações e operações condicionais, scripts Lua, chaves/valores e TTL, SCAN vs KEYS, cluster/hash tags, padrões (cache-aside, lock distribuído, pub/sub), eviction/persistência, segurança e integração com ASP.NET Core (IDistributedCache, HybridCache). Use quando o usuário pedir cache Redis, locks, pub/sub, "Redis está dando timeout", ou revisar código com Redis. Based on official docs - StackExchange.Redis e Redis (externas) + Microsoft Learn (Azure Managed Redis, Cache-Aside).
---

# Redis em .NET (StackExchange.Redis 3.x)

**Proveniência:** **[SER]** documentação oficial do **StackExchange.Redis** (pasta `docs` do repositório; a versão estável atual no NuGet é a série **3.x**; **4.0 está em alpha**), **[REDIS]** documentação oficial do **Redis** (redis.io) e **[MS]** Microsoft Learn (Azure Managed Redis, padrão Cache-Aside). Convenções minhas: **CONVENÇÃO**. Onde algo não foi lido, está dito.
Ligações: `aspnet-caching` (IDistributedCache/HybridCache/output cache), `aspnet-signalr` (backplane), `aspnet-identity-data-protection`, `csharp-async-await`, `dotnet-production-diagnostics`, `dotnet-observability`, `dotnet-security-review`, `dotnet-messaging`/`dotnet-rabbitmq` (mensageria durável), `dotnet-local-dev-containers`.

## Escolha: ASP.NET `IDistributedCache`/`HybridCache` × StackExchange.Redis direto
- **Só cache de dados/respostas:** prefira as abstrações do ASP.NET (`AddStackExchangeRedisCache`, `HybridCache`, ver `aspnet-caching`).
- **Estruturas do Redis (hash, set, sorted set, stream), contadores, locks, pub/sub, scripts Lua, SCAN:** use `StackExchange.Redis` direto. (A doc do Redis cita ainda a lib **NRedisStack** para módulos — JSON, busca, vetores, probabilísticas — construída sobre o SE.Redis.)

## Conexão: `ConnectionMultiplexer` é compartilhado e reutilizado [SER]
- É **thread-safe** e feito para ser **compartilhado**: **não crie um por operação** (a doc diz ser "excepcionalmente raro" usar `using`). `GetDatabase()`, `GetSubscriber()`, `GetServer()` são objetos **baratos (pass-through)**: não precisa guardar.
- **CONVENÇÃO (ASP.NET Core):** registre `IConnectionMultiplexer` como **singleton**, criado **uma vez** com `await ConnectionMultiplexer.ConnectAsync(options)`; `IDatabase` pode ser obtido por requisição.
- Vários nós (primary/replica): liste todos (`"server1:6379,server2:6379"`); ele identifica o primário. **Cluster não suporta múltiplos databases**.
- **Configuração** (string ou `ConfigurationOptions`) — padrões da doc:
| Opção | Padrão | Observação |
|---|---|---|
| `abortConnect`/`AbortOnConnectFail` | `true` (**`false` no Azure**) | com `true`, `Connect` falha se nenhum servidor estiver disponível; **a Microsoft recomenda `false` e deixar o multiplexer reconectar** |
| `connectRetry` / `connectTimeout` | 3 / 5000 ms | |
| `syncTimeout` / `asyncTimeout` | 5000 ms / = sync | **timeout menor não deixa o comando mais rápido, só falha antes** |
| `keepAlive` | −1 (60 s efetivo) | |
| `ssl`, `sslHost`, `sslProtocols` | `false` | TLS (reconhecido automaticamente em Azure Managed Redis) |
| `user` / `password` | null (usuário `default`) | ACLs do Redis 6+ |
| `name` / `ClientName` | null | **identifique o app** (aparece em `CLIENT LIST`) |
| `allowAdmin` | `false` | habilita comandos "arriscados" — mantenha desligado |
| `defaultDatabase` | null | |
- **Autenticação/segurança:** `ssl=true` em produção; usuário/senha; **Azure Managed Redis: Microsoft Entra ID / managed identity** via pacote `Microsoft.Azure.StackExchangeRedis` (`ConfigureForAzureWithUserAssignedManagedIdentityAsync`) em vez de chave. Segredos fora do código (`aspnet-configuration-options`).

## Resiliência e erros
- **Eventos** do `ConnectionMultiplexer` (falha/restauração de conexão, mudança de configuração, `ServerMaintenanceEvent` — o Azure avisa antes de manutenção): **logue-os** para monitorar e diagnosticar.
- **Exceções [REDIS/SER]:** `RedisConnectionException` (conexão recusada/perdida — recuperável: retry com backoff ou fallback), `RedisTimeoutException` (recuperável: retry com backoff), `RedisCommandException` (comando/argumento inválido — **bug**: corrija; ex.: `StringGet` em chave de lista), `RedisServerException` (operação inválida no servidor — corrija). Padrões documentados: **fail fast**, **degradação graciosa** (ex.: cache fora ⇒ ler do banco e logar warning) e **retry com backoff exponencial**.
- **`ForceReconnect` [MS]:** em casos raros o SE.Redis não reconecta; a Microsoft recomenda o padrão **singleton com opção de forçar reconexão periodicamente** (criar novo multiplexer e descartar o antigo; trate `ObjectDisposedException` do antigo). Chame para `RedisConnectionException`/`RedisSocketException`; para timeouts **só** com `ReconnectMinInterval`/`ReconnectErrorThreshold` generosos — senão novas conexões podem causar **falha em cascata** num servidor já sobrecarregado. Há opção `UseForceReconnect` no pacote `Microsoft.Extensions.Caching.StackExchangeRedis` (ver a página da Microsoft).
- **Reconexões [MS]:** não crie muitas conexões ao mesmo tempo ao reconectar (criação é limitada por taxa); escalone; feche e remova conexões antigas (limite por tier). **Linux:** os TCP settings padrão de algumas distribuições podem fazer a conexão **não se recuperar por 13 min ou mais**; a doc recomenda ajustar. **Conexões ociosas:** o Azure Managed Redis fecha após **10 min** ociosas ⇒ `keepAlive` menor que isso (ou `PING` periódico).
- **Mesma região** do app; use **hostname**, nunca IP público (pode mudar); **alertas** em memória usada, CPU e clientes conectados (acima de **75%** de forma consistente ⇒ escalar). TLS 1.2/1.3.

## Async: nunca bloqueie em chamada Redis [SER]
- **`.Result`/`.Wait()`/`.GetAwaiter().GetResult()` em chamada async é *sync over async***: prende uma thread esperando uma resposta que **também precisa de uma thread** para ser processada ⇒ **starvation do thread pool**; os timeouts parecem de rede/servidor mas não são (sinal: timeout reportando **dados já no socket**). **Correção única: `await`.** **Trocar para a API síncrona não resolve.** O analyzer do SE.Redis alerta (**SER307/SER308**). Ver `csharp-async-await`, `dotnet-production-diagnostics` (ThreadPool starvation).
- **Thread theft** só ocorre em **.NET Framework clássico** (com `SynchronizationContext` síncrono); em .NET Core/5+ não se aplica.
- **Diagnóstico de timeout (doc *Timeouts*):** veja na mensagem `qs` (requisições aguardando), `rs`, `in`, estatísticas IOCP/WORKER/POOL; cheque **CPU/banda** de cliente e servidor, **comandos lentos** (`SLOWLOG`; `KEYS *`, `MGET` com muitas chaves, Lua mal escrito), **requisição grande antes de várias pequenas** (uma conexão TCP, uma resposta por vez), e thread pool saturado. (Pacote 3.0 removeu o pool dedicado `SocketManager`/`mgr`; vale o pool global.)

## Desempenho e operações
- **Pipelining:** inicie várias operações async **sem aguardar uma a uma** e aguarde depois (`Task.WhenAll`); reduz latência e pacotes. **Fire-and-forget:** `flags: CommandFlags.FireAndForget` — retorna **default imediatamente** (null/0): use só quando não importa o resultado (ex.: contador de visitas, renovar expiração).
- **Valores pequenos e mais chaves [MS]:** valores grandes causam timeouts em outros comandos da mesma conexão; divida dados grandes; mais banda na VM ajuda; pode usar mais de um multiplexer (round-robin) em casos de alto volume.
- **Transações (MULTI/EXEC):** **não são como SQL** — os comandos ficam em fila, você **não decide dentro** da transação. Para "só se": `tran.AddCondition(Condition.HashNotExists(...))` + `Execute()` (usa WATCH por baixo); `committed=false` se a condição falhou. **Prefira um comando condicional/atômico** quando existir — o analyzer sugere (**SER300–SER303**). **Redis 8.4+:** CAS/CAD com `ValueCondition` (`StringSetAsync(..., when: ValueCondition.Equal(x))`, `StringDeleteAsync(..., when: ...)`) elimina transações/Lua para compare-and-set.
- **Scripts Lua:** `ScriptEvaluateResp(script, keys, values)` — **chaves em `KEYS`, valores em `ARGV`** (só as chaves participam do roteamento de slot/prefixo); o script é cacheado (`EVAL` na 1ª vez, depois `EVALSHA`, com retry transparente em `NOSCRIPT`); variante **read-only** (`EVAL_RO`) pode ir a replica; `LuaScript` (`@nome`) é legado.
- **Cluster:** 16384 hash slots; comandos multi-chave só funcionam se as chaves caem no **mesmo slot** ⇒ **hash tags** `{grupo}:1` — mas **não abuse** (muitas chaves no mesmo slot degradam). `KEYS/SCAN`, `FLUSHDB` etc. são por **servidor**, não por database lógico.

## Chaves, valores e expiração [REDIS]
- **Esquema de nomes** `tipo-do-objeto:id` (ex.: `user:1000`); **evite chaves muito longas** (1024 bytes é ruim) e muito curtas ilegíveis.
- **Toda chave de cache deve ter TTL** (CONVENÇÃO coerente com o padrão Cache-Aside [MS]: expiração adequada ao padrão de acesso — **nem curta demais** (recarrega sempre) **nem longa demais** (dado velho)). Expiração deslizante manual: `KeyExpire(key, ttl, FireAndForget)` a cada leitura.
- **Nunca `KEYS *` em produção** (bloqueia o servidor; a Microsoft também manda evitar). O SE.Redis oferece `server.Keys(pattern)` (sem `Async`) que **usa `SCAN` quando disponível** e pagina internamente; obtenha o `IServer` de **cada nó**. `FlushDatabase()` limpa só o servidor atual (comandos "arriscados" são habilitados por `allowAdmin`).

## Padrões
- **Cache-Aside [MS]:** ler do cache; em miss, buscar no banco, **gravar no cache** e retornar; na escrita, **gravar no banco e invalidar** o item. **Não garante consistência** (alteração externa só aparece quando recarregar); entre escrita e próxima leitura há **miss ou dado levemente velho** (se precisa de read-after-write, considere write-through); cache pode **evictar**; **não cache dados sensíveis/de segurança** compartilhados; cache local por instância diverge entre instâncias ⇒ cache distribuído; **não use** quando o dataset é estático (pré-carregue) ou quando quase não há hits; **não use** para *session state* em web farm (a doc manda evitar dependência de afinidade cliente-servidor).
- **Lock distribuído [REDIS/SER]:** instância única: `SET recurso <valor-aleatório-único> NX PX <ttl>`; **liberar só se o valor for o seu** (compare-and-delete) — senão você apaga o lock de outro. No SE.Redis: `LockTakeAsync(key, token, expiry)` → trabalho → `LockExtendAsync` (falha = lock expirou/foi tomado) → `LockReleaseAsync` (em `finally`). Escolha o TTL com folga. **Replicação do Redis é assíncrona**: com failover dois clientes podem segurar o lock (**violação de exclusão mútua**); a doc propõe o algoritmo **Redlock** (maioria de nós independentes) quando isso importa; se uma condição de corrida ocasional é aceitável, instância única serve. Para exclusão mútua rigorosa, considere o banco (`efcore-saving-concurrency`).
- **Pub/Sub [SER]:** `GetSubscriber().Subscribe(...)` (assinaturas **globais**, não presas ao `ISubscriber`); o multiplexer **reassina automaticamente** após reconexão; **exceções no handler são engolidas** — use `try/catch` dentro dele; `ChannelMessageQueue.OnMessage` (síncrono ou async) para processamento ordenado (ver *Pub/Sub Message Order*). **Não é fila durável**: a página de pub/sub do Redis não foi lida nesta pesquisa — para mensagens que não podem se perder use RabbitMQ/Service Bus (`dotnet-rabbitmq`, `dotnet-messaging`) ou Redis **Streams** (doc `Streams` do SE.Redis).
- **Failover geográfico (client-side) [SER]:** recurso para endpoints Active-Active; sem replicação entre os endpoints você muda para **outro conjunto de dados** (aceitável para cache recarregável, não para store durável).

## Memória, eviction e persistência
- **`maxmemory`** padrão em 64-bit é **0 = sem limite**; ao atingir o limite vale a **`maxmemory-policy`**: `noeviction` (erro nas escritas), `allkeys-lru`, `allkeys-lfu`, `allkeys-lrm`, `allkeys-random`, e variantes `volatile-*` (só chaves com TTL). Com replicação/persistência, **deixe RAM livre para buffers**. Para **cache** escolha uma política de eviction; para **dados** que não podem sumir, `noeviction` + capacidade/alertas.
- **Redis é efêmero por padrão** [MS]: perda de dados é possível em manutenção/falha; para dados sensíveis a perda ligue **persistência** ou backup (no Azure Managed Redis, backup periódico usa **import/export**, não a persistência); **alta disponibilidade desligada só em dev/teste**.

## Segurança [REDIS]
- O Redis é **projetado para clientes confiáveis em ambientes confiáveis**: **não exponha à internet**; restrinja a porta por firewall/rede, `bind` a interfaces específicas, **protected mode** (padrão sem senha), **ACLs**, **TLS**. Acesso de clientes não confiáveis só por uma camada com ACL e validação. Um `FLUSHALL` externo apaga tudo ⇒ `allowAdmin=false` no app, usuário com mínimo de comandos. **CONVENÇÃO:** valide dados vindos do cliente antes de usá-los em nomes de chave e passe valores a scripts Lua via `ARGV`, não por concatenação no texto do script.

## Integração no ASP.NET Core
- `AddStackExchangeRedisCache` (`Microsoft.Extensions.Caching.StackExchangeRedis`) para `IDistributedCache` e L2 do `HybridCache` (`aspnet-caching`); **backplane do SignalR** (`aspnet-signalr`); armazenar **chaves do Data Protection** em Redis (`aspnet-identity-data-protection`) — como o Redis é efêmero, proteja contra perda do key ring.
- **Health check:** pacote de terceiros `AspNetCore.Diagnostics.HealthChecks` (`aspnet-health-checks`). **Testes:** Redis real em container (`dotnet-local-dev-containers`, `dotnet-integration-testing`); evite fingir Redis com mocks para validar timeout/serialização.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | `ConnectionMultiplexer` criado por operação/requisição (ou descartado em `using`) | Alta |
| 2 | `.Result`/`.Wait()`/`GetAwaiter().GetResult()` em chamadas Redis (SER307/308) | Alta |
| 3 | `KEYS *` em produção; `FlushDatabase`/`allowAdmin=true` no app | Alta |
| 4 | Redis exposto à internet/sem TLS/sem senha ou ACL; senha/chave no código; sem managed identity onde cabe | Alta |
| 5 | Lock sem valor único/TTL, liberação sem verificar dono; exclusão mútua assumida com failover | Alta |
| 6 | Cache sem TTL; TTL inadequado; sem invalidação na escrita; dado sensível no cache | Média |
| 7 | Sem tratamento de `RedisConnectionException`/`Timeout` (sem fallback/retry com backoff); retry sem limite | Média |
| 8 | Timeouts "diminuídos para ficar rápido"; `abortConnect=true` derrubando o startup em nuvem; sem logs dos eventos de conexão | Média |
| 9 | Valores muito grandes numa chave (timeouts em outros comandos); pipelining ausente em loops de comandos | Média |
| 10 | Pub/Sub como fila durável; handler sem `try/catch` | Média |
| 11 | Transação MULTI/EXEC onde um comando condicional/CAS resolveria (SER300–303); multi-chave em cluster sem hash tag | Média |
| 12 | `maxmemory-policy` inadequada ao uso (`noeviction` em cache / eviction em dados que não podem sumir); sem alerta de memória | Média |
| 13 | Muitos clientes reconectando ao mesmo tempo; conexões antigas não descartadas; keepalive ≥ timeout ocioso do serviço | Baixa |

## Fontes
**[SER] StackExchange.Redis (docs do projeto):** https://stackexchange.github.io/StackExchange.Redis/ · Basics, Configuration, Timeouts, Sync over async, Transactions, Scripting, KeysScan, Compare-And-Swap, Failover, Authentication: https://github.com/StackExchange/StackExchange.Redis/tree/main/docs
**[REDIS] Redis:** Produção com .NET https://redis.io/docs/latest/develop/clients/dotnet/produsage/ · Error handling .NET https://redis.io/docs/latest/develop/clients/dotnet/error-handling/ · Eviction https://redis.io/docs/latest/develop/reference/eviction/ · Segurança https://redis.io/docs/latest/operate/oss_and_stack/management/security/ · Chaves https://redis.io/docs/latest/develop/using-commands/keyspace/ · Locks distribuídos https://redis.io/docs/latest/develop/clients/patterns/distributed-locks/
**[MS] Microsoft Learn:** Resiliência de conexão (Azure Managed Redis) https://learn.microsoft.com/en-us/azure/redis/best-practices-connection · Desenvolvimento https://learn.microsoft.com/en-us/azure/redis/best-practices-development · Gerenciamento de memória https://learn.microsoft.com/en-us/azure/redis/best-practices-memory-management · Cache-Aside https://learn.microsoft.com/en-us/azure/architecture/patterns/cache-aside
