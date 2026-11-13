---
name: dotnet-httpclient-resilience
description: Implementar e revisar chamadas HTTP em .NET - HttpClient, IHttpClientFactory (named/typed clients), DelegatingHandler, tempo de vida de conexões e DNS, SocketsHttpHandler, resiliência (AddStandardResilienceHandler, retry, circuit breaker, timeout, hedging), retries em POST. Use quando o usuário pedir para consumir APIs externas, revisar `new HttpClient()`, ou adicionar retry/timeout/circuit breaker. Based on official Microsoft Learn docs.
---

# HttpClient, IHttpClientFactory e resiliência

Só afirmar o que a doc oficial diz (fontes no fim). Async: `csharp-async-await`. DI: `dotnet-dependency-injection`.

## Tempo de vida do `HttpClient` (doc "Guidelines for using HttpClient")
- Cada `HttpClient` tem um **pool de conexões** (ligado ao `SocketsHttpHandler`). **Não crie e descarte um `HttpClient` a cada requisição** (esgota portas; o `Dispose` descarta o pool se o cliente é dono do handler).
- Use **uma das duas** estratégias: (a) **clientes de vida longa** com `PooledConnectionLifetime` (.NET Core/5+), ou (b) **clientes de vida curta criados por `IHttpClientFactory`**. Um número limitado de instâncias também é aceitável; vários podem ser necessários para múltiplos proxies ou para separar cookies.
- **DNS:** o `HttpClient` só resolve DNS ao criar a conexão e **não respeita TTL**; limite a vida das conexões com `SocketsHttpHandler.PooledConnectionLifetime` (a doc usa 15 min só como ilustração; escolha conforme a frequência de mudança).
- Se o app precisa de **cookies**, a doc recomenda **evitar `IHttpClientFactory`** (handlers em pool compartilham `CookieContainer` e vazam cookies; ao expirar `HandlerLifetime` o handler é reciclado e os cookies somem).
- Com a factory, `HttpClient` normalmente **não precisa de `Dispose`** (a factory gerencia). Handler lifetime padrão: **2 minutos** (configurável por cliente nomeado).

## `IHttpClientFactory` (doc ASP.NET Core "Make HTTP requests")
Benefícios: ponto central para **nomear e configurar** clientes lógicos; pool/reciclagem de handlers; **pipeline de handlers** (middleware de saída); integração com logging. Padrões de consumo:
- **Básico** (`AddHttpClient()` + `IHttpClientFactory.CreateClient()`).
- **Nomeado** (`AddHttpClient("github", c => { c.BaseAddress = ...; c.DefaultRequestHeaders.Add(...); })` + `CreateClient("github")`): muitos usos distintos / headers comuns; o request pode passar só o caminho.
- **Tipado** (`AddHttpClient<GitHubService>()`; o serviço recebe `HttpClient` no construtor): **recomendado pela doc quando se quer a configurabilidade da factory**; funciona com DI.
- **Gerado** (Refit etc., terceiros).
- **Typed client é registrado como transient**; a doc de factory tem uma seção "Avoid typed clients in singleton services" (um typed client capturado por um singleton pode deixar de reagir a mudanças de DNS, anulando um dos propósitos da factory). Opções da doc: **named client** injetando `IHttpClientFactory` no singleton e recriando o `HttpClient` quando preciso, ou, se precisar de typed client, `SocketsHttpHandler` com `PooledConnectionLifetime` como handler primário. O tipo precisa ter construtor que recebe `HttpClient` e **não** deve ser registrado separadamente no DI (o último registro sobrescreve o primeiro).
- POST/PUT/DELETE: `PostAsync`/`PutAsync`/`DeleteAsync`; use as extensões JSON (`PostAsJsonAsync`, `ReadFromJsonAsync`).
- **Handlers de saída** (`DelegatingHandler`): **devem ser registrados como Transient** (não singleton/scoped; reutilizar em vários pipelines lança `InvalidOperationException`); vários handlers executam na ordem registrada, cada um envolve o próximo.
- Logs de requisição/resposta por padrão em nível Information; headers só em Trace.
- Em console: `IHttpClientFactory` via Generic Host. `header propagation middleware` para repassar headers.

## Resiliência (doc `Microsoft.Extensions.Http.Resilience`)
- Pacote **`Microsoft.Extensions.Http.Polly` está obsoleto**: use `Microsoft.Extensions.Http.Resilience` (e `Microsoft.Extensions.Resilience` para pipelines genéricos).
- **Adicione apenas um handler de resiliência por cliente; não empilhe** (para vários, use `AddResilienceHandler` customizado).
```csharp
services.AddHttpClient<MyClient>().AddStandardResilienceHandler();
```
**Padrão do `AddStandardResilienceHandler`** (5 estratégias, de fora para dentro): (1) rate limiter (fila 0, 1.000 permissões), (2) timeout total 30 s (inclui retries), (3) retry (3 tentativas, backoff exponencial, jitter, atraso 2 s), (4) circuit breaker (falha 10%, throughput mínimo 100, amostragem 30 s, pausa 5 s), (5) timeout por tentativa 10 s. Tratam HTTP **≥ 500, 408, 429** e as exceções `HttpRequestException`/`TimeoutRejectedException` (Polly lança `TimeoutRejectedException`, não `TimeoutException`).
- **Retries em métodos não idempotentes:** por padrão tenta **todos os métodos**, o que pode duplicar dados (ex.: POST que insere). Use `options.Retry.DisableFor(HttpMethod.Post, HttpMethod.Delete)` ou `DisableForUnsafeHttpMethods()` (POST, PATCH, PUT, DELETE, CONNECT).
- **Hedging** (`AddStandardHedgingHandler`): executa contra vários endpoints se lento/falha transitória; pool de circuit breakers por **autoridade da URL** (esquema+host+porta); configure `SelectPipelineByAuthority`/`SelectPipelineBy`.
- **Pipelines genéricos:** `AddResiliencePipeline("chave", builder => ...)` e `ResiliencePipelineProvider<string>`; `AddResilienceEnricher` para métricas.
- Problemas conhecidos: gRPC client factory < 2.64.0 incompatível com `AddStandardResilienceHandler`; Application Insights < 2.23.0.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | `new HttpClient()` por requisição / `using (var c = new HttpClient())` | Alta |
| 2 | `HttpClient` estático sem `PooledConnectionLifetime` (DNS obsoleto) | Média |
| 3 | Typed/named client via `IHttpClientFactory` com configuração central | Média |
| 4 | `DelegatingHandler` registrado como singleton/scoped | Alta |
| 5 | Sem timeout/retry/circuit breaker em chamadas externas | Média |
| 6 | Retry automático em POST/PUT não idempotentes | Alta |
| 7 | Vários handlers de resiliência empilhados | Média |
| 8 | Uso do pacote obsoleto `Microsoft.Extensions.Http.Polly` | Baixa |
| 9 | Uso de cookies via factory sem cuidado | Média |
| 10 | Chamadas síncronas (`.Result`) a `HttpClient`; `CancellationToken` ausente | Média |
| 11 | Erros de status não tratados (`EnsureSuccessStatusCode`/checagem) | Média |

## Fontes oficiais
- Guidelines for using HttpClient: https://learn.microsoft.com/en-us/dotnet/fundamentals/networking/http/httpclient-guidelines
- IHttpClientFactory (ASP.NET Core): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/http-requests
- IHttpClientFactory (.NET): https://learn.microsoft.com/en-us/dotnet/core/extensions/httpclient-factory
- Resilient HTTP apps: https://learn.microsoft.com/en-us/dotnet/core/resilience/http-resilience
- Resilience introduction: https://learn.microsoft.com/en-us/dotnet/core/resilience/
