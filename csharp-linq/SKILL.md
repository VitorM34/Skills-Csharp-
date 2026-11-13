---
name: csharp-linq
description: Implementar ou revisar consultas LINQ em C# (Where, Select, OrderBy, GroupBy, Join, SelectMany, query syntax vs method syntax, execução adiada, ToList/ToArray, IEnumerable vs IQueryable, LINQ com EF Core, LINQ com async). Use quando o usuário pedir para criar uma query LINQ, revisar se está correta, ou entender por que a query roda duas vezes / não roda. Based on official Microsoft Learn docs.
---

# C# LINQ — implementar e revisar

Regra de ouro: afirme só o que está na documentação oficial (fontes no fim). Dúvida fora deste arquivo → busque em learn.microsoft.com antes de responder.

## Conceitos que a doc destaca

1. **Query ≠ resultado.** Uma *query variable* guarda a consulta, não os dados. Nada executa até iterar (`foreach`, `MoveNext`) ou chamar um operador que devolve valor único.
2. **Execução adiada** para operadores que devolvem sequência (`Where`, `Select`, `OrderBy`...). **Execução imediata** para os que devolvem valor único (`Count`, `Sum`, `Average`, `Max`, `First`...) e para `ToList()`/`ToArray()`.
3. Iterar a mesma query variable duas vezes **reexecuta** a consulta; o resultado só é o mesmo se fonte e query não mudaram. Para congelar um resultado: `ToList()`/`ToArray()`.
4. **Query syntax vs method syntax:** equivalentes, sem diferença semântica ou de desempenho. Operadores como `Count` e `Max` só existem como método. Combinar as duas formas é válido.
5. **`IEnumerable<T>`** → a lógica do operador roda em memória (delegates). **`IQueryable<T>`** → a query vira *expression tree* e o provedor (ex.: EF Core) traduz para SQL.
6. Em `IQueryable`, árvores de expressão limitam a sintaxe C# permitida, e cada provedor (EF Core) impõe mais restrições: consulte a doc do provedor.
7. Query expression começa com `from` e termina com `select` ou `group`; no meio: `where`, `orderby`, `join`, `let`, outros `from`; `into` continua a consulta após `group`/`select`/`join`.
8. `select` também **projeta/transforma** (ex.: para um DTO ou tipo anônimo).

## Como escrever

```csharp
// Filtro + ordenação + projeção
var result = cities
    .Where(c => c.Population > 15_000_000)
    .OrderByDescending(c => c.Population)
    .Select(c => new CityDto(c.Name, c.Population))
    .ToList();                       // materializa quando precisa do resultado

// Join (duas fontes de tipos diferentes; precisa de select/group no fim)
var q = from cat in categories
        join prod in products on cat equals prod.Category
        select new { Category = cat, prod.Name };

// Várias coleções aninhadas = SelectMany (múltiplos from)
var cityQuery = from country in countries
                from city in country.Cities
                where city.Population > 10_000
                select city;
```

Regras de escrita:
- Prefira o tipo explícito ou `var`; ambos servem. `var` é **obrigatório** com tipos anônimos.
- Filtre (`Where`) o mais cedo possível, antes de ordenar/projetar.
- Evite `orderby` em uma fonte **antes** do `join` esperando manter a ordem: alguns provedores não preservam. Ordene depois.
- `let` guarda o resultado de uma expressão (ex.: `Split`) em nova variável de intervalo.
- Para a doc, `IEnumerable<T>`: valor único → `Count()/Max()` etc.; entre parênteses `(from ... select ...).Count()` ou variável intermediária.

## LINQ + async (armadilha documentada)
`userIds.Select(id => GetUserAsync(id))` é execução adiada: as tasks só iniciam ao enumerar. Sempre materialize:
- `ToArray()` quando for processar tudo junto (`await Task.WhenAll(...)`).
- `ToList()` quando precisar remover itens (padrão `Task.WhenAny` + `Remove`).
A doc manda ter cautela ao misturar LINQ com código assíncrono por causa da execução adiada (as chamadas só acontecem ao enumerar). Sobre bloquear em async (`.Result`/`.Wait()`), ver `csharp-async-await`.

## Checklist de revisão

| # | Verificar | Problema |
|---|---|---|
| 1 | Query variable enumerada várias vezes sem `ToList/ToArray` | Reexecuta a consulta (custo e resultados diferentes se a fonte mudou). |
| 2 | `Select` com chamada async sem materializar | Tasks não iniciam / iniciam tarde. |
| 3 | `Count()` só para saber se existe algum elemento | `Count` precisa **iterar** os resultados para contar; para "existe/todos satisfazem" a doc oferece os operadores de quantificador `Any`, `All`, `Contains` (Quantifier operations). |
| 4 | LINQ sobre `IQueryable` (EF Core) com método C# sem tradução | Erro de tradução ou avaliação no cliente; checar a doc de EF Core. |
| 5 | Materializar (`ToList`) antes de filtrar em `IQueryable` | Traz tudo do banco para memória. Filtre antes de materializar. |
| 6 | `join` + `orderby` na fonte antes do join | Ordem pode não ser preservada. |
| 7 | Query syntax e method syntax misturadas sem necessidade | Só estilo; manter o mais legível. |
| 8 | Query expression sem `select`/`group` final | Não compila. |
| 9 | Projetar entidade inteira quando só precisa de campos | Use `select` para DTO (ver `dotnet-dto-review`). |

## Formato da resposta
Achados por severidade (Alta: execução errada/leitura inteira do banco; Média: reexecução; Baixa: estilo), cada um com trecho, justificativa citando a fonte e correção.

## Fontes oficiais
- LINQ (visão geral): https://learn.microsoft.com/en-us/dotnet/csharp/linq/
- Query expression basics: https://learn.microsoft.com/en-us/dotnet/csharp/linq/get-started/query-expression-basics
- Standard query operators: https://learn.microsoft.com/en-us/dotnet/csharp/linq/standard-query-operators/
- Async + LINQ: https://learn.microsoft.com/en-us/dotnet/csharp/asynchronous-programming/async-scenarios
- EF Core (consultas): https://learn.microsoft.com/en-us/ef/core/querying/
