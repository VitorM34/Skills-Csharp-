---
name: aspnet-hosted-services
description: Implementar e revisar tarefas em segundo plano no .NET/ASP.NET Core - IHostedService, BackgroundService, Worker Service, timers, filas de trabalho, consumo de serviços scoped (IServiceScopeFactory), ordem de start/stop, shutdown gracioso, Generic Host. Use quando o usuário pedir para criar job em background, worker, processamento fora da requisição ou revisar BackgroundService que usa DbContext. Based on official Microsoft Learn docs.
---

# Tarefas em segundo plano — Hosted Services e Worker Services

Só afirmar o que a doc oficial diz (fontes no fim). Async/cancelamento: `csharp-async-await`. DI e escopos: `dotnet-dependency-injection`.

## Quando usar
Tarefas longas **não devem** ser aguardadas dentro do processamento HTTP normal (`aspnet-performance-best-practices`); implemente-as como **hosted services** (nunca `Task.Run`/`async void` capturando `HttpContext` ou `DbContext` da requisição). Para app só de background: template **Worker Service** (`Microsoft.NET.Sdk.Worker`) com Generic Host.

## `IHostedService` e `BackgroundService`
- `IHostedService`: `StartAsync(CancellationToken)` e `StopAsync(CancellationToken)`. **`BackgroundService`** (classe abstrata, implementa `IHostedService`) exige implementar `ExecuteAsync(CancellationToken stoppingToken)`.
```csharp
public sealed class Worker(ILogger<Worker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            logger.LogInformation("Worker running at: {Time}", DateTimeOffset.Now);
            await Task.Delay(1_000, stoppingToken);
        }
    }
}
// Program.cs
builder.Services.AddHostedService<Worker>();
```
- **Ciclo de vida:** ativado **uma vez** na inicialização e encerrado graciosamente no shutdown. `StartAsync` deve ser **curto**: serviços iniciam **sequencialmente na ordem de registro** e nada mais inicia até `StartAsync` concluir (`HostOptions.ServicesStartConcurrently = true` permite concorrência). Na parada, **ordem inversa** (`ServicesStopConcurrently`).
- **Shutdown:** o token de `StopAsync` tem **timeout padrão de 30 s**; ao ser cancelado, aborte o trabalho restante e retorne rápido; `ExecuteAsync` deve terminar logo quando o token dispara, senão o serviço é encerrado de forma não graciosa ao fim do timeout (configurável, ex.: `HostOptions.ShutdownTimeout`).
- Se sobrescrever `StartAsync`/`StopAsync` de `BackgroundService`, **chame e dê `await` no método base**.
- Se houver erro na execução, `Dispose` deve ser chamado mesmo sem `StopAsync`.
- Concluir o host quando o serviço termina: chame `IHostApplicationLifetime.StopApplication()` (obrigatório no template Worker para tarefas "executa uma vez", senão o host roda indefinidamente). Para app curto com DI/logging/config sem a classe `Worker`, use o **Generic Host** puro.

## Serviços scoped dentro do hosted service
- O hosted service é **singleton**: **não** pode receber serviços scoped (ex.: `DbContext`) por construtor. **Nenhum escopo é criado por padrão**: injete **`IServiceScopeFactory`** (singleton), `using var scope = factory.CreateScope()` a cada unidade de trabalho e resolva os serviços scoped dentro dela.
```csharp
public sealed class Worker(IServiceScopeFactory scopeFactory) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            using var scope = scopeFactory.CreateScope();
            var processor = scope.ServiceProvider.GetRequiredService<IObjectProcessor>();
            await processor.ProcessAsync(ct);
            await Task.Delay(TimeSpan.FromSeconds(5), ct);
        }
    }
}
```

## Padrões da doc
- **Timed:** `System.Threading.Timer` **não espera** a execução anterior de `DoWork` terminar (pode sobrepor); incremente contadores com `Interlocked`. Para evitar sobreposição use um loop com `Task.Delay` ou `PeriodicTimer` (a doc traz "Asynchronous timed background task"; confirmar a página antes de detalhar).
- **Fila (queued background tasks):** endpoints enfileiram itens e o `BackgroundService` consome (em vez de executar no request).
- **Native AOT:** há orientação específica na doc.
- Worker template **não habilita Server GC** por padrão; avalie (`ServerGarbageCollection`).
- Container: `DockerDefaultTargetOS` (Linux/Windows).

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | `DbContext`/serviço scoped injetado direto no `BackgroundService` | Alta |
| 2 | `ExecuteAsync` sem respeitar `stoppingToken` (shutdown ungraceful) | Alta |
| 3 | `StartAsync` demorado (bloqueia o start dos demais) | Média |
| 4 | Tarefa de fundo disparada por `Task.Run`/`async void` dentro do controller | Alta |
| 5 | Exceção não tratada que derruba o loop (sem try/catch/log dentro do loop) | Alta |
| 6 | Timer sobrepondo execuções; estado compartilhado sem sincronização | Média |
| 7 | Override de `StartAsync/StopAsync` sem chamar o base | Média |
| 8 | Serviço "run once" sem `StopApplication` | Média |
| 9 | Ordem de serviços dependentes não considerada (registro) | Baixa |

## Fontes oficiais
- Background tasks with hosted services: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/host/hosted-services
- Worker services in .NET: https://learn.microsoft.com/en-us/dotnet/core/extensions/workers
- Generic Host: https://learn.microsoft.com/en-us/dotnet/core/extensions/generic-host
- Scoped service em worker: https://learn.microsoft.com/en-us/dotnet/core/extensions/scoped-service
- Queue service: https://learn.microsoft.com/en-us/dotnet/core/extensions/queue-service
- Timer service: https://learn.microsoft.com/en-us/dotnet/core/extensions/timer-service
