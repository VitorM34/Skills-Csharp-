---
name: dotnet-memory-disposable
description: Implementar e revisar gerenciamento de recursos e memória em .NET - IDisposable e IAsyncDisposable, dispose pattern (Dispose(bool), finalizer, SuppressFinalize, SafeHandle), using/await using, dispose em cascata, garbage collector (gerações, LOH, workstation vs server), vazamentos. Use quando o usuário pedir para implementar Dispose, revisar uso de recursos não gerenciados/HttpClient/streams, ou entender GC e LOH. Based on official Microsoft Learn docs.
---

# Recursos, IDisposable e Garbage Collector

Só afirmar o que a doc oficial diz (fontes no fim). DI e descarte de serviços: `dotnet-dependency-injection`. Desempenho web: `aspnet-performance-best-practices`.

## O que o GC faz (e não faz)
- O **GC é o gerenciador automático de memória gerenciada**: aloca/libera no heap gerenciado, compacta, dá **memória limpa** a objetos novos e garante **segurança de memória**. **Não** aloca nem libera **memória não gerenciada** e **não chama `Dispose`/`DisposeAsync`**: ele só conhece finalizers.
- **Gerações 0, 1, 2:** num app bem ajustado a maioria dos objetos morre na geração 0 (ex.: alocações por requisição). Uma coleta de geração N coleta também as mais novas; **Gen 2 = full GC** (mais cara). O usuário só aloca na Gen 0 (objetos pequenos) ou no **LOH** (objetos grandes); promoções para Gen 1/2 são feitas só pelo GC.
- **LOH (large object heap):** objetos grandes pertencem à geração 2 e **só são coletados em GC de geração 2**; normalmente **não são compactados** (compactação opcional: `GCSettings.LargeObjectHeapCompactionMode`; se precisar que não se movam, **pin**). Evite muitas alocações grandes de vida curta em caminhos quentes (ver `aspnet-performance-best-practices`). (A página do LOH descreve Windows/.NET Framework e .NET Core.)
- **Workstation × server GC:** workstation (padrão de apps standalone; em hospedados o host decide; sempre usado em máquina com 1 CPU lógica) coleta na thread de usuário que disparou; server GC usa mais recursos para throughput (configuração `ServerGarbageCollection`). **Não assuma tamanho de segmentos** (específico da implementação, muda).
- **`GC.Collect()`**: quase nunca é necessário (o GC roda continuamente); serve a casos únicos e testes.

## Quem deve ser descartado
- **Todo `IDisposable`/`IAsyncDisposable` deve ser descartado**, independentemente do escopo da variável, salvo indicação contrária. Use **`using`** (declaração `using var x = ...;` é a forma preferida de código moderno) ou **`await using`** para `IAsyncDisposable`; `try/finally` direto quando necessário.
- **Dispose em cascata:** se sua classe **possui** (campo/propriedade) um `IDisposable`, ela também deve implementar `IDisposable` e descartá-lo (quem instancia e guarda como membro é responsável).
- Objetos **resolvidos do container de DI não são descartados por você**; os que **você** cria (ou registra prontos) são sua responsabilidade (ver DI).
- `Dispose` deve ser **idempotente**: chamável várias vezes sem exceção, sem efeito a partir da 2ª.

## Dispose pattern (classes não seladas)
Considere toda classe não selada como **base potencial**:
```csharp
public class Resource : IDisposable
{
    private bool _disposed;
    public void Dispose()                       // público, NÃO virtual, sem parâmetros
    {
        Dispose(disposing: true);
        GC.SuppressFinalize(this);              // diz ao GC que o finalizer (se houver) não precisa rodar
    }
    protected virtual void Dispose(bool disposing)   // subclasses sobrescrevem este
    {
        if (_disposed) return;
        if (disposing) { /* descartar objetos gerenciados IDisposable (cascata) / SafeHandle */ }
        /* liberar recursos não gerenciados */
        _disposed = true;
    }
}
```
- `disposing = true` quando chamado por `Dispose()` (determinístico); **`false` quando vem do finalizer**: nesse caminho **só** libere recursos não gerenciados e **não toque em objetos gerenciados** (a ordem de finalização é não determinística).
- **Finalizer (`~T`/`Object.Finalize`) só é necessário se você referencia recursos não gerenciados diretamente** (cenário avançado, evitável). Se só tem objetos gerenciados, **não precisa de finalizer**. Para recursos não gerenciados, **envolva o handle num `SafeHandle`** (que já tem finalizer).
- FDG: ✖ **não torne `Dispose()` sem parâmetros virtual**; ✖ não declare outros overloads de `Dispose`; ✔ finalizer + dispose pattern em tipos que seguram recursos sem finalizer próprio; finalizar atrasa a coleta (a memória só é liberada na coleta seguinte), por isso não dependa só de finalizers.
- Thread-safety no descarte quando necessário (a doc mostra `Interlocked.CompareExchange`).

## IAsyncDisposable (`DisposeAsync`)
- Implemente também `IDisposable` quando possível: **só `IAsyncDisposable` + consumidor chamando `Dispose` = vazamento** (nunca chama `DisposeAsync`).
- Classes não seladas: `public ValueTask DisposeAsync()` (chama `DisposeAsyncCore()` e `Dispose(disposing: false)`, depois `GC.SuppressFinalize`) e `protected virtual ValueTask DisposeAsyncCore()`; observe que o `Dispose(bool)` recebe **`false`** a partir do `DisposeAsync` (e `true` a partir de `Dispose`). Há variante para classes seladas e para implementar os dois.
- Consumo: `await using`; **evite empilhar** `await using` com `ConfigureAwait` (pode pular `DisposeAsync` em condições de erro): use um dos padrões aceitáveis da doc (escopos aninhados/`await using` em declarações sequenciais).

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | `IDisposable` criado e não descartado (`HttpClient` manual, `Stream`, `DbConnection`, `CancellationTokenSource`) | Alta |
| 2 | Classe que guarda `IDisposable` em campo sem implementar `IDisposable` | Alta |
| 3 | `Dispose()` virtual, ou sem `GC.SuppressFinalize`, ou não idempotente | Média |
| 4 | Finalizer em classe que só tem objetos gerenciados | Média |
| 5 | Recurso não gerenciado sem `SafeHandle` | Média |
| 6 | Acesso a objetos gerenciados no caminho `disposing == false` | Alta |
| 7 | `IAsyncDisposable` sem `IDisposable`; `await using` empilhado com `ConfigureAwait` | Média |
| 8 | `GC.Collect()` "para limpar memória" | Média |
| 9 | Muitas alocações grandes (LOH) em hot path | Média |
| 10 | Descartar manualmente serviço resolvido do DI | Média |

## Fontes oficiais
- Fundamentals of garbage collection: https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/fundamentals
- Implement a Dispose method: https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/implementing-dispose
- Implement a DisposeAsync method: https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/implementing-disposeasync
- Using objects that implement IDisposable: https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/using-objects
- Dispose pattern (design guidelines): https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/dispose-pattern
- Workstation and server GC: https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/workstation-server-gc
- Large object heap: https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/large-object-heap
