---
name: csharp-async-await
description: Implementar ou revisar código assíncrono em C# (async/await, Task, Task<T>, ValueTask, Task.WhenAll/WhenAny, CancellationToken, async void, .Result/.Wait, ConfigureAwait, deadlock). Use quando o usuário pedir para criar uma task/método assíncrono, verificar se o await está correto, ou revisar uso de Task.Run e cancelamento. Based on official Microsoft Learn docs.
---

# C# async/await — implementar e revisar

Regra de ouro: **só afirme o que está na documentação oficial** (fontes no fim). Se a dúvida não estiver coberta aqui nem em `references/official-notes.md`, busque na doc (WebFetch em learn.microsoft.com) antes de responder. Não invente.

## Decisão rápida: qual padrão usar?

| Situação | O que fazer |
|---|---|
| **I/O-bound** (banco, HTTP, arquivo) | `async` + `await` direto na API assíncrona. **Sem** `Task.Run`. |
| **CPU-bound** (cálculo pesado) | `await Task.Run(() => Calcula())`. Meça antes: pode não compensar. |
| Várias operações independentes | Inicie todas, guarde as `Task`, depois `await Task.WhenAll(...)`. |
| Processar conforme terminam | `Task.WhenAny` em loop (`ToList()`, remover a concluída, `await` nela). |

## Como escrever (implementação)

1. Assinatura: modificador `async`, retorno `Task` (sem valor) ou `Task<T>` (com valor), nome terminando em `Async` (`GetUserAsync`).
2. `ValueTask<T>` só quando o método frequentemente completa de forma síncrona/cacheada em caminho crítico (evita alocação). Padrão continua sendo `Task`.
3. `async void` **somente** em event handlers. Em handler, mantenha o código mínimo e delegue para um método `async Task` testável.
4. Todo método `async` deve ter pelo menos um `await` (senão roda síncrono e o compilador avisa).
5. Aceite `CancellationToken` como último parâmetro em operações longas/I/O e repasse adiante para as APIs chamadas.
6. Cancelar: preferir `ct.ThrowIfCancellationRequested()` (a task vai para o estado *Canceled*). Apenas retornar do delegate deixa a task como *RanToCompletion*. Passe o **mesmo token** também ao `Task.Run`.
7. Exceções: o `await` relança a **primeira** exceção interna (não `AggregateException`). Validação de argumentos deve falhar **de forma síncrona** em métodos que retornam Task (doc: "Exceptions in task-returning methods").
8. Em `async`, não declare parâmetros `in`, `ref` ou `out`.

```csharp
// I/O-bound
public async Task<int> GetLengthAsync(string url, CancellationToken ct = default)
{
    string contents = await _httpClient.GetStringAsync(url, ct);
    return contents.Length;
}

// Concorrência: iniciar tudo primeiro, aguardar depois
var eggsTask  = FryEggsAsync(2);
var toastTask = MakeToastAsync(2);
await Task.WhenAll(eggsTask, toastTask);

// LINQ + async: SEMPRE materializar (ToArray/ToList) para iniciar todas as tasks
var tasks = userIds.Select(id => GetUserAsync(id)).ToArray();
User[] users = await Task.WhenAll(tasks);
```

## Checklist de revisão (reporte `arquivo:linha` + problema + correção)

| # | Verificar | Problema se violado |
|---|---|---|
| 1 | `.Result`, `.Wait()`, `.GetAwaiter().GetResult()`, `Task.WaitAll/WaitAny` em código com contexto (ASP.NET clássico/UI) | Risco de **deadlock**, exceções embrulhadas em `AggregateException`, thread bloqueada. Trocar por `await`, `WhenAll`, `WhenAny`. |
| 2 | `async void` fora de event handler | Exceção não capturável, não aguardável, difícil de testar. Trocar por `async Task`. |
| 3 | `Thread.Sleep` dentro de fluxo async | Bloqueia thread. Usar `await Task.Delay`. |
| 4 | `Task.Run` envolvendo chamada I/O já assíncrona | Desnecessário. Remover; só usar para CPU-bound. |
| 5 | `Select(async ...)`/`Select(x => FooAsync(x))` sem `ToList()/ToArray()` | Execução adiada: tasks não iniciam quando esperado. Materializar. |
| 6 | Método `async` sem nenhum `await` | Roda síncrono, state machine inútil. Remover `async` ou aguardar algo. |
| 7 | Método assíncrono sem sufixo `Async` | Convenção .NET (exceto event handlers, actions de controller, contratos de interface/base). |
| 8 | Lambda `async` passada para `Action` | Vira `async void`. Usar `Func<Task>`. |
| 9 | Falta `CancellationToken` em I/O longo / token não repassado | Operação não cancelável. |
| 10 | `Task.WhenAny`: resultado não aguardado depois | Exceções e resultado perdidos: faça `await finishedTask`. |
| 11 | Estado compartilhado mutado em dois pontos com `await` no meio | Condição de corrida. Proteger com `SemaphoreSlim.WaitAsync` (não se pode `await` dentro de `lock`). |
| 12 | Sem necessidade de bloquear mas há "wrapper síncrono" de método async | Evitar. Se for inevitável: `GetAwaiter().GetResult()` é preferível a `.Result/.Wait()` (não embrulha exceção), ainda com risco de deadlock. |

### ConfigureAwait
- Em **bibliotecas** sem dependência de contexto, `ConfigureAwait(false)` evita capturar contexto (desempenho e deadlock).
- **Não** usar quando o código após o `await` precisa do contexto (UI, `HttpContext` no ASP.NET clássico).
- Em ASP.NET Core não há `SynchronizationContext` por padrão; ainda assim, bloquear em async continua sendo má prática. Para detalhes e quando usar, ler o *ConfigureAwait FAQ* (link abaixo) antes de recomendar.

## Formato da resposta de revisão
1. Lista de achados por severidade (Alta: deadlock/async void/bloqueio; Média: falta de token, não materializado; Baixa: nomenclatura).
2. Para cada achado: trecho, por que é problema (cite a fonte), código corrigido.
3. Se tudo estiver correto, diga explicitamente o que foi checado.

## Fontes oficiais
- Programação assíncrona (visão geral): https://learn.microsoft.com/en-us/dotnet/csharp/asynchronous-programming/
- Modelo TAP com async/await: https://learn.microsoft.com/en-us/dotnet/csharp/asynchronous-programming/task-asynchronous-programming-model
- Cenários (I/O vs CPU, WhenAll, bloqueio síncrono, ValueTask): https://learn.microsoft.com/en-us/dotnet/csharp/asynchronous-programming/async-scenarios
- Cancelamento de tasks: https://learn.microsoft.com/en-us/dotnet/standard/parallel-programming/task-cancellation
- Best practices (arquivo MSDN Magazine, 2013, Stephen Cleary): https://learn.microsoft.com/en-us/archive/msdn-magazine/2013/march/async-await-best-practices-in-asynchronous-programming
- ConfigureAwait FAQ: https://devblogs.microsoft.com/dotnet/configureawait-faq

Mais detalhes extraídos: `references/official-notes.md`.
