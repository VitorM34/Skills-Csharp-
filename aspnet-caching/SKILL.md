---
name: aspnet-caching
description: Implementar e revisar cache no ASP.NET Core - IMemoryCache, IDistributedCache (Redis, SQL Server), HybridCache, output caching, response caching (Cache-Control, [ResponseCache]), expiração absoluta/sliding, SizeLimit, chaves de cache, invalidação por tag, stampede. Use quando o usuário pedir para cachear dados ou respostas, escolher o tipo de cache ou revisar riscos (chaves vindas do usuário, cache de conteúdo autenticado). Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# Caching no ASP.NET Core

Só afirmar o que a doc oficial diz (fontes no fim). Desempenho geral: `aspnet-performance-best-practices`. Ordem de middlewares: `aspnet-middleware-pipeline`.

## Qual cache usar (doc "Overview of caching")
| Tipo | O que é | Quando |
|---|---|---|
| **In-memory** (`IMemoryCache`) | memória do servidor web | servidor único ou várias instâncias com **session affinity/sticky sessions** |
| **Distributed** (`IDistributedCache`) | cache externo (Redis, SQL Server, Postgres, NCache, Cosmos DB, memória distribuída p/ dev) | web farm sem sticky sessions; escala maior; tira memória do processo |
| **HybridCache** | cache L1 (local) + L2 opcional (`IDistributedCache`) com proteção a stampede | dados que se quer em dois níveis com API simples |
| **Response caching** | headers HTTP (`Cache-Control`) para clientes/proxies | respeita RFC 9111; **não** revalida (sem 304); só memória |
| **Output caching** | middleware que cacheia **no servidor** respostas HTTP, configurável no servidor | política do servidor, invalidação programática, locking anti-stampede, armazenamento extensível |
| Tag Helpers | `<cache>` e distributed cache tag helper (Razor) | fragmentos de view |

## Princípios
- Cache serve para dados que **mudam pouco e são caros de gerar**. **O app nunca deve depender do valor em cache**: sempre ter fallback para buscar na origem.
- **Nunca use entrada externa como chave** (strings do usuário): consome memória imprevisível e permite ataques (negação de serviço por flood de chaves, acesso indevido). Use identificadores confiáveis.
- Apps em web farm sem sticky sessions → cache distribuído para evitar inconsistência.

## IMemoryCache (`Microsoft.Extensions.Caching.Memory`)
- Recomendado sobre `System.Runtime.Caching/MemoryCache` (integra com DI).
- Sempre `GetOrCreate`/fallback; **combine sliding com absolute expiration**: somente sliding pode **nunca expirar** se for acessado continuamente; a absoluta define um teto.
- **Sem `SizeLimit` o cache cresce sem limite** e o runtime **não faz trim sob pressão de memória**: o app precisa limitar. Com `SizeLimit` (sem unidade definida; todos os usuários usam a mesma unidade) **toda entrada deve informar `Size`**; entradas que estourem o limite não são cacheadas. Cuidado com cache compartilhado com código de terceiros.
- `MemoryCache.Compact(percent)` remove em ordem de prioridade; itens `NeverRemove` nunca saem. Dependências de expiração (`IChangeToken`/callbacks) para evict.

## IDistributedCache
- Interface por bytes (`GetAsync/SetAsync/RemoveAsync/RefreshAsync`); `GetAsync<T>` pode retornar default quando a chave não existe (extensões para `T`).
- **Redis** entrega melhor desempenho e é **recomendado para produção** (Azure Cache for Redis); SQL Server: use um **SQL Server dedicado** para o cache (compartilhar o mesmo banco dos dados do app reduz desempenho); benchmarking recomendado. Connection strings/segredos fora do controle de versão.
- Manipule sempre via `IDistributedCache` (não `SqlServerCache`). Não precisa de lifetime Singleton/Scoped explícito para implementações embutidas; evitar criar instância "na mão" (testabilidade/Explicit Dependencies). Guarde só dados muito usados (memória é cara).

## HybridCache
```csharp
builder.Services.AddHybridCache();
var data = await hybridCache.GetOrCreateAsync($"order{customerId}-{orderId}", async ct => await LoadAsync(ct));
```
- `GetOrCreateAsync`: tenta L1; se falta, tenta L2 (se configurado); se falta, chama a **factory** e grava nos dois. **Somente um chamador concorrente por chave** executa a factory (os demais esperam; o cancelamento só ocorre quando todos cancelam; vale por instância). Overload sem estado é o recomendado.
- **Chaves:** identifique exclusivamente o dado; **evite entrada do usuário**; use delimitadores (`order{customerId}{orderId}` é ambíguo); string interpolada **inline** na chamada (permite otimizações futuras); limite padrão **1024 caracteres** (`MaximumKeyLength`; chaves maiores ignoram o cache); Unicode válido.
- `SetAsync` grava sem ler; `RemoveAsync` por chave; **`RemoveByTagAsync`** é invalidação **lógica** (regra "ignore tudo criado antes de agora"), não apaga fisicamente; a tag `*` é reservada e invalida tudo.

## Output caching
`AddOutputCache()` + `UseOutputCache()` **só disponibilizam**; é preciso configurar políticas (`[OutputCache]`, `.CacheOutput()`, políticas nomeadas/base).
- **Ordem:** `UseOutputCache` **depois de `UseCors`**, **depois de `UseRouting`**, e **depois de `UseAuthentication`/`UseAuthorization`** (senão pode servir conteúdo cacheado para usuários não autorizados).
- Regras padrão: só **HTTP 200**, só **GET/HEAD**. Dá para sobrescrever (POST, 301) com política customizada; ao usar política base customizada, não chame `OutputCache()` sem argumentos nem o atributo (adiciona a política padrão).
- **Chave padrão** = esquema + host + porta + caminho + query string; controle com `VaryByQuery`, `VaryByValue`, `UseCaseSensitivePaths` (padrão insensível).
- Revalidação (304), invalidação por tag, locking de recurso (evita cache stampede/thundering herd), armazenamento extensível.

## Response caching
- `[ResponseCache]` define headers (`Cache-Control`: `public/private`, `no-cache`, `no-store`, `max-age`, `Vary`). **Clientes podem forçar `no-cache`** e o servidor deve honrar (a meta é reduzir latência/rede, não proteger o servidor).
- **Desative cache para conteúdo autenticado/dependente do usuário.** Para `VaryByQueryKeys` precisa do middleware de response caching (senão exceção). `Duration` positiva e `Location` `Any`/`Client` para habilitar. `UseCors` antes de `UseResponseCaching`.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Chave de cache montada com entrada do usuário | Alta |
| 2 | Cache de resposta/saída de conteúdo por usuário sem `Vary`/sem autenticação antes | Alta |
| 3 | `MemoryCache` sem `SizeLimit` em carga variável; entradas sem `Size` com limite | Média |
| 4 | Só sliding expiration (nunca expira) | Média |
| 5 | Código que depende do cache (sem fallback) | Alta |
| 6 | `IMemoryCache` em web farm sem sticky sessions | Alta |
| 7 | Redis/SQL com connection string no repositório; SQL compartilhado com dados do app | Média |
| 8 | Cache stampede em item caro (usar HybridCache/output cache locking) | Média |
| 9 | `UseOutputCache`/`UseResponseCaching` fora de ordem (antes de CORS/auth/routing) | Alta |
| 10 | Invalidação ausente/estratégia de tags | Média |

## Fontes oficiais
- Overview: https://learn.microsoft.com/en-us/aspnet/core/performance/caching/overview
- In-memory: https://learn.microsoft.com/en-us/aspnet/core/performance/caching/memory
- Distributed: https://learn.microsoft.com/en-us/aspnet/core/performance/caching/distributed
- HybridCache: https://learn.microsoft.com/en-us/aspnet/core/performance/caching/hybrid
- Output caching: https://learn.microsoft.com/en-us/aspnet/core/performance/caching/output
- Response caching: https://learn.microsoft.com/en-us/aspnet/core/performance/caching/response
