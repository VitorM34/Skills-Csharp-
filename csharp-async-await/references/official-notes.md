# Notas extraídas da documentação oficial (async/await)

Resumo em palavras próprias; consulte as páginas para o texto original. Páginas lidas em 2026-10-21.

## Task, threads e await
- `async`/`await` **não criam threads extras**. O método roda no contexto atual e só usa tempo de thread quando está ativo. (TAP model)
- `await` não bloqueia a thread: registra o resto do método como continuação e devolve o controle ao chamador. `finally` **não** executa na suspensão.
- Se a task já terminou quando é aguardada, o controle continua no mesmo método (sem custo de suspensão).
- Uma operação composta de parte assíncrona + parte síncrona é, como um todo, assíncrona.
- Tipos de retorno válidos: `Task<TResult>`, `Task`, `void` (só event handler), qualquer tipo com `GetAwaiter` (ex.: `ValueTask<T>`).
- Não existem parâmetros `in/ref/out` nem retorno por referência em método `async`.
- Convenção: métodos que retornam tipos aguardáveis terminam com `Async`; pode-se ignorar quando evento/classe base/interface dita outro nome.

## Exceções
- Exceção lançada em método async fica armazenada na `Task` (`Task.Exception`, um `AggregateException`). Ao `await`, relança-se a **primeira** exceção interna.
- `Wait()`/`Result` embrulham em `AggregateException`.
- Boa prática: erros de validação de argumento surgem de forma síncrona em métodos que retornam Task.

## Concorrência
- Iniciar tasks sem aguardar imediatamente (guardar o objeto `Task`) e aguardar no momento em que o resultado é necessário.
- `Task.WhenAll`: completa quando todas completam. `Task.WhenAny`: devolve `Task<Task>`; é preciso `await` na task concluída para obter resultado/exceção.
- Com LINQ, execução é adiada: sempre `ToArray()` (processar tudo junto, `WhenAll`) ou `ToList()` (gerenciar dinamicamente, `WhenAny` + `Remove`).
- Compare `async/await` vs `ContinueWith`: async/await é mais legível, melhor para erros, depuração e o compilador gera código otimizado.

## I/O-bound vs CPU-bound
| Pergunta | Cenário | Implementação |
|---|---|---|
| Espera resultado (ex.: banco)? | I/O-bound | `async`/`await` **sem** `Task.Run`; evitar TPL |
| Cálculo caro? | CPU-bound | `await Task.Run(...)`; considerar TPL se paralelizável |
Sempre medir: o custo de troca de contexto pode superar o ganho.

## Bloqueio síncrono (último recurso)
Ordem de preferência quando não dá para usar `await`: `GetAwaiter().GetResult()` → `Task.Run(async () => await X()).GetAwaiter().GetResult()` → `Wait()/Result` (desencorajado). Todos podem causar deadlock; preferir async até o ponto de entrada.

Tabela de substituição:
| Em vez de | Use |
|---|---|
| `Task.Wait`/`Task.Result` | `await` |
| `Task.WaitAny` | `await Task.WhenAny` |
| `Task.WaitAll` | `await Task.WhenAll` |
| `Thread.Sleep` | `await Task.Delay` |

## Deadlock (MSDN Magazine, Stephen Cleary)
- `await` captura o contexto (`SynchronizationContext`, senão `TaskScheduler`). Em GUI/ASP.NET clássico, só um bloco roda por vez; bloquear com `.Wait()` enquanto a continuação precisa do mesmo contexto trava os dois.
- Console não tem esse problema (contexto do thread pool), por isso o bug "só aparece em produção".
- Exceção à regra "async o caminho todo": `Main` de console clássico pode chamar `MainAsync().Wait()` (hoje `static async Task Main` é possível).
- `ConfigureAwait(false)` ajuda desempenho e evita deadlock, mas não use quando o código seguinte precisa do contexto.
- Para sincronizar recurso compartilhado em async: `SemaphoreSlim` com `WaitAsync` (não se pode `await` dentro de `lock`).
- Ferramentas: `Task.Run` (CPU), `TaskCompletionSource<T>` (envolver evento/operação), `CancellationTokenSource/Token`, `IProgress<T>/Progress<T>`.

## Cancelamento
- Cooperativo: quem solicita chama `CancellationTokenSource.Cancel()`; o delegate encerra em tempo hábil.
- Duas formas: retornar (task fica *RanToCompletion*) ou lançar `OperationCanceledException` com o token, de preferência via `ThrowIfCancellationRequested()` (task fica *Canceled*).
- A task só entra em *Canceled* se a exceção carrega o **mesmo token** passado à criação da task e `IsCancellationRequested == true`; senão vira *Faulted*.
- Aguardar task cancelada com `Wait/WaitAll` lança `TaskCanceledException` embrulhada em `AggregateException`; com `await`, lança `OperationCanceledException`. Descarte o `CancellationTokenSource` (`Dispose`).
