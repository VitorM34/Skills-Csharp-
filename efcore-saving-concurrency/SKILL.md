---
name: efcore-saving-concurrency
description: Implementar e revisar gravação de dados no EF Core - SaveChanges (transacional), entidades desconectadas (Update/Attach/TrackGraph), concorrência otimista (tokens, rowversion, DbUpdateConcurrencyException), transações (AutoTransactionBehavior, savepoints, BeginTransaction, TransactionScope), ExecuteUpdate/ExecuteDelete. Use quando o usuário pedir para atualizar entidades vindas da API, tratar conflitos de concorrência, controlar transações ou fazer updates/deletes em massa. Based on official Microsoft Learn docs (EF Core).
---

# EF Core — salvar, concorrência, transações e operações em massa

Só afirmar o que a doc oficial diz (fontes no fim). Padrão de update com DTO: `aspnet-http-endpoints`, `dotnet-dto-review`. Leitura/consulta: `efcore-querying`.

## SaveChanges
- Em **provedores que suportam transações, todas as mudanças de uma chamada a `SaveChanges(Async)` rodam em **uma transação**: ou tudo é aplicado ou nada. Para a maioria das apps basta; só controle transações manualmente se o requisito exigir.
- O EF detecta mudanças nas entidades **rastreadas** e as grava (adicionar/atualizar/remover; vários em lote). **Sempre use `SaveChangesAsync`** (ver `efcore-dbcontext-connection`).
- **Batching:** quantidade por roundtrip depende do provedor; no SQL Server o batching é menos eficiente com < 4 comandos e perde benefício acima de ~40; padrão **até 42 comandos por lote**.

## Entidades desconectadas (web: consulta numa requisição, salva em outra)
- O EF só rastreia **uma instância por chave primária**. **Melhor prática:** contexto de **vida curta por unit of work**. A segunda instância do contexto precisa saber se a entidade é **nova (insert) ou existente (update)**.
- Chave **auto-gerada**: chave não definida (padrão CLR) ⇒ nova; definida ⇒ existente. As chaves são setadas assim que a entidade é rastreada (mesmo em `Added`), então use esse teste **antes** de rastrear. `Update` normalmente marca para **update**, mas se a chave auto-gerada não foi definida marca para **insert**. Sem chave gerada, a app decide.
- `SetValues` marca como modificadas **só as propriedades diferentes** (envia UPDATE apenas das colunas alteradas; nenhum UPDATE se nada mudou). Grafos: `TrackGraph`; duplicatas no grafo precisam ser consolidadas (identity resolution).
- **Padrão seguro para APIs:** carregue a entidade pelo id, copie **só os campos permitidos do DTO** e `SaveChangesAsync` (evita overposting; ver `dotnet-dto-review`).

## Concorrência otimista
- O EF implementa **concorrência otimista**: sem locks; a modificação **falha ao salvar** se os dados mudaram desde a consulta. O `UPDATE`/`DELETE` inclui o token no `WHERE`; zero linhas afetadas ⇒ **`DbUpdateConcurrencyException`** (também em `DELETE` de linha modificada; normalmente **não** em inserts: conflito de chave vira erro específico do provedor).
- **Token gerado pelo banco:** ex. `rowversion` (SQL Server; Data Annotation `[Timestamp]` ou `IsRowVersion()`); o suporte varia por banco (SQLite não tem). **Token gerenciado pela aplicação:** `[ConcurrencyCheck]`/`IsConcurrencyToken()` em propriedade que você mesmo atualiza (ex.: um `Guid` novo a cada gravação; pode usar interceptor de `SaveChanges`); permite controlar quando regenerar para evitar conflitos desnecessários.
- Resolver o conflito: capturar a exceção e decidir (reler valores do banco, mesclar, sobrescrever). Em APIs: normalmente responder **409/412** ou recarregar e repetir (tutorial oficial trata `DbUpdateConcurrencyException` com `NotFound` quando a linha sumiu).

## Transações
- **Padrão:** `AutoTransactionBehavior.WhenNeeded` (EF cria transação só quando precisa); `Always` (sempre, pode adicionar roundtrips); **`Never` com cautela** (falha no meio pode deixar mudanças parciais).
- **Controle explícito:** `await using var tx = await context.Database.BeginTransactionAsync(); ... await tx.CommitAsync();` (rollback implícito ao descartar sem commit). **Savepoints:** se já há transação no contexto, `SaveChanges` cria um savepoint e, em erro, volta a ele.
- **Entre contextos:** compartilhar `DbConnection` **e** `DbTransaction` (só provedores relacionais); a conexão precisa poder ser fornecida externamente ao construir o contexto. **`DbTransaction` externa** (relacional). **`System.Transactions`/`TransactionScope`**: com APIs async use **`TransactionScopeAsyncFlowOption.Enabled`**.

## ExecuteUpdate / ExecuteDelete (EF 7+)
- Executam **SQL `UPDATE`/`DELETE` diretamente**, imediatamente, sem carregar entidades: `await db.Blogs.Where(b => b.Rating < 3).ExecuteDeleteAsync();` e `ExecuteUpdateAsync(s => s.SetProperty(b => b.IsVisible, false))` (várias propriedades; referenciar valor atual; navegações limitadas). Muito mais eficientes que carregar tudo e `SaveChanges` (que faz um UPDATE por entidade).
- **Não** conhecem o change tracker: **evite misturar** modificações rastreadas (`SaveChanges`) com `ExecuteUpdate/Delete`; **não** iniciam transação implícita; **não** aplicam concorrência automática (use `Where` com o token e confira o número de linhas afetadas; zero = conflito).
- Limitações: só update/delete (insert via `Add` + `SaveChanges`); várias chamadas não se acumulam.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Entidade recebida da API anexada direto (`Update(entidade)`/`State = Modified`) em vez de DTO | Alta |
| 2 | Contexto de vida longa reaproveitando entidades rastreadas | Média |
| 3 | Entidade crítica sem token de concorrência; `DbUpdateConcurrencyException` sem tratamento | Alta |
| 4 | Loop de `SaveChanges` por item em vez de lote (ou sem `ExecuteUpdate/Delete` quando cabe) | Média |
| 5 | Mistura de `ExecuteUpdate` com entidades rastreadas no mesmo fluxo | Média |
| 6 | `AutoTransactionBehavior.Never` sem necessidade | Alta |
| 7 | `TransactionScope` sem `TransactionScopeAsyncFlowOption.Enabled` em código async | Alta |
| 8 | Transação aberta cobrindo chamadas HTTP/longas | Média |
| 9 | `ExecuteDelete`/`ExecuteUpdate` onde o change tracker já tem entidades carregadas (ficam desatualizadas: a doc diz que operam à margem do tracker) | Média |

## Fontes oficiais
- Basic SaveChanges: https://learn.microsoft.com/en-us/ef/core/saving/basic
- Disconnected entities: https://learn.microsoft.com/en-us/ef/core/saving/disconnected-entities
- Concurrency conflicts: https://learn.microsoft.com/en-us/ef/core/saving/concurrency
- Transactions: https://learn.microsoft.com/en-us/ef/core/saving/transactions
- ExecuteUpdate/ExecuteDelete: https://learn.microsoft.com/en-us/ef/core/saving/execute-insert-update-delete
- Efficient updating: https://learn.microsoft.com/en-us/ef/core/performance/efficient-updating
