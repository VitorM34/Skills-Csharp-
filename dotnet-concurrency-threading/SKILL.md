---
name: dotnet-concurrency-threading
description: Implementar e revisar concorrência e paralelismo em .NET - threads vs ThreadPool, lock e System.Threading.Lock, Monitor, Interlocked, SemaphoreSlim, Mutex, deadlocks e race conditions, Parallel.For/ForEach (TPL data parallelism), System.Threading.Channels (produtor/consumidor), coleções thread-safe (ConcurrentDictionary etc.). Use quando o usuário pedir código multithread, sincronização, filas produtor/consumidor ou revisar race conditions. Based on official Microsoft Learn docs.
---

# Concorrência, threads e paralelismo

Só afirmar o que a doc oficial diz (fontes no fim). **async/await e Task**: `csharp-async-await`. Tarefas em segundo plano: `aspnet-hosted-services`. Coleções: `csharp-collections`.

## Princípios (managed threading best practices)
- Multithreading exige programação cuidadosa; **para a maioria das tarefas, enfileire trabalho no ThreadPool** (via `Task`/TPL).
- **Race condition:** resultado depende de qual thread chega primeiro (ex.: `objCt++` em campo estático = carregar/incrementar/gravar não é atômico). Ao escrever cada linha, pense no que ocorre se a thread for **preemptada** antes dela.
- **Deadlock:** threads esperando umas pelas outras (evite bloquear em ordem inconsistente, ver async: `.Result`/`.Wait()`).
- ✖ **Não use `Thread.Abort`** (obsoleto; lança `PlatformNotSupportedException` no .NET 5+): use **cancelamento cooperativo** com `CancellationToken`. ✖ `Thread.Suspend/Resume` para sincronizar: use `Mutex`, `ManualResetEvent`, `AutoResetEvent`, `Monitor`.
- ✖ Não controle workers a partir do programa principal por eventos; faça o **worker responsável por esperar trabalho, executar e notificar**. Se os workers não bloqueiam, use thread pool.
- Várias threads para tarefas que usam **recursos diferentes** (I/O, entrada do usuário); evite várias threads sobre o mesmo recurso; tarefas CPU-bound competem entre si.

## `lock` e objetos de sincronização
- **`lock`**: use um **objeto dedicado e privado**. ✖ **não faça lock em tipos** (`lock(typeof(X))`: um `Type` por AppDomain, código externo pode travar nele) nem com cautela em `this` (código externo pode travar na mesma instância → deadlock).
- **.NET 9 / C# 13:** use uma instância dedicada de **`System.Threading.Lock`** com o `lock` statement (usa `Lock.EnterScope()`); antes, um objeto de referência privado (`Monitor.Enter/Exit` com `try/finally`). `lock` garante liberar o monitor mesmo com exceção; se não puder garantir `Exit`, considere `Mutex` (liberado quando a thread dona termina).
- ✔ **`Interlocked`** para mudanças de estado simples (`Increment`, `Add`, `CompareExchange`) em vez de `lock`: melhor desempenho para atualizações atômicas (a doc mostra substituir `lock { x++ }` por `Interlocked.Increment`; para incrementos > 1 use `Interlocked.Add`; para "atribuir só se nulo" use `CompareExchange`).
- **Primitivas** (visão geral): `Monitor`/`lock` (exclusão mútua intra-processo, reentrante), **`Mutex`** (thread affinity; **nomeado = entre processos**), **`SemaphoreSlim`** (leve, **só intra-processo**; tem `WaitAsync`), **`ReaderWriterLockSlim`** (vários leitores, um escritor), `SpinLock`, eventos (`EventWaitHandle`, `ManualResetEventSlim`), `Barrier`, `CountdownEvent`. **Tipos leves** (sem handles do SO) rendem mais, mas não servem a sincronização **entre processos**. **Não dá para `await` dentro de `lock`**: use `SemaphoreSlim.WaitAsync` (ver `csharp-async-await`).
- Membros estáticos e construtores estáticos: cuidado com threads (a doc tem seção dedicada).

## ThreadPool
- Pool de **threads de background** gerenciadas pelo sistema, **um por processo**, reutilizadas; a fila de itens só é limitada pela memória, mas o **nº de threads ativas é limitado** (itens esperam). O pool cria/destrói threads para otimizar **throughput** (muitas threads aumentam contenção). Há **mínimo de threads** configurável (cuidado ao alterar).
- Use **TPL** (`Task`, `Task<T>`) sempre que possível. **Crie sua própria thread** só se precisar de **foreground thread**, de prioridade específica, etc.
- Exceções não tratadas em thread do pool **terminam o processo** (a doc lista 3 exceções à regra; trate dentro do trabalho).

## Parallel (TPL data parallelism)
`Parallel.For`/`Parallel.ForEach` particionam a coleção para várias threads (o scheduler redistribui trabalho se desbalanceado); escreva o corpo como um loop normal. Overloads permitem parar/sair do loop (`ParallelLoopState`), controlar o grau de concorrência (`ParallelOptions`), **estado local por thread** (reduz sincronização), cancelamento por `CancellationToken`. PLINQ para sintaxe declarativa. **Não** use `Parallel` para trabalho **I/O-bound** (use `async`; ver async-scenarios: CPU-bound → `Task.Run`/TPL). Corpos muito pequenos podem não compensar (há how-to "speed up small loop bodies"); meça.

## Channels (`System.Threading.Channels`) — produtor/consumidor assíncrono
- **Unbounded:** capacidade ilimitada (escritas síncronas); **Bounded:** capacidade máxima; quando cheio, padrão **`BoundedChannelFullMode.Wait`** (`WriteAsync` espera; `TryWrite` retorna `false`), ou `DropNewest`/`DropOldest`/`DropWrite`. Prefira **bounded** para impor **back-pressure** (evita crescimento de memória sem limite).
- Opções `SingleWriter`/`SingleReader` (a doc as define como `false` para vários produtores/consumidores); `AllowSynchronousContinuations = true` faz a escrita poder executar trabalho do leitor (cuidado). Todas as APIs assíncronas retornam `ValueTask`. Usar um canal **após fechado** lança `ChannelClosedException`. Produtor: `WriteAsync`/`TryWrite`/`Complete`; consumidor: `ReadAsync`/`WaitToReadAsync`/`ReadAllAsync`.
- Combine com `BackgroundService` para filas de trabalho (`aspnet-hosted-services`).

## Coleções thread-safe (`System.Collections.Concurrent`)
- Para **várias threads escrevendo**, use as coleções concorrentes (thread-safe **e** escaláveis, sem sincronização externa). **`List<T>`/`Dictionary<,>` não têm sincronização**: o código do usuário precisa sincronizar. **Se só lê** uma coleção compartilhada, as genéricas simples bastam. `ArrayList/Hashtable.Synchronized` travam a coleção inteira a cada operação (pior).
- `ConcurrentQueue<T>` rende melhor com **um** produtor e **um** consumidor dedicados (ganho modesto sobre `Queue<T>` + lock quando o processamento por item é minúsculo); `ConcurrentDictionary` ajuda em muitas atualizações (concorrência ajustável; **só leitura → `Dictionary` é mais rápido**); `BlockingCollection<T>` quando se precisa de **limite e bloqueio** (cancelamento, enumeração, exceções); `ConcurrentBag<T>` para dados não ordenados com inserção multi-thread rápida. **Meça** (orientação não é válida em todas as circunstâncias).

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Estado compartilhado mutável sem sincronização (campos estáticos, caches, contadores) | Alta |
| 2 | `lock(this)`/`lock(typeof(X))`/`lock("string")` | Alta |
| 3 | `await` dentro de `lock` / bloqueio com `.Result` em código async | Alta |
| 4 | `Thread.Abort`/`Suspend` | Alta |
| 5 | `lock` onde `Interlocked` basta; `Lock` (.NET 9) não adotado | Baixa |
| 6 | `Dictionary`/`List` usados por várias threads de escrita | Alta |
| 7 | `Parallel.ForEach` com I/O ou com corpo que usa estado compartilhado sem estado local | Média |
| 8 | Channel unbounded em produtor mais rápido que consumidor (memória) | Média |
| 9 | Threads criadas manualmente onde o pool/Task serve | Média |
| 10 | Exceção não tratada dentro de trabalho em thread/pool | Alta |
| 11 | Ordem inconsistente de aquisição de locks (deadlock) | Alta |

## Fontes oficiais
- Managed threading best practices: https://learn.microsoft.com/en-us/dotnet/standard/threading/managed-threading-best-practices
- Overview of synchronization primitives: https://learn.microsoft.com/en-us/dotnet/standard/threading/overview-of-synchronization-primitives
- The managed thread pool: https://learn.microsoft.com/en-us/dotnet/standard/threading/the-managed-thread-pool
- Data parallelism (TPL): https://learn.microsoft.com/en-us/dotnet/standard/parallel-programming/data-parallelism-task-parallel-library
- System.Threading.Channels: https://learn.microsoft.com/en-us/dotnet/core/extensions/channels
- Thread-safe collections: https://learn.microsoft.com/en-us/dotnet/standard/collections/thread-safe/
- When to use a thread-safe collection: https://learn.microsoft.com/en-us/dotnet/standard/collections/thread-safe/when-to-use-a-thread-safe-collection
- C# 13 `System.Threading.Lock`: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-13
