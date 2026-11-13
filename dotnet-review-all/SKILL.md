---
name: dotnet-review-all
description: Revisão completa de código C#/.NET que roda as skills específicas conforme o que o diff ou os arquivos contêm (linguagem, async, LINQ, coleções, interfaces, DTOs, services, DI, endpoints, controllers, Razor Pages, Blazor, SignalR, gRPC, EF Core, segurança, configuração, logging/observabilidade, exceções, convenções, testes, arquitetura, hospedagem/Docker, csproj/pacotes). Use quando o usuário pedir "revisa esse código .NET", "verifica se está tudo certo" ou uma revisão geral sem apontar o assunto. Orquestra as outras skills deste conjunto.
---

# Revisão geral .NET — orquestradora

Esta skill **não tem regras próprias**: ela decide quais skills específicas aplicar e consolida o resultado. Cada regra e fonte oficial vive na skill correspondente; ao reportar, cite a skill/regra de origem.

## Passo 1: descobrir o escopo
Use o diff (`git diff`, PR) ou os arquivos indicados. Se não houver nada indicado, pergunte o escopo antes de revisar o repositório inteiro. Leia também `*.csproj`, `Program.cs`, `appsettings*.json` e `Directory.*.props` quando existirem: muitos achados dependem deles.

## Passo 2: mapa de sinais → skill

### Linguagem e fundamentos
| Se o código contém… | Aplique |
|---|---|
| `async`, `await`, `Task`, `.Result`, `.Wait()`, `CancellationToken`, `Task.Run` | `csharp-async-await` |
| `.Where(`, `.Select(`, `from … in …`, `IQueryable`, `ToList()` | `csharp-linq` (+ `efcore-querying` se for EF) |
| `List<`, `Dictionary<`, `IEnumerable`, retorno/parâmetro de coleção | `csharp-collections` |
| `?`/`!` em tipos, `#nullable`, warnings CS86xx | `csharp-nullable-references` |
| classes/structs/records, herança, `abstract`, `sealed`, propriedades, `readonly` | `csharp-types-oop` |
| `<T>`, `where T :`, `delegate`, `event`, `Func<`, `Action<`, lambdas | `csharp-generics-delegates-events` |
| `switch` com padrões, `is`, interpolação/`StringBuilder`, `??`, `?.` | `csharp-patterns-strings-null` |
| construtor primário, collection expressions, `field`, extension members, `required` | `csharp-modern-features` |
| `try/catch`, `throw`, classes `*Exception` | `dotnet-exception-handling` |
| `IDisposable`, `using`, finalizers, `Span<T>`, alocações em loops quentes | `dotnet-memory-disposable` |
| `lock`, `Thread`, `Interlocked`, `Parallel`, `Channel<T>`, `SemaphoreSlim` | `dotnet-concurrency-threading` |
| API pública de biblioteca, nomes, overloads, extensibilidade | `dotnet-framework-design-guidelines` |
| `System.Text.Json`, `JsonSerializerOptions`, `[JsonPropertyName]`, converters | `dotnet-json-serialization` |
| `HttpClient`, `IHttpClientFactory`, Polly/`AddStandardResilienceHandler` | `dotnet-httpclient-resilience` |
| Sempre (qualquer C#) | `csharp-coding-conventions` (severidade Baixa) |

### Design e camadas
| Se o código contém… | Aplique |
|---|---|
| `interface I…`, classes que implementam interface | `dotnet-interface-review` |
| `AddScoped/AddSingleton/AddTransient`, construtores com dependências, `IServiceProvider` | `dotnet-dependency-injection` |
| Classes `*Service`, `*Repository`, regra de negócio | `dotnet-service-implementation` |
| Classes `*Dto`, `*Request`, `*Response` | `dotnet-dto-review` |
| `AutoMapper`, `Mapster`, `[Mapper]`, métodos `ToDto()`/`ToEntity()`, `ProjectTo` | `dotnet-object-mapping` (+ `dotnet-dto-review`) |
| Entidades/models, `required`, `record`, domínio | `dotnet-model-review`, `csharp-nullable-references` |
| Agregados, value objects, domain events, repositórios de domínio | `dotnet-ddd-tactical` |
| Estrutura de projetos/camadas, referências entre projetos | `dotnet-clean-architecture`, `dotnet-modular-monolith` |
| Vários serviços, gateway, saga | `dotnet-microservices`, `dotnet-distributed-patterns` |
| `ServiceBusClient`, `ServiceBusProcessor`, RabbitMQ, MassTransit, outbox, integration events, consumidores de mensagens | `dotnet-messaging` (+ `dotnet-distributed-patterns`) |

### ASP.NET Core
| Se o código contém… | Aplique |
|---|---|
| `MapGet/MapPost/…`, `MapGroup`, `TypedResults`, endpoint filters | `aspnet-minimal-api`, `aspnet-http-endpoints`, `aspnet-validation` |
| `[ApiController]`, `ControllerBase`, `[HttpGet]`, `ActionResult` | `aspnet-controllers`, `aspnet-http-endpoints`, `aspnet-validation` |
| Filtros MVC, `[FromBody]/[FromQuery]`, model binding, rotas de controllers | `aspnet-mvc-controllers-filters` |
| `*.cshtml` com `@page`, `PageModel`, `OnGet/OnPost` | `aspnet-razor-pages` |
| `*.razor`, `@rendermode`, `OnInitializedAsync`, `AuthorizeView` | `aspnet-blazor` |
| `Hub`, `MapHub`, `IHubContext`, `HubConnection` | `aspnet-signalr` |
| `.proto`, `MapGrpcService`, `GrpcChannel` | `aspnet-grpc` |
| `app.Use…`, ordem de middleware, `UseRouting`, `UseExceptionHandler` | `aspnet-middleware-pipeline`, `aspnet-error-handling` |
| `ProblemDetails`, `IExceptionHandler`, `UseStatusCodePages` | `aspnet-error-handling` |
| `IOptions<`, `IConfiguration`, `appsettings`, User Secrets, `Configure<T>` | `aspnet-configuration-options` |
| `ILogger`, `LoggerMessage`, provedores de log, log de dados sensíveis | `aspnet-logging` |
| `Meter`, `ActivitySource`, `AddOpenTelemetry`, métricas/traces | `dotnet-observability` |
| Incidente real: memória crescendo, CPU alta, app travada, lentidão sob carga, crash, pedido de dump/trace | `dotnet-production-diagnostics` |
| `[Authorize]`, `AddAuthentication`, JWT, políticas | `aspnet-authentication-authorization` |
| `AddIdentity`, `UserManager`, `SignInManager`, 2FA, cookies de auth, `IDataProtector`, `AddDataProtection` | `aspnet-identity-data-protection` |
| `[ApiVersion]`, `AddApiVersioning`, rotas `/v1/`, `api-version` | `aspnet-api-versioning` |
| CORS, HTTPS/HSTS, antiforgery, Data Protection, XSS/open redirect | `aspnet-web-security` |
| Pedido de "testar a segurança"/pentest interno/ASVS/ZAP/testes de IDOR, mass assignment, JWT | `dotnet-security-testing` (+ `dotnet-security-review`) |
| Pedido de "revisão de segurança"/OWASP, upload de arquivos, `FromSqlRaw`, `Html.Raw`, desserialização, segredos, `NuGetAudit` | `dotnet-security-review` (+ as skills de segurança acima) |
| `IMemoryCache`, `OutputCache`, `HybridCache`, `ResponseCaching` | `aspnet-caching` |
| `AddRateLimiter`, request timeouts, compressão | `aspnet-rate-limiting` |
| `BackgroundService`, `IHostedService`, `IHostedLifecycleService` | `aspnet-hosted-services` |
| `MapHealthChecks`, `IHealthCheck` | `aspnet-health-checks` |
| `AddOpenApi`, `MapOpenApi`, Swagger/Swashbuckle | `aspnet-openapi` |
| Desempenho de endpoint (alocações, sync I/O, payload grande, paginação) | `aspnet-performance-best-practices` |
| `Dockerfile`, `ForwardedHeaders`, Kestrel, `ASPNETCORE_URLS`, proxy reverso | `aspnet-hosting-deployment` |

### Dados (EF Core)
| Se o código contém… | Aplique |
|---|---|
| `DbContext`, `AddDbContext`, connection string | `efcore-dbcontext-connection` |
| `OnModelCreating`, `IEntityTypeConfiguration`, pasta `Migrations/` | `efcore-migrations-modeling` |
| `Include`, navegações, `Entry().Load`, lazy loading, relacionamentos | `efcore-relationships-loading` |
| Consultas LINQ sobre `DbSet`, `AsNoTracking`, projeção, paginação | `efcore-querying` |
| `SaveChanges`, concorrência (`RowVersion`), transações, `ExecuteUpdate/Delete` | `efcore-saving-concurrency` |
| Value converters, owned types, TPH/TPT, JSON columns, shadow props, HasData | `efcore-advanced-mapping` |
| `FromSql`, `SqlQuery`, compiled queries, N+1, performance de query | `efcore-sql-performance` |

### Infraestrutura e bibliotecas
| Se o código contém… | Aplique |
|---|---|
| `MongoDB.Driver`, `IMongoCollection`, `MongoClient`, `BsonDocument`, `Builders<`, `[BsonId]` | `dotnet-mongodb` |
| `IFeatureManager`, `IVariantFeatureManager`, `[FeatureGate]`, `AddFeatureManagement`, `feature_management`, feature flag/toggle | `dotnet-feature-flags` |
| `IRequest`, `IMediator`, `ISender`, `AddMediatR`, `IPipelineBehavior`, `AbstractValidator`, `FluentValidation` | `dotnet-mediatr-fluentvalidation` |
| `Hangfire`, `BackgroundJob.Enqueue`, `RecurringJob`, `Quartz`, `IJob`, `AddQuartz`, cron, jobs agendados | `dotnet-background-jobs` |
| `Dapper`, `Microsoft.Data.SqlClient`, `SqlConnection`, `SqlCommand`, `Query<T>`, SQL manual | `dotnet-dapper-adonet` |
| `compose.yaml`, `docker-compose`, `Testcontainers`, `ContainerBuilder`, `PostgreSqlBuilder` | `dotnet-local-dev-containers` |
| `dotnet new`, estrutura de solution, `.slnx`, `CLAUDE.md`, raiz do repositório | `dotnet-project-standards` |
| `Serilog`, `Log.Logger`, `AddSerilog`, `UseSerilogRequestLogging`, `WriteTo.`, `LogContext` | `dotnet-serilog` |
| `StackExchange.Redis`, `ConnectionMultiplexer`, `IDatabase`, `StringGetAsync`, `LockTake`, `AddStackExchangeRedisCache` | `dotnet-redis` |
| `RabbitMQ.Client`, `ConnectionFactory`, `IChannel`, `BasicPublishAsync`, `AsyncEventingBasicConsumer`, filas/exchanges AMQP | `dotnet-rabbitmq` |

### Testes
| Se o código contém… | Aplique |
|---|---|
| Projetos `*.Tests`, `[Fact]`, `[Theory]`, mocks | `dotnet-unit-testing`, `dotnet-xunit` (ou `dotnet-mstest`) |
| `WebApplicationFactory`, `HttpClient` contra a API, `*.IntegrationTests` | `dotnet-integration-testing` |
| Testes com `DbContext`, InMemory/SQLite, fixtures de banco | `efcore-testing` |
| Estrutura da suíte, `dotnet test`, cobertura, CI, NUnit, mutation/load | `dotnet-test-automation` |

### Projeto e build
| Se o código contém… | Aplique |
|---|---|
| `*.csproj`, `Directory.Build.props`, `Directory.Packages.props`, `global.json`, `.editorconfig` | `dotnet-project-tooling` |
| `PublishAot`, `PublishTrimmed`, `IsAotCompatible`, `JsonSerializerContext`, warnings `IL2xxx`/`IL3xxx`, `CreateSlimBuilder` | `dotnet-native-aot-trimming` |
| PR de upgrade de `net8.0`/`net9.0` → `net10.0`, warnings `ASPDEPR*`, mudança de TFM/pacotes | `dotnet-version-migration` |
| `.github/workflows/*.yml`, `azure-pipelines.yml`, `Dockerfile`, scripts de deploy/migrations | `dotnet-ci-cd` (+ `aspnet-hosting-deployment`, `dotnet-security-review`) |

## Passo 3: executar
1. Para cada skill selecionada, aplique **o checklist dela** apenas aos trechos relevantes.
2. Não invente regras fora das skills. Se algo parecer errado mas nenhuma skill cobre, busque na documentação oficial (learn.microsoft.com) antes de afirmar, e diga que está fora das skills.
3. Respeite `.editorconfig`, analyzers e decisões do projeto (convenções locais vencem convenções gerais).
4. Respeite o alvo: as skills assumem .NET 10/C# 14; recursos de versões preview estão marcados nelas.

## Passo 4: relatório consolidado
```
## Resumo
- Escopo revisado: <arquivos/diff>
- Skills aplicadas: <lista>
- Achados: Alta N · Média N · Baixa N

## Achados (ordenados por severidade)
1. [Alta] <arquivo>:<linha> — <problema>
   Regra: <skill> #<item> — Fonte: <URL oficial>
   Correção: <trecho>
...

## O que foi verificado e está correto
- <itens>

## Fora do escopo / não verificado
- <itens>
```
- Ordene por severidade: **Alta** (bugs, deadlock, vazamento de dados, segurança, perda de dados), **Média** (desempenho, design, validação), **Baixa** (estilo, nomenclatura).
- Combine achados duplicados vindos de skills diferentes.
- Diga o que **não** conseguiu verificar (ex.: faltou ver o `Program.cs`).
