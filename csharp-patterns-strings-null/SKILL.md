---
name: csharp-patterns-strings-null
description: Implementar e revisar pattern matching, strings e null-safety em C# - is/switch expression/when, exaustividade, property/relational/list patterns, is null, strings (imutabilidade, interpolação, raw string literals, SQL injection), operadores ?. ?? ??= (incluindo C# 14), nullable value types (int?), null-conditional assignment. Use quando o usuário pedir switch expressions, tratamento de strings, ou revisar null checks. Based on official Microsoft Learn docs (C# fundamentals).
---

# Pattern matching, strings e null-safety em C#

Só afirmar o que a doc oficial diz (fontes no fim). Nullable reference types: `csharp-nullable-references`. Estilo/convenções de string: `csharp-coding-conventions`.

## Pattern matching
- **`is`** testa uma condição e **atribui** a variável (definite assignment): `if (x is Express e) { e.TrackingCode ... }` sem cast separado. Use **`is null` / `is not null`** (não chamam `==`/`!=` sobrescritos).
- **`switch` expression:** a expressão antes do `switch` é a **entrada**; cada **arm** tem o padrão antes de `=>` e o resultado depois; o compilador escolhe o **primeiro arm, em ordem textual**, cujo padrão casa e cujo guard **`when`** (opcional) é verdadeiro. Um arm **subsumido** (todo valor que casaria já foi coberto por arm anterior sem guard) é **erro de compilação**. O arm descarte `_` deve vir **por último**. A expressão é **exaustiva** se os arms cobrem toda entrada; o compilador **avisa** quando detecta valor não tratado (não prova todos os casos).
- Padrões: **tipo/declaração/constante/var**, **property** (`StandardDelivery { Days: <= 2 }`), **posicional**, **relacional e lógicos** (`and`, `or`, `not`, `<=`), e **list patterns**.
- **List/slice patterns:** descrevem a **forma** de uma sequência (contagem + padrões por posição); exigem tipo com `Length`/`Count` e indexador (arrays, `List<T>`, strings, spans). `[ "Name", "Score" ]` casa exatamente dois elementos; um slice `..` permite elementos restantes. Para examinar um número arbitrário de elementos, use loop/LINQ (list pattern não itera todos).
- Escolha `switch` statement × expression conforme precise de ações ou de um valor.
- **Deconstruct** e **discards** (`_`) fazem parte da família de recursos (ver páginas).

## Strings
- `string` (palavra-chave, prefira) = `System.String`: **imutável**, UTF-16; métodos como `Replace`, `Trim`, `Substring` retornam **nova** string.
- **Literais:** regulares (poucos escapes), verbatim `@"..."` (a visão geral de strings o cita para barras invertidas/caminhos, mas a página de raw strings diz para usá-lo **só em código existente**), **raw string literals `"""..."""` (preferidos** para texto com aspas/barras/várias linhas: JSON, SQL, XML, regex, caminhos). Delimitador ≥ 3 aspas, fechamento com o mesmo número; margem definida pelo **delimitador de fechamento**; raw de linha única não pode ser vazia nem começar com aspas. Raw interpoladas: `$"""..."""`.
- **Interpolação** `$"{x}"` é a forma recomendada de compor strings: `null` vira string vazia; formato `{x:F2}`, alinhamento `{x,-10}`; chaves literais por escape; **usa `CultureInfo.CurrentCulture`** (para saída determinística passe cultura explícita via `DefaultInterpolatedStringHandler`); strings interpoladas **constantes** só se todas as expressões forem constantes. Para caminhos com `\` prefira raw interpolada a `$@"..."`.
- ⚠ **Raw string deixa SQL legível, não seguro**: **nunca** concatene/interpole valores do usuário em comandos SQL (injeção). Use comandos parametrizados (`DbCommand.CreateParameter`, EF Core raw SQL parametrizado, Dapper).
- Em loops grandes use `StringBuilder` (ver `csharp-coding-conventions`). Igualdade, indexação e operações comuns: ver páginas de strings (culturas: *Performing culture-insensitive string operations*).

## Null-safety (operadores)
| Operador | Uso |
|---|---|
| `?.` / `?[]` | acessa membro/indexador **só se não nulo**; senão a expressão inteira é `null` (encadeável) |
| `??` | valor da esquerda se não nulo, senão da direita; **associativo à direita** (`a ?? b ?? c`) |
| `??=` | atribui só se a variável é `null` (lazy init); o lado direito só é avaliado se for `null` |
| `?.` como alvo de atribuição (**C# 14**) | `obj?.Prop = valor` executa só se `obj` não nulo; o lado direito só é avaliado se `obj` não for nulo |
| `is null` / `is not null` | preferidos a `== null` (operador pode ser sobrecarregado) |
- **Disparo de evento/delegate**: `handler?.Invoke(...)` é thread-safe (avalia uma vez).
- **Nullable value types** (`int?`): o padrão é `null`; verifique e extraia com **type pattern** `if (temperature is int degrees)` (evita `Value` fora do check, que lança `InvalidOperationException`); fallback com `??` ou `GetValueOrDefault`; **`null` propaga em aritmética**: extraia o valor antes de calcular.
- Combine: `?.` para atravessar a cadeia + `??` para o padrão.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Cadeia de `if/else if` com `is`/casts → `switch` expression exaustiva com `_` final |
| 2 | Arm após o descarte/subsumido; falta de arm para tipo novo (aviso ignorado) |
| 3 | `== null` em tipo com `==` sobrecarregado |
| 4 | Concatenação em loop; formatação sem cultura onde importa (serialização, logs de máquina) |
| 5 | SQL montado com interpolação/concatenação de entrada do usuário |
| 6 | `Nullable<T>.Value` sem checagem; `GetValueOrDefault` mascarando ausência |
| 7 | `if (x != null) x.Foo()` extenso onde `?.`/`??` serve |
| 8 | Verbatim `@""` em código novo com aspas/linhas múltiplas (usar raw) |
| 9 | list patterns usados para decisões que exigem percorrer a sequência toda |

## Fontes oficiais
- Pattern matching: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/patterns/pattern-matching
- List patterns: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/patterns/list-patterns
- Strings: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/strings/
- String interpolation: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/strings/interpolation
- Raw string literals: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/strings/raw-string-literals
- Null operators: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/null-safety/null-operators
- Nullable value types: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/null-safety/nullable-value-types
