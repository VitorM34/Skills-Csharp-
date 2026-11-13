---
name: dotnet-serilog
description: Usar Serilog corretamente em aplicações .NET/ASP.NET Core - instalação, configuração em C# e appsettings.json (Serilog.Settings.Configuration), inicialização em dois estágios (bootstrap logger), message templates e logging estruturado (@ e $, destructuring), níveis e MinimumLevel.Override, enrichers e LogContext, request logging (UseSerilogRequestLogging/IDiagnosticContext), sinks (Console, File, Seq, OpenTelemetry, Async), JSON compacto, ciclo de vida (CloseAndFlush), SelfLog e boas práticas/segurança. Use quando o usuário pedir configurar Serilog, logging estruturado, trocar o logger padrão, reduzir ruído de logs ou revisar uso de Serilog. Based on official Serilog documentation (wiki e READMEs do projeto serilog) - biblioteca de terceiros, não da Microsoft.
---

# Serilog em .NET

**Proveniência:** documentação **oficial do projeto Serilog** — wiki (`serilog/serilog`), `serilog-aspnetcore`, `serilog-settings-configuration` e READMEs dos sinks `File`, `Async`, `Seq`, `OpenTelemetry` — marcada **[SL]**. **Serilog é biblioteca de terceiros**; a Microsoft só a cita como provedor de logging. A base do `ILogger`, níveis, scopes e `LoggerMessage` está em `aspnet-logging`. Convenções minhas: **CONVENÇÃO**. **Versão:** o `Serilog.AspNetCore` **segue o target framework/versão do `Microsoft.Extensions.Hosting`** (use a versão que casa com o seu .NET).
Ligações: `aspnet-logging`, `dotnet-observability`, `aspnet-configuration-options`, `aspnet-hosting-deployment`, `dotnet-security-review`, `dotnet-production-diagnostics`, `dotnet-local-dev-containers`.

## Quando usar
Serilog é uma alternativa ao pipeline padrão para **logging estruturado** com sinks/enrichers/destructuring ricos. Com `AddSerilog()`, **tudo** (logs do ASP.NET, `ILogger<T>` injetado e `Log.*`) passa pelo mesmo pipeline, níveis e destinos. Se o padrão do ASP.NET (`aspnet-logging`) + OpenTelemetry (`dotnet-observability`) já atende, não é obrigatório.

## Instalação e configuração mínima [SL]
- Pacotes: `Serilog` (core), `Serilog.AspNetCore` (integração), sinks separados (`Serilog.Sinks.Console`, `Serilog.Sinks.File`...), `Serilog.Settings.Configuration` (ler do `appsettings`), enrichers (`Serilog.Enrichers.Thread`, `...Environment`...).
- `Program.cs` (modelo oficial): configure o logger **primeiro**, para registrar erros de inicialização do host, e **sempre** faça flush:
```csharp
Log.Logger = new LoggerConfiguration().WriteTo.Console().CreateLogger();
try
{
    Log.Information("Starting web application");
    var builder = WebApplication.CreateBuilder(args);
    builder.Services.AddSerilog();          // redireciona o logging do host para o Serilog
    var app = builder.Build();
    app.Run();
}
catch (Exception ex) { Log.Fatal(ex, "Application terminated unexpectedly"); }
finally { Log.CloseAndFlush(); }
```
Depois **remova a configuração do logger padrão**, inclusive a seção `"Logging"` dos `appsettings.*.json` (substitua pela seção `"Serilog"`).
- **Inicialização em dois estágios** (para usar `appsettings`/DI): `CreateBootstrapLogger()` no início + `builder.Services.AddSerilog((services, lc) => lc.ReadFrom.Configuration(builder.Configuration).ReadFrom.Services(services).Enrich.FromLogContext().WriteTo.Console())`. O logger final **substitui por completo** o bootstrap: se quer console nos dois, configure `WriteTo.Console()` nos dois. `ReadFrom.Services(services)` injeta no pipeline implementações registradas de `IDestructuringPolicy`, `ILogEventEnricher`, `ILogEventFilter`, `ILogEventSink` e `LoggingLevelSwitch`.
- **Configuração por JSON** (`Serilog.Settings.Configuration`): seção **`Serilog` no nível raiz** (`MinimumLevel`, `WriteTo`, `Enrich`, `Destructure`, `Properties`, `Using`); `ReadFrom.Configuration(configuration)`; a seção `Using` lista os assemblies com os métodos de configuração (em .NET Core a descoberta automática por `.deps.json` pode dispensá-la). A API em C# é a base; a doc recomenda usar a configuração externa "com moderação".

## Níveis [SL]
`Verbose` < `Debug` < `Information` < `Warning` < `Error` < `Fatal`. **Sem `MinimumLevel` o padrão é `Information`**. `Information` não tem semântica própria — é quase sinônimo de "evento" (eventos interessantes da aplicação). Verbose "quase nunca" em produção.
- **`MinimumLevel.Override("Microsoft", LogEventLevel.Warning)`** para calar fontes ruidosas por namespace (use `{SourceContext}` no template de saída para descobrir de onde vem o ruído).
- **Por sink:** `restrictedToMinimumLevel` **só pode subir, não descer**, o nível do logger (o logger decide quais eventos nascem; o sink só filtra). Para mais detalhe num destino, deixe o `MinimumLevel` do logger baixo e restrinja os outros sinks.
- **Nível dinâmico:** `LoggingLevelSwitch` + `MinimumLevel.ControlledBy(switch)` para ligar Debug/Verbose temporariamente.
- **Checagem de nível** quase nunca é necessária (custo mínimo); em casos raros de desempenho, guarde `Log.IsEnabled(...)` num campo.

## Message templates e dados estruturados [SL]
- **Use template, nunca concatenação/interpolação:** `Log.Information("The time is {Now}", DateTime.Now)` ✔; `Log.Information("The time is " + DateTime.Now)` ✘ — o Serilog **faz parse e cacheia cada template** (até um limite): tratar o parâmetro como mensagem **degrada desempenho e consome memória do cache** e perde a estrutura (propriedades).
- **Regras:** propriedades entre `{ }`, nomes **identificadores C# válidos** (`FooBar`, não `Foo.Bar`/`Foo-Bar`); `{{` escapa; nomes **numéricos** casam por índice; se algum for não numérico, casam **da esquerda para a direita**; formatos como `{Count:000}`. **Estilo:** o nome da propriedade faz parte da frase (*fluent*), fragmentos (sem ponto final), propriedades em **PascalCase**.
- **Representação:** escalares (bool, numéricos, string, `DateTime/Offset`, `TimeSpan`, `Guid`, `Uri`, nullables) saem atômicos; `IEnumerable` vira coleção; dicionários com chave escalar; **objetos desconhecidos** viram `ToString()`. **`@` (destructuring)** preserva a estrutura de DTOs/eventos/modelos: `Log.Information("Processing {@SensorInput}", x)`; **`$`** força `ToString()`. Operadores definem a **captura**; formatos só afetam a exibição em texto.
- **Controle do que é gravado:** `Destructure.ByTransforming<T>(...)` (deve retornar tipo **diferente**, senão recursão), `IDestructuringPolicy` para casos condicionais, e limites `ToMaximumDepth`/`ToMaximumStringLength`/`ToMaximumCollectionCount` (na config JSON). **Segurança:** `@` com DTO/entidade pode **gravar campos sensíveis** (senha, token, PII) — destructure só o que precisa e aplique políticas (`dotnet-security-review`, OWASP A09; ASVS 16.2.5 pede aplicar a proteção por tipo de dado).
- Exceções: `Log.Error(ex, "mensagem")` (exceção como 1º argumento).

## Enrichers e contexto [SL]
- `Enrich.WithThreadId()` (convenção: `.WithXyz()` cria a propriedade `Xyz`), `Enrich.WithProperty("Version", "1.0.0")` para constantes, enricher próprio (`ILogEventEnricher`).
- **`Enrich.FromLogContext()` + `LogContext.PushProperty("A", 1)`** (em `using`): propriedades ambientes (ex.: id da transação) em todos os eventos dentro do escopo; **devem ser removidas na ordem inversa exata em que foram adicionadas** (senão comportamento indefinido). Mesma ideia com `ILogger<T>` do Microsoft.Extensions.Logging: `logger.BeginScope(new Dictionary<string, object> { ["UserId"] = ..., })` (**tem de ser dicionário**; exige `FromLogContext()`).
- Enrichers valem mais com **sinks estruturados** (onde propriedades são filtráveis). **CONVENÇÃO:** enriqueça com correlation/trace id e identificador do serviço (`dotnet-observability`) e **sem dados pessoais**.

## Request logging no ASP.NET Core [SL]
- O logging de requisições padrão do ASP.NET é **ruidoso (vários eventos por requisição)**. `UseSerilogRequestLogging()` emite **um evento por requisição** (método, path, status, tempo). **Antes**, suba o nível das fontes ruidosas: `MinimumLevel.Override("Microsoft.AspNetCore.Hosting"/"Mvc"/"Routing", Warning)`.
- **Posição no pipeline importa:** deve vir **antes** dos handlers (MVC etc.); a middleware **não mede o que vem antes dela** — dá para excluir ruído (ex.: `UseStaticFiles()`) colocando-a **depois** (`aspnet-middleware-pipeline`).
- Propriedades extras no mesmo evento: `IDiagnosticContext.Set("Chave", valor)` (injetável); opções: `MessageTemplate`, `GetLevel` (ex.: baixar nível de health checks — **CONVENÇÃO**), `EnrichDiagnosticContext`. Propriedades padrão: `RequestMethod`, `RequestPath`, `StatusCode`, `Elapsed`.

## Sinks e saída [SL]
- **Console** (JSON para containers/agregadores: `WriteTo.Console(new RenderedCompactJsonFormatter())`; `Console/Debug/File` suportam JSON via `Serilog.Formatting.Compact`). **CONVENÇÃO:** em container escreva em **stdout** (12-factor) e deixe a plataforma coletar.
- **File:** por padrão **só um processo pode escrever** no arquivo (para vários, `shared: true`); **limite de 1 GB por arquivo** (depois disso nada é gravado até o próximo roll; `fileSizeLimitBytes: null` remove) e **retém só os 31 arquivos mais recentes** (`retainedFileCountLimit`; `retainedFileTimeLimit` por idade); `rollingInterval: RollingInterval.Day` e/ou `rollOnFileSizeLimit: true`. Em **Azure App Service**, o Log Stream lê `D:\home\LogFiles\`: use sink de arquivo com `shared: true` e `flushToDiskInterval`.
- **`WriteTo.Async(a => a.File(...))`** (Serilog.Sinks.Async): move a escrita para uma thread de fundo (bom para File, sujeito a I/O); **buffer padrão de 10.000 eventos — acima disso eventos são descartados** (monitore `DroppedMessagesCount`/inspector); chame `CloseAndFlush()`. **Sinks de rede (Seq, Elasticsearch, Splunk...) já fazem batching assíncrono** e não precisam do wrapper.
- **Seq** (`WriteTo.Seq("http://...")`), **OpenTelemetry** (`Serilog.Sinks.OpenTelemetry`: envia `LogRecord`s via OTLP gRPC/HTTP, **mapeia propriedades Serilog ↔ atributos OTel 1-para-1** sem depender do SDK do OTel — ver `dotnet-observability`).
- **Formato de texto:** `outputTemplate` (`{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] {Message:lj}{NewLine}{Exception}`); `{Message:lj}` = JSON nos dados e literais de string como estão; `{Properties:j}` inclui o restante.
- Sub-loggers (`WriteTo.Logger(lc => lc.Filter...)`) para roteamento fino (políticas de destructuring **não** valem dentro deles); `Filter.ByExcluding/ByIncludingOnly` com `Matching`.

## Ciclo de vida e confiabilidade [SL]
- Configure o **logger raiz uma vez** e use-o por toda a vida do app; **`Log.CloseAndFlush()` (ou `await CloseAndFlushAsync()`) antes de sair** — sinks de rede e `File` mantêm buffers/recursos. Só o **logger raiz** precisa ser descartado; `Log.ForContext(...)` não.
- **Filosofia:** logging tem prioridade menor e **nunca deve afetar o app**: erros de configuração dependentes do ambiente (ex.: caminho inexistente) são capturados e vão para o **SelfLog**; violações de invariante (ex.: `null` como nome de arquivo) **lançam** `ArgumentNullException`. Ative **`SelfLog.Enable(Console.Error)`** (ou `TextWriter.Synchronized(file)`) para diagnosticar "por que meus logs não aparecem" — o SelfLog **não** escreve nos seus sinks e **não sincroniza** o `TextWriter` por conta própria.
- Existe o **Serilog Analyzer** (Roslyn, comunitário) que checa erros comuns de templates.

## Integração com o resto
- **`ILogger<T>` continua sendo a interface injetada** (`aspnet-logging`); `LoggerMessage`/source generators do .NET seguem válidos. O README manda **remover a seção `Logging`** e controlar níveis/filtros no Serilog (`MinimumLevel`/`Override`), para não manter duas configurações concorrentes.
- **Configuração:** `aspnet-configuration-options` (seção `Serilog`, overrides por ambiente via `appsettings.{Environment}.json`/variáveis). **Segredos** (chave do Seq/endpoint OTLP) fora do código.
- **Testes:** capture eventos com um sink em memória no teste (a doc não foi lida para isso — escolha um sink de teste da comunidade e verifique).
- **Alta cardinalidade/volume:** avalie custo de armazenamento do sink; amostragem/filtros por nível (`MinimumLevel.Override`).

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Interpolação/concatenação de strings em mensagens (`$"..."`, `"..." + x`) em vez de templates | Média |
| 2 | `{@Objeto}` com entidade/DTO contendo dados sensíveis; senha/token/PII em propriedades | Alta |
| 3 | Falta de `Log.CloseAndFlush()` no shutdown / logger configurado várias vezes | Média |
| 4 | Duas configurações de logging ativas (seção `Logging` + Serilog) ou bootstrap logger sem `WriteTo` equivalente no final | Baixa |
| 5 | `MinimumLevel` Debug/Verbose em produção; sem `Override` para `Microsoft`/`System` (ruído e custo) | Média |
| 6 | `UseSerilogRequestLogging()` depois dos handlers ou sem reduzir o log padrão do ASP.NET (eventos duplicados) | Baixa |
| 7 | Sink `File` sem política de retenção/tamanho entendida (1 GB, 31 arquivos) ou em vários processos sem `shared`; disco cheio | Média |
| 8 | `Async` sem monitorar descarte (buffer 10.000) ou sem flush; `Async` em cima de sink de rede (redundante) | Baixa |
| 9 | `LogContext.PushProperty` sem `using`/ordem de dispose incorreta; falta de `FromLogContext()` | Média |
| 10 | Sem `SelfLog` habilitado durante diagnóstico; erros de config silenciosos | Baixa |
| 11 | Nomes de propriedade inválidos/inconsistentes (`Foo.Bar`, camelCase misturado); logs sem correlation id | Baixa |
| 12 | Logs de PII/segredos em sink sem controle de acesso/retenção (LGPD/GDPR) | Alta |

## Fontes [SL] (documentação oficial do projeto Serilog)
- Getting Started: https://github.com/serilog/serilog/wiki/Getting-Started
- Configuration Basics (sinks, níveis, enrichers, filtros, sub-loggers): https://github.com/serilog/serilog/wiki/Configuration-Basics
- Writing Log Events (templates, níveis): https://github.com/serilog/serilog/wiki/Writing-Log-Events
- Structured Data (destructuring `@`/`$`): https://github.com/serilog/serilog/wiki/Structured-Data
- Enrichment / LogContext: https://github.com/serilog/serilog/wiki/Enrichment
- Lifecycle of Loggers: https://github.com/serilog/serilog/wiki/Lifecycle-of-Loggers
- Reliability: https://github.com/serilog/serilog/wiki/Reliability
- Debugging and Diagnostics (SelfLog): https://github.com/serilog/serilog/wiki/Debugging-and-Diagnostics
- Serilog.AspNetCore (AddSerilog, request logging, dois estágios): https://github.com/serilog/serilog-aspnetcore
- Serilog.Settings.Configuration: https://github.com/serilog/serilog-settings-configuration
- Sinks: File https://github.com/serilog/serilog-sinks-file · Async https://github.com/serilog/serilog-sinks-async · OpenTelemetry https://github.com/serilog/serilog-sinks-opentelemetry · Seq https://github.com/datalust/serilog-sinks-seq
- Message templates: https://messagetemplates.org/
