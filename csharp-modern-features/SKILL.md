---
name: csharp-modern-features
description: Usar e revisar recursos modernos do C# 12, 13 e 14 (.NET 10) - primary constructors, collection expressions e spread, params collections, System.Threading.Lock, keyword field, extension members, null-conditional assignment, implicit span conversions, partial members, lambda com default/modifiers; e o que é preview do C# 15. Use quando o usuário pedir para modernizar código, escolher a versão de linguagem ou verificar se um recurso existe na versão do projeto. Based on official Microsoft Learn docs ("What's new in C#").
---

# C# 12, 13 e 14 — recursos modernos

Só afirmar o que a doc oficial diz (fontes no fim). **C# 14 acompanha o .NET 10** (versão de linguagem padrão do SDK); C# 13 → .NET 9; C# 12 → .NET 8. **C# 15 aparece na doc** (união de tipos, hierarquias `closed`, extension indexers, labeled break/continue, collection expression arguments; "memory safety" é preview de fato) e é o padrão de projetos `net11.0` no SDK .NET 11 (a doc diz isso; **que o SDK .NET 11 seja prerelease não está escrito nas páginas lidas** — só a "memory safety" é marcada *preview*, e exige `LangVersion` preview): **não use em projeto .NET 10 de produção**. A doc de versão de linguagem diz que o padrão acompanha o TFM, que usar versão mais nova que a do TFM "não é suportado" e que **não se deve definir `LangVersion` como `latest`**. Confira a versão de linguagem/target framework do projeto antes de sugerir qualquer recurso. Convenções: `csharp-coding-conventions`.

## C# 12
- **Primary constructors em qualquer `class`/`struct`** (não só records): os parâmetros ficam no escopo de todo o corpo; **todo construtor explícito deve chamar o primary com `this(...)`**; o compilador **não gera propriedades** (só em `record`) — **confirmado** no tutorial, assim como "o compilador cria armazenamento só quando o parâmetro é usado no corpo de um membro" e "todo outro construtor deve chamar o primary via `this()`". **Não reconfirmados** (não estão no tutorial lido): em **`class`** o construtor sem parâmetros implícito deixa de ser emitido (e em `struct` continua), e o alvo de atributo `[method: ...]`. Convenção de nomes: camelCase em class/struct, PascalCase em record. Os parâmetros ficam em escopo em todo o corpo. Típico em DI: `class Worker(ILogger<Worker> logger)`.
- **Collection expressions** `[1, 2, 3]` para arrays, `Span<T>`/`ReadOnlySpan<T>`, tipos com método *create* que recebe `ReadOnlySpan<T>`, `List<T>`/tipos com collection initializer e interfaces (`IEnumerable<T>`, `IReadOnlyList<T>`, `IList<T>`...); **spread** `[.. a, .. b]` (o operando precisa ser enumerável por `foreach`); **não** inicializam *inline arrays*; criam a coleção sempre com todos os elementos. Preferido pela convenção oficial.
- **`ref readonly` parameters**, **default lambda parameters**, **alias any type** (`using Point = (int, int);`), **inline arrays**, `[Experimental]`; **interceptors** "debutaram como preview experimental no C# 12" e a doc diz que o preview não era recomendado para produção e estava sujeito a mudanças — **a página fala no passado, então confirme o status atual** antes de usar.

## C# 13 (.NET 9)
- **`params` collections**: `params` aceita tipos de coleção além de arrays (ex.: `params ReadOnlySpan<T>`/`IEnumerable<T>`).
- **`System.Threading.Lock`**: nova primitiva de sincronização; `lock (_lock)` usa `Lock.EnterScope()` (ref struct com `Dispose`) se o alvo é `Lock`; se convertido para outro tipo volta a `Monitor`.
- Nova escape `\e`; method group natural type; **índice implícito `^`** em object initializers; `ref`/`unsafe` em iterators e async; `allows ref struct` e interfaces em ref struct; partial properties/indexers; overload resolution priority.
- **`field` keyword** (preview em 13, estável em 14).

## C# 14 (.NET 10)
- **Extension members** (`extension<TSource>(IEnumerable<TSource> source) { public bool IsEmpty => !source.Any(); ... }`): permite **extension properties** e extensões **estáticas** (membros que parecem estáticos do tipo, inclusive operadores definidos pelo usuário).
- **`field`**: corpo de acessor sem declarar campo de apoio; o compilador sintetiza.
```csharp
public string Message { get; set => field = value ?? throw new ArgumentNullException(nameof(value)); }
public SqlConnection Connection { get => field ??= new SqlConnection("..."); }   // lazy init
```
  (Atenção a variáveis/membros chamados `field` existentes: ver breaking changes.)
- **Null-conditional assignment**: `customer?.Order = value;`.
- **Implicit span conversions** (suporte de primeira classe a `Span<T>`/`ReadOnlySpan<T>`), **`nameof` com tipos genéricos abertos**, **modificadores em parâmetros de lambda sem tipo** (`(text, out result) => ...`), **partial events e constructors**, **user-defined compound assignment operators**, novas diretivas para file-based apps.

## Como aplicar ao revisar
1. Use recursos modernos **quando a versão do projeto permite** e **quando melhoram clareza** (a doc recomenda usar recursos modernos e evitar construções obsoletas, mas ensina *quando* cada um serve).
2. Sugestões típicas: `new List<string> { "a" }` → `["a"]`; construtor que só copia parâmetros para campos → primary constructor; propriedade com campo privado só para validar → `field`; `lock (new object())` → `Lock`.
3. Cuidado com **breaking changes** e com **atualizações de linguagem**: veja *breaking changes* e *version update considerations* antes de subir a versão.
4. `LangVersion`/`TargetFramework` no `.csproj` definem o que compila (ver *C# language versioning*).

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Recurso de C# 14/15 usado em projeto que alveja .NET 8/9 |
| 2 | Primary constructor em classe com campos/estado que precisa de `readonly` explícito |
| 3 | `field` colidindo com membro existente chamado `field` |
| 4 | Lock em `object` onde `System.Threading.Lock` (.NET 9+) é melhor |
| 5 | Collection expression onde o tipo-alvo não é suportado/semântica difere (verificar o tipo) |
| 6 | Recursos preview (C# 15) em código de produção |

## Fontes oficiais
- What's new in C# 12: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-12
- What's new in C# 13: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-13
- What's new in C# 14: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-14
- What's new in C# 15 (preview): https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-15
- Histórico de versões: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-version-history
- Breaking changes: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/breaking-changes
- Versão de linguagem: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/configure-language-version
