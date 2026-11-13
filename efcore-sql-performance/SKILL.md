---
name: efcore-sql-performance
description: SQL bruto, avaliação no cliente, paginação e desempenho avançado no EF Core - FromSql/FromSqlInterpolated/FromSqlRaw, SqlQuery, injeção de SQL, client vs server evaluation, offset vs keyset pagination, DbContext pooling, connection pooling, batching, modelagem para desempenho (desnormalização, colunas computadas, views materializadas). Use quando o usuário pedir consulta SQL no EF, otimização avançada, paginação eficiente ou revisar risco de SQL injection. Based on official Microsoft Learn docs (EF Core).
---

# EF Core — SQL, client evaluation, paginação e desempenho avançado

Só afirmar o que a doc oficial diz (fontes no fim). Consultas básicas/tracking/N+1: `efcore-querying`. Update em massa: `efcore-saving-concurrency`.

## SQL queries
- Use SQL quando o LINQ **não expressa** a consulta ou gera SQL ineficiente; pode retornar **entidades** ou **tipos keyless**.
- **`FromSql`** (EF 7+; antes `FromSqlInterpolated`) com **interpolação parametrizada**: `db.Blogs.FromSql($"SELECT * FROM Blogs WHERE Name = {name}")`: **os valores viram parâmetros SQL** (seguro). **`FromSqlInterpolated`** também é seguro. **`FromSqlRaw` pode ser vulnerável a SQL injection se mal usado**; a doc alerta: ao introduzir valores do usuário, **nunca** concatene/interpole strings no SQL cru.
- `FromSql` só pode ser usado **diretamente sobre um `DbSet`** (não sobre qualquer query LINQ); depois dele pode-se **compor com LINQ** (o EF trata o SQL como **subconsulta**); o SQL precisa ser **composável** (em geral começa com `SELECT` e não termina com `;`/`ORDER BY` no nível externo etc.: veja a doc).
- **Stored procedures:** parâmetros devem casar exatamente (ordem, tipos, facets); use parâmetros nomeados. **Nomes de coluna não podem ser parametrizados.** Aceitar nome de coluna do usuário pode escolher coluna **sem índice** (query lenta, sobrecarga) ou **com dados que não deveriam ser expostos**; salvo cenários realmente dinâmicos, é melhor ter **duas queries** para dois nomes. Se mesmo assim precisar de SQL dinâmico, use `FromSqlRaw` e **é sua responsabilidade garantir que a string é segura**: sanitize (detectar `;`, comentários e outras construções SQL e **escapar ou rejeitar**) e continue **parametrizando os valores**.
- Uso do SQL bruto é **último recurso** (custo de manutenção).

## Client vs server evaluation
- O EF avalia a query **no servidor o máximo possível**; partes são convertidas em **parâmetros** avaliados no cliente; há suporte a **client evaluation na projeção de nível superior** (método C# na cláusula `Select` final).
- Filtro (`Where`) com método C# que não pode ser aplicado no banco: o EF **bloqueia a avaliação no cliente e lança exceção em runtime** (para não trazer tudo para a memória); para optar explicitamente por avaliar no cliente use `AsEnumerable()`/`ToList()` (`AsAsyncEnumerable`/`ToListAsync`): `AsEnumerable` faz **streaming**; `ToList` faz **buffering** (mais memória; melhor se for enumerar várias vezes).
- ⚠ **Possível vazamento de memória** com client evaluation: o EF **cacheia o plano compilado**; delegates com constantes que não viram parâmetro podem reter objetos. Use uma **variável local** (vira parâmetro) em vez de constantes/instâncias capturadas.
- Comparações com `null`: ver "Null comparisons". Funções de banco: `EF.Functions` e *user-defined function mapping*.

## Paginação
- **Sempre use ordenação totalmente única** (ex.: data **+ ID**); senão linhas podem ser puladas/duplicadas entre páginas.
- **Offset** (`Skip/Take`): simples e permite acesso aleatório a páginas, mas o banco **ainda processa as linhas puladas** (custo cresce com o offset) e resultados podem se mover se dados mudam.
- **Keyset (seek)** — **alternativa recomendada**: lembre os valores da **última linha** e use `WHERE` (ex.: `Id > lastId`); eficiente com índice; serve a navegação **próxima/anterior**, **não** a acesso aleatório. Com várias chaves de ordenação, combine-as (data + ID). Dê atenção a **índices** nas colunas de paginação.

## DbContext e conexões
- **DbContext pooling** (`AddDbContextPool`): reusa instâncias para reduzir o overhead de montar serviços internos (relevante em alto desempenho; `DbContext` é leve em geral). **Efetivamente trata o contexto como singleton**: cuidado com **estado que muda entre requisições** (ex.: tenant ID, `OnConfiguring`); trate o estado por requisição com cuidado (**segurança**).
- **Connection pooling** é do **driver ADO.NET**, **ortogonal** ao pooling de DbContext (o EF não o implementa).
- **Batching** de comandos no `SaveChanges` (ver `efcore-saving-concurrency`).

## Modelando para desempenho
**Desnormalização/cache** (dados redundantes para evitar joins, ex.: nota média do blog): mantenha o valor em dia por **colunas computadas armazenadas**, atualização via regular API com **interceptors/eventos de `SaveChanges`** (mais roundtrips) ou **views materializadas/indexadas**; defina exatamente quando recalcular. Aceitável que o dado em cache atrase um pouco.
Outras páginas: *Performance diagnosis*, *compiled queries/Native AOT e queries pré-compiladas* (consultar antes de detalhar).

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | `FromSqlRaw` com concatenação/interpolação de entrada do usuário | **Alta** |
| 2 | SQL dinâmico com nome de coluna/tabela vindo do usuário sem sanitização/rejeição | Alta |
| 3 | Método C# em `Where` forçando client evaluation com `ToList()` antes | Alta |
| 4 | Constantes/instâncias capturadas em query client-evaluated (retenção de memória) | Média |
| 5 | Paginação por offset profundo onde keyset serve; ordenação não única | Média |
| 6 | Paginação sem índice nas colunas de ordenação | Média |
| 7 | `AddDbContextPool` com estado por requisição no contexto | Alta |
| 8 | Agregados caros recalculados a cada leitura sem estratégia de cache/denormalização | Baixa |
| 9 | SQL bruto onde LINQ resolve | Baixa |

## Fontes oficiais
- SQL queries: https://learn.microsoft.com/en-us/ef/core/querying/sql-queries
- Client vs server evaluation: https://learn.microsoft.com/en-us/ef/core/querying/client-eval
- Pagination: https://learn.microsoft.com/en-us/ef/core/querying/pagination
- Advanced performance topics: https://learn.microsoft.com/en-us/ef/core/performance/advanced-performance-topics
- Modeling for performance: https://learn.microsoft.com/en-us/ef/core/performance/modeling-for-performance
- Efficient updating: https://learn.microsoft.com/en-us/ef/core/performance/efficient-updating
- Performance diagnosis: https://learn.microsoft.com/en-us/ef/core/performance/performance-diagnosis
