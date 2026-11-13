---
name: dotnet-background-jobs
description: Agendar e executar jobs em segundo plano no .NET com Hangfire e Quartz.NET - escolha entre BackgroundService, Hangfire e Quartz, jobs fire-and-forget/delayed/recurring, cron (Quartz usa segundos primeiro), retries, idempotência, misfire, DisallowConcurrentExecution, persistência, cluster/múltiplos nós, filas, DI com escopo, shutdown gracioso, dashboard seguro, fuso e horário de verão. Use quando o usuário pedir jobs agendados, tarefas recorrentes, cron, Hangfire, Quartz, processamento em background com persistência/retry, ou ao revisar esse código.
---

# Jobs agendados e em background (Hangfire / Quartz.NET)

**Proveniência:** documentação **oficial de cada projeto** (não é Microsoft): Hangfire (`HangfireIO/Hangfire.Documentation`) marcada **[HF]** e Quartz.NET 4.x (`quartznet/quartznet`, docs `quartz-4.x`, incl. *best-practices*, *hosted-services-integration*, *microsoft-di-integration*, *configuration/reference*) marcada **[QZ]**. Para `BackgroundService`/hosted services puros, a fonte é Microsoft e está em `aspnet-hosted-services`. **CONVENÇÃO** = recomendação desta skill, não da doc. **Não li:** Hangfire Pro/Ace (pagos), Hangfire Redis (Pro), batches, throttling em detalhe, extensibilidade de filtros, pacotes Quartz de Redis/dashboard; a página de licenciamento do Hangfire não foi verificada — confira a licença antes de adotar. Versões consultadas: Hangfire 1.8, Quartz 4.6.2 (NuGet em out/2026).
Ligações: `aspnet-hosted-services`, `aspnet-health-checks`, `dotnet-messaging`, `dotnet-rabbitmq`, `dotnet-redis`, `dotnet-serilog`, `dotnet-observability`, `aspnet-hosting-deployment`, `dotnet-security-review`, `dotnet-dapper-adonet`, `efcore-querying`, `dotnet-unit-testing`.

## Qual ferramenta usar (CONVENÇÃO, com fatos das docs)
| Necessidade | Opção |
|---|---|
| Loop/timer simples, sem persistência, perder execução num restart é aceitável | `BackgroundService` (`aspnet-hosted-services`) |
| "Executar isto depois/em background" disparado por requisição, com retry, painel e persistência | **Hangfire** (fire-and-forget, delayed, continuations, recurring) |
| Agenda complexa: calendários, cron com fuso, regras de recorrência, misfire configurável, cluster, muitos triggers por job | **Quartz.NET** |
| Mensagens entre serviços, múltiplos consumidores, entrega garantida | broker (`dotnet-messaging`, `dotnet-rabbitmq`), não scheduler |
Jobs persistentes **exigem um armazenamento** (SQL Server etc.) — é mais uma dependência operacional; só adote se precisar de persistência/retry/painel.

## Regras comuns a qualquer scheduler (valem nos dois) 
- **Idempotência/reentrância** [HF]: a doc manda tornar o método *reentrant*, pois ele pode ser interrompido (exceção, shutdown) e reexecutado; exemplo oficial: gravar um `deliveryId` e checar "não entregue" antes de enviar o e-mail. [QZ] diz o mesmo: o guard-rail de `[DisallowConcurrentExecution]` mantém o caso normal em ordem, **idempotência mantém o caso anormal correto**.
- **Argumentos/dados pequenos e simples** [HF][QZ]: passe **ids**, carregue a entidade dentro do job. Nada de entidades grandes; **nunca segredos/connection strings** em job data (aparecem em backups, painel e API).
- **Escopo por execução**: job deve resolver dependências **scoped** (ex.: `DbContext`) de um escopo criado por execução — ver DI abaixo.
- **Cancelamento/shutdown**: aceite `CancellationToken` e respeite-o. Job interrompido por shutdown é recolocado/reexecutado; logo precisa ser idempotente.
- **Relógio e fuso**: defina o fuso explicitamente; evite horários locais ambíguos (horário de verão). Teste com `TimeProvider` falso (`dotnet-unit-testing`) em vez de mexer na hora da máquina.
- **Logging e métricas**: registre início/fim/falha com id do job; falha de job não pode ficar silenciosa (`dotnet-serilog`, `dotnet-observability`).

## Hangfire [HF]
### Setup ASP.NET Core
```csharp
builder.Services.AddHangfire(c => c.UseSqlServerStorage(connectionString)); // pacote Hangfire (traz Hangfire.SqlServer)
builder.Services.AddHangfireServer();   // processamento como IHostedService
...
app.MapHangfireDashboard();             // painel (veja segurança)
```
- Armazenamento SQL Server: `Hangfire.SqlServer`; suporta SQL Server 2008R2+ e Azure SQL. Prefira **`Microsoft.Data.SqlClient`** (a 1.8 não referencia mais `System.Data.SqlClient`; usa o novo se instalado). O schema é **instalado automaticamente** pelo construtor de `SqlServerStorage`; para integrar com suas migrations use `PrepareSchemaIfNecessary = false`. Dá para isolar num schema `HangFire` com usuário próprio (script na doc).
- Opções "recomendadas" (1.7+; na 1.8 são auto-detectadas pela versão do schema, desligável com `TryAutoDetectSchemaDependentOptions = false`): `CommandBatchMaxTimeout`, `SlidingInvisibilityTimeout`, `QueuePollInterval = TimeSpan.Zero`, `UseRecommendedIsolationLevel`, `DisableGlobalLocks` (requer migração para schema 7).
### Tipos de job
- **Fire-and-forget**: `IBackgroundJobClient.Enqueue<IService>(x => x.Run(id))` — injete `IBackgroundJobClient` em vez de usar o estático quando possível.
- **Delayed**: `Schedule(...)`; **continuations**: `ContinueJobWith`.
- **Recurring**: `RecurringJob.AddOrUpdate("id-unico", () => ..., Cron.Daily)` ou cron `"0 12 * */2"` (os exemplos da doc usam **5 campos**; não li se há variante com segundos). O id **precisa ser único** (senão vira um job só) e pode ser *case sensitive*; `RemoveIfExists`, `Trigger` (não recalcula a próxima execução). Um componente do servidor verifica recorrentes **a cada minuto**.
- `RecurringJob` é fachada de `RecurringJobManager` (doc). Prefira jobs sobre **interfaces/serviços** (resolvidos pelo container) a lambdas sobre classes estáticas (CONVENÇÃO; as APIs injetáveis `IRecurringJobManager`/`AddOrUpdate<T>` **não** estão nas páginas que li — confira).
### Retries e falhas
- `AutomaticRetryAttribute` é aplicado **globalmente com 10 tentativas** por padrão; depois vai para `Failed` (visível no painel, não expira até você excluir). `[AutomaticRetry(Attempts = 0)]` desliga; `GlobalJobFilters.Filters.Add(new AutomaticRetryAttribute { Attempts = 5 })` muda o padrão. Com `AddHangfire`, dependências de filtros devem ser *Transient/Singleton*.
- Retry é seguro **só** com job idempotente — erros de programação reexecutam 10 vezes à toa; não use retry para erro permanente (CONVENÇÃO: capture/valide e falhe sem retry quando for determinístico).
- **Habilite logging** do Hangfire (erros internos só aparecem em log).
### Cancelamento e DI
- Parâmetro `CancellationToken` comum é suportado desde a 1.7 (substituído em runtime); um processo de fundo consulta o storage em `CancellationCheckInterval` (padrão 5 s). Job derrubado por shutdown volta ao início da fila. `IJobCancellationToken` é obsoleto.
- Em ASP.NET Core a integração DI cria o job a partir do container (escopo por job); **`HttpContext` não está disponível** no job — passe os dados necessários como argumento.
### Filas e servidores
- `[Queue("alpha")]` no método; nomes: **minúsculas, dígitos, `_` e `-`**. Servidores escolhem filas em `AddHangfireServer(o => o.Queues = new[]{"alpha","beta","default"})`; ordem de processamento **depende do storage** (SQL Server: ordem alfanumérica, índice ignorado).
- Vários servidores/processos usam o mesmo storage e coordenam por locks distribuídos (desde 1.5 nomes únicos via GUID). Grau de paralelismo: `WorkerCount`.
### Dashboard
- Por padrão o painel só aceita **requisições locais**. Em produção exija autorização: `IDashboardAuthorizationFilter` (ou `MapHangfireDashboard().RequireAuthorization(...)` — a doc alerta que, com endpoint routing, mesmo assim o filtro local continua valendo se você não o substituir). Nunca deixe o painel aberto: ele permite disparar/excluir jobs (`dotnet-security-review`, `aspnet-authentication-authorization`).
### Hospedagem [HF]
- O servidor Hangfire **precisa estar sempre ativo**: em app web, não inicia até o primeiro request e pode parar por idle timeout/reciclagem do pool (IIS: always running + preload; ver `aspnet-hosting-deployment`). Se o processamento é pesado/longo ou jobs são abortados constantemente, a doc recomenda **mover o processamento para outro processo** (worker/console/serviço) — o app web só enfileira.

## Quartz.NET [QZ]
### Setup (4.x, Microsoft DI + Generic Host)
```csharp
builder.AddQuartz(q =>                       // lê a seção "Quartz" do appsettings
{
    q.ScheduleJob<ReportJob>(t => t
        .WithIdentity("daily-report")
        .WithCronSchedule("0 0 2 * * ?"));   // SEGUNDOS primeiro
});
builder.AddQuartzHostedService(o => o.WaitForJobsToComplete = true);
```
- Registrar jobs como **scoped**: `AddJob<T>`/`ScheduleJob<T>` registram o tipo como scoped; a job factory abre **um escopo por disparo** e o descarta ao fim, então o job pode usar `DbContext`. Mantenha **um construtor público** por job. Propriedades do job data são aplicadas em properties de mesmo nome/tipo (precisam de setter).
- Hosted service: `WaitForJobsToComplete` padrão **`false`** (host encerra com jobs rodando) — ligue-o; `AwaitApplicationStarted` padrão true; `AutoStart=false` quando você mesmo inicia (ex.: após eleição de líder). `AddQuartzHostedService()` sem scheduler registrado **lança no startup**. No 3.x os pacotes eram separados (`Quartz.Extensions.*`); 4.x tem tudo no pacote `Quartz`.
- Health check: `AddHealthChecks().AddQuartz()` (Healthy = rodando e alcança o store; Degraded = standby/`Created` com AutoStart=false).
### Job
```csharp
[DisallowConcurrentExecution]
public sealed class ReportJob(IReportService svc, ILogger<ReportJob> log) : IJob
{
    public static readonly JobKey Key = new("daily-report");
    public async ValueTask Execute(IJobExecutionContext ctx, CancellationToken ct) // 4.x: ValueTask + token
        => await svc.RunAsync(ct);
}
```
(No 3.x a assinatura é `Task Execute(IJobExecutionContext)`.) Escreva a `JobKey` **uma vez** como `static readonly`.
### Quando o job lança exceção
- A exceção é logada, embrulhada em `JobExecutionException` e o trigger completa o disparo normalmente: **o job NÃO é reexecutado e a agenda não muda** (nas duas versões). Não há retry automático.
- Para refazer: `throw new JobExecutionException(ex) { RefireImmediately = true }` (3.x: argumento `refireImmediately: true`) — reexecuta **imediatamente, no mesmo worker, sem backoff**; **limite** com `context.RefireCount < N`, senão vira laço apertado. Outras flags: `UnscheduleFiringTrigger`, `UnscheduleAllTriggers`. Cancelar via token **não** é falha.
- Retry com atraso/backoff: reagende um trigger novo (CONVENÇÃO — a doc lida aqui só descreve o refire imediato).
### Concorrência
- `[DisallowConcurrentExecution]` impede execuções sobrepostas **da mesma JobKey** (não da classe); com store persistente vale **no cluster inteiro**, mas é tão bom quanto a tabela de fired-triggers (veja relógio). Com `[PersistJobDataAfterExecution]` use também `[DisallowConcurrentExecution]`.
- Limite por categoria de trabalho: *execution groups*. Nenhum dos dois é uma fila: trabalho retido **misfire**, não enfileira.
- `MaxConcurrency` (thread pool) configurável em `Quartz:ThreadPool`.
### Misfire (escolha pela consequência)
- Misfire = disparo que não rodou dentro do threshold do horário previsto (scheduler parado, pool cheio, trigger retido). Padrão `SmartPolicy`: cron/recorrência → **dispara uma vez agora e retoma**; simple infinito → pula para o próximo.
- Cron: `IgnoreMisfires` (roda todos os perdidos — recupera "o mais rápido que o pool permitir": 20 disparos seguidos após 5 min parado num trigger de 15 s), `FireAndProceed` (um agora), `DoNothing` (pula). 4.x troca os métodos nomeados por `WithMisfireInstruction` com enum por família.
- Pergunta-guia: a ocorrência é sobre um **momento** (pular) ou um **backlog** (recuperar)? Ex.: acerto noturno perdido → rodar uma vez atrasado (padrão); refresh de cache → só o próximo.
- Threshold padrão do store persistente: 60 s (`RAMJobStore`: 5 s).
### Cron e fuso
- **Quartz cron tem SEGUNDOS no início** e usa `?`; `* 0/5 * * * ?` = todo segundo de cada 5º minuto; "a cada 5 minutos" = `0 0/5 * * * ?`. Linha de crontab de 5 campos **não** é cron do Quartz (e o dia da semana é 1-7 a partir de domingo, não 0-6). 4.x: `CronExpression.Parse(linha, CronFormat.Unix)` / `CronScheduleBuilder.Create(linha, CronFormat.Unix)`.
- **Cuidado ao migrar 3.x → 4.x:** `0 0 0 ? * MON/2` mudou de significado (3.x quinzenal; 4.0 `FormatException`; ≥4.1 vira seg/qua/sex, sem log). Audite antes de atualizar.
- Tipo de trigger certo para o que você quer: intervalo real (`SimpleTrigger`), hora do dia na zona (`CronTrigger`/`RecurrenceTrigger`), a cada N dias/meses (`CalendarIntervalTrigger`), janela diária (`DailyTimeIntervalTrigger`). Regras que cron não diz (quinzena, "penúltima sexta") → `RecurrenceTrigger` (RFC 5545). Defina o fuso do cron explicitamente.
### Persistência e cluster
- `UsePersistentStore(s => s.UseSqlServer(cs))` (padrão é RAM: some no restart). `StoreJobDataAsStrings = true` **desde o início do projeto** evita problemas de versão/serialização. Tabelas `QRTZ_` (prefixo configurável; scripts de schema vêm na doc/repo do Quartz — **não os reescreva de memória**).
- Cluster: `store.UseClustering()` (liga locks de banco); todos os nós com **mesmo `InstanceName`** e **`InstanceId` diferente** (`GenerateInstanceId = true`). `CheckinInterval`/`CheckinMisfireThreshold` padrão 7,5 s cada.
- **Relógios dos nós precisam concordar**: um nó ~7 s à frente pode declarar morto um nó saudável, liberar seus triggers, criar recovery triggers e **apagar suas linhas de fired-trigger — o `DisallowConcurrentExecution` deixa de valer**. Use NTP e alerte no log de recovery.
- A best-practices do Quartz desaconselha re-registrar triggers a cada deploy com start "agora + poucos segundos" (o restante da frase eu **não li por inteiro**); use identidades estáveis (`WithIdentity`) (CONVENÇÃO; a semântica de substituir/duplicar agendas no store persistente **não li** — confira).
### Dashboard/segurança
- Job data e logs podem expor dados: nada de segredos neles; qualquer API/painel de gestão do Quartz deve ficar atrás de autenticação (CONVENÇÃO).

## Hangfire × Quartz em resumo (fatos)
| | Hangfire | Quartz.NET |
|---|---|---|
| Modelo | lambda/método serializado; fila de jobs | classes `IJob` + triggers |
| Retry | automático (10 por padrão) | **nenhum**; refire imediato manual |
| Cron | exemplos da doc com 5 campos | segundos primeiro (6-7 campos) |
| Painel | embutido (Dashboard) | não li |
| Misfire | não li (só: recorrentes são checados a cada minuto e enfileirados) | instruções por tipo de trigger |
| Cluster | vários servidores no mesmo storage | cluster com `InstanceId`s + relógios sincronizados |

## Checklist de revisão
- [ ] Tem mesmo necessidade de scheduler persistente, ou `BackgroundService` basta (`aspnet-hosted-services`)?
- [ ] Job **idempotente**; dados do job são ids pequenos; **sem segredos**; sem `HttpContext`.
- [ ] Dependências scoped via escopo por execução; `CancellationToken` respeitado.
- [ ] Hangfire: retries ajustados (`Attempts`) conforme o job; logging do Hangfire ligado; erro permanente não é reexecutado 10x; filas com nomes válidos.
- [ ] Hangfire: dashboard com `IDashboardAuthorizationFilter` em produção; servidor sempre ativo (ou processo separado).
- [ ] Quartz: cron com **segundos primeiro**; fuso explícito; auditoria `MON/2` na migração 3.x→4.x.
- [ ] Quartz: `WaitForJobsToComplete = true`; `RefireImmediately` limitado por `RefireCount`; **misfire** escolhido pela consequência; `[DisallowConcurrentExecution]` onde sobreposição é perigosa.
- [ ] Quartz persistente: store configurado, `StoreJobDataAsStrings`, cluster com `InstanceId`s distintos e relógios sincronizados.
- [ ] Health check do scheduler; logs/alertas para falha de job; teste com `TimeProvider`/relógio falso.
- [ ] Licença do Hangfire (e extensões Pro) verificada antes de uso comercial.

## Fontes
- [HF] https://docs.hangfire.io/ (repo `HangfireIO/Hangfire.Documentation`): best-practices, dealing-with-exceptions, performing-recurrent-tasks, using-cancellation-tokens, configuring-queues, running-multiple-server-instances, using-sql-server, using-dashboard, making-aspnet-app-always-running, getting-started/aspnet-core-applications.
- [QZ] https://www.quartz-scheduler.net/documentation/quartz-4.x/ — best-practices, packages/hosted-services-integration, packages/microsoft-di-integration, configuration/reference, tutorial/job-stores (repo `quartznet/quartznet`).
- Microsoft (hosted services): ver `aspnet-hosted-services`.
