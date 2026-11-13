---
name: aspnet-health-checks
description: Implementar e revisar health checks no ASP.NET Core - AddHealthChecks, MapHealthChecks, IHealthCheck, liveness vs readiness, probes de banco/EF Core, tags e filtros, status codes, RequireAuthorization/RequireHost, Docker HEALTHCHECK, Kubernetes, publishers. Use quando o usuário pedir endpoint de saúde, probes para contêiner/orquestrador ou revisar verificações de dependências. Based on official Microsoft Learn docs.
---

# Health checks no ASP.NET Core

Só afirmar o que a doc oficial diz (fontes no fim). Segurança de endpoints: `aspnet-authentication-authorization`. Logging: `aspnet-logging`.

## Básico
```csharp
builder.Services.AddHealthChecks();
app.MapHealthChecks("/healthz");
```
- Sem checks registrados, a app é "saudável" se **responde** no endpoint; o writer padrão devolve **texto puro** com o `HealthStatus` (Healthy/Degraded/Unhealthy).
- **Prefira `MapHealthChecks` a `UseHealthChecks`**: integra com middleware que reconhece endpoints (autorização, host, CORS) e dá controle fino.
- Docker `HEALTHCHECK`: precisa de `curl`/`wget` na imagem (`curl` não vem nas imagens Linux do .NET; Alpine tem `wget`).

## Criar checks
- Implemente `IHealthCheck` (`CheckHealthAsync`) e registre `AddCheck<MeuCheck>("nome", failureStatus: ..., tags: ...)`; lambda com `AddCheck("nome", () => HealthCheckResult.Healthy())`. `failureStatus` nulo = `Unhealthy`.
- **Probe de banco:** `AspNetCore.Diagnostics.HealthChecks` (biblioteca de terceiros, com check para SQL Server; **a Microsoft não a mantém nem dá suporte**) ou o check de `DbContext` com `AddDbContextCheck<T>()` (pacote `Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore`): por padrão chama `CanConnectAsync` do EF Core (overloads permitem outra operação). Atenção ao custo/segurança de verificações pesadas no endpoint.
- Checks podem usar DI (resolvidos conforme registro).
- Bibliotecas: exponha extension methods que recebem dados customizados.

## Opções do endpoint
- **`Predicate`** filtra quais checks rodam (ex.: por `tags`); **`ResultStatusCodes`** mapeia status → HTTP; **`AllowCachingResponses`** (padrão `false` = o middleware define `Cache-Control`/`Expires`/`Pragma` para impedir cache); **`ResponseWriter`** customiza a saída (ex.: JSON).
- **`RequireHost("*:5001")`** restringe host/porta (útil em contêiner para expor porta de monitoramento); **`RequireAuthorization()`** protege o endpoint; CORS se consumido por navegador.
- Não exponha detalhes internos (mensagens de exceção, strings de conexão) em endpoints públicos.

## Liveness × readiness
- **Liveness**: o processo travou/caiu e **precisa reiniciar**. **Readiness**: está pronto para receber tráfego (ex.: terminou de baixar configuração, conexões ok).
- Exemplo da doc: app que baixa um arquivo grande na partida e pode tentar de novo: **não reinicie** (liveness não executa os checks de dependência), mas **não receba requisições** até ficar pronto (readiness inclui o check). Implemente com **tags** (`ready`) e dois endpoints (`/healthz/live` com `Predicate = _ => false`, `/healthz/ready` com tag `ready`). Exemplo de probes Kubernetes na doc.

## Publisher
`IHealthCheckPublisher` publica resultados periodicamente (ex.: para métricas). `HealthCheckPublisherOptions`: `Delay` (5 s inicial), `Period` (30 s), `Predicate`, `Timeout` (30 s; `Timeout.InfiniteTimeSpan` sem timeout).

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Endpoint de saúde existe e é usado pelo orquestrador/load balancer |
| 2 | Liveness leve (sem dependências); readiness verifica dependências críticas |
| 3 | Endpoint exposto publicamente sem autorização/`RequireHost` quando retorna detalhes |
| 4 | Check de banco pesado ou sem timeout (derruba o app sob falha do banco) |
| 5 | Status codes mapeados conforme o orquestrador espera |
| 6 | Resposta com dados sensíveis |
| 7 | `UseHealthChecks` onde seria preciso autorização por endpoint (usar `MapHealthChecks`) |
| 8 | Contêiner sem `curl`/`wget` para o `HEALTHCHECK` |

## Fontes oficiais
- Health checks in ASP.NET Core: https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks
- Generic Host / workers (health em worker): https://learn.microsoft.com/en-us/dotnet/core/diagnostics/diagnostic-health-checks
