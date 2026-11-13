# Skills C# / .NET para Claude Code

Conjunto de **84 skills** (cada uma é uma pasta com `SKILL.md`) baseadas na **documentação oficial da Microsoft (Microsoft Learn)**, com foco em **.NET 10 / C# 14 / ASP.NET Core 10 / EF Core 10**. Pesquisadas e escritas em 2026-10-21 a partir de clones locais dos repositórios oficiais de documentação (conteúdo filtrado para a versão 10; recursos de .NET 11/C# 15 preview ficam de fora ou marcados).

Princípio: a skill só afirma o que está na documentação oficial; cada uma termina com a lista de fontes e instrui o Claude a **buscar na doc** quando a dúvida não estiver coberta (em vez de inventar). Onde a doc oficial não cobre o assunto (ex.: monolito modular, padrão de service layer, versionamento de API) a skill **diz isso** e marca o que é **convenção**.

## Como instalar

Claude Code carrega skills de `~/.claude/skills/<nome>/SKILL.md` (todas as sessões) ou `<projeto>/.claude/skills/<nome>/SKILL.md` (só aquele projeto). Opções:

**A) Linkar todas no seu usuário (recomendado: edições aqui refletem na hora):**
```bash
cd ~/Projects/claude/skills && ./install.sh
```
**B) Só em um projeto:**
```bash
cd ~/Projects/claude/skills && ./install.sh /caminho/do/projeto
```
Depois reinicie a sessão do Claude Code. Use digitando `/nome-da-skill` ou pedindo em linguagem natural (a `description` de cada skill faz o Claude escolher sozinho). Para "revisar tudo", use `/dotnet-review-all`.

## Skills

### Linguagem C#
| Skill | Para quê |
|---|---|
| `csharp-async-await` | async/await, Task, WhenAll, cancelamento, deadlock |
| `csharp-linq` | LINQ: sintaxes, execução adiada, IEnumerable × IQueryable |
| `csharp-collections` | Escolher coleções; o que expor em APIs públicas |
| `csharp-nullable-references` | Nullable reference types, `?`, `!`, atributos |
| `csharp-types-oop` | Classes, structs, records, herança, polimorfismo, enums, interfaces |
| `csharp-generics-delegates-events` | Generics, delegates, lambdas, eventos |
| `csharp-patterns-strings-null` | Pattern matching, strings (interpolação/raw), operadores null |
| `csharp-modern-features` | Recursos C# 12–14 (construtor primário, collection expressions, `field`…) |
| `csharp-coding-conventions` | Verificar padrões: nomenclatura, estilo, `var`, layout |

### .NET fundamentos
| Skill | Para quê |
|---|---|
| `dotnet-exception-handling` | try/catch, throw, exceções customizadas, Try* |
| `dotnet-framework-design-guidelines` | Design de APIs/bibliotecas: nomes, tipos, membros, extensibilidade |
| `dotnet-memory-disposable` | IDisposable/IAsyncDisposable, GC, LOH, memória |
| `dotnet-concurrency-threading` | Threads, thread pool, sincronização, coleções thread-safe, Channels, TPL |
| `dotnet-json-serialization` | System.Text.Json: opções, atributos, source generation, required |
| `dotnet-httpclient-resilience` | `HttpClient`/`IHttpClientFactory`, resiliência (retry, circuit breaker) |
| `dotnet-production-diagnostics` | Investigar em produção: memory leak, CPU alta, deadlock, ThreadPool starvation, crash (counters, dump, trace, gcdump, stack, monitor, containers) |
| `dotnet-observability` | Logs, métricas (`Meter`), tracing (`ActivitySource`), OpenTelemetry |
| `dotnet-version-migration` | Upgrade 8→9→10: passos oficiais, breaking changes (ASP.NET, EF, libs), checklist |
| `dotnet-project-tooling` | SDK/csproj, `Directory.Build.props`, Central Package Management, `global.json`, analyzers/.editorconfig |

### Design (interfaces, DTO, models, services, DI)
| Skill | Para quê |
|---|---|
| `dotnet-interface-review` | Implementar/revisar interfaces |
| `dotnet-dto-review` | DTOs de entrada/saída, overposting, PATCH, records |
| `dotnet-model-review` | Models/entidades: class × record × struct, `required` |
| `dotnet-service-implementation` | Services e repositórios |
| `dotnet-object-mapping` | Entity↔DTO: manual, projeção `Select`, Mapperly/Mapster/AutoMapper (terceiros) |
| `dotnet-dependency-injection` | Registro, lifetimes, captive dependency, keyed services |

### ASP.NET Core
| Skill | Para quê |
|---|---|
| `aspnet-http-endpoints` | GET/POST/PUT/PATCH/DELETE, binding, status codes |
| `aspnet-minimal-api` | Minimal APIs: MapGroup, TypedResults, filtros |
| `aspnet-controllers` | Controllers de API: `[ApiController]`, ActionResult |
| `aspnet-mvc-controllers-filters` | Filtros MVC, model binding, roteamento de controllers |
| `aspnet-razor-pages` | Razor Pages: PageModel, handlers, binding, convenções |
| `aspnet-blazor` | Blazor: render modes, ciclo de vida, disposal, EF Core |
| `aspnet-signalr` | SignalR: hubs, grupos, auth, escala |
| `aspnet-grpc` | gRPC: serviços, clientes, deadlines, versionamento |
| `aspnet-validation` | DataAnnotations, `AddValidation()`, regras customizadas |
| `aspnet-error-handling` | ProblemDetails, `UseExceptionHandler`, `IExceptionHandler` |
| `aspnet-middleware-pipeline` | Pipeline, ordem, roteamento, ambientes |
| `aspnet-configuration-options` | Configuração, Options pattern, secrets |
| `aspnet-logging` | `ILogger`, `LoggerMessage`, níveis, escopos |
| `aspnet-authentication-authorization` | Autenticação, autorização, JWT, policies |
| `dotnet-security-review` | Revisão de segurança pelo OWASP Top 10:2025 → docs oficiais + analyzers de segurança (CA2100, CA3xxx, CA23xx, CA53xx), NuGet Audit, upload, segredos |
| `dotnet-security-testing` | Testar a segurança do seu app: WSTG + ASVS 5.0, testes automáticos (IDOR/BOLA, mass assignment, JWT), ZAP, relatório e reteste |
| `aspnet-identity-data-protection` | Identity (senha, lockout, 2FA, passkeys, Identity API) e Data Protection (key ring, web farm, containers) |
| `aspnet-api-versioning` | Estratégias de versionamento (oficial) + lib Asp.Versioning (terceiros) |
| `aspnet-web-security` | CORS, HTTPS/HSTS, antiforgery, XSS, open redirect |
| `aspnet-caching` | Cache em memória/distribuído/híbrido, output caching |
| `aspnet-rate-limiting` | Rate limiting, timeouts, compressão |
| `aspnet-hosted-services` | BackgroundService, IHostedService |
| `aspnet-health-checks` | Health checks |
| `aspnet-openapi` | Geração de OpenAPI |
| `aspnet-performance-best-practices` | Boas práticas de desempenho |
| `aspnet-hosting-deployment` | Kestrel, reverse proxy, forwarded headers, Docker/containers |

### Banco de dados (EF Core)
| Skill | Para quê |
|---|---|
| `efcore-dbcontext-connection` | DbContext, connection string, lifetime, secrets |
| `efcore-querying` | Tracking, projeção, paginação, filtros |
| `efcore-relationships-loading` | Relacionamentos, Include, lazy/explicit loading |
| `efcore-migrations-modeling` | Modelo (Fluent API) e migrations |
| `efcore-saving-concurrency` | SaveChanges, concorrência, transações, bulk |
| `efcore-advanced-mapping` | Value converters, owned/complex types, herança, JSON |
| `efcore-sql-performance` | SQL bruto, N+1, performance |
| `efcore-testing` | Testes com EF Core: banco real, SQLite, InMemory (evitar) |

### Infraestrutura e bibliotecas
| Skill | Para quê |
|---|---|
| `dotnet-mongodb` | MongoDB com o driver oficial: MongoClient/DI, mapeamento BSON (ObjectId, Guid, DateTime), CRUD/LINQ3, índices, transações, change streams, provider EF |
| `dotnet-feature-flags` | Feature flags com Microsoft.FeatureManagement: filtros, targeting/rollout, variantes, telemetria, App Configuration, ciclo de vida |
| `dotnet-mediatr-fluentvalidation` | MediatR (CQRS, pipeline behaviors, licença) e FluentValidation (validators, DI, Minimal API, testes) e a combinação dos dois |
| `dotnet-background-jobs` | Hangfire e Quartz.NET: jobs agendados/recorrentes, retry, idempotência, cron, misfire, cluster, DI com escopo, dashboard seguro |
| `dotnet-dapper-adonet` | ADO.NET (SqlClient) e Dapper: pooling, parâmetros/SQL injection, async, transações, retry, Encrypt, quando usar vs EF |
| `dotnet-local-dev-containers` | Docker Compose para dev (healthcheck/depends_on, secrets, profiles) e Testcontainers for .NET (módulos, xUnit, wait, Ryuk, CI) |
| `dotnet-project-standards` | Padrão de projeto/repo: dotnet new (sln/slnx, global.json, editorconfig...), layout src/tests, arquivos de raiz, CLAUDE.md do projeto |
| `dotnet-serilog` | Serilog: AddSerilog, dois estágios, templates/@, enrichers, request logging, sinks (File/Async/Seq/OTel), SelfLog |
| `dotnet-redis` | Redis com StackExchange.Redis 3.x: multiplexer, resiliência, sync-over-async, transações/CAS, locks, cache-aside, eviction, segurança |
| `dotnet-rabbitmq` | RabbitMQ com cliente 7.x: conexão/canais, confirms, ack/prefetch, quorum queues, DLX, poison messages |

### Arquitetura
| Skill | Para quê |
|---|---|
| `dotnet-clean-architecture` | Camadas, Application Core / Infrastructure / UI |
| `dotnet-modular-monolith` | Monolito modular (⚠ sem guia oficial; marcado) |
| `dotnet-microservices` | Microsserviços, quando usar, antipadrões |
| `dotnet-ddd-tactical` | DDD tático: agregados, value objects, domain events |
| `dotnet-messaging` | Integration events, outbox, competing consumers, pub/sub, Azure Service Bus |
| `dotnet-distributed-patterns` | CQRS, saga, idempotent consumer, retry, circuit breaker, gateway, strangler |

### Testes
| Skill | Para quê |
|---|---|
| `dotnet-test-automation` | Estratégia, frameworks, VSTest × MTP, `dotnet test`, cobertura, CI, mutation, carga |
| `dotnet-unit-testing` | Testes unitários (AAA, nomes, stubs/mocks, controllers/Razor/minimal API) |
| `dotnet-xunit` | xUnit: Fact/Theory, fixtures, ciclo de vida |
| `dotnet-mstest` | MSTest |
| `dotnet-integration-testing` | `WebApplicationFactory`, TestServer, mocks, auth |

### Orquestração
| Skill | Para quê |
|---|---|
| `dotnet-native-aot-trimming` | Native AOT e trimming: quando vale, compatibilidade ASP.NET/EF, warnings IL2xxx/IL3xxx, source generators, tamanho, diagnóstico |
| `dotnet-ci-cd` | Pipeline .NET (exemplo GitHub Actions): restore com lock file, build/analyzers, testes e exit codes, container, migrations (bundle/script), segurança do pipeline |
| `dotnet-feature-workflow` | Implementar uma feature ponta a ponta: descobrir → contrato → modelo → EF/migration → service → endpoint → testes → gates (orquestra as outras skills) |
| `dotnet-review-all` | Revisão geral: decide e roda as skills certas e consolida |

## Manutenção
- Cada `SKILL.md` lista as URLs oficiais (todas verificadas com HTTP 200 em 2026-10-21). Para atualizar uma skill: peça "atualize a skill X contra a doc oficial atual" e confira o diff.
- A documentação muda a cada versão do .NET; reconfira as skills a cada release (hoje: .NET 10).
- `csharp-async-await` tem notas extras em `references/official-notes.md`.

## Lacunas conhecidas (não cobertas ou só superficiais)
- **Blazor**: só fundamentos (render modes, ciclo de vida, disposal, EF Core, autorização). Formulários, JS interop, state management, PWA e Hybrid (MAUI) não foram detalhados.
- **Razor Pages/Views**: Tag Helpers, view components, localização e areas só são mencionados.
- **Hospedagem**: IIS, Nginx/Apache, Windows Service e Azure App Service têm páginas oficiais próprias não detalhadas; Docker/Kestrel/proxy estão cobertos.
- **Não cobertos**: .NET Aspire, Native AOT/trimming, globalização/localização, TPL Dataflow/PLINQ, reflection/atributos customizados, E/S de arquivos, mensageria com MassTransit/NServiceBus/RabbitMQ em detalhe (só Service Bus e padrões oficiais).
- **Terceiros**: onde a Microsoft cita bibliotecas de terceiros (ex.: AspNetCore.Diagnostics.HealthChecks, Polly) a skill avisa. Em `aspnet-api-versioning` (Asp.Versioning) e `dotnet-object-mapping` (Mapperly/Mapster/AutoMapper) a parte de biblioteca vem da documentação dos próprios projetos, marcada **[LIB]**.
- As skills foram escritas lendo a documentação, mas **não foram executadas contra projetos reais**: valide as recomendações em um projeto-piloto antes de adotar como regra do time.
