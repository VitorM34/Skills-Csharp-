---
name: efcore-querying
description: Implementar e revisar consultas no EF Core - tracking vs AsNoTracking, projeção com Select, N+1, Include/eager loading, lazy loading, split queries, paginação, Take, AsAsyncEnumerable, buffering vs streaming, índices, SQL bruto, async. Use quando o usuário pedir para otimizar queries, verificar N+1, ou revisar leitura/gravação com DbContext. Based on official Microsoft Learn docs.
---

# EF Core — consultas eficientes e corretas

Só afirmar o que a doc oficial diz (fontes no fim). LINQ geral: `csharp-linq`. Contexto: `efcore-dbcontext-connection`.

## Tracking vs no-tracking
- Por padrão queries que retornam entidades são **tracking**: alterações são gravadas no `SaveChanges`; EF faz *identity resolution* (mesma instância para a mesma chave) e fixa navegações.
- **Leitura somente** → `AsNoTracking()`: mais rápido (sem change tracker/snapshot), mas sem identity resolution (a mesma linha referenciada várias vezes vira várias instâncias). `AsNoTrackingWithIdentityResolution()` combina os dois.
- Padrão do contexto: `UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)` e `AsTracking()` onde precisar.
- Projeção para tipo que **não contém entidades** (anônimo/DTO só com valores) → nada rastreado. Se o resultado contém entidades, elas são rastreadas.
- Tipos **keyless** nunca são rastreados.

```csharp
var dtos = await context.Blogs
    .AsNoTracking()
    .Where(b => b.Rating > 3)
    .Select(b => new BlogDto(b.BlogId, b.Url))
    .ToListAsync(ct);
```

## Checklist de eficiência (doc "Efficient Querying")
1. **Índices:** o fator principal de velocidade. `StartsWith` usa índice (SQL Server); `EndsWith` não. Filtro por expressão sobre coluna (`price / 2`) não usa índice simples: coluna computada persistida. Índice acelera leitura e retarda escrita: não crie à toa; índice composto (A,B) ajuda filtros por A e por A+B, **não** só por B. Diagnostique com o plano de execução do banco.
2. **Projete só o que precisa** (`Select`): evita trazer colunas inúteis. Útil em leitura; para atualizar, precisa da entidade rastreada.
3. **Limite o resultado** (`Take(n)`) e pagine. `Skip/Take` é intuitivo mas ineficiente em páginas profundas: prefira **keyset pagination** quando navega página a página (ver doc de paginação).
4. **Cartesian explosion** ao carregar vários one-to-many com `Include` (JOINs duplicam dados): use **split queries** (`AsSplitQuery()`); cada query = um roundtrip.
5. **Eager loading** (`Include`, `ThenInclude`, filtered include) quando você já sabe o que precisa: um roundtrip. Explicit/lazy loading somente quando a necessidade depende de outra fonte.
6. **Evite lazy loading**: causa **N+1** (uma query por item). Preferir eager/explicit ou projeção (`Select(b => new { b.Url, b.Posts })`).
7. **Buffering vs streaming:** `ToList/ToArray` carregam tudo na memória; `await foreach` com `AsAsyncEnumerable()` faz streaming. Não use `ToList` se vai aplicar outro operador LINQ depois: use `AsEnumerable()`/`AsAsyncEnumerable()`. (Retry strategy e split query também fazem buffering interno.)
8. **Tracking** só quando vai gravar (ver acima).
9. **SQL bruto** (`FromSql...`, UDFs, views) é último recurso, com custo de manutenção.
10. **Sempre async** (`ToListAsync`, `SaveChangesAsync`); não misture sync/async.
11. Query operators sobre `IQueryable` são traduzidos pelo provider; operadores/métodos C# sem tradução forçam avaliação no cliente ou erro: ver doc de *client vs server evaluation* e as restrições do EF Core em `csharp-linq`.

## Padrão de atualização (com DTO)
```csharp
var todo = await db.Todos.FindAsync(id);          // tracking
if (todo is null) return TypedResults.NotFound();
todo.Name = dto.Name;                              // só campos permitidos
await db.SaveChangesAsync();
```
Concorrência: tratar `DbUpdateConcurrencyException` (tutorial oficial usa `when (!Exists(id))` → NotFound).

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Loop com acesso a navegação (lazy) → N+1 | Alta |
| 2 | Query de leitura sem `AsNoTracking` | Média |
| 3 | Entidade inteira carregada para usar 1–2 campos | Média |
| 4 | Lista sem `Take`/paginação em endpoint público | Alta |
| 5 | `ToList()` seguido de `.Where(...)` | Média |
| 6 | Vários `Include` de coleção sem split query em tabelas grandes | Média |
| 7 | `Skip` grande em paginação sequencial | Baixa/Média |
| 8 | Filtros que não usam índice (`EndsWith`, funções sobre coluna) | Média |
| 9 | Chamadas síncronas (`ToList`, `SaveChanges`) | Média |
| 10 | Mesma instância de contexto em tarefas paralelas | Alta |
| 11 | Retornar entidade na API (usar DTO) | Alta |

## Fontes oficiais
- Efficient querying: https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying
- Tracking vs no-tracking: https://learn.microsoft.com/en-us/ef/core/querying/tracking
- Related data (Include, lazy, explicit): https://learn.microsoft.com/en-us/ef/core/querying/related-data/
- Single vs split queries: https://learn.microsoft.com/en-us/ef/core/querying/single-split-queries
- Pagination: https://learn.microsoft.com/en-us/ef/core/querying/pagination
