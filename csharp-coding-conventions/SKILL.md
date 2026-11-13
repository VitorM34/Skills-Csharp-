---
name: csharp-coding-conventions
description: Verificar padrões e convenções de código C#/.NET - nomenclatura (PascalCase, camelCase, _campo, I-interface, sufixo Async, Attribute, Exception), uso de var, string interpolation, collection expressions, file-scoped namespace, using fora do namespace, LINQ style, construtores primários, layout. Use quando o usuário pedir para verificar padrões, convenções, estilo ou nomes do código. Based on official Microsoft Learn docs.
---

# Convenções de código C# — verificar padrões

Fonte: convenções da equipe `dotnet/docs`, adotadas das diretrizes do .NET Runtime/Roslyn. A própria doc diz que são **exemplos de convenções comuns, não uma lista autoritativa**, e que o compilador **não impõe** os nomes; o projeto pode adotar outras (consistência > preferência). Detalhes finos: *Framework Design Guidelines*. Antes de apontar violação, verifique se o projeto tem `.editorconfig`/analyzers próprios e **siga o que o projeto define**.

## Nomenclatura (identifier names)
| Elemento | Regra |
|---|---|
| Classe, struct, record, delegate, enum, namespace, método, propriedade, evento, membros públicos/`protected` | **PascalCase** |
| Interface | PascalCase + prefixo **`I`** (`IWorkerQueue`) |
| Parâmetro, variável local | **camelCase** |
| Campo privado/internal **não constante** | `_camelCase` |
| Campo estático privado/internal | `s_camelCase` (thread-static `t_`); não é padrão do VS nem das FDG, configurável no editorconfig |
| Constante (campo ou local, inclusive private/internal) | PascalCase |
| Atributo | termina com `Attribute` |
| Enum | substantivo singular; **plural** para `[Flags]` |
| Parâmetros de construtor primário | **camelCase** em `class`/`struct`; **PascalCase** em `record` (viram propriedades públicas) |
| Parâmetro de tipo genérico | descritivo com prefixo `T` (`TSession`); `T` sozinho se único e óbvio |
| Método assíncrono (retorna Task/ValueTask) | sufixo **`Async`** (exceto event handlers, actions, contratos de interface/base) |
| Exceção | sufixo `Exception` |
| Coleção | sufixo `Collection`/`Dictionary`; ver `csharp-collections` |
- Nomes significativos e descritivos; **clareza > brevidade**; evite abreviações e acrônimos (exceto os amplamente aceitos); evite nome de uma letra (exceto contador de loop); **sem dois `_` consecutivos**.
- Namespace descritivo em notação de domínio reverso; nome de assembly reflete o propósito.
- Records posicionais: parâmetros em PascalCase.

## Linguagem (guidelines)
- Use recursos modernos do C#; evite construções obsoletas.
- Capture só exceções que sabe tratar; tipos específicos (ver `dotnet-exception-handling`).
- LINQ para manipular coleções; async/await para I/O (ver `csharp-linq`, `csharp-async-await`).
- Palavras-chave de tipo: `string`, `int` (não `String`, `Int32`). Prefira `int` a tipos unsigned.
- **`var`** só quando o tipo é óbvio no lado direito (`new`, cast explícito, literal); não use o nome da variável para indicar tipo; não use `var` no `foreach` (tipo do elemento nem sempre óbvio); `var` no `for`; em LINQ, tipagem implícita é preferida.
- **Strings:** interpolação (`$"{a}, {b}"`) para concatenar curtas; `StringBuilder` em loops; raw string literals em vez de escapes/verbatim; interpolação baseada em expressão (não posicional).
- **Construtores:** `required` em vez de construtor para forçar inicialização; primary constructor.
- **Coleções:** collection expressions `string[] v = ["a", "b"];`.
- **Delegates:** `Func<>`/`Action<>` em vez de declarar tipos; sintaxe concisa.
- **`using`:** use a declaração `using var x = ...;`; `using` diretives **fora** do namespace; namespace **file-scoped** (`namespace Foo;`).
- **Operadores:** `&&`/`||` em vez de `&`/`|` em comparações.
- **`new`:** forma concisa (`var x = new T();` ou `T x = new();`); inicializadores de objeto.
- **Estáticos:** chame por `NomeDaClasse.Membro`.
- **Eventos:** lambda para handler que não será removido.
- **LINQ (estilo):** nomes significativos nas query variables; propriedades de tipo anônimo em PascalCase; renomear propriedades ambíguas (`CustomerName`/`DistributorName`); `where` antes dos outros clauses; vários `from` em vez de `join` para coleções internas; alinhar clauses sob o `from`.

## Layout
4 espaços (sem tabs), chaves estilo **Allman** (cada chave em linha própria), uma instrução/declaração por linha, linha em branco entre métodos/propriedades, parênteses para deixar cláusulas claras, quebra de linha **antes** de operadores binários. Comentários: `//` curtos em linha própria, iniciam com maiúscula e terminam com ponto; XML doc (`///`) para membros públicos; evite `/* */` longos.

## Ferramentas
`.editorconfig` + code analysis (naming rules, style rules) para impor; o `.editorconfig` do `dotnet/docs` serve de ponto de partida. Segurança: *Secure coding guidelines*.

## Formato da resposta
Liste violações por arquivo:linha (Nomenclatura / Linguagem / Layout), regra citada, correção sugerida. **Não** renomeie API pública sem avisar (breaking change) e **não** imponha convenção contra o `.editorconfig` do projeto.

## Fontes oficiais
- Identifier names: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/identifier-names
- Coding conventions: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions
- Framework Design Guidelines: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/
- Naming rules (editorconfig): https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/naming-rules
