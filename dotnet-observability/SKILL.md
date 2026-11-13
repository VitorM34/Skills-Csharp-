---
name: dotnet-observability
description: Implementar e revisar observabilidade em .NET/ASP.NET Core - logs, métricas (System.Diagnostics.Metrics, Meter, IMeterFactory, tipos de instrumento) e tracing distribuído (ActivitySource/Activity, W3C TraceContext), OpenTelemetry (pacotes, exporters OTLP/Prometheus, AddMeter/AddSource), métricas built-in do ASP.NET Core e Kestrel, dotnet-counters. Use quando o usuário pedir métricas customizadas, tracing, correlação entre serviços, integrar OpenTelemetry/Prometheus/Grafana/Application Insights ou revisar instrumentação. Based on official Microsoft Learn docs (.NET 10 / ASP.NET Core 10).
---

# Observabilidade (logs, métricas, traces)

Só afirmar o que a doc oficial diz (fontes no fim). Logging com `ILogger`: `aspnet-logging`. Health checks: `aspnet-health-checks`. Padrões distribuídos: `dotnet-distributed-patterns`. Testes: `dotnet-unit-testing`. Investigação de incidentes (dump, trace, CPU/memória/travamento): `dotnet-production-diagnostics`.

## Conceito
Observabilidade = monitorar/analisar telemetria para ver mudanças de desempenho e diagnosticar por quê, **sem ser invasiva** (diferente de debug). **Três pilares:** **logs**, **métricas** e **distributed tracing**. Telemetria vem do runtime (GC, JIT), de bibliotecas (Kestrel, `HttpClient`) e do código da aplicação. Abordagens: **em código** (biblioteca como OpenTelemetry; mais poderosa/configurável), **fora do processo** via EventPipe (`dotnet-monitor`), ou **startup hook** (auto-instrumentação OpenTelemetry).

## OpenTelemetry no .NET
- Padrão aberto (APIs, convenções semânticas, exporters, protocolo **OTLP**). **No .NET o framework já fornece as APIs**, então o OTel só coleta e exporta: **`ILogger`** (logs), **`Meter`** (métricas), **`ActivitySource`/`Activity`** (traces). Autores de **bibliotecas** dependem só de `System.Diagnostics.DiagnosticSource` (parte do runtime); só o **app** referencia OpenTelemetry.
- Pacotes: `OpenTelemetry` (core), `OpenTelemetry.Extensions.Hosting`, `...Instrumentation.AspNetCore`, `...Instrumentation.Http` (`HttpClient`), `...Instrumentation.GrpcNetClient`, `...Instrumentation.SqlClient`, exporters `Console`, **`OpenTelemetryProtocol` (OTLP)**, `Prometheus.AspNetCore`, `Zipkin`. (Alguns são pré-release; verifique versão.)
- Configuração típica: `builder.Services.AddOpenTelemetry().ConfigureResource(r => r.AddService(name)).WithMetrics(...).WithTracing(...)`; **`AddMeter("nome")`** e **`AddSource("nome")`** registram *quais* Meters/ActivitySources exportar — **se o nome não for adicionado, a telemetria customizada não sai**. Endpoint OTLP por `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`; **headers/segredos de endpoint não vão no código**. Prometheus: `AddPrometheusExporter()` + `app.MapPrometheusScrapingEndpoint()`. Backends citados: Aspire Dashboard, Prometheus/Grafana/Jaeger, Azure Monitor/Application Insights.

## Métricas (`System.Diagnostics.Metrics`)
- `Meter` = grupo nomeado de **instrumentos**; instrumentos gravam medições; **ferramentas de coleta decidem as métricas calculadas**. Em código **sem DI**: crie o `Meter` **uma vez** em campo estático. **Com DI (ASP.NET Core/Generic Host): use `IMeterFactory`** (registrado automaticamente a partir do .NET 8; `AddMetrics()` manual) e **não** estáticos — isola Meters entre containers (**testes em paralelo** só observam as próprias medições) e o factory descarta os Meters (não chame `Dispose`). Registre a classe de métricas como **singleton**.
- **Nomes:** únicos, hierárquicos com pontos (guideline OTel): instrumentos em minúsculas, pontos e `_` entre palavras (ex.: `contoso.ticket_queue.duration`); nem toda ferramenta preserva o nome do Meter ⇒ torne o nome do instrumento globalmente único. Crie Meters separados se quiser ligar/desligar grupos de métricas.
- **Instrumentos:** `Counter` (só cresce; total e taxa), `UpDownCounter` (sobe/desce: tamanhos de fila/cache), `Observable*` (o chamador mantém o total e fornece **callback**; úteis em hot paths > 1M chamadas/s/thread), `Gauge`/`ObservableGauge` (valor atual), **`Histogram`** (distribuição: **para medir tempo, geralmente preferido**; olhe percentis 90/95/99 em vez de médias; `Advice` define buckets recomendados). Tipo numérico genérico: `byte, short, int, long, float, double, decimal`.
- **Multidimensional:** associe **tags** (chave/valor) às medições; **cuidado com cardinalidade**: ferramentas podem ter limites rígidos e custar caro; a doc diz que **menos de ~1000 combinações por instrumento** tende a ser seguro, e Histograms usam bem mais memória. As APIs de gravar são **thread-safe** e custam **< 10 ns** sem coleta (dezenas–centenas de ns com coleta).
- **Built-in do ASP.NET Core** (Meters `Microsoft.AspNetCore.Hosting`, `...Server.Kestrel`, `...Routing`, `...RateLimiting`, `...Diagnostics`, `...Http.Connections` (SignalR); no 10: Components/Blazor, Authentication/Authorization): ex. `http.server.request.duration`, `aspnetcore.diagnostics.exceptions`. Para exportar, `AddMeter` desses nomes (+ `AddView` para buckets). **`dotnet-counters monitor -n <app> --counters Microsoft.AspNetCore.Hosting`** vê ao vivo (útil para verificar instrumentação).

## Tracing distribuído
- **`Activity`** = unidade de trabalho; **`ActivitySource`** a cria. Formato padrão no .NET 5+: **W3C TraceContext** (trace-id 16 bytes, span-id 8 bytes, parent span-id). **ASP.NET Core e `HttpClient` já propagam IDs nos headers automaticamente**, sem código extra (outros protocolos/mensageria dependem de bibliotecas ou código seu). `Activity.Current` flui por chamadas síncronas e assíncronas.
- **`ActivitySource`**: crie **uma vez, estático**, com nome único e hierárquico (assembly/componente); `using var activity = source.StartActivity("Nome")` marca unidade de trabalho significativa. **`StartActivity` retorna `null` se ninguém escuta** ⇒ use `activity?.SetTag(...)`. Tags = metadados; **events** ficam em memória (poucos eventos; para muitos use `ILogger`); status/exceções (`SetStatus`) são opcionais. `ILogger` captura o ID da Activity ativa (**correlação logs↔trace automática**).
- Coleta: OpenTelemetry/Application Insights/`ActivityListener`.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | `AddMeter`/`AddSource` ausentes para Meters/ActivitySources customizados | Média |
| 2 | `new Meter` estático em código com DI/testes paralelos (usar `IMeterFactory`) | Média |
| 3 | `new ActivitySource` dentro do método (criar a cada chamada) | Média |
| 4 | `activity.SetTag` sem `?.` (NRE quando não há listener) | Média |
| 5 | Tags de alta cardinalidade (userId, URL completa) em métricas | Alta |
| 6 | Tempo medido com Counter/média em vez de Histogram | Baixa |
| 7 | Dados sensíveis em tags/logs; chaves OTLP no código | Alta |
| 8 | Propagação de trace perdida em mensageria/filas (headers não propagados) | Média |
| 9 | Muitos `activity.AddEvent` em vez de logs | Baixa |
| 10 | Nome de instrumento fora do padrão/ não único | Baixa |

## Fontes oficiais
- Observabilidade com OpenTelemetry: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/observability-with-otel
- Exemplo OTLP/Aspire Dashboard: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/observability-otlp-example
- Métricas — criar: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/metrics-instrumentation
- Métricas — coletar: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/metrics-collection
- Distributed tracing (conceitos): https://learn.microsoft.com/en-us/dotnet/core/diagnostics/distributed-tracing-concepts
- Tracing — instrumentação: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/distributed-tracing-instrumentation-walkthroughs
- ASP.NET Core metrics: https://learn.microsoft.com/en-us/aspnet/core/metrics/overview
- Métricas built-in do ASP.NET Core: https://learn.microsoft.com/en-us/aspnet/core/metrics/built-in
- dotnet-counters: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-counters
